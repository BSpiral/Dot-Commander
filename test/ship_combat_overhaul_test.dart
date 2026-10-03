import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/core/movement/point.dart';
import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/pirates/encounters/encounter_result.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';
import 'package:dot_commander/pirates/progression/life_balance.dart';
import 'package:dot_commander/pirates/ships/hull_catalog.dart';
import 'package:dot_commander/pirates/theater/result_script.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/world/npc_navigation.dart';
import 'package:dot_commander/ui/theater/deck_theater.dart';

/// Ship/combat overhaul pass 2026-09-21: focused tests for the revised
/// hull roster, cargo/crew hull-identity ceilings, the Firepower
/// increment fix, the cannon-combat-HUD authoritative-damage fix, the
/// boarding lane/occupancy assignment, the cargo-pressure selling AI
/// fix, pirate/hunter recruitment damping, and encounter-weighting
/// rebalance. See test/content_npc_test.dart, test/encounter_test.dart,
/// test/offline_progression_test.dart, test/world_life_test.dart,
/// test/live_playtest_repair_pass_test.dart, test/economy_test.dart,
/// test/monetization_test.dart, test/playtest_polish_test.dart, and
/// test/port_relations_balance_test.dart for pre-existing coverage that
/// this pass updated in place rather than duplicating here.

Vessel _vessel(
  String id, {
  String hull = 'Sloop',
  BehaviorMode role = BehaviorMode.pirate,
  bool owned = false,
  double x = 300,
  double y = 300,
}) {
  final h = hullFor(hull);
  return Vessel(
    id: id,
    name: id,
    captain: 'Captain $id',
    hullType: hull,
    position: Point2(x, y),
    speed: h.baseSpeed,
    maxHullHp: h.hp,
    crewCount: h.crew,
    behavior: role,
    playerOwned: owned,
  )..firepower = h.guns;
}

