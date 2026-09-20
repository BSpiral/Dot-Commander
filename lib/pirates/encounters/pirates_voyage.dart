import '../world/world_life.dart';
import '../world/npc_navigation.dart';
import '../progression/life_balance.dart';
import '../economy/port_economy.dart';
import '../progression/fleet_progress.dart';
import '../ships/hull_catalog.dart';
import 'dart:math';
import '../../core/simulation/simulation.dart';
import '../../core/simulation/vessel.dart';
import '../../core/movement/sea_navigation.dart';
import 'encounter_result.dart';

class EncounterRun {
  final EncounterResult result;
  double elapsed;
  EncounterRun(this.result, {this.elapsed = 0});
}

/// Voyage authority: detection, reservations, elapsed time and one-time application.
/// The renderer only reads this state. Pausing the engine pauses encounters too.
class PiratesVoyage extends Simulation {
  late final NpcNavigation npc = NpcNavigation(this);
  final bool npcDecisions;
  late final WorldLife life = WorldLife(this);
  PortReceipt? lastPort;
  late final FleetProgress progress = FleetProgress(ships);

  // Saturday repair pass 2026-09-20: the map-based "money ship" (replaces
  // the old rewarded-ad Gold button). Deliberately reuses the EXISTING
  // ship/navigation/rendering systems -- it's a completely ordinary
  // non-player Vessel (tagged isMoneyShip), so npc_navigation.dart's
  // generic "every non-player atSea ship" tick already sails it around
  // with zero new movement code. Only spawn timing, despawn, and claiming
  // are new. State here is session-only by design (not serialized -- see
  // VoyageStore.save filtering isMoneyShip ships out of the snapshot), so
  // an app restart simply starts a fresh cooldown rather than needing new
  // save-format fields for a lightweight bonus feature.
  double _moneyShipCooldownRemaining = 0, _moneyShipAliveSeconds = 0, _moneyShipCheckTimer = 0;

  void _tickMoneyShip(double dt) {
    final existing = ships.where((s) => s.isMoneyShip).toList();
    if (existing.isNotEmpty) {
      // The money ship is deliberately excluded from life.startPort and
      // checkDiscovery (see combatAvailable/the update() guard above --
      // it never enters WorldLife.works, so it never needs any special
      // case in save/restore for an id VoyageStore.save excludes from
      // the snapshot). Left alone, though, reaching a port/search
      // destination would still flip it to Activity.docked/observing via
      // the ordinary movement system and then sit there forever with
      // nothing to release it -- so simply give it a fresh destination
      // whenever that happens, keeping it perpetually underway. A ship
      // that never quite makes port is exactly the right feel for it
      // anyway.
      for (final s in existing) {
        if (s.activity == Activity.docked || s.activity == Activity.observing) {
          s.activity = Activity.sailing;
          s.destination = chooseDestination(s);
        }
      }
      _moneyShipAliveSeconds += dt;
      if (_moneyShipAliveSeconds >= Balance.moneyShipDespawnSimSeconds) {
        for (final s in existing) {
          ships.remove(s);
        }
        _moneyShipAliveSeconds = 0;
        _moneyShipCooldownRemaining = Balance.moneyShipCooldownSimSeconds;
        revision++;
      }
      return;
    }
    if (_moneyShipCooldownRemaining > 0) {
      _moneyShipCooldownRemaining = max(0, _moneyShipCooldownRemaining - dt);
      return;
    }
    _moneyShipCheckTimer += dt;
    if (_moneyShipCheckTimer < Balance.moneyShipSpawnCheckIntervalSimSeconds) {
      return;
    }
    _moneyShipCheckTimer = 0;
    if (rng.nextDouble() >= Balance.moneyShipSpawnChance) return;
    _spawnMoneyShip();
  }

  void _spawnMoneyShip() {
    final ports = places
        .where((p) => p.kind == DestinationKind.port && p.id != 'tortuga')
        .toList();
    if (ports.isEmpty) return;
    final port = ports[rng.nextInt(ports.length)];
    final h = hullFor('Galleon');
    ships.add(
      Vessel(
        id: 'money-ship-${rng.nextInt(1 << 31)}',
        name: 'The Gilded Prize',
        captain: 'Unknown',
        hullType: h.name,
        position: port.position,
        speed: h.baseSpeed,
        maxHullHp: h.hp,
        crewCount: h.crew,
        behavior: BehaviorMode.merchant,
        playerOwned: false,
      )..isMoneyShip = true,
    );
    revision++;
  }

