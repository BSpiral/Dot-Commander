import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/monetization/monetization_ids.dart';
import 'package:dot_commander/pirates/encounters/pirates_voyage.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';
import 'package:dot_commander/pirates/ships/hull_catalog.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';

/// Live playtest repair pass 2026-09-20 (reward chests, dead Cargo tree,
/// Hull cargo bonuses, Money Ship). See:
/// - monetization_ids.dart / fleet_progress.dart's ChestCategoryContent
///   and FleetProgress.roll for items 1-3 (naming + reward-pool fix);
/// - the deleted lib/ui/management/progression_tracks.dart and
///   port_relations_balance_test.dart's "Existing saves migrate safely"
///   group for item 4 (dead Cargo tree removal);
/// - equipment_content.dart's Cargo Hold Extension and world_life.dart's
///   _advance for item 5 (Hull cargo bonuses / the hidden-cap fix);
/// - pirates_voyage.dart's _tickMoneyShip/claimMoneyShip for item 6
///   (spawn pacing + the real hour-of-earnings reward).
void main() {
  group('Item 1-2: standardized upgrade families and the ad-chest reward pools', () {
    test('the three RewardedAdGroup labels are exactly Hull / Crew Equipment / Officer', () {
      expect(RewardedAdGroup.hull.label, 'Hull');
      expect(RewardedAdGroup.crewEquipment.label, 'Crew Equipment');
      expect(RewardedAdGroup.officersCommon.label, 'Officer');
    });

    test(
      'the Hull ad chest can award more than just brand-new ship hulls -- the '
      'live-play "ship dispenser" bug is fixed: rolling it repeatedly produces '
      'BOTH a hull swap and a cannon/rigging/reinforcement/figurehead item',
      () {
        final p = FleetProgress([]);
        var sawHullSwap = false, sawOtherHullFamilyItem = false;
        for (var seed = 0; seed < 300; seed++) {
          final item = p.roll(
            ChestKind.common,
            Random(seed),
            category: ChestCategory.hull,
            source: RollSource.adCommon,
          );
          if (item.kind == ItemKind.hull) {
            sawHullSwap = true;
          } else {
            sawOtherHullFamilyItem = true;
          }
        }
        expect(sawHullSwap, isTrue, reason: 'a hull swap is still a legitimate Hull upgrade outcome');
        expect(
          sawOtherHullFamilyItem,
          isTrue,
          reason: 'the Hull chest must not be reduced to ONLY ever producing ships',
        );
      },
    );

    test(
      'every RewardedAdGroup (Hull/Crew Equipment/Officer) never awards an item outside its own upgrade family',
      () {
        for (final group in RewardedAdGroup.values) {
          final category = group.chestCategories.single;
          final p = FleetProgress([]);
          for (var seed = 0; seed < 300; seed++) {
            final item = p.roll(
              ChestKind.common,
              Random(seed),
              category: category,
              source: RollSource.adCommon,
            );
            expect(
              category.accepts(item.kind),
              isTrue,
              reason: '${group.label} produced a ${item.kind.name} item ("${item.name}") outside its own family',
            );
          }
        }
      },
    );

    test(
      'the Crew Equipment and Officer ad chests specifically never award a ship hull '
      '(the exact live-play complaint: "produced ships instead of the intended categories")',
      () {
        for (final group in [RewardedAdGroup.crewEquipment, RewardedAdGroup.officersCommon]) {
          final category = group.chestCategories.single;
          final p = FleetProgress([]);
          for (var seed = 0; seed < 300; seed++) {
            final item = p.roll(
              ChestKind.common,
              Random(seed),
              category: category,
              source: RollSource.adCommon,
            );
            expect(item.kind, isNot(ItemKind.hull));
          }
        }
      },
    );
  });

  group('Item 3: gem chests -- naming, pricing, category isolation', () {
    test('the three standardized categories carry the exact family names', () {
      expect(ChestCategory.hull.label, 'Hull');
      expect(ChestCategory.crew.label, 'Crew Equipment');
      expect(ChestCategory.officers.label, 'Officer');
    });

    test('common/rare gem chest prices are exactly 10 and 50 gems, for every category', () {
      expect(Balance.chestCosts[ChestKind.common], 10);
      expect(Balance.chestCosts[ChestKind.rare], 50);
    });

    test(
      'audit: two other chest types still exist beyond the three standardized families '
      '(Equipment = ship rigging/reinforcement/figurehead, Ordnance = cannon ammo types) -- '
      'both remain independently purchasable in the Shop\'s gem grid, untouched by this pass, '
      'and their pools are (now, by construction) subsets of the widened Hull family, not '
      'unrelated leaked content',
      () {
        expect(ChestCategory.values, containsAll([ChestCategory.equipment, ChestCategory.cannon]));
        expect(ChestCategory.equipment.label, 'Equipment');
        expect(ChestCategory.cannon.label, 'Ordnance');
        for (final kind in ItemKind.values) {
          if (ChestCategory.equipment.accepts(kind) || ChestCategory.cannon.accepts(kind)) {
            expect(
              ChestCategory.hull.accepts(kind),
              isTrue,
              reason: 'Equipment/Ordnance content must all fall within the wider Hull family now that Hull spans hullSlots',
            );
          }
        }
      },
    );
  });

  group('Item 4: the dead Cargo/Hold future-progression tree is gone', () {
    test('CommandTrack has no cargo-named track -- only the five real ones', () {
      expect(
        CommandTrack.values.map((t) => t.name),
        {'hull', 'firepower', 'crew', 'navigation', 'portRelations'},
      );
    });
    // The behavioral half of this cleanup (an old save carrying the
    // removed legacy 'cargo' per-ship key now fails to load instead of
    // silently migrating) is covered end-to-end in
    // port_relations_balance_test.dart's "Existing saves migrate safely"
    // group, which exercises the real VoyageStore.load path.
  });

  group('Item 5: Hull cargo bonuses actually affect usable capacity', () {
    test('equipping the Cargo Hold Extension raises effectiveHoldCapacity past the raw hull base', () {
      final v = createCaribbean();
      final ship = v.ships.first; // fresh Sloop, hull.holds == 4
      final baseCapacity = v.progress.effectiveHoldCapacity(ship);
      expect(baseCapacity, hullFor(ship.hullType).holds);

      v.progress.inventory.add(
        const EquipmentItem(
          'item-cargo-1',
          'Fitted Cargo Hold Extension',
          ItemKind.reinforcement,
          contentId: 'cargo_hold',
        ),
      );
      v.progress.nextItem = 2;
      expect(v.equip(ship.id, ItemKind.reinforcement, 'item-cargo-1'), isTrue);

      expect(
        v.progress.effectiveHoldCapacity(ship),
        greaterThan(baseCapacity),
        reason: 'a Hull-family cargo item must genuinely raise usable capacity, not just display text',
      );
    });

    test(
      'the hidden cargo-cap bug is fixed: a ship with a Hull cargo bonus can actually LOAD '
      'more cargo at port than its raw hull base, not just be "allowed" to buy it and then '
      'silently lose the extra on departure',
      () {
        final v = createCaribbean()..coins = 100000;
        final ship = v.ships.first;
        final rawHullHolds = hullFor(ship.hullType).holds;

        v.progress.inventory.add(
          const EquipmentItem(
            'item-cargo-1',
            'Fitted Cargo Hold Extension',
            ItemKind.reinforcement,
            contentId: 'cargo_hold',
          ),
        );
        v.progress.nextItem = 2;
        expect(v.equip(ship.id, ItemKind.reinforcement, 'item-cargo-1'), isTrue);
        final effectiveCapacity = v.progress.effectiveHoldCapacity(ship);
        expect(effectiveCapacity, greaterThan(rawHullHolds));

        ship
          ..hullHp = ship.maxHullHp
          ..crewCount = hullFor(ship.hullType).crew
          ..cargo = 0
          ..destination = v.life.portFor(ship)
          ..position = v.life.portFor(ship).position;
        v.life.startPort(ship);
        // Generous bounded loop (matches this project's other port-flow
        // tests, e.g. world_life_test.dart) rather than computing exact
        // per-phase durations -- just run until the visit completes.
        for (var i = 0; i < 2000 && v.life.works.isNotEmpty; i++) {
          v.life.tick(1);
        }
        expect(v.life.works, isEmpty, reason: 'port visit never completed');

        expect(
          ship.cargo,
          greaterThan(rawHullHolds),
          reason: 'the old bug re-clamped final cargo to the RAW hull base, discarding the paid-for Hull cargo bonus',
        );
        expect(ship.cargo, lessThanOrEqualTo(effectiveCapacity));
      },
    );
  });

  group('Item 6: Money Ship spawn pacing and reward', () {
    test(
      'over a simulated hour, an attentive player sees between 5 and 6 money ships '
      '(the provable bound for a 540s base + 0-120s jitter cooldown across 3600s), '
      'each spaced 540-660s apart -- reasonably even, never a burst, never a drought',
      () {
        final v = createCaribbean(encountersEnabled: true);
        final spawnTimes = <double>[];
        for (var t = 1.0; t <= 3600; t += 1.0) {
          v.update(1.0);
          final found = v.ships.where((s) => s.isMoneyShip);
          if (found.isNotEmpty) {
            spawnTimes.add(t);
            v.claimMoneyShip(found.first.id); // a reasonably attentive player
          }
        }
        expect(spawnTimes.length, inInclusiveRange(5, 6));
        for (var i = 1; i < spawnTimes.length; i++) {
          final gap = spawnTimes[i] - spawnTimes[i - 1];
          expect(
            gap,
            inInclusiveRange(
              Balance.moneyShipCooldownSimSeconds - 1,
              Balance.moneyShipCooldownSimSeconds + Balance.moneyShipCooldownJitterSimSeconds + 1,
            ),
            reason: 'gap #$i ($gap s) fell outside the deterministic cooldown+jitter window -- pacing is bursty/droughty',
          );
        }
      },
    );

    test(
      'the claim reward equals the canonical fleetCoinsPerHour formula, and scales with a stronger fleet -- not a stale flat constant',
      () {
        Vessel moneyShipOn(PiratesVoyage v) {
          for (var i = 0; i < 3000 && v.ships.every((s) => !s.isMoneyShip); i++) {
            v.update(1.0);
          }
          return v.ships.firstWhere((s) => s.isMoneyShip);
        }

        final base = createCaribbean(encountersEnabled: true);
        final baseShip = moneyShipOn(base);
        final baseReward = base.claimMoneyShip(baseShip.id);
        expect(baseReward, Balance.fleetCoinsPerHour(base.ships).round());

        // A strictly stronger fleet (real Port Relations Tree investment,
        // which legitimately raises Vessel.economyBonus through the
        // canonical FleetProgress.apply path -- not a hand-poked field
        // that a later simulation tick could silently overwrite) must
        // earn a strictly larger reward -- proving this is a live
        // computation of the player's OWN fleet, not a fixed number that
        // happens to match once by coincidence.
        final boosted = createCaribbean(encountersEnabled: true)..coins = 100000000;
        final boostedPlayerShip = boosted.ships.firstWhere((s) => s.playerOwned);
        for (var i = 0; i < 500; i++) {
          boosted.buyTree(boostedPlayerShip.id, CommandTrack.portRelations);
        }
        expect(boostedPlayerShip.economyBonus, greaterThan(0));
        final boostedShip = moneyShipOn(boosted);
        final boostedReward = boosted.claimMoneyShip(boostedShip.id);
        expect(boostedReward, Balance.fleetCoinsPerHour(boosted.ships).round());
        expect(boostedReward, greaterThan(baseReward));
        expect(baseReward, isNot(540), reason: 'must not be the old flat constant');
      },
    );
  });
}
