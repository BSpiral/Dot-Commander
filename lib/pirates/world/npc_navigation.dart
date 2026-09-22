import 'dart:math';
import '../../core/movement/point.dart';
import '../../core/simulation/vessel.dart';
import '../encounters/pirates_voyage.dart';

abstract final class NpcBalance {
  static const pirateRadius = 170.0,
      hunterRadius = 280.0,
      explorerMultiplier = 2.0;
  static const lostContact = 1.6,
      fullHold = .8,
      decisionInterval = .75,
      reacquireDelay = 20.0;
}

/// Decisions only; the existing Simulation still owns routing/movement.
class NpcNavigation {
  final PiratesVoyage v;
  NpcNavigation(this.v);
  double radius(Vessel s) {
    final base = s.hunter ? NpcBalance.hunterRadius : NpcBalance.pirateRadius;
    final scouts = v.ships.any(
      (e) =>
          e.atSea &&
          e.behavior == BehaviorMode.explorer &&
          e.position.distanceTo(s.position) < base,
    );
    return base * (scouts ? NpcBalance.explorerMultiplier : 1);
  }

  double condition(Vessel s) => min(
    s.hullHp / s.maxHullHp,
    s.crewCount / v.progress.crewCapacity(s),
  ).clamp(0, 1);
  double power(Vessel s) =>
      s.hullHp +
      s.crewCount * 1.5 * s.crewEffectiveness +
      s.firepower * 5 +
      s.handling * 20;
  bool needsPort(Vessel s) =>
      1 - condition(s) > min(.7, s.npcTolerance + .3) ||
      (s.behavior == BehaviorMode.pirate &&
          s.cargo >= v.progress.effectiveHoldCapacity(s) * NpcBalance.fullHold);
  bool willing(Vessel s, Vessel target) {
    if (s.playerOwned || s.hunter) return true;
    if (s.fleeing || s.returnToPort || needsPort(s)) return false;
    if (s.behavior == BehaviorMode.pirate && target.hunter) return false;
    final damage = 1 - condition(s);
    final risk =
        s.npcResolve * (1 - damage * .8 - max(0, damage - s.npcTolerance) * .7);
    return power(target) <= power(s) * risk.clamp(.55, 1.25);
  }

  bool targetAllowed(Vessel s, Vessel target) =>
      v.combatAvailable(target) &&
      target.id != s.ignoredTarget &&
      s.position.distanceTo(target.position) <= radius(s) &&
      (s.playerOwned || willing(s, target));
  Vessel? find(String? id) {
    for (final s in v.ships) {
      if (s.id == id) return s;
    }
    return null;
  }

  double segmentDistance(Point2 p, Point2 a, Point2 b) {
    final dx = b.x - a.x, dy = b.y - a.y;
    final denominator = dx * dx + dy * dy;
    final t = denominator == 0
        ? 0.0
        : ((p.x - a.x) * dx + (p.y - a.y) * dy) / denominator;
    return p.distanceTo(
      Point2(a.x + dx * t.clamp(0, 1), a.y + dy * t.clamp(0, 1)),
    );
  }

  Destination? safePort(Vessel s, Vessel threat) {
    final choices = v.places
        .where(
          (p) =>
              p.kind == DestinationKind.port &&
              (s.behavior == BehaviorMode.pirate
                  ? p.id == 'tortuga'
                  : p.id != 'tortuga') &&
              s.position.distanceTo(p.position) <= 500,
        )
        .toList();
    final candidates = <Destination>[];
    final current = s.position.distanceTo(threat.position);
    for (final p in choices) {
      final route = v.navigation.route(s.position, p.position);
      if (route.isEmpty) continue;
      final first = s.position.toward(route.first, 30);
      if (first.distanceTo(threat.position) < current - 5) continue;
      var previous = s.position;
      var safe = true;
      for (final point in route) {
        if (segmentDistance(threat.position, previous, point) <
            min(65, current * .8)) {
          safe = false;
          break;
        }
        previous = point;
      }
      if (safe) candidates.add(p);
    }
    candidates.sort(
      (a, b) => s.position
          .distanceTo(a.position)
          .compareTo(s.position.distanceTo(b.position)),
    );
    return candidates.isEmpty ? null : candidates.first;
  }

