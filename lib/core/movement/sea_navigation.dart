import 'dart:math';
import 'point.dart';

/// Conservative coastline envelope. The visual land stays inside these bounds.
class LandRegion {
  final String id;
  final double left, top, right, bottom;
  const LandRegion(this.id, this.left, this.top, this.right, this.bottom);
  bool contains(Point2 p, [double clearance = 0]) =>
      p.x >= left - clearance &&
      p.x <= right + clearance &&
      p.y >= top - clearance &&
      p.y <= bottom + clearance;

  bool blocks(Point2 a, Point2 b, double clearance) {
    final l = left - clearance,
        r = right + clearance,
        t = top - clearance,
        bt = bottom + clearance;
    if (max(a.x, b.x) < l ||
        min(a.x, b.x) > r ||
        max(a.y, b.y) < t ||
        min(a.y, b.y) > bt) {
      return false;
    }
    var enter = 0.0, leave = 1.0;
    final dx = b.x - a.x, dy = b.y - a.y;
    if (dx.abs() < 1e-10) {
      if (a.x < l || a.x > r) return false;
    } else {
      final u = (l - a.x) / dx, v = (r - a.x) / dx;
      enter = max(enter, min(u, v));
      leave = min(leave, max(u, v));
      if (enter > leave) return false;
    }
    if (dy.abs() < 1e-10) {
      if (a.y < t || a.y > bt) return false;
    } else {
      final u = (t - a.y) / dy, v = (bt - a.y) / dy;
      enter = max(enter, min(u, v));
      leave = min(leave, max(u, v));
    }
    return enter <= leave;
  }
}

/// Small deterministic visibility graph, precomputed for static island corners.
/// No Flutter/Flame dependency. Empty routes mean unreachable, never sail through.
class SeaNavigation {
  final List<LandRegion> land;
  final double clearance;
  late final List<Point2> _corners;
  late final List<List<double>> _edges;
  SeaNavigation(List<LandRegion> land, {this.clearance = 10})
    : land = List.unmodifiable(land) {
    // Extra corner space keeps fixed-step rendered chords outside clearance.
    final margin = clearance + 2;
    _corners = [
      for (final r in land) ...[
        Point2(r.left - margin, r.top - margin),
        Point2(r.right + margin, r.top - margin),
        Point2(r.right + margin, r.bottom + margin),
        Point2(r.left - margin, r.bottom + margin),
      ],
    ].where(isWater).toList();
    _edges = List.generate(
      _corners.length,
      (i) => List.generate(
        _corners.length,
        (j) => clearSegment(_corners[i], _corners[j])
            ? _corners[i].distanceTo(_corners[j])
            : double.infinity,
      ),
    );
  }
  bool isWater(Point2 p) =>
      p.x.isFinite &&
      p.y.isFinite &&
      p.x >= 0 &&
      p.x <= 960 &&
      p.y >= 0 &&
      p.y <= 720 &&
      !land.any((r) => r.contains(p, clearance));
  bool clearSegment(Point2 a, Point2 b) =>
      isWater(a) && isWater(b) && !land.any((r) => r.blocks(a, b, clearance));

  List<Point2> route(Point2 start, Point2 goal) {
    if (!isWater(start) || !isWater(goal)) return [];
    if (clearSegment(start, goal)) return [goal];
    final nodes = [..._corners, start, goal];
    final source = nodes.length - 2, target = nodes.length - 1;
    final distance = List.filled(nodes.length, double.infinity)..[source] = 0;
    final previous = List.filled(nodes.length, -1);
    final visited = List.filled(nodes.length, false);
    for (var step = 0; step < nodes.length; step++) {
      var current = -1;
      for (var i = 0; i < nodes.length; i++) {
        if (!visited[i] && (current < 0 || distance[i] < distance[current])) {
          current = i;
        }
      }
      if (current < 0 || !distance[current].isFinite) return [];
      if (current == target) break;
      visited[current] = true;
      for (var i = 0; i < nodes.length; i++) {
        if (visited[i]) continue;
        final cost = current < _corners.length && i < _corners.length
            ? _edges[current][i]
            : clearSegment(nodes[current], nodes[i])
            ? nodes[current].distanceTo(nodes[i])
            : double.infinity;
        final candidate = distance[current] + cost;
        if (candidate < distance[i]) {
          distance[i] = candidate;
          previous[i] = current;
        }
      }
    }
    if (previous[target] < 0) return [];
    final path = <Point2>[];
    for (var i = target; i != source; i = previous[i]) {
      path.add(nodes[i]);
    }
    return path.reversed.toList();
  }
}
