import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/core/movement/point.dart';
import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';

void main() {
  test('movement clamps at waypoint without overshoot', () {
    final p = const Point2(0, 0).toward(const Point2(3, 4), 10);
    expect(p.x, 3);
    expect(p.y, 4);
  });
  test(
    'startup has fifteen unique persistent identities and six hull types',
    () {
      final sim = createCaribbean();
      expect(sim.ships.length, 15);
      expect(sim.ships.map((s) => s.id).toSet().length, 15);
      expect(sim.ships.where((s) => s.playerOwned).length, 1);
      expect(sim.ships.map((s) => s.hullType).toSet().length, 6);
    },
  );
  for (final mode in BehaviorMode.values) {
    test('${mode.name} destination preference', () {
      final sim = createCaribbean();
      final ship = sim.ships.first;
      sim.setBehavior(ship, mode);
      final destination = ship.destination!;
      if (mode == BehaviorMode.merchant) {
        expect(destination.kind, DestinationKind.port);
      }
      if (mode == BehaviorMode.explorer) {
        expect(destination.kind, DestinationKind.search);
      }
      if (mode == BehaviorMode.pirate || mode == BehaviorMode.privateer) {
        expect(destination.kind, DestinationKind.ship);
        expect(destination.id, isNot(ship.id));
        if (mode == BehaviorMode.privateer) {
          expect(
            sim.ships.firstWhere((s) => s.id == destination.id).behavior,
            BehaviorMode.pirate,
          );
        }
      }
    });
  }
  test('NPC docks then resumes with identity and stats unchanged', () {
    final sim = createCaribbean();
    final ship = sim.ships[1];
    ship.behavior = BehaviorMode.merchant;
    ship.destination = caribbeanPlaces.first;
    ship.position = ship.destination!.position;
    final identity = [
      ship.id,
      ship.name,
      ship.captain,
      ship.hullType,
      ship.hullHp,
      ship.crewCount,
    ];
    sim.update(1 / 60);
    expect(ship.activity, Activity.docked);
    sim.update(1);
    expect(ship.activity, Activity.docked);
    for (var i = 0; i < 300 && ship.activity == Activity.docked; i++) {
      sim.update(.02);
    }
    expect(ship.activity, Activity.sailing);
    expect(ship.destination!.id, isNot(caribbeanPlaces.first.id));
    expect([
      ship.id,
      ship.name,
      ship.captain,
      ship.hullType,
      ship.hullHp,
      ship.crewCount,
    ], identity);
    expect(identical(sim.ships[1], ship), isTrue);
  });
  test('search arrival observes and changed order immediately resumes', () {
    final sim = createCaribbean();
    final ship = sim.ships.first;
    ship.destination = caribbeanPlaces.last;
    ship.position = ship.destination!.position;
    sim.update(.01);
    expect(ship.activity, Activity.observing);
    sim.setBehavior(ship, BehaviorMode.merchant);
    expect(ship.activity, Activity.sailing);
    expect(ship.pauseRemaining, 0);
  });
  test('privateer without pirates falls back to port', () {
    final sim = createCaribbean();
    for (final ship in sim.ships) {
      ship.behavior = BehaviorMode.merchant;
    }
    sim.setBehavior(sim.ships.first, BehaviorMode.privateer);
    expect(sim.ships.first.destination!.kind, DestinationKind.port);
  });
  test('seeded movement is reproducible and bounded over port visits', () {
    final a = createCaribbean(seed: Random(7).nextInt(1000));
    final b = createCaribbean(seed: Random(7).nextInt(1000));
    for (var i = 0; i < 18000; i++) {
      a.update(1 / 60);
      b.update(1 / 60);
    }
    for (var i = 0; i < a.ships.length; i++) {
      expect(a.ships[i].position.x, b.ships[i].position.x);
      expect(a.ships[i].position.y, b.ships[i].position.y);
      expect(a.ships[i].position.x, inInclusiveRange(0, 960));
      expect(a.ships[i].position.y, inInclusiveRange(0, 720));
    }
  });
  test('invalid time rejected and zero time leaves state alone', () {
    final sim = createCaribbean();
    sim.update(0);
    expect(sim.ships.first.destination, isNull);
    expect(() => sim.update(-1), throwsArgumentError);
    expect(() => sim.update(double.nan), throwsArgumentError);
  });
}
