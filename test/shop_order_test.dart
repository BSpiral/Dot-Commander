import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/monetization/ads_service.dart';
import 'package:dot_commander/monetization/billing_service.dart';
import 'package:dot_commander/monetization/monetization_ids.dart';
import 'package:dot_commander/monetization/monetization_store.dart';
import 'package:dot_commander/monetization/rewarded_chest_service.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/ui/management/progression_panel.dart';

/// Shop reorder pass 2026-10-03: locks the FINAL SHOP ORDER down with
/// real widget-position assertions (not just presence/count, which
/// test/economy_widget_test.dart and test/monetization_test.dart already
/// covered). See progression_panel.dart's own doc comments for the
/// reasoning; this file only proves the resulting order.
///
/// `billing` is a plain, unstarted BillingService (no .start(), no real
/// platform channel call) -- enough for GemPackTile's rows to render
/// (as "Unavailable"/disabled, since no ProductDetails ever resolved),
/// which is all an ORDER test needs; purchase-flow correctness itself is
/// covered elsewhere (test/monetization_update_test.dart).
Future<void> _pumpShop(
  WidgetTester tester, {
  required dynamic voyage,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProgressionPanel(
            voyage: voyage,
            ship: voyage.ships.first,
            tab: 0,
            changed: () {},
            billing: BillingService(),
            rewardedChests: RewardedChestService.singleSource(
              ads: RewardedAdController(),
              store: MonetizationStore(now: () => DateTime.utc(2026, 1, 1)),
            ),
            onRewardedChestGranted: (_) async {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

double _dy(WidgetTester tester, String key) =>
    tester.getTopLeft(find.byKey(Key(key))).dy;

void main() {
  testWidgets('the three Gem packs are the first three entries in the entire Shop, in gems_100 -> gems_550 -> gems_1200 order', (tester) async {
    final voyage = createCaribbean();
    await _pumpShop(tester, voyage: voyage);

    for (final id in MonetizationIds.gemProductIds) {
      expect(find.byKey(Key('buy_gems_shop_$id')), findsOneWidget);
    }

    final gems100 = _dy(tester, 'buy_gems_shop_${MonetizationIds.gems100ProductId}');
    final gems550 = _dy(tester, 'buy_gems_shop_${MonetizationIds.gems550ProductId}');
    final gems1200 = _dy(tester, 'buy_gems_shop_${MonetizationIds.gems1200ProductId}');
    final commandBerths = _dy(tester, 'buy_slot');
    final firstHullRow = _dy(tester, 'chest_hull_common');

    expect(gems100, lessThan(gems550), reason: '100-gem pack must come before the 550-gem pack');
    expect(gems550, lessThan(gems1200), reason: '550-gem pack must come before the 1200-gem pack');
    expect(gems1200, lessThan(commandBerths), reason: 'all three Gem packs must precede Command berths -- the very next existing Shop entry');
    expect(commandBerths, lessThan(firstHullRow), reason: 'Command berths keeps its existing position, before any chest row');
  });

  testWidgets('Hull retains all three purchase methods in order: Watch Ad -> 10-Gem Common -> 50-Gem Rare', (tester) async {
    final voyage = createCaribbean();
    await _pumpShop(tester, voyage: voyage);

    final ad = _dy(tester, 'watch_chest_ad_hull');
    final common = _dy(tester, 'chest_hull_common');
    final rare = _dy(tester, 'chest_hull_rare');
    expect(ad, lessThan(common), reason: 'Watch Ad -> Common Hull Chest must come before 10-Gem Common');
    expect(common, lessThan(rare), reason: '10-Gem Common Hull Chest must come before 50-Gem Rare');
  });

  testWidgets('Officer retains all three purchase methods in order: Watch Ad -> 10-Gem Common -> 50-Gem Rare', (tester) async {
    final voyage = createCaribbean();
    await _pumpShop(tester, voyage: voyage);

    final ad = _dy(tester, 'watch_chest_ad_officersCommon');
    final common = _dy(tester, 'chest_officers_common');
    final rare = _dy(tester, 'chest_officers_rare');
    expect(ad, lessThan(common), reason: 'Watch Ad -> Common Officer Chest must come before 10-Gem Common');
    expect(common, lessThan(rare), reason: '10-Gem Common Officer Chest must come before 50-Gem Rare');
  });

  testWidgets('Crew (the existing category not named in the launch brief) retains all three purchase methods in order, unchanged', (tester) async {
    final voyage = createCaribbean();
    await _pumpShop(tester, voyage: voyage);

    final ad = _dy(tester, 'watch_chest_ad_crewEquipment');
    final common = _dy(tester, 'chest_crew_common');
    final rare = _dy(tester, 'chest_crew_rare');
    expect(ad, lessThan(common), reason: 'Watch Ad -> Common Crew Chest must come before 10-Gem Common');
    expect(common, lessThan(rare), reason: '10-Gem Common Crew Chest must come before 50-Gem Rare');
  });

  testWidgets('Equipment has zero Shop rows, exactly as it already did before this reorder -- not newly added, not newly removed', (tester) async {
    final voyage = createCaribbean();
    await _pumpShop(tester, voyage: voyage);

    expect(find.byKey(const Key('chest_equipment_common')), findsNothing);
    expect(find.byKey(const Key('chest_equipment_rare')), findsNothing);
    // RewardedAdGroup has no 'equipment' member at all (see
    // monetization_ids.dart), so there's no ad row to check for either.
    // Note: "Crew Equipment Chest" legitimately contains the substring
    // "Equipment Chest" -- a plain text search would wrongly flag it, so
    // this checks the real ChestCategory.equipment-keyed rows only.
  });

  testWidgets('existing category order is preserved exactly: Hull -> Crew -> Officers (gem packs and Command berths aside)', (tester) async {
    final voyage = createCaribbean();
    await _pumpShop(tester, voyage: voyage);

    final hullStart = _dy(tester, 'watch_chest_ad_hull');
    final crewStart = _dy(tester, 'watch_chest_ad_crewEquipment');
    final officersStart = _dy(tester, 'watch_chest_ad_officersCommon');

    expect(hullStart, lessThan(crewStart), reason: 'Hull block must still precede Crew, exactly as in the pre-reorder Shop');
    expect(crewStart, lessThan(officersStart), reason: 'Crew block must still precede Officers, exactly as in the pre-reorder Shop');
  });

  testWidgets('no category/purchase-method entry was duplicated by the reorder', (tester) async {
    final voyage = createCaribbean();
    await _pumpShop(tester, voyage: voyage);

    for (final category in ['hull', 'crew', 'officers']) {
      for (final kind in ['common', 'rare']) {
        expect(find.byKey(Key('chest_${category}_$kind')), findsOneWidget);
      }
    }
    for (final group in RewardedAdGroup.values) {
      expect(find.byKey(Key('watch_chest_ad_${group.name}')), findsOneWidget);
    }
    for (final id in MonetizationIds.gemProductIds) {
      expect(find.byKey(Key('buy_gems_shop_$id')), findsOneWidget);
    }
  });
}
