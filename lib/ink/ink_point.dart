import 'affine2.dart';
import 'vec2.dart';

/// One sampled pen point in page coordinates.
///
/// Stored in JSON as `[x, y, pressure, tMillis]`.
class InkPoint {
  const InkPoint(this.x, this.y, this.pressure, this.t);

  /// Creates a point rounded to the precision we persist (0.01 pt for
  /// position, 0.001 for pressure). Use this at capture time so a stroke's
  /// `raw` points survive a save/load round trip unchanged.
  factory InkPoint.quantized(double x, double y, double pressure, int t) =>
      InkPoint(_q(x, 100), _q(y, 100), _q(pressure.clamp(0.0, 1.0), 1000), t);

  factory InkPoint.fromJson(List<dynamic> j) => InkPoint(
        (j[0] as num).toDouble(),
        (j[1] as num).toDouble(),
        j.length > 2 ? (j[2] as num).toDouble() : 0.5,
        j.length > 3 ? (j[3] as num).toInt() : 0,
      );

  final double x;
  final double y;

  /// Normalized pressure in [0, 1]. 0.5 when the device reports none.
  final double pressure;

  /// Milliseconds since the stroke started (or any monotonic origin). The
  /// tidy feature uses timing, so every point carries one.
  final int t;

  Vec2 get pos => Vec2(x, y);

  bool get isFinite => x.isFinite && y.isFinite && pressure.isFinite;

  InkPoint withPos(double nx, double ny) => InkPoint(nx, ny, pressure, t);

  InkPoint transformed(Affine2 m) =>
      InkPoint(m.applyX(x, y), m.applyY(x, y), pressure, t);

  /// Linear interpolation of position and pressure; keeps this point's time.
  InkPoint lerp(InkPoint o, double k) => InkPoint(x + (o.x - x) * k,
      y + (o.y - y) * k, pressure + (o.pressure - pressure) * k, t);

  List<num> toJson() => [_q(x, 100), _q(y, 100), _q(pressure, 1000), t];

  static double _q(double v, int scale) => (v * scale).roundToDouble() / scale;

  @override
  bool operator ==(Object other) =>
      other is InkPoint &&
      other.x == x &&
      other.y == y &&
      other.pressure == pressure &&
      other.t == t;

  @override
  int get hashCode => Object.hash(x, y, pressure, t);

  @override
  String toString() => 'InkPoint($x, $y, p=$pressure, t=$t)';
}
