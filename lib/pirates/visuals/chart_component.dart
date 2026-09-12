import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../core/simulation/simulation.dart' as core;
import '../../core/simulation/vessel.dart';

/// Static chart compiled once; coast geometry is supplied by the simulation.
class ChartComponent extends Component {
  final core.Simulation simulation;
  ui.Picture? _picture;
  double _labelScale = 1;
  ChartComponent(this.simulation);
  @override
  Future<void> onLoad() async {
    _record();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    final scale = math.min(size.x / 1024, size.y / 768);
    if (scale > 0) {
      final next = (.65 / scale).clamp(1.0, 1.8);
      if ((next - _labelScale).abs() > .01) {
        _labelScale = next;
        _record();
      }
    }
  }

  void _record() {
    _picture?.dispose();
    final recorder = ui.PictureRecorder();
    _draw(Canvas(recorder));
    _picture = recorder.endRecording();
  }

  @override
  void onRemove() {
    _picture?.dispose();
    _picture = null;
    super.onRemove();
  }

  @override
  void render(Canvas canvas) {
    if (_picture != null) canvas.drawPicture(_picture!);
  }

  void _text(
    Canvas canvas,
    String text,
    double x,
    double y, {
    double size = 16,
    bool centered = false,
    Color color = const Color(0xfff2dfb2),
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size * ((size >= 16 && size <= 18) ? _labelScale : 1.0),
          fontFamily: 'serif',
          letterSpacing: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 910);
    final left = (centered ? x - painter.width / 2 : x).clamp(
      24.0,
      math.max(24.0, 936 - painter.width),
    );
    painter.paint(
      canvas,
      Offset(
        left.toDouble(),
        y.clamp(16.0, math.max(16.0, 704 - painter.height)),
      ),
    );
    painter.dispose();
  }

