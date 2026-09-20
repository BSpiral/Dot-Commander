import '../progression/fleet_progress.dart';
import 'dart:convert';
import '../../core/movement/sea_navigation.dart';
import '../../core/simulation/vessel.dart';
import '../ships/hull_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/persistence/voyage_snapshot.dart';
import '../encounters/pirates_voyage.dart';
import '../world/caribbean.dart';

/// A single small local snapshot. Inject read/write functions for disk-free tests.
class VoyageStore {
  static const key = 'dot_commander.pirates.voyage.v1';
  final DateTime Function() now;
  final Future<String?> Function() read;
  final Future<void> Function(String) write;
  Future<void> _pending = Future.value();
  // Set by load() exactly when a genuine offline reward was just granted
  // (reward > 0), so CommandScreen can show a one-time "while you were
  // away" notification for a real cold start -- see also
  // CommandScreen.didChangeAppLifecycleState for the background-resume
  // equivalent path, which computes and reports its own reward directly
  // rather than through these fields.
  int? lastOfflineRewardCoins;
  int? lastOfflineMinutes;
  VoyageStore({
    DateTime Function()? now,
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  }) : now = now ?? DateTime.now,
       read = read ?? (() => SharedPreferencesAsync().getString(key)),
       write =
           write ?? ((value) => SharedPreferencesAsync().setString(key, value));
  Future<PiratesVoyage> load() async {
    final source = await read();
    final fresh = createCaribbean(encountersEnabled: true);
    if (source == null) return fresh;
    final version = (jsonDecode(source) as Map<String, dynamic>)['version'];
    if (version == 1) {
      final old = VoyageSnapshot.decode(
        source,
        SeaNavigation(legacyCaribbeanLand),
        fresh.places,
      );
      // Keep identities, orders and progress. Only positions newly covered by land move.
      final migrated = <Vessel>[];
      for (final ship in old) {
        final hull = hullFor(ship.hullType);
        final position = nearestWater(ship.position, fresh.navigation);
        final copy =
            Vessel(
                id: ship.id,
                name: ship.name,
                captain: ship.captain,
                hullType: ship.hullType,
                position: position,
                speed: hull.baseSpeed,
                maxHullHp: ship.maxHullHp,
                crewCount: ship.crewCount,
                behavior: ship.behavior,
                playerOwned: ship.playerOwned,
                load: ship.load,
              )
              ..hullHp = ship.hullHp
              ..destination = ship.destination
              ..activity = ship.activity
              ..pauseRemaining = ship.pauseRemaining
              ..heading = ship.heading;
        if (position.distanceTo(ship.position) > 0) {
          copy.activity = Activity.sailing;
          copy.pauseRemaining = 0;
        }
        migrated.add(copy);
      }
      for (final ship in migrated) {
        final target = ship.destination;
        if (target?.kind == DestinationKind.ship) {
          final other = migrated.firstWhere((s) => s.id == target!.id);
          ship.destination = Destination(
            other.id,
            other.name,
            other.position,
            DestinationKind.ship,
          );
        }
      }
      final ids = migrated.map((s) => s.id).toSet();
      migrated.addAll(
        fresh.ships.where((s) => !s.playerOwned && !ids.contains(s.id)),
      );
      return createCaribbean(restoredShips: migrated, encountersEnabled: true);
    }
    final loaded = createCaribbean(
      encountersEnabled: true,
      restoredShips: VoyageSnapshot.decode(
        source,
        fresh.navigation,
        fresh.places,
      ),
    );
    if (version == 3 ||
        version == 4 ||
        version == 5 ||
        version == 6 ||
        version == 7) {
      loaded.restoreEncounters(
        (jsonDecode(source) as Map<String, dynamic>)['encounters']
            as Map<String, dynamic>,
      );
    } else if (loaded.ships.any((s) => s.activity == Activity.engaged)) {
      throw const FormatException('Legacy save cannot contain battles');
    }
    if (version == 4 || version == 5 || version == 6 || version == 7) {
      try {
        loaded.progress.restore(
          (jsonDecode(source) as Map<String, dynamic>)['progression'],
          loaded.ships,
        );
        for (final ship in loaded.ships.where((s) => s.playerOwned)) {
          final hp = ship.hullHp, maxHp = ship.maxHullHp, speed = ship.speed;
          final crew = ship.crewCount, hull = ship.hullType;
          if (loaded.busy(ship.id)) continue;
          loaded.progress.apply(ship);
          if (version == 7 &&
              (ship.hullType != hull ||
                  (ship.maxHullHp - maxHp).abs() > .00001 ||
                  (ship.speed - speed).abs() > .00001)) {
            throw const FormatException('Equipment state mismatch');
          }
          ship.hullHp = version == 7
              ? hp
              : ship.maxHullHp * (hp / maxHp).clamp(0, 1);
          ship.crewCount = crew;
        }
      } catch (_) {
        throw const FormatException('Invalid progression save');
      }
    } else {
      // Materialize zero-level identities without changing existing damage/battles.
      loaded.progress;
    }
    if (version == 6 || version == 7) {
      loaded.life.restore((jsonDecode(source) as Map<String, dynamic>)['life']);
    } else {
      final legacyFavor =
          loaded.progress.tree.remove(FleetTrack.portFavor) ?? 0;
      for (final c in loaded.progress.commands.values.where(
        (c) => legacyFavor > 0,
      )) {
        c.tree[CommandTrack.portRelations] =
            ((c.tree[CommandTrack.portRelations] ?? 0) + legacyFavor).clamp(
              0,
              1100,
            );
      }
    }
    // Effective capacity (hull base + Fleet Tree + equipment, see
    // FleetProgress.effectiveHoldCapacity) rather than raw hull.holds --
    // progress.restore already ran above, so any FleetTrack.shipHold
    // investment is already reflected here.
    if (version < 7) {
      for (final s in loaded.ships) {
        s.cargo = s.cargo.clamp(0, loaded.progress.effectiveHoldCapacity(s));
      }
    }
    if (loaded.ships.any(
      (s) => s.cargo > loaded.progress.effectiveHoldCapacity(s),
    )) {
      throw const FormatException('Cargo exceeds hold capacity');
    }
    if (version == 4 || version == 5 || version == 6 || version == 7) {
      final timestamp = (jsonDecode(source) as Map<String, dynamic>)['savedAt'];
      if (timestamp is int) {
        final minutes =
            (now().millisecondsSinceEpoch - timestamp) ~/ 60000;
        final reward = Balance.offlineRewardCoins(
          offlineTreeLevel: loaded.progress.tree[FleetTrack.offline] ?? 0,
          elapsedMinutes: minutes,
          fleetCoinsPerHour: Balance.fleetCoinsPerHour(loaded.ships),
        );
        if (reward > 0) {
          loaded.coins += reward;
          lastOfflineRewardCoins = reward;
          lastOfflineMinutes = minutes;
          // A save failure here must not discard an otherwise-valid
          // `loaded` voyage back to the caller -- it would propagate
          // out of load() entirely (this whole method's caller has no
          // narrower try/catch than "the whole load failed"), throwing
          // away a correctly-decoded voyage over a transient write
          // hiccup in what is, at worst, a delayed persistence of a
          // reward that will simply be recomputed (from the same
          // still-on-disk `savedAt`) the next time load() runs.
          try {
            await save(loaded);
          } catch (_) {}
        }
      }
    }
    return loaded;
  }

  Future<void> save(PiratesVoyage simulation) {
    // The money ship (see Vessel.isMoneyShip) is deliberately session-only
    // -- excluded here so a save mid-visit never persists it as a
    // permanent extra NPC, and an app restart simply starts a fresh
    // spawn cooldown instead of needing new save-format fields for a
    // lightweight bonus feature.
    final root =
        jsonDecode(
              VoyageSnapshot.encode(
                simulation.ships.where((s) => !s.isMoneyShip).toList(),
              ),
            )
            as Map<String, dynamic>;
    root['version'] = 7;
    root['life'] = simulation.life.toJson();
    root['savedAt'] = now().millisecondsSinceEpoch;
    root['progression'] = simulation.progress.toJson();
    root['encounters'] = simulation.encounterJson();
    final snapshot = jsonEncode(root);
    // Preserve write order even across an earlier platform failure.
    final operation = _pending.then((_) => write(snapshot));
    _pending = operation.then<void>(
      (_) {},
      onError: (Object e, StackTrace s) {},
    );
    return operation;
  }
}
