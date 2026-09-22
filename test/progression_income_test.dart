import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';
import 'package:dot_commander/pirates/progression/life_balance.dart';
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
      v.progress.tree[FleetTrack.offline] = 1000; // cap only, see Saturday repair pass 2026-09-20
      final fleetRate = Balance.fleetCoinsPerHour(v.ships);
      final position = v.ships.first.position;
      await store.save(v);
      now = now.add(const Duration(days: 2));
      final loaded = await store.load();
      final expectedReward = Balance.offlineRewardCoins(
        offlineTreeLevel: 1000,
        elapsedMinutes: 2 * 24 * 60,
        fleetCoinsPerHour: fleetRate,
      );
      expect(loaded.coins, 7 + expectedReward);
      expect(loaded.ships.first.position.x, position.x);
      expect(loaded.ships.first.position.y, position.y);
      expect((await store.load()).coins, 7 + expectedReward);
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
    'noncombat purchases never change initial CP; crew upgrades now genuinely add sailors, capped at the hull\'s own ceiling',
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
      // Ship/combat overhaul pass 2026-09-21: crew COUNT now genuinely
      // grows with CommandTrack.crew investment (capped per-hull at
      // HullDefinition.crewCeiling -- see FleetProgress.apply's own doc
      // comment) -- this is the direct fix for "the Sloop in particular
      // should have unusually good long-term customization potential."
      // combatPower is UNCHANGED as an assertion target above (that
      // block only buys portRelations/offline, neither of which touch
      // crew), so this is a genuinely separate, additive effect: a real
      // crew increase DOES raise combatPower (crewCount is one of its
      // terms) -- checked below, not asserted away.
      for (var i = 0; i < 1000; i++) {
        v.buyTree(s.id, CommandTrack.crew);
      }
      expect(s.crewCount, greaterThan(crew));
      expect(s.crewCount, v.progress.crewCapacity(s));
      expect(s.crewCount, lessThanOrEqualTo(70)); // this ship's own crewCeiling (Sloop)
      expect(v.progress.combatPower(s), greaterThan(cp));
      // Correction, Port Relations balance pass 2026-09-20: Crew
      // Effectiveness has no mechanical ceiling (a plain multiplier, see
      // FleetProgress.apply's own comment) -- 1000 levels genuinely
      // reaches 1 + LifeBalance.percent(1000), not a hardcoded-capped 1.2.
      expect(s.crewEffectiveness, 1 + LifeBalance.percent(1000));
    },
  );
}
