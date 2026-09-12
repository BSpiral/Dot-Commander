import 'dart:convert';
import '../movement/point.dart';
import '../movement/sea_navigation.dart';
import '../simulation/vessel.dart';

/// Versioned model snapshot. Renderer objects and navigation caches are excluded.
class VoyageSnapshot {
  static String encode(List<Vessel> ships) => jsonEncode({
    'version': 2,
    'ships': [
      for (final s in ships)
        {
          'id': s.id,
          'name': s.name,
          'captain': s.captain,
          'hullType': s.hullType,
          'playerOwned': s.playerOwned,
          'position': [s.position.x, s.position.y],
          'speed': s.speed,
          'load': s.load.name,
          'riggingBonus': s.riggingBonus,
          'maxHullHp': s.maxHullHp,
          'hullHp': s.hullHp,
          'crewCount': s.crewCount,
          'cargo': s.cargo,
          'chainPenalty': s.chainPenalty,
          'ordnance': s.ordnance,
          'npcTolerance': s.npcTolerance,
          'npcResolve': s.npcResolve,
          'npcPersistence': s.npcPersistence,
          'fleeing': s.fleeing,
          'threatId': s.threatId,
          'pursuitId': s.pursuitId,
          'ignoredTarget': s.ignoredTarget,
          'fleeTime': s.fleeTime,
          'pursuitTime': s.pursuitTime,
          'decisionWait': s.decisionWait,
          'ignoreTime': s.ignoreTime,
          'effects': {
            'firepower': s.firepower,
            'crewEffectiveness': s.crewEffectiveness,
            'handling': s.handling,
            'damageReduction': s.damageReduction,
            'postHullRecovery': s.postHullRecovery,
            'postCrewRecovery': s.postCrewRecovery,
            'crewDefense': s.crewDefense,
            'openingVolley': s.openingVolley,
            'openingAttack': s.openingAttack,
            'economyBonus': s.economyBonus,
            'fieldRepairBonus': s.fieldRepairBonus,
            'penaltyMitigation': s.penaltyMitigation,
            'minimumMovement': s.minimumMovement,
          },
          'atSea': s.atSea,
          'hunter': s.hunter,
          'returnToPort': s.returnToPort,
          'retiring': s.retiring,
          'attacks': s.attacksSincePort,
          'respawn': s.respawnRemaining,
          'log': s.recentActivity,
          'recovering': s.recovering,
          'behavior': s.behavior.name,
          'activity': s.activity.name,
          'pauseRemaining': s.pauseRemaining,
          'heading': s.heading,
          'destination': s.destination == null
              ? null
              : {
                  'id': s.destination!.id,
                  'name': s.destination!.name,
                  'kind': s.destination!.kind.name,
                  'position': [
                    s.destination!.position.x,
                    s.destination!.position.y,
                  ],
                },
        },
    ],
  });

