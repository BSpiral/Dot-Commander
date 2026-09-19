import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../pirates/theater/battle_script.dart';
import '../../pirates/theater/preview_script.dart';

class DeckGeometry {
  static const aspect = 3.8;
  static const plankStations = [-.22, 0.0, .22];
  static List<double> stations(int count) => [
    for (var i = 0; i < count; i++) -.32 + .64 * (i + 1) / (count + 1),
  ];
  static Rect bounds(Size stage, DeckPose pose, double widthFraction) =>
      Rect.fromCenter(
        center: Offset(pose.x * stage.width, pose.y * stage.height),
        width: stage.width * widthFraction,
        height: stage.width * widthFraction / aspect,
      );
}

class DeckTheater extends StatelessWidget {
  final int masts, crewA, crewB;
  final double damage;
  final BattleScript? script;
  final double seconds;
  const DeckTheater({
    super.key,
    required this.masts,
    this.damage = 0,
    this.script,
    this.seconds = 0,
    this.crewA = 4,
    this.crewB = 4,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Horizontal ship cards, bow facing right',
    child: AspectRatio(
      aspectRatio: script == null ? 2.8 : 2.5,
      child: ClipRect(
        child: CustomPaint(
          key: const Key('broadside_deck'),
          painter: TheaterPainter(masts, damage, script, seconds, crewA, crewB),
        ),
      ),
    ),
  );
}

class TheaterPainter extends CustomPainter {
  final int masts, crewA, crewB;
  final double damage, seconds;
  final BattleScript? script;
  TheaterPainter(
    this.masts,
    this.damage,
    this.script,
    this.seconds,
    this.crewA,
    this.crewB,
  );
  // Ship rect is drawn ~20% smaller than the full stage (.9 -> .72 width
  // fraction) so more of the surrounding deck/activity space is visible
  // around it at once, while the stage's own AspectRatio (and therefore
  // its total on-screen size) is unchanged -- see DeckTheater.build.
  Rect _deck(Size size, DeckPose pose, {double scale = 1}) => Rect.fromCenter(
    center: Offset(pose.x * size.width, pose.y * size.height),
    width: size.width * .72 * scale,
    height:
        (script == null
            ? size.width * .72 / 3.8
            : math.min(size.width * .72 / 6.4, size.height * .27)) *
        scale,
  );
  @override
  void paint(Canvas canvas, Size size) {
    final sample = script?.sample(seconds);
    final a = _deck(size, sample?.player ?? const DeckPose(.5, .5));
    final da = sample?.playerDamage ?? TheaterDamage(hull: damage.clamp(0, 1));
    // The opponent starts far off (see result_script.dart's amplified
    // opening gap) and should read as small/distant at first, then
    // visibly grow as the already-decided encounter closes toward
    // cannon range/boarding -- purely a cosmetic size ramp keyed off
    // the current player/opponent pose gap, not a new distance
    // simulation. Player scale is left at 1 (our own ship never shrinks).
    final gap = sample == null
        ? 0.0
        : (sample.opponent.y - sample.player.y).abs();
    final opponentScale = sample == null
        ? 1.0
        : (0.55 + 0.45 * ((0.84 - gap) / (0.84 - 0.36)).clamp(0.0, 1.0));
    final b = sample == null
        ? null
        : _deck(size, sample.opponent, scale: opponentScale);
    if (b != null && sample != null) {
      for (final x in DeckGeometry.stations(sample.planks)) {
        canvas.drawLine(
          Offset(a.center.dx + x * a.width, a.bottom),
          Offset(b.center.dx + x * b.width, b.top),
          Paint()
            ..color = const Color(0xffd9bb84)
            ..strokeWidth = 5,
        );
      }
    }
    _ship(canvas, a, da, true);
    if (b != null && sample != null) {
      _ship(canvas, b, sample.opponentDamage, false);
    }
    double crossing = 0;
    if (sample != null && sample.planks > 0) {
      final start = script!.frames.firstWhere((f) => f.planks > 0).seconds;
      crossing = ((seconds - start) / (script!.duration - start)).clamp(0, 1);
    }
    _crew(
      canvas,
      a,
      b,
      crewA,
      da.crewFraction,
      true,
      crossing,
      sample?.planks ?? 0,
      script?.ending == TheaterEnding.playerVictory,
    );
    if (b != null && sample != null) {
      _crew(
        canvas,
        b,
        a,
        crewB,
        sample.opponentDamage.crewFraction,
        false,
        crossing,
        sample.planks,
        script!.ending == TheaterEnding.opponentVictory,
      );
    }
    if (script != null) {
      for (final cue in script!.cannonCues) {
        final t = (seconds - cue.seconds) / cue.duration;
        if (t < 0 || t > 1) continue;
        final origin = Offset(
          cue.from.x * size.width,
          cue.from.y * size.height,
        );
        canvas.drawCircle(
          origin,
          6 * (1 - t) + 2,
          Paint()..color = const Color(0xffffd37a),
        );
        canvas.drawCircle(
          origin + Offset(0, -8 * t),
          4 + 10 * t,
          Paint()..color = Colors.white.withValues(alpha: .45 * (1 - t)),
        );
      }
    }
    if (sample?.complete == true) {
      final win = script!.ending == TheaterEnding.playerVictory
          ? a
          : script!.ending == TheaterEnding.opponentVictory
          ? b
          : null;
      if (win != null) {
        final tp = TextPainter(
          text: const TextSpan(
            text: '⚑',
            style: TextStyle(fontSize: 22, color: Color(0xffffd37a)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, win.topRight - const Offset(25, 4));
        tp.dispose();
      }
    }
  }

  void _ship(Canvas c, Rect r, TheaterDamage state, bool owned) {
    c.drawRRect(
      RRect.fromRectAndRadius(
        r.inflate(r.height * .055),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xff194553),
    );
    final deck = Path()
      ..moveTo(r.right, r.center.dy)
      ..lineTo(r.right - r.width * .08, r.top)
      ..lineTo(r.left, r.top)
      ..lineTo(r.left, r.bottom)
      ..lineTo(r.right - r.width * .08, r.bottom)
      ..close();
    c.drawPath(
      deck,
      Paint()
        ..color = Color.lerp(
          const Color(0xff806047),
          const Color(0xff393332),
          state.hull,
        )!,
    );
    c.drawPath(
      deck,
      Paint()
        ..color = owned ? const Color(0xffffd58a) : const Color(0xffcfaaa0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    for (var x = r.left + 12; x < r.right - 12; x += 16) {
      c.drawLine(
        Offset(x, r.top + 2),
        Offset(x, r.bottom - 2),
        Paint()
          ..color = const Color(0xffac895d)
          ..strokeWidth = .6,
      );
    }
    for (var i = 0; i < masts; i++) {
      final x = r.left + r.width * (i + 1) / (masts + 1);
      c.drawLine(
        Offset(x, r.top + r.height * .25),
        Offset(x, r.bottom - r.height * (.25 + state.sails * .3)),
        Paint()
          ..color = const Color(0xffded1ac)
          ..strokeWidth = 2,
      );
    }
    for (final x in [.25, .5, .75]) {
      for (final y in [r.top, r.bottom]) {
        c.drawRect(
          Rect.fromCenter(
            center: Offset(r.left + r.width * x, y),
            width: 6,
            height: 4,
          ),
          Paint()..color = const Color(0xff292a2c),
        );
      }
    }
    if (state.hull > .25) {
      c.drawLine(
        r.center - const Offset(12, 6),
        r.center + const Offset(8, 8),
        Paint()
          ..color = Colors.black54
          ..strokeWidth = 3,
      );
    }
    for (var i = 0; i < 3; i++) {
      if (state.smoke > 0) {
        c.drawCircle(
          r.center + Offset(i * 5 - 5, -6 - i * 3),
          4 + i * 2,
          Paint()..color = Colors.grey.withValues(alpha: state.smoke * .6),
        );
      }
    }
  }

  // Five slightly different colors for indices 0-4 so a viewer can pick
  // the ship's officers out from ordinary crew at a glance. Index 0 keeps
  // its existing gold captain ring; the other four are new. These are the
  // SAME representative dots used everywhere else (idle and combat) --
  // no separate officer entities or data model, just a color lookup by
  // index, matching "use the same actual crew through normal operation
  // and combat" rather than a fake dedicated combat roster.
  static const _officerColors = [
    Color(0xffffd37a), // captain (unchanged)
    Color(0xffb79bff), // quartermaster
    Color(0xff7ec8ff), // bosun
    Color(0xffef9c6a), // carpenter
    Color(0xff8ef58a), // navigator
  ];

  void _crew(
    Canvas c,
    Rect home,
    Rect? enemy,
    int count,
    double fraction,
    bool owned,
    double crossing,
    int planks,
    bool winner,
  ) {
    final living = (count * fraction).ceil().clamp(0, 20);
    final rows = count > 10 ? 3 : 2;
    final columns = (count / rows).ceil().clamp(1, 10);
    for (var i = 0; i < living; i++) {
      var p = Offset(
        home.left + home.width * (.12 + .72 * (i ~/ rows + .5) / columns),
        home.center.dy + ((i % rows) - (rows - 1) / 2) * home.height * .24,
      );
      final crossingNow = enemy != null && planks > 0 && i > 0 && i.isOdd;
      if (!crossingNow) {
        // Ordinary sailing/trading/exploring is still visually alive:
        // a small per-dot wander (own speed/phase from its index, so
        // dots don't move in lockstep) around its work position --
        // believable ambient activity, not a real position/pathing
        // simulation. Also runs during pre-boarding combat phases
        // (encounter/maneuver/cannon), where crew are at their posts.
        final phase = i * 1.9;
        final speed = .3 + (i % 4) * .07;
        p = p.translate(
          math.sin(seconds * speed + phase) * home.width * .06,
          math.cos(seconds * speed * .8 + phase * 1.4) * home.height * .12,
        );
      }
      if (crossingNow) {
        final laneIndex = i % planks;
        final lane = DeckGeometry.stations(planks)[laneIndex];
        // Multiple crew sharing one lane (the common case: most hulls
        // have only 1-2 planks) must not perfectly overlap or collapse
        // into a single dot once aboard -- a small deterministic
        // per-dot jitter spreads them within the lane, and a per-dot
        // progress delay staggers the crossing itself so they visibly
        // queue/spread rather than teleporting together in lockstep.
        final jitter = (((i * 37) % 11) - 5) / 5.0 * .12;
        final rank = i ~/ planks;
        final personalDelay = (rank % 4) * .05;
        final bridge = Offset(
          home.center.dx + (lane + jitter) * home.width,
          (home.center.dy + enemy.center.dy) / 2,
        );
        final target = Offset(
          enemy.center.dx + (lane + jitter) * enemy.width,
          enemy.center.dy + ((rank % 3) - 1) * enemy.height * .18,
        );
        final personalCrossing = (crossing - personalDelay).clamp(0.0, 1.0);
        final t = winner ? personalCrossing : math.min(personalCrossing, .55);
        p = t < .5
            ? Offset.lerp(p, bridge, t * 2)!
            : Offset.lerp(bridge, target, (t - .5) * 2)!;
      }
      c.drawCircle(
        p,
        count > 7 ? 2.1 : 2.7,
        Paint()
          ..color = i < _officerColors.length
              ? _officerColors[i]
              : owned
              ? const Color(0xff84d8d1)
              : const Color(0xffe7a59b),
      );
      if (i == 0) {
        c.drawCircle(
          p,
          3.8,
          Paint()
            ..color = const Color(0xffffd37a)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .7,
        );
      }
    }
  }

  @override
  bool shouldRepaint(TheaterPainter old) =>
      old.masts != masts ||
      old.damage != damage ||
      old.script != script ||
      old.seconds != seconds ||
      old.crewA != crewA ||
      old.crewB != crewB;
}

/// Development fixture only; never connected to encounter detection or saves.
class TheaterPreview extends StatefulWidget {
  const TheaterPreview({super.key});
  @override
  State<TheaterPreview> createState() => _TheaterPreviewState();
}

class _TheaterPreviewState extends State<TheaterPreview>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 13),
  )..forward();
  BattleScript script = previewScript();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Material(
      color: const Color(0xff132c36),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final seconds = controller.value * script.duration;
            final sample = script.sample(seconds);
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Theater preview • scripted fixture'),
                  DeckTheater(masts: 3, script: script, seconds: seconds),
                  Text('${sample.phase.name} • ${seconds.toStringAsFixed(1)}s'),
                  if (sample.complete)
                    Text('Supplied ending: ${script.ending.name}'),
                  Slider(
                    value: controller.value,
                    onChanged: (v) {
                      controller.stop();
                      controller.value = v;
                    },
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => controller.forward(from: 0),
                        child: const Text('Replay'),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(
                            () => script = previewScript(
                              escape: script.ending != TheaterEnding.escaped,
                            ),
                          );
                          controller.forward(from: 0);
                        },
                        child: const Text('Boarding / escape'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}
