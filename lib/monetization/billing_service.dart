import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'monetization_ids.dart';
import 'monetization_store.dart';

/// Remove Ads ($2.99, one-time, non-consumable) purchase flow.
///
/// Granting the entitlement is idempotent by construction:
/// [MonetizationStore.grantRemoveAds] only ever sets one persisted boolean
/// to true, so it is safe to call every time the purchase stream delivers
/// this product -- on the original purchase, on a redelivery after a
/// dropped connection, and on every `restorePurchases()` call -- without
/// ever granting anything extra or double-charging (Google Play itself
/// refuses to sell an already-owned non-consumable again).
class BillingService {
  final InAppPurchase _iap;
  final MonetizationStore store;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _removeAdsProduct;
  final _entitlementController = StreamController<bool>.broadcast();

  BillingService({InAppPurchase? iap, MonetizationStore? store})
    : _iap = iap ?? InAppPurchase.instance,
      store = store ?? MonetizationStore();

  /// Fires `true` each time the Remove Ads entitlement is (re)confirmed.
  /// UI should also read [MonetizationStore.hasRemoveAds] directly at
  /// startup; this stream is for live updates while the app is running.
  Stream<bool> get entitlementGranted => _entitlementController.stream;

  String get removeAdsPriceLabel =>
      _removeAdsProduct?.price ?? MonetizationIds.removeAdsFallbackPriceLabel;

  Future<void> start() async {
    if (!await _iap.isAvailable()) return;
    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (Object e) {
        if (kDebugMode) debugPrint('Purchase stream error: $e');
      },
    );
    final response = await _iap.queryProductDetails({
      MonetizationIds.removeAdsProductId,
    });
    if (response.notFoundIDs.isNotEmpty && kDebugMode) {
      debugPrint(
        'Product(s) not found in the store: ${response.notFoundIDs} -- '
        'create them in Play Console before release.',
      );
    }
    if (response.productDetails.isNotEmpty) {
      _removeAdsProduct = response.productDetails.first;
    }
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != MonetizationIds.removeAdsProductId) continue;
      switch (purchase.status) {
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

  Future<void> restorePurchases() => _iap.restorePurchases();

  void dispose() {
    _sub?.cancel();
    _entitlementController.close();
  }
}
