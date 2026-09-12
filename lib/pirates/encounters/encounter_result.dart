import '../../core/simulation/vessel.dart';
import '../ships/hull_catalog.dart';
import 'dart:math' as math;

enum EncounterKind { escape, cannon, boarding }

/// Immutable inputs captured before combat. No live Vessel references.
class Combatant {
  final String id, name, hullType;
  final double hullHp, maxHullHp, speed;
  final int crew;
  final double firepower, crewEffectiveness, handling;
  final double damageReduction;
  final int attacks;
  final String ordnance;
  final int cargo;
  final double crewDefense, openingVolley, openingAttack, economyBonus;
  final bool wantsEscape;
  final bool owned;
  final BehaviorMode role;
  const Combatant(
    this.id,
    this.name,
    this.hullType,
    this.hullHp,
    this.maxHullHp,
    this.speed,
    this.crew,
    this.owned,
    this.role, {
    this.firepower = 0,
    this.crewEffectiveness = 1,
    this.handling = 0,
    this.damageReduction = 0,
    this.attacks = 0,
    this.ordnance = 'standard',
    this.cargo = 0,
    this.crewDefense = 0,
    this.openingVolley = 0,
    this.openingAttack = 0,
    this.economyBonus = 0,
    this.wantsEscape = true,
  });
  factory Combatant.capture(Vessel s) => Combatant(
    s.id,
    s.name,
    s.hullType,
    s.hullHp,
    s.maxHullHp,
    s.effectiveSpeed,
    s.crewCount,
    s.playerOwned,
    s.behavior,
    firepower: s.firepower,
    crewEffectiveness: s.crewEffectiveness,
    handling: s.handling,
    damageReduction: s.damageReduction,
    attacks: s.attacksSincePort,
    ordnance: s.ordnance,
    cargo: s.cargo,
    crewDefense: s.crewDefense,
    openingVolley: s.openingVolley,
    openingAttack: s.openingAttack,
    economyBonus: s.economyBonus,
    wantsEscape: s.fleeing || s.playerOwned,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'hullType': hullType,
    'hullHp': hullHp,
    'maxHullHp': maxHullHp,
    'speed': speed,
    'crew': crew,
    'owned': owned,
    'role': role.name,
    'firepower': firepower,
    'crewEffectiveness': crewEffectiveness,
    'handling': handling,
    'damageReduction': damageReduction,
    'attacks': attacks,
    'ordnance': ordnance,
    'cargo': cargo,
    'crewDefense': crewDefense,
    'openingVolley': openingVolley,
    'openingAttack': openingAttack,
    'economyBonus': economyBonus,
    'wantsEscape': wantsEscape,
  };
  factory Combatant.fromJson(Map<String, dynamic> j) => Combatant(
    j['id'],
    j['name'],
    j['hullType'],
    (j['hullHp'] as num).toDouble(),
    (j['maxHullHp'] as num).toDouble(),
    (j['speed'] as num).toDouble(),
    j['crew'],
    j['owned'],
    BehaviorMode.values.byName(j['role']),
    firepower: (j['firepower'] as num? ?? 0).toDouble(),
    crewEffectiveness: (j['crewEffectiveness'] as num? ?? 1).toDouble(),
    handling: (j['handling'] as num? ?? 0).toDouble(),
    damageReduction: (j['damageReduction'] as num? ?? 0).toDouble(),
    attacks: j['attacks'] as int? ?? 0,
    ordnance: j['ordnance'] ?? 'standard',
    cargo: j['cargo'] ?? 0,
    crewDefense: (j['crewDefense'] as num? ?? 0).toDouble(),
    openingVolley: (j['openingVolley'] as num? ?? 0).toDouble(),
    openingAttack: (j['openingAttack'] as num? ?? 0).toDouble(),
    economyBonus: (j['economyBonus'] as num? ?? 0).toDouble(),
    wantsEscape: j['wantsEscape'] ?? true,
  );
}

class EncounterResult {
  final String id;
  final Combatant a, b;
  final EncounterKind kind;
  final String? winnerId;
  final String? escapedId;
  final double damageA, damageB;
  final int crewLossA, crewLossB, coins, gems;
  final int burnedA, burnedB, loot;
  final double chainA, chainB;
  final int effectsVersion;
  const EncounterResult({
    required this.id,
    this.escapedId,
    required this.a,
    required this.b,
    required this.kind,
    required this.winnerId,
    required this.damageA,
    required this.damageB,
    required this.crewLossA,
    required this.crewLossB,
    required this.coins,
    required this.gems,
    this.burnedA = 0,
    this.burnedB = 0,
    this.loot = 0,
    this.chainA = 0,
    this.chainB = 0,
    this.effectsVersion = 0,
  });
  int get planks => kind == EncounterKind.boarding
      ? math.min(
          hullFor(a.hullType).plankCapacity,
          hullFor(b.hullType).plankCapacity,
        )
      : 0;
  double get duration => switch (kind) {
    EncounterKind.escape => 14,
    EncounterKind.cannon => 18,
    EncounterKind.boarding => 26,
  };
  bool involves(String shipId) => a.id == shipId || b.id == shipId;
  String get summary => kind == EncounterKind.escape
      ? '${b.name} escaped'
      : winnerId == null
      ? 'Draw — both ships withdraw'
      : '${winnerId == a.id ? a.name : b.name} victorious';
  Map<String, dynamic> toJson() => {
    'id': id,
    'a': a.toJson(),
    'b': b.toJson(),
    'kind': kind.name,
    'winner': winnerId,
    'escaped': escapedId,
    'damageA': damageA,
    'damageB': damageB,
    'crewLossA': crewLossA,
    'crewLossB': crewLossB,
    'coins': coins,
    'gems': gems,
    'burnedA': burnedA,
    'burnedB': burnedB,
    'loot': loot,
    'chainA': chainA,
    'chainB': chainB,
    'effectsVersion': effectsVersion,
  };
  factory EncounterResult.fromJson(Map<String, dynamic> j) => EncounterResult(
    id: j['id'],
    a: Combatant.fromJson(j['a']),
    b: Combatant.fromJson(j['b']),
    kind: EncounterKind.values.byName(j['kind']),
    winnerId: j['winner'],
    escapedId: j['escaped'],
    damageA: (j['damageA'] as num).toDouble(),
    damageB: (j['damageB'] as num).toDouble(),
    crewLossA: j['crewLossA'],
    crewLossB: j['crewLossB'],
    coins: j['coins'],
    gems: j['gems'],
    burnedA: j['burnedA'] ?? 0,
    burnedB: j['burnedB'] ?? 0,
    loot: j['loot'] ?? 0,
    chainA: (j['chainA'] as num? ?? 0).toDouble(),
    chainB: (j['chainB'] as num? ?? 0).toDouble(),
    effectsVersion: j['effectsVersion'] ?? 0,
  );
}

