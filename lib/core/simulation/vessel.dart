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
  // Port Relations balance pass 2026-09-20: equipment's own cargo/hold
  // percentage bonus (see FleetProgress.effectiveHoldCapacity) -- kept
  // separate from the Fleet Tree's own flat +1-per-step hold bonus so
  // "equipment bonuses do NOT consume any portion of the tree's +50
  // progression" (they're two independent additive/multiplicative
  // inputs to the same effective-capacity formula, not a shared pool).
  double holdBonus = 0;
  double npcTolerance = .3, npcResolve = 1, npcPersistence = 30;
  bool fleeing = false;
  String? threatId, pursuitId, ignoredTarget;
  double fleeTime = 0, pursuitTime = 0, decisionWait = 0, ignoreTime = 0;
  // Final corrections pass 2026-09-20, rigging-mitigation audit: the
  // inner `.clamp(0, .6)` on penaltyMitigation is NOT mechanically
  // required. The OUTER `.clamp(minimumMovement, 1.0)` on the whole
  // expression already fully protects this formula on its own -- even
  // if penaltyMitigation reached 1.0 (fully canceling chainPenalty's
  // speed impact) or grew arbitrarily larger, the term inside the outer
  // parens could go negative, but the outer clamp catches that and
  // simply floors movementFactor at minimumMovement; it can never
  // exceed 1.0 (faster than undamaged) regardless of how large
  // penaltyMitigation gets. So unlike Damage Reduction/Boarding Defense
  // (where removing their inner clamp would let (1-x) go negative with
  // NOTHING else protecting it), this .6 is an ordinary inherited
  // BALANCE number, not a genuine mechanical ceiling -- left UNCHANGED
  // this pass pending an explicit target value (Rigging-Damage
  // Mitigation has no tree-soft-cap number assigned in this design
  // brief the way Damage Reduction/Boarding Defense/etc. do).
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
  // Saturday repair pass 2026-09-20: the map-based "money ship" bonus --
  // an ordinary, ephemeral NPC Vessel. Tapping/catching it is a
  // rewarded-ad opportunity (see CommandScreen._claimMoneyShip and
  // RewardedMoneyShipService); only a completed ad grants its real
  // fleetCoinsPerHour reward, then removes it. Deliberately NOT
  // persisted (see VoyageStore.save filtering these out): its presence
  // and spawn timer are session-only, matching a lightweight, occasional
  // bonus rather than durable game state.
  bool isMoneyShip = false;
  int attacksSincePort = 0;
  double respawnRemaining = 0;
  double damageReduction = 0, postHullRecovery = 0, postCrewRecovery = 0;
  final List<String> recentActivity = [];
  int cargo = 0;
  bool recovering = false;
  int crewCount;
  // Ship/combat overhaul pass 2026-09-21: real, persisted crew CAPACITY
  // (distinct from crewCount, the current headcount) -- mirrors
  // maxHullHp's own role for hull HP exactly, and for the same reason:
  // FleetProgress.apply needs to read the ship's crew capacity AS IT WAS
  // BEFORE this specific Command Tree purchase to correctly preserve
  // war-damage percentage while still letting the capacity itself grow.
  // Recomputing "the old capacity" from the CURRENT tree level inside
  // apply() cannot work -- PiratesVoyage.buyTree already bumps the tree
  // level BEFORE calling apply(), so by the time apply() runs, "before"
  // and "after" would read the exact same (already-bumped) tree value,
  // making the fraction-preservation math cancel out to a no-op and
  // crew count would never actually grow through real gameplay. A
  // stored field, updated by apply() and left untouched in between (the
  // same pattern maxHullHp already uses), is the fix.
  int maxCrew;
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
  }) : hullHp = maxHullHp,
       maxCrew = crewCount {
    if (!playerOwned) {
      final seed = id.codeUnits.fold(17, (a, b) => (a * 31 + b) & 0x7fffffff);
      npcTolerance = .1 + (seed % 41) / 100;
      npcResolve = .85 + ((seed ~/ 41) % 36) / 100;
      npcPersistence = 22 + ((seed ~/ 1476) % 25).toDouble();
    }
  }
}
