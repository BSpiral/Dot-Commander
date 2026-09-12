import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/core/movement/point.dart';
import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/core/persistence/voyage_snapshot.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/ships/hull_catalog.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';

void main() {
  test(
    'hull speed and load/damage give visibly different pace without role restrictions',
    () {
      final sim = createCaribbean();
      final ship = sim.ships.first;
      ship.load = LoadState.normal;
      final normal = ship.effectiveSpeed;
      ship.load = LoadState.heavy;
      expect(ship.effectiveSpeed, closeTo(normal * .72, .001));
      ship.hullHp = ship.maxHullHp * .5;
      expect(ship.effectiveSpeed, closeTo(normal * .72 * .725, .001));
      ship.load = LoadState.light;
      ship.hullHp = ship.maxHullHp;
      expect(ship.effectiveSpeed, greaterThan(normal));
      expect(
        hullFor('Sloop').baseSpeed,
        greaterThan(hullFor('Man-of-War').baseSpeed * 3),
      );
      for (final hull in hullCatalog) {
        for (final mode in BehaviorMode.values) {
          final s = Vessel(
            id: 'test',
            name: 'Test',
            captain: 'Captain',
            hullType: hull.name,
            position: const Point2(20, 20),
            speed: hull.baseSpeed,
            maxHullHp: hull.hp,
            crewCount: hull.crew,
            behavior: mode,
          );
          expect(sim.chooseDestination(s), isNotNull);
        }
      }
    },
  );
  test(
    'merchants keep sailing and every port stop is temporary in ten simulated minutes',
    () {
      final sim = createCaribbean();
      final merchants = sim.ships
          .where((s) => !s.playerOwned && s.behavior == BehaviorMode.merchant)
          .toList();
      expect(merchants.length, greaterThanOrEqualTo(5));
      final sailing = {for (final s in merchants) s.id: 0};
      final stops = {for (final s in merchants) s.id: 0};
      final streak = {for (final s in merchants) s.id: 0};
      for (var tick = 0; tick < 36000; tick++) {
        sim.update(1 / 60);
        for (final s in merchants.where((s) => s.atSea)) {
          if (s.activity == Activity.docked) {
            stops[s.id] = stops[s.id]! + 1;
            streak[s.id] = streak[s.id]! + 1;
          } else {
            sailing[s.id] = sailing[s.id]! + 1;
            streak[s.id] = 0;
          }
          expect(streak[s.id], lessThanOrEqualTo(1500), reason: s.name);
        }
      }
      for (final s in merchants.where((s) => s.atSea)) {
        expect(sailing[s.id]! / 36000, greaterThan(.35), reason: s.name);
        expect(stops[s.id], greaterThan(0), reason: s.name);
      }
    },
  );
  test(
    'legacy voyage migrates land-covered positions and adds NPCs without renaming old ships',
    () async {
      final data = jsonDecode(VoyageSnapshot.encode(createCaribbean().ships));
      data['version'] = 1;
      data['ships'] = (data['ships'] as List).take(8).toList();
      data['ships'][0]['position'] = [545, 120];
      data['ships'][0]['name'] = 'Old Reliable';
      for (final row in data['ships']) {
        row.remove('load');
        row.remove('riggingBonus');
      }
      final source = jsonEncode(data);
      String? saved = source;
      final store = VoyageStore(
        read: () async => saved,
        write: (s) async {
          saved = s;
        },
      );
      final sim = await store.load();
      expect(sim.ships.length, 15);
      expect(sim.ships.first.name, 'Old Reliable');
      expect(sim.navigation.isWater(sim.ships.first.position), isTrue);
      expect(
        sim.ships.first.position.distanceTo(const Point2(545, 120)),
        greaterThan(0),
      );
      expect(sim.ships.first.speed, hullFor('Sloop').baseSpeed);
      await store.save(sim);
      expect(jsonDecode(saved!)['version'], 7);
      final again = await store.load();
      expect(again.ships.length, 15);
      expect(again.ships.first.name, 'Old Reliable');
    },
  );
  test(
    'load and reserved rigging modifier round-trip, fleet limit is enforced',
    () {
      final sim = createCaribbean();
      sim.ships.first.load = LoadState.heavy;
      sim.ships.first.riggingBonus = .1;
      final decoded = VoyageSnapshot.decode(
        VoyageSnapshot.encode(sim.ships),
        sim.navigation,
        sim.places,
      );
      expect(decoded.first.effectiveSpeed, sim.ships.first.effectiveSpeed);
      final data = jsonDecode(VoyageSnapshot.encode(sim.ships));
      for (var i = 0; i < 6; i++) {
        data['ships'][i]['playerOwned'] = true;
      }
      expect(
        () =>
            VoyageSnapshot.decode(jsonEncode(data), sim.navigation, sim.places),
        throwsFormatException,
      );
    },
  );
  test('close-contact pursuit resumes with another target or a port', () {
    final sim = createCaribbean();
    final ship = sim.ships[2];
    final target = sim.ships[1];
    ship.position = target.position;
    ship.destination = Destination(
      target.id,
      target.name,
      target.position,
      DestinationKind.ship,
    );
    ship.activity = Activity.observing;
    ship.pauseRemaining = .01;
    sim.update(.02);
    expect(ship.activity, Activity.sailing);
    expect(ship.destination!.id, isNot(target.id));
    expect(
      ship.destination!.position.distanceTo(ship.position),
      greaterThan(50),
    );
  });
  test('no NPC remains stationary beyond its bounded service visit', () {
    final sim = createCaribbean();
    final idle = {for (final s in sim.ships) s.id: 0};
    for (var frame = 0; frame < 18000; frame++) {
      final before = {for (final s in sim.ships) s.id: s.position};
      sim.update(1 / 60);
      for (final ship in sim.ships.where((s) => !s.playerOwned && s.atSea)) {
        idle[ship.id] = before[ship.id]!.distanceTo(ship.position) < .00001
            ? idle[ship.id]! + 1
            : 0;
        expect(idle[ship.id], lessThan(1500), reason: ship.name);
      }
    }
  });
}
