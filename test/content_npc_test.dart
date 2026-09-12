import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/core/movement/point.dart';
import 'package:dot_commander/core/movement/sea_navigation.dart';
import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/pirates/ships/hull_catalog.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';
import 'package:dot_commander/pirates/encounters/encounter_result.dart';
import 'package:dot_commander/pirates/encounters/pirates_voyage.dart';
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

PiratesVoyage world(
  List<Vessel> ships, {
  bool decisions = true,
}) => PiratesVoyage(
  ships: ships,
  places: const [
    Destination('west', 'West Port', Point2(100, 300), DestinationKind.port),
    Destination('east', 'East Port', Point2(500, 300), DestinationKind.port),
    Destination('north', 'North Port', Point2(300, 100), DestinationKind.port),
    Destination(
      'tortuga',
      'Pirate Haven',
      Point2(700, 600),
      DestinationKind.port,
    ),
  ],
  rng: Random(9),
  navigation: SeaNavigation([]),
  encountersEnabled: true,
  npcDecisions: decisions,
);
EquipmentItem give(PiratesVoyage v, String definition, {String? ship}) {
  final d = equipmentContent.firstWhere((d) => d.id == definition);
  final i = EquipmentItem(
    'item-${v.progress.nextItem++}',
    d.name,
    d.kind,
    contentId: d.id,
    bonus: 0,
  );
  v.progress.inventory.add(i);
  if (ship != null) expect(v.equip(ship, d.kind, i.id), isTrue);
  return i;
}

