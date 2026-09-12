import 'dart:math';

class Point2 {
  final double x, y;
  const Point2(this.x, this.y);
  double distanceTo(Point2 other) =>
      sqrt(pow(x - other.x, 2) + pow(y - other.y, 2));
  Point2 toward(Point2 target, double distance) {
    final length = distanceTo(target);
    if (length <= distance || length == 0) return target;
    return Point2(
      x + (target.x - x) * distance / length,
      y + (target.y - y) * distance / length,
    );
  }
}
