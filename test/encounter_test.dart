import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/core/movement/point.dart';
import 'package:dot_commander/core/movement/sea_navigation.dart';
import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/pirates/encounters/encounter_result.dart';
import 'package:dot_commander/pirates/encounters/pirates_voyage.dart';
import 'package:dot_commander/pirates/ships/hull_catalog.dart';
import 'package:dot_commander/pirates/ships/crew_representation.dart';
import 'package:dot_commander/pirates/theater/result_script.dart';
import 'package:dot_commander/pirates/theater/battle_script.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';

Vessel ship(
  String id, {
  String hull = 'Brig',
  BehaviorMode mode = BehaviorMode.pirate,
  bool owned = false,
  double x = 100,
}) => Vessel(
  id: id,
  name: id,
  captain: 'Captain $id',
  hullType: hull,
  position: Point2(x, 100),
  speed: 30,
  maxHullHp: hullFor(hull).hp,
  crewCount: hullFor(hull).crew,
  behavior: mode,
  playerOwned: owned,
);
PiratesVoyage smallWorld(List<Vessel> ships) => PiratesVoyage(
  ships: ships,
  places: const [
    Destination('port', 'Port', Point2(300, 300), DestinationKind.port),
  ],
  rng: Random(3),
  navigation: SeaNavigation([]),
  encountersEnabled: true,
  npcDecisions: false,
);
void target(Vessel a, Vessel b) {
  a.destination = Destination(b.id, b.name, b.position, DestinationKind.ship);
}

