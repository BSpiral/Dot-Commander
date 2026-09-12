import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';

void main() {
  test(
    'offline coins are capped and persisted before returning, without replay on relaunch',
    () async {
      var now = DateTime.utc(2026, 9, 10);
      String? data;
      final store = VoyageStore(
        now: () => now,
        read: () async => data,
        write: (s) async {
          data = s;
        },
      );
      final v = createCaribbean()..coins = 7;
      v.progress.tree[FleetTrack.offline] = 1000;
      final position = v.ships.first.position;
      await store.save(v);
      now = now.add(const Duration(days: 2));
      final loaded = await store.load();
      expect(loaded.coins, 487);
      expect(loaded.ships.first.position.x, position.x);
      expect(loaded.ships.first.position.y, position.y);
      expect((await store.load()).coins, 487);
    },
  );
  test('clock rollback never gives negative or bonus currency', () async {
    var now = DateTime.utc(2026, 9, 10);
    String? data;
    final store = VoyageStore(
      now: () => now,
      read: () async => data,
      write: (s) async {
        data = s;
      },
    );
    final v = createCaribbean()..coins = 4;
    v.progress.tree[FleetTrack.offline] = 1000;
    await store.save(v);
    now = now.subtract(const Duration(days: 1));
    expect((await store.load()).coins, 4);
  });
  test(
    'v3 wallet and encounter metadata migrate into zero-level command state',
    () async {
      String? data;
      final store = VoyageStore(
        read: () async => data,
        write: (s) async {
          data = s;
        },
      );
      final v = createCaribbean()
        ..coins = 33
        ..gems = 9;
      await store.save(v);
      final root = jsonDecode(data!);
      root['version'] = 3;
      root.remove('progression');
      root.remove('savedAt');
      data = jsonEncode(root);
      final loaded = await store.load();
      expect(loaded.coins, 33);
      expect(loaded.gems, 9);
      expect(loaded.progress.commands.values.single.tree, isEmpty);
      await store.save(loaded);
      expect((await store.load()).coins, 33);
    },
  );
  test(
    'noncombat purchases never change initial CP and crew upgrades never add sailors',
    () {
      final v = createCaribbean()..coins = 1000000000;
      final s = v.ships.first;
      final cp = v.progress.combatPower(s);
      v.buyTree(s.id, CommandTrack.portRelations);
      v.buyTree(s.id, CommandTrack.portRelations);
      for (final t in [FleetTrack.offline]) {
        v.buyFleetTree(t);
      }
      expect(v.progress.combatPower(s), cp);
      final crew = s.crewCount;
      for (var i = 0; i < 1000; i++) {
        v.buyTree(s.id, CommandTrack.crew);
      }
      expect(s.crewCount, crew);
      expect(s.crewEffectiveness, 1.2);
    },
  );
}
