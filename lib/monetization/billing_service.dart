import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'monetization_ids.dart';
import 'monetization_store.dart';

/// Whether an Android consume attempt actually succeeded, and (if not) a
/// ready-to-log diagnostic message -- kept as a pure function of the
/// returned [BillingResultWrapper] (see [BillingService._finishConsumablePurchase])
/// so this DECISION is directly unit-testable with a plain constructed
/// result, no real Play Billing platform channel needed (mirroring
/// packages/billing_service's own established "separate the decision
/// from the plumbing" pattern for exactly this reason).
class ConsumeCheck {
  final bool succeeded;
  final String? diagnosticMessage;
  const ConsumeCheck({required this.succeeded, this.diagnosticMessage});
}

ConsumeCheck checkConsumeResult(String productId, BillingResultWrapper result) {
  if (result.responseCode == BillingResponse.ok) {
    return const ConsumeCheck(succeeded: true);
  }
  return ConsumeCheck(
    succeeded: false,
    diagnosticMessage:
        'Consume failed for $productId '
        '(${result.responseCode}, ${result.debugMessage}) -- the gem/coin '
        'credit is already durably recorded; Play still shows this '
        'purchase as owned and it will be retried automatically on the '
        'next restore (app startup/resume).',
  );
}

/// Remove Ads ($2.99, one-time, non-consumable) purchase flow, plus the
/// three consumable gem packs (monetization update pass 2026-09-27).
///
/// Granting the Remove Ads entitlement is idempotent by construction:
/// [MonetizationStore.grantRemoveAds] only ever sets one persisted boolean
/// to true, so it is safe to call every time the purchase stream delivers
/// this product -- on the original purchase, on a redelivery after a
/// dropped connection, and on every `restorePurchases()` call -- without
/// ever granting anything extra or double-charging (Google Play itself
/// refuses to sell an already-owned non-consumable again).
///
/// Gem packs are CONSUMABLE, which needs a different safety story -- see
/// [_onPurchaseUpdate] and MonetizationStore's own "gem purchase
/// durability" section for the exact ordering that prevents losing or
/// double-crediting a real-money gem purchase.
class BillingService {
  final InAppPurchase _iap;
  final MonetizationStore store;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _removeAdsProduct;
  final Map<String, ProductDetails> _gemProducts = {};
  ProductDetails? _coinsProduct;
  final _entitlementController = StreamController<bool>.broadcast();

  /// Fires the number of gems just durably credited, once per completed
  /// purchase (or once per leftover pending amount recovered at [start]
  /// from a prior session that was killed before draining it -- see
  /// MonetizationStore.pendingGems). The listener (CommandScreen) is
  /// responsible for adding this to the live voyage's gem balance, saving
  /// it, and then calling [store]'s `clearPendingGems` for the same
  /// amount -- see that method's own doc comment for why THAT ordering is
  /// what makes this safe across a crash.
  final _gemsCreditedController = StreamController<int>.broadcast();

  /// Coin-purchase equivalent of [gemsCredited] -- same contract, same
  /// crash-safety story, MonetizationStore.pendingCoins/clearPendingCoins
  /// in place of the gem equivalents.
  final _coinsCreditedController = StreamController<int>.broadcast();

  BillingService({InAppPurchase? iap, MonetizationStore? store})
    : _iap = iap ?? InAppPurchase.instance,
      store = store ?? MonetizationStore();

  /// Fires `true` each time the Remove Ads entitlement is (re)confirmed.
  /// UI should also read [MonetizationStore.hasRemoveAds] directly at
  /// startup; this stream is for live updates while the app is running.
  Stream<bool> get entitlementGranted => _entitlementController.stream;

  Stream<int> get gemsCredited => _gemsCreditedController.stream;
  Stream<int> get coinsCredited => _coinsCreditedController.stream;

  /// The real, localized Play Billing price for Remove Ads, or `null` if
  /// [ProductDetails] hasn't resolved yet -- see [gemPriceLabel]'s own
  /// doc comment (BILLING AUDIT FIX) for why there is deliberately no
  /// hardcoded fallback string here any more. `null` means "not
  /// purchasable right now"; the UI must disable the buy action in that
  /// state, never show a guessed price.
  String? get removeAdsPriceLabel => _removeAdsProduct?.price;

  /// The real, localized price Play Billing reports for [productId], or
  /// `null` if [ProductDetails] hasn't resolved yet (offline at startup,
  /// store unreachable, the product not yet created in Play Console,
  /// etc.) -- BILLING AUDIT FIX: previously fell back to a hardcoded
  /// price string in that case, which let an actually-unavailable
  /// product still display (and remain tappable) as if it were a real,
  /// purchasable price. `null` now means exactly "not purchasable right
  /// now"; every call site must disable its buy action rather than
  /// substitute a guessed price. Returns `null` for an unrecognized
  /// [productId] too.
  String? gemPriceLabel(String productId) => _gemProducts[productId]?.price;

  /// The real, localized price for the 5,000-coin pack, or `null` before
  /// [ProductDetails] has resolved -- same contract as [gemPriceLabel].
  String? get coinsPriceLabel => _coinsProduct?.price;