  void _draw(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 960, 720),
      Paint()..color = const Color(0xff174c60),
    );
    final ink = Paint()
      ..color = const Color(0xff326879)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    // Chart grid and restrained rhumb lines, recorded once rather than rebuilt per frame.
    for (var x = 40.0; x < 960; x += 80) {
      canvas.drawLine(Offset(x, 16), Offset(x, 704), ink);
    }
    for (var y = 40.0; y < 720; y += 80) {
      canvas.drawLine(Offset(16, y), Offset(944, y), ink);
    }
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      canvas.drawLine(
        const Offset(840, 620),
        Offset(840 + 1200 * math.cos(a), 620 + 1200 * math.sin(a)),
        Paint()
          ..color = const Color(0x183fc4c6)
          ..strokeWidth = 1,
      );
    }
    final rng = math.Random(91);
    for (var i = 0; i < 500; i++) {
      final x = rng.nextDouble() * 960, y = rng.nextDouble() * 720;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + 2 + rng.nextDouble() * 4, y),
        Paint()..color = const Color(0x154ac2c2),
      );
    }
    for (var y = 90.0; y < 700; y += 85) {
      for (var x = 45.0; x < 940; x += 115) {
        canvas.drawArc(Rect.fromLTWH(x, y, 20, 5), 0, math.pi, false, ink);
        canvas.drawArc(
          Rect.fromLTWH(x + 10, y + 8, 20, 5),
          0,
          math.pi,
          false,
          ink,
        );
      }
    }
    for (final land in simulation.navigation.land) {
      final width = land.right - land.left, height = land.bottom - land.top;
      final points = [
        const Offset(.02, .4),
        const Offset(.16, .08),
        const Offset(.35, .15),
        const Offset(.5, .02),
        const Offset(.74, .18),
        const Offset(.88, .12),
        const Offset(.99, .44),
        const Offset(.91, .7),
        const Offset(.7, .8),
        const Offset(.6, .98),
        const Offset(.32, .88),
        const Offset(.17, .97),
        const Offset(.04, .7),
      ];
      final coast = Path();
      for (var i = 0; i < points.length; i++) {
        final x = land.left + points[i].dx * width,
            y = land.top + points[i].dy * height;
        if (i == 0) {
          coast.moveTo(x, y);
        } else {
          coast.lineTo(x, y);
        }
      }
      coast.close();
      canvas.drawPath(
        coast,
        Paint()
          ..color = const Color(0xff237e88)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 26
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        coast,
        Paint()
          ..color = const Color(0xff3c9996)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 13
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(coast, Paint()..color = const Color(0xffd8be7e));
      canvas.save();
      canvas.clipPath(coast);
      canvas.drawOval(
        Rect.fromLTWH(land.left + 11, land.top + 9, width - 26, height - 22),
        Paint()..color = const Color(0xff628568),
      );
      for (var i = 0; i < 4; i++) {
        final x = land.left + 23 + i * 15, y = land.top + 18 + (i % 2) * 9;
        canvas.drawPath(
          Path()
            ..moveTo(x - 6, y + 7)
            ..lineTo(x, y - 6)
            ..lineTo(x + 8, y + 7)
            ..close(),
          Paint()..color = const Color(0xff426e59),
        );
      }
      canvas.restore();
      canvas.drawPath(
        coast,
        Paint()
          ..color = const Color(0xffebd39b)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    for (final place in simulation.places) {
      final p = Offset(place.position.x, place.position.y);
      if (place.kind == DestinationKind.port) {
        if (place.id == 'tortuga') {
          canvas.drawLine(
            p + const Offset(15, -35),
            p + const Offset(15, -65),
            Paint()
              ..color = const Color(0xffb93838)
              ..strokeWidth = 2,
          );
          canvas.drawPath(
            Path()
              ..moveTo(p.dx + 15, p.dy - 65)
              ..lineTo(p.dx + 34, p.dy - 57)
              ..lineTo(p.dx + 15, p.dy - 49)
              ..close(),
            Paint()..color = const Color(0xffb93838),
          );
        }
        // Harbor town on land and a pier ending before the open-water berth.
        for (var i = 0; i < 3; i++) {
          final x = p.dx - 24 + i * 12, y = p.dy - 37 - (i % 2) * 4;
          canvas.drawRect(
            Rect.fromLTWH(x, y, 9, 10),
            Paint()..color = const Color(0xffefe0b2),
          );
          canvas.drawPath(
            Path()
              ..moveTo(x - 1, y)
              ..lineTo(x + 4.5, y - 5)
              ..lineTo(x + 10, y)
              ..close(),
            Paint()..color = const Color(0xff995b41),
          );
        }
        canvas.drawLine(
          p + const Offset(0, -25),
          p + const Offset(0, -7),
          Paint()
            ..color = const Color(0xffab814e)
            ..strokeWidth = 5,
        );
        canvas.drawLine(
          p + const Offset(-9, -7),
          p + const Offset(9, -7),
          Paint()
            ..color = const Color(0xffe7c282)
            ..strokeWidth = 3,
        );
        canvas.drawCircle(
          p,
          7,
          Paint()
            ..color = const Color(0xffe7c282)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        _text(
          canvas,
          place.id == 'marrow' ? 'St. Marrow' : place.name,
          p.dx,
          p.dy + 27,
          size: 18,
          centered: true,
        );
      } else {
        final pen = Paint()
          ..color = const Color(0xffbbd4ca)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawPath(
          Path()
            ..moveTo(p.dx, p.dy - 7)
            ..lineTo(p.dx + 6, p.dy)
            ..lineTo(p.dx, p.dy + 7)
            ..lineTo(p.dx - 6, p.dy)
            ..close(),
          pen,
        );
        _text(
          canvas,
          place.name,
          p.dx,
          p.dy + 23,
          size: 16,
          centered: true,
          color: const Color(0xffb4d0c6),
        );
      }
    }
    // Printed compass rose and sea-chart furniture, not interactive controls.
    const center = Offset(840, 620);
    canvas.drawCircle(
      center,
      38,
      Paint()
        ..color = const Color(0xffa9bba9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    for (var i = 0; i < 8; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(i * math.pi / 4);
      canvas.drawPath(
        Path()
          ..moveTo(0, -(i.isEven ? 49.0 : 29.0))
          ..lineTo(7, 0)
          ..lineTo(0, 6)
          ..lineTo(-7, 0)
          ..close(),
        Paint()
          ..color = i.isEven
              ? const Color(0xffdfcc9a)
              : const Color(0xff688c8c),
      );
      canvas.restore();
    }
    _text(canvas, 'N', 833, 550, size: 17);
    _text(canvas, 'THE WINDWARD REACH', 30, 23, size: 21);
    _text(
      canvas,
      'Caribbean waters',
      31,
      51,
      size: 13,
      color: const Color(0xffb0c4b6),
    );
    _text(
      canvas,
      'PORTS  •  REEFS  •  OPEN SEA',
      30,
      675,
      size: 12,
      color: const Color(0xffadbfaf),
    );
    canvas.drawRect(
      const Rect.fromLTWH(12, 12, 936, 696),
      Paint()
        ..color = const Color(0xffb8b88e)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
}
