import '../pirates/progression/fleet_progress.dart';
import 'ads_service.dart';
import 'monetization_store.dart';

enum RewardedChestOutcome {
  /// The ad was watched to completion, the SDK confirmed the reward, and
  /// today's per-category allowance was successfully consumed -- the
  /// caller must grant exactly one Common Chest roll for this outcome,
  /// and only this outcome.
  granted,

  /// Today's 5/day allowance for this specific chest category was
  /// already used up; no ad was shown (a wasted ad request is avoided),
  /// or the ad was watched but the allowance was exhausted by a
  /// concurrent grant in the brief window between the pre-check and the
  /// SDK confirming the reward (rare; still correctly grants nothing).
  capReached,

  /// No ad was ready to show yet.
  notAvailable,

  /// A rewarded ad (for this or any other chest category -- only one
  /// can be on screen at a time) is already showing.
  busy,

  /// The ad was shown but the user closed/skipped it before earning the
  /// reward, or it failed to display once summoned.
  dismissedWithoutReward,
}

/// Common Chests' rewarded-ad opening route. Each [ChestCategory] has its
/// own independent 5-per-day allowance (not a shared pool) -- see
/// Balance.rewardedChestDailyCap and MonetizationStore's per-key
/// counters. This class only decides *whether* a chest may be granted
/// for watching an ad; the actual chest roll
/// (PiratesVoyage.openRewardedChest) is the caller's job, and must only
/// run when this reports [RewardedChestOutcome.granted] -- never
/// speculatively, and never more than once per call to [watch].
///
/// [adsByCategory] maps each category to the ad source that serves it.
/// Several categories are deliberately mapped to the SAME underlying ad
/// source/unit (see MonetizationIds.rewardedAdUnitIdFor) -- that only
/// shares ad supply between them; the daily allowance below is always
/// looked up and consumed by [ChestCategory], never by ad source, so
/// sharing an ad unit can never combine or inflate two categories' caps.
class RewardedChestService {
  final Map<ChestCategory, RewardedAdSource> adsByCategory;
  final MonetizationStore store;
  final int dailyCap;

  RewardedChestService({
    required this.adsByCategory,
    required this.store,
    this.dailyCap = Balance.rewardedChestDailyCap,
  }) : assert(
         ChestCategory.values.every(adsByCategory.containsKey),
         'adsByCategory must map every ChestCategory to an ad source',
       );

  /// Convenience for when every category shares one ad source (e.g. most
  /// tests, or a build that hasn't split rewarded ad units by category).
  factory RewardedChestService.singleSource({
    required RewardedAdSource ads,
    required MonetizationStore store,
    int dailyCap = Balance.rewardedChestDailyCap,
  }) => RewardedChestService(
    adsByCategory: {for (final c in ChestCategory.values) c: ads},
    store: store,
    dailyCap: dailyCap,
  );

  String _key(ChestCategory category) => 'chest_${category.name}';

  Future<int> remainingToday(ChestCategory category) =>
      store.remainingRewardedOpensToday(_key(category), dailyCap);

  /// Watches one rewarded ad on behalf of [category]. Returns
  /// [RewardedChestOutcome.granted] at most once per call, and only
  /// after both the SDK confirmed the reward AND this category's daily
  /// allowance was atomically consumed -- the caller should treat
  /// exactly (and only) that outcome as "open one Common Chest of this
  /// category now".
  Future<RewardedChestOutcome> watch(ChestCategory category) async {
    // Pre-check avoids spending an ad impression on a category that is
    // already capped for today.
    if (await remainingToday(category) <= 0) {
      return RewardedChestOutcome.capReached;
    }
    final result = await adsByCategory[category]!.show();
    switch (result) {
      case RewardedShowResult.busy:
        return RewardedChestOutcome.busy;
      case RewardedShowResult.notAvailable:
        return RewardedChestOutcome.notAvailable;
      case RewardedShowResult.dismissedWithoutReward:
        return RewardedChestOutcome.dismissedWithoutReward;
      case RewardedShowResult.earned:
        final consumed = await store.recordRewardedOpen(
          _key(category),
          dailyCap,
        );
        return consumed
            ? RewardedChestOutcome.granted
            : RewardedChestOutcome.capReached;
    }
  }
}
