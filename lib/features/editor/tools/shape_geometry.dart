import 'dart:math' as math;

import '../../../ink/ink_point.dart';
import '../../../ink/ink_rect.dart';
import '../../../ink/stroke.dart';
import '../../../ink/vec2.dart';
import 'geometry.dart';
import 'tool_config.dart';

/// Clean geometry for snapped shapes: outlines built from a few vertices,
/// turned into evenly spaced [InkPoint]s with constant pressure and
/// timestamps taken from the hand-drawn stroke.

/// A recognized (or built) shape: its kind and the generated points that
/// replace the stroke's `points` (its `raw` keeps the hand-drawn ink).
///
/// Closed shapes repeat their first point at the end.
class ShapeResult {
  ShapeResult(this.kind, List<InkPoint> points)
      : points = List.unmodifiable(points);

  final ShapeKind kind;
  final List<InkPoint> points;

  /// [stroke] snapped to this shape: same id and `raw`, new `points`, and
  /// `shape` set (shapes are never tidied).
  Stroke applyTo(Stroke stroke) =>
      stroke.copyWith(points: points, shape: kind);

  @override
  String toString() => 'ShapeResult(${kind.name}, ${points.length} points)';
}

/// Maps a position along a generated shape to a time, so the generated
/// points carry timestamps from the stroke they replace.
class StrokeTiming {
  /// Times interpolated by arc length along [points] (the hand-drawn ink):
  /// the point a fraction `f` along the shape gets the time at which the
  /// pen was a fraction `f` along its own path.
  factory StrokeTiming.fromPoints(List<InkPoint> points) {
    if (points.isEmpty) return StrokeTiming.linear(0, 0);
    final fractions = <double>[0];
    final times = <int>[points.first.t];
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      length += points[i - 1].pos.distanceTo(points[i].pos);
      fractions.add(length);
      times.add(math.max(points[i].t, times.last));
    }
    if (length <= 0) {
      return StrokeTiming.linear(points.first.t, times.last);
    }
    for (var i = 0; i < fractions.length; i++) {
      fractions[i] /= length;
    }
    return StrokeTiming._(fractions, times);
  }

  /// Times spread evenly from [t0] to [t1].
  StrokeTiming.linear(int t0, int t1)
      : _fractions = const [0, 1],
        _times = [t0, math.max(t0, t1)];

  StrokeTiming._(this._fractions, this._times);

  final List<double> _fractions;
  final List<int> _times;

  /// The time at [fraction] (0–1) of the way along.
  int timeAt(double fraction) {
    final f = fraction.clamp(0.0, 1.0);
    // Binary search for the last knot at or before f.
    var lo = 0, hi = _fractions.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_fractions[mid] <= f) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = _fractions[hi] - _fractions[lo];
    final k = span <= 0 ? 0.0 : (f - _fractions[lo]) / span;
    return (_times[lo] + (_times[hi] - _times[lo]) * k).round();
  }
}

/// Turns the polyline through [outline] into shape points: every vertex is
/// kept exactly and segments are split about [spacing] apart. Pressure is
/// constant and times follow [timing] by arc length. Positions are
/// quantized like captured ink so they survive a save/load round trip.
List<InkPoint> outlineToPoints(
  List<Vec2> outline,
  StrokeTiming timing, {
  required double spacing,
  required double pressure,
  bool densify = true,
}) {
  final pts = densify ? densifyPolyline(outline, spacing) : outline;
  final cum = cumulativeLengths(pts);
  final total = cum.isEmpty ? 0.0 : cum.last;
  return [
    for (var i = 0; i < pts.length; i++)
      InkPoint.quantized(pts[i].x, pts[i].y, pressure,
          timing.timeAt(total <= 0 ? 0 : cum[i] / total)),
  ];
}

/// The outline of an arrow: shaft from [tail] to [tip], then the two barbs
/// drawn tip → barb → tip → other barb (one continuous stroke).
///
/// Each barb has length [barbLength] and makes [barbAngle] (radians) with
/// the shaft. [firstBarbSide] picks which barb comes first: +1 for the one
/// clockwise (on screen) from the backward shaft direction, −1 for the
/// other.
List<Vec2> arrowOutline(Vec2 tail, Vec2 tip, double barbLength,
    double barbAngle, {int firstBarbSide = 1}) {
  final back = (tail - tip).normalized();
  final side = firstBarbSide >= 0 ? 1.0 : -1.0;
  final b1 = tip + back.rotate(side * barbAngle) * barbLength;
  final b2 = tip + back.rotate(-side * barbAngle) * barbLength;
  return [tail, tip, b1, tip, b2];
}

