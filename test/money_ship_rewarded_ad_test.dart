import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/main.dart';
import 'package:dot_commander/monetization/ads_service.dart';
import 'package:dot_commander/monetization/rewarded_money_ship_service.dart';
import 'package:dot_commander/pirates/encounters/pirates_voyage.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';
import 'package:dot_commander/pirates/visuals/pirates_game.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';

/// Live playtest correction 2026-09-20 (second pass, same day): the Money
/// Ship must be a rewarded-ad opportunity -- catching/tapping it only
/// starts the ad; the fleetCoinsPerHour reward is granted ONLY on a
/// confirmed completed ad. An earlier pass lost this gating and granted
/// coins directly from the tap. See CommandScreen._claimMoneyShip and
/// RewardedMoneyShipService.
///
/// [_FakeRewardedAdSource] mirrors the exact fake already used in
/// monetization_test.dart for the chest ad rows -- the real SDK-backed
/// RewardedAdController cannot be driven to report an earned reward from
/// a plain Dart/widget test (no ad ever actually loads in a test
/// environment), so the "successful ad grants the reward" half of this
/// contract is proven at the RewardedMoneyShipService layer directly,
/// exactly like RewardedChestService's own "earned" tests. The
/// CommandScreen/Flame widget-level tests below instead prove the real,
/// live wiring for the "no ad available -> tap grants nothing" path,
/// which the test environment always exercises deterministically (no ad
/// unit ever loads without hitting a real ad server).
class _FakeRewardedAdSource implements RewardedAdSource {
  RewardedShowResult result;
  int showCalls = 0;
  _FakeRewardedAdSource(this.result);

  @override
  bool get isReady => true;
  @override
  bool get isBusy => false;
  @override
  Future<void> preload() async {}
  @override
  Future<RewardedShowResult> show() async {
    showCalls++;
    return result;
  }
}

void main() {
  group('RewardedMoneyShipService (the actual gate)', () {
    test('a confirmed completed ad (earned) is the ONLY outcome that grants', () async {
      final service = RewardedMoneyShipService(ads: _FakeRewardedAdSource(RewardedShowResult.earned));
      expect(await service.watch(), RewardedMoneyShipOutcome.granted);
    });

    test('no ad ready grants nothing', () async {
      final service = RewardedMoneyShipService(ads: _FakeRewardedAdSource(RewardedShowResult.notAvailable));
      expect(await service.watch(), RewardedMoneyShipOutcome.notAvailable);
    });

    test('closing/skipping the ad before completion grants nothing', () async {
      final service = RewardedMoneyShipService(ads: _FakeRewardedAdSource(RewardedShowResult.dismissedWithoutReward));
      expect(await service.watch(), RewardedMoneyShipOutcome.dismissedWithoutReward);
    });

    test('an ad already showing (e.g. a repeated tap while one is in flight) grants nothing', () async {
      final service = RewardedMoneyShipService(ads: _FakeRewardedAdSource(RewardedShowResult.busy));
      expect(await service.watch(), RewardedMoneyShipOutcome.busy);
    });

    test(
      'granted plus PiratesVoyage.claimMoneyShip together deliver exactly the current one-hour fleet-income reward, never a stale constant',
      () async {
        final v = createCaribbean(encountersEnabled: true);
        String? moneyShipId;
        for (var i = 0; i < 5000 && moneyShipId == null; i++) {
          v.update(1.0);
          final found = v.ships.where((s) => s.isMoneyShip);
          if (found.isNotEmpty) moneyShipId = found.first.id;
        }
        expect(moneyShipId, isNotNull);

        final service = RewardedMoneyShipService(ads: _FakeRewardedAdSource(RewardedShowResult.earned));
        final outcome = await service.watch();
        expect(outcome, RewardedMoneyShipOutcome.granted);

        // This is exactly what CommandScreen._claimMoneyShip does once
        // (and only once) the service reports granted.
        final expected = Balance.fleetCoinsPerHour(v.ships).round();
        final reward = v.claimMoneyShip(moneyShipId!);
        expect(reward, expected);
        expect(reward, isNot(540), reason: 'must not be the old flat constant');
      },
    );
  });

  group('the money ship encounter cannot be double-claimed', () {
    test('a second claimMoneyShip call for the same (already-claimed) id grants nothing', () {
      final v = createCaribbean(encountersEnabled: true);
      String? moneyShipId;
      for (var i = 0; i < 5000 && moneyShipId == null; i++) {
        v.update(1.0);
        final found = v.ships.where((s) => s.isMoneyShip);
        if (found.isNotEmpty) moneyShipId = found.first.id;
      }
      expect(moneyShipId, isNotNull);
      final first = v.claimMoneyShip(moneyShipId!);
      expect(first, greaterThan(0));
      expect(v.claimMoneyShip(moneyShipId), 0);
    });
  });

  group('CommandScreen: catching the Money Ship does not directly grant coins', () {
    Future<PiratesGame> pumpAndFindGame(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = VoyageStore(read: () async => null, write: (_) async {});
      await tester.pumpWidget(DotCommanderApp(store: store));
      await tester.pump(const Duration(milliseconds: 100));
      return tester
          .widget<GameWidget<PiratesGame>>(find.byType(GameWidget<PiratesGame>))
          .game!;
    }

    Vessel spawnMoneyShip(PiratesGame game) {
      final voyage = game.simulation as PiratesVoyage;
      for (var i = 0; i < 5000 && voyage.ships.every((s) => !s.isMoneyShip); i++) {
        voyage.update(1.0);
      }
      return voyage.ships.firstWhere((s) => s.isMoneyShip);
    }

    testWidgets(
      'no ad ready in the test environment -- tapping/catching the money ship grants no coins and leaves it on the map to try again',
      (tester) async {
        final game = await pumpAndFindGame(tester);
        final voyage = game.simulation as PiratesVoyage;
        final moneyShip = spawnMoneyShip(game);
        final coinsBefore = voyage.coins;

        // Exercises the exact real path ShipComponent.onTapDown uses
        // (chart.onSelected(ship)), not a synthetic shortcut.
        game.onSelected(moneyShip);
        await tester.pump();
        await tester.pump();

        expect(
          voyage.coins,
          coinsBefore,
          reason: 'catching the money ship must never grant coins by itself -- only a completed rewarded ad may',
        );
        expect(
          voyage.ships.any((s) => s.id == moneyShip.id && s.isMoneyShip),
          isTrue,
          reason: 'a failed/unavailable ad must not consume the encounter -- the ship stays put',
        );
        expect(find.textContaining('No ad ready'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'tapping repeatedly (no ad available each time) never grants coins across multiple attempts',
      (tester) async {
        final game = await pumpAndFindGame(tester);
        final voyage = game.simulation as PiratesVoyage;
        final moneyShip = spawnMoneyShip(game);
        final coinsBefore = voyage.coins;

        for (var i = 0; i < 3; i++) {
          game.onSelected(moneyShip);
          await tester.pump();
          await tester.pump();
        }

        expect(voyage.coins, coinsBefore);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