  Destination away(Vessel s, Vessel threat) {
    Point2 best = s.position;
    var score = -double.infinity;
    for (var i = 0; i < 16; i++) {
      final angle = 2 * pi * i / 16;
      final p = Point2(
        s.position.x + cos(angle) * 120,
        s.position.y + sin(angle) * 120,
      );
      if (!v.navigation.isWater(p) ||
          !v.navigation.clearSegment(s.position, p)) {
        continue;
      }
      final value = p.distanceTo(threat.position);
      if (value > score) {
        score = value;
        best = p;
      }
    }
    return Destination(
      'safety-${s.id}',
      'Breaking contact',
      best,
      DestinationKind.waypoint,
    );
  }

  Destination? destination(Vessel s) {
    if (s.playerOwned) return null;
    if (s.fleeing) {
      final threat = find(s.threatId);
      if (threat != null && threat.atSea) {
        if (s.behavior != BehaviorMode.pirate ||
            s.position.distanceTo(threat.position) > radius(threat)) {
          final port = safePort(s, threat);
          if (port != null) return port;
        }
        return away(s, threat);
      }
      return v.life.portFor(s);
    }
    return null;
  }

  void disengage(Vessel s, String target) {
    s.ignoredTarget = s.playerOwned ? null : target;
    s.ignoreTime = NpcBalance.reacquireDelay;
    s.pursuitId = null;
    s.pursuitTime = 0;
    s.destination = null;
    s.activity = Activity.sailing;
  }

  void tick(double dt) {
    for (final s in v.ships.where((s) => !s.playerOwned && s.atSea)) {
      if (v.busy(s.id) || s.activity == Activity.docked) continue;
      if (s.hunter) {
        s.fleeing = false;
        s.threatId = null;
      }
      s.ignoreTime = max(0, s.ignoreTime - dt);
      if (s.ignoreTime == 0) s.ignoredTarget = null;
      if (s.fleeing) s.fleeTime += dt;
      final target = s.destination?.kind == DestinationKind.ship
          ? find(s.destination!.id)
          : null;
      if (target != null) {
        if (s.pursuitId != target.id) {
          s.pursuitId = target.id;
          s.pursuitTime = 0;
        }
        s.pursuitTime += dt;
        if (!v.combatAvailable(target) ||
            !willing(s, target) ||
            s.position.distanceTo(target.position) >
                radius(s) * NpcBalance.lostContact ||
            s.pursuitTime >
                (s.hunter ? s.npcPersistence * 2 : s.npcPersistence)) {
          disengage(s, target.id);
        }
      } else {
        s.pursuitId = null;
        s.pursuitTime = 0;
      }
      s.decisionWait -= dt;
      if (s.decisionWait > 0) continue;
      s.decisionWait = NpcBalance.decisionInterval;
      if (!s.hunter) {
        final threats = v.ships
            .where(
              (t) =>
                  t.id != s.id &&
                  v.combatAvailable(t) &&
                  s.position.distanceTo(t.position) <= radius(t) &&
                  ((t.hunter && s.behavior == BehaviorMode.pirate) ||
                      (t.behavior == BehaviorMode.pirate &&
                          t.destination?.id == s.id)),
            )
            .toList();
        threats.sort((a, b) => power(b).compareTo(power(a)));
        if (threats.isNotEmpty &&
            (threats.first.hunter || !willing(s, threats.first))) {
          if (!s.fleeing) v.life.log(s, 'Fleeing toward safety');
          s.fleeing = true;
          s.threatId = threats.first.id;
        }
        if (s.fleeing) {
          final t = find(s.threatId);
          if (s.behavior == BehaviorMode.pirate &&
              (t == null ||
                  !t.atSea ||
                  s.position.distanceTo(t.position) >
                      radius(t) * NpcBalance.lostContact)) {
            s.fleeing = false;
            s.threatId = null;
            s.fleeTime = 0;
          } else {
            s.destination = destination(s);
            s.activity = Activity.sailing;
            s.pauseRemaining = 0;
            continue;
          }
        }
        if (needsPort(s)) {
          if (!s.returnToPort) {
            v.life.log(s, 'Returning to port: condition / full hold');
          }
          s.returnToPort = true;
        }
      }
      if (s.returnToPort || s.retiring || s.recovering) {
        s.destination = v.life.portFor(s);
        s.activity = Activity.sailing;
        continue;
      }
      // Periodic reacquisition uses the same chooseDestination and route cache.
      if (s.behavior == BehaviorMode.pirate ||
          s.behavior == BehaviorMode.privateer) {
        final next = v.chooseDestination(s);
        if (next.kind == DestinationKind.ship) {
          s.destination = next;
          s.activity = Activity.sailing;
        }
      }
    }
  }
}
