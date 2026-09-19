import 'ads_service.dart';
import 'monetization_store.dart';
import '../pirates/progression/fleet_progress.dart';

enum RewardedGoldOutcome {
  /// The ad was watched to completion, the SDK confirmed the reward, and
  /// today's allowance was successfully consumed -- the caller must
  /// grant exactly one gold reward for this outcome, and only this one.
  granted,

  /// Today's 5/day allowance was already used up.
  capReached,

  /// No ad was ready to show yet.
  notAvailable,

  /// A rewarded ad is already showing.
  busy,

  /// The ad was shown but closed/skipped before earning the reward.
  dismissedWithoutReward,
}

/// The "watch an ad for gold" reward (playability pass 2026-09-18).
/// Added when the Common Chest ad rows were consolidated from 5 down to
/// 3 (one per real RewardedAdGroup -- see RewardedChestService); this
/// reuses the freed reward opportunity for something genuinely different
/// from a 4th near-identical chest path. Mirrors RewardedChestService's
/// shape (same daily-cap mechanics, same MonetizationStore) but grants
/// gold via PiratesVoyage.grantAdGold instead of an equipment roll.
class RewardedGoldService {
  static const _key = 'ad_gold';
  final RewardedAdSource ads;
  final MonetizationStore store;
  final int dailyCap;
  RewardedGoldService({
    required this.ads,
    required this.store,
    this.dailyCap = Balance.rewardedChestDailyCap,
  });

  Future<int> remainingToday() =>
      store.remainingRewardedOpensToday(_key, dailyCap);

  Future<RewardedGoldOutcome> watch() async {
    if (await remainingToday() <= 0) return RewardedGoldOutcome.capReached;
    final result = await ads.show();
    switch (result) {
      case RewardedShowResult.busy:
        return RewardedGoldOutcome.busy;
      case RewardedShowResult.notAvailable:
        return RewardedGoldOutcome.notAvailable;
      case RewardedShowResult.dismissedWithoutReward:
        return RewardedGoldOutcome.dismissedWithoutReward;
      case RewardedShowResult.earned:
        final consumed = await store.recordRewardedOpen(_key, dailyCap);
        return consumed
            ? RewardedGoldOutcome.granted
            : RewardedGoldOutcome.capReached;
    }
  }
}
