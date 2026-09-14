import 'dart:async';

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
}
