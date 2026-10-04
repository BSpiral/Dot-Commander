import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistence for everything monetization needs to remember, kept
/// deliberately separate from `VoyageStore`'s `dot_commander.pirates.voyage.v1`
/// key: a real-money entitlement (Remove Ads) must never be affected by a
/// voyage reset/reroll, and must be checkable before a voyage even exists
/// (e.g. to decide whether to show a banner while the world loads). The
/// same separation protects the per-chest-type rewarded-ad daily
/// allowances: a debug voyage reset (or any future voyage reroll) must
/// never reset how many rewarded Common Chests today's date has already
/// granted.
///
/// All logic here is plain Dart over `SharedPreferences` -- no
/// `google_mobile_ads`/`in_app_purchase` imports -- so it is directly unit
/// testable without any ad/billing platform channel.
abstract final class MonetizationKeys {
  static const removeAds = 'dot_commander.monetization.remove_ads';
  static String rewardedDate(String key) =>
      'dot_commander.monetization.rewarded_date.$key';
  static String rewardedCount(String key) =>
      'dot_commander.monetization.rewarded_count.$key';

  // Gem/coin purchase durability (monetization update pass 2026-09-27;
  // BILLING AUDIT FIX 2026-09-27: merged from two separate keys -- a
  // pending amount counter and a credited-purchase-id list -- into ONE
  // JSON blob per currency under a single key. See
  // MonetizationStore._ConsumableLedgerState's own doc comment for why:
  // two independent keys could be left inconsistent by a persistence
  // failure that succeeds on one write and fails on the other, and
  // EITHER order of those two writes had a real failure mode (silently
  // losing the credited amount, or double-crediting on the next retry).
  // A single-key write either fully succeeds or leaves both pieces of
  // state completely unchanged -- never partially updated.
  static const gemPurchaseLedger = 'dot_commander.monetization.gem_purchase_ledger';
  static const coinPurchaseLedger = 'dot_commander.monetization.coin_purchase_ledger';
}

/// The durable state behind one currency's consumable-purchase ledger --
/// see [MonetizationKeys.gemPurchaseLedger]/[coinPurchaseLedger]'s own
/// doc comment for why [pending] and [creditedIds] are stored together
/// under one key rather than as two independent ones. A malformed or
/// missing blob (a fresh install, or a JSON-decode failure) safely
/// resolves to empty/zero rather than throwing -- there is nothing to
/// recover yet in that case, not a real error.
class _ConsumableLedgerState {
  final int pending;
  final List<String> creditedIds;
  const _ConsumableLedgerState({required this.pending, required this.creditedIds});

  static const empty = _ConsumableLedgerState(pending: 0, creditedIds: []);

  Map<String, dynamic> toJson() => {'pending': pending, 'creditedIds': creditedIds};

  static _ConsumableLedgerState fromJson(String? raw) {
    if (raw == null) return empty;
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return empty;
      final pending = map['pending'];
      final ids = map['creditedIds'];
      return _ConsumableLedgerState(
        pending: pending is int && pending >= 0 ? pending : 0,
        creditedIds: ids is List ? ids.whereType<String>().toList() : <String>[],
      );
    } on FormatException {
      return empty;
    }
  }
}

class MonetizationStore {
  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _now;
  // A tiny async mutex per counter key: each call for a given key chains
  // onto the previous call for that SAME key, so concurrent grant
  // attempts for one chest type are serialized (one at a time, in order)
  // rather than racing each other or being dropped -- while different
  // keys (different chest types) never block each other, matching the
  // "independent daily allowance per chest type" design. A plain boolean
  // "busy" guard is NOT enough here -- it would make every concurrent
  // caller except the very first one fail immediately instead of queuing,
  // which would under-grant valid rewards, not just prevent duplicates.
  final Map<String, Future<void>> _locks = {};

  MonetizationStore({
    Future<SharedPreferences> Function()? prefs,
    DateTime Function()? now,
  }) : _prefs = prefs ?? SharedPreferences.getInstance,
       _now = now ?? DateTime.now;

