import 'dart:math';
import '../../core/simulation/vessel.dart';
import '../encounters/pirates_voyage.dart';
import '../progression/fleet_progress.dart';
import '../progression/life_balance.dart';
import '../ships/hull_catalog.dart';

class PortWork {
  final String shipId;
  final double hull;
  final int crew, repairCost, crewCost, buyLimit;
  int phase = 0, bought = 0;
  double remaining = 0;
  bool poor = false;
  PortWork(
    this.shipId,
    this.hull,
    this.crew,
    this.repairCost,
    this.crewCost,
    this.buyLimit,
  );
  String get status => [
    'Selling cargo / Unloading',
    'Repairing Hull',
    'Restoring Crew',
    'Buying cargo / Loading cargo',
    'Departing',
  ][phase.clamp(0, 4)];
  Map<String, dynamic> toJson() => {
    'ship': shipId,
    'hull': hull,
    'crew': crew,
    'repairCost': repairCost,
    'crewCost': crewCost,
    'buyLimit': buyLimit,
    'phase': phase,
    'bought': bought,
    'remaining': remaining,
    'poor': poor,
  };
  factory PortWork.fromJson(Map<String, dynamic> j) {
    final w = PortWork(
      j['ship'],
      (j['hull'] as num).toDouble(),
      j['crew'],
      j['repairCost'],
      j['crewCost'],
      j['buyLimit'],
    );
    w.phase = j['phase'];
    w.bought = j['bought'];
    w.remaining = (j['remaining'] as num).toDouble();
    w.poor = j['poor'];
    if (w.phase < 0 ||
        w.phase > 4 ||
        !w.remaining.isFinite ||
        w.remaining < 0 ||
        w.hull < 0 ||
        w.crew < 0) {
      throw const FormatException('Invalid port work');
    }
    return w;
  }
}

/// Operational authority; renderers only inspect ships and work progress.
class WorldLife {
  final PiratesVoyage v;
  final Map<String, PortWork> works = {};
  double arrivalClock = 0;
  int nextNpc = 1;
  WorldLife(this.v);
  void log(Vessel s, String message) {
    s.recentActivity.insert(0, message);
    if (s.recentActivity.length > LifeBalance.logLimit) {
      s.recentActivity.removeLast();
    }
    v.revision++;
  }

  int get npcCount => v.ships.where((s) => s.atSea && !s.playerOwned).length;
  int get pirateCount =>
      v.ships.where((s) => s.atSea && s.behavior == BehaviorMode.pirate).length;
  Destination portFor(Vessel s) {
    final pirate = s.behavior == BehaviorMode.pirate;
    var ports = v.places
        .where(
          (p) =>
              p.kind == DestinationKind.port &&
              (pirate ? p.id == 'tortuga' : p.id != 'tortuga'),
        )
        .toList();
    if (ports.isEmpty) {
      ports = v.places.where((p) => p.kind == DestinationKind.port).toList();
    }
    ports.sort(
      (a, b) => s.position
          .distanceTo(a.position)
          .compareTo(s.position.distanceTo(b.position)),
    );
    return ports.first;
  }

  double bonus(Vessel s, CommandTrack t) =>
      v.progress.commands[s.id]?.percent(t) ?? 0;
  void defeat(Vessel s) {
    if (!s.atSea) return;
    log(s, 'Defeated: cargo lost ${s.cargo}');
    s.cargo = 0;
    s.atSea = false;
    s.activity = Activity.sailing;
    s.destination = portFor(s);
    s.recovering = true;
    s.returnToPort = true;
    v.heldShips.remove(s.id);
    works.remove(s.id);
    s.respawnRemaining = s.playerOwned
        ? LifeBalance.playerRespawn
        : (s.behavior == BehaviorMode.pirate || s.hunter
              ? LifeBalance.pirateRespawn
              : 0);
    log(
      s,
      s.behavior == BehaviorMode.pirate
          ? 'Removed from waters; returning through Pirate Haven'
          : 'Returning through port',
    );
  }