  /// Claims [id]'s flat gold reward and removes it from the map. Returns
  /// the amount granted, or 0 if [id] isn't a currently-present money
  /// ship (already claimed/despawned/never existed) -- callers should
  /// treat 0 as "nothing happened," not an error.
  int claimMoneyShip(String id) {
    final match = ships.where((s) => s.id == id && s.isMoneyShip);
    if (match.isEmpty) return 0;
    ships.remove(match.first);
    coins += Balance.moneyShipReward;
    _moneyShipAliveSeconds = 0;
    _moneyShipCooldownRemaining = Balance.moneyShipCooldownSimSeconds;
    revision++;
    return Balance.moneyShipReward;
  }
  String? purchaseSlot() {
    final n = progress.commands.length;
    if (n >= 5 || coins < Balance.slotCosts[n]) return null;
    final base = ships.firstWhere((s) => s.playerOwned);
    final id = 'command-${n + 1}';
    if (ships.any((s) => s.id == id)) return null;
    final h = hullFor('Sloop');
    final ship = Vessel(
      id: id,
      name: [
        'Sea Lark',
        'Silver Tern',
        'Dawn Runner',
        'Salt Finch',
        'Amber Gull',
      ][n],
      captain: [
        'Alex Morgan',
        'Morgan Reed',
        'Robin Vale',
        'Sam Bell',
        'Jamie West',
      ][n],
      hullType: h.name,
      position: places
          .firstWhere((p) => p.kind == DestinationKind.port)
          .position,
      speed: h.baseSpeed,
      maxHullHp: h.hp,
      crewCount: h.crew,
      behavior: base.behavior,
      playerOwned: true,
    );
    coins -= Balance.slotCosts[n];
    ships.add(ship);
    progress.commands[id] = CommandProgress(id);
    progress.apply(ship);
    revision++;
    return id;
  }

  bool buyTree(String id, CommandTrack track) {
    final c = progress.commands[id];
    if (c == null || busy(id)) return false;
    final level = c.level(track), cost = LifeBalance.cost(c.level(track));
    if (level >= LifeBalance.maxLevels || coins < cost) return false;
    coins -= cost;
    c.tree[track] = level + 1;
    progress.apply(ships.firstWhere((s) => s.id == id));
    if (recent?.result.involves(id) == true) recent = null;
    revision++;
    return true;
  }

  bool buyFleetTree(FleetTrack track) {
    if (track != FleetTrack.offline && track != FleetTrack.shipHold) {
      return false;
    }
    final level = progress.tree[track] ?? 0,
        cost = Balance.treeCost(progress.tree[track] ?? 0);
    if (level >= Balance.maxLevel || coins < cost) return false;
    coins -= cost;
    progress.tree[track] = level + 1;
    revision++;
    return true;
  }

  EquipmentItem? openChest(
    ChestKind kind, {
    required ChestCategory category,
    Random? random,
  }) {
    final cost = Balance.chestCosts[kind]!;
    if (gems < cost) return null;
    gems -= cost;
    final reward = progress.roll(
      kind,
      random ?? rng,
      category: category,
      source: kind == ChestKind.common
          ? RollSource.paidCommon
          : RollSource.paidRare,
    );
    revision++;
    return reward;
  }

  /// Grants a free Common Chest roll earned by watching a rewarded ad
  /// (see RewardedChestService), instead of spending gems. Callers must
  /// only call this after their own daily-allowance bookkeeping
  /// (MonetizationStore.recordRewardedOpen) has already confirmed and
  /// recorded the grant, exactly once per watched ad -- this method
  /// itself does not re-check or persist any ad-side allowance; it is
  /// the same deterministic roll as a paid Common Chest, just without a
  /// gem cost.
  EquipmentItem openRewardedChest(ChestCategory category, {Random? random}) {
    final reward = progress.roll(
      ChestKind.common,
      random ?? rng,
      category: category,
      source: RollSource.adCommon,
    );
    revision++;
    return reward;
  }

