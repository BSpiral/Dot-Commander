import 'dart:convert';
import 'package:flame/game.dart';
import 'package:dot_commander/pirates/visuals/pirates_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/main.dart';
import 'package:dot_commander/core/persistence/voyage_snapshot.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';

void main() {
  testWidgets('expanded activity survives Tree and Deck round trip', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = VoyageStore(read: () async => null, write: (_) async {});
    await tester.pumpWidget(DotCommanderApp(store: store));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Recent activity'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('tab_tree')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tab_deck')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('Recent activity'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  for (final size in [
    const Size(320, 568),
    const Size(360, 780),
    const Size(390, 844),
    const Size(430, 932),
    const Size(844, 390),
    const Size(1200, 800),
  ]) {
    testWidgets('fleet, map orders and five management tabs at $size', (
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
      await tester.pumpWidget(DotCommanderApp(store: store));
      await tester.pump(const Duration(milliseconds: 100));
      // The redundant title/AppBar was removed (presentation pass): the
      // banner now occupies the recovered top area instead.
      expect(find.text('Dot Commander: Pirates'), findsNothing);
      expect(find.byKey(const Key('banner_ad_bar')), findsOneWidget);
      expect(find.text('15 sails'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('fleet_slot_1')))
            .onPressed,
        isNotNull,
      );
      final management = tester.getSize(
        find.byKey(const Key('management_area')),
      );
      final mapRect = tester.getRect(find.byKey(const Key('living_map')));
      final managementRect = tester.getRect(
        find.byKey(const Key('management_area')),
      );
      if (size.width < size.height) {
        expect(managementRect.top, greaterThanOrEqualTo(mapRect.bottom));
        expect(managementRect.width, size.width);
        expect(
          tester.getRect(find.byKey(const Key('tab_shop'))).top,
          closeTo(managementRect.top, 1),
        );
      } else {
        expect(managementRect.left, greaterThanOrEqualTo(mapRect.right));
      }
      if (size.width < size.height) {
        expect(
          management.height /
              (management.height +
                  tester.getSize(find.byKey(const Key('living_map'))).height),
          // Range raised again (playability pass 2026-09-18): the
          // management panel's height share was deliberately increased
          // (.38 -> .48 of available height, see command_screen.dart) so
          // the Deck tab has substantially more room, per real playtest
          // feedback that it was being squeezed into too small a strip.
          // The map still gets the majority of the screen.
          inInclusiveRange(.48, .58),
        );
      }
      for (var i = 0; i < 5; i++) {
        final rect = tester.getRect(find.byKey(Key('fleet_slot_$i')));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.height, greaterThanOrEqualTo(48));
      }
      // The behavior selector is now a small persistent tag -- an overlay
      // that never reserves map space (see the "Behavior tag/overlay"
      // tests below for the map-space-recovery assertion itself) -- so
      // the game chart now always extends to the map's full bottom
      // edge, with no carve-out for a permanently-expanded selector.
      final tagRect = tester.getRect(find.byKey(const Key('behavior_tag')));
      expect(tagRect.width, greaterThanOrEqualTo(48));
      expect(tagRect.height, greaterThanOrEqualTo(32));
      final chartRect = tester.getRect(find.byType(GameWidget<PiratesGame>));
      expect(chartRect.bottom, closeTo(mapRect.bottom, .5));
      final deckSize = tester.getSize(find.byKey(const Key('broadside_deck')));
      expect(deckSize.width / deckSize.height, closeTo(2.8, .01));
      await tester.tap(find.byKey(const Key('behavior_tag')));
      await tester.pump();
      expect(find.byKey(const Key('order_explorer')), findsOneWidget);
      await tester.tap(find.byKey(const Key('order_explorer')));
      await tester.pump();
      expect((await store.load()).ships.first.behavior.name, 'explorer');
      // Selecting a behavior closes the overlay back to the small tag.
      expect(find.byKey(const Key('order_explorer')), findsNothing);
      for (final tab in ['shop', 'tree', 'upgrades', 'deck', 'settings']) {
        final finder = find.byKey(Key('tab_$tab'));
        expect(tester.getRect(finder).bottom, lessThanOrEqualTo(size.height));
        await tester.tap(finder);
        await tester.pump();
        expect(find.byKey(const Key('behavior_tag')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'tapping outside the open behavior popup dismisses it without changing '
    'the selected behavior',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = VoyageStore(read: () async => null, write: (_) async {});
      await tester.pumpWidget(DotCommanderApp(store: store));
      await tester.pump(const Duration(milliseconds: 100));
      final before = (await store.load()).ships.first.behavior.name;
      await tester.tap(find.byKey(const Key('behavior_tag')));
      await tester.pump();
      expect(find.byKey(const Key('order_explorer')), findsOneWidget);
      // Tap somewhere clearly outside the popup (top-left corner, near
      // the ad banner) -- the popup is a real Overlay entry now, so this
      // exercises hit-testing across the whole screen, not just within
      // the map's own bounds.
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(find.byKey(const Key('order_explorer')), findsNothing);
      expect((await store.load()).ships.first.behavior.name, before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'five owned ships select independently and retain individual orders',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = jsonDecode(VoyageSnapshot.encode(createCaribbean().ships));
      for (var i = 0; i < 5; i++) {
        data['ships'][i]['playerOwned'] = true;
      }
      String? saved = jsonEncode(data);
      final store = VoyageStore(
        read: () async => saved,
        write: (s) async {
          saved = s;
        },
      );
      await tester.pumpWidget(DotCommanderApp(store: store));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(Key('fleet_slot_$i')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('behavior_tag')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('order_privateer')));
        await tester.pump();
        expect((await store.load()).ships[i].behavior.name, 'privateer');
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('saved name and orders load before play, then autosave', (
    tester,
  ) async {
    final data = jsonDecode(VoyageSnapshot.encode(createCaribbean().ships));
    data['ships'][0]['name'] = 'Brine Runner';
    data['ships'][0]['behavior'] = 'explorer';
    String? saved = jsonEncode(data);
    var writes = 0;
    final store = VoyageStore(
      read: () async => saved,
      write: (s) async {
        saved = s;
        writes++;
      },
    );
    await tester.pumpWidget(DotCommanderApp(store: store));
    await tester.pump(const Duration(milliseconds: 100));
    // Not necessarily an exact standalone "Brine Runner" text widget
    // anymore -- the default tab (Deck) now folds the ship name into a
    // single compact status line ("Brine Runner • ...", see
    // management_panel.dart) rather than a separate header Text, as part
    // of reclaiming vertical space for the ship art itself.
    expect(find.textContaining('Brine Runner'), findsWidgets);
    expect(find.textContaining('explorer • Brine Runner'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(writes, greaterThan(0));
    expect((await store.load()).ships.first.name, 'Brine Runner');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('unreadable save is retained without autosave overwrite', (
    tester,
  ) async {
    var writes = 0;
    await tester.pumpWidget(
      DotCommanderApp(
        store: VoyageStore(
          read: () async => 'invalid data',
          write: (_) async {
            writes++;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Original save preserved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(writes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'portrait/wide resize retains the same live game and selected orders',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        DotCommanderApp(
          store: VoyageStore(read: () async => null, write: (_) async {}),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final before = tester
          .widget<GameWidget<PiratesGame>>(find.byType(GameWidget<PiratesGame>))
          .game!;
      await tester.tap(find.byKey(const Key('behavior_tag')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('order_explorer')));
      await tester.pump();
      for (final size in [const Size(1200, 800), const Size(320, 568)]) {
        tester.view.physicalSize = size;
        await tester.pump(const Duration(milliseconds: 100));
        final after = tester
            .widget<GameWidget<PiratesGame>>(
              find.byType(GameWidget<PiratesGame>),
            )
            .game!;
        expect(identical(before, after), isTrue);
        expect(after.simulation.ships.first.behavior.name, 'explorer');
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
