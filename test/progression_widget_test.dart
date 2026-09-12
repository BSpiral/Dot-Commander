import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/main.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';

void main() {
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
      await tester.drag(
        find.byKey(const PageStorageKey('management_2')),
        const Offset(0, -240),
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('equip_item-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('equip_item-1')));
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