  bool equip(String id, ItemKind kind, String? itemId) {
    final c = progress.commands[id];
    if (c == null || busy(id)) return false;
    final item = progress.item(itemId);
    if (itemId != null &&
        (item == null ||
            item.kind != kind ||
            (progress.assignedTo(itemId) != null &&
                progress.assignedTo(itemId) != id))) {
      return false;
    }
    if (itemId == null) {
      c.equipped.remove(kind);
    } else {
      c.equipped[kind] = itemId;
    }
    progress.apply(ships.firstWhere((s) => s.id == id));
    if (recent?.result.involves(id) == true) recent = null;
    revision++;
    return true;
  }

  bool encountersEnabled;
  final EncounterResolver resolver;
  final List<EncounterRun> _active = [];
  List<EncounterRun> get active => List.unmodifiable(_active);
  final Map<String, double> _cooldowns = {};
  int coins = 0, gems = 0, nextEncounter = 1, revision = 0;
  bool soundEnabled = true;
  EncounterRun? recent;
  PiratesVoyage({
    required super.ships,
    required super.places,
    required super.rng,
    required SeaNavigation super.navigation,
    this.encountersEnabled = false,
    this.npcDecisions = true,
    this.resolver = const PrototypeResolver(),
  }) {
    progress;
    for (final s in ships.where((s) => !s.playerOwned)) {
      if (s.firepower == 0) s.firepower = hullFor(s.hullType).guns;
    }
  }
  void dismissResult() {
    recent = null;
    revision++;
  }

  EncounterRun? encounterFor(String id) {
    for (final run in _active) {
      if (run.result.involves(id)) return run;
    }
    return recent?.result.involves(id) == true ? recent : null;
  }

  bool inBattle(String id) => _active.any((run) => run.result.involves(id));
  bool busy(String id) => heldShips.contains(id) || inBattle(id);
  bool combatAvailable(Vessel s) =>
      s.atSea &&
      // The money ship is a purely visual sail-and-tap bonus (see
      // isMoneyShip's doc comment) -- never a combat participant, so it
      // never needs an encounter/save-format special case.
      !s.isMoneyShip &&
      s.hullHp > 0 &&
      s.crewCount > 0 &&
      !s.recovering &&
      s.activity != Activity.docked &&
      s.activity != Activity.engaged &&
      !busy(s.id) &&
      !life.works.containsKey(s.id);
  @override
  void setBehavior(Vessel ship, BehaviorMode behavior) {
    if (busy(ship.id)) {
      ship.behavior = behavior;
      return;
    }
    super.setBehavior(ship, behavior);
  }

  @override
  bool targetAllowed(Vessel ship, Vessel target) =>
      !encountersEnabled || !npcDecisions || npc.targetAllowed(ship, target);
  @override
  Destination chooseDestination(Vessel ship) {
    if (encountersEnabled && npcDecisions) {
      final safety = npc.destination(ship);
      if (safety != null) return safety;
    }
    if (ship.returnToPort || ship.recovering || ship.retiring) {
      return life.portFor(ship);
    }
    final chosen = super.chooseDestination(ship);
    if (chosen.kind == DestinationKind.port &&
        ((ship.behavior == BehaviorMode.pirate) != (chosen.id == 'tortuga'))) {
      final ports = places
          .where(
            (p) =>
                p.kind == DestinationKind.port &&
                (ship.behavior == BehaviorMode.pirate
                    ? p.id == 'tortuga'
                    : p.id != 'tortuga') &&
                p.id != ship.destination?.id,
          )
          .toList();
      return ports.isEmpty
          ? life.portFor(ship)
          : ports[rng.nextInt(ports.length)];
    }
    return chosen;
  }