  void fieldSupport(Vessel s) {
    if (v.inBattle(s.id)) return;
    final c = v.progress.commands[s.id];
    if (c == null) return;
    final specialist = c.equipped.containsKey(ItemKind.carpenter)
        ? 'carpenter'
        : (v.progress.item(c.equipped[ItemKind.bosun])?.specialist ??
              v.progress.item(c.equipped[ItemKind.quartermaster])?.specialist);
    final modifier =
        1 -
        (bonus(s, CommandTrack.portRelations) + s.economyBonus).clamp(0, .35);
    if (specialist == 'carpenter') {
      final amount = min(
        LifeBalance.fieldLimit.toDouble() + s.fieldRepairBonus,
        s.maxHullHp - s.hullHp,
      );
      final price =
          (amount *
                  LifeBalance.repairPrice *
                  LifeBalance.fieldPriceMultiplier *
                  modifier)
              .ceil();
      if (amount > 0 && v.coins >= price) {
        v.coins -= price;
        s.hullHp += amount;
        log(
          s,
          'Carpenter field repaired +${amount.toStringAsFixed(1)} Hull (-$price coins)',
        );
      }
    } else if (specialist == 'bosun') {
      final amount = min(
        LifeBalance.fieldLimit,
        max(0, hullFor(s.hullType).crew - s.crewCount),
      );
      final price =
          (amount *
                  LifeBalance.crewPrice *
                  LifeBalance.fieldPriceMultiplier *
                  modifier)
              .ceil();
      if (amount > 0 && v.coins >= price) {
        v.coins -= price;
        s.crewCount += amount;
        log(s, 'Bosun restored +$amount Crew (-$price coins)');
      }
    }
  }

  void attacked(Vessel s, Vessel by) {
    log(s, 'Attacked by ${by.name}');
    if (!s.playerOwned && s.behavior == BehaviorMode.merchant) {
      s.attacksSincePort++;
    }
  }

  void startPort(Vessel s) {
    if (v.inBattle(s.id) || s.activity == Activity.engaged) return;
    if (works.containsKey(s.id)) return;
    s.attacksSincePort = 0;
    if (!s.playerOwned && s.fleeing && s.behavior == BehaviorMode.merchant) {
      s.atSea = false;
      s.respawnRemaining = 0;
      s.fleeing = false;
      s.threatId = null;
      log(s, 'Escaped to port; voyage completed');
      for (final other in v.ships) {
        if (!v.busy(other.id) && other.destination?.id == s.id) {
          v.npc.disengage(other, s.id);
        }
      }
      return;
    }
    if (!s.playerOwned &&
        (s.retiring || v.rng.nextDouble() < LifeBalance.departureChance)) {
      s.atSea = false;
      s.respawnRemaining = 0;
      log(s, 'Departed world at ${s.destination?.name}');
      return;
    }
    final port = (bonus(s, CommandTrack.portRelations) + s.economyBonus).clamp(
          0,
          .35,
        ),
        hull = bonus(s, CommandTrack.hull),
        crew = bonus(s, CommandTrack.crew);
    final capacity = (LifeBalance.serviceCapacity * (1 + port)).floor();
    final repair = min(max(0.0, s.maxHullHp - s.hullHp), capacity.toDouble());
    final refill = min(
      max(0, hullFor(s.hullType).crew - s.crewCount),
      capacity,
    );
    final w = PortWork(
      s.id,
      repair,
      refill,
      (repair * LifeBalance.repairPrice * (1 - min(.2, hull + port))).ceil(),
      (refill * LifeBalance.crewPrice * (1 - min(.2, crew + port))).ceil(),
      (LifeBalance.cargoPortCapacity * (1 + port)).floor(),
    );
    works[s.id] = w;
    v.heldShips.add(s.id);
    s.activity = Activity.docked;
    log(s, 'Arrived ${s.destination?.name}');
    final sold = min(s.cargo, w.buyLimit);
    s.cargo -= sold;
    final sale = (sold * LifeBalance.cargoSell * (1 + port)).floor();
    if (s.playerOwned) v.coins += sale;
    log(s, 'Sold $sold cargo +$sale coins');
    w.remaining = max(
      LifeBalance.minimumServiceStage,
      LifeBalance.serviceSeconds(sold.toDouble(), serviceMultiplier(s)),
    );
  }

  double serviceMultiplier(Vessel s, {String? specialist}) {
    final base =
        1 -
        min(
          LifeBalance.percentCap,
          bonus(s, CommandTrack.crew) + bonus(s, CommandTrack.portRelations),
        );
    final command = v.progress.commands[s.id];
    final role = command?.equipped.containsKey(ItemKind.carpenter) == true
        ? 'carpenter'
        : (v.progress.item(command?.equipped[ItemKind.bosun])?.specialist ??
              v.progress
                  .item(command?.equipped[ItemKind.quartermaster])
                  ?.specialist);
    return base *
        (specialist != null && role == specialist
            ? 1 - LifeBalance.specialistServiceReduction
            : 1);
  }

