import 'package:flutter/foundation.dart';

/// Central place for every ID monetization needs -- ad units, the AdMob
/// App ID (also declared in AndroidManifest.xml), and the IAP product ID.
/// Nothing else in this project should hardcode one of these strings.
///
/// PRODUCTION SETUP REQUIRED BEFORE PUBLIC RELEASE:
/// The `kDebugMode` branch below uses Google's own published *test* ad
/// unit IDs (https://developers.google.com/admob/android/test-ads) --
/// they always serve a clearly-labeled test creative and are safe to ship
/// in a debug/internal build, but must never be the ones real users see.
/// The `else` branch below is a placeholder using the SAME test IDs so a
/// Closed-testing build still shows real (test-labeled) ad content instead
/// of failing to load -- replace `_prodBannerId`/`_prodRewardedId` and the
/// AdMob App ID in `android/app/src/main/AndroidManifest.xml` with real
/// values from your own AdMob console before promoting past Closed
/// testing. See the release report for the exact Play Console/AdMob
/// console steps this requires.
abstract final class MonetizationIds {
  static const _testBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const _testRewardedId = 'ca-app-pub-3940256099942544/5224354917';

  // TODO(release): replace with this app's real AdMob ad unit IDs.
  static const _prodBannerId = _testBannerId;
  static const _prodRewardedId = _testRewardedId;

  static String get bannerAdUnitId =>
      kDebugMode ? _testBannerId : _prodBannerId;
  static String get rewardedAdUnitId =>
      kDebugMode ? _testRewardedId : _prodRewardedId;

  /// The Play Console in-app product ID for the Remove Ads entitlement.
  /// Must be created in Play Console > Monetize > Products > In-app
  /// products with this exact ID, a one-time (non-consumable) purchase,
  /// priced at $2.99 (or the local-currency equivalent Play computes).
  static const removeAdsProductId = 'remove_ads';
  static const removeAdsFallbackPriceLabel = '\$2.99';
}