void main() {
  test(
    'battle lock freezes both voyages for full lifecycle and rejects port work',
    () {
      final a = ship('a', hull: 'Man-of-War'),
          b = ship('b', hull: 'Sloop', x: 105),
          c = ship('c', x: 108);
      target(a, b);
      target(c, b);
      final v = smallWorld([a, b, c]);
      v.update(.01);
      final run = v.active.single;
      final positions = [a.position, b.position];
      final destinations = [a.destination, b.destination];
      final health = [a.hullHp, b.hullHp];
      for (var i = 0; i < 10; i++) {
        v.setBehavior(a, BehaviorMode.explorer);
        v.setBehavior(b, BehaviorMode.merchant);
        v.life.startPort(a);
        v.life.startPort(b);
        scriptForResult(run.result).sample(run.result.duration);
        v.update(run.result.duration / 11);
        expect(v.active, hasLength(1));
        expect([a.position, b.position], positions);
        expect([a.destination, b.destination], destinations);
        expect([a.hullHp, b.hullHp], health);
        expect(a.activity, Activity.engaged);
        expect(b.activity, Activity.engaged);
        expect(v.life.works.containsKey(a.id), isFalse);
        expect(v.life.works.containsKey(b.id), isFalse);
        expect(v.busy(a.id) && v.busy(b.id), isTrue);
      }
      v.update(run.result.duration / 11 + .01);
      expect(v.active, isEmpty);
      expect(a.activity, Activity.sailing);
      expect(v.busy(a.id), isFalse);
      expect(a.behavior, BehaviorMode.explorer);
      expect(b.atSea, isFalse);
    },
  );
  for (final service in [false, true]) {
    for (final dockAttacker in [false, true]) {
      test(
        'no port combat: timed service=$service attacker docked=$dockAttacker',
        () {
          final a = ship('a', mode: BehaviorMode.privateer),
              b = ship('b', x: 105);
          final v = smallWorld([a, b]);
          final docked = dockAttacker ? a : b;
          docked.activity = Activity.docked;
          docked.pauseRemaining = 100;
          docked.destination = v.places.first;
          if (service) v.life.startPort(docked);
          target(a, b);
          if (dockAttacker) a.activity = Activity.docked;
          if (!dockAttacker) {
            expect(v.chooseDestination(a).kind, isNot(DestinationKind.ship));
          }
          v.update(.01);
          expect(v.active, isEmpty);
          expect(v.combatAvailable(docked), isFalse);
          expect(docked.activity, Activity.docked);
        },
      );
    }
  }
  test(
    'post-fight recovery restores only fresh damage and hunter returns to port',
    () {
      final a = ship('hunter', hull: 'Man-of-War', mode: BehaviorMode.privateer)
        ..hunter = true
        ..postHullRecovery = .2;
      a.hullHp -= 10;
      final b = ship('pirate', hull: 'Sloop', x: 105);
      final v = smallWorld([a, b]);
      target(a, b);
      v.update(.01);
      final r = v.active.single.result;
      expect(r.winnerId, a.id);
      final expected = a.hullHp - (r.a.id == a.id ? r.damageA : r.damageB) * .8;
      v.update(r.duration);
      expect(a.hullHp, closeTo(expected, .000001));
      expect(a.maxHullHp - a.hullHp, greaterThan(10));
      expect(a.returnToPort, isTrue);
      expect(a.destination!.kind, DestinationKind.port);
      expect(b.atSea, isFalse);
      expect(b.respawnRemaining, 60);
      final hp = a.hullHp;
      v.update(.01);
      expect(a.hullHp, hp);
    },
  );
  test('boarding defeat exhausts crew while leaving positive Hull', () {
    final a = ship('a'), b = ship('b')..crewCount = 45;
    final r = const PrototypeResolver().resolve(
      'boarding',
      Combatant.capture(a),
      Combatant.capture(b),
    );
    expect(r.kind, EncounterKind.boarding);
    expect(r.winnerId, a.id);
    expect(r.crewLossB, b.crewCount);
    expect(r.damageB, lessThan(b.hullHp));
  });
  test('plank capacity belongs to hull and uses lower capacity', () {
    final expected = {
      'Sloop': 1,
      'Schooner': 1,
      'Brig': 2,
      'Frigate': 2,
      'Galley': 3,
      'Man-of-War': 5,
    };
    for (final a in expected.entries) {
      for (final b in expected.entries) {
        expect(hullFor(a.key).plankCapacity, a.value);
        final result = EncounterResult(
          id: 'x',
          a: Combatant.capture(ship('a', hull: a.key)),
          b: Combatant.capture(ship('b', hull: b.key)),
          kind: EncounterKind.boarding,
          winnerId: 'a',
          damageA: 0,
          damageB: 0,
          crewLossA: 0,
          crewLossB: 0,
          coins: 0,
          gems: 0,
        );
        expect(result.planks, min(a.value, b.value));
        expect(scriptForResult(result).frames.last.planks, result.planks);
      }
    }
  });
  test(
    'representatives are bounded, scale slowly, and respect surviving crew',
    () {
      expect(representativeCount('Sloop', 18), 6);
      // Ship/combat overhaul pass 2026-09-21: Brig's own crew base rose
      // 55 -> 70 (see hull_catalog.dart) -- 50/70 crew is proportionally
      // slightly less than full strength, so this now lands at 11 (still
      // near its 12-dot representativeCap), not a full 12.
      expect(representativeCount('Brig', 50), 11);
      expect(representativeCount('Brig', 250), 12);
      expect(representativeCount('Man-of-War', 2000), 20);
      expect(representativeCount('Man-of-War', 2000, importantCrew: 50), 20);
      expect(representativeCount('Sloop', 1), 1);
      expect(representativeCount('Sloop', 0), 0);
    },
  );
  test(
    'resolver deterministic cannon victory favors hull loss over crew loss',
    () {
      final a = Combatant.capture(ship('a', hull: 'Man-of-War', owned: true));
      final b = Combatant.capture(ship('b', hull: 'Sloop'));
      const resolver = PrototypeResolver();
      final r = resolver.resolve('x', a, b);
      expect(r.kind, EncounterKind.cannon);
      expect(r.winnerId, 'a');
      expect(r.coins, 2);
      expect(r.gems, 1);
      expect(r.damageB / b.maxHullHp, greaterThan(r.crewLossB / b.crew));
      expect(r.planks, 0);
      expect(resolver.resolve('x', a, b).toJson(), r.toJson());
    },
  );
  test('boarding emphasizes crew damage and draw awards nothing', () {
    final a = ship('a', owned: true), b = ship('b');
    b.crewCount = 45;
    final r = const PrototypeResolver().resolve(
      'x',
      Combatant.capture(a),
      Combatant.capture(b),
    );
    expect(r.kind, EncounterKind.boarding);
    expect(r.crewLossB / r.b.crew, greaterThan(r.damageB / r.b.maxHullHp));
    final draw = const PrototypeResolver().resolve(
      'y',
      Combatant.capture(a),
      Combatant.capture(ship('c')),
    );
    expect(draw.winnerId, isNull);
    expect(draw.coins, 0);
  });
  test(
    'fast peaceful defender escapes without boarding and without rewards',
    () {
      final a = ship('a', hull: 'Man-of-War'),
          b = Vessel(
            id: 'b',
            name: 'b',
            captain: 'b',
            hullType: 'Sloop',
            position: const Point2(105, 100),
            speed: 100,
            maxHullHp: 80,
            crewCount: 18,
            behavior: BehaviorMode.merchant,
          );
      b.fleeing = true;
      final r = const PrototypeResolver().resolve(
        'x',
        Combatant.capture(a),
        Combatant.capture(b),
      );
      expect(r.kind, EncounterKind.escape);
      expect(r.escapedId, 'b');
      expect(r.winnerId, isNull);
      expect(r.coins, 0);
      expect(
        scriptForResult(r).frames.any((f) => f.phase == TheaterPhase.boarding),
        isFalse,
      );
    },
  );
  test(
    'hostile meeting starts, holds ships, resolves first and applies once',
    () {
      final a = ship('a', hull: 'Man-of-War', owned: true),
          b = ship('b', hull: 'Sloop', x: 105);
      target(a, b);
      final sim = smallWorld([a, b]);
      sim.update(.01);
      expect(sim.active, hasLength(1));
      final run = sim.active.single;
      final hp = b.hullHp;
      expect(sim.busy('a'), isTrue);
      expect(a.activity, Activity.engaged);
      final script = scriptForResult(run.result);
      for (var i = 0; i < 100; i++) {
        script.sample(i.toDouble());
      }
      expect(b.hullHp, hp);
      expect(sim.coins, 0); // Renderer/seek never applies result.
      final pos = a.position;
      sim.update(1);
      expect(a.position, pos);
      sim.setBehavior(a, BehaviorMode.explorer);
      expect(a.activity, Activity.engaged);
      sim.update(run.result.duration);
      expect(sim.active, isEmpty);
      expect(b.hullHp, hp - run.result.damageB);
      expect(sim.coins, 2);
      expect(sim.gems, 1);
      expect(a.behavior, BehaviorMode.explorer);
      sim.update(1);
      expect(sim.coins, 2);
      expect(sim.ships, hasLength(2));
    },
  );
  test(
    'busy participant cannot join a second battle and allies cannot fight',
    () {
      final a = ship('a'), b = ship('b', x: 105), c = ship('c', x: 108);
      target(a, b);
      target(c, b);
      final sim = smallWorld([a, b, c]);
      sim.update(.01);
      expect(sim.active, hasLength(1));
      expect(sim.busy('c'), isFalse);
      final x = ship('x', owned: true), y = ship('y', owned: true, x: 105);
      target(x, y);
      final allies = smallWorld([x, y]);
      allies.update(.01);
      expect(allies.active, isEmpty);
    },
  );
  test('peaceful and privateer roles only initiate relevant encounters', () {
    for (final role in [
      BehaviorMode.merchant,
      BehaviorMode.explorer,
      BehaviorMode.privateer,
    ]) {
      final a = ship('a', mode: role),
          b = ship('b', mode: BehaviorMode.merchant, x: 105);
      target(a, b);
      final sim = smallWorld([a, b]);
      sim.update(.01);
      expect(sim.active, isEmpty);
    }
    final a = ship('a', mode: BehaviorMode.privateer), b = ship('b', x: 105);
    target(a, b);
    final sim = smallWorld([a, b]);
    sim.update(.01);
    expect(sim.active, hasLength(1));
  });
  test(
    'active save resumes immutable result, applies once, and reward receipt survives reload',
    () async {
      String? saved;
      final store = VoyageStore(
        read: () async => saved,
        write: (s) async {
          saved = s;
        },
      );
      final sim = createCaribbean(encountersEnabled: true);
      final a = sim.ships.first, b = sim.ships[1];
      a.position = const Point2(200, 240);
      b.position = const Point2(205, 240);
      a.behavior = BehaviorMode.pirate;
      b.hullHp = 12;
      b.crewCount = 2;
      b.behavior = BehaviorMode.pirate;
      target(a, b);
      sim.update(.01);
      final run = sim.encounterFor(a.id)!;
      expect(run.result.coins, 2);
      sim.update(3);
      await store.save(sim);
      final loaded = await store.load();
      expect(loaded.encounterFor(a.id)!.result.toJson(), run.result.toJson());
      expect(loaded.encounterFor(a.id)!.elapsed, run.elapsed);
      expect(loaded.coins, 0);
      loaded.update(run.result.duration);
      await store.save(loaded);
      final again = await store.load();
      expect(again.coins, 2);
      expect(again.gems, 1);
      expect(again.ships.first.hullHp, loaded.ships.first.hullHp);
      again.update(.1);
      expect(again.coins, 2);
      final data = jsonDecode(saved!);
      expect(data['version'], 7);
    },
  );
  test(
    'invalid encounter save and negative currency fail without overwrite',
    () async {
      String? saved;
      var writes = 0;
      final store = VoyageStore(
        read: () async => saved,
        write: (s) async {
          writes++;
          saved = s;
        },
      );
      await store.save(createCaribbean());
      final data = jsonDecode(saved!);
      data['encounters']['coins'] = -1;
      saved = jsonEncode(data);
      await expectLater(store.load(), throwsFormatException);
      expect(writes, 1);
    },
  );
}
