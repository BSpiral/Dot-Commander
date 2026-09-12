import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';
import 'package:dot_commander/pirates/progression/life_balance.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';
import 'package:dot_commander/pirates/encounters/encounter_result.dart';

void main() {
  test(
    'eleven cycles: gold, blue, final MAXED; linear rewards and steeper costs',
    () {
      final c = CommandProgress('x');
      for (var stars = 1; stars <= 5; stars++) {
        c.tree[CommandTrack.hull] = stars * 100;
        expect(c.label(CommandTrack.hull), '0 / 100 ${'★' * stars}');
      }
      c.tree[CommandTrack.hull] = 600;
      expect(c.label(CommandTrack.hull), '0 / 100 ★ Super Prestige');
      c.tree[CommandTrack.hull] = 1000;
      expect(c.label(CommandTrack.hull), '0 / 100 ★★★★★ Super Prestige');
      c.tree[CommandTrack.hull] = 1100;
      expect(c.label(CommandTrack.hull), 'MAXED');
      for (var cycle = 0; cycle < 11; cycle++) {
        expect(
          LifeBalance.rewardUnits(cycle * 100 + 1) -
              LifeBalance.rewardUnits(cycle * 100),
          (cycle + 1).toDouble(),
        );
      }
      expect(LifeBalance.cost(100), 808);
      expect(LifeBalance.percent(1100), .2);
    },
  );
  test(
    'new expensive commands are independent; fleet offline stays shared',
    () {
      final v = createCaribbean()..coins = 2000000;
      final c = v.progress.commands.values.first;
      c.tree[CommandTrack.hull] = 600;
      v.progress.tree[FleetTrack.offline] = 500;
      for (var i = 1; i < 5; i++) {
        final before = v.coins;
        final id = v.purchaseSlot()!;
        expect(before - v.coins, LifeBalance.commandPrices[i]);
        expect(v.progress.commands[id]!.tree, isEmpty);
      }
      expect(v.progress.offlineCapMinutes, 360);
      expect(v.progress.commands.values.first.level(CommandTrack.hull), 600);
    },
  );
  test('timed port stages have capacity ten, sell first then pay and load', () {
    final v = createCaribbean()..coins = 100;
    final s = v.ships.first;
    s.hullHp = 40;
    s.crewCount = 0;
    s.cargo = 4;
    s.destination = v.life.portFor(s);
    s.position = s.destination!.position;
    v.life.startPort(s);
    expect(v.coins, 108);
    expect(s.hullHp, 40);
    expect(s.crewCount, 0);
    v.life.tick(2);
    expect(v.coins, 98);
    expect(s.hullHp, 40);
    v.life.tick(5);
    expect(s.hullHp, 50);
    expect(v.coins, 88);
    v.life.tick(5);
    expect(s.crewCount, 10);
    expect(v.coins, 84);
    expect(v.life.works[s.id]!.remaining, 2);
    v.life.tick(2);
    expect(s.cargo, 4);
    expect(v.life.works, isEmpty);
  });
  test(
    'poor tax restores only capacity and exactly one restart cargo without cash',
    () {
      final v = createCaribbean();
      final s = v.ships.first
        ..hullHp = 0
        ..crewCount = 0
        ..cargo = 0;
      s.destination = v.life.portFor(s);
      s.position = s.destination!.position;
      v.life.startPort(s);
      for (var i = 0; i < 200; i++) {
        v.life.tick(.1);
      }
      expect(s.hullHp, 10);
      expect(s.crewCount, 10);
      expect(s.cargo, 1);
      expect(v.coins, 0);
    },
  );
  test(
    'Hull and Crew zero independently remove player and respawn at correct port',
    () {
      for (final crewDeath in [false, true]) {
        final v = createCaribbean();
        final s = v.ships.first
          ..behavior = BehaviorMode.pirate
          ..cargo = 4;
        if (crewDeath) {
          s.crewCount = 0;
        } else {
          s.hullHp = 0;
        }
        v.update(.01);
        expect(s.atSea, false);
        expect(s.cargo, 0);
        v.update(5.1);
        expect(s.destination!.id, 'tortuga');
        expect(v.life.works.containsKey(s.id), true);
      }
    },
  );
  test('pirate absence is sixty seconds and reentry uses Pirate Haven', () {
    final v = createCaribbean();
    final s = v.ships.firstWhere(
      (s) => !s.playerOwned && s.behavior == BehaviorMode.pirate,
    )..hullHp = 0;
    v.life.defeat(s);
    v.life.tick(59);
    expect(s.atSea, false);
    v.life.tick(1.01);
    expect(s.atSea, true);
    expect(s.destination!.id, 'tortuga');
  });
  test(
    'player piracy triggers both Hunters and retirement happens only at port',
    () {
      final v = createCaribbean(encountersEnabled: true);
      for (final s in v.ships) {
        s.behavior = BehaviorMode.merchant;
      }
      for (final s in v.ships.take(4)) {
        s.behavior = BehaviorMode.pirate;
      }
      v.life.tick(.01);
      expect(v.ships.where((s) => s.hunter && s.atSea).length, 1);
      for (final s in v.ships.take(8)) {
        s.behavior = BehaviorMode.pirate;
      }
      v.life.tick(.01);
      expect(v.ships.where((s) => s.hunter && s.atSea).length, 2);
      for (final s in v.ships.where((s) => !s.hunter)) {
        s.behavior = BehaviorMode.merchant;
      }
      v.life.tick(.01);
      final hunters = v.ships.where((s) => s.hunter && s.atSea).toList();
      expect(hunters.length, 2);
      for (final s in hunters) {
        expect(s.returnToPort, true);
        expect(s.retiring, true);
        s.position = s.destination!.position;
        s.activity = Activity.sailing;
      }
      v.update(.01);
      expect(v.ships.where((s) => s.hunter && s.atSea), isEmpty);
    },
  );
  test(
    'population cap excludes player commands and replacement weight favors scarcity',
    () {
      final v = createCaribbean()..coins = 2000000;
      for (var i = 0; i < 4; i++) {
        v.purchaseSlot();
      }
      for (var i = 0; i < 50; i++) {
        v.life.spawn(BehaviorMode.merchant);
      }
      expect(v.life.npcCount, 20);
      expect(v.ships.where((s) => s.playerOwned).length, 5);
      for (final s in v.ships.where((s) => !s.playerOwned)) {
        s.behavior = BehaviorMode.privateer;
      }
      var merchants = 0;
      for (var i = 0; i < 500; i++) {
        if (v.life.weightedRole() == BehaviorMode.merchant) merchants++;
      }
      expect(merchants, greaterThan(250));
    },
  );
  test(
    'merchant second attack predetermines defeat; docking resets attack count',
    () {
      final v = createCaribbean();
      final a = v.ships.first..behavior = BehaviorMode.pirate;
      final b = v.ships[1]
        ..behavior = BehaviorMode.merchant
        ..speed = 200
        ..fleeing = true;
      v.life.attacked(b, a);
      final first = const PrototypeResolver().resolve(
        '1',
        Combatant.capture(a),
        Combatant.capture(b),
      );
      expect(first.kind, EncounterKind.escape);
      v.life.attacked(b, a);
      final second = const PrototypeResolver().resolve(
        '2',
        Combatant.capture(a),
        Combatant.capture(b),
      );
      expect(second.winnerId, a.id);
      expect(second.damageB, b.hullHp);
      b.destination = v.life.portFor(b);
      v.life.startPort(b);
      expect(b.attacksSincePort, 0);
    },
  );
  test(
    'cannon hits Hull harder than Crew; boarding can defeat via Crew alone',
    () {
      final v = createCaribbean();
      final a = v.ships.first..firepower = 100;
      final b = v.ships[1];
      final r = const PrototypeResolver().resolve(
        'c',
        Combatant.capture(a),
        Combatant.capture(b),
      );
      expect(r.kind, EncounterKind.cannon);
      expect(r.damageB, b.hullHp);
      expect(r.crewLossB, lessThan(b.crewCount));
    },
  );
  test(
    'port work and bounded log survive reload without repeating cargo sale',
    () async {
      String? data;
      final store = VoyageStore(
        read: () async => data,
        write: (s) async {
          data = s;
        },
      );
      final v = createCaribbean()..coins = 100;
      final s = v.ships.first
        ..cargo = 4
        ..hullHp = 70;
      s.destination = v.life.portFor(s);
      s.position = s.destination!.position;
      v.life.startPort(s);
      for (var i = 0; i < 200; i++) {
        v.life.log(s, 'event $i');
      }
      expect(s.recentActivity.length, 12);
      await store.save(v);
      final loaded = await store.load();
      expect(loaded.coins, 108);
      expect(loaded.life.works.length, 1);
      expect(loaded.ships.first.recentActivity.length, 12);
      loaded.life.tick(2);
      expect(loaded.coins, 98);
    },
  );
  test('Carpenter/Bosun hooks are bounded and cost twice port price', () {
    final v = createCaribbean()..coins = 100;
    final s = v.ships.first
      ..hullHp = 50
      ..crewCount = 10;
    v.progress.inventory.add(
      const EquipmentItem(
        'item-1',
        'Carpenter',
        ItemKind.quartermaster,
        specialist: 'carpenter',
      ),
    );
    v.progress.commands[s.id]!.equipped[ItemKind.quartermaster] = 'item-1';
    v.life.fieldSupport(s);
    expect(s.hullHp, 52);
    expect(v.coins, 96);
    v.progress.inventory.add(
      const EquipmentItem(
        'item-2',
        'Bosun',
        ItemKind.quartermaster,
        specialist: 'bosun',
      ),
    );
    v.progress.commands[s.id]!.equipped[ItemKind.quartermaster] = 'item-2';
    v.life.fieldSupport(s);
    expect(s.crewCount, 12);
    expect(v.coins, 92);
  });
}
