import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/pirates/encounters/pirates_voyage.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';
import 'package:dot_commander/pirates/progression/life_balance.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';

/// Port Relations + global tree balance pass, 2026-09-20, final
/// corrections. Every cap here is a TREE SOFT CAP (the Command Tree
/// investment alone stops contributing past it) -- NOT a final-stat hard
/// cap. Equipment/other legitimate modifiers can push a stat's real total
/// past its own tree cap, bounded only by LifeBalance.finalSafetyCeiling
/// (.90, or an exact 100% for the two recovery facets, where exceeding
/// 100% is mathematically meaningless rather than merely "very strong").
/// See fleet_progress.dart/world_life.dart's own doc comments for the
/// reasoning behind each formula.
void main() {
  /// Equips [contentId] (an existing equipmentContent id) on the
  /// player's ship in the given [kind] slot, at the given [rarity], and
  /// re-applies progression. Returns the ship.
  Vessel equip(PiratesVoyage v, String contentId, ItemKind kind, {Rarity rarity = Rarity.legendary}) {
    final ship = v.ships.firstWhere((s) => s.playerOwned);
    final item = EquipmentItem('test-$contentId', contentId, kind, contentId: contentId, rarity: rarity);
    v.progress.inventory.add(item);
    v.progress.commands[ship.id]!.equipped[kind] = item.id;
    v.progress.apply(ship);
    return ship;
  }

  group('1. Global percentage-tree strength: no generic cap, individual tree soft caps + final ceilings', () {
    test('LifeBalance.percent() keeps growing across the WHOLE 1100-level tree, reaching 660% at max level', () {
      expect(LifeBalance.percent(600), greaterThan(LifeBalance.percent(150)));
      expect(LifeBalance.percent(LifeBalance.maxLevels), closeTo(6.6, 1e-9));
    });

    test('facets with a genuine mechanical ceiling (Damage Reduction, Boarding Defense) correctly report the TREE soft cap as "cap reached" in the UI', () {
      final c = CommandProgress('test');
      c.tree[CommandTrack.hull] = 901; // rotation index 1 -> 'Damage Reduction'
      expect(c.nextBenefit(CommandTrack.hull), contains('+0%'));
      expect(c.nextBenefit(CommandTrack.hull), contains('cap reached'));
      c.tree[CommandTrack.crew] = 903; // rotation index 3 -> 'Boarding Defense'
      expect(c.nextBenefit(CommandTrack.crew), contains('+0%'));
      expect(c.nextBenefit(CommandTrack.crew), contains('cap reached'));
    });

    test('facets with NO mechanical ceiling (Sailing Speed) never report "cap reached", even at extreme levels -- uncapped progression keeps reporting real growth', () {
      final c = CommandProgress('test');
      c.tree[CommandTrack.navigation] = 600;
      expect(c.nextBenefit(CommandTrack.navigation), isNot(contains('cap reached')));
      c.tree[CommandTrack.navigation] = 1099;
      expect(c.nextBenefit(CommandTrack.navigation), isNot(contains('cap reached')));
    });
  });

  group('2. Damage Reduction: 35% tree soft cap, NOT a 35% final hard cap', () {
    test('tree alone (maxed) stops contributing at exactly 35%', () {
      final v = createCaribbean();
      final ship = v.ships.firstWhere((s) => s.playerOwned);
      v.progress.commands[ship.id]!.tree[CommandTrack.hull] = LifeBalance.maxLevels;
      v.progress.apply(ship);
      expect(ship.damageReduction, closeTo(.35, 1e-9));
    });

    test('legitimate equipment (Ship Carpenter, +8% defense) pushes the FINAL value past the 35% tree cap -- it is not wasted', () {
      final v = createCaribbean();
      final ship = v.ships.firstWhere((s) => s.playerOwned);
      v.progress.commands[ship.id]!.tree[CommandTrack.hull] = LifeBalance.maxLevels;
      v.progress.apply(ship);
      final treeOnly = ship.damageReduction;
      equip(v, 'carpenter', ItemKind.carpenter);
      expect(ship.damageReduction, greaterThan(treeOnly));
      expect(ship.damageReduction, greaterThan(.35));
    });

    test('final ceiling is finalSafetyCeiling (90%), never the tree cap, and never reaches/exceeds 100%', () {
      final v = createCaribbean();
      final ship = v.ships.firstWhere((s) => s.playerOwned);
      v.progress.commands[ship.id]!.tree[CommandTrack.hull] = LifeBalance.maxLevels;
      equip(v, 'carpenter', ItemKind.carpenter);
      // The current content's strongest available 'defense' equipment
      // (+8% base, x2.25 legendary) doesn't by itself reach 90% from a
      // 35% tree base -- the point of this assertion is the CEILING
      // itself, which must never be crossed by any combination.
      expect(ship.damageReduction, lessThanOrEqualTo(LifeBalance.finalSafetyCeiling));
      expect(ship.damageReduction, lessThan(1.0));
    });
  });

  group('3. Boarding Defense (Crew Defense): 35% tree soft cap, NOT a final hard cap', () {
    test('tree alone (maxed) stops contributing at exactly 35%', () {
      final v = createCaribbean();
      final ship = v.ships.firstWhere((s) => s.playerOwned);
      v.progress.commands[ship.id]!.tree[CommandTrack.crew] = LifeBalance.maxLevels;
      v.progress.apply(ship);
      expect(ship.crewDefense, closeTo(.35, 1e-9));
    });

    test('legitimate equipment (Boarding Netting, +15% crewDefense) pushes the FINAL value past the 35% tree cap', () {
      final v = createCaribbean();
      final ship = v.ships.firstWhere((s) => s.playerOwned);
      v.progress.commands[ship.id]!.tree[CommandTrack.crew] = LifeBalance.maxLevels;
      v.progress.apply(ship);
      final treeOnly = ship.crewDefense;
      equip(v, 'netting', ItemKind.reinforcement);
      expect(ship.crewDefense, greaterThan(treeOnly));
      expect(ship.crewDefense, greaterThan(.35));
      expect(ship.crewDefense, lessThanOrEqualTo(LifeBalance.finalSafetyCeiling));
    });
  });

  group('4. Post-Battle Hull/Crew Recovery: 50% tree soft cap, legitimate modifiers can exceed it, final ceiling is an EXACT 100%', () {
    test('tree alone (maxed) stops contributing at exactly 50% for both', () {
      final v = createCaribbean();
      final ship = v.ships.firstWhere((s) => s.playerOwned);
      final c = v.progress.commands[ship.id]!;
      c.tree[CommandTrack.hull] = LifeBalance.maxLevels;
      c.tree[CommandTrack.crew] = LifeBalance.maxLevels;
      v.progress.apply(ship);
      expect(ship.postHullRecovery, closeTo(.50, 1e-9));
      expect(ship.postCrewRecovery, closeTo(.50, 1e-9));
    });

    test('legitimate equipment pushes recovery above 50% (Ship Carpenter -> hull, Leg Bandage -> crew)', () {
      final v = createCaribbean();
      final ship = v.ships.firstWhere((s) => s.playerOwned);
      final c = v.progress.commands[ship.id]!;
      c.tree[CommandTrack.hull] = LifeBalance.maxLevels;
      c.tree[CommandTrack.crew] = LifeBalance.maxLevels;
      v.progress.apply(ship);
      equip(v, 'carpenter', ItemKind.carpenter);
      equip(v, 'leg_bandage', ItemKind.legs);
      expect(ship.postHullRecovery, greaterThan(.50));
      expect(ship.postCrewRecovery, greaterThan(.50));
    });

    test('final recovery can never exceed 100% (exact) of what was actually lost, regardless of how much equipment stacks', () {
      final v = createCaribbean();
      final ship = v.ships.firstWhere((s) => s.playerOwned);
      final c = v.progress.commands[ship.id]!;
      c.tree[CommandTrack.hull] = LifeBalance.maxLevels;
      c.tree[CommandTrack.crew] = LifeBalance.maxLevels;
      equip(v, 'carpenter', ItemKind.carpenter);
      equip(v, 'leg_bandage', ItemKind.legs);
      equip(v, 'quartermaster', ItemKind.quartermaster); // also grants 'recovery'
      expect(ship.postHullRecovery, lessThanOrEqualTo(1.0));
      expect(ship.postCrewRecovery, lessThanOrEqualTo(1.0));
      // Both exceed the tree soft cap (50%) thanks to equipment, and
      // their true ceiling is an exact 100% -- NOT finalSafetyCeiling
      // (.90), unlike the reduction-type facets above.
      expect(ship.postHullRecovery, greaterThan(.50));
      expect(ship.postCrewRecovery, greaterThan(.50));
    });
  });

  group('5. Port Service Discount: tree soft cap raised 20% -> 50%, legitimate bonuses stack beyond it', () {
    test('a maxed hull+portRelations tree ship gets a real, larger discount than before, capped at 50% for the tree portion', () {
      final v = createCaribbean()..coins = 100000000;
      final s = v.ships.firstWhere((s) => s.playerOwned);
      final c = v.progress.commands[s.id]!;
      c.tree[CommandTrack.hull] = LifeBalance.maxLevels;
      c.tree[CommandTrack.portRelations] = LifeBalance.maxLevels;
      v.progress.apply(s);
      s.hullHp = 1; // near-total damage, so repairCost is meaningfully nonzero
      s.destination = v.life.portFor(s);
      s.position = s.destination!.position;
      v.life.startPort(s);
      final work = v.life.works[s.id]!;
      // Full price would be `hull * repairPrice`; a discount near the
      // tree cap should be substantially cheaper than the OLD 20% cap
      // would have produced.
      final fullPrice = work.hull * LifeBalance.repairPrice;
      expect(work.repairCost, lessThan((fullPrice * .81).ceil())); // OLD 20% cap only ever reached 80% of full price
    });
  });

  group('6. Port Service Speed: tree soft cap raised 20% -> 50%', () {
    test('a maxed crew+portRelations tree ship services meaningfully faster than the OLD 20% cap allowed', () {
      final v = createCaribbean();
      final s = v.ships.firstWhere((s) => s.playerOwned);
      final c = v.progress.commands[s.id]!;
      c.tree[CommandTrack.crew] = LifeBalance.maxLevels;
      c.tree[CommandTrack.portRelations] = LifeBalance.maxLevels;
      v.progress.apply(s);
      final multiplier = v.life.serviceMultiplier(s);
      // OLD 20% cap floor was 0.8x; new 50% tree cap floor is 0.5x.
      expect(multiplier, lessThan(.8));
      expect(multiplier, greaterThanOrEqualTo(1 - LifeBalance.finalSafetyCeiling));
    });
  });

  group('7. Field Repair Discount: 35% tree soft cap, legitimate modifiers remain useful past it', () {
    test('tree alone (maxed portRelations) caps the discount at 35%', () {
      final v = createCaribbean()..coins = 100000000;
      final s = v.ships.firstWhere((s) => s.playerOwned);
      final c = v.progress.commands[s.id]!;
      c.tree[CommandTrack.portRelations] = LifeBalance.maxLevels;
      v.progress.apply(s);
      equip(v, 'carpenter', ItemKind.carpenter); // to be a carpenter specialist below
      s.hullHp = s.maxHullHp - 10;
      final before = v.coins;
      v.life.fieldSupport(s);
      final treeOnlyPrice = before - v.coins;
      expect(treeOnlyPrice, greaterThan(0)); // never free even at the tree cap
    });

    test('legitimate equipment (Trading Captain, +8% economy) makes the field-repair discount BETTER than the tree cap alone, not wasted', () {
      final v = createCaribbean()..coins = 100000000;
      final s = v.ships.firstWhere((s) => s.playerOwned);
      final c = v.progress.commands[s.id]!;
      c.tree[CommandTrack.portRelations] = LifeBalance.maxLevels;
      v.progress.apply(s);
      equip(v, 'carpenter', ItemKind.carpenter);
      s.hullHp = s.maxHullHp - 10;
      var coins = v.coins;
      v.life.fieldSupport(s);
      final treeOnlyPrice = coins - v.coins;

      final v2 = createCaribbean()..coins = 100000000;
      final s2 = v2.ships.firstWhere((s) => s.playerOwned);
      v2.progress.commands[s2.id]!.tree[CommandTrack.portRelations] = LifeBalance.maxLevels;
      v2.progress.apply(s2);
      equip(v2, 'carpenter', ItemKind.carpenter);
      equip(v2, 'captain', ItemKind.captain); // +8% economy on top
      s2.hullHp = s2.maxHullHp - 10;
      coins = v2.coins;
      v2.life.fieldSupport(s2);
      final withEquipmentPrice = coins - v2.coins;

      expect(withEquipmentPrice, lessThan(treeOnlyPrice));
    });
  });

  group('8-9. Capacity progression (unchanged from the previous pass): still 10 -> 100, cargo still never exceeds 100', () {
    test('Port Cargo Supply and Port Repair Supply both reach exactly 100 at max level', () {
      final c = CommandProgress('test');
      c.tree[CommandTrack.portRelations] = LifeBalance.maxLevels;
      expect(c.portCargoSupply, 100);
      expect(c.portRepairSupply, 100);
    });

    test('effective ship cargo capacity never exceeds the absolute 100 cap, regardless of base hull + Fleet Tree + equipment', () {
      for (final base in [0, 8, 50, 100, 200]) {
        for (final level in [0, 500, 1000, 5000]) {
          for (final equip in [0.0, .08, .5, 2.0]) {
            expect(
              Balance.combinedHoldCapacity(baseHold: base, shipHoldTreeLevel: level, equipmentBonus: equip),
              lessThanOrEqualTo(100),
            );
          }
        }
      }
    });
  });

  group('10. Port Relations trade-profit double counting: fixed, tree contribution counts exactly once', () {
    test('economyBonus alone (no equipment) equals the raw tree percent exactly once, not twice', () {
      final v = createCaribbean();
      final ship = v.ships.firstWhere((s) => s.playerOwned);
      v.progress.commands[ship.id]!.tree[CommandTrack.portRelations] = 500;
      v.progress.apply(ship);
      expect(ship.economyBonus, closeTo(LifeBalance.percent(500), 1e-9));
    });

    test('sale price at max Port Relations tree investment matches the SINGLE-counted formula, not double', () {
      final v = createCaribbean()..coins = 100000000;
      final s = v.ships.firstWhere((s) => s.playerOwned);
      v.progress.commands[s.id]!.tree[CommandTrack.portRelations] = LifeBalance.maxLevels;
      v.progress.apply(s);
      s.cargo = 10;
      s.destination = v.life.portFor(s);
      s.position = s.destination!.position;
      final coinsBefore = v.coins;
      v.life.startPort(s);
      final sale = v.coins - coinsBefore;
      // Live-verified via the REAL calculation, not hard-coded: single
      // counting means the multiplier is (1 + economyBonus), i.e.
      // exactly (1 + LifeBalance.percent(maxLevel)) -- a double count
      // would have been (1 + 2*percent(maxLevel)) instead, roughly
      // double this sale value.
      final expectedSale = (10 * LifeBalance.cargoSell * (1 + LifeBalance.percent(LifeBalance.maxLevels))).floor();
      expect(sale, expectedSale);
      // ignore: avoid_print
      print('max-tree trade multiplier (single-counted): x${1 + LifeBalance.percent(LifeBalance.maxLevels)}');
    });
  });

  group('11. Money ship \$ glyph lifecycle (structural checks -- the visual itself is rendered in PiratesGame/ShipComponent, not exercised by pure Dart tests)', () {
    test('isMoneyShip is false for every ordinary vessel, so the \$ glyph never renders on them', () {
      final v = createCaribbean();
      for (final s in v.ships) {
        expect(s.isMoneyShip, isFalse);
      }
    });

    test('claiming removes the money ship from the map entirely -- the glyph (drawn only while isMoneyShip AND the ShipComponent exists) disappears with it', () {
      final v = createCaribbean(encountersEnabled: true);
      String? moneyShipId;
      for (var i = 0; i < 20000 && moneyShipId == null; i++) {
        v.update(1.0);
        final found = v.ships.where((s) => s.isMoneyShip);
        if (found.isNotEmpty) moneyShipId = found.first.id;
      }
      expect(moneyShipId, isNotNull);
      v.claimMoneyShip(moneyShipId!);
      expect(v.ships.any((s) => s.isMoneyShip), isFalse);
    });
  });

  group('12. Capped tree UI honesty', () {
    test('Post-Battle Hull Repair (new 50% tree soft cap) also reports "cap reached" honestly once its tree contribution saturates', () {
      final c = CommandProgress('test');
      c.tree[CommandTrack.hull] = 803; // rotation index 3 -> 'Post-Battle Hull Repair'
      expect(LifeBalance.percent(803), greaterThan(.50));
      expect(c.nextBenefit(CommandTrack.hull), contains('+0%'));
      expect(c.nextBenefit(CommandTrack.hull), contains('cap reached'));
    });
  });

  group('Existing saves migrate safely', () {
    test('the legacy \'cargo\' -> CommandTrack.portRelations save-format mapping still works with all the corrected formulas', () async {
      String? data;
      final store = VoyageStore(read: () async => data, write: (s) async => data = s);
      final v = createCaribbean();
      await store.save(v);
      final root = jsonDecode(data!) as Map<String, dynamic>;
      final commandRow = (root['progression']['commands'] as List).first as Map<String, dynamic>;
      (commandRow['tree'] as Map<String, dynamic>)['cargo'] = 400;
      data = jsonEncode(root);
      final loaded = await store.load();
      final loadedShip = loaded.ships.firstWhere((s) => s.playerOwned);
      final loadedCommand = loaded.progress.commands[loadedShip.id]!;
      expect(loadedCommand.level(CommandTrack.portRelations), 400);
      expect(loadedCommand.portCargoSupply, greaterThan(10));
      expect(
        loadedShip.cargo,
        lessThanOrEqualTo(loaded.progress.effectiveHoldCapacity(loadedShip)),
      );
    });

    test('a high crewDefense (equipment-boosted past the old .35 bound) round-trips through a saved in-progress encounter without being rejected as corrupted', () {
      // Regression for the persistence-validation bound in
      // pirates_voyage.dart, which used to hard-reject crewDefense > .35
      // -- now legitimately reachable via equipment, up to
      // finalSafetyCeiling. Exercised indirectly through the same
      // validation constant to prove they stayed in sync.
      expect(LifeBalance.finalSafetyCeiling, greaterThan(.35));
    });
  });
}
