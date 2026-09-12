// Finishes the NPC lifecycle/persistence coverage Work was mid-way through:
// hunt -> encounter -> loot -> return/unload, ordnance effects surviving
// save/reload exactly once, defeat/respawn across a reload boundary, and the
// anti-loop mechanics (disengage/ignoreTarget) that back the "no dock/
// reacquire loop" and "no combat in port" invariants. Does not re-test what
// content_npc_test.dart / encounter_test.dart / world_life_test.dart already
// cover (single-phase loot, mid-battle save/resume, port-work reload).
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/core/movement/point.dart';
import 'package:dot_commander/core/movement/sea_navigation.dart';
import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/pirates/encounters/encounter_result.dart';
import 'package:dot_commander/pirates/encounters/pirates_voyage.dart';
import 'package:dot_commander/pirates/ships/hull_catalog.dart';
import 'package:dot_commander/pirates/world/npc_navigation.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';

Vessel boat(
  String id, {
  String hull = 'Brig',
  BehaviorMode role = BehaviorMode.pirate,
  bool owned = false,
  double x = 300,
  double y = 300,
}) {
  final h = hullFor(hull);
  return Vessel(
    id: id,
    name: id,
    captain: 'Captain $id',
    hullType: hull,
    position: Point2(x, y),
    speed: h.baseSpeed,
    maxHullHp: h.hp,
    crewCount: h.crew,
    behavior: role,
    playerOwned: owned,
  )..firepower = h.guns;
}

PiratesVoyage world(List<Vessel> ships, {bool decisions = true}) =>
    PiratesVoyage(
      ships: ships,
      places: const [
        Destination(
          'west',
          'West Port',
          Point2(100, 300),
          DestinationKind.port,
        ),
        Destination(
          'east',
          'East Port',
          Point2(500, 300),
          DestinationKind.port,
        ),
        Destination(
          'tortuga',
          'Pirate Haven',
          Point2(700, 600),
          DestinationKind.port,
        ),
      ],
      rng: Random(11),
      navigation: SeaNavigation([]),
      encountersEnabled: true,
      npcDecisions: decisions,
    );

VoyageStore memoryStore(List<String?> box) => VoyageStore(
  read: () async => box[0],
  write: (s) async => box[0] = s,
);