void main() {
  test(
    'NPC pirate loots, unloads without buying trade cargo, then resumes',
    () {
      final a = boat('a', hull: 'Frigate')..ordnance = 'grape';
      final b = boat('b', hull: 'Brig', role: BehaviorMode.merchant)..cargo = 8;
      final v = world([a, b], decisions: false);
      a.destination = Destination(
        b.id,
        b.name,
        b.position,
        DestinationKind.ship,
      );
      v.update(.01);
      final run = v.active.single;
      v.update(run.result.duration);
      expect(a.cargo, 8);
      v.npc.tick(1);
      expect(a.returnToPort, isTrue);
      a.destination = v.life.portFor(a);
      a.position = a.destination!.position;
      v.life.startPort(a);
      for (var i = 0; i < 4; i++) {
        v.life.tick(30);
      }
      expect(a.cargo, 0);
      expect(a.returnToPort, isFalse);
      expect(v.life.works.containsKey(a.id), isFalse);
    },
  );
  test(
    'three-minute autonomous world stays saveable and respects NPC cap',
    () async {
      String? data;
      final store = VoyageStore(
        read: () async => data,
        write: (s) async {
          data = s;
        },
      );
      var v = createCaribbean(encountersEnabled: true);
      for (var tick = 0; tick < 1800; tick++) {
        v.update(.1);
        expect(v.life.npcCount, lessThanOrEqualTo(20));
        for (final run in v.active) {
          expect(v.busy(run.result.a.id) && v.busy(run.result.b.id), isTrue);
        }
        if (tick % 300 == 299) {
          await store.save(v);
          v = await store.load();
        }
      }
    },
  );
  test(
    'lost contact ends pursuit and no safe port uses a water escape waypoint',
    () {
      final a = boat('a', hull: 'Frigate'),
          b = boat('b', hull: 'Sloop', x: 900);
      final v = world([a, b]);
      a.destination = Destination(
        b.id,
        b.name,
        b.position,
        DestinationKind.ship,
      );
      v.npc.tick(.1);
      expect(a.destination?.id, isNot(b.id));
      final fleeing = boat('m', role: BehaviorMode.merchant, x: 50, y: 50);
      final threat = boat('p', x: 100, y: 50);
      final escape = v.npc.away(fleeing, threat);
      expect(escape.kind, DestinationKind.waypoint);
      expect(v.navigation.isWater(escape.position), isTrue);
      expect(
        escape.position.distanceTo(threat.position),
        greaterThan(fleeing.position.distanceTo(threat.position)),
      );
    },
  );

  test(
    'eleven distinct hulls are a toolbox, not a single ascending ladder',
    () {
      expect(hullCatalog.length, 11);
      expect(hullFor('Fluyt').holds, greaterThan(hullFor('Galleon').holds));
      expect(hullFor('Man-of-War').guns, greaterThan(hullFor('Galleon').guns));
      expect(
        hullFor('Galleon').baseSpeed,
        greaterThan(hullFor('Frigate').baseSpeed),
      );
      expect(
        hullFor('Sloop').baseSpeed,
        greaterThan(hullFor('Brig').baseSpeed),
      );
      expect(hullFor('Sloop').guns, lessThan(hullFor('Brig').guns));
      expect(hullFor('Pirogue').crew, 8);
    },
  );
  test('crew has exactly five slots and officers exactly five roles', () {
    expect(crewSlots.map((s) => s.name), [
      'head',
      'body',
      'hands',
      'legs',
      'weapon',
    ]);
    expect(officerSlots.map((s) => s.name), [
      'captain',
      'quartermaster',
      'bosun',
      'carpenter',
      'navigator',
    ]);
    expect(
      ItemKind.values.any((s) => s.name == 'feet' || s.name == 'surgeon'),
      isFalse,
    );
    for (final slot in [...crewSlots, ...officerSlots]) {
      expect(equipmentContent.any((d) => d.kind == slot), isTrue);
    }
  });
  test(
    'new hull equipment preserves captain, command Tree and independent copies',
    () {
      final v = createCaribbean();
      final s = v.ships.first;
      final id = s.id, name = s.captain;
      v.progress.commands[id]!.tree[CommandTrack.hull] = 600;
      final item = EquipmentItem(
        'item-${v.progress.nextItem++}',
        'Galleon',
        ItemKind.hull,
        hullType: 'Galleon',
        bonus: 0,
      );
      v.progress.inventory.add(item);
      expect(v.equip(id, ItemKind.hull, item.id), isTrue);
      expect(s.id, id);
      expect(s.captain, name);
      expect(s.hullType, 'Galleon');
      expect(v.progress.commands[id]!.level(CommandTrack.hull), 600);
      final copy = give(v, 'cutlass');
      final other = give(v, 'cutlass');
      expect(copy.id, isNot(other.id));
      expect(copy.contentId, other.contentId);
    },
  );
  test(
    'crew content changes offense protection recovery and special volley',
    () {
      final v = createCaribbean();
      final s = v.ships.first;
      give(v, 'cutlass', ship: s.id);
      expect(s.crewEffectiveness, greaterThan(1));
      give(v, 'leathers', ship: s.id);
      expect(s.crewDefense, .08);
      give(v, 'leg_bandage', ship: s.id);
      expect(s.postCrewRecovery, .06);
      give(v, 'pistol', ship: s.id);
      expect(s.openingVolley, .04);
      expect(
        v.progress.commands[s.id]!.equipped.keys,
        containsAll([ItemKind.weapon, ItemKind.body, ItemKind.legs]),
      );
    },
  );
  test(
    'all officer jobs feed existing derived stats without changing identity',
    () {
      final v = createCaribbean();
      final s = v.ships.first;
      final speed = s.speed;
      give(v, 'captain', ship: s.id);
      expect(s.economyBonus, .08);
      give(v, 'quartermaster', ship: s.id);
      expect(s.crewEffectiveness, greaterThan(1));
      give(v, 'bosun', ship: s.id);
      expect(s.firepower, greaterThan(hullFor('Sloop').guns));
      give(v, 'carpenter', ship: s.id);
      expect(s.fieldRepairBonus, 1);
      expect(s.damageReduction, greaterThan(0));
      give(v, 'navigator', ship: s.id);
      expect(s.speed, greaterThan(speed));
      expect(v.progress.commands[s.id]!.equipped.length, 5);
    },
  );
  test(
    'ship gear choices mitigate slowdowns protect crew or trade fire for speed',
    () {
      final v = createCaribbean();
      final s = v.ships.first..chainPenalty = .55;
      final slow = s.effectiveSpeed;
      give(v, 'keel', ship: s.id);
      expect(s.effectiveSpeed, greaterThan(slow));
      give(v, 'sweeps', ship: s.id);
      expect(s.movementFactor, .65);
      give(v, 'netting', ship: s.id);
      expect(s.crewDefense, .15);
      give(v, 'deck', ship: s.id);
      expect(s.speed, greaterThan(hullFor('Sloop').baseSpeed));
      expect(s.firepower, lessThan(hullFor('Sloop').guns));
      give(v, 'gunports', ship: s.id);
      expect(s.openingAttack, .1);
    },
  );
  test('heavy sinking pays much less than grapeshot capture', () {
    final a = boat('a', hull: 'Man-of-War', owned: true),
        b = boat('b', hull: 'Brig')..cargo = 8;
    a.ordnance = 'heavy';
    final sunk = const PrototypeResolver().resolve(
      'a',
      Combatant.capture(a),
      Combatant.capture(b),
    );
    a.ordnance = 'grape';
    final prize = const PrototypeResolver().resolve(
      'b',
      Combatant.capture(a),
      Combatant.capture(b),
    );
    expect(sunk.kind, EncounterKind.cannon);
    expect(prize.kind, EncounterKind.boarding);
    expect(sunk.coins, lessThan(prize.coins));
    expect(sunk.loot, 1);
    expect(prize.loot, 8);
    expect(prize.crewLossB, b.crewCount);
    expect(prize.damageB, lessThan(b.hullHp));
  });
  test('fire burns cargo; chain remains on a surviving victor', () {
    final a = boat('a', hull: 'Man-of-War', owned: true),
        b = boat('b', hull: 'Sloop')
          ..cargo = 4
          ..ordnance = 'chain';
    a.ordnance = 'fire';
    final v = world([a, b], decisions: false);
    a.destination = Destination(b.id, b.name, b.position, DestinationKind.ship);
    v.update(.01);
    final result = v.active.single.result;
    expect(result.burnedB, 2);
    expect(result.chainA, .55);
    v.update(result.duration);
    expect(a.atSea, isTrue);
    expect(a.chainPenalty, .55);
    final slower = a.effectiveSpeed;
    expect(slower, lessThan(a.speed));
    a.destination = v.life.portFor(a);
    a.position = a.destination!.position;
    v.life.startPort(a);
    v.life.tick(30);
    expect(a.chainPenalty, .55);
    v.life.tick(30);
    expect(a.chainPenalty, 0);
  });
  test(
    'pistol affects boarding opening and defensive gear reduces survivor losses',
    () {
      final a = boat('a'), b = boat('b');
      final baseline = const PrototypeResolver().resolve(
        'base',
        Combatant.capture(a),
        Combatant.capture(b),
      );
      a.openingVolley = .04;
      final volley = const PrototypeResolver().resolve(
        'volley',
        Combatant.capture(a),
        Combatant.capture(b),
      );
      expect(volley.crewLossB, greaterThan(baseline.crewLossB));
      a.crewDefense = .3;
      final protected = const PrototypeResolver().resolve(
        'defense',
        Combatant.capture(a),
        Combatant.capture(b),
      );
      expect(protected.crewLossA, lessThanOrEqualTo(volley.crewLossA));
    },
  );
  test(
    'healthy bold merchant may fight similar threat but damage changes decision',
    () {
      final m = boat('merchant', role: BehaviorMode.merchant)
        ..npcResolve = 1.2
        ..npcTolerance = .1;
      final p = boat('pirate')..firepower = 10;
      final v = world([m, p]);
      expect(v.npc.willing(m, p), isTrue);
      m.hullHp *= .8;
      expect(v.npc.willing(m, p), isFalse);
    },
  );
  test(
    'weak pirate refuses warship and badly damaged or full pirate returns',
    () {
      final p = boat('p', hull: 'Schooner'),
          war = boat(
            'w',
            hull: 'Man-of-War',
            role: BehaviorMode.merchant,
            x: 340,
          );
      final v = world([p, war]);
      expect(v.npc.willing(p, war), isFalse);
      expect(v.chooseDestination(p).kind, isNot(DestinationKind.ship));
      p.hullHp = 10;
      v.npc.tick(1);
      expect(p.returnToPort, isTrue);
      expect(p.destination!.id, 'tortuga');
      p.hullHp = p.maxHullHp;
      p.returnToPort = false;
      p.cargo = hullFor(p.hullType).holds;
      v.npc.tick(1);
      expect(p.returnToPort, isTrue);
      expect(p.destination!.id, 'tortuga');
    },
  );
  test(
    'hunter never flees, pirate does, detection expands around explorers',
    () {
      final h = boat('hunter', role: BehaviorMode.privateer)..hunter = true;
      final p = boat('pirate', hull: 'Man-of-War', x: 330);
      final v = world([h, p]);
      h.hullHp = 1;
      expect(v.npc.willing(h, p), isTrue);
      v.npc.tick(1);
      expect(h.fleeing, isFalse);
      expect(p.fleeing, isTrue);
      final before = v.npc.radius(h);
      v.ships.add(boat('scout', role: BehaviorMode.explorer, x: 310));
      expect(v.npc.radius(h), before * 2);
    },
  );
  test('chase times out and avoids instant reacquisition', () {
    final a = boat('p', hull: 'Frigate')..npcPersistence = 2;
    final b = boat('m', hull: 'Sloop', role: BehaviorMode.merchant, x: 400);
    final v = world([a, b]);
    a.destination = Destination(b.id, b.name, b.position, DestinationKind.ship);
    v.npc.tick(3);
    expect(a.ignoredTarget, b.id);
    expect(a.destination?.id, isNot(b.id));
  });
  test(
    'safety avoids port behind the pirate and merchant ends chase at port',
    () {
      final m = boat('m', role: BehaviorMode.merchant), p = boat('p', x: 350);
      final v = world([m, p]);
      final safe = v.npc.safePort(m, p)!;
      expect(safe.id, isNot('east'));
      m.fleeing = true;
      m.threatId = p.id;
      m.destination = safe;
      m.position = safe.position;
      p.destination = Destination(
        m.id,
        m.name,
        m.position,
        DestinationKind.ship,
      );
      v.life.startPort(m);
      expect(m.atSea, isFalse);
      expect(p.destination, isNull);
      expect(m.respawnRemaining, 0);
    },
  );
  test(
    'pirate boarding adds cargo and a captured hull once, preserving battle lock',
    () {
      final a = boat('a', hull: 'Man-of-War', owned: true)..ordnance = 'grape';
      final b = boat('b', hull: 'Brig')..cargo = 8;
      final v = world([a, b], decisions: false);
      a.destination = Destination(
        b.id,
        b.name,
        b.position,
        DestinationKind.ship,
      );
      v.update(.01);
      final result = v.active.single.result;
      final prior = v.progress.inventory.length;
      v.update(result.duration - 1);
      expect(a.cargo, 0);
      expect(v.busy(a.id), isTrue);
      v.update(1);
      expect(a.cargo, 8);
      expect(v.progress.inventory.length, prior + 1);
      v.update(.01);
      expect(v.progress.inventory.length, prior + 1);
    },
  );
  test(
    'schema seven preserves equipment copies chain and captain/chase state',
    () async {
      String? data;
      final store = VoyageStore(
        read: () async => data,
        write: (s) async {
          data = s;
        },
      );
      final v = createCaribbean();
      final s = v.ships.first;
      give(v, 'chain', ship: s.id);
      give(v, 'pistol', ship: s.id);
      give(v, 'navigator', ship: s.id);
      s.chainPenalty = .55;
      final npc = v.ships[1]
        ..fleeing = true
        ..threatId = v.ships[2].id
        ..fleeTime = 12;
      await store.save(v);
      final loaded = await store.load();
      expect(jsonDecode(data!)['version'], 7);
      expect(loaded.ships.first.chainPenalty, .55);
      expect(loaded.ships.first.ordnance, 'chain');
      expect(loaded.ships[1].npcTolerance, npc.npcTolerance);
      expect(loaded.ships[1].fleeTime, 12);
      expect(loaded.progress.commands[s.id]!.equipped.length, 3);
    },
  );
  test(
    'legacy generic officer and gear migrate without discarding physical copies',
    () async {
      String? data;
      final store = VoyageStore(
        read: () async => data,
        write: (s) async {
          data = s;
        },
      );
      final v = createCaribbean();
      await store.save(v);
      final j = jsonDecode(data!);
      j['version'] = 6;
      j['progression']['inventory'] = [
        {
          'id': 'item-1',
          'name': 'Old officer',
          'kind': 'officer',
          'hull': null,
          'rarity': 'common',
          'bonus': 1,
          'specialist': null,
        },
        {
          'id': 'item-2',
          'name': 'Old gear',
          'kind': 'gear',
          'hull': null,
          'rarity': 'common',
          'bonus': 1,
        },
      ];
      j['progression']['nextItem'] = 3;
      j['progression']['commands'][0]['equipped'] = {
        'officer': 'item-1',
        'gear': 'item-2',
      };
      data = jsonEncode(j);
      final loaded = await store.load();
      expect(loaded.progress.inventory.length, 2);
      expect(
        loaded.progress.commands.values.first.equipped[ItemKind.quartermaster],
        'item-1',
      );
      expect(
        loaded.progress.commands.values.first.equipped[ItemKind.body],
        'item-2',
      );
      await store.save(loaded);
      expect((await store.load()).progress.inventory.length, 2);
    },
  );
}
