import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/main.dart';
import 'package:dot_commander/core/movement/point.dart';
import 'package:dot_commander/core/simulation/vessel.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/ui/theater/battle_deck.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(360, 780),
    const Size(390, 844),
    const Size(430, 932),
    const Size(844, 390),
    const Size(1200, 800),
  ]) {
    testWidgets('live battle cards and bottom management at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? saved;
      final store = VoyageStore(
        read: () async => saved,
        write: (s) async {
          saved = s;
        },
      );
      final sim = createCaribbean(encountersEnabled: true)
        ..soundEnabled = false;
      final a = sim.ships.first, b = sim.ships[1];
      a.position = const Point2(200, 240);
      b.position = const Point2(205, 240);
      a.behavior = BehaviorMode.pirate;
      b.behavior = BehaviorMode.pirate;
      a.destination = Destination(
        b.id,
        b.name,
        b.position,
        DestinationKind.ship,
      );
      sim.update(.01);
      await store.save(sim);
      await tester.pumpWidget(DotCommanderApp(store: store));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(BattleDeck), findsOneWidget);
      expect(find.byKey(const Key('battle_status')), findsOneWidget);
      final deck = tester.getSize(find.byKey(const Key('broadside_deck')));
      expect(deck.width / deck.height, closeTo(2.5, .01));
      expect(deck.width, greaterThan(240));
      if (size.width < size.height) {
        final map = tester.getRect(find.byKey(const Key('living_map'))),
            management = tester.getRect(
              find.byKey(const Key('management_area')),
            );
        expect(management.width, size.width);
        expect(management.top, greaterThanOrEqualTo(map.bottom));
      }
      for (final name in ['shop', 'tree', 'upgrades', 'deck', 'settings']) {
        final tab = find.byKey(Key('tab_$name'));
        expect(tester.getRect(tab).bottom, lessThanOrEqualTo(size.height));
        await tester.tap(tab);
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      expect(find.byKey(const Key('coins')), findsOneWidget);
      expect(find.byKey(const Key('gems')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
