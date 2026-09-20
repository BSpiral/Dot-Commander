import 'package:flutter/foundation.dart';

import '../pirates/progression/fleet_progress.dart';

/// Central place for every ID monetization needs -- ad units, the AdMob
/// App ID (also declared in AndroidManifest.xml), and the IAP product ID.
/// Nothing else in this project should hardcode one of these strings.
///
/// Dot Commander's real AdMob account is wired in below for the Closed
/// Beta build. Debug builds (`flutter run`, `flutter test`) always use
/// Google's own published *test* ad unit IDs
/// (https://developers.google.com/admob/android/test-ads) regardless of
/// the real IDs below, so local development never serves (or clicks) a
/// real ad request. Release builds use the real IDs below -- this is
/// intentional for Closed Beta: the point of this pass is for testers to
/// exercise the real ad flow, not a further test placeholder.
abstract final class MonetizationIds {
  static const testBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';
  static const testRewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

  static const _realBannerId = 'ca-app-pub-7136986047774590/6286181016';

  // Real rewarded ad units, named after their AdMob console labels.
  // Several Common Chest categories deliberately share one underlying ad
  // unit here (see RewardedAdGroup/ChestCategoryRewardedGroup below) --
  // that only shares ad SUPPLY between those categories. Each
  // ChestCategory still keeps its own independent 5/day gameplay
  // allowance in MonetizationStore (see RewardedChestService), keyed by
  // category, never by ad unit -- sharing an ad unit cannot combine or
  // inflate a daily limit.
  static const _shipCommonRewardedId =
      'ca-app-pub-7136986047774590/4201486884';
  static const _crewEquipmentRewardedId =
      'ca-app-pub-7136986047774590/7543422364';
  static const _officersCommonRewardedId =
      'ca-app-pub-7136986047774590/1788532806';

  static String get bannerAdUnitId =>
      kDebugMode ? testBannerAdUnitId : _realBannerId;

  /// The real rewarded ad unit ID backing [group], or Google's test
  /// rewarded ID in debug builds.
  static String rewardedAdUnitIdFor(RewardedAdGroup group) {
    if (kDebugMode) return testRewardedAdUnitId;
    return switch (group) {
      RewardedAdGroup.shipCommon => _shipCommonRewardedId,
      RewardedAdGroup.crewEquipment => _crewEquipmentRewardedId,
      RewardedAdGroup.officersCommon => _officersCommonRewardedId,
    };
  }

  /// AdMob device IDs to register as GADMobileAds test devices (see
  /// https://developers.google.com/admob/android/test-ads#enable_test_devices).
  /// A device listed here always receives Google's test ad creative, no
  /// matter which ad unit ID above is requested -- this is the supported
  /// way for a developer's OWN physical phone to be clicked/interacted
  /// with repeatedly (including in a Release build) without generating
  /// invalid-traffic activity against the real ad units above.
  ///
  /// Deliberately empty by default. To use it: run a build with ads
  /// enabled on your device, find the line in logcat that reads
  /// "Use RequestConfiguration.Builder... to get test ads on this
  /// device" (it prints your device's ID), and add that ID string here
  /// while YOU are personally repeat-testing on that phone. Do NOT add a
  /// Closed Beta tester's device here -- the whole point of this pass is
  /// for testers to exercise the real ad flow, and listing their device
  /// would silently show them test ads instead.
  static const testDeviceIds = <String>[];

  /// The Play Console in-app product ID for the Remove Ads entitlement.
  /// Must be created in Play Console > Monetize > Products > In-app
  /// products with this exact ID, a one-time (non-consumable) purchase,
  /// priced at $2.99 (or the local-currency equivalent Play computes).
  static const removeAdsProductId = 'remove_ads';
  static const removeAdsFallbackPriceLabel = '\$2.99';
}

/// Which of Dot Commander's three real rewarded ad units backs a Common
/// Chest category's rewarded-ad opening route. Named after the AdMob
/// console labels for those units.
///
/// Playability pass 2026-09-18: this is also the player-facing unit for
/// Common Chest AD REWARDS -- there are exactly 3 "watch an ad to open a
/// Common Chest" rows, one per group below (see RewardedChestTile/
/// RewardedChestService). Paid gem-purchase chests (Shop tab) are
/// unaffected and still offer all 5 ChestCategory values individually.
///
/// Saturday playtest repair pass 2026-09-20: [crewEquipment] previously
/// pooled THREE different ChestCategory values (equipment, crew, cannon)
/// behind one "Crew & Equipment" button, chosen at random per watch --
/// but ChestCategory.equipment means SHIP equipment (rigging/
/// reinforcement/figurehead, see ChestCategoryContent.accepts), not crew
/// gear, so a button promising crew equipment could hand out a
/// Figurehead. Each group now grants from exactly ONE ChestCategory, so a
/// button's label is always an honest, complete description of what it
/// can award -- ChestCategory.equipment and ChestCategory.cannon are no
/// longer reachable via any rewarded ad (still purchasable in the Shop's
/// paid chest grid, which already offers all 5 categories individually);
/// adding a dedicated ad route for either would need a real new AdMob ad
/// unit, which doesn't exist.
enum RewardedAdGroup { shipCommon, crewEquipment, officersCommon }

extension RewardedAdGroupLabel on RewardedAdGroup {
  String get label => switch (this) {
    RewardedAdGroup.shipCommon => 'Ship',
    RewardedAdGroup.crewEquipment => 'Crew Equipment',
    RewardedAdGroup.officersCommon => 'Officers',
  };

  /// The single ChestCategory this ad group grants access to. Kept
  /// list-shaped (always exactly 1 element) so existing callers that
  /// pick "a random category within the group" (see
  /// CommandScreen._grantRewardedChest) need no changes now that every
  /// group maps to exactly one category.
  List<ChestCategory> get chestCategories => switch (this) {
    RewardedAdGroup.shipCommon => const [ChestCategory.hull],
    RewardedAdGroup.crewEquipment => const [ChestCategory.crew],
    RewardedAdGroup.officersCommon => const [ChestCategory.officers],
  };
}