  @override
  void update(double dt) {
    if (!dt.isFinite || dt < 0) throw ArgumentError.value(dt);
    if (dt == 0) return;
    for (final id in _cooldowns.keys.toList()) {
      _cooldowns[id] = _cooldowns[id]! - dt;
      if (_cooldowns[id]! <= 0) _cooldowns.remove(id);
    }
    // Resolver-owned reservations remain authoritative until result application.
    for (final run in _active) {
      for (final s in ships.where((s) => run.result.involves(s.id))) {
        heldShips.add(s.id);
        s.activity = Activity.engaged;
      }
    }
    life.tick(dt);
    _tickMoneyShip(dt);
    if (encountersEnabled && npcDecisions) npc.tick(dt);
    for (final s in ships.toList()) {
      if (s.atSea &&
          !busy(s.id) &&
          !life.works.containsKey(s.id) &&
          (s.hullHp <= 0 || s.crewCount <= 0)) {
        life.defeat(s);
      }
    }
    final previous = {for (final s in ships) s.id: s.activity};
    super.update(dt);
    for (final s in ships.toList()) {
      if (!s.atSea || previous[s.id] != Activity.sailing) continue;
      // The money ship never actually enters port service (see
      // isMoneyShip's doc comment) -- it's a purely visual sail-and-tap
      // bonus, not a real economic actor, so it never touches
      // WorldLife.works and therefore never needs any special-case
      // handling in save/restore for an id that VoyageStore.save
      // deliberately excludes from the snapshot.
      if (s.isMoneyShip) continue;
      if (s.activity == Activity.docked) {
        life.startPort(s);
      } else if (s.activity == Activity.observing) {
        // One qualifying observation = one genuine arrival at a search
        // destination (not a fixed timer -- see WorldLife.checkDiscovery).
        life.checkDiscovery(s);
      }
    }
    for (final run in _active.toList()) {
      run.elapsed = min(run.result.duration, run.elapsed + dt);
      if (run.elapsed >= run.result.duration) _complete(run);
    }
    if (!encountersEnabled) return;
    // Stable ID order makes simultaneous arrivals deterministic.
    final ordered = ships.toList()..sort((a, b) => a.id.compareTo(b.id));
    for (final a in ordered) {
      if (!combatAvailable(a) ||
          a.crewCount <= 0 ||
          a.hullHp <= 0 ||
          a.recovering ||
          busy(a.id) ||
          _cooldowns.containsKey(a.id) ||
          a.destination?.kind != DestinationKind.ship) {
        continue;
      }
      final candidates = ships.where((b) => b.id == a.destination!.id);
      if (candidates.isEmpty) continue;
      final b = candidates.first;
      final hostile =
          (a.behavior == BehaviorMode.pirate ||
          (a.behavior == BehaviorMode.privateer &&
              b.behavior == BehaviorMode.pirate));
      if (!combatAvailable(b) ||
          b.crewCount <= 0 ||
          b.hullHp <= 0 ||
          b.recovering ||
          !hostile ||
          a.playerOwned && b.playerOwned ||
          busy(b.id) ||
          _cooldowns.containsKey(b.id)) {
        continue;
      }
      if (a.position.distanceTo(b.position) > 22 ||
          !navigation.clearSegment(a.position, b.position)) {
        continue;
      }
      if (npcDecisions && !npc.willing(a, b)) continue;
      life.attacked(b, a);
      final result = resolver.resolve(
        'encounter-${nextEncounter++}',
        Combatant.capture(a),
        Combatant.capture(b),
      );
      _active.add(EncounterRun(result));
      for (final ship in [a, b]) {
        heldShips.add(ship.id);
        ship.activity = Activity.engaged;
        ship.pauseRemaining = 0;
      }
      revision++;
    }
  }

