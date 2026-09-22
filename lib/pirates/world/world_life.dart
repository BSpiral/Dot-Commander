import 'dart:math';
import '../../core/simulation/vessel.dart';
import '../encounters/pirates_voyage.dart';
import '../progression/fleet_progress.dart';
import '../progression/life_balance.dart';
import '../ships/hull_catalog.dart';
import 'discoveries.dart';

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
  // Ship/combat overhaul pass 2026-09-21 (pirate/hunter ecosystem
  // damping): counts down toward 0; a new hunter may only be recruited
  // once it's at 0 (then reset -- see tick's own hunter-recruitment
  // block). Root cause this fixes: `required` was recomputed fresh from
  // the INSTANTANEOUS pirateCount every single tick with no cooldown at
  // all, so a pirateCount that bounces across LifeBalance.hunterThresholds
  // (rising/falling faster than a spawned hunter batch can visibly
  // suppress piracy and then retire) could trigger repeated fresh
  // recruitment rounds stacking on top of a still-retiring previous
  // batch -- a real live report: 8 pirates/0 hunters, then ~10 minutes
  // later 10 hunters/1 pirate. hunterThresholds/hunterRetire already give
  // spawn-vs-retire a real hysteresis GAP (4/8 to trigger vs 2 to
  // retire); this adds the missing TIME dimension, matching the same
  // "roll on a clock, not every tick" pattern arrivalClock/arrivalInterval
  // already use for ordinary NPC arrivals just below.
  double hunterSpawnCooldown = 0;
  // Per-ship escalating discovery probability -- see checkDiscovery.
  // Keyed by ship ID so each of the player's commands builds its own
  // independent luck streak; absent entries mean "at base probability"
  // (never rolled yet, or just reset by a successful find).
  final Map<String, double> discoveryProbability = {};
  WorldLife(this.v);
  void log(Vessel s, String message) {
    s.recentActivity.insert(0, message);
    if (s.recentActivity.length > LifeBalance.logLimit) {
      s.recentActivity.removeLast();
    }
    v.revision++;
  }

  /// Rolls one Explorer discovery check for [s], called exactly once per
  /// qualifying observation -- see PiratesVoyage.update, which fires this
  /// the moment a ship's activity transitions into Activity.observing
  /// (arriving at and completing a look at a search-kind destination).
  /// Not a fixed timer: how often this actually fires depends entirely
  /// on how often the ship reaches a new observation point, which itself
  /// varies with real travel distance/time -- exactly the "10 seconds
  /// apart, 90 seconds apart" organic pacing this was asked for.
  ///
  /// A failed roll raises the probability for THIS ship's next
  /// qualifying observation (capped); a successful one resets to base
  /// and grants a flavored reward drawn from discoveries.dart, weighted
  /// so small finds are common and great finds are rare.
  void checkDiscovery(Vessel s) {
    if (!s.playerOwned || s.behavior != BehaviorMode.explorer) return;
    final current =
        discoveryProbability[s.id] ?? Balance.discoveryBaseProbability;
    if (v.rng.nextDouble() >= current) {
      discoveryProbability[s.id] = (current + Balance.discoveryProbabilityStep)
          .clamp(Balance.discoveryBaseProbability, Balance.discoveryProbabilityCap);
      return;
    }
    discoveryProbability[s.id] = Balance.discoveryBaseProbability;
    final tierRoll = v.rng.nextDouble();
    final tier = tierRoll < .04
        ? DiscoveryTier.great
        : tierRoll < .22
        ? DiscoveryTier.good
        : DiscoveryTier.small;
    final options = discoveryContent.where((d) => d.tier == tier).toList();
    final found = options[v.rng.nextInt(options.length)];
    v.coins += found.gold;
    v.gems += found.gems;
    log(s, found.flavor);
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
    // Final corrections pass 2026-09-20: fixed the same trade-profit
    // double count as startPort (s.economyBonus already contains
    // bonus(portRelations) once -- see FleetProgress.apply), and split
    // "tree soft cap" from "final safety ceiling": the tree-only
    // contribution stops growing at fieldRepairDiscountTreeCap (35%,
    // unchanged number, now correctly scoped as tree-only rather than
    // final), while portRelations' own equipment/other bonus can push
    // the total further, up to finalSafetyCeiling (90%) -- this
    // formula has NO other protection at its use site below, so
    // dropping the final ceiling entirely would let field-repair price
    // go negative (the game paying the player), a genuine mechanical
    // requirement, not an inherited generic cap.
    final portRelationsTree = bonus(s, CommandTrack.portRelations);
    final portRelationsEquipment = s.economyBonus - portRelationsTree;
    final discount = (portRelationsTree.clamp(0, LifeBalance.fieldRepairDiscountTreeCap) + portRelationsEquipment)
        .clamp(0, LifeBalance.finalSafetyCeiling);
    final modifier = 1 - discount;
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
      // Ship/combat overhaul pass 2026-09-21: was the raw hull base --
      // a ship that has genuinely grown past it via Command Tree crew
      // investment (see FleetProgress.crewCapacity) would otherwise never
      // be considered short of crew at all once past that base, even
      // mid-battle-losses.
      final amount = min(
        LifeBalance.fieldLimit,
        max(0, v.progress.crewCapacity(s) - s.crewCount),
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
    // The universal every-Nth-visit trickle excludes Merchant behavior:
    // Merchant has its own dedicated gem progression below (the
    // dock-streak trickle, gated on actual successful trades), and
    // letting Merchant docks also feed this generic counter would let
    // a single dock/trade event double-dip both gem sources at once
    // (their thresholds can land on the same event by construction,
    // not just coincidence). Every other player behavior (pirate,
    // explorer, privateer) is unaffected and keeps this trickle
    // exactly as before.
    if (s.playerOwned && s.behavior != BehaviorMode.merchant) {
      v.progress.visits++;
      if (v.progress.visits % Balance.visitsPerGem == 0) {
        v.gems++;
        log(s, 'Loyal-visit bonus: +1 gem');
      }
    }
    // Final corrections pass 2026-09-20, fixing Port Relations
    // trade-profit double counting: s.economyBonus ALREADY equals
    // c.percent(portRelations) + equipment (see FleetProgress.apply) --
    // it must not be added to bonus(portRelations) again on top of
    // itself (the previous `bonus(...) + s.economyBonus` pattern
    // double-counted the tree contribution). tradeBonus below is the
    // single, correctly-counted value for the sale-price multiplier
    // (no ceiling -- Trade Profit Bonus is uncapped).
    final tradeBonus = s.economyBonus;
    final hull = bonus(s, CommandTrack.hull), crew = bonus(s, CommandTrack.crew);
    // Port Service Discount: the TREE portion (hull + portRelations,
    // matching the pre-existing blended structure) is soft-capped at
    // portServiceDiscountTreeCap (50%, raised from 20%); portRelations'
    // own equipment/other bonus -- isolated from economyBonus so the
    // tree portion already counted above isn't counted twice -- can
    // push the final discount further, up to finalSafetyCeiling (90%).
    // Repair and crew-refill get their own discount (hull vs crew tree
    // contribution differs) but share the same portRelations term,
    // matching the original formula's structure.
    final portRelationsTree = bonus(s, CommandTrack.portRelations);
    final portRelationsEquipment = s.economyBonus - portRelationsTree;
    final repairDiscount = ((hull + portRelationsTree).clamp(0, LifeBalance.portServiceDiscountTreeCap) + portRelationsEquipment)
        .clamp(0, LifeBalance.finalSafetyCeiling);
    final crewDiscount = ((crew + portRelationsTree).clamp(0, LifeBalance.portServiceDiscountTreeCap) + portRelationsEquipment)
        .clamp(0, LifeBalance.finalSafetyCeiling);
    // Port Relations balance pass 2026-09-20: cargo/repair-per-visit
    // capacity used to passively ride the SAME `port` value as the
    // price discount/trade bonus (capped at a barely-visible +30% even
    // at full investment). Both are now their own explicit, much
    // longer-ranged integer progressions of the SAME portRelations
    // level -- see CommandProgress.portCargoSupply/portRepairSupply.
    // Crew refill keeps the OLD flat base (10) unscaled -- no new
    // progression was requested for it this pass.
    final cmd = v.progress.commands[s.id];
    final cargoSupply = cmd?.portCargoSupply ?? LifeBalance.cargoPortCapacity;
    final repairSupply = cmd?.portRepairSupply ?? LifeBalance.serviceCapacity;
    final repair = min(max(0.0, s.maxHullHp - s.hullHp), repairSupply.toDouble());
    final refill = min(
      max(0, v.progress.crewCapacity(s) - s.crewCount),
      LifeBalance.serviceCapacity,
    );
    final w = PortWork(
      s.id,
      repair,
      refill,
      (repair * LifeBalance.repairPrice * (1 - repairDiscount)).ceil(),
      (refill * LifeBalance.crewPrice * (1 - crewDiscount)).ceil(),
      cargoSupply,
    );
    works[s.id] = w;
    v.heldShips.add(s.id);
    s.activity = Activity.docked;
    log(s, 'Arrived ${s.destination?.name}');
    final sold = min(s.cargo, w.buyLimit);
    s.cargo -= sold;
    final sale = (sold * LifeBalance.cargoSell * (1 + tradeBonus)).floor();
    if (s.playerOwned) v.coins += sale;
    log(s, 'Sold $sold cargo +$sale coins');
    // Merchant-specific gem trickle: a legitimate gem source through
    // merchant gameplay itself (active trading), not requiring a switch
    // to pirate/privateer combat. Counts successful trade completions
    // (this dock, with sold > 0), not sale value -- see
    // Balance.merchantDocksPerGem. Idle docking with nothing to sell
    // (sold == 0, e.g. an empty hold) never reaches this branch, so it
    // can't be farmed by looping empty dock visits.
    if (s.playerOwned && s.behavior == BehaviorMode.merchant && sold > 0) {
      v.progress.merchantDockStreak++;
      if (v.progress.merchantDockStreak >= Balance.merchantDocksPerGem) {
        v.progress.merchantDockStreak = 0;
        v.gems++;
        log(s, 'Trade bonus: +1 gem');
      }
    }
    w.remaining = max(
      LifeBalance.minimumServiceStage,
      LifeBalance.serviceSeconds(sold.toDouble(), serviceMultiplier(s)),
    );
  }

  double serviceMultiplier(Vessel s, {String? specialist}) {
    // Final corrections pass 2026-09-20: Port Service Speed's tree soft
    // cap raised from 20% (the old generic percentCap) to 50%
    // (portServiceSpeedTreeCap). No equipment currently feeds this
    // formula (crew/portRelations tree bonuses only), so the extra
    // finalSafetyCeiling clamp is a no-op today -- kept for structural
    // consistency and so a future equipment modifier ("if supported",
    // per the design brief) would be safely bounded without further
    // changes here.
    final treeSpeed = (bonus(s, CommandTrack.crew) + bonus(s, CommandTrack.portRelations))
        .clamp(0, LifeBalance.portServiceSpeedTreeCap);
    final base = 1 - treeSpeed.clamp(0, LifeBalance.finalSafetyCeiling);
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
      s.crewCount = min(v.progress.crewCapacity(s), s.crewCount + w.crew);
      w.phase = 3;
      final free = max(0, v.progress.effectiveHoldCapacity(s) - s.cargo);
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
      // Live playtest repair pass 2026-09-20: this used to re-clamp to
      // the RAW hull base (hullFor(s.hullType).holds) even though `free`
      // just above already correctly sized w.bought against the ship's
      // real effective capacity (cargoCeiling + equipment) -- silently
      // discarding any cargo bought past the hull's own base, making
      // legitimate Hull cargo upgrades meaningless in practice.
      s.cargo = min(v.progress.effectiveHoldCapacity(s), s.cargo + w.bought);
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

  // Encounter/ship-selection balance pass 2026-09-21: Man-of-War used to
  // be drawn UNIFORMLY with Frigate/Brig within the ordinary (non-hunter)
  // Privateer hull pool -- a 1-in-3 chance, compounding with Privateer's
  // own (now-reduced, see LifeBalance.roleWeights) ambient population
  // weight to make Man-of-War feel like ordinary traffic rather than the
  // rare "OH FUCK, do not fight that" encounter it's meant to be.
  // Frigate/Brig stay common and comparably threatening; Man-of-War is
  // now a genuine minority outcome.
  static const _privateerHullWeights = {
    'Frigate': .45,
    'Brig': .45,
    'Man-of-War': .10,
  };
  String _weightedHull(Map<String, double> weights) {
    var roll = v.rng.nextDouble() * weights.values.reduce((a, b) => a + b);
    for (final entry in weights.entries) {
      roll -= entry.value;
      if (roll <= 0) return entry.key;
    }
    return weights.keys.last;
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
      BehaviorMode.privateer => null, // see _privateerHullWeights below
    };
    final chosenHull = hunter
        ? 'Frigate'
        : role == BehaviorMode.privateer
        ? _weightedHull(_privateerHullWeights)
        : hulls![v.rng.nextInt(hulls.length)];
    final h = hullFor(chosenHull);
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
    // Pirate floor: guarantee a normal, playing world always has at
    // least one pirate somewhere in play -- either actively at sea, or
    // due back from a defeat respawn timer -- so the pirate lifecycle
    // (creation, routing, combat, respawn) is actually provable and a
    // normal player encounters one. Fires only when NO pirate anywhere
    // qualifies (a truly empty roster, or one that permanently
    // departed via departureChance and will never return on its own);
    // a pirate that's merely between defeat and its 60s respawn still
    // counts, so this can never stack a second pirate on top of one
    // already due back. This is a floor of exactly 1, not a frequency
    // change -- pirateCount is necessarily 0 whenever this fires (see
    // below), so it can't push past maxPirates either.
    final hasPirate = v.ships.any(
      (s) =>
          s.behavior == BehaviorMode.pirate &&
          (s.atSea || s.respawnRemaining > 0),
    );
    if (v.ships.length >= LifeBalance.minRosterForPopulationFloors &&
        !hasPirate &&
        npcCount < LifeBalance.maxNpcs) {
      spawn(BehaviorMode.pirate);
    }
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
    hunterSpawnCooldown = max(0, hunterSpawnCooldown - dt);
    if (hunters < required) {
      if (hunterSpawnCooldown == 0) {
        spawn(BehaviorMode.privateer, hunter: true);
        // Only ONE recruitment per cooldown window, even if `required`
        // jumped by 2 at once -- deliberately conservative: a genuinely
        // sustained (not momentary) pirate surge will still reach
        // `required` over a couple of cooldown windows, but a single
        // bounce across the threshold can never mint a whole fresh
        // batch in one shot.
        hunterSpawnCooldown = LifeBalance.hunterSpawnCooldownSeconds;
      }
    } else {
      hunterSpawnCooldown = 0;
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
      // Below the critical floor, this arrival is guaranteed rather
      // than merely LifeBalance.arrivalChance likely -- see
      // LifeBalance.criticalNpcFloor for why: combat losses (a
      // permanent removal for non-pirate/hunter NPCs, by design) can
      // outpace the probabilistic trickle regardless of how that
      // trickle alone is tuned. Above the floor, arrivals stay purely
      // probabilistic, preserving natural fluctuation and never
      // forcing the world toward maxNpcs.
      final guaranteed =
          v.ships.length >= LifeBalance.minRosterForPopulationFloors &&
          npcCount < LifeBalance.criticalNpcFloor;
      if (npcCount < LifeBalance.maxNpcs &&
          (guaranteed || v.rng.nextDouble() < LifeBalance.arrivalChance)) {
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
    'discoveryProbability': discoveryProbability,
    'hunterSpawnCooldown': hunterSpawnCooldown,
  };
  void restore(Map<String, dynamic> j) {
    arrivalClock = (j['clock'] as num).toDouble();
    nextNpc = j['nextNpc'];
    if (!arrivalClock.isFinite || arrivalClock < 0 || nextNpc < 1) {
      throw const FormatException('Invalid world clock');
    }
    // Absent in saves from before this pass -- 0 (cooldown already
    // elapsed) is a safe, conservative default, matching how a fresh
    // WorldLife already starts.
    hunterSpawnCooldown = (j['hunterSpawnCooldown'] as num? ?? 0).toDouble();
    if (!hunterSpawnCooldown.isFinite ||
        hunterSpawnCooldown < 0 ||
        hunterSpawnCooldown > LifeBalance.hunterSpawnCooldownSeconds) {
      throw const FormatException('Invalid hunter spawn cooldown');
    }
    discoveryProbability.clear();
    final rawProbability = j['discoveryProbability'] as Map<String, dynamic>?;
    if (rawProbability != null) {
      for (final entry in rawProbability.entries) {
        final value = (entry.value as num).toDouble();
        if (!value.isFinite ||
            value < Balance.discoveryBaseProbability ||
            value > Balance.discoveryProbabilityCap) {
          throw const FormatException('Invalid discovery probability');
        }
        discoveryProbability[entry.key] = value;
      }
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
