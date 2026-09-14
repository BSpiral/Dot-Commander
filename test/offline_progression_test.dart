import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/ui/command_screen.dart';

void main() {
  group('Balance.offlineRewardCoins (the shared formula)', () {
    test('zero tree level always grants nothing, any elapsed time', () {
      expect(Balance.offlineRewardCoins(0, 0), 0);
      expect(Balance.offlineRewardCoins(0, 500), 0);
      expect(Balance.offlineRewardCoins(0, 100000), 0);
    });

    test('zero elapsed minutes grants nothing, any tree level', () {
      expect(Balance.offlineRewardCoins(1000, 0), 0);
    });

    test('reward scales with elapsed minutes and tree level', () {
      // 500/1000 level -> cap 360 min (halfway from 240 to 480).
      expect(Balance.offlineRewardCoins(500, 360), 180);
      expect(Balance.offlineRewardCoins(1000, 480), 480);
    });

    test('clamps to the tree level\'s own offline cap, never exceeding it', () {
      final cap = Balance.offlineCapMinutes(500);
      final atCap = Balance.offlineRewardCoins(500, cap);
      final wayOver = Balance.offlineRewardCoins(500, cap * 10);
      expect(wayOver, atCap);
    });

    test('negative elapsed minutes (a clock anomaly) never grants a negative reward', () {
      expect(Balance.offlineRewardCoins(500, -100), 0);
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
        v.progress.tree[FleetTrack.offline] = 500;
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

        final expectedReward = Balance.offlineRewardCoins(500, 6 * 60);
        expect(expectedReward, greaterThan(0));
        expect(find.text('● ${500 + expectedReward} coins'), findsOneWidget);

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
      'a zero-investment fleet (no Offline Effectiveness levels) resumes '
      'with no reward -- expected, not a bug',
      (tester) async {
        String? data;
        final store = VoyageStore(
          read: () async => data,
          write: (s) async {
            data = s;
          },
        );
        final v = createCaribbean()..coins = 500;
        await store.save(v); // FleetTrack.offline left at its default (0)

        var now = DateTime(2026, 6, 1, 12, 0);
        await tester.pumpWidget(
          MaterialApp(home: CommandScreen(store: store, now: () => now)),
        );
        await tester.pump(const Duration(milliseconds: 100));

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        now = now.add(const Duration(hours: 10));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();

        expect(find.text('● 500 coins'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