  // The player's own device-local calendar day, NOT UTC. Using UTC here
  // previously meant "today" could roll over up to several hours before
  // or after the player's own local midnight (e.g. a player at UTC-5
  // sees the UTC day change at 7pm local, but their own local midnight
  // doesn't register as a new "today" until 5am local) -- a real,
  // confirmed multi-hour-per-day mismatch window that can make a daily
  // allowance look "stuck" from the player's perspective even though
  // the code is deterministically correct by its own (UTC) definition.
  // Diagnosed during the time/progression repair pass; local time
  // matches what a player actually experiences as "today."
  String _today() {
    final d = _now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Whether the $2.99 Remove Ads entitlement is owned. Persisted
  /// independently of any voyage; a debug voyage reset must never clear it.
  Future<bool> hasRemoveAds() async {
    final prefs = await _prefs();
    return prefs.getBool(MonetizationKeys.removeAds) ?? false;
  }

  /// Idempotent: safe to call every time the purchase stream reports the
  /// entitlement (restore, re-delivery after a dropped connection, etc.)
  /// without granting anything twice, since this only ever sets a single
  /// persisted boolean to true.
  Future<void> grantRemoveAds() async {
    final prefs = await _prefs();
    await prefs.setBool(MonetizationKeys.removeAds, true);
  }

  /// How many rewarded-ad grants remain today for the given counter
  /// [key] (e.g. one key per Common Chest category -- see
  /// RewardedChestService). Independent keys have entirely independent
  /// allowances; there is no shared/global pool.
  Future<int> remainingRewardedOpensToday(String key, int dailyCap) async {
    final prefs = await _prefs();
    final storedDate = prefs.getString(MonetizationKeys.rewardedDate(key));
    final today = _today();
    final count = storedDate == today
        ? (prefs.getInt(MonetizationKeys.rewardedCount(key)) ?? 0)
        : 0;
    return (dailyCap - count).clamp(0, dailyCap);
  }

  /// Records that one rewarded-ad grant happened just now for [key],
  /// resetting that key's counter on a new day. Call this exactly once
  /// per completed rewarded-ad view, from inside the SDK's "user earned
  /// reward" callback only -- never speculatively before the ad actually
  /// finishes, and never before the specific reward (e.g. a chest roll)
  /// is about to be granted.
  ///
  /// Returns false (and records nothing) if today's cap for [key] was
  /// already reached, so a caller that raced past the UI's disabled
  /// state still cannot grant more than the cap. Concurrent calls for
  /// the SAME key are serialized (see [_locks]) so two near-simultaneous
  /// grants are counted one after the other against the same cap, never
  /// both squeezed through a stale read.
  Future<bool> recordRewardedOpen(String key, int dailyCap) {
    final previous = _locks[key] ?? Future.value();
    final done = Completer<void>();
    _locks[key] = done.future;
    return previous.then((_) async {
      try {
        final prefs = await _prefs();
        final storedDate = prefs.getString(MonetizationKeys.rewardedDate(key));
        final today = _today();
        final count = storedDate == today
            ? (prefs.getInt(MonetizationKeys.rewardedCount(key)) ?? 0)
            : 0;
        if (count >= dailyCap) return false;
        await prefs.setString(MonetizationKeys.rewardedDate(key), today);
        await prefs.setInt(MonetizationKeys.rewardedCount(key), count + 1);
        return true;
      } finally {
        done.complete();
      }
    });
  }

  // ---------------------------------------------------------------------
  // Gem purchase durability (monetization update pass 2026-09-27)
  // ---------------------------------------------------------------------
  //
  // A consumable gem purchase is real money -- it must survive an app
  // restart, a delayed Play response, a duplicate purchase-stream
  // callback, a dropped network connection, and Play redelivering the
  // same still-unconsumed purchase again, WITHOUT ever losing the gems or
  // crediting them twice. The pattern used here:
  //
  //  1. BillingService calls [creditGemPurchaseIfNew] the moment Play
  //     reports a purchase, keyed by that purchase's own stable id --
  //     BEFORE the purchase is ever consumed/finished on Play's side (see
  //     BillingService._onPurchaseUpdate). This durably records "N gems
  //     are owed" in SharedPreferences, independent of the voyage file, so
  //     it survives even if the app dies before the voyage ever sees the
  //     gems.
  //  2. Only after that durable write succeeds does BillingService
  //     consume/finish the purchase with Play -- so if the app dies before
  //     step 1 completes, the purchase is still unconsumed and Play will
  //     redeliver it next launch, giving this a chance to run again. If it
  //     dies AFTER step 1 but before consumption, redelivery finds the
  //     purchase id already recorded (a no-op the second time) and simply
  //     retries consumption.
  //  3. Whoever owns the live voyage (CommandScreen) drains
  //     [pendingGems] into the voyage's real gem balance, saves the
  //     voyage, and only THEN calls [clearPendingGems] for exactly the
  //     amount it just durably saved -- so a crash between crediting here
  //     and that save completing leaves the pending amount recorded for
  //     next launch to apply again, rather than silently dropped.
  //
  // Both the credit and the clear go through the same per-key lock
  // (['gems']) that [recordRewardedOpen] already established the pattern
  // for, so a live purchase landing concurrently with a drain can never
  // race each other.

  /// Durably records that [purchaseKey] (a stable per-transaction id --
  /// see BillingService for exactly which field) has been credited
  /// [gems] gems, UNLESS it was already recorded (redelivery of the same
  /// still-unconsumed purchase, a duplicate stream callback, etc.), in
  /// which case this is a no-op and returns false. Returns true only the
  /// first time a given [purchaseKey] is seen.
  Future<bool> creditGemPurchaseIfNew(String purchaseKey, int gems) =>
      _creditConsumablePurchaseIfNew(
        purchaseKey,
        gems,
        lockKey: 'gems',
        ledgerKey: MonetizationKeys.gemPurchaseLedger,
      );

  /// The gem total durably recorded by [creditGemPurchaseIfNew] but not
  /// yet drained into a voyage's real balance (see [clearPendingGems]).
  /// Read at BillingService.start() (a prior session may have credited
  /// this and then been killed before ever draining it) and again live,
  /// each time a purchase completes.
  Future<int> pendingGems() async {
    final prefs = await _prefs();
    return _ConsumableLedgerState.fromJson(
      prefs.getString(MonetizationKeys.gemPurchaseLedger),
    ).pending;
  }

  /// Reduces the durable pending-gems counter by [amount] -- call this
  /// ONLY after the caller has itself durably applied that same [amount]
  /// to a voyage's real gem balance AND confirmed that voyage save
  /// completed. Never clears more than the current recorded amount (a
  /// concurrent credit landing between a caller's read and this call is
  /// preserved, not clobbered, because both operations share the same
  /// ['gems'] lock).
  Future<void> clearPendingGems(int amount) => _clearPendingConsumable(
    amount,
    lockKey: 'gems',
    ledgerKey: MonetizationKeys.gemPurchaseLedger,
  );

  /// Coin purchase equivalent of [creditGemPurchaseIfNew] -- same
  /// durability story, a separate currency and separate durable state
  /// (see MonetizationKeys.coinPurchaseLedger), so a gem purchase and a
  /// coin purchase in flight at the same time can never interfere with
  /// each other.
  Future<bool> creditCoinPurchaseIfNew(String purchaseKey, int coins) =>
      _creditConsumablePurchaseIfNew(
        purchaseKey,
        coins,
        lockKey: 'coins',
        ledgerKey: MonetizationKeys.coinPurchaseLedger,
      );

  Future<int> pendingCoins() async {
    final prefs = await _prefs();
    return _ConsumableLedgerState.fromJson(
      prefs.getString(MonetizationKeys.coinPurchaseLedger),
    ).pending;
  }

  Future<void> clearPendingCoins(int amount) => _clearPendingConsumable(
    amount,
    lockKey: 'coins',
    ledgerKey: MonetizationKeys.coinPurchaseLedger,
  );

  /// Shared implementation behind [creditGemPurchaseIfNew]/
  /// [creditCoinPurchaseIfNew].
  ///
  /// BILLING AUDIT FIX: reads and rewrites [ledgerKey]'s WHOLE
  /// [_ConsumableLedgerState] (pending amount + credited-id list) as a
  /// single `setString` call, not two independent keys. Two independent
  /// writes had a real failure mode either order: pending-then-ids could
  /// leave an amount durably added but never marked credited (a retry
  /// would then add it AGAIN -- a duplicate credit); ids-then-pending
  /// could leave a purchase marked credited with its amount never added
  /// at all (a retry would then never add it -- a lost credit, since the
  /// id already looks "handled"). A single-key write instead either
  /// fully succeeds (both change together) or leaves the WHOLE blob
  /// exactly as it was (neither changes) -- there is no partially-applied
  /// state for a crash/failure to land in, so a failure here is always
  /// safely retryable from scratch, never a duplicate or a loss.
  ///
  /// [lockKey] keeps a gem credit and a coin credit from ever racing each
  /// other's own currency-specific state while still serializing
  /// same-currency calls.
  Future<bool> _creditConsumablePurchaseIfNew(
    String purchaseKey,
    int amount, {
    required String lockKey,
    required String ledgerKey,
  }) {
    final previous = _locks[lockKey] ?? Future.value();
    final done = Completer<void>();
    _locks[lockKey] = done.future;
    return previous.then((_) async {
      try {
        final prefs = await _prefs();
        final state = _ConsumableLedgerState.fromJson(
          prefs.getString(ledgerKey),
        );
        if (state.creditedIds.contains(purchaseKey)) return false;
        // Cap the remembered-id list so a long-lived install can't grow
        // it forever -- Play will never redeliver a purchase this old
        // again, so trimming the oldest entries is safe.
        const keepMost = 200;
        final updatedIds = [...state.creditedIds, purchaseKey];
        final updated = _ConsumableLedgerState(
          pending: state.pending + amount,
          creditedIds: updatedIds.length > keepMost
              ? updatedIds.sublist(updatedIds.length - keepMost)
              : updatedIds,
        );
        await prefs.setString(ledgerKey, jsonEncode(updated.toJson()));
        return true;
      } finally {
        done.complete();
      }
    });
  }

  Future<void> _clearPendingConsumable(
    int amount, {
    required String lockKey,
    required String ledgerKey,
  }) {
    final previous = _locks[lockKey] ?? Future.value();
    final done = Completer<void>();
    _locks[lockKey] = done.future;
    return previous.then((_) async {
      try {
        final prefs = await _prefs();
        final state = _ConsumableLedgerState.fromJson(
          prefs.getString(ledgerKey),
        );
        final remaining = state.pending - amount;
        final updated = _ConsumableLedgerState(
          pending: remaining < 0 ? 0 : remaining,
          creditedIds: state.creditedIds,
        );
        await prefs.setString(ledgerKey, jsonEncode(updated.toJson()));
      } finally {
        done.complete();
      }
    });
  }
}
