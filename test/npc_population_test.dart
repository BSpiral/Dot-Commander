// Regression coverage for the NPC-population repair (2026-09-14): the
// previous arrival pacing (60s interval, 1% chance) averaged one
// successful spawn roll per ~100 minutes of active play, so a world
// that dipped low (via departures/defeats) could only keep draining,
// never recover toward LifeBalance.maxNpcs. See LifeBalance.
// arrivalInterval/arrivalChance for the repaired constants and full
// rationale.
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/progression/life_balance.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';

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
}
