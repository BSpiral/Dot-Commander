import 'ads_service.dart';

/// Live playtest correction 2026-09-20 (second pass, same day): the Money
/// Ship is a REWARDED-AD opportunity, not a direct grant. Tapping/catching
/// it on the map only initiates this -- the actual gold reward
/// (PiratesVoyage.claimMoneyShip's real fleetCoinsPerHour formula) must be
/// granted ONLY once the SDK confirms the ad was watched to completion.
enum RewardedMoneyShipOutcome {
  /// The ad was watched to completion and the SDK confirmed the reward --
  /// the caller must grant the money ship's reward for this outcome, and
  /// only this outcome.
  granted,

  /// No ad was ready to show yet.
  notAvailable,

  /// A rewarded ad is already showing (only one can be on screen at a
  /// time) -- this also protects a single money ship encounter from being
  /// exploited by repeated taps while its ad is already in flight, since
  /// [RewardedAdController]'s own busy-guard rejects a second concurrent
  /// show() before either can complete.
  busy,

  /// The ad was shown but closed/skipped before earning the reward, or it
  /// failed to display once summoned.
  dismissedWithoutReward,
}

/// The Money Ship's rewarded-ad opening route. Deliberately reuses an
/// existing ad unit for supply (the same established precedent as this
/// project's earlier "watch an ad for gold" shop button, before it moved
/// to a map encounter -- see git history) rather than a new dedicated ad
/// unit. Unlike RewardedChestService/the old RewardedGoldService, this
/// has NO daily cap of its own: the Money Ship's availability is already
/// rate-limited by its own spawn schedule (~6/hour, ~540-660s apart -- see
/// Balance.moneyShipCooldownSimSeconds), so a separate allowance would
/// only double-gate the exact same opportunity.
class RewardedMoneyShipService {
  final RewardedAdSource ads;
  RewardedMoneyShipService({required this.ads});

  Future<RewardedMoneyShipOutcome> watch() async {
    final result = await ads.show();
    return switch (result) {
      RewardedShowResult.earned => RewardedMoneyShipOutcome.granted,
      RewardedShowResult.notAvailable => RewardedMoneyShipOutcome.notAvailable,
      RewardedShowResult.busy => RewardedMoneyShipOutcome.busy,
      RewardedShowResult.dismissedWithoutReward =>
        RewardedMoneyShipOutcome.dismissedWithoutReward,
    };
  }
}