  static List<Vessel> decode(
    String source,
    SeaNavigation navigation,
    List<Destination> places,
  ) {
    try {
      final root = jsonDecode(source) as Map<String, dynamic>;
      if (root['version'] != 1 &&
          root['version'] != 2 &&
          root['version'] != 3 &&
          root['version'] != 4 &&
          root['version'] != 5 &&
          root['version'] != 6 &&
          root['version'] != 7) {
        throw const FormatException('Unsupported save version');
      }
      final rows = root['ships'] as List;
      if (rows.isEmpty || rows.length > 100) {
        throw const FormatException('Invalid fleet size');
      }
      double number(dynamic value) {
        final n = (value as num).toDouble();
        if (!n.isFinite) throw const FormatException('Invalid number');
        return n;
      }

      String text(dynamic value) {
        if (value is! String || value.isEmpty || value.length > 120) {
          throw const FormatException('Invalid identity');
        }
        return value;
      }

      Point2 point(dynamic value) {
        final p = Point2(number(value[0]), number(value[1]));
        if (!navigation.isWater(p)) {
          throw const FormatException('Position outside navigable water');
        }
        return p;
      }

      final ships = <Vessel>[];
      for (final row in rows) {
        final ship = Vessel(
          id: text(row['id']),
          name: text(row['name']),
          captain: text(row['captain']),
          hullType: text(row['hullType']),
          position: point(row['position']),
          speed: number(row['speed']),
          maxHullHp: number(row['maxHullHp']),
          crewCount: row['crewCount'] as int,
          behavior: BehaviorMode.values.byName(row['behavior'] as String),
          playerOwned: row['playerOwned'] as bool,
          load: LoadState.values.byName(row['load'] as String? ?? 'normal'),
          riggingBonus: number(row['riggingBonus'] ?? 0),
        );
        ship.cargo = row['cargo'] as int? ?? 0;
        ship.chainPenalty = number(row['chainPenalty'] ?? 0);
        ship.ordnance = row['ordnance'] ?? 'standard';
        if (![
              'standard',
              'heavy',
              'grape',
              'chain',
              'fire',
            ].contains(ship.ordnance) ||
            ship.chainPenalty < 0 ||
            ship.chainPenalty > .8) {
          throw const FormatException('Invalid ordnance state');
        }
        ship.npcTolerance = number(row['npcTolerance'] ?? ship.npcTolerance);
        ship.npcResolve = number(row['npcResolve'] ?? ship.npcResolve);
        ship.npcPersistence = number(
          row['npcPersistence'] ?? ship.npcPersistence,
        );
        ship.fleeing = row['fleeing'] ?? false;
        ship.threatId = row['threatId'];
        ship.pursuitId = row['pursuitId'];
        ship.ignoredTarget = row['ignoredTarget'];
        ship.fleeTime = number(row['fleeTime'] ?? 0);
        ship.pursuitTime = number(row['pursuitTime'] ?? 0);
        ship.decisionWait = number(row['decisionWait'] ?? 0);
        ship.ignoreTime = number(row['ignoreTime'] ?? 0);
        if (ship.npcTolerance < 0 ||
            ship.npcTolerance > 1 ||
            ship.npcResolve < .5 ||
            ship.npcResolve > 1.5 ||
            ship.npcPersistence < 1 ||
            ship.npcPersistence > 120 ||
            ship.fleeTime < 0 ||
            ship.pursuitTime < 0 ||
            ship.ignoreTime < 0) {
          throw const FormatException('Invalid NPC state');
        }
        final effects = row['effects'] as Map<String, dynamic>?;
        if (effects != null) {
          ship.firepower = number(effects['firepower'] ?? 0);
          ship.crewEffectiveness = number(effects['crewEffectiveness'] ?? 1);
          ship.handling = number(effects['handling'] ?? 0);
          ship.damageReduction = number(effects['damageReduction'] ?? 0);
          ship.postHullRecovery = number(effects['postHullRecovery'] ?? 0);
          ship.postCrewRecovery = number(effects['postCrewRecovery'] ?? 0);
          ship.crewDefense = number(effects['crewDefense'] ?? 0);
          ship.openingVolley = number(effects['openingVolley'] ?? 0);
          ship.openingAttack = number(effects['openingAttack'] ?? 0);
          ship.economyBonus = number(effects['economyBonus'] ?? 0);
          ship.fieldRepairBonus = number(effects['fieldRepairBonus'] ?? 0);
          ship.penaltyMitigation = number(effects['penaltyMitigation'] ?? 0);
          ship.minimumMovement = number(effects['minimumMovement'] ?? 0);
        }

        ship.atSea = row['atSea'] as bool? ?? true;
        ship.hunter = row['hunter'] as bool? ?? false;
        ship.returnToPort = row['returnToPort'] as bool? ?? false;
        ship.retiring = row['retiring'] as bool? ?? false;
        ship.attacksSincePort = row['attacks'] as int? ?? 0;
        ship.respawnRemaining = number(row['respawn'] ?? 0);
        ship.recentActivity.addAll(
          (row['log'] as List? ?? []).cast<String>().take(12),
        );
        if (ship.respawnRemaining < 0 || ship.attacksSincePort < 0) {
          throw const FormatException('Invalid world state');
        }
        ship.recovering = row['recovering'] as bool? ?? false;
        if (ship.cargo < 0 || ship.cargo > 1000) {
          throw const FormatException('Invalid cargo');
        }
        ship.hullHp = number(row['hullHp']);
        ship.activity = Activity.values.byName(row['activity'] as String);
        ship.pauseRemaining = number(row['pauseRemaining']);
        ship.heading = number(row['heading']);
        if (ship.speed <= 0 ||
            ship.speed > 500 ||
            ship.riggingBonus < 0 ||
            ship.riggingBonus > 3 ||
            ship.maxHullHp <= 0 ||
            ship.hullHp < 0 ||
            ship.hullHp > ship.maxHullHp ||
            ship.crewCount < 0 ||
            ship.pauseRemaining < 0 ||
            ship.pauseRemaining > 60) {
          throw const FormatException('Invalid ship state');
        }
        final d = row['destination'];
        if (d != null) {
          final kind = DestinationKind.values.byName(d['kind'] as String);
          final id = text(d['id']);
          if (kind == DestinationKind.ship ||
              kind == DestinationKind.waypoint) {
            ship.destination = Destination(
              id,
              text(d['name']),
              point(d['position']),
              kind,
            );
          } else {
            ship.destination = places.firstWhere(
              (p) => p.id == id && p.kind == kind,
            );
          }
        }
        if (ship.activity != Activity.sailing &&
            ship.activity != Activity.engaged &&
            ship.destination == null) {
          throw const FormatException('Missing arrival destination');
        }
        if (ship.activity == Activity.docked &&
            (ship.destination!.kind != DestinationKind.port ||
                ship.position.distanceTo(ship.destination!.position) > 1)) {
          throw const FormatException('Invalid docked position');
        }
        ships.add(ship);
      }
      final ids = ships.map((s) => s.id).toSet();
      if (ids.length != ships.length ||
          ships.where((s) => s.playerOwned).isEmpty ||
          ships.where((s) => s.playerOwned).length > 5) {
        throw const FormatException('Invalid identities');
      }
      for (final ship in ships) {
        if (ship.destination?.kind == DestinationKind.ship &&
            (!ids.contains(ship.destination!.id) ||
                ship.destination!.id == ship.id)) {
          throw const FormatException('Invalid ship target');
        }
      }
      return ships;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Malformed voyage');
    }
  }
}
