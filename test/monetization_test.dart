import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dot_commander/monetization/ads_service.dart';
import 'package:dot_commander/monetization/banner_ad_bar.dart';
import 'package:dot_commander/monetization/monetization_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MonetizationStore: Remove Ads entitlement', () {
    test('starts unowned and is granted idempotently', () async {
      final store = MonetizationStore();
      expect(await store.hasRemoveAds(), isFalse);
      await store.grantRemoveAds();
      expect(await store.hasRemoveAds(), isTrue);
      // Redelivery (restore, dropped-connection retry) must not error or
      // change anything -- granting is just setting one bool to true.
      await store.grantRemoveAds();
      await store.grantRemoveAds();
      expect(await store.hasRemoveAds(), isTrue);
    });

    test('persists across a fresh SharedPreferences handle (restart)', () async {
      final first = MonetizationStore();
      await first.grantRemoveAds();
      // A brand-new store instance re-reading the same backing prefs
      // simulates an app restart without any in-memory state carried over.
      final second = MonetizationStore();
      expect(await second.hasRemoveAds(), isTrue);
    });
  });

  group('MonetizationStore: rewarded-ad daily cap', () {
    test('grants up to the cap then blocks, and reports remaining correctly', () async {
      final fixed = DateTime.utc(2026, 1, 1, 12);
      final store = MonetizationStore(now: () => fixed);
      const cap = 3;
      expect(await store.rewardedAdsRemainingToday(cap), 3);
      expect(await store.recordRewardedAdGrant(cap), isTrue);
      expect(await store.rewardedAdsRemainingToday(cap), 2);
      expect(await store.recordRewardedAdGrant(cap), isTrue);
      expect(await store.recordRewardedAdGrant(cap), isTrue);
      expect(await store.rewardedAdsRemainingToday(cap), 0);
      // The cap is a hard stop -- one more attempt grants nothing.
      expect(await store.recordRewardedAdGrant(cap), isFalse);
      expect(await store.rewardedAdsRemainingToday(cap), 0);
    });

    test('resets on a new UTC day', () async {
      var now = DateTime.utc(2026, 1, 1, 23, 59);
      final store = MonetizationStore(now: () => now);
      const cap = 2;
      expect(await store.recordRewardedAdGrant(cap), isTrue);
      expect(await store.recordRewardedAdGrant(cap), isTrue);
      expect(await store.recordRewardedAdGrant(cap), isFalse);
      now = DateTime.utc(2026, 1, 2, 0, 1);
      expect(await store.rewardedAdsRemainingToday(cap), cap);
      expect(await store.recordRewardedAdGrant(cap), isTrue);
    });

    test('concurrent grant attempts never exceed the cap', () async {
      final fixed = DateTime.utc(2026, 1, 1);
      final store = MonetizationStore(now: () => fixed);
      const cap = 3;
      final results = await Future.wait(
        List.generate(10, (_) => store.recordRewardedAdGrant(cap)),
      );
      expect(results.where((r) => r).length, cap);
      expect(await store.rewardedAdsRemainingToday(cap), 0);
    });
  });

  group('RewardedAdController', () {
    test('reports notAvailable when no ad has been preloaded', () async {
      final controller = RewardedAdController(
        store: MonetizationStore(now: () => DateTime.utc(2026, 1, 1)),
      );
      final (outcome, gems) = await controller.watch(
        rewardGems: 2,
        dailyCap: 3,
      );
      expect(outcome, RewardedWatchOutcome.notAvailable);
      expect(gems, 0);
    });

    test('reports capReached without needing a loaded ad once today is exhausted', () async {
      final store = MonetizationStore(now: () => DateTime.utc(2026, 1, 1));
      const cap = 1;
      expect(await store.recordRewardedAdGrant(cap), isTrue);
      final controller = RewardedAdController(store: store);
      final (outcome, gems) = await controller.watch(
        rewardGems: 2,
        dailyCap: cap,
      );
      expect(outcome, RewardedWatchOutcome.capReached);
      expect(gems, 0);
    });
  });

  group('BannerAdBar: the permanent ad container', () {
    testWidgets(
      'shows the bordered placeholder box immediately when ads are enabled, '
      'before any real ad has loaded',
      (tester) async {
        // Mirrors real usage: a Column child (see CommandScreen), which
        // gives the bar loose height so it can size itself to
        // BannerAdBar.height -- unlike a bare MaterialApp.home, which
        // would stretch it to fill the whole test surface.
        await tester.pumpWidget(_hostedInColumn(showAds: true));
        await tester.pump();
        expect(find.byKey(const Key('banner_ad_bar')), findsOneWidget);
        expect(find.byKey(const Key('banner_ad_placeholder')), findsOneWidget);
        final size = tester.getSize(find.byKey(const Key('banner_ad_bar')));
        expect(size.height, BannerAdBar.height);
      },
    );

    testWidgets('fully collapses (no box at all) once Remove Ads is owned', (
      tester,
    ) async {
      await tester.pumpWidget(_hostedInColumn(showAds: false));
      await tester.pump();
      expect(find.byKey(const Key('banner_ad_bar')), findsNothing);
      expect(find.byKey(const Key('banner_ad_placeholder')), findsNothing);
    });

    testWidgets(
      'collapses live when showAds flips to false (purchase completes mid-session)',
      (tester) async {
        await tester.pumpWidget(_hostedInColumn(showAds: true));
        await tester.pump();
        expect(find.byKey(const Key('banner_ad_bar')), findsOneWidget);
        await tester.pumpWidget(_hostedInColumn(showAds: false));
        await tester.pump();
        expect(find.byKey(const Key('banner_ad_bar')), findsNothing);
      },
    );
  });
}

Widget _hostedInColumn({required bool showAds}) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: [Expanded(child: Container()), BannerAdBar(showAds: showAds)],
    ),
  ),
);