  void _advance(Vessel s, PortWork w) {
    final speed = serviceMultiplier(s);
    if (w.phase == 0) {
      w.phase = 1;
      final pay = s.playerOwned ? min(v.coins, w.repairCost) : w.repairCost;
      w.poor = pay < w.repairCost;
      if (s.playerOwned) v.coins -= pay;
      log(
        s,
        'Repairing Hull ${w.hull.toStringAsFixed(1)} / ${LifeBalance.serviceCapacity}: -$pay coins',
      );
      w.remaining = LifeBalance.serviceSeconds(
        w.hull,
        serviceMultiplier(s, specialist: 'carpenter'),
      );
    } else if (w.phase == 1) {
      s.hullHp = min(s.maxHullHp, s.hullHp + w.hull);
      s.chainPenalty = 0;
      w.phase = 2;
      final pay = s.playerOwned ? min(v.coins, w.crewCost) : w.crewCost;
      w.poor = w.poor || pay < w.crewCost;
      if (s.playerOwned) v.coins -= pay;
      log(s, 'Restoring Crew ${w.crew}: -$pay coins');
      w.remaining = LifeBalance.serviceSeconds(
        w.crew.toDouble(),
        serviceMultiplier(s, specialist: 'bosun'),
      );
    } else if (w.phase == 2) {
      s.crewCount = min(hullFor(s.hullType).crew, s.crewCount + w.crew);
      w.phase = 3;
      final free = max(0, hullFor(s.hullType).holds - s.cargo);
      w.poor = w.poor || (s.playerOwned && v.coins < LifeBalance.cargoBuy);
      if (w.poor) {
        s.cargo = 0;
        w.bought = 1;
        log(s, 'Poor tax: one restart cargo; limited service only');
      } else {
        w.bought = !s.playerOwned && s.behavior == BehaviorMode.pirate
            ? 0
            : min(free, w.buyLimit);
        if (s.playerOwned) {
          w.bought = min(w.bought, v.coins ~/ LifeBalance.cargoBuy);
        }
        if (s.playerOwned) v.coins -= w.bought * LifeBalance.cargoBuy;
      }
      log(
        s,
        'Bought ${w.bought} cargo -${w.poor ? 0 : w.bought * LifeBalance.cargoBuy} coins',
      );
      w.remaining = LifeBalance.serviceSeconds(w.bought.toDouble(), speed);
    } else {
      s.cargo = min(hullFor(s.hullType).holds, s.cargo + w.bought);
      w.phase = 4;
      s.fleeing = false;
      s.threatId = null;
      s.fleeTime = 0;
      s.recovering = false;
      s.returnToPort = false;
      works.remove(s.id);
      v.heldShips.remove(s.id);
      s.pauseRemaining = 0;
      log(s, 'Departed ${s.destination?.name}');
      if (s.hunter && pirateCount <= LifeBalance.hunterRetire) {
        s.atSea = false;
        return;
      }
      v.setBehavior(s, s.behavior);
    }
  }

  BehaviorMode weightedRole() {
    final counts = List<int>.filled(4, 0);
    for (final s in v.ships.where(
      (s) => s.atSea && !s.playerOwned && !s.hunter,
    )) {
      counts[s.behavior.index]++;
    }
    final weights = [
      for (var i = 0; i < 4; i++)
        LifeBalance.roleWeights[i] *
            (1 +
                max(
                  0.0,
                  LifeBalance.roleWeights[i] * max(1, npcCount) - counts[i],
                )) /
            (1 + counts[i]),
    ];
    if (counts[1] >= LifeBalance.maxPirates) weights[1] = 0;
    var roll = v.rng.nextDouble() * weights.reduce((a, b) => a + b);
    for (var i = 0; i < 4; i++) {
      roll -= weights[i];
      if (roll <= 0) return BehaviorMode.values[i];
    }
    return BehaviorMode.merchant;
  }

  void spawn(BehaviorMode role, {bool hunter = false}) {
    if (npcCount >= LifeBalance.maxNpcs) return;
    final hulls = switch (role) {
      BehaviorMode.merchant => [
        'Cog',
        'Fluyt',
        'Galley',
        'Galleon',
        'Schooner',
      ],
      BehaviorMode.pirate => ['Schooner', 'Brig', 'Frigate', 'Sloop'],
      BehaviorMode.explorer => ['Pirogue', 'Barque', 'Sloop', 'Schooner'],
      BehaviorMode.privateer => ['Frigate', 'Brig', 'Man-of-War'],
    };
    final h = hullFor(hunter ? 'Frigate' : hulls[v.rng.nextInt(hulls.length)]);
    final first = v.ships.first;
    final s = Vessel(
      id: 'arrival-${nextNpc++}',
      name: hunter ? 'Pirate Hunter $nextNpc' : 'Voyager $nextNpc',
      captain: 'Captain $nextNpc',
      hullType: h.name,
      position: first.position,
      speed: h.baseSpeed,
      maxHullHp: h.hp,
      crewCount: h.crew,
      behavior: role,
    )..hunter = hunter;
    s.position = portFor(s).position;
    s.firepower = h.guns * (hunter ? 1.2 : 1.0);
    v.ships.add(s);
    log(s, 'Entered waters');
  }

