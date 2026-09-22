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

  /// Boarding presentation pass 2026-09-21: deterministic occupancy-aware
  /// lane assignment for crossing dot [i] out of up to [planks]
  /// simultaneous lanes -- round-robins across every lane and staggers
  /// each dot's crossing start by its position in that lane's own queue,
  /// so a congested lane visibly sends dots across one at a time instead
  /// of several dots stacking on the identical path at the identical
  /// instant. A top-level pure function (not a TheaterPainter method)
  /// specifically so it's directly unit-testable -- see
  /// test/ship_combat_overhaul_test.dart.
  ///
  /// [i] is a DOT index, not a crossing-order index -- only ODD dot
  /// indices actually cross (see DeckTheater's own boarding-party rule:
  /// half the crew crosses, half holds the home deck). Reindexing by
  /// `(i - 1) ~/ 2` before taking the lane modulus is required, not
  /// cosmetic: `i % planks` alone, applied directly to odd `i`, only
  /// ever lands on ODD-numbered lanes whenever [planks] is even (every
  /// odd number mod an even number is itself odd) -- e.g. every 2-plank
  /// hull matchup (Brig, Frigate, Cog, Fluyt, Knarr, Corbita...) would
  /// permanently leave lane 0 completely unused, exactly the "occupancy
  /// -aware" property this function exists to guarantee.
  static ({int index, double queueDelay}) laneAssignment(int i, int planks) {
    final crossingOrder = (i - 1) ~/ 2;
    final lane = crossingOrder % planks;
    final queuePosition = crossingOrder ~/ planks;
    return (index: lane, queueDelay: (queuePosition % 4) * .05);
  }
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
    // Boarding presentation pass 2026-09-21: a visible water backdrop so
    // "outside the deck" reads as impassable water rather than empty
    // background -- the same topology _crew's movement rules already
    // enforce (dots never actually render outside a deck rect or the
    // plank bridge between them), now visually legible too. A few faint
    // animated ripple lines, not a new rendering subsystem.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff0d3440),
    );
    for (var i = 0; i < 4; i++) {
      final y = size.height * (.15 + i * .23);
      final phase = seconds * .4 + i * 1.7;
      final path = Path()..moveTo(0, y);
      for (double x = 0; x <= size.width; x += size.width / 12) {
        path.lineTo(x, y + math.sin(x / size.width * 6 + phase) * 2.5);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xff1c5568).withValues(alpha: .55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
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
        final from = Offset(a.center.dx + x * a.width, a.bottom);
        final to = Offset(b.center.dx + x * b.width, b.top);
        // Boarding presentation pass 2026-09-21: a real plank/gangway
        // read (a board with rails and cross-slats), not a single thin
        // line -- reusing the same wood palette _ship already paints its
        // own deck planking with (0xff806047 base / 0xffac895d grain /
        // 0xffd9bb84 highlight), so the crossing visually belongs to the
        // same material as the decks it connects.
        final normal = (to - from);
        final length = normal.distance;
        final perp = length == 0
            ? const Offset(1, 0)
            : Offset(-normal.dy, normal.dx) / length;
        final boardWidth = 6.0;
        canvas.drawLine(
          from - perp * boardWidth,
          to - perp * boardWidth,
          Paint()
            ..color = const Color(0xff6b4f37)
            ..strokeWidth = 2,
        );
        canvas.drawLine(
          from + perp * boardWidth,
          to + perp * boardWidth,
          Paint()
            ..color = const Color(0xff6b4f37)
            ..strokeWidth = 2,
        );
        canvas.drawLine(
          from,
          to,
          Paint()
            ..color = const Color(0xffd9bb84)
            ..strokeWidth = boardWidth * 2,
        );
        final slats = math.max(2, (length / 10).round());
        for (var s = 1; s < slats; s++) {
          final t = s / slats;
          final centerPoint = Offset.lerp(from, to, t)!;
          canvas.drawLine(
            centerPoint - perp * boardWidth,
            centerPoint + perp * boardWidth,
            Paint()
              ..color = const Color(0xffac895d)
              ..strokeWidth = 1.2,
          );
        }
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
      crewB,
      sample?.opponentDamage.crewFraction ?? 1,
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
        crewA,
        da.crewFraction,
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
    // Boarding presentation pass 2026-09-21: was a single faint 0.6px
    // stroke per seam, easy to read as a flat brown rectangle at normal
    // mobile scale. Alternating subtle shade bands BETWEEN seams (clipped
    // to the actual deck silhouette, including the angled bow) give each
    // strip a real "individual plank" read; the seam lines themselves are
    // thicker and darker so they stay visible over the hull-damage tint.
    c.save();
    c.clipPath(deck);
    var board = 0;
    for (var x = r.left; x < r.right; x += 16) {
      if (board.isOdd) {
        c.drawRect(
          Rect.fromLTRB(x, r.top, x + 16, r.bottom),
          Paint()..color = Colors.black.withValues(alpha: .06),
        );
      }
      board++;
    }
    c.restore();
    for (var x = r.left + 12; x < r.right - 12; x += 16) {
      c.drawLine(
        Offset(x, r.top + 2),
        Offset(x, r.bottom - 2),
        Paint()
          ..color = const Color(0xff5c4530)
          ..strokeWidth = 1,
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

  // Boarding presentation pass 2026-09-21: deck topology and combat-dot
  // behavior, entirely presentation-side (see this file's own doc
  // comment: no Flutter/voyage/RNG/damage here -- BattleScript already
  // determined the real outcome before a single dot moves). The rule
  // set below mirrors the design brief almost verbatim:
  //   - a combat-capable dot with a reachable enemy seeks it, rather
  //     than idling/wandering while one exists (both attacker AND
  //     defender sides -- previously only attackers ever reacted to an
  //     active boarding; defenders kept doing the ordinary ambient
  //     wander throughout, which is exactly the "wanders around during
  //     active combat" bug).
  //   - "water" (outside the deck rects and the plank bridge between
  //     them) is never a valid position -- every branch below computes
  //     `p` as a point ON one of the two deck rects or an explicit lerp
  //     between deck-edge points, never an unconstrained offset; the
  //     idle wander is the only place that could drift outside its own
  //     deck, so it's now hard-clamped back into `home`.
  //   - planks are the only crossing: a dot only ever leaves its own
  //     deck via a lane index into DeckGeometry.stations(planks).
  //   - occupancy: lane ASSIGNMENT (see DeckGeometry.laneAssignment) spreads crossing
  //     dots round-robin across every available lane instead of index
  //     parity alone, and QUEUE POSITION within a lane (not just a
  //     flat per-dot delay) staggers when each dot actually starts
  //     crossing, so a busy lane visibly queues rather than stacking
  //     several dots on the identical path at the identical instant.
  //   - retargeting: an attacker's destination slot tracks the
  //     opposing side's CURRENT living count, so as defenders fall the
  //     remaining attackers converge on the defenders that are still
  //     actually there instead of a fixed, possibly-already-empty spot.
  void _crew(
    Canvas c,
    Rect home,
    Rect? enemy,
    int count,
    double fraction,
    int enemyCount,
    double enemyFraction,
    bool owned,
    double crossing,
    int planks,
    bool winner,
  ) {
    final living = (count * fraction).ceil().clamp(0, 20);
    final enemyLiving = (enemyCount * enemyFraction).ceil().clamp(0, 20);
    final rows = count > 10 ? 3 : 2;
    final columns = (count / rows).ceil().clamp(1, 10);
    Offset post(int i) => Offset(
      home.left + home.width * (.12 + .72 * (i ~/ rows + .5) / columns),
      home.center.dy + ((i % rows) - (rows - 1) / 2) * home.height * .24,
    );
    for (var i = 0; i < living; i++) {
      var p = post(i);
      final boardingActive = enemy != null && planks > 0;
      // Half the crew (odd indices) form the boarding party -- the rest
      // hold the home deck. A defender never crosses; it instead reacts
      // in place (see the defend branch below) once boarded.
      final crossingNow = boardingActive && i > 0 && i.isOdd;
      final defendingNow = boardingActive && !crossingNow && enemyLiving > 0;
      if (!crossingNow && !defendingNow) {
        // Ordinary sailing/trading/exploring, or a boarding this side has
        // already won (no living enemy left to react to): still visually
        // alive via a small per-dot wander (own speed/phase from its
        // index, so dots don't move in lockstep) around its work
        // position -- believable ambient activity, not a real position/
        // pathing simulation. Hard-clamped to `home` so the wander can
        // never visually drift past the deck's own edge into open water.
        final phase = i * 1.9;
        final speed = .3 + (i % 4) * .07;
        p = p.translate(
          math.sin(seconds * speed + phase) * home.width * .06,
          math.cos(seconds * speed * .8 + phase * 1.4) * home.height * .12,
        );
        p = Offset(
          p.dx.clamp(home.left, home.right),
          p.dy.clamp(home.top, home.bottom),
        );
      } else if (crossingNow) {
        final lane = DeckGeometry.laneAssignment(i, planks);
        final laneOffset = DeckGeometry.stations(planks)[lane.index];
        // Multiple crew sharing one lane (the common case: most hulls
        // have only 1-2 planks) must not perfectly overlap -- a small
        // deterministic per-dot jitter spreads them within the lane.
        final jitter = (((i * 37) % 11) - 5) / 5.0 * .12;
        final bridge = Offset(
          home.center.dx + (laneOffset + jitter) * home.width,
          (home.center.dy + enemy.center.dy) / 2,
        );
        // Retarget onto whichever defender slot is still actually
        // living, cycling among only the currently-living slots rather
        // than a fixed assignment that could aim at an already-empty
        // position.
        final targetSlot = enemyLiving > 0 ? i % enemyLiving : 0;
        final target = Offset(
          enemy.center.dx + (laneOffset + jitter) * enemy.width,
          enemy.center.dy + ((targetSlot % 3) - 1) * enemy.height * .18,
        );
        // lane.queueDelay staggers crossing START by queue position
        // within this specific lane (occupancy: a lane with several
        // dots queued visibly sends them across one at a time, not
        // simultaneously), on top of the existing per-rank delay.
        final personalCrossing = (crossing - lane.queueDelay).clamp(0.0, 1.0);
        final t = winner ? personalCrossing : math.min(personalCrossing, .55);
        p = t < .5
            ? Offset.lerp(p, bridge, t * 2)!
            : Offset.lerp(bridge, target, (t - .5) * 2)!;
      } else {
        // Defending: hold post but turn to face/lean toward the nearest
        // active plank lane -- a real, if small, reaction to "enemies
        // are the objective," instead of continuing the idle wander
        // while genuinely under boarding.
        final nearestLane = DeckGeometry.stations(planks).reduce(
          (a, b) => (a - (i.isEven ? -.1 : .1)).abs() < (b - (i.isEven ? -.1 : .1)).abs() ? a : b,
        );
        p = p.translate(
          nearestLane * home.width * .18,
          math.sin(seconds * 1.4 + i) * home.height * .04,
        );
        p = Offset(
          p.dx.clamp(home.left, home.right),
          p.dy.clamp(home.top, home.bottom),
        );
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