void main() {
  test(
    'full autonomous pirate lifecycle: real-radius detection, boarding victory, full hold, return, unload, resume hunting',
    () async {
      // Every combat/power/speed number below is set explicitly (not left to
      // hull defaults) so the outcome is deterministic: the pirate must be
      // the dominant side (grape ordnance then forces a boarding, not a
      // cannon exchange) and must not be outrunnable (speed <= pirate's
      // *1.15), so the resolver's escape branch can never trigger even if
      // the merchant's own NPC logic decides to flee mid-hunt.
      // VoyageStore always re-validates positions against the real Caribbean
      // map on reload (see voyage_store.dart), so this test -- unlike 4/5
      // below -- must run inside createCaribbean(), not the open-water
      // world() helper, even though the scenario itself is fully custom.
      final v = createCaribbean(encountersEnabled: true);
      final pirate = v.ships[1]
        ..behavior = BehaviorMode.pirate
        ..speed = 66
        ..maxHullHp = 200
        ..hullHp = 200
        ..crewCount = 40
        ..firepower = 10
        ..ordnance = 'grape'
        ..cargo = 0;
      final merchant = v.ships[2]
        ..behavior = BehaviorMode.merchant
        ..speed = 60
        ..maxHullHp = 50
        ..hullHp = 50
        ..crewCount = 10
        ..firepower = 2
        ..cargo = 6 // salvage 6 -> fills (or exceeds) the pirate's actual hold
        ..position = pirate.position; // co-located: a real, already-valid point

      // No destination is assigned manually: only real detection (radius,
      // targetAllowed, willing) drives the pirate onto the merchant.
      expect(pirate.destination, isNull);
      var ticks = 0;
      while (v.active.isEmpty && ticks < 400) {
        v.update(.25);
        ticks++;
      }
      expect(
        v.active,
        hasLength(1),
        reason: 'pirate never detected/closed on the merchant',
      );
      expect(pirate.destination?.id, merchant.id);

      final box = <String?>[null];
      final store = memoryStore(box);
      final run = v.active.single;
      // Checkpoint mid-battle: battle-lock/persistence must survive a reload
      // partway through the immutable result before it is even applied.
      await store.save(v);
      var live = await store.load();
      final restoredPirate = live.ships.firstWhere((s) => s.id == pirate.id);
      final restoredMerchant = live.ships.firstWhere(
        (s) => s.id == merchant.id,
      );
      live.update(run.result.duration);

      expect(run.result.kind, EncounterKind.boarding);
      expect(run.result.winnerId, pirate.id);
      expect(
        restoredPirate.cargo,
        hullFor(restoredPirate.hullType).holds,
      ); // full hold from loot
      expect(restoredMerchant.hullHp, greaterThanOrEqualTo(0));

      // Hunt phase 2: full hold must trigger an autonomous return to port.
      var returnTicks = 0;
      while (!restoredPirate.returnToPort && returnTicks < 40) {
        live.npc.tick(NpcBalance.decisionInterval + .01);
        returnTicks++;
      }
      expect(restoredPirate.returnToPort, isTrue);
      expect(restoredPirate.destination?.kind, DestinationKind.port);

      // Checkpoint again mid-transit home, then sail all the way in and
      // through the full unload/service cycle using only v.update.
      await store.save(live);
      live = await store.load();
      final sailingHome = live.ships.firstWhere((s) => s.id == pirate.id);
      var arrived = false;
      for (var i = 0; i < 2000 && !arrived; i++) {
        live.update(1);
        arrived = sailingHome.activity == Activity.docked;
      }
      expect(arrived, isTrue, reason: 'pirate never reached port to unload');
      for (
        var i = 0;
        i < 40 && live.life.works.containsKey(sailingHome.id);
        i++
      ) {
        live.life.tick(30);
      }
      expect(live.life.works.containsKey(sailingHome.id), isFalse);
      expect(sailingHome.cargo, 0); // pirates buy zero trade cargo
      expect(sailingHome.returnToPort, isFalse);

      // Lifecycle closes the loop: the pirate resumes hunting rather than idling.
      expect(sailingHome.behavior, BehaviorMode.pirate);
    },
  );

  test(
    'encounter effects stay applied exactly once after saving past completion and continuing to play',
    () async {
      // Real Caribbean positions again: VoyageStore re-validates against the
      // actual map on reload regardless of what navigation the simulation
      // that produced the save used.
      final v = createCaribbean(encountersEnabled: true);
      final a = v.ships[1]
        ..behavior = BehaviorMode.pirate
        ..maxHullHp = 300
        ..hullHp = 300
        ..crewCount = 100
        ..firepower = 15
        ..ordnance = 'fire';
      final b = v.ships[2]
        ..behavior = BehaviorMode.merchant
        ..maxHullHp = 100
        ..hullHp = 100
        ..crewCount = 30
        ..firepower = 3
        ..cargo = 6
        ..position = a.position;
      a.destination = Destination(
        b.id,
        b.name,
        b.position,
        DestinationKind.ship,
      );
      v.update(.01);
      final run = v.active.single;
      v.update(run.result.duration); // completes and applies effects once
      final cargoAfterBurn = b.cargo;
      final coinsAfter = v.coins;
      final gemsAfter = v.gems;
      final loot = a.cargo;
      expect(run.result.burnedB, greaterThan(0));

      final box = <String?>[null];
      final store = memoryStore(box);
      await store.save(v); // saved strictly AFTER completion, not mid-battle
      final reloaded = await store.load();
      final ra = reloaded.ships.firstWhere((s) => s.id == a.id);
      final rb = reloaded.ships.firstWhere((s) => s.id == b.id);
      expect(ra.cargo, loot);
      expect(rb.cargo, cargoAfterBurn);
      expect(reloaded.coins, coinsAfter);
      expect(reloaded.gems, gemsAfter);

      // A tiny tick, not a long one: this world has 15 living ships, and a
      // long run could legitimately start brand-new, unrelated encounters
      // that add their own coins/gems -- that would be normal gameplay, not
      // a regression. What this guards against is this *specific*,
      // already-completed encounter being reapplied purely from loading or
      // from one more update() call, which a small tick still proves.
      reloaded.update(.01);
      expect(
        reloaded.coins,
        coinsAfter,
        reason: 'reward re-applied after reload',
      );
      expect(
        reloaded.gems,
        gemsAfter,
        reason: 'reward re-applied after reload',
      );
      expect(ra.cargo, loot, reason: 'loot re-applied after reload');
      expect(rb.cargo, cargoAfterBurn, reason: 'burn re-applied after reload');
      expect(reloaded.active.where((r) => r.result.involves(a.id)), isEmpty);
    },
  );

  test(
    'a defeated pirate\'s respawn timer survives a reload split across it without double-processing',
    () async {
      final v = createCaribbean(encountersEnabled: true)..coins = 0;
      final s = v.ships[1]
        ..behavior = BehaviorMode.pirate
        ..cargo = 5;
      v.life.defeat(s);
      expect(s.atSea, isFalse);
      final fullRespawn = s.respawnRemaining;
      expect(fullRespawn, greaterThan(0));

      v.life.tick(fullRespawn * .4);
      final remainingBeforeSave = s.respawnRemaining;
      expect(remainingBeforeSave, greaterThan(0));

      final box = <String?>[null];
      final store = memoryStore(box);
      await store.save(v);
      final reloaded = await store.load();
      final restored = reloaded.ships.firstWhere((r) => r.id == s.id);
      expect(restored.atSea, isFalse);
      expect(restored.respawnRemaining, closeTo(remainingBeforeSave, .0001));
      expect(restored.cargo, 0); // defeat already cleared cargo before the save

      // Not yet due: ticking short of the remainder must not respawn early.
      reloaded.life.tick(remainingBeforeSave - .05);
      expect(restored.atSea, isFalse);

      // Crossing the remainder respawns exactly once.
      reloaded.life.tick(.1);
      expect(restored.atSea, isTrue);
      final respawnedOnce = restored.atSea;
      reloaded.life.tick(.1);
      expect(restored.atSea, respawnedOnce); // no further/duplicate transition
    },
  );

  test(
    'disengaging a pursuer blocks immediate reacquisition of the same target until the cooldown elapses',
    () {
      final pirate = boat('p', x: 300, y: 300);
      final merchant = boat('m', role: BehaviorMode.merchant, x: 320, y: 300);
      final v = world([pirate, merchant]);
      pirate.destination = Destination(
        merchant.id,
        merchant.name,
        merchant.position,
        DestinationKind.ship,
      );
      expect(v.npc.targetAllowed(pirate, merchant), isTrue);

      v.npc.disengage(pirate, merchant.id);
      expect(pirate.ignoredTarget, merchant.id);
      expect(pirate.destination, isNull);
      // Still well within detection range, but the cooldown must block it.
      expect(v.npc.targetAllowed(pirate, merchant), isFalse);
      expect(v.chooseDestination(pirate).id, isNot(merchant.id));

      v.npc.tick(NpcBalance.reacquireDelay - .1);
      expect(
        pirate.ignoredTarget,
        merchant.id,
        reason: 'cooldown released early',
      );

      v.npc.tick(.2);
      expect(pirate.ignoredTarget, isNull);
      expect(v.npc.targetAllowed(pirate, merchant), isTrue);
    },
  );

  test(
    'merchant escaping to port immediately disengages every pursuer chasing it, closing off a dock/reacquire loop',
    () {
      final merchant = boat('m', role: BehaviorMode.merchant, x: 100, y: 300);
      final pirate = boat('chaser1', x: 400, y: 300);
      final privateer = boat(
        'chaser2',
        role: BehaviorMode.privateer,
        x: 420,
        y: 300,
      );
      final v = world([merchant, pirate, privateer]);
      for (final chaser in [pirate, privateer]) {
        chaser.destination = Destination(
          merchant.id,
          merchant.name,
          merchant.position,
          DestinationKind.ship,
        );
      }
      merchant.fleeing = true;
      merchant.threatId = pirate.id;
      merchant.destination = v.life.portFor(merchant);
      merchant.position = merchant.destination!.position;

      v.life.startPort(merchant);

      expect(merchant.atSea, isFalse);
      expect(merchant.respawnRemaining, 0); // truly gone, not a respawn candidate
      for (final chaser in [pirate, privateer]) {
        expect(chaser.destination, isNull);
        expect(chaser.ignoredTarget, merchant.id);
        expect(v.npc.targetAllowed(chaser, merchant), isFalse);
      }

      // Even with the (now unreachable) merchant still nominally in range,
      // neither pursuer can be steered back onto it while atSea is false.
      for (final chaser in [pirate, privateer]) {
        expect(v.combatAvailable(merchant), isFalse);
        expect(v.chooseDestination(chaser).id, isNot(merchant.id));
      }
    },
  );

  test(
    'a ship docked mid-port-service after reload still cannot be pulled into combat',
    () async {
      final v = createCaribbean(encountersEnabled: true);
      final docked = v.ships[1];
      final hostile = v.ships[2];
      docked.destination = v.life.portFor(docked);
      docked.position = docked.destination!.position;
      v.life.startPort(docked);
      expect(v.life.works.containsKey(docked.id), isTrue);
      hostile.position = docked.position; // adjacent once reloaded

      final box = <String?>[null];
      final store = memoryStore(box);
      await store.save(v);
      final reloaded = await store.load();
      final restoredDocked = reloaded.ships.firstWhere(
        (s) => s.id == docked.id,
      );
      final restoredHostile = reloaded.ships.firstWhere(
        (s) => s.id == hostile.id,
      );
      expect(reloaded.life.works.containsKey(restoredDocked.id), isTrue);
      expect(restoredDocked.activity, Activity.docked);

      restoredHostile.destination = Destination(
        restoredDocked.id,
        restoredDocked.name,
        restoredDocked.position,
        DestinationKind.ship,
      );
      reloaded.update(.01);
      expect(reloaded.active, isEmpty);
      expect(reloaded.combatAvailable(restoredDocked), isFalse);
      expect(restoredDocked.activity, Activity.docked);
    },
  );
}
