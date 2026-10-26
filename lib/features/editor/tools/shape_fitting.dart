import 'dart:math' as math;

import '../../../ink/vec2.dart';
import 'geometry.dart';

/// Geometric fitting used by the shape recognizer: polyline simplification,
/// line fits and ellipse fits. Pure math on [Vec2] lists.

/// Douglas–Peucker simplification of the open polyline `pts[from..to]`.
///
/// Returns the indices of the kept points in order, always including [from]
/// and [to]. Every dropped point lies within [tolerance] of the segment
/// between the kept points around it.
List<int> douglasPeucker(List<Vec2> pts, double tolerance,
    {int from = 0, int? to}) {
  final last = to ?? pts.length - 1;
  if (last <= from) return [from];
  final keep = <int>{from, last};
  final stack = <(int, int)>[(from, last)];
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    if (b - a < 2) continue;
    final (index, dist) = farthestFromSegment(pts, a, b);
    if (dist > tolerance) {
      keep.add(index);
      stack
        ..add((a, index))
        ..add((index, b));
    }
  }
  return keep.toList()..sort();
}

/// Douglas–Peucker on the closed loop through [loop] (the last point joins
/// back to the first). Returns indices into [loop] in order, starting with 0.
///
/// The loop is split at the point farthest from `loop[0]` and each half is
/// simplified; index 0 is therefore always kept even when it is not a
/// corner, and callers remove it like any other low-turn vertex.
List<int> douglasPeuckerClosed(List<Vec2> loop, double tolerance) {
  final m = loop.length;
  if (m < 3) return [for (var i = 0; i < m; i++) i];
  var far = 1;
  var farD = -1.0;
  for (var i = 1; i < m; i++) {
    final d = loop[i].distanceSquaredTo(loop[0]);
    if (d > farD) {
      farD = d;
      far = i;
    }
  }
  // Close the loop by repeating the first point at index m.
  final closed = [...loop, loop[0]];
  final first = douglasPeucker(closed, tolerance, from: 0, to: far);
  final second = douglasPeucker(closed, tolerance, from: far, to: m);
  return [...first, ...second.skip(1).where((i) => i != m)];
}

/// The index in `(a, b)` of the point of [pts] farthest from the segment
/// `pts[a]`–`pts[b]`, and that distance. Returns `(a, 0)` when there is no
/// point in between.
(int, double) farthestFromSegment(List<Vec2> pts, int a, int b) {
  final p = pts[a], q = pts[b];
  var index = a;
  var best = 0.0;
  for (var i = a + 1; i < b; i++) {
    final r = pts[i];
    final d = distanceSquaredToSegmentXY(r.x, r.y, p.x, p.y, q.x, q.y);
    if (d > best) {
      best = d;
      index = i;
    }
  }
  return (index, math.sqrt(best));
}

/// Largest distance from the points of [loop] strictly between cyclic
/// indices [i] and [j] (walking forward from [i]) to the segment
/// `loop[i]`–`loop[j]`.
double cyclicDeviation(List<Vec2> loop, int i, int j) {
  final m = loop.length;
  final p = loop[i], q = loop[j];
  var best = 0.0;
  for (var k = (i + 1) % m; k != j; k = (k + 1) % m) {
    final r = loop[k];
    final d = distanceSquaredToSegmentXY(r.x, r.y, p.x, p.y, q.x, q.y);
    if (d > best) best = d;
  }
  return math.sqrt(best);
}

/// The points of [loop] from cyclic index [i] to [j] inclusive (walking
/// forward from [i]).
List<Vec2> cyclicRange(List<Vec2> loop, int i, int j) {
  final m = loop.length;
  final out = <Vec2>[loop[i]];
  for (var k = i; k != j;) {
    k = (k + 1) % m;
    out.add(loop[k]);
  }
  return out;
}

/// A straight line through [point] with unit direction [dir].
class LineFit {
  const LineFit(this.point, this.dir);

  final Vec2 point;
  final Vec2 dir;

  /// Signed distance of [p] from the line (positive on the clockwise side
  /// of [dir] on screen).
  double signedDistance(Vec2 p) => dir.cross(p - point);

  /// The foot of the perpendicular from [p].
  Vec2 project(Vec2 p) => point + dir * dir.dot(p - point);

