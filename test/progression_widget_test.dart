import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/main.dart';
import 'package:dot_commander/pirates/encounters/pirates_voyage.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';
import 'package:dot_commander/ui/management/progression_panel.dart';

void main() {
  Widget upgradesPanel(PiratesVoyage v, Vessel ship) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ProgressionPanel(voyage: v, ship: ship, tab: 2, changed: () {}),
      ),
    ),
  );

  testWidgets(
    'Upgrades tab groups equipment into Hull/Officer/Crew Equipment '
    'categories (plus Inventory) and each category drills into its own '
    'five slots, shown plainly as EMPTY rather than hidden',
    (tester) async {
      final v = createCaribbean();
      final ship = v.ships.firstWhere((s) => s.playerOwned);
      await tester.pumpWidget(upgradesPanel(v, ship));
      await tester.pump();
      // Landing page: exactly the three categories plus Inventory --
      // not a flat dump of every owned item.
      expect(find.byKey(const Key('upgrade_category_hull')), findsOneWidget);
      expect(
        find.byKey(const Key('upgrade_category_officer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('upgrade_category_crewEquipment')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('upgrade_inventory')), findsOneWidget);

      // Hull category: five slots -- Ship, Cannons, Rigging,
      // Reinforcement, Figurehead. A fresh command has nothing equipped
      // except the default Sloop hull (its own special-cased "Basic
      // Sloop (default...)" row); the other four read as explicit EMPTY
      // slots rather than disappearing from the layout.
      await tester.tap(find.byKey(const Key('upgrade_category_hull')));
      await tester.pump();
      for (final label in ['Ship', 'Cannons', 'Rigging', 'Reinforcement', 'Figurehead']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.textContaining('Basic Sloop'), findsOneWidget);
      expect(find.text('EMPTY — unequipped'), findsNWidgets(4));

      // Back to landing, into Crew Equipment: five slots, all empty.
      await tester.tap(find.byKey(const Key('upgrades_back')));
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('upgrade_category_crewEquipment')),
      );
      await tester.pump();
      for (final label in ['Head', 'Body', 'Hands', 'Legs', 'Weapon']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('EMPTY — unequipped'), findsNWidgets(5));

      // Equipping something turns that slot's row from empty to named.
      // Re-pumping preserves UpgradesPanel's own navigation State (same
      // widget position/type), so this stays on the Crew Equipment slot
      // list already opened above rather than resetting to the landing
      // page -- no extra navigation tap needed.
      v.progress.inventory.add(
        const EquipmentItem('item-1', 'Test Cutlass', ItemKind.weapon),
      );
      v.progress.commands[ship.id]!.equipped[ItemKind.weapon] = 'item-1';
      await tester.pumpWidget(upgradesPanel(v, ship));
      await tester.pump();
      expect(find.text('EMPTY — unequipped'), findsNWidgets(4));
      expect(find.textContaining('Test Cutlass'), findsWidgets);
    },
  );
  testWidgets(
    'phone purchase, command Tree, chest reward and hull equip save through real controls',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
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
        ..gems = 20;
      v.progress.inventory.add(
        const EquipmentItem(
          'item-1',
          'Test Brig',
          ItemKind.hull,
          hullType: 'Brig',
        ),
      );
      v.progress.nextItem = 2;
      await store.save(v);
      await tester.pumpWidget(DotCommanderApp(store: store));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('tab_shop')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('buy_slot')));
      await tester.pump();
      expect((await store.load()).progress.commands.length, 2);
      await tester.ensureVisible(find.byKey(const Key('chest_hull_common')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('chest_hull_common')));
      await tester.pump();
      expect((await store.load()).gems, 10);
      await tester.tap(find.byKey(const Key('tab_tree')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('tree_hull')));
      await tester.tap(find.byKey(const Key('tree_hull')));
      await tester.pump();
      expect(
        (await store.load()).progress.commands.values.first.level(
          CommandTrack.hull,
        ),
        1,
      );
      await tester.tap(find.byKey(const Key('tab_upgrades')));
      await tester.pump();
      // Relevance-first navigation: Upgrades -> Hull -> Ship shows only
      // owned ships, not the flat old all-items list.
      await tester.tap(find.byKey(const Key('upgrade_category_hull')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('upgrade_slot_hull')));
      await tester.pump();
      final equipButton = find.byKey(const Key('equip_stack_hull|Brig_common'));
      await tester.ensureVisible(equipButton);
      await tester.pump();
      await tester.tap(equipButton);
      await tester.pump();
      final restored = await store.load();
      expect(restored.ships.first.hullType, 'Brig');
      expect(
        restored.progress.commands.values.first.level(CommandTrack.hull),
        1,
      );
      expect(restored.progress.commands.values.last.tree, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
