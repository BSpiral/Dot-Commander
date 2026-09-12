import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/pirates/theater/battle_script.dart';
import 'package:dot_commander/pirates/theater/preview_script.dart';
import 'package:dot_commander/ui/theater/deck_theater.dart';
import 'package:flutter/material.dart';

void main() {
  test(
    'seek is deterministic, clamps endpoints and preserves supplied ending',
    () {
      final script = previewScript();
      final a = script.sample(5);
      script.sample(12);
      final b = script.sample(5);
      expect(a.player.x, b.player.x);
      expect(a.player.x, inExclusiveRange(.48, .55));
      expect(script.sample(-1).phase, TheaterPhase.encounter);
      expect(script.sample(100).complete, isTrue);
      expect(script.ending, TheaterEnding.playerVictory);
      expect(() => script.frames.clear(), throwsUnsupportedError);
      expect(() => script.sample(double.nan), throwsArgumentError);
    },
  );
  test('cannons occur during movement before damaged boarding alignment', () {
    final script = previewScript();
    expect(script.sample(4.5).phase, TheaterPhase.cannon);
    expect(script.sample(4.5).opponent.x, isNot(script.sample(5).opponent.x));
    expect(script.cannonCues.every((c) => c.seconds + c.duration < 7), isTrue);
    final board = script.sample(10);
    expect(board.phase, TheaterPhase.boarding);
    expect(board.player.x, board.opponent.x);
    expect(board.planks, 3);
    expect(board.opponentDamage.hull, greaterThan(.5));
    expect(board.opponentDamage.sails, greaterThan(0));
    expect(board.opponentDamage.smoke, greaterThan(0));
    expect(board.opponentDamage.crewFraction, lessThan(1));
  });
  test('escape fixture completes without closing or boarding', () {
    final script = previewScript(escape: true);
    expect(script.ending, TheaterEnding.escaped);
    expect(
      script.frames.any(
        (f) => f.phase == TheaterPhase.boarding || f.planks > 0,
      ),
      isFalse,
    );
    expect(script.sample(12).opponent.x, greaterThan(1));
    expect(script.sample(13).complete, isTrue);
  });
  test('invalid timelines are rejected at boundary', () {
    const first = TheaterKeyframe(
      seconds: 0,
      phase: TheaterPhase.encounter,
      player: DeckPose(.5, .7),
      opponent: DeckPose(.5, .3),
    );
    const end = TheaterKeyframe(
      seconds: 2,
      phase: TheaterPhase.complete,
      player: DeckPose(.5, .7),
      opponent: DeckPose(.5, .3),
    );
    for (final frames in <List<TheaterKeyframe>>[
      [],
      [first],
      [first, first, end],
      [
        first,
        const TheaterKeyframe(
          seconds: 2,
          phase: TheaterPhase.complete,
          player: DeckPose(.5, .7),
          opponent: DeckPose(.5, .3),
          opponentDamage: TheaterDamage(hull: 2),
        ),
      ],
    ]) {
      expect(
        () => BattleScript(
          id: 'invalid',
          ending: TheaterEnding.draw,
          frames: frames,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => BattleScript(
        id: 'invalid',
        ending: TheaterEnding.draw,
        frames: [first, end],
        cannonCues: [const CannonCue(1, 2, DeckPose(0, 0), DeckPose(1, 1))],
      ),
      throwsArgumentError,
    );
  });
  test('horizontal decks leave boarding gap across narrow stages', () {
    for (final width in [288.0, 328.0, 358.0, 398.0]) {
      final size = Size(width, width / 2.8);
      final a = DeckGeometry.bounds(size, const DeckPose(.5, .68), .48);
      final b = DeckGeometry.bounds(size, const DeckPose(.5, .32), .48);
      expect(a.width / a.height, closeTo(3.8, .01));
      expect(b.bottom, lessThan(a.top));
      expect(a.left, greaterThan(0));
      expect(a.right, lessThan(width));
    }
  });
  testWidgets('preview remains scrollable in narrow and landscape layouts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [const Size(320, 568), const Size(844, 390)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: TheaterPreview())),
      );
      await tester.pump(const Duration(seconds: 13));
      await tester.ensureVisible(find.text('Replay'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets('preview can seek and switch to escape without voyage state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TheaterPreview())),
    );
    await tester.pump(const Duration(seconds: 11));
    expect(find.textContaining('boarding'), findsWidgets);
    await tester.tap(find.text('Boarding / escape'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 13));
    expect(find.text('Supplied ending: escaped'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
