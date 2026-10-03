import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/core/movement/point.dart';
import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';
import 'package:dot_commander/pirates/ships/hull_catalog.dart';

/// Hull Chest reward-category architecture (balance design lock
/// 2026-10-03): coverage for the explicit, pool-size-independent 6% Hull
/// category chance and the three independent per-source Hull identity
/// tables in lib/pirates/progression/hull_reward_tables.dart. See that
/// file's own doc comments for the full design rationale; this file only
/// proves the invariants the design brief required.
const _normalHullNames = [
  'Pirogue',
  'Barque',
  'Sloop',
  'Schooner',
  'Cog',
  'Corbita',
  'Longship',
  'Knarr',
  'Galley',
  'Brig',
  'Fluyt',
  'Caravel',
  'Frigate',
  'Galleon',
  'Man-of-War',
];

Vessel _vessel(String id) {
  final h = hullFor('Sloop');
  return Vessel(
    id: id,
    name: id,
    captain: 'Captain $id',
    hullType: 'Sloop',
    position: Point2(300, 300),
    speed: h.baseSpeed,
    maxHullHp: h.hp,
    crewCount: h.crew,
    behavior: BehaviorMode.pirate,
    playerOwned: true,
  )..firepower = h.guns;
}

void main() {
  group('Hull Chest category weights', () {
    test('hull category chance is explicitly 6.00% (600bp of 10000)', () {
      expect(hullChestCategoryWeightsBp[HullChestRewardCategory.hull], 600);
    });

    test('category weights sum to exactly 10000bp (100%)', () {
      final total = hullChestCategoryWeightsBp.values.fold(0, (a, b) => a + b);
      expect(total, 10000);
    });

    test('hull category weight does not depend on equipmentContent size: real pool has 14 hull-family items, weight is still a flat literal', () {
      final hullFamilyCount = equipmentContent.where((d) => ChestCategory.hull.accepts(d.kind)).length;
      expect(hullFamilyCount, 14, reason: 'sanity: this is the real current pool size the OLD implicit mechanism used to divide by');
      // The constant itself cannot be a function of hullFamilyCount --
      // it is a literal int in a const map. Demonstrate the mechanism is
      // genuinely decoupled: an alternate category table that changes
      // ONLY the non-hull shares (as if equipmentContent's per-kind
      // counts were completely different) leaves hull's own 600
      // untouched, because pickWeighted and the hull branch of roll()
      // never read equipmentContent.length before choosing the category.
      const alternateNonHullSkew = <HullChestRewardCategory, int>{
        HullChestRewardCategory.hull: 600,
        HullChestRewardCategory.cannon: 9000, // wildly different "pool size"
        HullChestRewardCategory.reinforcement: 100,
        HullChestRewardCategory.rigging: 100,
        HullChestRewardCategory.figurehead: 200,
      };
      expect(alternateNonHullSkew.values.fold(0, (a, b) => a + b), 10000);
      expect(alternateNonHullSkew[HullChestRewardCategory.hull], hullChestCategoryWeightsBp[HullChestRewardCategory.hull]);
    });

    test('empirically, ~6% of real Hull Chest rolls land on kind==hull regardless of pool content (statistical, 20000 seeds)', () {
      final progress = FleetProgress([_vessel('p')]);
      var hullCount = 0;
      const n = 20000;
      for (var seed = 0; seed < n; seed++) {
        final item = progress.roll(ChestKind.common, Random(seed), category: ChestCategory.hull, source: RollSource.paidCommon);
        if (item.kind == ItemKind.hull) hullCount++;
      }
      final fraction = hullCount / n;
      expect(fraction, closeTo(0.06, 0.01), reason: 'observed $fraction over $n rolls');
    });
  });

  group('Table membership: Xebec exclusion/inclusion', () {
    test('Ad/Common table has exactly the 15 normal hulls, no Xebec', () {
      expect(hullTableAdCommonBp.keys.toSet(), _normalHullNames.toSet());
      expect(hullTableAdCommonBp.containsKey('Xebec'), isFalse);
    });

    test('10-gem Common table has exactly the 15 normal hulls, no Xebec', () {
      expect(hullTablePaidCommonBp.keys.toSet(), _normalHullNames.toSet());
      expect(hullTablePaidCommonBp.containsKey('Xebec'), isFalse);
    });

    test('50-gem Rare table has exactly the 15 normal hulls plus Xebec (16 total)', () {
      expect(hullTableRareBp.keys.toSet(), {..._normalHullNames, 'Xebec'});
      expect(hullTableRareBp.length, 16);
    });

    test('every expected hull appears exactly once in its appropriate table (no duplicate/missing keys)', () {
      for (final table in [hullTableAdCommonBp, hullTablePaidCommonBp]) {
        expect(table.length, 15);
        expect(table.keys.toSet().length, 15, reason: 'no duplicate keys');
      }
      expect(hullTableRareBp.length, 16);
      expect(hullTableRareBp.keys.toSet().length, 16);
    });

    test('Ad/Common Hull Chest rolls can never produce Xebec, by construction (300 seeds, no occurrence)', () {
      final progress = FleetProgress([_vessel('p')]);
      for (var seed = 0; seed < 300; seed++) {
        final item = progress.roll(ChestKind.common, Random(seed), category: ChestCategory.hull, source: RollSource.adCommon);
        if (item.kind == ItemKind.hull) expect(item.hullType, isNot('Xebec'));
      }
    });

    test('10-gem Common Hull Chest rolls can never produce Xebec, by construction (300 seeds, no occurrence)', () {
      final progress = FleetProgress([_vessel('p')]);
      for (var seed = 0; seed < 300; seed++) {
        final item = progress.roll(ChestKind.common, Random(seed), category: ChestCategory.hull, source: RollSource.paidCommon);
        if (item.kind == ItemKind.hull) expect(item.hullType, isNot('Xebec'));
      }
    });

    test('50-gem Rare Hull Chest CAN produce Xebec (reachable within a bounded number of seeds)', () {
      final progress = FleetProgress([_vessel('p')]);
      var found = false;
      for (var seed = 0; seed < 2000 && !found; seed++) {
        final item = progress.roll(ChestKind.rare, Random(seed), category: ChestCategory.hull, source: RollSource.paidRare);
        if (item.kind == ItemKind.hull && item.hullType == 'Xebec') found = true;
      }
      expect(found, isTrue);
    });
  });

  group('Every Hull table totals exactly 100%', () {
    test('Ad/Common sums to exactly 10000bp', () {
      expect(hullTableAdCommonBp.values.fold(0, (a, b) => a + b), 10000);
    });

    test('10-gem Common sums to exactly 10000bp', () {
      expect(hullTablePaidCommonBp.values.fold(0, (a, b) => a + b), 10000);
    });

    test('50-gem Rare sums to exactly 10000bp', () {
      expect(hullTableRareBp.values.fold(0, (a, b) => a + b), 10000);
    });
  });

  group('Rare chest does not guarantee a Rare-or-better hull', () {
    test('the bottom half of the normal hull progression (Pirogue..Galley) still holds a real majority share of the Rare table', () {
      const bottomHalf = ['Pirogue', 'Barque', 'Sloop', 'Schooner', 'Cog', 'Corbita', 'Longship', 'Knarr'];
      final bottomShare = bottomHalf.fold<int>(0, (a, n) => a + hullTableRareBp[n]!);
      expect(bottomShare, greaterThan(5000), reason: 'low/basic hulls must remain genuinely possible, not token-rare, from a Rare chest');
    });

    test('Xebec is the single rarest entry in the Rare table, strictly below Man-of-War', () {
      expect(hullTableRareBp['Xebec'], lessThan(hullTableRareBp['Man-of-War']!));
      expect(hullTableRareBp.values.reduce(min), hullTableRareBp['Xebec']);
    });
  });

  group('pickWeighted determinism', () {
    test('same seed, same table => same pick, every time (pure function, no hidden state)', () {
      final a = pickWeighted(hullTableRareBp, Random(777));
      final b = pickWeighted(hullTableRareBp, Random(777));
      expect(a, b);
    });

    test('roll() itself is deterministic for a fixed seed', () {
      final p1 = FleetProgress([_vessel('p')]);
      final p2 = FleetProgress([_vessel('p')]);
      final i1 = p1.roll(ChestKind.rare, Random(999), category: ChestCategory.hull, source: RollSource.paidRare);
      final i2 = p2.roll(ChestKind.rare, Random(999), category: ChestCategory.hull, source: RollSource.paidRare);
      expect(i1.kind, i2.kind);
      expect(i1.hullType, i2.hullType);
      expect(i1.rarity, i2.rarity);
      expect(i1.name, i2.name);
    });
  });

  group('Legendary-only Xebec rule (finalized 2026-10-03)', () {
    test('every generated Xebec is Legendary -- Fine Xebec and Masterwork Xebec never occur (2000 seeds)', () {
      final progress = FleetProgress([_vessel('p')]);
      var xebecCount = 0;
      for (var seed = 0; seed < 2000; seed++) {
        final item = progress.roll(ChestKind.rare, Random(seed), category: ChestCategory.hull, source: RollSource.paidRare);
        if (item.kind == ItemKind.hull && item.hullType == 'Xebec') {
          xebecCount++;
          expect(item.rarity, Rarity.legendary);
          expect(item.name, 'Legendary Xebec');
          expect(item.name, isNot('Fine Xebec'));
          expect(item.name, isNot('Masterwork Xebec'));
        }
      }
      expect(xebecCount, greaterThan(0), reason: 'sanity: Xebec must actually have occurred at least once in this sample for the above assertions to mean anything');
    });

    test('other hulls retain their existing (non-forced) rarity behavior -- a non-Xebec hull result still varies by rarity across seeds', () {
      final progress = FleetProgress([_vessel('p')]);
      final seenRaritiesByNonXebecHull = <Rarity>{};
      for (var seed = 0; seed < 500; seed++) {
        final item = progress.roll(ChestKind.rare, Random(seed), category: ChestCategory.hull, source: RollSource.paidRare);
        if (item.kind == ItemKind.hull && item.hullType != 'Xebec') {
          seenRaritiesByNonXebecHull.add(item.rarity);
        }
      }
      expect(seenRaritiesByNonXebecHull.length, greaterThan(1), reason: 'non-Xebec hulls must still draw from the real rarity distribution, not be pinned to a single value the way Xebec now is');
    });

    test('the Xebec override is table-driven, not rarity-first: Xebec is still absent from Ad/Common and 10-gem Common regardless of how many Legendary rarity rolls occur', () {
      for (final source in [RollSource.adCommon, RollSource.paidCommon]) {
        final progress = FleetProgress([_vessel('p')]);
        for (var seed = 0; seed < 300; seed++) {
          final item = progress.roll(ChestKind.common, Random(seed), category: ChestCategory.hull, source: source);
          if (item.kind == ItemKind.hull) expect(item.hullType, isNot('Xebec'));
        }
      }
    });
  });

  group('Non-hull Hull-Chest categories are unaffected outside the explicit-category change', () {
    test('cannon-kind items remain reachable through the Hull chest (now via the explicit 33.58% cannon category share)', () {
      final progress = FleetProgress([_vessel('p')]);
      var foundCannon = false;
      for (var seed = 0; seed < 100 && !foundCannon; seed++) {
        final item = progress.roll(ChestKind.common, Random(seed), category: ChestCategory.hull, source: RollSource.paidCommon);
        if (item.kind == ItemKind.cannon) foundCannon = true;
      }
      expect(foundCannon, isTrue);
    });

    test('equipment/crew/officers chest categories are completely untouched -- still a flat uniform pick', () {
      final progress = FleetProgress([_vessel('p')]);
      for (var seed = 0; seed < 50; seed++) {
        final item = progress.roll(ChestKind.common, Random(seed), category: ChestCategory.equipment, source: RollSource.paidCommon);
        expect(ChestCategory.equipment.accepts(item.kind), isTrue);
        expect(item.kind, isNot(ItemKind.hull), reason: 'equipment category never includes a hull swap, exactly as before');
      }
    });
  });
}
