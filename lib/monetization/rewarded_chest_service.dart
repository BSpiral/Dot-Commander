import '../pirates/progression/fleet_progress.dart';
import 'ads_service.dart';
import 'monetization_ids.dart';
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

/// Common Chests' rewarded-ad opening route. Each [RewardedAdGroup] (the
/// three real underlying ad units -- see MonetizationIds) has its own
/// independent 5-per-day allowance (not a shared pool) -- see
/// Balance.rewardedChestDailyCap and MonetizationStore's per-key
/// counters. This class only decides *whether* a chest may be granted
/// for watching an ad; the actual chest roll
/// (PiratesVoyage.openRewardedChest, against a category chosen from
/// [RewardedAdGroupLabel.chestCategories]) is the caller's job, and must
/// only run when this reports [RewardedChestOutcome.granted] -- never
/// speculatively, and never more than once per call to [watch].
///
/// Playability pass 2026-09-18: previously keyed by the finer-grained
/// [ChestCategory] (5 values, presented as 5 near-identical UI rows even
/// though only 3 real ad units back them). Now keyed directly by
/// [RewardedAdGroup] (3 values = 3 rows), matching ad supply 1:1; a
/// group covering more than one ChestCategory (crewEquipment) grants a
/// roll from a random category within it, so nothing became less
/// obtainable, only less repetitive to browse.
class RewardedChestService {
  final Map<RewardedAdGroup, RewardedAdSource> adsByGroup;
  final MonetizationStore store;
  final int dailyCap;

  RewardedChestService({
    required this.adsByGroup,
    required this.store,
    this.dailyCap = Balance.rewardedChestDailyCap,
  }) : assert(
         RewardedAdGroup.values.every(adsByGroup.containsKey),
         'adsByGroup must map every RewardedAdGroup to an ad source',
       );

  /// Convenience for when every group shares one ad source (e.g. most
  /// tests, or a build that hasn't split rewarded ad units by group).
  factory RewardedChestService.singleSource({
    required RewardedAdSource ads,
    required MonetizationStore store,
    int dailyCap = Balance.rewardedChestDailyCap,
  }) => RewardedChestService(
    adsByGroup: {for (final g in RewardedAdGroup.values) g: ads},
    store: store,
    dailyCap: dailyCap,
  );

  String _key(RewardedAdGroup group) => 'chest_group_${group.name}';

  Future<int> remainingToday(RewardedAdGroup group) =>
      store.remainingRewardedOpensToday(_key(group), dailyCap);

  /// Watches one rewarded ad on behalf of [group]. Returns
  /// [RewardedChestOutcome.granted] at most once per call, and only
  /// after both the SDK confirmed the reward AND this group's daily
  /// allowance was atomically consumed -- the caller should treat
  /// exactly (and only) that outcome as "open one Common Chest from this
  /// group now" (picking a category via
  /// [RewardedAdGroupLabel.chestCategories]).
  Future<RewardedChestOutcome> watch(RewardedAdGroup group) async {
    // Pre-check avoids spending an ad impression on a group that is
    // already capped for today.
    if (await remainingToday(group) <= 0) {
      return RewardedChestOutcome.capReached;
    }
    final result = await adsByGroup[group]!.show();
    switch (result) {
      case RewardedShowResult.busy:
        return RewardedChestOutcome.busy;
      case RewardedShowResult.notAvailable:
        return RewardedChestOutcome.notAvailable;
      case RewardedShowResult.dismissedWithoutReward:
        return RewardedChestOutcome.dismissedWithoutReward;
      case RewardedShowResult.earned:
        final consumed = await store.recordRewardedOpen(_key(group), dailyCap);
        return consumed
            ? RewardedChestOutcome.granted
            : RewardedChestOutcome.capReached;
    }
  }
}
