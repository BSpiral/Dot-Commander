import 'dart:math' as math;
import 'chart_component.dart';
import '../ships/hull_catalog.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart' hide Simulation;
import '../../core/simulation/simulation.dart';
import '../../core/simulation/vessel.dart';

class PiratesGame extends FlameGame {
  final Simulation simulation;
  final void Function(Vessel) onSelected;
  String selectedId;
  double fps = 0, locateRemaining = 0;
  double _accumulator = 0;
  double shipScale = 1;
  final _rendered = <String>{};
  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    final pixelScale = math.min(size.x / 1024, size.y / 768);
    if (pixelScale > 0) shipScale = (.42 / pixelScale).clamp(1.0, 1.65);
  }

  PiratesGame(this.simulation, this.onSelected)
    : selectedId = simulation.ships.first.id,
      super(
        camera: CameraComponent.withFixedResolution(width: 1024, height: 768),
      );
  void locate(Vessel ship) {
    selectedId = ship.id;
    locateRemaining = 2;
  }

  @override
  Color backgroundColor() => const Color(0xff092b3b);
  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;
    camera.viewfinder.position = Vector2(-32, -24);
    world.add(ChartComponent(simulation));
    for (final ship in simulation.ships) {
      world.add(ShipComponent(ship, this));
      _rendered.add(ship.id);
    }
  }

  @override
  void update(double dt) {
    final ids = simulation.ships.map((s) => s.id).toSet();
    for (final component
        in world.children.whereType<ShipComponent>().toList()) {
      if (!ids.contains(component.ship.id)) {
        component.removeFromParent();
        _rendered.remove(component.ship.id);
      }
    }
    for (final ship in simulation.ships) {
      if (_rendered.add(ship.id)) world.add(ShipComponent(ship, this));
    }
    locateRemaining = math.max(0, locateRemaining - dt);
    if (dt > 0) fps = fps == 0 ? 1 / dt : fps * .95 + .05 / dt;
    _accumulator += dt.clamp(0, .1);
    while (_accumulator >= 1 / 60) {
      simulation.update(1 / 60);
      _accumulator -= 1 / 60;
    }
    super.update(dt);
  }
}

class ShipComponent extends PositionComponent with TapCallbacks {
  final Vessel ship;
  final PiratesGame chart;
  ShipComponent(this.ship, this.chart)
    : super(size: Vector2(48, 48), anchor: Anchor.center);
  @override
  void update(double dt) {
    super.update(dt);
    position.setValues(ship.position.x, ship.position.y);
    scale.setAll(chart.shipScale);
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (!ship.atSea) return;
    chart.locate(ship);
    chart.onSelected(ship);
  }

  @override
  void render(Canvas canvas) {
    if (!ship.atSea) return;
    if (ship.activity == Activity.engaged) {
      final pen = Paint()
        ..color = const Color(0xffff9872)
        ..strokeWidth = 3;
      canvas.drawLine(const Offset(12, 8), const Offset(25, 20), pen);
      canvas.drawLine(const Offset(25, 8), const Offset(12, 20), pen);
    }
    if (ship.playerOwned) {
      canvas.drawCircle(
        const Offset(24, 24),
        20,
        Paint()..color = const Color(0x404be5df),
      );
    }
    if (ship.activity == Activity.docked) {
      final pen = Paint()
        ..color = const Color(0xfff2d996)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(const Offset(50, 17), 3, pen);
      canvas.drawLine(const Offset(50, 20), const Offset(50, 32), pen);
      canvas.drawLine(const Offset(44, 23), const Offset(56, 23), pen);
      canvas.drawArc(
        const Rect.fromLTWH(42, 22, 16, 12),
        0,
        math.pi,
        false,
        pen,
      );
    }
    if (chart.selectedId == ship.id) {
      canvas.drawCircle(
        const Offset(24, 24),
        24,
        Paint()
          ..color = const Color(0xfff9d885)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    canvas.save();
    canvas.translate(24, 24);
    canvas.rotate(ship.heading);
    final hullInfo = hullFor(ship.hullType);
    canvas.scale(hullInfo.visualScale);
    if (ship.activity == Activity.sailing) {
      final wake = Paint()
        ..color = const Color(0x997bd4d0)
        ..strokeWidth = 1.6;
      canvas.drawLine(const Offset(-21, -5), const Offset(-34, -10), wake);
      canvas.drawLine(const Offset(-21, 5), const Offset(-34, 10), wake);
    }
    final hull = Path()
      ..moveTo(21, 0)
      ..lineTo(9, -8)
      ..lineTo(-17, -7)
      ..lineTo(-21, 0)
      ..lineTo(-17, 7)
      ..lineTo(9, 8)
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xff241f25));
    canvas.drawPath(
      hull,
      Paint()
        ..color = ship.playerOwned
            ? const Color(0xffffd77d)
            : const Color(0xffc6ded9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.drawLine(
      const Offset(-17, 0),
      const Offset(17, 0),
      Paint()
        ..color = const Color(0xffd7b57d)
        ..strokeWidth = 2,
    );
    final sailPaint = Paint()
      ..color = ship.playerOwned
          ? const Color(0xffffe6a8)
          : const Color(0xffe1ece5);
    for (var mast = 0; mast < hullInfo.masts; mast++) {
      final x = hullInfo.masts == 1
          ? 2.0
          : -12.0 + 24 * mast / (hullInfo.masts - 1);
      canvas.drawPath(
        Path()
          ..moveTo(x, -12)
          ..lineTo(x + 8, 0)
          ..lineTo(x, 12)
          ..close(),
        sailPaint,
      );
    }
    final flag = switch (ship.behavior) {
      BehaviorMode.merchant => const Color(0xff74d6bd),
      BehaviorMode.pirate => const Color(0xffeb726a),
      BehaviorMode.explorer => const Color(0xffdeb6fa),
      BehaviorMode.privateer => const Color(0xff94c6ff),
    };
    canvas.drawRect(const Rect.fromLTWH(-18, -12, 8, 5), Paint()..color = flag);
    if (ship.hullType == 'Galley') {
      final oar = Paint()
        ..color = const Color(0xffc5b285)
        ..strokeWidth = 1.4;
      for (var x = -12.0; x < 15; x += 6) {
        canvas.drawLine(Offset(x, -7), Offset(x - 3, -15), oar);
        canvas.drawLine(Offset(x, 7), Offset(x - 3, 15), oar);
      }
    }
    canvas.restore();
    if (chart.selectedId == ship.id && chart.locateRemaining > 0) {
      canvas.drawCircle(
        const Offset(24, 24),
        28 + (2 - chart.locateRemaining) * 18,
        Paint()
          ..color = const Color(
            0xffffdf92,
          ).withValues(alpha: chart.locateRemaining / 2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }
}
