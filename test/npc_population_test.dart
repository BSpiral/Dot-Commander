// Regression coverage for the NPC-population repair (2026-09-14): the
// previous arrival pacing (60s interval, 1% chance) averaged one
// successful spawn roll per ~100 minutes of active play, so a world
// that dipped low (via departures/defeats) could only keep draining,
// never recover toward LifeBalance.maxNpcs. See LifeBalance.
// arrivalInterval/arrivalChance for the repaired constants and full
// rationale.
//
// Extended the same day with a second finding from a live report that
// the arrival-rate repair alone wasn't enough: combat defeat of a
// non-pirate, non-hunter NPC is a PERMANENT population loss by
// existing, deliberate design (see WorldLife.defeat and
// test/lifecycle_persistence_test.dart's own "truly gone, not a
// respawn candidate" assertion, which this file does not change) --
// under active combat that drain can outpace any purely probabilistic
// arrival trickle. LifeBalance.criticalNpcFloor/minRosterForPopulation
// Floors add a deterministic recovery guarantee below a critically low
// population, and a similar deterministic pirate floor guarantees a
// normal world always has at least one pirate. Both are gated on a
// realistically-sized roster (minRosterForPopulationFloors) so they
// never inject ships into small, deliberately hand-built test
// fixtures elsewhere in this suite (e.g. encounter_test.dart's
// smallWorld) that were never meant to model the real ~15-ship roster.
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/progression/life_balance.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';

