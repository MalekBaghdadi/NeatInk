import 'dart:math' as math;

import '../../../ink/ink_rect.dart';
import '../../../ink/vec2.dart';

/// Small pure-Dart geometry helpers shared by the editor tools.
///
/// The hot-path functions take plain doubles so eraser and lasso loops over
/// thousands of points don't allocate a `Vec2` per point.

/// Squared distance from point (px, py) to the segment (ax, ay)–(bx, by).
double distanceSquaredToSegmentXY(
    double px, double py, double ax, double ay, double bx, double by) {
  final abx = bx - ax, aby = by - ay;
  final len2 = abx * abx + aby * aby;
  var t = 0.0;
  if (len2 > 0) {
    t = ((px - ax) * abx + (py - ay) * aby) / len2;
    if (t < 0) {
      t = 0;
    } else if (t > 1) {
      t = 1;
    }
  }
  final dx = ax + abx * t - px, dy = ay + aby * t - py;
  return dx * dx + dy * dy;
}

/// Distance from [p] to the segment [a]–[b] (a point when `a == b`).
double distanceToSegment(Vec2 p, Vec2 a, Vec2 b) =>
    math.sqrt(distanceSquaredToSegmentXY(p.x, p.y, a.x, a.y, b.x, b.y));

/// Squared distance between segments (ax, ay)–(bx, by) and (cx, cy)–(dx, dy).
/// Zero when they cross. Either segment may be a single point.
double segmentDistanceSquaredXY(double ax, double ay, double bx, double by,
    double cx, double cy, double dx, double dy) {
  if (_segmentsCross(ax, ay, bx, by, cx, cy, dx, dy)) return 0;
  // Disjoint segments: the closest pair always involves an endpoint.
  return math.min(
    math.min(distanceSquaredToSegmentXY(ax, ay, cx, cy, dx, dy),
        distanceSquaredToSegmentXY(bx, by, cx, cy, dx, dy)),
    math.min(distanceSquaredToSegmentXY(cx, cy, ax, ay, bx, by),
        distanceSquaredToSegmentXY(dx, dy, ax, ay, bx, by)),
  );
}