  void _complete(EncounterRun run) {
    if (!_active.remove(run)) return;
    final r = run.result;
    for (final ship in ships.where((s) => r.involves(s.id))) {
      final a = ship.id == r.a.id;
      final before = a ? r.a : r.b;
      ship.hullHp = max(0, before.hullHp - (a ? r.damageA : r.damageB));
      ship.crewCount = max(0, before.crew - (a ? r.crewLossA : r.crewLossB));
      if (r.effectsVersion > 0) {
        final burned = a ? r.burnedA : r.burnedB;
        ship.cargo = max(0, ship.cargo - burned);
        if (burned > 0) life.log(ship, 'Fire destroyed $burned cargo');
        ship.chainPenalty = max(ship.chainPenalty, a ? r.chainA : r.chainB);
        if (ship.chainPenalty > 0) {
          life.log(ship, 'Rigging damaged; slowed until port service');
        }
        if (r.winnerId == ship.id) {
          final taken = min(
            r.loot,
            max(0, progress.effectiveHoldCapacity(ship) - ship.cargo),
          );
          ship.cargo += taken;
          life.log(
            ship,
            '${r.kind == EncounterKind.cannon ? "Salvage" : "Prize cargo"}: +$taken',
          );
        }
      }
      heldShips.remove(ship.id);
      life.log(
        ship,
        'Hull damage: -${(a ? r.damageA : r.damageB).toStringAsFixed(1)} / Crew damage: -${a ? r.crewLossA : r.crewLossB}',
      );
      if (!ship.playerOwned &&
          ship.behavior == BehaviorMode.merchant &&
          ship.attacksSincePort >= LifeBalance.merchantAttacks) {
        ship.hullHp = 0;
      }
      if (ship.hullHp <= 0 || ship.crewCount <= 0) {
        life.defeat(ship);
      } else {
        final recovery = (a ? r.damageA : r.damageB) * ship.postHullRecovery;
        ship.hullHp = min(ship.maxHullHp, ship.hullHp + recovery);
        ship.crewCount +=
            ((a ? r.crewLossA : r.crewLossB) * ship.postCrewRecovery).floor();
        if (recovery > 0) {
          life.log(
            ship,
            'Post-fight Hull recovery +${recovery.toStringAsFixed(1)}',
          );
        }
        life.fieldSupport(ship);
        if (ship.hunter && r.winnerId == ship.id) {
          ship.returnToPort = true;
          life.log(ship, 'Victory; returning to port before hunting');
        }
        ship.fleeing = false;
        ship.threatId = null;
        ship.pursuitId = null;
        ship.pursuitTime = 0;
        super.setBehavior(ship, ship.behavior);
      }
      if (ship.playerOwned) progress.apply(ship);
      _cooldowns[ship.id] = 45;
    }
    if (r.effectsVersion > 0 &&
        r.kind == EncounterKind.boarding &&
        r.winnerId != null) {
      final winner = r.winnerId == r.a.id ? r.a : r.b;
      final loser = r.winnerId == r.a.id ? r.b : r.a;
      if (winner.owned && !loser.owned) {
        final prize = EquipmentItem(
          'item-${progress.nextItem++}',
          'Captured ${loser.hullType}',
          ItemKind.hull,
          hullType: loser.hullType,
          bonus: 0,
        );
        progress.inventory.add(prize);
        progress.mergeDuplicates();
        life.log(
          ships.firstWhere((s) => s.id == winner.id),
          'Captured ${loser.hullType}; available in Upgrades',
        );
      }
    }
    coins += r.coins;
    gems += r.gems;
    if (r.a.owned || r.b.owned) recent = run;
    revision++;
  }

