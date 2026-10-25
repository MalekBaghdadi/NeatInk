import 'dart:math' as math;

/// An immutable 2D vector / point in page coordinates (PDF points, y down).
///
/// Pure Dart on purpose: `ink/` and `beautify/` must not depend on `dart:ui`.
class Vec2 {
  const Vec2(this.x, this.y);

  static const Vec2 zero = Vec2(0, 0);

  final double x;
  final double y;

  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(double k) => Vec2(x * k, y * k);
  Vec2 operator /(double k) => Vec2(x / k, y / k);
  Vec2 operator -() => Vec2(-x, -y);

  double dot(Vec2 o) => x * o.x + y * o.y;

  /// z component of the 3D cross product (positive = `o` is clockwise from
  /// this vector on screen, because y points down).
  double cross(Vec2 o) => x * o.y - y * o.x;

  double get lengthSquared => x * x + y * y;
  double get length => math.sqrt(lengthSquared);

  double distanceTo(Vec2 o) {
    final dx = x - o.x, dy = y - o.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  double distanceSquaredTo(Vec2 o) {
    final dx = x - o.x, dy = y - o.y;
    return dx * dx + dy * dy;
  }

  Vec2 normalized() {
    final l = length;
    return l == 0 ? Vec2.zero : Vec2(x / l, y / l);
  }

  /// Rotates by [radians]. With y pointing down, a positive angle turns
  /// clockwise on screen.
  Vec2 rotate(double radians) {
    final c = math.cos(radians), s = math.sin(radians);
    return Vec2(x * c - y * s, x * s + y * c);
  }

  Vec2 lerp(Vec2 o, double t) => Vec2(x + (o.x - x) * t, y + (o.y - y) * t);

  bool get isFinite => x.isFinite && y.isFinite;

  @override
  bool operator ==(Object other) =>
      other is Vec2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Vec2(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}