/// The closed outline through [corners], starting at `corners[start]` and
/// ending back on it.
List<Vec2> polygonOutline(List<Vec2> corners, {int start = 0}) {
  final n = corners.length;
  return [for (var k = 0; k <= n; k++) corners[(start + k) % n]];
}

/// The closed outline of the ellipse `center + R(theta)·(a cos t, b sin t)`
/// from parameter [t0] all the way round (increasing t when [clockwise],
/// which is clockwise on screen because y points down), resampled to
/// points about [spacing] apart. Ends back on its first point.
List<Vec2> ellipseOutline(Vec2 center, double a, double b, double theta,
    {double t0 = 0, bool clockwise = true, required double spacing}) {
  // Dense samples in the parameter, then even arc-length resampling.
  final perimeter = math.pi *
      (3 * (a + b) - math.sqrt((3 * a + b) * (a + 3 * b))); // Ramanujan
  final dense = math.max(64, (perimeter / spacing * 4).ceil());
  final dir = clockwise ? 1.0 : -1.0;
  final pts = <Vec2>[
    for (var i = 0; i <= dense; i++)
      center +
          Vec2(a * math.cos(t0 + dir * 2 * math.pi * i / dense),
                  b * math.sin(t0 + dir * 2 * math.pi * i / dense))
              .rotate(theta),
  ];
  pts[dense] = pts[0]; // close exactly
  final length = polylineLength(pts);
  final n = math.max(12, (length / spacing).round());
  return resamplePolyline(pts, length / n);
}

/// Builds a shape of [kind] from a drag between [from] and [to] (the shape
/// tool): lines and arrows go from [from] to [to]; rectangles, ellipses and
/// triangles fill the box the two points span (the triangle is isosceles
/// with its apex at the middle of the top edge). Times run linearly from
/// [t0] to [t1]. Returns null when the drag is too short to draw anything.
ShapeResult? buildShape(
  ShapeKind kind,
  Vec2 from,
  Vec2 to, {
  int t0 = 0,
  int t1 = 0,
  ToolConfig config = ToolConfig.defaults,
}) {
  if (!from.isFinite || !to.isFinite || from.distanceTo(to) < 1) return null;
  final timing = StrokeTiming.linear(t0, t1);
  final spacing = config.shapeOutputSpacingPt;
  final pressure = config.shapeOutputPressure;
  List<InkPoint> pointsOf(List<Vec2> outline) => outlineToPoints(
      outline, timing, spacing: spacing, pressure: pressure);
  final box = InkRect.fromPoints([from, to]);

  switch (kind) {
    case ShapeKind.line:
      return ShapeResult(kind, pointsOf([from, to]));
    case ShapeKind.arrow:
      final len = from.distanceTo(to);
      final barb = (len * config.arrowBuildBarbFraction)
          .clamp(config.arrowBuildMinBarbPt, config.arrowBuildMaxBarbPt);
      return ShapeResult(
          kind,
          pointsOf(arrowOutline(from, to, barb.toDouble(),
              degToRad(config.arrowBuildBarbAngleDeg))));
    case ShapeKind.rectangle:
      if (box.width < 1 || box.height < 1) return null;
      final corners = [
        box.topLeft,
        Vec2(box.right, box.top),
        box.bottomRight,
        Vec2(box.left, box.bottom),
      ];
      // Start at the corner the drag started from.
      var start = 0;
      for (var i = 1; i < 4; i++) {
        if (corners[i].distanceTo(from) < corners[start].distanceTo(from)) {
          start = i;
        }
      }
      return ShapeResult(kind, pointsOf(polygonOutline(corners, start: start)));
    case ShapeKind.ellipse:
      if (box.width < 1 || box.height < 1) return null;
      final outline = ellipseOutline(
          box.center, box.width / 2, box.height / 2, 0,
          t0: -math.pi / 2, spacing: spacing);
      return ShapeResult(
          kind,
          outlineToPoints(outline, timing,
              spacing: spacing, pressure: pressure, densify: false));
    case ShapeKind.triangle:
      if (box.width < 1 || box.height < 1) return null;
      final corners = [
        Vec2(box.center.x, box.top),
        box.bottomRight,
        Vec2(box.left, box.bottom),
      ];
      return ShapeResult(kind, pointsOf(polygonOutline(corners)));
  }
}