/// Proper crossing test (endpoints strictly on opposite sides). Touching and
/// collinear cases are left to the endpoint distances, which are then ~0.
bool _segmentsCross(double ax, double ay, double bx, double by, double cx,
    double cy, double dx, double dy) {
  final d1 = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
  final d2 = (bx - ax) * (dy - ay) - (by - ay) * (dx - ax);
  final d3 = (dx - cx) * (ay - cy) - (dy - cy) * (ax - cx);
  final d4 = (dx - cx) * (by - cy) - (dy - cy) * (bx - cx);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

/// Bounding box of the area an eraser circle of [radius] covers while moving
/// from [from] to [to].
InkRect sweepBounds(Vec2 from, Vec2 to, double radius) => InkRect(
      math.min(from.x, to.x) - radius,
      math.min(from.y, to.y) - radius,
      math.max(from.x, to.x) + radius,
      math.max(from.y, to.y) + radius,
    );

/// The parameter interval `[t0, t1] ⊆ [0, 1]` of the segment `p0 → p1` that
/// lies inside the capsule of [radius] around the segment `a → b` (the area a
/// circle sweeps moving from `a` to `b`), or null when they don't overlap.
///
/// The capsule is convex, so its intersection with a segment is a single
/// interval. The capsule is the union of the two end discs and the
/// rectangle between them, so the interval is the hull of the three
/// sub-intervals, each of which is solved exactly.
(double, double)? segmentCapsuleInterval(
    Vec2 p0, Vec2 p1, Vec2 a, Vec2 b, double radius) {
  final dx = p1.x - p0.x, dy = p1.y - p0.y;
  var lo = double.infinity, hi = double.negativeInfinity;

  void include((double, double)? iv) {
    if (iv == null) return;
    if (iv.$1 < lo) lo = iv.$1;
    if (iv.$2 > hi) hi = iv.$2;
  }

  include(_discInterval(p0.x, p0.y, dx, dy, a.x, a.y, radius));
  final abx = b.x - a.x, aby = b.y - a.y;
  final len = math.sqrt(abx * abx + aby * aby);
  if (len > 0) {
    include(_discInterval(p0.x, p0.y, dx, dy, b.x, b.y, radius));
    include(_slabInterval(p0, dx, dy, a, abx / len, aby / len, len, radius));
  }
  if (lo > hi) return null;
  return (lo, hi);
}

/// `t ∈ [0, 1]` with `|p0 + t·d − c| ≤ r`: a quadratic inequality in t.
(double, double)? _discInterval(double p0x, double p0y, double dx, double dy,
    double cx, double cy, double r) {
  final fx = p0x - cx, fy = p0y - cy;
  final qa = dx * dx + dy * dy;
  final qc = fx * fx + fy * fy - r * r;
  if (qa == 0) return qc <= 0 ? (0.0, 1.0) : null;
  final qb = 2 * (fx * dx + fy * dy);
  final disc = qb * qb - 4 * qa * qc;
  if (disc < 0) return null;
  final sq = math.sqrt(disc);
  final t0 = math.max(0.0, (-qb - sq) / (2 * qa));
  final t1 = math.min(1.0, (-qb + sq) / (2 * qa));
  return t0 <= t1 ? (t0, t1) : null;
}

/// `t ∈ [0, 1]` inside the rectangle `0 ≤ along ≤ len`, `|across| ≤ r`
/// around the segment starting at [a] with unit direction (ux, uy)
/// (Liang–Barsky clipping against the four sides).
(double, double)? _slabInterval(Vec2 p0, double dx, double dy, Vec2 a,
    double ux, double uy, double len, double r) {
  final fx = p0.x - a.x, fy = p0.y - a.y;
  // along(t) = (f + t·d)·u must lie in [0, len];
  // across(t) = (f + t·d)·n must lie in [−r, r], with n = (−uy, ux).
  final along = _clip(fx * ux + fy * uy, dx * ux + dy * uy, 0, len, 0, 1);
  if (along == null) return null;
  return _clip(-fx * uy + fy * ux, -dx * uy + dy * ux, -r, r, along.$1,
      along.$2);
}

/// Narrows `[lo, hi]` to the t where `alpha + beta·t ∈ [min, max]`.
(double, double)? _clip(double alpha, double beta, double min, double max,
    double lo, double hi) {
  if (beta.abs() < 1e-12) {
    return alpha < min || alpha > max ? null : (lo, hi);
  }
  var t0 = (min - alpha) / beta, t1 = (max - alpha) / beta;
  if (t0 > t1) {
    final tmp = t0;
    t0 = t1;
    t1 = tmp;
  }
  final nlo = t0 > lo ? t0 : lo, nhi = t1 < hi ? t1 : hi;
  return nlo <= nhi ? (nlo, nhi) : null;
}

/// Even-odd point-in-polygon test. The polygon is implicitly closed.
bool pointInPolygon(double x, double y, List<Vec2> polygon) {
  var inside = false;
  final n = polygon.length;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    final xi = polygon[i].x, yi = polygon[i].y;
    final xj = polygon[j].x, yj = polygon[j].y;
    if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

/// Signed shoelace area of the implicitly closed polygon. With y pointing
/// down, a positive value means the points go clockwise on screen.
double signedPolygonArea(List<Vec2> polygon) {
  var sum = 0.0;
  final n = polygon.length;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    sum += polygon[j].x * polygon[i].y - polygon[i].x * polygon[j].y;
  }
  return sum / 2;
}

/// Total length of the open polyline through [points].
double polylineLength(List<Vec2> points) {
  var sum = 0.0;
  for (var i = 1; i < points.length; i++) {
    sum += points[i - 1].distanceTo(points[i]);
  }
  return sum;
}

/// Cumulative arc length at each point (first entry 0).
List<double> cumulativeLengths(List<Vec2> points) {
  final out = List<double>.filled(points.length, 0);
  for (var i = 1; i < points.length; i++) {
    out[i] = out[i - 1] + points[i - 1].distanceTo(points[i]);
  }
  return out;
}

/// Resamples the polyline to points [spacing] apart along its length. The
/// first and last points are kept; the last gap may be shorter.
List<Vec2> resamplePolyline(List<Vec2> points, double spacing) {
  if (points.length < 2 || spacing <= 0) return List.of(points);
  final out = <Vec2>[points.first];
  var carry = 0.0; // distance travelled since the last emitted point
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1], b = points[i];
    final seg = a.distanceTo(b);
    if (seg == 0) continue;
    var along = spacing - carry; // distance into this segment of the next sample
    while (along <= seg) {
      out.add(a.lerp(b, along / seg));
      along += spacing;
    }
    carry = seg - (along - spacing);
  }
  // End exactly on the last point; fold a sliver of a final gap into the
  // previous sample instead of emitting a near-duplicate.
  if (out.length > 1 &&
      out.last.distanceTo(points.last) < spacing * 1e-3) {
    out[out.length - 1] = points.last;
  } else if (out.last != points.last) {
    out.add(points.last);
  }
  return out;
}

/// Splits each segment of the polyline through [vertices] into pieces of at
/// most about [spacing], keeping every vertex exactly.
List<Vec2> densifyPolyline(List<Vec2> vertices, double spacing) {
  if (vertices.isEmpty) return const [];
  final out = <Vec2>[vertices.first];
  for (var i = 1; i < vertices.length; i++) {
    final a = vertices[i - 1], b = vertices[i];
    final n = math.max(1, (a.distanceTo(b) / spacing).round());
    for (var k = 1; k < n; k++) {
      out.add(a.lerp(b, k / n));
    }
    out.add(b);
  }
  return out;
}

/// Signed angle in radians from direction [u] to direction [v], in (−π, π].
/// Positive means clockwise on screen (y down).
double signedAngleBetween(Vec2 u, Vec2 v) =>
    math.atan2(u.cross(v), u.dot(v));

/// Unsigned angle in radians between directions [u] and [v], in [0, π].
double angleBetween(Vec2 u, Vec2 v) => signedAngleBetween(u, v).abs();

/// Degrees → radians.
double degToRad(double degrees) => degrees * math.pi / 180;

/// Radians → degrees.
double radToDeg(double radians) => radians * 180 / math.pi;
