import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/core/movement/point.dart';
import 'package:dot_commander/core/movement/sea_navigation.dart';
import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';

void main() {
  test(
    'unobstructed route is direct and blocked route uses safe deterministic corners',
    () {
      final nav = SeaNavigation([
        const LandRegion('island', 100, 100, 200, 200),
      ]);
      const start = Point2(50, 150), goal = Point2(250, 150);
      expect(nav.clearSegment(start, goal), isFalse);
      final path = nav.route(start, goal);
      expect(path.length, greaterThan(1));
      var previous = start;
      for (final point in path) {
        expect(nav.clearSegment(previous, point), isTrue);
        previous = point;
      }
      expect(previous.x, goal.x);
      expect(previous.y, goal.y);
      expect(
        nav.route(start, goal).map((p) => [p.x, p.y]),
        path.map((p) => [p.x, p.y]),
      );
      expect(nav.route(const Point2(20, 20), const Point2(80, 20)).length, 1);
    },
  );
  test(
    'land, clearance, off-map and unreachable goals never produce unsafe paths',
    () {
      final nav = SeaNavigation([
        const LandRegion('island', 100, 100, 200, 200),
      ]);
      expect(nav.route(const Point2(20, 20), const Point2(150, 150)), isEmpty);
      expect(nav.isWater(const Point2(95, 150)), isFalse);
      expect(nav.route(const Point2(-1, 20), const Point2(20, 20)), isEmpty);
      final wall = SeaNavigation([const LandRegion('wall', 400, 0, 500, 720)]);
      expect(
        wall.route(const Point2(100, 300), const Point2(700, 300)),
        isEmpty,
      );
    },
  );
  test('all island berths and initial ship positions are navigable', () {
    final sim = createCaribbean();
    for (final place in sim.places) {
      expect(
        sim.navigation.isWater(place.position),
        isTrue,
        reason: place.name,
      );
    }
    for (final ship in sim.ships) {
      expect(sim.navigation.isWater(ship.position), isTrue, reason: ship.name);
    }
    for (final a in sim.places) {
      for (final b in sim.places) {
        expect(sim.navigation.route(a.position, b.position), isNotEmpty);
      }
    }
  });
  test(
    'every movement segment stays in water across a ten-minute living voyage',
    () {
      final sim = createCaribbean();
      var docked = false, observed = false;
      for (var i = 0; i < 36000; i++) {
        // Keyed by id (not position/index) so a ship appearing or
        // disappearing mid-run (e.g. the money ship -- see
        // Vessel.isMoneyShip) can't misalign a positional before/after
        // pairing; a ship with no recorded "before" position just
        // started existing this tick, so it has no segment to check yet.
        final before = {for (final s in sim.ships) s.id: s.position};
        sim.update(1 / 60);
        for (final ship in sim.ships) {
          final previous = before[ship.id];
          if (previous != null) {
            expect(
              sim.navigation.clearSegment(previous, ship.position),
              isTrue,
              reason:
                  'step $i ship ${ship.id} from ${previous.x},${previous.y} to ${ship.position.x},${ship.position.y}',
            );
          }
          docked |= ship.activity == Activity.docked;
          observed |= ship.activity == Activity.observing;
        }
      }
      expect(docked, isTrue);
      expect(observed, isTrue);
    },
  );
  test(
    'a longer update follows multiple route segments instead of cutting land',
    () {
      final sim = createCaribbean();
      final ship = sim.ships.first;
      ship.position = const Point2(30, 102);
      ship.destination = sim.places[1];
      sim.update(10);
      expect(sim.navigation.isWater(ship.position), isTrue);
      expect(
        ship.position.distanceTo(ship.destination!.position),
        greaterThan(1),
      );
    },
  );
}