void main() {
  group('1. Revised hull roster: exact base stats', () {
    test('explicitly-specified existing hulls match the design brief exactly', () {
      final schooner = hullFor('Schooner');
      expect(schooner.baseSpeed, 58);
      expect(schooner.hp, 85);
      expect(schooner.crew, 25);
      expect(schooner.guns, 3);

      final cog = hullFor('Cog');
      expect(cog.baseSpeed, 38);
      expect(cog.hp, 130);
      expect(cog.crew, 35);
      expect(cog.guns, 4);
      expect(cog.holds, 15);

      final brig = hullFor('Brig');
      expect(brig.baseSpeed, 45);
      expect(brig.hp, 150);
      expect(brig.crew, 70);
      expect(brig.guns, 8);
      expect(brig.holds, 8);

      final galley = hullFor('Galley');
      expect(galley.baseSpeed, 32);
      expect(galley.hp, 175);
      expect(galley.crew, 60);
      expect(galley.guns, 3);
      expect(galley.holds, 22);
      expect(galley.plankCapacity, 3);

      final fluyt = hullFor('Fluyt');
      expect(fluyt.baseSpeed, 32);
      expect(fluyt.hp, 160);
      expect(fluyt.crew, 50);
      expect(fluyt.guns, 2);
      expect(fluyt.holds, 30);

      final galleon = hullFor('Galleon');
      expect(galleon.baseSpeed, 32);
      expect(galleon.hp, 300);
      expect(galleon.crew, 110);
      expect(galleon.guns, 12);
      expect(galleon.holds, 23);
      expect(galleon.plankCapacity, 3);

      final frigate = hullFor('Frigate');
      expect(frigate.baseSpeed, 45);
      expect(frigate.hp, 200);
      expect(frigate.crew, 90);
      expect(frigate.guns, 15);
      expect(frigate.holds, 5);
      expect(frigate.plankCapacity, 2);

      final manOfWar = hullFor('Man-of-War');
      expect(manOfWar.baseSpeed, 20);
      expect(manOfWar.hp, 360);
      expect(manOfWar.crew, 160);
      expect(manOfWar.guns, 20);
      expect(manOfWar.holds, 8);
      expect(manOfWar.plankCapacity, 5);

      // A Brig and Frigate at the SAME speed is intentional: escape/chase
      // must depend on other factors, not an automatic Brig flight.
      expect(brig.baseSpeed, frigate.baseSpeed);
    });

    test('Pirogue keeps its 75 speed and stays a fragile escape/courier hull, not a combat ship', () {
      final pirogue = hullFor('Pirogue');
      expect(pirogue.baseSpeed, 75);
      expect(pirogue.hp, lessThan(hullFor('Sloop').hp));
      expect(pirogue.guns, lessThan(hullFor('Sloop').guns));
    });

    test('Man-of-War is not made faster -- still the slowest hull, real counterplay', () {
      final manOfWar = hullFor('Man-of-War');
      for (final h in hullCatalog) {
        if (h.name == 'Man-of-War') continue;
        expect(manOfWar.baseSpeed, lessThanOrEqualTo(h.baseSpeed));
      }
    });
  });

  group('2. New normal hulls: Longship, Knarr, Corbita', () {
    test('Longship is a boarding specialist -- more crew, far fewer guns than the Brig it contrasts with', () {
      final longship = hullFor('Longship');
      expect(longship.baseSpeed, 43);
      expect(longship.hp, 150);
      expect(longship.crew, 80);
      expect(longship.guns, 2);
      expect(longship.holds, 8);
      expect(longship.plankCapacity, 3);
      expect(longship.masts, 1);
      final brig = hullFor('Brig');
      expect(longship.crew, greaterThan(brig.crew));
      expect(longship.guns, lessThan(brig.guns));
    });

    test('Knarr is a merchant-raider -- real cargo, not replacing Longship/Cog/Galley/Fluyt', () {
      final knarr = hullFor('Knarr');
      expect(knarr.baseSpeed, 38);
      expect(knarr.hp, 170);
      expect(knarr.crew, 55);
      expect(knarr.guns, 4);
      expect(knarr.holds, 18);
      expect(knarr.plankCapacity, 2);
      expect(knarr.masts, 1);
    });

    test('Corbita sits cleanly between Cog and Galley in the cargo progression', () {
      final cog = hullFor('Cog'), corbita = hullFor('Corbita'), galley = hullFor('Galley');
      expect(corbita.baseSpeed, 35);
      expect(corbita.hp, 145);
      expect(corbita.crew, 40);
      expect(corbita.guns, 3);
      expect(corbita.holds, 18);
      expect(corbita.masts, 2);
      expect(corbita.holds, greaterThan(cog.holds));
      expect(corbita.holds, lessThan(galley.holds));
    });
  });

  group('3. Caravel: late-game merchant flagship', () {
    test('exact stats, and the full merchant cargo staircase Cog < Corbita < Galley < Fluyt < Caravel', () {
      final caravel = hullFor('Caravel');
      expect(caravel.baseSpeed, 27);
      expect(caravel.hp, 250);
      expect(caravel.crew, 75);
      expect(caravel.guns, 8);
      expect(caravel.holds, 40);
      expect(caravel.plankCapacity, 2);
      expect(caravel.masts, 3);

      final order = ['Cog', 'Corbita', 'Galley', 'Fluyt', 'Caravel'].map((n) => hullFor(n).holds).toList();
      for (var i = 1; i < order.length; i++) {
        expect(order[i], greaterThan(order[i - 1]), reason: 'merchant cargo progression must strictly increase');
      }
      expect(order, [15, 18, 22, 30, 40]);
    });

    test('Caravel is not the best combat ship -- Frigate/Galleon/Man-of-War all outgun it', () {
      final caravel = hullFor('Caravel');
      for (final name in ['Frigate', 'Galleon', 'Man-of-War']) {
        expect(caravel.guns, lessThan(hullFor(name).guns));
      }
      // Brig/Frigate can both catch it (faster).
      expect(hullFor('Brig').baseSpeed, greaterThan(caravel.baseSpeed));
      expect(hullFor('Frigate').baseSpeed, greaterThan(caravel.baseSpeed));
    });
  });

  group('4. Xebec: Legendary hull foundation', () {
    test('Xebec is the only hull gated above common rarity', () {
      final xebec = hullFor('Xebec');
      expect(xebec.minRollRarityIndex, Rarity.legendary.index);
      for (final h in hullCatalog) {
        if (h.name == 'Xebec') continue;
        expect(h.minRollRarityIndex, 0, reason: '${h.name} must remain obtainable at any rarity, exactly like before this pass');
      }
    });

    test('Xebec has real, meaningful weaknesses -- not simply a faster Man-of-War', () {
      final xebec = hullFor('Xebec'), manOfWar = hullFor('Man-of-War'), frigate = hullFor('Frigate');
      expect(xebec.baseSpeed, greaterThan(frigate.baseSpeed), reason: 'exceptional speed is its whole identity');
      expect(xebec.hp, lessThan(manOfWar.hp));
      expect(xebec.hp, lessThan(frigate.hp), reason: 'constrained HP -- wins by controlling range, not by tanking');
      expect(xebec.holds, lessThan(hullFor('Cog').holds), reason: 'not an economic ship');
      expect(xebec.guns, lessThanOrEqualTo(frigate.guns), reason: 'dangerous, but not simply the best gunned ship too');
    });

    test('a Common/Paid-Common Hull Chest roll can never produce Xebec -- Xebec is not a key in either hull table at all (balance lock 2026-10-03)', () {
      expect(hullTableAdCommonBp.containsKey('Xebec'), isFalse);
      expect(hullTablePaidCommonBp.containsKey('Xebec'), isFalse);
      for (final source in [RollSource.adCommon, RollSource.paidCommon]) {
        final ship = _vessel('p', owned: true);
        final progress = FleetProgress([ship]);
        for (var seed = 0; seed < 300; seed++) {
          final item = progress.roll(ChestKind.common, Random(seed), category: ChestCategory.hull, source: source);
          if (item.kind == ItemKind.hull) {
            expect(item.hullType, isNot('Xebec'));
          }
        }
      }
    });

    test('a genuine Legendary Xebec is reachable through the Rare Chest roll pipeline, and is ALWAYS Legendary (finalized balance lock 2026-10-03: narrow Xebec rarity-override rule)', () {
      expect(hullTableRareBp.containsKey('Xebec'), isTrue);
      final ship = _vessel('p', owned: true);
      final progress = FleetProgress([ship]);
      var foundXebec = false;
      for (var seed = 0; seed < 2000 && !foundXebec; seed++) {
        final item = progress.roll(ChestKind.rare, Random(seed), category: ChestCategory.hull, source: RollSource.paidRare);
        if (item.kind == ItemKind.hull && item.hullType == 'Xebec') {
          foundXebec = true;
          // Finalized balance lock 2026-10-03: Xebec is the game's only
          // current Legendary hull, so a Xebec pull always overrides the
          // independently-rolled rarity to Legendary -- 'Fine Xebec'/
          // 'Masterwork Xebec' must never occur (see roll()'s own doc
          // comment for why this is a narrow override, not a return to
          // rarity-first/rarity-gated hull eligibility).
          expect(item.name, 'Legendary Xebec');
          expect(item.rarity, Rarity.legendary);
        }
      }
      expect(foundXebec, isTrue, reason: 'Xebec is reachable within a reasonable number of Rare Chest rolls under its 100bp (1%) table weight');
    });
  });

  group('5. Cargo progression: hull identity survives equipment investment (Fleet-wide Ship Hold tree retired)', () {
    test('a fully equipment-invested Pirogue can never approach Fluyt/Caravel cargo territory (the reported 52+ cargo bug)', () {
      final ship = _vessel('p', hull: 'Pirogue', owned: true, role: BehaviorMode.merchant);
      final progress = FleetProgress([ship]);
      ship.holdBonus = 5.0; // absurdly generous equipment bonus -- the only cargo-growth lever left
      progress.apply(ship);
      final capacity = progress.effectiveHoldCapacity(ship);
      expect(capacity, lessThanOrEqualTo(hullFor('Pirogue').cargoCeiling));
      expect(capacity, lessThan(20), reason: 'nowhere near Fluyt (55 ceiling) or Caravel (90 ceiling) territory');
    });

    test('a Fluyt/Caravel with a real equipped Cargo Hold Extension genuinely grows well past its own base hold', () {
      for (final hull in ['Fluyt', 'Caravel']) {
        final ship = _vessel('p', hull: hull, owned: true, role: BehaviorMode.merchant);
        final progress = FleetProgress([ship]);
        // apply() recomputes holdBonus from EQUIPPED items every call
        // (never trusts a directly-set field, same as every other
        // secondary stat) -- equip the real 'cargo_hold' Reinforcement
        // item (+15% base, x2.25 at Legendary rarity = +33.75%). A
        // non-Sloop hull's own FleetProgress constructor already auto
        // -equips a synthetic "Legacy $hull" item under id 'item-1' (see
        // FleetProgress's own constructor) -- this item's id must be
        // genuinely unique, or `item(id)` would silently resolve back to
        // THAT unrelated hull item instead (same id, first match wins).
        final item = EquipmentItem('test-cargo-hold', 'Legendary Cargo Hold Extension', ItemKind.reinforcement, rarity: Rarity.legendary, contentId: 'cargo_hold');
        progress.inventory.add(item);
        progress.commands[ship.id]!.equipped[ItemKind.reinforcement] = item.id;
        progress.apply(ship);
        final capacity = progress.effectiveHoldCapacity(ship);
        expect(capacity, greaterThan(hullFor(hull).holds), reason: '$hull must genuinely benefit from investment');
        expect(capacity, lessThanOrEqualTo(hullFor(hull).cargoCeiling));
      }
    });

    test('FleetTrack.shipHold is retired -- setting it has no effect on cargo capacity at all', () {
      final ship = _vessel('p', hull: 'Fluyt', owned: true, role: BehaviorMode.merchant);
      final progress = FleetProgress([ship]);
      progress.apply(ship);
      final before = progress.effectiveHoldCapacity(ship);
      progress.tree[FleetTrack.shipHold] = Balance.maxLevel;
      progress.apply(ship);
      expect(progress.effectiveHoldCapacity(ship), before);
    });

    test('buyFleetTree no longer offers FleetTrack.shipHold as a purchase at all', () {
      final v = createCaribbean()..coins = 1000000000;
      expect(v.buyFleetTree(FleetTrack.shipHold), isFalse);
      expect(v.progress.tree.containsKey(FleetTrack.shipHold), isFalse);
    });

    test('combinedHoldCapacity never exceeds min(100, cargoCeiling) for any combination of inputs', () {
      for (final ceiling in [10, 45, 90, 150]) {
        for (final base in [2, 20, 40]) {
          for (final equip in [0.0, .5, 3.0]) {
            final result = Balance.combinedHoldCapacity(
              baseHold: base,
              cargoCeiling: ceiling,
              equipmentBonus: equip,
            );
            expect(result, lessThanOrEqualTo(min(100, ceiling)));
          }
        }
      }
    });
  });

  group('6. Crew growth: the Sloop "wonder ship" customization ceiling', () {
    test('a fully Command-Tree-invested Sloop reaches roughly 70 crew, far beyond its base of 18', () {
      final ship = _vessel('p', hull: 'Sloop', owned: true);
      final progress = FleetProgress([ship]);
      // Real gameplay calls apply() incrementally as CommandTrack.crew is
      // purchased one level at a time (see PiratesVoyage.buyTree), so a
      // fresh ship's crew is always at 100% of ITS CURRENT capacity the
      // whole way up. Establish that real baseline (tree=0, crewFraction
      // 18/18=1.0) BEFORE jumping the tree, matching how a real ship
      // actually reaches this state rather than materializing crew out
      // of thin air in one synthetic jump.
      progress.apply(ship);
      expect(ship.crewCount, 18);
      progress.commands[ship.id]!.tree[CommandTrack.crew] = LifeBalance.maxLevels;
      progress.apply(ship);
      expect(progress.crewCapacity(ship), 70);
      expect(ship.crewCount, 70);
    });

    test('other hulls have much less proportional crew-growth headroom than the Sloop', () {
      for (final hull in ['Cog', 'Frigate', 'Galleon']) {
        final ship = _vessel('p', hull: hull, owned: true);
        final progress = FleetProgress([ship]);
        progress.commands[ship.id]!.tree[CommandTrack.crew] = LifeBalance.maxLevels;
        progress.apply(ship, preserveDamage: false);
        final growthRatio = progress.crewCapacity(ship) / hullFor(hull).crew;
        expect(growthRatio, lessThan(70 / 18), reason: '$hull must not out-grow the Sloop proportionally');
      }
    });

    test('crew losses survive a hull swap proportionally, even once crew has grown past the hull\'s raw base', () {
      final ship = _vessel('p', hull: 'Sloop', owned: true);
      final progress = FleetProgress([ship]);
      progress.apply(ship); // establish the real 18/18 baseline first
      progress.commands[ship.id]!.tree[CommandTrack.crew] = LifeBalance.maxLevels;
      progress.apply(ship);
      expect(ship.crewCount, 70);
      ship.crewCount = 35; // exactly half, well ABOVE the raw hull base (18)
      // Re-applying (e.g. after equipping a different hull item) must
      // preserve the 50% fraction against the GROWN capacity, not divide
      // by the raw base (18) and wrongly clamp to 100%.
      progress.apply(ship, preserveDamage: false);
      expect(ship.crewCount, 35);
    });

    test('NPCs (no CommandProgress) get their unmodified hull base crew capacity only', () {
      final ship = _vessel('npc', hull: 'Sloop', owned: false);
      final progress = FleetProgress([ship]);
      expect(progress.crewCapacity(ship), hullFor('Sloop').crew);
    });
  });

  group('7. Firepower increment: +0.1, authoritative and persistent', () {
    test('LifeBalance.firePerUnit is exactly 0.1', () {
      expect(LifeBalance.firePerUnit, .1);
    });

    test('apply() and CommandProgress.nextBenefit agree on the real firepower delta at several levels', () {
      final ship = _vessel('p', hull: 'Sloop', owned: true);
      final progress = FleetProgress([ship]);
      final c = progress.commands[ship.id]!;
      // Even levels only: nextBenefit's headline alternates between
      // 'Firepower' and 'Opening Attack Strength' by level parity (see
      // CommandProgress.nextBenefit's own pattern) -- odd levels would
      // compare against the wrong metric here.
      for (final level in [0, 50, 100, 250, 300]) {
        c.tree[CommandTrack.firepower] = level;
        progress.apply(ship);
        final before = ship.firepower;
        // The UI's own displayed "next level" delta, read BEFORE buying.
        final preDelta = double.parse(RegExp(r'[\d.]+').firstMatch(c.nextBenefit(CommandTrack.firepower))!.group(0)!);
        c.tree[CommandTrack.firepower] = level + 1;
        progress.apply(ship);
        final after = ship.firepower;
        expect((after - before), closeTo(preDelta, 0.001), reason: 'the displayed and actual firepower increment must agree at level $level');
      }
    });

    test('firepower growth survives a save/restore round trip', () {
      final ship = _vessel('p', hull: 'Sloop', owned: true);
      var progress = FleetProgress([ship]);
      progress.commands[ship.id]!.tree[CommandTrack.firepower] = 300;
      progress.apply(ship);
      final firepowerBefore = ship.firepower;
      final saved = progress.toJson();

      final ship2 = _vessel('p', hull: 'Sloop', owned: true);
      final restored = FleetProgress([ship2]);
      restored.restore(saved, [ship2]);
      restored.apply(ship2);
      expect(ship2.firepower, closeTo(firepowerBefore, 0.0001));
      expect(restored.commands[ship2.id]!.level(CommandTrack.firepower), 300);
    });
  });

  group('8. Cannon combat HUD: bars must show real, progressively-revealed authoritative damage', () {
    Combatant combatant(String id, {bool owned = false, double hullHp = 200, double maxHullHp = 200, int crew = 90}) =>
        Combatant(id, id, 'Frigate', hullHp, maxHullHp, 45, crew, owned, BehaviorMode.pirate);

    test('damage becomes visible partway through the fight (at the cannon-impact keyframe), not frozen at zero until the very end', () {
      final a = combatant('a', owned: true);
      final b = combatant('b');
      final r = EncounterResult(
        id: 'x',
        a: a,
        b: b,
        kind: EncounterKind.cannon,
        winnerId: 'b',
        damageA: 120, // a real, already-decided outcome -- damage never fabricated at render time
        damageB: 20,
        crewLossA: 40,
        crewLossB: 5,
        coins: 0,
        gems: 0,
      );
      final script = scriptForResult(r.playerFirst());
      // The keyframe timeline (see result_script.dart) reveals real
      // damage as a step at the seconds:10 "cannon impact" keyframe --
      // BEFORE this fix, the bars this data now feeds (see
      // ManagementPanel) were bound to the live Vessel instead, which
      // PiratesVoyage._complete only ever mutates once the WHOLE
      // encounter finishes -- i.e. frozen at 0 for the entire fight,
      // then snapping instantly at the very end. This proves the real
      // authoritative damage is now visible well before the fight ends.
      final beforeImpact = script.sample(5).playerDamage.hull;
      final afterImpact = script.sample(12).playerDamage.hull;
      final end = script.sample(r.duration).playerDamage.hull;
      expect(beforeImpact, 0, reason: 'no damage before the ships even close to cannon range');
      expect(afterImpact, closeTo(120 / 200, 0.01), reason: 'the real, authoritative damage fraction must already be visible partway through the fight');
      expect(end, closeTo(afterImpact, 0.0001), reason: 'never regresses or gets fabricated further after the real value is revealed');
    });

    test('EncounterResult.playerFirst normalizes whichever side is actually player-owned into slot a, swapping damage/crew loss together', () {
      final playerSide = combatant('player', owned: true);
      final enemySide = combatant('enemy', owned: false);
      // Player happens to have been captured as slot "b" this time.
      final r = EncounterResult(
        id: 'x',
        a: enemySide,
        b: playerSide,
        kind: EncounterKind.cannon,
        winnerId: null,
        damageA: 5,
        damageB: 55,
        crewLossA: 1,
        crewLossB: 12,
        coins: 0,
        gems: 0,
      );
      final normalized = r.playerFirst();
      expect(normalized.a.id, 'player');
      expect(normalized.a.owned, isTrue);
      expect(normalized.damageA, 55, reason: 'damage must travel WITH the identity it belongs to, not stay in slot A');
      expect(normalized.crewLossA, 12);
    });

    test('a result where slot a is already the player is left untouched (no needless swap)', () {
      final playerSide = combatant('player', owned: true);
      final enemySide = combatant('enemy');
      final r = EncounterResult(
        id: 'x',
        a: playerSide,
        b: enemySide,
        kind: EncounterKind.cannon,
        winnerId: 'player',
        damageA: 3,
        damageB: 40,
        crewLossA: 0,
        crewLossB: 8,
        coins: 2,
        gems: 0,
      );
      expect(identical(r.playerFirst(), r), isTrue);
    });
  });

  group('9. Boarding movement: occupancy-aware lane assignment', () {
    test('crossing dots round-robin across every available lane, never all crammed into lane 0', () {
      const planks = 2;
      final lanesUsed = <int>{};
      for (var i = 1; i < 8; i += 2) {
        // only odd indices actually cross, matching DeckTheater's own rule
        lanesUsed.add(DeckGeometry.laneAssignment(i, planks).index);
      }
      expect(lanesUsed, {0, 1}, reason: 'both lanes must genuinely get used, not just lane 0');
    });

    test('lane index is always within [0, planks) for any dot index', () {
      for (final planks in [1, 2, 3, 5]) {
        for (var i = 0; i < 40; i++) {
          final lane = DeckGeometry.laneAssignment(i, planks);
          expect(lane.index, greaterThanOrEqualTo(0));
          expect(lane.index, lessThan(planks));
        }
      }
    });

    test('queue position within the SAME lane staggers crossing start -- a congested lane visibly queues rather than stacking', () {
      const planks = 1; // forces every crossing dot to share the one lane
      // Only ODD dot indices actually cross (see DeckTheater's own
      // boarding-party rule) -- 1, 3, 5 is the real sequence of crossing
      // dots this function is ever called with.
      final first = DeckGeometry.laneAssignment(1, planks);
      final second = DeckGeometry.laneAssignment(3, planks);
      final third = DeckGeometry.laneAssignment(5, planks);
      expect(first.index, second.index);
      expect(second.index, third.index);
      expect(second.queueDelay, greaterThan(first.queueDelay), reason: 'the 2nd dot queued on this lane must start later than the 1st');
      expect(third.queueDelay, greaterThan(second.queueDelay), reason: 'the 3rd dot queued on this lane must start later than the 2nd');
    });

    test('assignment is deterministic -- the same (i, planks) always produces the same lane and delay', () {
      final a = DeckGeometry.laneAssignment(5, 3);
      final b = DeckGeometry.laneAssignment(5, 3);
      expect(a, b);
    });
  });

  group('10. Cargo-pressure selling AI', () {
    test('a player Pirate ship at/above the shared full-hold pressure threshold is redirected to port instead of seeking a new target', () {
      final v = createCaribbean(encountersEnabled: true);
      final ship = v.ships.firstWhere((s) => s.playerOwned);
      ship.behavior = BehaviorMode.pirate;
      final capacity = v.progress.effectiveHoldCapacity(ship);
      ship.cargo = (capacity * NpcBalance.fullHold).ceil();
      expect(ship.returnToPort, isFalse, reason: 'test setup precondition');
      final destination = v.chooseDestination(ship);
      expect(ship.returnToPort, isTrue);
      expect(destination.kind, DestinationKind.port);
    });

    test('a player Pirate ship with low cargo utilization is NOT redirected -- keeps hunting normally', () {
      final v = createCaribbean(encountersEnabled: true);
      final ship = v.ships.firstWhere((s) => s.playerOwned);
      ship.behavior = BehaviorMode.pirate;
      ship.cargo = 0;
      v.chooseDestination(ship);
      expect(ship.returnToPort, isFalse);
    });

    test('a non-Pirate player ship is never redirected purely by cargo pressure (only Pirate behavior actively hunts prey)', () {
      final v = createCaribbean(encountersEnabled: true);
      final ship = v.ships.firstWhere((s) => s.playerOwned);
      ship.behavior = BehaviorMode.merchant;
      ship.cargo = v.progress.effectiveHoldCapacity(ship);
      v.chooseDestination(ship);
      expect(ship.returnToPort, isFalse);
    });
  });

  group('11. Pirate/hunter ecosystem damping', () {
    test('hunterSpawnCooldown prevents a second recruitment from firing within the same cooldown window', () {
      final v = createCaribbean(encountersEnabled: true);
      for (final s in v.ships) {
        s.behavior = BehaviorMode.merchant;
      }
      for (final s in v.ships.take(8)) {
        s.behavior = BehaviorMode.pirate; // pressure >= hunterThresholds[1] -> required = 2
      }
      v.life.tick(.01);
      expect(v.ships.where((s) => s.hunter && s.atSea).length, 1, reason: 'only one recruitment per cooldown window');
      v.life.tick(1);
      expect(v.ships.where((s) => s.hunter && s.atSea).length, 1, reason: 'still within the cooldown -- no second hunter yet');
      v.life.tick(LifeBalance.hunterSpawnCooldownSeconds);
      expect(v.ships.where((s) => s.hunter && s.atSea).length, 2, reason: 'cooldown elapsed -- the second hunter can now be recruited');
    });

    test('hunterSpawnCooldown persists through a WorldLife save/restore round trip', () {
      final v = createCaribbean(encountersEnabled: true);
      for (final s in v.ships.take(8)) {
        s.behavior = BehaviorMode.pirate;
      }
      v.life.tick(.01);
      expect(v.life.hunterSpawnCooldown, greaterThan(0));
      final saved = v.life.toJson();

      final v2 = createCaribbean(encountersEnabled: true);
      v2.life.restore(saved);
      expect(v2.life.hunterSpawnCooldown, v.life.hunterSpawnCooldown);
    });

    test('an old save with no hunterSpawnCooldown key restores as an already-elapsed (0) cooldown, not a crash', () {
      final v = createCaribbean(encountersEnabled: true);
      final legacy = v.life.toJson()..remove('hunterSpawnCooldown');
      v.life.restore(legacy);
      expect(v.life.hunterSpawnCooldown, 0);
    });
  });

  group('12. Encounter/ship-selection weighting', () {
    test('merchant is by far the most common ambient role; privateer is meaningfully rarer than before', () {
      expect(LifeBalance.roleWeights[BehaviorMode.merchant.index], greaterThan(LifeBalance.roleWeights[BehaviorMode.privateer.index] * 2));
      expect(LifeBalance.roleWeights.reduce((a, b) => a + b), closeTo(1.0, 0.0001));
    });

    test('within the ordinary (non-hunter) Privateer hull pool, Man-of-War is a small minority next to Frigate/Brig, over many spawns', () {
      final v = createCaribbean(encountersEnabled: true);
      final counts = <String, int>{};
      for (var seed = 0; seed < 400; seed++) {
        final fresh = createCaribbean(seed: seed, encountersEnabled: true);
        fresh.life.spawn(BehaviorMode.privateer);
        final spawned = fresh.ships.where((s) => s.behavior == BehaviorMode.privateer && !s.hunter);
        for (final s in spawned) {
          counts[s.hullType] = (counts[s.hullType] ?? 0) + 1;
        }
      }
      final manOfWarCount = counts['Man-of-War'] ?? 0;
      final total = counts.values.fold(0, (a, b) => a + b);
      expect(total, greaterThan(0), reason: 'test setup: privateers must actually have spawned');
      expect(manOfWarCount / total, lessThan(.25), reason: 'Man-of-War should be an occasional threat, not routine traffic');
      expect(v.ships, isNotEmpty); // keep the unused `v` meaningful/no dead import
    });
  });

  group('13. Chest/Ordnance cleanup', () {
    test('ChestCategory has exactly the four canonical categories -- no cannon/Ordnance', () {
      expect(ChestCategory.values.map((c) => c.name).toSet(), {'hull', 'equipment', 'crew', 'officers'});
    });

    test('cannon-kind equipment (shot types) remain obtainable -- now via the Hull chest category, which already spans hullSlots', () {
      expect(ChestCategory.hull.accepts(ItemKind.cannon), isTrue);
      final ship = _vessel('p', owned: true);
      final progress = FleetProgress([ship]);
      var foundCannon = false;
      for (var seed = 0; seed < 100 && !foundCannon; seed++) {
        final item = progress.roll(ChestKind.common, Random(seed), category: ChestCategory.hull, source: RollSource.paidCommon);
        if (item.kind == ItemKind.cannon) foundCannon = true;
      }
      expect(foundCannon, isTrue, reason: 'cannon shot items must still be reachable through the Hull family');
    });

    test('a pre-existing owned cannon-kind item (a real, unaffected ItemKind -- never itself tagged with a ChestCategory in save data) restores cleanly', () {
      // Confirms the removal of ChestCategory.cannon needed no save
      // migration: ChestCategory was NEVER part of EquipmentItem's own
      // persisted shape (see EquipmentItem.toJson/fromJson -- only
      // ItemKind/rarity/hullType/bonus/contentId are stored), so an
      // owned cannon-kind item from any pre-existing save restores
      // exactly as it always did.
      final ship = _vessel('p', owned: true);
      final progress = FleetProgress([ship]);
      final saved = {
        'commands': [
          {'id': ship.id, 'tree': <String, int>{}, 'equipped': <String, String>{}},
        ],
        'tree': <String, int>{},
        'inventory': [
          {
            'id': 'item-1',
            'name': 'Heavy Shot',
            'kind': 'cannon',
            'hull': null,
            'rarity': 'rare',
            'bonus': 0.0,
            'set': null,
            'specialist': null,
            'content': 'heavy',
          },
        ],
        'nextItem': 2,
        'visits': 0,
        'merchantDockStreak': 0,
        'lastRewards': <String>[],
      };
      progress.restore(saved, [ship]);
      expect(progress.inventory.single.kind, ItemKind.cannon);
      expect(progress.inventory.single.rarity, Rarity.rare);
    });
  });

  group('14. FleetTrack.shipHold retirement: real end-to-end old-save safety', () {
    test('a real saved voyage with shipHold investment and cargo that only fit because of it loads without throwing, safely clamped to the new capacity', () async {
      String? data;
      final s = VoyageStore(
        read: () async => data,
        write: (v) async => data = v,
      );
      final voyage = createCaribbean(encountersEnabled: true);
      final ship = voyage.ships.firstWhere((v) => v.playerOwned);
      // Simulate a save written back when shipHold was still purchasable
      // and contributing: a real +50-level investment, and cargo that
      // relied on it (would exceed the ship's post-retirement capacity).
      voyage.progress.tree[FleetTrack.shipHold] = 1000;
      ship.cargo = voyage.progress.effectiveHoldCapacity(ship) + 20;
      await s.save(voyage);

      final loaded = await s.load();
      final loadedShip = loaded.ships.firstWhere((v) => v.playerOwned);
      expect(loadedShip.cargo, lessThanOrEqualTo(loaded.progress.effectiveHoldCapacity(loadedShip)), reason: 'stale over-capacity cargo from a shipHold-inflated old save must be clamped, never crash the load');
      expect(loaded.progress.tree.containsKey(FleetTrack.shipHold), isFalse, reason: 'the stale tree value itself must not linger either');
    });

    test('a save with FleetTrack.shipHold still in its raw tree JSON restores without throwing, and the key is gone afterward', () {
      final ship = _vessel('p', owned: true);
      final progress = FleetProgress([ship]);
      final saved = {
        'commands': [
          {'id': ship.id, 'tree': <String, int>{}, 'equipped': <String, String>{}},
        ],
        'tree': {'shipHold': 1000, 'offline': 400},
        'inventory': <Map<String, dynamic>>[],
        'nextItem': 1,
        'visits': 0,
        'merchantDockStreak': 0,
        'lastRewards': <String>[],
      };
      progress.restore(saved, [ship]);
      expect(progress.tree.containsKey(FleetTrack.shipHold), isFalse);
      expect(progress.tree[FleetTrack.offline], 400, reason: 'unrelated FleetTrack values must be untouched');
    });
  });
}
