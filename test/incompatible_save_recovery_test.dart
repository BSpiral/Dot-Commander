import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dot_commander/main.dart';
import 'package:dot_commander/pirates/persistence/voyage_store.dart';

/// Incompatible-save recovery pass: the old "Could not load voyage.
/// Original save preserved; autosave paused." dead-end now has a real
/// "Start New Voyage" action. Deliberately NOT testing old-save
/// migration (out of scope per the brief) -- these tests only cover the
/// recovery path itself: the failure state, the explicit opt-in action,
/// and that nothing writes over the original save before that action is
/// taken.
void main() {
  Future<void> pumpApp(WidgetTester tester, VoyageStore store) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(DotCommanderApp(store: store));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'an incompatible old save shows the failure message and a Start New Voyage action',
    (tester) async {
      final store = VoyageStore(
        // Garbage that jsonDecode itself rejects -- simulates a genuinely
        // incompatible/corrupt old save, not a specific schema version.
        read: () async => 'not valid json{{{',
        write: (_) async {},
      );
      await pumpApp(tester, store);

      expect(
        find.text('Could not load voyage. Original save preserved; autosave paused.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('start_new_voyage_button')), findsOneWidget);
    },
  );

  testWidgets(
    'the original incompatible save is never overwritten before Start New Voyage is chosen',
    (tester) async {
      int writeCount = 0;
      final store = VoyageStore(
        read: () async => 'not valid json{{{',
        write: (_) async => writeCount++,
      );
      await pumpApp(tester, store);
      expect(writeCount, 0);

      // Let the normal 5-second autosave timer fire several times over --
      // canSave must have stayed false, so _save() must keep no-op-ing.
      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 5));
      }
      expect(
        writeCount,
        0,
        reason: 'autosave must stay paused until Start New Voyage is explicitly chosen',
      );
      expect(find.byKey(const Key('start_new_voyage_button')), findsOneWidget);
    },
  );

  testWidgets(
    'choosing Start New Voyage discards the old save, writes a fresh one, restores autosaving, and enters the game normally',
    (tester) async {
      // A real store re-reads whatever was actually last written -- the
      // freshly-pushed CommandScreen this action navigates to calls
      // load() again for real, so the mock must behave like real
      // storage (serve back the latest write), not a fixed constant, or
      // the new screen would "fail to load" its own just-written save.
      String? onDisk = 'not valid json{{{';
      int writeCount = 0;
      final store = VoyageStore(
        read: () async => onDisk,
        write: (s) async {
          onDisk = s;
          writeCount++;
        },
      );
      await pumpApp(tester, store);
      expect(find.byKey(const Key('start_new_voyage_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('start_new_voyage_button')));
      await tester.pump();
      // Enough pumps to let store.save() resolve, the pushReplacement
      // transition finish, and the freshly-pushed CommandScreen's own
      // _load() resolve too -- deliberately several bounded pumps, not
      // pumpAndSettle (which would hang against the live simulation
      // Timer.periodic, same reasoning as this project's other widget
      // tests).
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      // A completely fresh voyage was written over the old (discarded)
      // incompatible save -- real, current-schema content, not a
      // migration of the old one (there was nothing decodable to migrate
      // from in the first place). At least one write is the discard
      // -and-replace itself; the freshly-pushed screen's own normal
      // revision-watcher (see command_screen.dart's 250ms timer) may
      // legitimately autosave once more shortly after loading -- same
      // pre-existing behavior any successful load already has, nothing
      // to do with this recovery path specifically.
      expect(writeCount, greaterThanOrEqualTo(1));
      expect(onDisk, isNotNull);
      final root = jsonDecode(onDisk!) as Map<String, dynamic>;
      expect(root['version'], 7);

      // The failure state is gone; the game is playable normally.
      expect(find.byKey(const Key('start_new_voyage_button')), findsNothing);
      expect(
        find.text('Could not load voyage. Original save preserved; autosave paused.'),
        findsNothing,
      );
      expect(find.byKey(const Key('banner_ad_bar')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Autosaving is genuinely restored, not just cosmetically -- the
      // normal 5-second timer produces a real further write.
      final writesBefore = writeCount;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 100));
      expect(writeCount, greaterThan(writesBefore));
    },
  );

  testWidgets(
    'a save that loads successfully never shows the Start New Voyage action',
    (tester) async {
      String? saved;
      final store = VoyageStore(
        read: () async => saved,
        write: (s) async => saved = s,
      );
      await pumpApp(tester, store);
      expect(find.byKey(const Key('start_new_voyage_button')), findsNothing);
    },
  );

  testWidgets(
    'a genuinely absent save (first launch / fresh install) loads a playable voyage that can itself be saved and reloaded',
    (tester) async {
      // No pre-existing data at all -- read() returning null is exactly
      // what a real fresh install looks like (nothing has ever been
      // written yet), distinct from the other tests above which all start
      // from undecodable garbage simulating an old incompatible save.
      String? onDisk;
      int writeCount = 0;
      final store = VoyageStore(
        read: () async => onDisk,
        write: (s) async {
          onDisk = s;
          writeCount++;
        },
      );
      await pumpApp(tester, store);

      expect(find.byKey(const Key('start_new_voyage_button')), findsNothing);
      expect(find.text('Could not load voyage. Original save preserved; autosave paused.'), findsNothing);
      expect(find.byKey(const Key('banner_ad_bar')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // The normal 5-second autosave timer produces a real write of the
      // brand-new voyage -- proving it isn't just held in memory.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 100));
      expect(writeCount, greaterThanOrEqualTo(1));
      expect(onDisk, isNotNull);
      final root = jsonDecode(onDisk!) as Map<String, dynamic>;
      expect(root['version'], 7);

      // A second, independent CommandScreen against the SAME store (the
      // same on-disk state a real relaunch would see) must load that
      // freshly-created save cleanly, not fail.
      final store2 = VoyageStore(
        read: () async => onDisk,
        write: (s) async => onDisk = s,
      );
      await pumpApp(tester, store2);
      expect(find.byKey(const Key('start_new_voyage_button')), findsNothing);
      expect(find.byKey(const Key('banner_ad_bar')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'there is no Cancel/Back action on this screen -- backgrounding or closing the app while a save is incompatible never writes over the preserved save',
    (tester) async {
      // CommandScreen is the app's home route (see DotCommanderApp) with no
      // AppBar back arrow, so the only way a player can leave this state
      // without pressing Start New Voyage is backgrounding or exiting the
      // app -- exercised here via the same WidgetsBindingObserver
      // lifecycle callback and dispose() the real app would go through.
      int writeCount = 0;
      final store = VoyageStore(
        read: () async => 'not valid json{{{',
        write: (_) async => writeCount++,
      );
      await pumpApp(tester, store);
      expect(find.byKey(const Key('start_new_voyage_button')), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await tester.pump();
      expect(writeCount, 0);

      await tester.pumpWidget(const SizedBox());
      expect(
        writeCount,
        0,
        reason: 'disposing the incompatible-save screen must never write over the preserved save',
      );
    },
  );
}
