import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'monetization_ids.dart';

/// One-time SDK bring-up. Safe to call more than once; the plugin itself
/// no-ops a repeat initialize.
class AdsService {
  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
    // Registers MonetizationIds.testDeviceIds (empty by default) so a
    // developer's own listed device always gets Google's test ad
    // creative, regardless of which real ad unit ID is requested. A no-op
    // when the list is empty, which is the default/shipping state.
    if (MonetizationIds.testDeviceIds.isNotEmpty) {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: MonetizationIds.testDeviceIds),
      );
    }
  }
}

enum RewardedShowResult {
  /// The user watched the whole ad and the SDK confirmed the reward.
  earned,

  /// The ad was shown but closed/skipped before a reward was earned, or
  /// it failed to show once summoned.
  dismissedWithoutReward,

  /// No ad was ready to show (still loading, or failed to load).
  notAvailable,

  /// A rewarded ad is already being shown (only one can be on screen at
  /// a time); this call did not start a second one.
  busy,
}

/// The abstract shape of "a source of rewarded ads" that
/// [RewardedChestService] depends on -- [RewardedAdController] is the
/// real (SDK-backed) implementation used in the app; tests can implement
/// this directly with a fake to drive [RewardedChestService.watch]
/// through its `earned` branch without touching the real ad SDK at all
/// (which cannot be made to report an earned reward from a plain Dart
/// test).
abstract class RewardedAdSource {
  bool get isReady;
  bool get isBusy;
  Future<void> preload();
  Future<RewardedShowResult> show();
}

/// Owns exactly one rewarded ad's lifecycle at a time: preload and show.
/// This is a pure ad-mechanics primitive -- it knows nothing about gems,
/// chests, or any other in-game reward; callers (e.g.
/// RewardedChestService) decide what [RewardedShowResult.earned] means
/// and are responsible for granting it exactly once.
///
/// [show] guarantees at most one reward-worthy result per completed ad
/// view:
///  - the SDK invokes `onUserEarnedReward` at most once per shown ad,
///  - the loaded ad instance is discarded the instant [show] is called
///    (it cannot be shown a second time), and
///  - [_busy] refuses to start a second `show()` while one is already
///    in flight (there can only ever be one fullscreen rewarded ad on
///    screen at a time; a repeated tap or an app pause/resume racing a
///    still-open ad cannot start a duplicate show).
class RewardedAdController implements RewardedAdSource {
  /// Which ad unit this controller loads/shows. Several Common Chest
  /// categories intentionally share one controller/ad unit (see
  /// MonetizationIds.rewardedAdUnitIdFor) -- that only shares ad supply;
  /// [_busy] still ensures only one show() across every category using
  /// this same controller can be in flight at a time.
  final String adUnitId;
  RewardedAdController({this.adUnitId = MonetizationIds.testRewardedAdUnitId});

  RewardedAd? _ad;
  bool _loading = false;
  bool _busy = false;

  @override
  bool get isReady => _ad != null;
  @override
  bool get isBusy => _busy;

  @override
  Future<void> preload() async {
    if (_ad != null || _loading) return;
    _loading = true;
    try {
      await RewardedAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) => _ad = ad,
          onAdFailedToLoad: (error) {
            if (kDebugMode) debugPrint('Rewarded ad failed to load: $error');
            // Load failures (including no-fill) grant nothing on their
            // own -- watch() simply reports notAvailable while _ad stays
            // null. Retry shortly so testers exercising failure/no-fill
            // during Closed Beta still see ad supply recover, rather
            // than a permanently dead rewarded slot for the rest of the
            // session.
            Future.delayed(const Duration(seconds: 30), () {
              if (_ad == null && !_loading) unawaited(preload());
            });
          },
        ),
      );
    } finally {
      _loading = false;
    }
  }

  /// Shows the currently loaded ad (if any). Returns
  /// [RewardedShowResult.earned] only once the SDK has actually
  /// confirmed the user earned the reward -- the caller must not grant
  /// anything until it sees that value, and must grant it at most once
  /// per call to [show].
  @override
  Future<RewardedShowResult> show() async {
    if (_busy) return RewardedShowResult.busy;
    final ad = _ad;
    if (ad == null) return RewardedShowResult.notAvailable;
    _busy = true;
    _ad = null; // Discard immediately: an ad instance can only show once.
    try {
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
      // Kick off the next preload in the background so a subsequent
      // watch has an ad ready immediately.
      unawaited(preload());
      return earned
          ? RewardedShowResult.earned
          : RewardedShowResult.dismissedWithoutReward;
    } finally {
      _busy = false;
    }
  }
}
