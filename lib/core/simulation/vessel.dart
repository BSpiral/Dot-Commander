import '../movement/point.dart';

enum BehaviorMode { merchant, pirate, explorer, privateer }

enum LoadState { light, normal, heavy }

enum Activity { sailing, docked, observing, engaged }

enum DestinationKind { port, search, ship, waypoint }

class Destination {
  final String id, name;
  final Point2 position;
  final DestinationKind kind;
  const Destination(this.id, this.name, this.position, this.kind);
}

class Vessel {
  final String id, name, captain;
  String hullType;
  final bool playerOwned;
  double speed, maxHullHp;
  double firepower = 0, crewEffectiveness = 1, handling = 0;
  double hullHp;
  String ordnance = 'standard';
  double chainPenalty = 0, penaltyMitigation = 0, minimumMovement = 0;
  double crewDefense = 0, openingVolley = 0, openingAttack = 0;
  double economyBonus = 0, fieldRepairBonus = 0;
  double npcTolerance = .3, npcResolve = 1, npcPersistence = 30;
  bool fleeing = false;
  String? threatId, pursuitId, ignoredTarget;
  double fleeTime = 0, pursuitTime = 0, decisionWait = 0, ignoreTime = 0;
  double get movementFactor =>
      (1 - chainPenalty * (1 - penaltyMitigation.clamp(0, .6))).clamp(
        minimumMovement,
        1.0,
      );

  LoadState load;
  double riggingBonus;
  double get effectiveSpeed =>
      speed *
      switch (load) {
        LoadState.light => 1.12,
        LoadState.normal => 1.0,
        LoadState.heavy => .72,
      } *
      (.45 + .55 * (hullHp / maxHullHp).clamp(0.0, 1.0)) *
      (1 + riggingBonus) *
      movementFactor;
  bool atSea = true, hunter = false, returnToPort = false, retiring = false;
  int attacksSincePort = 0;
  double respawnRemaining = 0;
  double damageReduction = 0, postHullRecovery = 0, postCrewRecovery = 0;
  final List<String> recentActivity = [];
  int cargo = 0;
  bool recovering = false;
  int crewCount;
  Point2 position;
  Destination? destination;
  BehaviorMode behavior;
  Activity activity = Activity.sailing;
  double pauseRemaining = 0;
  double heading = 0;
  Vessel({
    required this.id,
    required this.name,
    required this.captain,
    required this.hullType,
    required this.position,
    required this.speed,
    required this.maxHullHp,
    required this.crewCount,
    required this.behavior,
    this.playerOwned = false,
    this.load = LoadState.normal,
    this.riggingBonus = 0,
  }) : hullHp = maxHullHp {
    if (!playerOwned) {
      final seed = id.codeUnits.fold(17, (a, b) => (a * 31 + b) & 0x7fffffff);
      npcTolerance = .1 + (seed % 41) / 100;
      npcResolve = .85 + ((seed ~/ 41) % 36) / 100;
      npcPersistence = 22 + ((seed ~/ 1476) % 25).toDouble();
    }
  }
}