  /// Where this line meets [o], or null when they are (nearly) parallel.
  Vec2? intersect(LineFit o) {
    final denom = dir.cross(o.dir);
    if (denom.abs() < 1e-6) return null;
    final t = (o.point - point).cross(o.dir) / denom;
    return point + dir * t;
  }
}

/// Total-least-squares line through [pts] (centroid plus principal axis),
/// or null for fewer than 2 distinct points.
LineFit? fitLine(List<Vec2> pts) {
  if (pts.length < 2) return null;
  var cx = 0.0, cy = 0.0;
  for (final p in pts) {
    cx += p.x;
    cy += p.y;
  }
  cx /= pts.length;
  cy /= pts.length;
  var sxx = 0.0, sxy = 0.0, syy = 0.0;
  for (final p in pts) {
    final dx = p.x - cx, dy = p.y - cy;
    sxx += dx * dx;
    sxy += dx * dy;
    syy += dy * dy;
  }
  if (sxx + syy < 1e-12) return null;
  // Principal axis of the 2×2 covariance matrix.
  final angle = 0.5 * math.atan2(2 * sxy, sxx - syy);
  return LineFit(Vec2(cx, cy), Vec2(math.cos(angle), math.sin(angle)));
}

/// [angle] (radians) snapped to the nearest multiple of [step] when within
/// [tolerance] of it; otherwise unchanged.
double snapAngle(double angle, double step, double tolerance) {
  final k = (angle / step).roundToDouble();
  final snapped = k * step;
  return (angle - snapped).abs() <= tolerance ? snapped : angle;
}

/// Sum of the signed turning angles (radians) along the polyline through
/// [pts]; with [closed], the turns at the joint back to the start count too.
/// Positive is clockwise on screen. A simple loop gives about ±2π.
double totalTurning(List<Vec2> pts, {bool closed = false}) {
  final n = pts.length;
  if (n < 3) return 0;
  var sum = 0.0;
  final count = closed ? n : n - 2;
  for (var k = 0; k < count; k++) {
    final a = pts[k % n], b = pts[(k + 1) % n], c = pts[(k + 2) % n];
    final u = b - a, v = c - b;
    if (u.lengthSquared == 0 || v.lengthSquared == 0) continue;
    sum += signedAngleBetween(u, v);
  }
  return sum;
}

/// An ellipse `centre + R(theta)·(a·cos t, b·sin t)` with `a ≥ b`.
class EllipseFit {
  const EllipseFit({
    required this.center,
    required this.a,
    required this.b,
    required this.theta,
    required this.meanError,
    required this.maxError,
    required this.maxAngularGap,
  });

  final Vec2 center;

  /// Semi-major and semi-minor axis lengths.
  final double a, b;

  /// Direction of the major axis (radians).
  final double theta;

  /// Mean and max of |normalized radius − 1| over the fitted points.
  final double meanError, maxError;

  /// Largest angle (radians) around the centre without any fitted point.
  final double maxAngularGap;

  /// Minor / major axis ratio (1 for a circle).
  double get axisRatio => a == 0 ? 0 : b / a;

  /// Ellipse parameter `t` of the point closest in angle to [p].
  double parameterOf(Vec2 p) {
    final d = (p - center).rotate(-theta);
    return math.atan2(d.y / b, d.x / a);
  }

  /// The point at parameter [t].
  Vec2 pointAt(double t) =>
      center + Vec2(a * math.cos(t), b * math.sin(t)).rotate(theta);
}

