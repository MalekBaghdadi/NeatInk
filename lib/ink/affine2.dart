import 'dart:math' as math;

import 'vec2.dart';

/// An immutable 2D affine transform:
///
///     x' = a·x + c·y + e
///     y' = b·x + d·y + f
///
/// This is the same `[a b c d e f]` layout as a PDF `cm` matrix and as
/// Flutter's `Matrix4` 2D subset, so it maps directly to both.
///
/// Composition: `p * q` means "apply `q` first, then `p`".
class Affine2 {
  const Affine2(this.a, this.b, this.c, this.d, this.e, this.f);

  static const Affine2 identity = Affine2(1, 0, 0, 1, 0, 0);

  factory Affine2.translation(double dx, double dy) =>
      Affine2(1, 0, 0, 1, dx, dy);

  /// Scale by ([sx], [sy]) around [pivot].
  factory Affine2.scaling(double sx, double sy, {Vec2 pivot = Vec2.zero}) =>
      Affine2(sx, 0, 0, sy, pivot.x - sx * pivot.x, pivot.y - sy * pivot.y);

  /// Rotate by [radians] around [pivot]. With y pointing down, a positive
  /// angle turns clockwise on screen.
  factory Affine2.rotation(double radians, {Vec2 pivot = Vec2.zero}) {
    final cs = math.cos(radians), sn = math.sin(radians);
    // R = T(p) · Rot · T(-p)
    return Affine2(cs, sn, -sn, cs, pivot.x - cs * pivot.x + sn * pivot.y,
        pivot.y - sn * pivot.x - cs * pivot.y);
  }

  /// Horizontal shear: `x' = x + k·(y − pivotY)`, `y' = y`.
  /// Points on the line `y = pivotY` do not move.
  factory Affine2.shearX(double k, {double pivotY = 0}) =>
      Affine2(1, 0, k, 1, -k * pivotY, 0);

  final double a, b, c, d, e, f;

  /// `this * other`: apply [other] first, then this.
  Affine2 operator *(Affine2 o) => Affine2(
        a * o.a + c * o.b,
        b * o.a + d * o.b,
        a * o.c + c * o.d,
        b * o.c + d * o.d,
        a * o.e + c * o.f + e,
        b * o.e + d * o.f + f,
      );

  /// Returns the transform that applies this and then [next].
  Affine2 then(Affine2 next) => next * this;

  Vec2 apply(Vec2 p) => Vec2(a * p.x + c * p.y + e, b * p.x + d * p.y + f);

  double applyX(double x, double y) => a * x + c * y + e;
  double applyY(double x, double y) => b * x + d * y + f;

  double get determinant => a * d - b * c;

  /// Average linear scale factor (geometric mean of the axis scales). Useful
  /// for scaling stroke widths along with geometry.
  double get meanScale => math.sqrt(determinant.abs());

  Affine2 inverted() {
    final det = determinant;
    if (det == 0) {
      throw StateError('Affine2 is not invertible');
    }
    final ia = d / det, ib = -b / det, ic = -c / det, id = a / det;
    return Affine2(ia, ib, ic, id, -(ia * e + ic * f), -(ib * e + id * f));
  }

  bool get isIdentity =>
      a == 1 && b == 0 && c == 0 && d == 1 && e == 0 && f == 0;

  List<double> toList() => [a, b, c, d, e, f];

  factory Affine2.fromList(List<num> v) => Affine2(v[0].toDouble(),
      v[1].toDouble(), v[2].toDouble(), v[3].toDouble(), v[4].toDouble(),
      v[5].toDouble());

  /// True when every coefficient is within [eps] of [o]'s.
  bool closeTo(Affine2 o, [double eps = 1e-9]) =>
      (a - o.a).abs() <= eps &&
      (b - o.b).abs() <= eps &&
      (c - o.c).abs() <= eps &&
      (d - o.d).abs() <= eps &&
      (e - o.e).abs() <= eps &&
      (f - o.f).abs() <= eps;

  @override
  bool operator ==(Object other) =>
      other is Affine2 &&
      other.a == a &&
      other.b == b &&
      other.c == c &&
      other.d == d &&
      other.e == e &&
      other.f == f;

  @override
  int get hashCode => Object.hash(a, b, c, d, e, f);

  @override
  String toString() => 'Affine2($a, $b, $c, $d, $e, $f)';
}