  void tick(double dt) {
    for (final s in v.ships.toList()) {
      if (!s.atSea && s.respawnRemaining > 0) {
        s.respawnRemaining = max(0, s.respawnRemaining - dt);
        if (s.respawnRemaining == 0) {
          if (!s.playerOwned && npcCount >= LifeBalance.maxNpcs) {
            s.respawnRemaining = .1;
            continue;
          }
          s.position = portFor(s).position;
          s.destination = portFor(s);
          s.atSea = true;
          s.activity = Activity.docked;
          startPort(s);
        }
      }
    }
    for (final w in works.values.toList()) {
      final s = v.ships.firstWhere((s) => s.id == w.shipId);
      if (v.inBattle(s.id)) continue;
      w.remaining = max(0, w.remaining - dt);
      if (w.remaining == 0) _advance(s, w);
    }
    if (!v.encountersEnabled) return;
    final pressure = pirateCount;
    for (final s in v.ships.where((s) => s.atSea && s.hunter)) {
      if (pressure <= LifeBalance.hunterRetire && !s.retiring) {
        s.retiring = true;
        s.returnToPort = true;
        if (!v.busy(s.id)) v.setBehavior(s, s.behavior);
      }
    }
    final required = pressure >= LifeBalance.hunterThresholds[1]
        ? 2
        : pressure >= LifeBalance.hunterThresholds[0]
        ? 1
        : 0;
    final hunters = v.ships
        .where((s) => s.hunter && (s.atSea || s.respawnRemaining > 0))
        .length;
    for (var i = hunters; i < required; i++) {
      spawn(BehaviorMode.privateer, hunter: true);
    }
    if (v.ships.length > 60) {
      final candidates = v.ships
          .where(
            (s) =>
                !s.playerOwned &&
                !s.atSea &&
                s.respawnRemaining == 0 &&
                !v.active.any((r) => r.result.involves(s.id)) &&
                v.recent?.result.involves(s.id) != true,
          )
          .toList();
      for (final old in candidates) {
        if (v.ships.length <= 60) break;
        for (final s in v.ships) {
          if (s.destination?.kind == DestinationKind.ship &&
              s.destination?.id == old.id) {
            s.destination = null;
            s.activity = Activity.sailing;
            s.pauseRemaining = 0;
          }
        }
        v.ships.remove(old);
      }
    }
    arrivalClock += dt;
    if (arrivalClock >= LifeBalance.arrivalInterval) {
      arrivalClock %= LifeBalance.arrivalInterval;
      if (npcCount < LifeBalance.maxNpcs &&
          v.rng.nextDouble() < LifeBalance.arrivalChance) {
        spawn(weightedRole());
      }
    }
  }

  String status(Vessel s) => works[s.id] != null
      ? '${works[s.id]!.status} (${works[s.id]!.remaining.toStringAsFixed(1)}s)'
      : !s.atSea
      ? 'Waiting / recovery ${s.respawnRemaining.toStringAsFixed(0)}s'
      : s.activity == Activity.engaged
      ? 'Fighting'
      : s.fleeing
      ? 'Fleeing toward safety'
      : s.returnToPort
      ? 'Returning to port'
      : s.destination?.kind == DestinationKind.ship
      ? 'Chasing'
      : s.activity.name;
  Map<String, dynamic> toJson() => {
    'clock': arrivalClock,
    'nextNpc': nextNpc,
    'works': works.values.map((w) => w.toJson()).toList(),
  };
  void restore(Map<String, dynamic> j) {
    arrivalClock = (j['clock'] as num).toDouble();
    nextNpc = j['nextNpc'];
    if (!arrivalClock.isFinite || arrivalClock < 0 || nextNpc < 1) {
      throw const FormatException('Invalid world clock');
    }
    for (final x in j['works']) {
      final w = PortWork.fromJson(x);
      if (!v.ships.any((s) => s.id == w.shipId) ||
          works.containsKey(w.shipId) ||
          v.inBattle(w.shipId)) {
        throw const FormatException('Invalid port reservation');
      }
      works[w.shipId] = w;
      v.heldShips.add(w.shipId);
    }
  }
}
