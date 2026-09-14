import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/main.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';
import 'package:dot_commander/pirates/progression/life_balance.dart';
import 'package:dot_commander/pirates/ships/crew_representation.dart';
import 'package:dot_commander/pirates/ships/hull_catalog.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';

void main() {
  test('next benefit follows prestige, secondary cap, and MAXED', () {
    final c = CommandProgress('test');
    for (final entry in {
      0: '0.1',
      100: '0.2',
      500: '0.6',
      600: '0.7',
      1000: '1.1',
    }.entries) {
      c.tree[CommandTrack.hull] = entry.key;
      expect(
        c.nextBenefit(CommandTrack.hull),
        'Next level: +${entry.value} Hull capacity',
      );
    }
    // Levels 0/100/500 all land on navigation's rotation index 0
    // ("Sailing Speed") -- 100 and 500 are both multiples of the 4-step
    // pattern length, matching the varied-rotation coverage below.
    for (final entry in {0: '0.01', 100: '0.02', 500: '0.06'}.entries) {
      c.tree[CommandTrack.navigation] = entry.key;
      expect(
        c.nextBenefit(CommandTrack.navigation),
        'Next level: +${entry.value}% Sailing Speed',
      );
    }
    c.tree[CommandTrack.navigation] = 600;
    expect(c.nextBenefit(CommandTrack.navigation), contains('+0%'));
    c.tree[CommandTrack.hull] = 1100;
    expect(c.nextBenefit(CommandTrack.hull), 'Maximum level reached');
    c.tree[CommandTrack.firepower] = 100;
    expect(
      c.nextBenefit(CommandTrack.firepower),
      'Next level: +0.04 firepower',
    );
  });
  test(
    'each Command Tree track rotates through varied, accurate headline facets',
    () {
      final c = CommandProgress('test');
      // Hull: capacity, Damage Reduction, capacity, Post-Battle Hull
      // Repair, Port Repair Discount, then repeats -- CORE/secondary/
      // CORE/utility/related, matching the requested progression style.
      c.tree[CommandTrack.hull] = 0;
      expect(c.nextBenefit(CommandTrack.hull), contains('Hull capacity'));
      c.tree[CommandTrack.hull] = 1;
      expect(c.nextBenefit(CommandTrack.hull), contains('Damage Reduction'));
      c.tree[CommandTrack.hull] = 2;
      expect(c.nextBenefit(CommandTrack.hull), contains('Hull capacity'));
      c.tree[CommandTrack.hull] = 3;
      expect(
        c.nextBenefit(CommandTrack.hull),
        contains('Post-Battle Hull Repair'),
      );
      c.tree[CommandTrack.hull] = 4;
      expect(
        c.nextBenefit(CommandTrack.hull),
        contains('Port Repair Discount'),
      );
      c.tree[CommandTrack.hull] = 5;
      expect(c.nextBenefit(CommandTrack.hull), contains('Hull capacity'));

      // Firepower: core firepower alternating with Opening Attack Strength.
      c.tree[CommandTrack.firepower] = 0;
      expect(c.nextBenefit(CommandTrack.firepower), contains('firepower'));
      c.tree[CommandTrack.firepower] = 1;
      expect(
        c.nextBenefit(CommandTrack.firepower),
        contains('Opening Attack Strength'),
      );

      // Crew: Effectiveness, Recovery, Effectiveness, Boarding Defense.
      c.tree[CommandTrack.crew] = 0;
      expect(c.nextBenefit(CommandTrack.crew), contains('Crew Effectiveness'));
      c.tree[CommandTrack.crew] = 1;
      expect(c.nextBenefit(CommandTrack.crew), contains('Crew Recovery'));
      c.tree[CommandTrack.crew] = 2;
      expect(c.nextBenefit(CommandTrack.crew), contains('Crew Effectiveness'));
      c.tree[CommandTrack.crew] = 3;
      expect(c.nextBenefit(CommandTrack.crew), contains('Boarding Defense'));

      // Navigation: Sailing Speed, Handling, Sailing Speed, Rigging-Damage
      // Mitigation.
      c.tree[CommandTrack.navigation] = 1;
      expect(c.nextBenefit(CommandTrack.navigation), contains('Handling'));
      c.tree[CommandTrack.navigation] = 3;
      expect(
        c.nextBenefit(CommandTrack.navigation),
        contains('Rigging-Damage Mitigation'),
      );

      // Port Relations: Service Discount alternating with Trade Profit Bonus.
      c.tree[CommandTrack.portRelations] = 0;
      expect(
        c.nextBenefit(CommandTrack.portRelations),
        contains('Port Service Discount'),
      );
      c.tree[CommandTrack.portRelations] = 1;
      expect(
        c.nextBenefit(CommandTrack.portRelations),
        contains('Trade Profit Bonus'),
      );
    },
  );
  test(
    'Command Tree secondary bonuses (crewDefense/penaltyMitigation/'
    'economyBonus/openingAttack) actually reach the vessel via apply()',
    () {
      final v = createCaribbean();
      final ship = v.ships.firstWhere((s) => s.playerOwned);
      final c = v.progress.commands[ship.id]!;
      c.tree[CommandTrack.crew] = 500;
      c.tree[CommandTrack.navigation] = 500;
      c.tree[CommandTrack.portRelations] = 500;
      c.tree[CommandTrack.firepower] = 500;
      v.progress.apply(ship);
      final expected = LifeBalance.percent(500);
      expect(expected, greaterThan(0));
      expect(ship.crewDefense, closeTo(expected, 1e-9));
      expect(ship.penaltyMitigation, closeTo(expected, 1e-9));
      expect(ship.economyBonus, closeTo(expected, 1e-9));
      expect(ship.openingAttack, closeTo(expected, 1e-9));
    },
  );
  test(
    'density scales by hull and surviving crew, bounded at twenty including captain',
    () {
      for (final h in hullCatalog) {
        expect(representativeCount(h.name, h.crew), h.representativeCap);
        expect(representativeCount(h.name, 1), 1);
        expect(representativeCount(h.name, 0), 0);
        expect(representativeCount(h.name, h.crew * 100), h.representativeCap);
      }
      expect(representativeCount('Frigate', 55), 13);
      expect(representativeCount('Frigate', 22), 8);
    },
  );
  test(
    'service takes visible proportional time and retains progression/specialist speed bonuses',
    () {
      final v = createCaribbean();
      final s = v.ships.first;
      expect(LifeBalance.serviceSeconds(10, v.life.serviceMultiplier(s)), 5);
      expect(LifeBalance.serviceSeconds(5, v.life.serviceMultiplier(s)), 2.5);
      expect(LifeBalance.serviceSeconds(1, v.life.serviceMultiplier(s)), .75);
      expect(LifeBalance.serviceSeconds(0, v.life.serviceMultiplier(s)), 0);
      v.progress.commands[s.id]!.tree[CommandTrack.crew] = 600;
      expect(LifeBalance.serviceSeconds(10, v.life.serviceMultiplier(s)), 4);
      v.progress.inventory.add(
        const EquipmentItem(
          'specialist',
          'Carpenter',
          ItemKind.quartermaster,
          specialist: 'carpenter',
        ),
      );
      v.progress.commands[s.id]!.equipped[ItemKind.quartermaster] =
          'specialist';
      expect(
        LifeBalance.serviceSeconds(
          10,
          v.life.serviceMultiplier(s, specialist: 'carpenter'),
        ),
        closeTo(3.6, .000001),
      );
      expect(
        LifeBalance.serviceSeconds(
          10,
          v.life.serviceMultiplier(s, specialist: 'bosun'),
        ),
        4,
      );
    },
  );
  testWidgets(
    'debug reset cancellation preserves save and confirmation starts clean',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? data;
      final store = VoyageStore(
        read: () async => data,
        write: (s) async {
          data = s;
        },
      );
      final v = createCaribbean()
        ..coins = 20000
        ..gems = 50;
      v.purchaseSlot();
      v.progress.commands.values.first.tree[CommandTrack.hull] = 100;
      v.progress.apply(v.ships.first);
      await store.save(v);
      await tester.pumpWidget(DotCommanderApp(store: store));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('tab_settings')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('debug_reset')));
      await tester.pump();
      expect(find.text('DEBUG: Reset entire voyage?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 300));
      expect((await store.load()).coins, 10000);
      await tester.tap(find.byKey(const Key('debug_reset')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirm_debug_reset')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final restored = await store.load();
      expect(restored.progress.commands.length, 1);
      expect(restored.progress.commands.values.single.tree, isEmpty);
      expect(restored.progress.inventory, isEmpty);
      expect(restored.coins, 0);
      expect(restored.gems, 0);
      expect(restored.active, isEmpty);
      expect(restored.life.works, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
