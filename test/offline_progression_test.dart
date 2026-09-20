import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/ui/command_screen.dart';

void main() {
  group('Balance.offlineRewardCoins (the shared formula)', () {
    test('zero fleet coins/hour always grants nothing, any elapsed time', () {
      expect(Balance.offlineRewardCoins(offlineTreeLevel: 0, elapsedMinutes: 0, fleetCoinsPerHour: 0), 0);
      expect(Balance.offlineRewardCoins(offlineTreeLevel: 0, elapsedMinutes: 500, fleetCoinsPerHour: 0), 0);
      expect(Balance.offlineRewardCoins(offlineTreeLevel: 1000, elapsedMinutes: 100000, fleetCoinsPerHour: 0), 0);
    });

    test('zero elapsed minutes grants nothing, any rate/tree level', () {
      expect(Balance.offlineRewardCoins(offlineTreeLevel: 1000, elapsedMinutes: 0, fleetCoinsPerHour: 540), 0);
    });

    test('reward scales with elapsed minutes and fleet coins/hour', () {
      // 500/1000 tree level -> cap 360 min (halfway from 240 to 480).
      expect(
        Balance.offlineRewardCoins(offlineTreeLevel: 500, elapsedMinutes: 360, fleetCoinsPerHour: 60),
        360, // 60 coins/hour * 6h = 360
      );
      expect(
        Balance.offlineRewardCoins(offlineTreeLevel: 1000, elapsedMinutes: 60, fleetCoinsPerHour: 540),
        540,
      );
    });

    test('clamps to the tree level\'s own offline cap, never exceeding it', () {
      final cap = Balance.offlineCapMinutes(500);
      final atCap = Balance.offlineRewardCoins(offlineTreeLevel: 500, elapsedMinutes: cap, fleetCoinsPerHour: 540);
      final wayOver = Balance.offlineRewardCoins(offlineTreeLevel: 500, elapsedMinutes: cap * 10, fleetCoinsPerHour: 540);
      expect(wayOver, atCap);
    });

    test('negative elapsed minutes (a clock anomaly) never grants a negative reward', () {
      expect(Balance.offlineRewardCoins(offlineTreeLevel: 500, elapsedMinutes: -100, fleetCoinsPerHour: 540), 0);
    });
  });

  group('Balance.shipThroughputFactor / shipCoinsPerHour / fleetCoinsPerHour', () {
    test('a Galley at zero bonuses is exactly the 1.0 reference ship', () {
      final v = createCaribbean();
      final ship = v.ships.firstWhere((s) => s.playerOwned);
      // apply() derives hullType from the EQUIPPED hull item (defaulting
      // to Sloop), not from whatever is assigned directly -- equip a
      // real Galley hull item, the same way the game itself would.
      final galleyHull = EquipmentItem('galley-1', 'Test Galley', ItemKind.hull, hullType: 'Galley');
      v.progress.inventory.add(galleyHull);
      v.progress.commands[ship.id]!.equipped[ItemKind.hull] = galleyHull.id;
      v.progress.apply(ship);
      expect(ship.hullType, 'Galley');
      // apply() resets speed from the hull's own baseSpeed at zero
      // Navigation investment, so this ship is exactly the reference.
      expect(Balance.shipThroughputFactor(ship), closeTo(1.0, 0.001));
      expect(Balance.shipCoinsPerHour(ship), closeTo(Balance.neutralShipCoinsPerHour, 0.5));
    });

    test('a fresh starting Sloop is meaningfully below the 1.0 reference (the "-40%" starting estimate)', () {
      final v = createCaribbean();
      final ship = v.ships.firstWhere((s) => s.playerOwned);
      expect(ship.hullType, 'Sloop');
      final rate = Balance.shipCoinsPerHour(ship);
      // Grounded in real hull stats (speed x cargo hold vs the Galley
      // reference), not a guess -- see Balance.shipCoinsPerHour's doc
      // comment for the full derivation. Lands close to (within the
      // 2026-09-20 economy audit's own "approximately") the ~324/hour
      // estimate.
      expect(rate, greaterThan(280));
      expect(rate, lessThan(360));
    });

    test('economyBonus (portRelations Tree + equipped economy gear) scales a ship\'s rate multiplicatively', () {
      final v = createCaribbean();
      final ship = v.ships.firstWhere((s) => s.playerOwned);
      final base = Balance.shipCoinsPerHour(ship);
      ship.economyBonus = .2; // the existing 0-0.2 cap
      expect(Balance.shipCoinsPerHour(ship), closeTo(base * 1.2, 0.5));
    });

    test('fleetCoinsPerHour sums every player-owned ship independently -- multiple productive ships earn proportionally more', () {
      final v = createCaribbean();
      final solo = Balance.fleetCoinsPerHour(v.ships);
      v.coins = 1000000;
      v.purchaseSlot();
      final withSecondShip = Balance.fleetCoinsPerHour(v.ships);
      expect(withSecondShip, greaterThan(solo));
    });

    test('fleetCoinsPerHour ignores NPC ships and the money ship', () {
      final v = createCaribbean();
      final playerOnly = Balance.fleetCoinsPerHour(v.ships.where((s) => s.playerOwned));
      expect(Balance.fleetCoinsPerHour(v.ships), playerOnly);
    });
  });

  group('resume-triggered offline reward (was cold-start-only)', () {
    testWidgets(
      'backgrounding then resuming after a real gap grants the same '
      'reward a cold restart would, without requiring a cold restart',
      (tester) async {
        String? data;
        final store = VoyageStore(
          read: () async => data,
          write: (s) async {
            data = s;
          },
        );
        final v = createCaribbean()..coins = 500;
        v.progress.tree[FleetTrack.offline] = 500; // 6h cap
        final fleetRate = Balance.fleetCoinsPerHour(v.ships);
        await store.save(v);

        var now = DateTime(2026, 6, 1, 12, 0);
        await tester.pumpWidget(
          MaterialApp(
            home: CommandScreen(store: store, now: () => now),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('● 500 coins'), findsOneWidget);

        // Background the app...
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        // ...6 real-world hours pass while it's away...
        now = now.add(const Duration(hours: 6));
        // ...then it's resumed (NOT relaunched -- no new CommandScreen,
        // no new VoyageStore.load() call; this is exactly the common
        // "backgrounded overnight" case the fix targets).
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        // The offline-reward SnackBar is shown from a post-frame
        // callback (see CommandScreen._showOfflineRewardNotification) so
        // it never tries to find a Scaffold mid-build -- one more pump
        // lets that callback fire and the SnackBar actually appear.
        await tester.pump();

        final expectedReward = Balance.offlineRewardCoins(
          offlineTreeLevel: 500,
          elapsedMinutes: 6 * 60,
          fleetCoinsPerHour: fleetRate,
        );
        expect(expectedReward, greaterThan(0));
        expect(find.text('● ${500 + expectedReward} coins'), findsOneWidget);
        expect(find.textContaining('$expectedReward gold'), findsOneWidget);

        final saved = await store.load();
        expect(saved.coins, 500 + expectedReward);

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'a brief background (e.g. a system dialog) grants no reward',
      (tester) async {
        String? data;
        final store = VoyageStore(
          read: () async => data,
          write: (s) async {
            data = s;
          },
        );
        final v = createCaribbean()..coins = 500;
        v.progress.tree[FleetTrack.offline] = 500;
        await store.save(v);

        var now = DateTime(2026, 6, 1, 12, 0);
        await tester.pumpWidget(
          MaterialApp(home: CommandScreen(store: store, now: () => now)),
        );
        await tester.pump(const Duration(milliseconds: 100));

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();
        now = now.add(const Duration(seconds: 2));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();

        expect(find.text('● 500 coins'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'a zero-investment fleet (no Offline Effectiveness levels) still earns a '
      'real reward from its own ships\' throughput -- the exact Saturday '
      'live-play report ("offline money is not being awarded"); the OLD '
      'formula paid literally \$0 here since it depended solely on the '
      'Offline Effectiveness Fleet Tree level, never the fleet\'s real stats',
      (tester) async {
        String? data;
        final store = VoyageStore(
          read: () async => data,
          write: (s) async {
            data = s;
          },
        );
        final v = createCaribbean()..coins = 500;
        final fleetRate = Balance.fleetCoinsPerHour(v.ships);
        await store.save(v); // FleetTrack.offline left at its default (0) -- affects the CAP only now

        var now = DateTime(2026, 6, 1, 12, 0);
        await tester.pumpWidget(
          MaterialApp(home: CommandScreen(store: store, now: () => now)),
        );
        await tester.pump(const Duration(milliseconds: 100));

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        now = now.add(const Duration(hours: 10)); // beyond the 4h default cap
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();

        final expectedReward = Balance.offlineRewardCoins(
          offlineTreeLevel: 0,
          elapsedMinutes: 10 * 60,
          fleetCoinsPerHour: fleetRate,
        );
        expect(expectedReward, greaterThan(0), reason: 'a real starting fleet has real throughput even with zero Fleet Tree investment');
        expect(find.text('● ${500 + expectedReward} coins'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
