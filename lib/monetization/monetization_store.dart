import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistence for everything monetization needs to remember, kept
/// deliberately separate from `VoyageStore`'s `dot_commander.pirates.voyage.v1`
/// key: a real-money entitlement (Remove Ads) must never be affected by a
/// voyage reset/reroll, and must be checkable before a voyage even exists
/// (e.g. to decide whether to show a banner while the world loads).
///
/// All logic here is plain Dart over `SharedPreferences` -- no
/// `google_mobile_ads`/`in_app_purchase` imports -- so it is directly unit
/// testable without any ad/billing platform channel.
abstract final class MonetizationKeys {
  static const removeAds = 'dot_commander.monetization.remove_ads';
  static const rewardedDate = 'dot_commander.monetization.rewarded_date';
  static const rewardedCount = 'dot_commander.monetization.rewarded_count';
}

class MonetizationStore {
  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _now;
  // A tiny async mutex: each call chains onto the previous one so
  // concurrent grant attempts are serialized (one at a time, in order)
  // rather than racing each other or being dropped. A plain boolean
  // "busy" guard is NOT enough here -- it would make every concurrent
  // caller except the very first one fail immediately instead of queuing,
  // which would under-grant valid rewards, not just prevent duplicates.
  Future<void> _lock = Future.value();

  MonetizationStore({
    Future<SharedPreferences> Function()? prefs,
    DateTime Function()? now,
  }) : _prefs = prefs ?? SharedPreferences.getInstance,
       _now = now ?? DateTime.now;

  String _today() {
    final d = _now().toUtc();
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

  /// How many rewarded-ad gem grants remain for today's local-UTC date.
  Future<int> rewardedAdsRemainingToday(int dailyCap) async {
    final prefs = await _prefs();
    final storedDate = prefs.getString(MonetizationKeys.rewardedDate);
    final today = _today();
    final count = storedDate == today
        ? (prefs.getInt(MonetizationKeys.rewardedCount) ?? 0)
        : 0;
    return (dailyCap - count).clamp(0, dailyCap);
  }

  /// Records that one rewarded-ad gem grant happened just now, resetting
  /// the counter on a new day. Call this exactly once per completed
  /// rewarded-ad view, from inside the SDK's "user earned reward" callback
  /// only -- never speculatively before the ad actually finishes.
  ///
  /// Returns false (and records nothing) if today's cap was already
  /// reached, so a caller that raced past the UI's disabled state still
  /// cannot grant more than the cap. Concurrent calls are serialized (see
  /// [_lock]) so two near-simultaneous grants are counted one after the
  /// other against the same cap, never both squeezed through a stale read.
  Future<bool> recordRewardedAdGrant(int dailyCap) {
    final previous = _lock;
    final done = Completer<void>();
    _lock = done.future;
    return previous.then((_) async {
      try {
        final prefs = await _prefs();
        final storedDate = prefs.getString(MonetizationKeys.rewardedDate);
        final today = _today();
        final count = storedDate == today
            ? (prefs.getInt(MonetizationKeys.rewardedCount) ?? 0)
            : 0;
        if (count >= dailyCap) return false;
        await prefs.setString(MonetizationKeys.rewardedDate, today);
        await prefs.setInt(MonetizationKeys.rewardedCount, count + 1);
        return true;
      } finally {
        done.complete();
      }
    });
  }
}
