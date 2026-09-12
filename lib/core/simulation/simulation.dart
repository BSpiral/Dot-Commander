import 'dart:math';
import 'vessel.dart';
import '../movement/point.dart';
import '../movement/sea_navigation.dart';

/// Pure Dart, fixed-step friendly simulation. No Flame or Flutter dependency.
class Simulation {
  final Set<String> heldShips = {};
  final List<Vessel> ships;
  final List<Destination> places;
  final Random rng;
  final SeaNavigation navigation;
  final _routes = <String, List<Point2>>{};
  final _goals = <String, Point2>{};
  final _replan = <String, double>{};
  Simulation({
    required List<Vessel> ships,
    required List<Destination> places,
    required this.rng,
    SeaNavigation? navigation,
  }) : navigation = navigation ?? SeaNavigation([]),
       ships = List.of(ships),
       places = List.unmodifiable(places) {
    if (ships.map((s) => s.id).toSet().length != ships.length) {
      throw ArgumentError('Ship IDs must be unique');
    }
    if (places.isEmpty) {
      throw ArgumentError('At least one destination is required');
    }
  }

  bool targetAllowed(Vessel ship, Vessel target) => true;

  Destination chooseDestination(Vessel ship) {
    final targets = ships
        .where(
          (s) =>
              s.id != ship.id &&
              targetAllowed(ship, s) &&
              s.atSea &&
              s.activity != Activity.docked &&
              s.activity != Activity.engaged &&
              s.hullHp > 0 &&
              s.crewCount > 0 &&
              !s.recovering &&
              !(ship.playerOwned && s.playerOwned) &&
              !heldShips.contains(s.id) &&
              (ship.activity != Activity.observing ||
                  (s.id != ship.destination?.id &&
                      ship.position.distanceTo(s.position) > 60)) &&
              (ship.behavior != BehaviorMode.privateer ||
                  s.behavior == BehaviorMode.pirate),
        )
        .toList();
    if ((ship.behavior == BehaviorMode.pirate ||
            ship.behavior == BehaviorMode.privateer) &&
        targets.isNotEmpty) {
      targets.sort(
        (a, b) => ship.position
            .distanceTo(a.position)
            .compareTo(ship.position.distanceTo(b.position)),
      );
      final target = targets.first;
      return Destination(
        target.id,
        target.name,
        target.position,
        DestinationKind.ship,
      );
    }
    final kind = ship.behavior == BehaviorMode.explorer
        ? DestinationKind.search
        : DestinationKind.port;
    var choices = places
        .where((p) => p.kind == kind && p.id != ship.destination?.id)
        .toList();
    if (choices.isEmpty) choices = places.where((p) => p.kind == kind).toList();
    if (choices.isEmpty) choices = places.toList();
    return choices[rng.nextInt(choices.length)];
  }

  void setBehavior(Vessel ship, BehaviorMode behavior) {
    _routes.remove(ship.id);
    ship.behavior = behavior;
    ship.destination = chooseDestination(ship);
    ship.activity = Activity.sailing;
    ship.pauseRemaining = 0;
  }

  void update(double dt) {
    if (!dt.isFinite || dt < 0) throw ArgumentError.value(dt, 'dt');
    if (dt == 0) return;
    // Snapshot target positions: pursuit does not depend on entity iteration order.
    final positions = {for (final s in ships) s.id: s.position};
    for (final ship in ships) {
      if (!ship.atSea || heldShips.contains(ship.id)) continue;
      if (ship.activity != Activity.sailing) {
        ship.pauseRemaining -= dt;
        if (ship.pauseRemaining > 0) continue;
        if (ship.behavior == BehaviorMode.merchant &&
            ship.activity == Activity.docked) {
          ship.load =
              LoadState.values[(ship.load.index + 1) % LoadState.values.length];
        } else if (ship.behavior == BehaviorMode.explorer &&
            ship.activity == Activity.observing) {
          ship.load = ship.load == LoadState.heavy
              ? LoadState.light
              : LoadState.heavy;
        }
        ship.destination = chooseDestination(ship);
        ship.activity = Activity.sailing;
        ship.pauseRemaining = 0;
      }
      ship.destination ??= chooseDestination(ship);
      var destination = ship.destination!;
      if (destination.kind == DestinationKind.ship) {
        final target = positions[destination.id];
        if (target != null) {
          destination = Destination(
            destination.id,
            destination.name,
            target,
            destination.kind,
          );
          ship.destination = destination;
        }
      }
      _replan[ship.id] = (_replan[ship.id] ?? 0) - dt;
      final oldGoal = _goals[ship.id];
      final moved =
          oldGoal == null || oldGoal.distanceTo(destination.position) > .01;
      if (!_routes.containsKey(ship.id) ||
          (moved &&
              (destination.kind != DestinationKind.ship ||
                  _replan[ship.id]! <= 0)) ||
          (_routes[ship.id]!.isEmpty && moved)) {
        _routes[ship.id] = navigation.route(
          ship.position,
          destination.position,
        );
        _goals[ship.id] = destination.position;
        _replan[ship.id] = .75;
      }
      final route = _routes[ship.id]!;
      var remaining = ship.effectiveSpeed * dt;
      while (route.isNotEmpty && remaining > 0) {
        final waypoint = route.first;
        final distance = ship.position.distanceTo(waypoint);
        if (distance > 0) {
          ship.heading = atan2(
            waypoint.y - ship.position.y,
            waypoint.x - ship.position.x,
          );
        }
        ship.position = ship.position.toward(waypoint, remaining);
        remaining -= distance;
        if (distance <= ship.effectiveSpeed * dt &&
            ship.position.distanceTo(waypoint) < .0001) {
          route.removeAt(0);
        } else {
          break;
        }
      }
      if (ship.position.distanceTo(destination.position) <
              (destination.kind == DestinationKind.ship ? 18 : 1) &&
          navigation.clearSegment(ship.position, destination.position)) {
        ship.activity = destination.kind == DestinationKind.port
            ? Activity.docked
            : Activity.observing;
        ship.pauseRemaining = 2;
      }
    }
  }
}
