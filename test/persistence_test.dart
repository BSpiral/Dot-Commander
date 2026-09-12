import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/core/persistence/voyage_snapshot.dart';
import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';

void main() {
  test(
    'round-trip preserves identities, orders, coordinates, stats and dock state',
    () {
      final sim = createCaribbean();
      final ship = sim.ships.first;
      ship.position = sim.places.first.position;
      ship.destination = sim.places.first;
      ship.activity = Activity.docked;
      ship.pauseRemaining = 1.3;
      ship.hullHp = 53;
      final restored = VoyageSnapshot.decode(
        VoyageSnapshot.encode(sim.ships),
        sim.navigation,
        sim.places,
      );
      expect(VoyageSnapshot.encode(restored), VoyageSnapshot.encode(sim.ships));
      final resumed = createCaribbean(restoredShips: restored);
      resumed.update(.5);
      expect(restored.first.activity, Activity.docked);
      for (
        var i = 0;
        i < 300 && restored.first.activity == Activity.docked;
        i++
      ) {
        resumed.update(.02);
      }
      expect(restored.first.activity, Activity.sailing);
      expect(restored.first.pauseRemaining, 0);
      expect(
        () => VoyageSnapshot.decode(
          VoyageSnapshot.encode(restored),
          sim.navigation,
          sim.places,
        ),
        returnsNormally,
      );
    },
  );
  test(
    'ship target remains attached to the same persistent identity on reload',
    () {
      final sim = createCaribbean();
      sim.setBehavior(sim.ships.first, BehaviorMode.privateer);
      final target = sim.ships.first.destination!.id;
      final restored = VoyageSnapshot.decode(
        VoyageSnapshot.encode(sim.ships),
        sim.navigation,
        sim.places,
      );
      expect(restored.first.destination!.id, target);
      expect(restored.first.behavior, BehaviorMode.privateer);
    },
  );
  for (final change in ['version', 'duplicate', 'land', 'target', 'number']) {
    test('invalid $change snapshot is rejected', () {
      final sim = createCaribbean();
      final root =
          jsonDecode(VoyageSnapshot.encode(sim.ships)) as Map<String, dynamic>;
      final rows = root['ships'] as List;
      switch (change) {
        case 'version':
          root['version'] = 99;
        case 'duplicate':
          rows[1]['id'] = rows[0]['id'];
        case 'land':
          rows[0]['position'] = [110, 102];
        case 'target':
          rows[0]['destination'] = {
            'id': 'missing',
            'name': 'lost',
            'position': [20, 20],
            'kind': 'ship',
          };
        case 'number':
          rows[0]['speed'] = -1;
      }
      expect(
        () =>
            VoyageSnapshot.decode(jsonEncode(root), sim.navigation, sim.places),
        throwsFormatException,
      );
    });
  }
  test(
    'local store reloads names and orders; no elapsed offline simulation',
    () async {
      String? saved;
      final store = VoyageStore(
        read: () async => saved,
        write: (value) async {
          saved = value;
        },
      );
      final sim = await store.load();
      sim.setBehavior(sim.ships.first, BehaviorMode.explorer);
      sim.update(1);
      await store.save(sim);
      final loaded = await store.load();
      expect(
        VoyageSnapshot.encode(loaded.ships),
        VoyageSnapshot.encode(sim.ships),
      );
    },
  );
  test(
    'serialized writes retain latest state and recover after write failure',
    () async {
      final writes = <String>[];
      final gate = Completer<void>();
      var attempt = 0;
      final store = VoyageStore(
        read: () async => null,
        write: (value) async {
          if (attempt++ == 0) {
            await gate.future;
            throw StateError('disk');
          }
          writes.add(value);
        },
      );
      final sim = createCaribbean();
      final first = store.save(sim);
      final failure = expectLater(first, throwsStateError);
      sim.setBehavior(sim.ships.first, BehaviorMode.explorer);
      final second = store.save(sim);
      gate.complete();
      await failure;
      await second;
      expect(
        jsonDecode(writes.single)['ships'],
        jsonDecode(VoyageSnapshot.encode(sim.ships))['ships'],
      );
    },
  );
}