/// Fits an ellipse to the closed loop [pts] (roughly uniformly spaced, so
/// the centroid approximates the centre).
///
/// The axes' orientation comes from the second moments of the points; then,
/// in that rotated frame, `A·u² + B·v² + C·u + D·v = 1` is solved by linear
/// least squares, which also corrects the centre. Returns null when the
/// points don't describe an ellipse at all (degenerate or hyperbolic fit).
EllipseFit? fitEllipse(List<Vec2> pts) {
  final n = pts.length;
  if (n < 5) return null;
  var cx = 0.0, cy = 0.0;
  for (final p in pts) {
    cx += p.x;
    cy += p.y;
  }
  cx /= n;
  cy /= n;
  var sxx = 0.0, sxy = 0.0, syy = 0.0;
  for (final p in pts) {
    final dx = p.x - cx, dy = p.y - cy;
    sxx += dx * dx;
    sxy += dx * dy;
    syy += dy * dy;
  }
  final theta = 0.5 * math.atan2(2 * sxy, sxx - syy);
  final cs = math.cos(theta), sn = math.sin(theta);

  // Normal equations of the 4-parameter fit, in a frame scaled by `s` so
  // the matrix stays well conditioned for any shape size.
  final s = math.sqrt((sxx + syy) / n);
  if (!(s > 1e-9)) return null;
  final ata = List.generate(4, (_) => List<double>.filled(4, 0));
  final atb = List<double>.filled(4, 0);
  final us = List<double>.filled(n, 0), vs = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final dx = (pts[i].x - cx) / s, dy = (pts[i].y - cy) / s;
    final u = dx * cs + dy * sn, v = -dx * sn + dy * cs;
    us[i] = u;
    vs[i] = v;
    final row = [u * u, v * v, u, v];
    for (var r = 0; r < 4; r++) {
      atb[r] += row[r];
      for (var c = 0; c < 4; c++) {
        ata[r][c] += row[r] * row[c];
      }
    }
  }
  final x = solveLinearSystem(ata, atb);
  if (x == null) return null;
  final (qa, qb, qc, qd) = (x[0], x[1], x[2], x[3]);
  if (!(qa > 0) || !(qb > 0)) return null;
  final u0 = -qc / (2 * qa), v0 = -qd / (2 * qb);
  final g = 1 + qc * qc / (4 * qa) + qd * qd / (4 * qb);
  if (!(g > 0)) return null;
  var a = math.sqrt(g / qa), b = math.sqrt(g / qb);
  var axis = theta;

  // Fit quality in the normalized frame.
  var sumErr = 0.0, maxErr = 0.0;
  final angles = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final eu = (us[i] - u0) / a, ev = (vs[i] - v0) / b;
    final err = (math.sqrt(eu * eu + ev * ev) - 1).abs();
    sumErr += err;
    if (err > maxErr) maxErr = err;
    angles[i] = math.atan2(ev, eu);
  }
  angles.sort();
  var gap = angles.first + 2 * math.pi - angles.last;
  for (var i = 1; i < n; i++) {
    gap = math.max(gap, angles[i] - angles[i - 1]);
  }

  final center = Vec2(cx, cy) + Vec2(u0 * s, v0 * s).rotate(theta);
  a *= s;
  b *= s;
  if (b > a) {
    final t = a;
    a = b;
    b = t;
    axis += math.pi / 2;
  }
  return EllipseFit(
    center: center,
    a: a,
    b: b,
    theta: _normalizeHalfTurn(axis),
    meanError: sumErr / n,
    maxError: maxErr,
    maxAngularGap: gap,
  );
}

/// [angle] folded into (−π/2, π/2] (an axis direction has no sign).
double _normalizeHalfTurn(double angle) {
  var t = angle % math.pi; // [0, π)
  if (t > math.pi / 2) t -= math.pi;
  return t;
}

/// Solves the square system `m·x = rhs` by Gaussian elimination with
/// partial pivoting. Returns null when it is singular. [m] and [rhs] are
/// modified.
List<double>? solveLinearSystem(List<List<double>> m, List<double> rhs) {
  final n = rhs.length;
  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var r = col + 1; r < n; r++) {
      if (m[r][col].abs() > m[pivot][col].abs()) pivot = r;
    }
    if (m[pivot][col].abs() < 1e-12) return null;
    if (pivot != col) {
      final row = m[pivot];
      m[pivot] = m[col];
      m[col] = row;
      final v = rhs[pivot];
      rhs[pivot] = rhs[col];
      rhs[col] = v;
    }
    for (var r = col + 1; r < n; r++) {
      final f = m[r][col] / m[col][col];
      if (f == 0) continue;
      for (var c = col; c < n; c++) {
        m[r][c] -= f * m[col][c];
      }
      rhs[r] -= f * rhs[col];
    }
  }
  final x = List<double>.filled(n, 0);
  for (var r = n - 1; r >= 0; r--) {
    var sum = rhs[r];
    for (var c = r + 1; c < n; c++) {
      sum -= m[r][c] * x[c];
    }
    x[r] = sum / m[r][r];
  }
  return x;
}
