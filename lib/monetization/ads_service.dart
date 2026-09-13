import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'monetization_ids.dart';
import 'monetization_store.dart';

/// One-time SDK bring-up. Safe to call more than once; the plugin itself
/// no-ops a repeat initialize.
class AdsService {
  static Future<void> initialize() => MobileAds.instance.initialize();
}

enum RewardedWatchOutcome {
  /// The user watched the whole ad and a reward was granted.
  rewarded,

  /// Today's rewarded-ad cap was already reached; no ad was shown.
  capReached,

  /// An ad was not available to show (still loading, or failed to load).
  notAvailable,

  /// The ad was shown but closed/skipped before a reward was earned.
  dismissedWithoutReward,
}

/// Owns exactly one rewarded ad's lifecycle at a time: preload, show, and
/// grant-on-earn. `watch()` is the only entry point that can lead to a
/// reward, and it guarantees the reward is recorded at most once per
/// completed ad view:
///  - the SDK invokes `onUserEarnedReward` at most once per shown ad,
///  - the loaded ad instance is discarded the moment `show()` is called
///    (it cannot be shown a second time), and
///  - [MonetizationStore.recordRewardedAdGrant] independently enforces the
///    daily cap as the final source of truth, so even a race between two
///    `watch()` calls cannot grant more than the cap allows.
class RewardedAdController {
  final MonetizationStore store;
  RewardedAd? _ad;
  bool _loading = false;
  RewardedAdController({MonetizationStore? store})
    : store = store ?? MonetizationStore();

  bool get isReady => _ad != null;

  Future<void> preload() async {
    if (_ad != null || _loading) return;
    _loading = true;
    try {
      await RewardedAd.load(
        adUnitId: MonetizationIds.rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) => _ad = ad,
          onAdFailedToLoad: (error) {
            if (kDebugMode) debugPrint('Rewarded ad failed to load: $error');
          },
        ),
      );
    } finally {
      _loading = false;
    }
  }

  /// Shows the currently loaded ad (if any) and, only once the user has
  /// actually earned the reward, records and returns how many gems to
  /// grant. The caller is responsible for adding the returned gem count
  /// to the player's persisted balance and saving -- this controller does
  /// not touch game state directly, so it stays testable without a voyage.
  Future<(RewardedWatchOutcome, int)> watch({
    required int rewardGems,
    required int dailyCap,
  }) async {
    if (await store.rewardedAdsRemainingToday(dailyCap) <= 0) {
      return (RewardedWatchOutcome.capReached, 0);
    }
    final ad = _ad;
    if (ad == null) return (RewardedWatchOutcome.notAvailable, 0);
    _ad = null; // Discard immediately: an ad instance can only show once.

    var earned = false;
    final dismissed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        if (!dismissed.isCompleted) dismissed.complete();
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        a.dispose();
        if (!dismissed.isCompleted) dismissed.complete();
      },
    );
    await ad.show(
      onUserEarnedReward: (ad, reward) {
        earned = true;
      },
    );
    await dismissed.future;
    // Kick off the next preload in the background so a subsequent watch
    // (tomorrow, or after the cap resets) has an ad ready immediately.
    unawaited(preload());
    if (!earned) return (RewardedWatchOutcome.dismissedWithoutReward, 0);
    final granted = await store.recordRewardedAdGrant(dailyCap);
    return granted
        ? (RewardedWatchOutcome.rewarded, rewardGems)
        : (RewardedWatchOutcome.capReached, 0);
  }
}