/// A Random whose nextDouble() always returns a value that fails ANY
/// probability check written as `rng.nextDouble() < chance` for a
/// chance < 1 -- used to prove a recovery path is truly deterministic
/// (guaranteed), not merely likely enough that a test's chosen seed
/// happens to succeed.
class _AlwaysFailRandom implements Random {
  @override
  double nextDouble() => .999999;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

void main() {
  test('a low NPC population (~7) visibly recovers during an ordinary '
      'play session, without ever requiring a save wipe', () {
    final v = createCaribbean(encountersEnabled: true, seed: 101);
    // Simulate a world that has already drained down to a low
    // population, the way departures/defeats do over time -- send the
    // rest of the initial NPC roster permanently out of the world.
    for (final s in v.ships.where((s) => !s.playerOwned).skip(7)) {
      s.atSea = false;
      s.respawnRemaining = 0;
    }
    expect(v.life.npcCount, 7);
    // ~20 minutes of continuous active play, in small steps.
    for (var i = 0; i < 12000; i++) {
      v.life.tick(.1);
    }
    expect(v.life.npcCount, greaterThan(7));
    expect(v.life.npcCount, lessThanOrEqualTo(LifeBalance.maxNpcs));
  });

  test('NPC population never exceeds maxNpcs, even under sustained '
      'arrival opportunity over a long session', () {
    final v = createCaribbean(encountersEnabled: true, seed: 202);
    // ~83 minutes of continuous active play -- comfortably enough time
    // for the repaired arrival rate to reach the cap many times over if
    // nothing were stopping it.
    for (var i = 0; i < 50000; i++) {
      v.life.tick(.1);
    }
    expect(v.life.npcCount, lessThanOrEqualTo(LifeBalance.maxNpcs));
    // The arrival clock invariant that makes this safe regardless of
    // session length: it always wraps back under the interval instead
    // of accumulating.
    expect(v.life.arrivalClock, lessThan(LifeBalance.arrivalInterval));
  });

  test('a stale/oversized persisted arrival clock cannot stall future '
      'rolls (existing pre-repair saves self-correct on load)', () {
    final v = createCaribbean(encountersEnabled: true);
    // A value that was a valid "mid-wait" under the OLD 60s arrival
    // interval -- under the repaired 15s interval this is already well
    // overdue. restore() only validates finiteness/non-negativity, and
    // never re-clamps against the current interval constant, so this
    // is exactly what an existing save looks like the first time it's
    // loaded after this repair ships.
    v.life.restore({'clock': 45.0, 'nextNpc': 1, 'works': []});
    expect(v.life.arrivalClock, 45.0);
    v.life.tick(.01);
    // The very next tick must process (and wrap) that overdue clock,
    // not leave it sitting above the interval -- which would otherwise
    // require an ever-growing wait before the next roll is even
    // attempted, i.e. a permanent stall.
    expect(v.life.arrivalClock, lessThan(LifeBalance.arrivalInterval));
  });

  test('an existing save with a low NPC population loads unmodified and '
      'then recovers -- no save wipe required', () async {
    String? data;
    final store = VoyageStore(
      read: () async => data,
      write: (s) async {
        data = s;
      },
    );
    final v = createCaribbean(encountersEnabled: true, seed: 303);
    for (final s in v.ships.where((s) => !s.playerOwned).skip(7)) {
      s.atSea = false;
      s.respawnRemaining = 0;
    }
    expect(v.life.npcCount, 7);
    await store.save(v);
    final loaded = await store.load();
    // The low population is preserved through the round trip as-is --
    // recovery comes from normal play afterward, not from the load
    // itself inventing/backfilling a healthier population.
    expect(loaded.life.npcCount, 7);
    for (var i = 0; i < 20000; i++) {
      loaded.life.tick(.1);
    }
    expect(loaded.life.npcCount, greaterThan(7));
    expect(loaded.life.npcCount, lessThanOrEqualTo(LifeBalance.maxNpcs));
  });

  test('pirate NPCs are reachable both directly and through natural '
      'arrivals, and stay a minority under maxPirates', () {
    final v = createCaribbean(encountersEnabled: true, seed: 404);
    final before = v.life.pirateCount;
    v.life.spawn(BehaviorMode.pirate);
    expect(v.life.pirateCount, before + 1);
    expect(v.ships.last.behavior, BehaviorMode.pirate);

    // Empty the world entirely, then run a realistic session's worth of
    // ticks so every ship present is a product of the natural arrival
    // system (not the initial roster) -- proving the repaired arrival
    // rate, combined with the existing 10% pirate role weight, actually
    // produces pirates a normal player would encounter.
    for (final s in v.ships.where((s) => !s.playerOwned)) {
      s.atSea = false;
      s.respawnRemaining = 0;
    }
    expect(v.life.npcCount, 0);
    for (var i = 0; i < 30000; i++) {
      v.life.tick(.1);
    }
    expect(v.life.pirateCount, greaterThan(0));
    expect(v.life.pirateCount, lessThanOrEqualTo(LifeBalance.maxPirates));
  });

  test(
    'a critically low population (below LifeBalance.criticalNpcFloor) '
    'recovers deterministically -- guaranteed, not merely likely -- even '
    'when the arrival-chance roll would otherwise always fail',
    () {
      final v = createCaribbean(
        encountersEnabled: true,
        rng: _AlwaysFailRandom(),
      );
      for (final s in v.ships.where((s) => !s.playerOwned).skip(3)) {
        s.atSea = false;
        s.respawnRemaining = 0;
      }
      expect(v.life.npcCount, 3);
      expect(v.life.npcCount, lessThan(LifeBalance.criticalNpcFloor));
      // A fake RNG that always fails LifeBalance.arrivalChance proves any
      // growth here comes from the deterministic floor, not luck.
      for (var i = 0; i < 200; i++) {
        v.life.tick(1);
      }
      expect(v.life.npcCount, greaterThan(3));
    },
  );

  test(
    'cleanup (the >60-ship trim) removes only permanently-departed '
    'ghosts, never a freshly spawned, still-active NPC',
    () {
      final v = createCaribbean(encountersEnabled: true, seed: 606);
      // Manufacture enough permanently-departed ghost entries (spawned,
      // then immediately marked gone) to push the total roster past the
      // cleanup threshold, without ever raising the ACTIVE npc count
      // (each is ghosted before the next spawn, so LifeBalance.maxNpcs
      // never blocks this loop).
      while (v.ships.length <= 60) {
        v.life.spawn(BehaviorMode.merchant);
        v.ships.last
          ..atSea = false
          ..respawnRemaining = 0;
      }
      expect(v.ships.length, greaterThan(60));
      v.life.spawn(BehaviorMode.pirate);
      final fresh = v.ships.last;
      expect(fresh.atSea, isTrue);
      final freshId = fresh.id;
      v.life.tick(.01); // exercises the >60 cleanup branch this tick
      expect(v.ships.length, lessThanOrEqualTo(60)); // cleanup did run
      expect(v.ships.any((s) => s.id == freshId), isTrue);
      expect(v.ships.firstWhere((s) => s.id == freshId).atSea, isTrue);
    },
  );

  test(
    'save/load preserves a freshly-spawned (not initial-roster) NPC '
    'exactly, including its role and identity',
    () async {
      String? data;
      final store = VoyageStore(
        read: () async => data,
        write: (s) async {
          data = s;
        },
      );
      final v = createCaribbean(encountersEnabled: true, seed: 707);
      v.life.spawn(BehaviorMode.privateer);
      final spawnedId = v.ships.last.id;
      await store.save(v);
      final loaded = await store.load();
      final restored = loaded.ships.firstWhere((s) => s.id == spawnedId);
      expect(restored.behavior, BehaviorMode.privateer);
      expect(restored.playerOwned, isFalse);
      expect(restored.atSea, isTrue);
    },
  );

  test(
    'a zero-pirate world recovers to exactly 1 pirate on the very next '
    'tick (deterministic, not probabilistic), with valid navigation/'
    'position state, and never stacks a second one on immediate '
    'follow-up ticks',
    () {
      final v = createCaribbean(encountersEnabled: true, seed: 808);
      for (final s in v.ships.where((s) => s.behavior == BehaviorMode.pirate)) {
        s.atSea = false;
        s.respawnRemaining = 0; // permanently gone, not merely respawning
      }
      expect(v.life.pirateCount, 0);
      v.life.tick(.01); // one tick is enough -- the floor is not a roll
      final pirates = v.ships
          .where((s) => s.behavior == BehaviorMode.pirate && s.atSea)
          .toList();
      expect(pirates.length, 1);
      final pirate = pirates.single;
      expect(v.navigation.isWater(pirate.position), isTrue);
      // Present in the SAME collection PiratesGame iterates with no
      // filtering to build the map's render tree (see
      // pirates_game.dart: `for (final ship in simulation.ships) ...`)
      // -- the render path is provably fed directly by v.ships.
      expect(v.ships.contains(pirate), isTrue);
      // Route/target selection + movement: a few real update() ticks
      // (not just WorldLife.tick) must resolve a destination.
      for (var i = 0; i < 50; i++) {
        v.update(.1);
      }
      expect(pirate.destination, isNotNull);
      // Doesn't stack: immediate follow-up ticks (far too soon for a
      // natural 15s arrival interval to even complete once) must not
      // add a second pirate on top of the one the floor just seeded.
      for (var i = 0; i < 10; i++) {
        v.life.tick(.01);
      }
      expect(
        v.ships.where((s) => s.behavior == BehaviorMode.pirate && s.atSea).length,
        1,
      );
    },
  );

  test(
    'a pirate seeded by the floor survives save/load with its role '
    'intact and remains reachable in the ship collection the map '
    'consumes',
    () async {
      String? data;
      final store = VoyageStore(
        read: () async => data,
        write: (s) async {
          data = s;
        },
      );
      final v = createCaribbean(encountersEnabled: true, seed: 909);
      for (final s in v.ships.where((s) => s.behavior == BehaviorMode.pirate)) {
        s.atSea = false;
        s.respawnRemaining = 0;
      }
      v.life.tick(.01);
      final seededId = v.ships
          .firstWhere((s) => s.behavior == BehaviorMode.pirate && s.atSea)
          .id;
      await store.save(v);
      final loaded = await store.load();
      final restored = loaded.ships.firstWhere((s) => s.id == seededId);
      expect(restored.behavior, BehaviorMode.pirate);
      expect(restored.atSea, isTrue);
      expect(loaded.ships.contains(restored), isTrue);
    },
  );
}