  Map<String, dynamic> encounterJson() => {
    'lastPort': lastPort?.toJson(),
    'coins': coins,
    'gems': gems,
    'nextEncounter': nextEncounter,
    'sound': soundEnabled,
    'cooldowns': _cooldowns,
    'active': [
      for (final r in _active)
        {'result': r.result.toJson(), 'elapsed': r.elapsed},
    ],
    'recent': recent == null
        ? null
        : {'result': recent!.result.toJson(), 'elapsed': recent!.elapsed},
  };
  void restoreEncounters(Map<String, dynamic> j) {
    try {
      int count(dynamic v) {
        if (v is! int || v < 0 || v > 1000000000) {
          throw const FormatException('Invalid currency/count');
        }
        return v;
      }

      if (j['lastPort'] != null) {
        lastPort = PortReceipt.fromJson(j['lastPort']);
        if (!ships.any((s) => s.id == lastPort!.shipId && s.playerOwned)) {
          throw const FormatException('Invalid port command');
        }
      }
      coins = count(j['coins']);
      gems = count(j['gems']);
      nextEncounter = count(j['nextEncounter']);
      if (nextEncounter < 1) {
        throw const FormatException('Invalid encounter sequence');
      }
      soundEnabled = j['sound'] as bool;
      for (final e in (j['cooldowns'] as Map<String, dynamic>).entries) {
        final value = (e.value as num).toDouble();
        if (!ships.any((s) => s.id == e.key) ||
            !value.isFinite ||
            value <= 0 ||
            value > 45) {
          throw const FormatException('Invalid cooldown');
        }
        _cooldowns[e.key] = value;
      }
      EncounterRun decode(dynamic value) {
        final r = EncounterResult.fromJson(value['result']);
        final elapsed = (value['elapsed'] as num).toDouble();
        if (r.loot < 0 ||
            r.loot > 1000 ||
            r.burnedA < 0 ||
            r.burnedA > r.a.cargo ||
            r.burnedB < 0 ||
            r.burnedB > r.b.cargo ||
            !r.chainA.isFinite ||
            !r.chainB.isFinite ||
            r.chainA < 0 ||
            r.chainA > .8 ||
            r.chainB < 0 ||
            r.chainB > .8 ||
            r.a.id == r.b.id ||
            !ships.any((s) => s.id == r.a.id) ||
            !ships.any((s) => s.id == r.b.id) ||
            !elapsed.isFinite ||
            elapsed < 0 ||
            elapsed > r.duration ||
            r.coins < 0 ||
            r.coins > 1000000 ||
            r.gems < 0 ||
            r.gems > 1000000 ||
            (r.winnerId != null &&
                r.winnerId != r.a.id &&
                r.winnerId != r.b.id)) {
          throw const FormatException('Invalid encounter');
        }
        if ((r.kind == EncounterKind.escape &&
                r.escapedId != r.a.id &&
                r.escapedId != r.b.id) ||
            (r.kind != EncounterKind.escape && r.escapedId != null)) {
          throw const FormatException('Invalid escaping identity');
        }
        for (final c in [r.a, r.b]) {
          final ship = ships.firstWhere((s) => s.id == c.id);
          if (![
                'standard',
                'heavy',
                'grape',
                'chain',
                'fire',
              ].contains(c.ordnance) ||
              c.cargo < 0 ||
              c.cargo > 1000 ||
              !c.crewDefense.isFinite ||
              c.crewDefense < 0 ||
              // Final corrections pass 2026-09-20: was hardcoded at the
              // OLD .35 tree-only soft cap -- legitimate equipment can
              // now push a live ship's crewDefense up to
              // finalSafetyCeiling (.90, see FleetProgress.apply), so a
              // real, valid in-progress encounter snapshot could
              // legitimately exceed .35. Validate against the same
              // final ceiling instead, or this would wrongly reject (as
              // "corrupted") a perfectly valid save.
              c.crewDefense > LifeBalance.finalSafetyCeiling ||
              !c.openingVolley.isFinite ||
              c.openingVolley < 0 ||
              c.openingVolley > .2 ||
              c.owned != ship.playerOwned ||
              c.name != ship.name ||
              c.hullType != ship.hullType ||
              !c.speed.isFinite ||
              c.speed <= 0) {
            throw const FormatException('Combatant identity mismatch');
          }
          final loss = c.id == r.a.id ? r.crewLossA : r.crewLossB;
          final damage = c.id == r.a.id ? r.damageA : r.damageB;
          if (!c.hullHp.isFinite ||
              !c.maxHullHp.isFinite ||
              c.maxHullHp <= 0 ||
              c.hullHp < 0 ||
              c.hullHp > c.maxHullHp ||
              !damage.isFinite ||
              damage < 0 ||
              damage > c.hullHp ||
              loss < 0 ||
              loss > c.crew ||
              c.crew < 0) {
            throw const FormatException('Invalid combat damage');
          }
        }
        return EncounterRun(r, elapsed: elapsed);
      }

      final encounterIds = <String>{};
      for (final value in j['active'] as List) {
        final run = decode(value);
        if (!encounterIds.add(run.result.id) ||
            busy(run.result.a.id) ||
            busy(run.result.b.id) ||
            run.elapsed >= run.result.duration) {
          throw const FormatException('Duplicate battle reservation');
        }
        for (final c in [run.result.a, run.result.b]) {
          final ship = ships.firstWhere((s) => s.id == c.id);
          if (ship.activity != Activity.engaged ||
              ship.hullHp != c.hullHp ||
              ship.crewCount != c.crew) {
            throw const FormatException('Battle state mismatch');
          }
          heldShips.add(c.id);
        }
        _active.add(run);
      }
      if (ships.any((s) => s.activity == Activity.engaged && !busy(s.id))) {
        throw const FormatException('Missing active battle');
      }
      if (j['recent'] != null) {
        recent = decode(j['recent']);
        if (encounterIds.contains(recent!.result.id) ||
            recent!.elapsed != recent!.result.duration) {
          throw const FormatException('Incomplete result receipt');
        }
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Malformed encounter save');
    }
  }
}
