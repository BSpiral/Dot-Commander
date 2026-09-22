import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/pirates/economy/port_economy.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';

void main() {
  test(
    'offline cap is earned from 4h through 6h to 8h, bounded at all levels',
    () {
      final p = createCaribbean().progress;
      expect(p.offlineCapMinutes, 240);
      expect(p.offlineCapLabel, '4h 0m');
      p.tree[FleetTrack.offline] = 500;
      expect(p.offlineCapMinutes, 360);
      p.tree[FleetTrack.offline] = 1000;
      expect(p.offlineCapMinutes, 480);
      expect(Balance.offlineCapMinutes(10000), 480);
      expect(Balance.offlineCapMinutes(-1), 240);
    },
  );
  test('offline payout calculation uses earned cap after reload', () async {
    var now = DateTime.utc(2026);
    String? data;
    final store = VoyageStore(
      now: () => now,
      read: () async => data,
      write: (s) async {
        data = s;
      },
    );
    final v = createCaribbean();
    v.progress.tree[FleetTrack.offline] = 500; // cap only, see Saturday repair pass 2026-09-20
    final fleetRate = Balance.fleetCoinsPerHour(v.ships);
    await store.save(v);
    now = now.add(const Duration(hours: 12)); // beyond the 6h cap this tree level earns
    final loaded = await store.load();
    final expectedReward = Balance.offlineRewardCoins(
      offlineTreeLevel: 500,
      elapsedMinutes: 12 * 60,
      fleetCoinsPerHour: fleetRate,
    );
    expect(expectedReward, greaterThan(0));
    expect(loaded.coins, expectedReward);
    expect(loaded.progress.offlineCapMinutes, 360);
    expect((await store.load()).coins, expectedReward);
  });
  test(
    'repair and recruitment quotes have explicit baselines and modifier inputs',
    () {
      expect(PortEconomy.repair(7), 7);
      expect(PortEconomy.repair(7, multiplier: .5), 4);
      expect(PortEconomy.recruitment(12), 12);
      expect(PortEconomy.recruitment(12, multiplier: .5), 6);
      expect(PortEconomy.sale(4), 8);
      expect(PortEconomy.sale(4, multiplier: 2), 16);
    },
  );
  test(
    'all eight chest choices restrict category and retain duplicates/prices',
    () {
      var choices = 0;
      for (final category in ChestCategory.values) {
        for (final rarity in ChestKind.values) {
          choices++;
          final v = createCaribbean()..gems = 100000;
          for (var i = 0; i < 100; i++) {
            final before = v.gems;
            final item = v.openChest(
              rarity,
              category: category,
              random: Random(i),
            )!;
            expect(category.accepts(item.kind), isTrue);
            expect(before - v.gems, rarity == ChestKind.common ? 10 : 50);
          }
          // Same-seed determinism is checked on a FRESH voyage (no prior
          // inventory), not the one that just accumulated 100 items above
          // -- auto-merge (mergeDuplicates) means roll()'s returned item
          // can legitimately differ between two otherwise-identical seeds
          // once enough matching duplicates already exist in inventory,
          // so that accumulated state is not a fair determinism check.
          // Both rolls share ONE fresh voyage (so their ids come from the
          // same counter and are genuinely comparable), each with its own
          // independent Random(9) -- proving the SAME seed reproduces the
          // same roll content while still being two distinct physical
          // copies (different ids).
          final fresh = createCaribbean()..gems = 100000;
          final a = fresh.openChest(rarity, category: category, random: Random(9))!;
          final b = fresh.openChest(rarity, category: category, random: Random(9))!;
          expect(a.name, b.name);
          expect(a.id, isNot(b.id));
        }
      }
      // Ship/combat overhaul pass 2026-09-21: ChestCategory.cannon
      // ("Ordnance") removed -- 4 categories x 2 kinds = 8, matching this
      // test's own title (which already said "eight" even when the
      // actual count here was still 10).
      expect(choices, 8);
    },
  );
  test(
    'v4 migration preserves progression and inventory; v5 cargo/recovery/receipt persist',
    () async {
      String? data;
      final store = VoyageStore(
        read: () async => data,
        write: (s) async {
          data = s;
        },
      );
      final v = createCaribbean()
        ..coins = 123
        ..gems = 90;
      v.buyTree(v.ships.first.id, CommandTrack.hull);
      v.openChest(
        ChestKind.common,
        category: ChestCategory.hull,
        random: Random(8),
      );
      await store.save(v);
      final root = jsonDecode(data!);
      root['version'] = 4;
      for (final s in root['ships']) {
        s.remove('cargo');
        s.remove('recovering');
      }
      data = jsonEncode(root);
      final loaded = await store.load();
      expect(loaded.coins, 122);
      expect(loaded.gems, 80);
      expect(loaded.progress.inventory.length, 1);
      expect(loaded.progress.commands.values.first.level(CommandTrack.hull), 1);
      loaded.ships.first.cargo = 3;
      loaded.ships.first.recovering = true;
      loaded.ships.first.hullHp = 0;
      await store.save(loaded);
      final again = await store.load();
      expect(again.ships.first.cargo, 3);
      expect(again.ships.first.recovering, true);
      expect(again.ships.first.hullHp, 0);
    },
  );
  test(
    'HOTFIX regression: a pre-2026-09-18 save owning Reinforced Keel or '
    'Boarding Netting (saved under the old undifferentiated "equipment" '
    'ItemKind, now split into Rigging/Reinforcement) loads without '
    'throwing, instead of taking down the whole load/autosave path',
    () async {
      String? data;
      final store = VoyageStore(
        read: () async => data,
        write: (s) async {
          data = s;
        },
      );
      await store.save(createCaribbean());
      final root = jsonDecode(data!);
      root['progression']['inventory'] = [
        {
          'id': 'item-1',
          'name': 'Common Reinforced Keel',
          'kind': 'equipment',
          'hull': null,
          'rarity': 'common',
          'bonus': 0.0,
          'set': null,
          'specialist': null,
          'content': 'keel',
        },
        {
          'id': 'item-2',
          'name': 'Common Boarding Netting',
          'kind': 'equipment',
          'hull': null,
          'rarity': 'common',
          'bonus': 0.0,
          'set': null,
          'specialist': null,
          'content': 'netting',
        },
      ];
      root['progression']['nextItem'] = 3;
      data = jsonEncode(root);
      final loaded = await store.load();
      expect(loaded.progress.inventory.length, 2);
      expect(
        loaded.progress.inventory.map((i) => i.kind).toSet(),
        {ItemKind.reinforcement},
        reason:
            'both items resolve to their real current kind (Reinforcement), '
            'not the blanket legacy default (Rigging)',
      );
    },
  );
  test(
    'every fifth qualifying port visit grants exactly one gem, persists, and does not affect NPCs',
    () async {
      final v = createCaribbean();
      // Not Merchant: isolates the universal every-5th-visit trickle
      // this test exercises from the SEPARATE merchant-specific
      // dock-streak gem trickle (Balance.merchantDocksPerGem), which
      // would otherwise also fire on this same repeated single-ship
      // dock cycle and double the gem count at their shared 5-visit
      // cadence. See world_life_test.dart for that mechanism's own
      // dedicated coverage.
      final s = v.ships.first..behavior = BehaviorMode.privateer;
      expect(v.progress.visits, 0);
      expect(v.gems, 0);
      void dock() {
        s.destination = v.life.portFor(s);
        s.position = s.destination!.position;
        v.life.startPort(s);
        // Finish the port-work state machine so the next call is a fresh
        // arrival, not a same-visit no-op re-entry.
        while (v.life.works.containsKey(s.id)) {
          v.life.tick(999);
        }
      }

      for (var i = 1; i <= 4; i++) {
        dock();
        expect(v.progress.visits, i);
        expect(v.gems, 0, reason: 'no gem before the 5th visit');
      }
      dock();
      expect(v.progress.visits, 5);
      expect(v.gems, 1, reason: 'exactly one gem on the 5th visit');
      for (var i = 6; i <= 9; i++) {
        dock();
        expect(v.gems, 1, reason: 'no extra gem before the 10th visit');
      }
      dock();
      expect(v.progress.visits, 10);
      expect(v.gems, 2, reason: 'exactly one more gem on the 10th visit');

      // A non-player (NPC) arrival must not consume the player's visit count.
      final npc = v.ships.firstWhere((s) => !s.playerOwned);
      npc.destination = v.life.portFor(npc);
      npc.position = npc.destination!.position;
      v.life.startPort(npc);
      expect(v.progress.visits, 10);
      expect(v.gems, 2);

      String? data;
      final store = VoyageStore(
        read: () async => data,
        write: (str) async {
          data = str;
        },
      );
      await store.save(v);
      final loaded = await store.load();
      expect(loaded.progress.visits, 10);
      expect(loaded.gems, 2);
    },
  );
  test('opening a chest with insufficient gems changes nothing', () {
    final v = createCaribbean()..gems = 5;
    final before = v.progress.inventory.length;
    final reward = v.openChest(
      ChestKind.common,
      category: ChestCategory.hull,
    );
    expect(reward, isNull);
    expect(v.gems, 5);
    expect(v.progress.inventory.length, before);
  });
}