abstract interface class EncounterResolver {
  EncounterResult resolve(String id, Combatant a, Combatant b);
}

/// Deliberately small deterministic prototype policy. Replace this, not the theater.
class PrototypeResolver implements EncounterResolver {
  const PrototypeResolver();
  @override
  EncounterResult resolve(String id, Combatant a, Combatant b) {
    double strength(Combatant c) =>
        c.hullHp +
        c.crew * 1.5 * c.crewEffectiveness +
        c.firepower * 5 +
        c.handling * 20 +
        c.openingAttack * (c.hullHp + c.firepower * 5) +
        c.openingVolley * 100;
    final ap = strength(a), bp = strength(b);
    final forcedB =
        !b.owned && b.role == BehaviorMode.merchant && b.attacks >= 2;
    final escape =
        !forcedB &&
        b.wantsEscape &&
        (b.role == BehaviorMode.merchant || b.role == BehaviorMode.explorer) &&
        b.speed > a.speed * 1.15;
    final draw = (ap - bp).abs() <= math.max(ap, bp) * .05;
    final dominant = ap >= bp ? a : b;
    final kind = forcedB
        ? EncounterKind.cannon
        : escape
        ? EncounterKind.escape
        : dominant.ordnance == 'grape'
        ? EncounterKind.boarding
        : dominant.ordnance == 'heavy' || dominant.ordnance == 'fire'
        ? EncounterKind.cannon
        : math.max(ap, bp) > math.min(ap, bp) * 1.7
        ? EncounterKind.cannon
        : EncounterKind.boarding;
    final winner = forcedB
        ? a.id
        : escape || draw
        ? null
        : ap > bp
        ? a.id
        : b.id;
    double damage(Combatant c) {
      final enemy = c.id == a.id ? b : a;
      if (!escape &&
          (!draw || forcedB) &&
          kind == EncounterKind.cannon &&
          winner != c.id) {
        return c.hullHp;
      }
      return math.min(
        c.hullHp,
        c.maxHullHp *
            (escape
                ? .03
                : kind == EncounterKind.cannon
                ? .15
                : .08) *
            (1 - c.damageReduction.clamp(0, .35)) *
            (enemy.ordnance == 'fire'
                ? 1.35
                : enemy.ordnance == 'grape'
                ? .7
                : 1),
      );
    }

    int crewLoss(Combatant c) {
      final enemy = c.id == a.id ? b : a;
      if (!escape &&
          !draw &&
          kind == EncounterKind.boarding &&
          winner != c.id) {
        return c.crew;
      }
      return math.min(
        c.crew,
        (c.crew *
                    (escape
                        ? 0
                        : kind == EncounterKind.cannon
                        ? (enemy.ordnance == 'grape' ? .16 : .02)
                        : (enemy.ordnance == 'grape' ? .22 : .08)) *
                    (1 - c.crewDefense) +
                (kind == EncounterKind.boarding
                    ? c.crew * enemy.openingVolley
                    : 0))
            .floor(),
      );
    }

    final ownedWin =
        winner != null &&
        ((winner == a.id && a.owned) || (winner == b.id && b.owned));
    final burnedA = b.ordnance == 'fire' ? (a.cargo * .5).ceil() : 0;
    final burnedB = a.ordnance == 'fire' ? (b.cargo * .5).ceil() : 0;
    final loser = winner == a.id ? b : a;
    final burned = winner == a.id ? burnedB : burnedA;
    final salvage = kind == EncounterKind.cannon
        ? 1
        : math.max(2, loser.cargo - burned);
    final loot = winner == null ? 0 : salvage;
    final reward = kind == EncounterKind.cannon ? 2 : 25;
    return EncounterResult(
      id: id,
      a: a,
      b: b,
      kind: kind,
      winnerId: winner,
      escapedId: escape ? b.id : null,
      damageA: damage(a),
      damageB: damage(b),
      crewLossA: crewLoss(a),
      crewLossB: crewLoss(b),
      coins: ownedWin
          ? (reward * (1 + (winner == a.id ? a.economyBonus : b.economyBonus)))
                .floor()
          : 0,
      burnedA: burnedA,
      burnedB: burnedB,
      loot: loot,
      chainA: b.ordnance == 'chain' ? .55 : 0,
      chainB: a.ordnance == 'chain' ? .55 : 0,
      effectsVersion: 1,
      gems: ownedWin ? 1 : 0,
    );
  }
}
