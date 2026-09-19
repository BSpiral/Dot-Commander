import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';
import 'package:dot_commander/core/persistence/voyage_snapshot.dart';

void main() {
  test(
    'slot prices escalate, basic Sloops have independent identities and zero Trees',
    () {
      final v = createCaribbean()..coins = 2000000;
      final first = v.ships.first;
      v.buyTree(first.id, CommandTrack.hull);
      var previous = 0;
      for (var i = 1; i < 5; i++) {
        final before = v.coins, id = v.purchaseSlot()!;
        expect(before - v.coins, Balance.slotCosts[i]);
        expect(Balance.slotCosts[i], greaterThan(previous));
        previous = Balance.slotCosts[i];
        final s = v.ships.firstWhere((s) => s.id == id);
        expect(s.hullType, 'Sloop');
        expect(v.progress.commands[id]!.tree, isEmpty);
        expect(v.progress.commands[id]!.equipped, isEmpty);
        expect(s.captain, isNot(first.captain));
      }
      expect(v.purchaseSlot(), isNull);
      expect(v.progress.commands[first.id]!.level(CommandTrack.hull), 1);
    },
  );
  test('unaffordable operations are atomic', () {
    final v = createCaribbean();
    expect(v.purchaseSlot(), isNull);
    expect(v.buyTree(v.ships.first.id, CommandTrack.hull), false);
    expect(v.openChest(ChestKind.common, category: ChestCategory.hull), isNull);
    expect(v.coins, 0);
    expect(v.gems, 0);
  });
  test('Tree begins at one coin, escalates and caps at 1100', () {
    final v = createCaribbean()..coins = 1000000000;
    final id = v.ships.first.id;
    expect(Balance.treeCost(0), 1);
    for (var i = 0; i < 1100; i++) {
      expect(v.buyTree(id, CommandTrack.hull), true);
      if (i > 0) {
        expect(Balance.treeCost(i), greaterThan(Balance.treeCost(i - 1)));
      }
    }
    final balance = v.coins;
    expect(v.buyTree(id, CommandTrack.hull), false);
    expect(v.coins, balance);
    expect(v.progress.commands[id]!.level(CommandTrack.hull), 1100);
  });
  test('combat upgrades increase CP, economic and fleet upgrades do not', () {
    final v = createCaribbean()..coins = 2000000;
    final s = v.ships.first;
    v.progress.apply(s);
    for (final t in [
      CommandTrack.hull,
      CommandTrack.firepower,
      CommandTrack.crew,
      CommandTrack.navigation,
      CommandTrack.navigation,
    ]) {
      final before = v.progress.combatPower(s);
      for (var i = 0; i < 20; i++) {
        v.buyTree(s.id, t);
      }
      expect(v.progress.combatPower(s), greaterThan(before));
    }
    final cp = v.progress.combatPower(s), crew = s.crewCount;
    for (final t in [CommandTrack.portRelations]) {
      v.buyTree(s.id, t);
    }
    for (final t in [FleetTrack.offline]) {
      v.buyFleetTree(t);
    }
    expect(v.progress.combatPower(s), cp);
    expect(s.crewCount, crew);
    final id = v.purchaseSlot()!;
    expect(v.progress.tree[FleetTrack.offline], 1);
    expect(v.progress.commands[id]!.tree, isEmpty);
  });
  test(
    'hull swaps and relaunch retain substantial Tree, inventory, currency and damage',
    () async {
      final v = createCaribbean()
        ..coins = 2000000
        ..gems = 77;
      final s = v.ships.first;
      for (var i = 0; i < 200; i++) {
        v.buyTree(s.id, CommandTrack.hull);
      }
      final p = v.progress;
      p.inventory.addAll([
        const EquipmentItem('item-1', 'Brig', ItemKind.hull, hullType: 'Brig'),
        const EquipmentItem(
          'item-2',
          'Excellent Sloop',
          ItemKind.hull,
          hullType: 'Sloop',
          bonus: 3,
        ),
      ]);
      p.nextItem = 3;
      s.hullHp = s.maxHullHp * .5;
      expect(v.equip(s.id, ItemKind.hull, 'item-1'), true);
      expect(s.hullType, 'Brig');
      expect(s.hullHp / s.maxHullHp, .5);
      String? saved;
      final store = VoyageStore(
        read: () async => saved,
        write: (x) async {
          saved = x;
        },
      );
      await store.save(v);
      final loaded = await store.load();
      final restored = loaded.ships.first;
      expect(restored.hullType, 'Brig');
      expect(loaded.coins, v.coins);
      expect(loaded.gems, 77);
      expect(loaded.equip(restored.id, ItemKind.hull, 'item-2'), true);
      expect(restored.hullType, 'Sloop');
      expect(loaded.progress.commands[s.id]!.level(CommandTrack.hull), 200);
      expect(loaded.progress.inventory.length, 2);
      expect(restored.hullHp / restored.maxHullHp, .5);
      expect(loaded.equip(s.id, ItemKind.hull, null), true);
      expect(loaded.progress.commands[s.id]!.equipped, isEmpty);
      expect(loaded.progress.inventory.length, 2);
      await store.save(loaded);
      expect(
        (await store.load()).progress.commands[s.id]!.level(CommandTrack.hull),
        200,
      );
    },
  );
  test(
    'chests charge once and allow duplicate physical copies including Sloop',
    () {
      final v = createCaribbean()..gems = 1000;
      final a = v.openChest(
        ChestKind.common,
        category: ChestCategory.hull,
        random: Random(7),
      )!;
      final b = v.openChest(
        ChestKind.common,
        category: ChestCategory.hull,
        random: Random(7),
      )!;
      expect(a.name, b.name);
      expect(a.id, isNot(b.id));
      expect(v.gems, 980);
      expect(v.progress.lastRewards, [b.id]);
      v.openChest(
        ChestKind.rare,
        category: ChestCategory.hull,
        random: Random(1),
      );
      expect(v.gems, 930);
      EquipmentItem? hull;
      for (var seed = 0; seed < 1000; seed++) {
        final p = FleetProgress([]);
        final item = p.roll(
          ChestKind.common,
          Random(seed),
          category: ChestCategory.hull,
          source: RollSource.paidCommon,
        );
        if (item.hullType == 'Sloop') {
          hull = item;
          break;
        }
      }
      expect(hull, isNotNull);
      expect(hull!.bonus, greaterThan(0));
    },
  );
  test(
    'same physical item cannot equip to two commands, unequip releases it',
    () {
      final v = createCaribbean()..coins = 20000;
      final id = v.purchaseSlot()!, first = v.ships.first.id;
      v.progress.inventory.add(
        const EquipmentItem('item-1', 'Cannon', ItemKind.cannon),
      );
      v.progress.nextItem = 2;
      expect(v.equip(first, ItemKind.cannon, 'item-1'), true);
      expect(v.equip(id, ItemKind.cannon, 'item-1'), false);
      expect(v.equip(id, ItemKind.hull, 'item-1'), false);
      expect(v.equip(first, ItemKind.cannon, null), true);
      expect(v.equip(id, ItemKind.cannon, 'item-1'), true);
      v.heldShips.add(id);
      expect(v.equip(id, ItemKind.cannon, null), false);
      expect(v.buyTree(id, CommandTrack.hull), false);
    },
  );
  test('v2 saves migrate without losing identity or damage', () async {
    final v = createCaribbean();
    v.ships.first.hullHp = 42;
    String? data = VoyageSnapshot.encode(v.ships);
    final store = VoyageStore(
      read: () async => data,
      write: (x) async {
        data = x;
      },
    );
    final loaded = await store.load();
    expect(loaded.ships.first.hullHp, 42);
    expect(loaded.progress.commands.length, 1);
    await store.save(loaded);
    expect(jsonDecode(data!)['version'], 7);
    expect((await store.load()).ships.first.hullHp, 42);
  });
  test('invalid progression preserves original save', () async {
    final v = createCaribbean();
    String? data;
    var writes = 0;
    final store = VoyageStore(
      read: () async => data,
      write: (x) async {
        data = x;
        writes++;
      },
    );
    await store.save(v);
    final root = jsonDecode(data!);
    root['progression']['commands'][0]['tree']['hull'] = 1101;
    data = jsonEncode(root);
    await expectLater(store.load(), throwsFormatException);
    expect(writes, 1);
  });
}