  /// BILLING AUDIT FIX: also triggers one automatic [restorePurchases]
  /// call, so an entitlement/consumable Play already confirmed but this
  /// app never durably recorded locally (e.g. a prior session crashed
  /// between payment and the local grant+persist) is recovered on its
  /// own at startup, without the player needing to notice anything is
  /// missing. Best-effort: a failure here (e.g. no network) is
  /// swallowed -- Remove Ads' own manual "Restore" button remains
  /// available as a fallback, and this same recovery also runs again on
  /// every app resume (see CommandScreen.didChangeAppLifecycleState).
  Future<void> start() async {
    if (!await _iap.isAvailable()) return;
    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (Object e) {
        if (kDebugMode) debugPrint('Purchase stream error: $e');
      },
    );
    try {
      await restorePurchases();
    } catch (e) {
      if (kDebugMode) debugPrint('Automatic startup restore failed: $e');
    }
    final response = await _iap.queryProductDetails({
      MonetizationIds.removeAdsProductId,
      MonetizationIds.coins5000ProductId,
      ...MonetizationIds.gemProductIds,
    });
    if (response.notFoundIDs.isNotEmpty && kDebugMode) {
      debugPrint(
        'Product(s) not found in the store: ${response.notFoundIDs} -- '
        'create them in Play Console before release.',
      );
    }
    for (final product in response.productDetails) {
      if (product.id == MonetizationIds.removeAdsProductId) {
        _removeAdsProduct = product;
      } else if (product.id == MonetizationIds.coins5000ProductId) {
        _coinsProduct = product;
      } else if (MonetizationIds.gemProductFor(product.id) != null) {
        _gemProducts[product.id] = product;
      }
    }
    // Recovers gems/coins durably credited in a prior session that was
    // killed before CommandScreen ever applied them to a voyage and saved
    // (see MonetizationStore's own "gem purchase durability" section) --
    // this is the ONE other place, besides a live purchase completing,
    // that [gemsCredited]/[coinsCredited] fire.
    final leftoverPendingGems = await store.pendingGems();
    if (leftoverPendingGems > 0) {
      _gemsCreditedController.add(leftoverPendingGems);
    }
    final leftoverPendingCoins = await store.pendingCoins();
    if (leftoverPendingCoins > 0) {
      _coinsCreditedController.add(leftoverPendingCoins);
    }
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      // BILLING AUDIT FIX: each purchase is handled in its own try/catch
      // so a failure processing ONE (a persistence error, a failed
      // consume call, anything unexpected) can never abort the rest of
      // this batch -- every other purchase in [purchases] still gets
      // processed normally.
      try {
        await _handlePurchase(purchase);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Unhandled error processing purchase ${purchase.productID}: $e');
        }
      }
    }
  }

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    final gemInfo = MonetizationIds.gemProductFor(purchase.productID);
    // BILLING AUDIT FIX: never trust `purchase.status` alone for a
    // grant-worthy outcome -- `package:in_app_purchase_android`'s own
    // `restorePurchases()` unconditionally overwrites EVERY returned
    // purchase's `.status` to `PurchaseStatus.restored`, discarding
    // whatever the real underlying Android `purchaseState` actually was
    // (confirmed by reading that plugin's own source). A purchase Play's
    // own `queryPurchasesAsync` can legitimately return in
    // `PurchaseStateWrapper.pending` (a deferred/cash payment still being
    // confirmed) would otherwise be reported here as "restored" and
    // granted/credited for money that hasn't actually cleared. This
    // check is a no-op on the ordinary fresh-purchase path (the plugin
    // already derives `.status` from that same raw state there); it is
    // what makes the restore path safe.
    final status = _verifiedStatus(purchase);
    if (purchase.productID == MonetizationIds.removeAdsProductId) {
      switch (status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await store.grantRemoveAds();
          _entitlementController.add(true);
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        case PurchaseStatus.error:
          if (kDebugMode) debugPrint('Purchase error: ${purchase.error}');
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        case PurchaseStatus.canceled:
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        case PurchaseStatus.pending:
          break;
      }
      return;
    }
    if (purchase.productID == MonetizationIds.coins5000ProductId) {
      switch (status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // Same durability ordering as the gem branch below -- see
          // MonetizationStore's own doc comment.
          final purchaseKey =
              purchase.purchaseID ??
              purchase.verificationData.serverVerificationData;
          final credited = await store.creditCoinPurchaseIfNew(
            purchaseKey,
            MonetizationIds.coins5000Amount,
          );
          if (credited) {
            _coinsCreditedController.add(MonetizationIds.coins5000Amount);
          }
          await _finishConsumablePurchase(purchase);
        case PurchaseStatus.error:
          if (kDebugMode) {
            debugPrint('Coin purchase error: ${purchase.error}');
          }
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        case PurchaseStatus.canceled:
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        case PurchaseStatus.pending:
          break;
      }
      return;
    }
    if (gemInfo == null) return; // Not a product this app handles.
    switch (status) {
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        // Durability ordering (see MonetizationStore's own doc comment):
        // record the durable credit FIRST, only then consume/finish the
        // purchase with Play. If this process dies between the two, the
        // purchase is still unconsumed and Play redelivers it next
        // launch -- creditGemPurchaseIfNew sees the same purchase key
        // again and correctly no-ops the credit while retrying
        // consumption.
        final purchaseKey =
            purchase.purchaseID ??
            purchase.verificationData.serverVerificationData;
        final credited = await store.creditGemPurchaseIfNew(
          purchaseKey,
          gemInfo.totalGems,
        );
        if (credited) _gemsCreditedController.add(gemInfo.totalGems);
        await _finishConsumablePurchase(purchase);
      case PurchaseStatus.error:
        if (kDebugMode) debugPrint('Gem purchase error: ${purchase.error}');
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
      case PurchaseStatus.canceled:
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
      case PurchaseStatus.pending:
        break;
    }
  }

  /// See [_handlePurchase]'s own doc comment on why raw Android
  /// `purchaseState` is authoritative over the plugin's own (sometimes
  /// mislabeled on the restore path) `PurchaseStatus`.
  PurchaseStatus _verifiedStatus(PurchaseDetails purchase) {
    if (purchase is! GooglePlayPurchaseDetails) return purchase.status;
    final rawState = purchase.billingClientPurchase.purchaseState;
    if (rawState == PurchaseStateWrapper.purchased) return purchase.status;
    return rawState == PurchaseStateWrapper.pending
        ? PurchaseStatus.pending
        : PurchaseStatus.error;
  }

  /// Finishes a CONSUMABLE purchase with the store, deliberately NOT via
  /// the generic [InAppPurchase.completePurchase] on Android -- that call
  /// only ever ACKNOWLEDGES a purchase there (see
  /// InAppPurchaseAndroidPlatform.completePurchase), which would leave the
  /// gem pack permanently "owned" and unable to be bought again. Android
  /// consumables must be explicitly CONSUMED instead, which itself also
  /// satisfies Play's acknowledgement requirement. iOS/other platforms
  /// have no separate consume verb -- finishing the transaction via
  /// [InAppPurchase.completePurchase] is already the correct, complete
  /// step there.
  ///
  /// BILLING AUDIT FIX: the Android consume call's own result is now
  /// actually checked -- previously this awaited [consumePurchase] and
  /// discarded its returned [BillingResultWrapper] entirely, so a failed
  /// consume (network error, Play momentarily unavailable, etc.) was
  /// silently treated exactly like a success. The gem/coin credit was
  /// already durably recorded before this method is ever called (see
  /// MonetizationStore's own doc comment), so nothing is lost either
  /// way; what a failed consume actually means is the purchase stays
  /// "owned" on Play's side. The safe recovery/retry path is automatic:
  /// [start]'s own restore-on-startup (and CommandScreen's matching
  /// restore-on-resume) will redeliver that same still-unconsumed
  /// purchase, which lands back here and simply retries the consume --
  /// `creditGemPurchaseIfNew`/`creditCoinPurchaseIfNew` are idempotent,
  /// so the retry credits nothing extra.
  Future<void> _finishConsumablePurchase(PurchaseDetails purchase) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final result = await InAppPurchase.instance
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
          .consumePurchase(purchase);
      final check = checkConsumeResult(purchase.productID, result);
      if (!check.succeeded && kDebugMode) debugPrint(check.diagnosticMessage);
    } else if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  /// Starts the purchase flow. Returns immediately; the actual grant
  /// happens asynchronously through [entitlementGranted] /
  /// [_onPurchaseUpdate] once Google Play confirms the purchase, exactly
  /// once per successful payment (never on a mere UI tap).
  Future<bool> buyRemoveAds() async {
    final product = _removeAdsProduct;
    if (product == null) return false;
    return _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  /// Starts a gem-pack purchase flow. Returns immediately (false only if
  /// [productId] isn't a known, already-queried gem product -- e.g. Play
  /// Console hasn't been configured with it yet, or [start] hasn't
  /// completed); the actual gem credit happens asynchronously through
  /// [gemsCredited] once Google Play confirms the purchase (see
  /// [_onPurchaseUpdate]).
  ///
  /// `autoConsume: false` is deliberate -- see MonetizationStore's own
  /// "gem purchase durability" doc comment for why letting the plugin
  /// auto-consume would risk losing paid gems to a crash between the
  /// purchase landing and this app durably recording the credit.
  Future<bool> buyGems(String productId) async {
    final product = _gemProducts[productId];
    if (product == null) return false;
    return _iap.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
      autoConsume: false,
    );
  }

  /// Starts the 5,000-coin purchase flow. Same shape/safety as [buyGems].
  Future<bool> buyCoins() async {
    final product = _coinsProduct;
    if (product == null) return false;
    return _iap.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
      autoConsume: false,
    );
  }

  Future<void> restorePurchases() => _iap.restorePurchases();

  void dispose() {
    _sub?.cancel();
    _entitlementController.close();
    _gemsCreditedController.close();
    _coinsCreditedController.close();
  }
}
