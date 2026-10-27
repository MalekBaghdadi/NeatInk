import 'dart:math' as math;

import '../../../ink/ink_point.dart';
import '../../../ink/stroke.dart';
import '../../../ink/vec2.dart';
import 'geometry.dart';
import 'shape_fitting.dart';
import 'shape_geometry.dart';
import 'tool_config.dart';

/// Classifies a hand-drawn stroke as a line, arrow, rectangle, ellipse
/// (circle) or triangle, for hold-to-snap. Pure Dart; all thresholds live in
/// [ToolConfig].
///
/// The pipeline, in short:
///  1. Collapse the pen resting at the start / end (the hold itself).
///  2. Resample evenly, so every feature is independent of drawing speed.
///  3. If the stroke comes back to its start it is a closed shape:
///     * polygon: Douglas–Peucker corners, wobbly vertices merged away;
///       4 corners at right angles make a rectangle (rotated ones too), 3
///       corners a triangle;
///     * ellipse: least-squares fit with residual and coverage checks;
///     * whichever fits the ink better wins, so a square is not an ellipse
///       and a circle is not an octagon.
///  4. Otherwise it is a line (straight, not a zigzag) or an arrow (shaft
///     followed by two barbs drawn tip → barb → tip → barb).
///  5. Anything else (handwriting, scribbles, spirals, zigzags) gives null.
///
/// Returns null when there is no confident match: a wrong snap destroys the
/// look of the user's page, a missed snap costs one more try.
RecognizedShape? recognizeShape(
  List<InkPoint> stroke, {
  ToolConfig config = ToolConfig.defaults,
}) {
  final trimmed = _trimDwell([
    for (final p in stroke)
      if (p.isFinite) p,
  ], config);
  if (trimmed.length < 3) return null;
  final raw = [for (final p in trimmed) p.pos];
  final length = polylineLength(raw);
  if (length < config.shapeMinPathLengthPt) return null;

  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  for (final p in raw) {
    minX = math.min(minX, p.x);
    minY = math.min(minY, p.y);
    maxX = math.max(maxX, p.x);
    maxY = math.max(maxY, p.y);
  }
  final diagonal = math.sqrt(
      (maxX - minX) * (maxX - minX) + (maxY - minY) * (maxY - minY));
  if (!(diagonal > 0)) return null;

  final spacing = (length / config.shapeAnalysisSamples)
      .clamp(config.shapeMinSpacingPt, config.shapeMaxSpacingPt)
      .toDouble();
  final pts = resamplePolyline(raw, spacing);
  if (pts.length < 6) return null;
  final tolerance = (diagonal * config.polygonToleranceFraction)
      .clamp(config.polygonToleranceMinPt, config.polygonToleranceMaxPt)
      .toDouble();

  final loopEnd = _closureIndex(pts, diagonal, config);
  if (loopEnd != null) {
    final loop = pts.sublist(0, loopEnd + 1);
    return _recognizeClosed(
        loop, spacing, diagonal, tolerance, maxX - minX, maxY - minY, config);
  }
  return _lineOf(pts, config) ?? _arrowOf(pts, diagonal, tolerance, config);
}

// ---------------------------------------------------------------------------
// Input preparation

/// Drops the samples of a pen resting at the end (and the start) of the
/// stroke: everything within the dwell radius of the extreme point for at
/// least the dwell time collapses onto the first sample of the rest.
List<InkPoint> _trimDwell(List<InkPoint> pts, ToolConfig cfg) {
  var from = 0, to = pts.length - 1;
  if (to < 2) return pts;
  final r = cfg.shapeDwellRadiusPt;
  // End.
  var k = to;
  while (k > 0 && pts[k - 1].pos.distanceTo(pts[to].pos) <= r) {
    k--;
  }
  if (k < to && pts[to].t - pts[k].t >= cfg.shapeDwellMs) to = k;
  // Start.
  k = from;
  while (k < to && pts[k + 1].pos.distanceTo(pts[from].pos) <= r) {
    k++;
  }
  if (k > from && pts[k].t - pts[from].t >= cfg.shapeDwellMs) from = k;
  return pts.sublist(from, to + 1);
}

/// The index at which the stroke comes back to its start (the stroke is
/// then closed and ink after that index is overshoot), or null for an open
/// stroke.
int? _closureIndex(List<Vec2> pts, double diagonal, ToolConfig cfg) {
  final cum = cumulativeLengths(pts);
  final total = cum.last;
  final limit = cfg.closedGapFraction * diagonal;
  int? best;
  var bestDist = double.infinity;
  for (var i = 1; i < pts.length; i++) {
    if (cum[i] < cfg.closedSearchStartFraction * total) continue;
    final d = pts[i].distanceTo(pts[0]);
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
  }
  if (best == null || bestDist > limit) return null;
  // A short overshoot past the start is fine; a long tail is another shape.
  if (total - cum[best] > limit) return null;
  return best;
}

// ---------------------------------------------------------------------------
// Lines and arrows

RecognizedShape? _lineOf(List<Vec2> pts, ToolConfig cfg) {
  final chord = pts.first.distanceTo(pts.last);
  if (chord < cfg.lineMinLengthPt) return null;
  if (polylineLength(pts) / chord > cfg.lineMaxPathRatio) return null;
  final fit = fitLine(pts);
  if (fit == null) return null;
  var deviation = 0.0;
  for (final p in pts) {
    deviation = math.max(deviation, fit.signedDistance(p).abs());
  }
  if (deviation >
      cfg.lineMaxDeviationFraction * chord + cfg.lineDeviationSlackPt) {
    return null;
  }
  final (a, b) = _snapSegment(fit.project(pts.first), fit.project(pts.last), cfg);
  if (a.distanceTo(b) < cfg.lineMinLengthPt) return null;
  return RecognizedShape._line([a, b]);
}

/// Rotates the segment about its middle so it lies exactly on a multiple of
/// 45° when it is within [ToolConfig.lineAngleSnapDeg] of it.
(Vec2, Vec2) _snapSegment(Vec2 a, Vec2 b, ToolConfig cfg) {
  final d = b - a;
  final angle = math.atan2(d.y, d.x);
  final snapped = snapAngle(
      angle, math.pi / 4, degToRad(cfg.lineAngleSnapDeg));
  if (snapped == angle) return (a, b);
  final mid = a.lerp(b, 0.5);
  final half = Vec2(math.cos(snapped), math.sin(snapped)) * (d.length / 2);
  return (mid - half, mid + half);
}

/// Shaft plus head, drawn as one stroke: tail → tip → barb → tip → barb.
RecognizedShape? _arrowOf(
    List<Vec2> pts, double diagonal, double tolerance, ToolConfig cfg) {
  var idx = douglasPeucker(pts, tolerance);
  if (idx.length > cfg.polygonMaxVertices) return null;
  idx = _mergeVertices(pts, idx,
      closed: false, tolerance: tolerance, cfg: cfg);
  idx = _dropHooks(pts, idx, cfg);
  if (idx.length != 5) return null;

  final tail = pts[idx[0]], tip = pts[idx[1]];
  final b1 = pts[idx[2]], tip2 = pts[idx[3]], b2 = pts[idx[4]];
  final shaft = tail.distanceTo(tip);
  if (shaft < cfg.arrowMinShaftPt) return null;
  final l1 = tip.distanceTo(b1), l2 = tip2.distanceTo(b2);
  final longer = math.max(l1, l2), shorter = math.min(l1, l2);
  final minBarb = math.max(cfg.arrowMinBarbFraction * shaft, cfg.arrowMinBarbPt);
  if (shorter < minBarb || longer > cfg.arrowMaxBarbFraction * shaft) {
    return null;
  }
  if (shorter / longer < cfg.arrowMinBarbRatio) return null;
  // The return to the tip lands on it.
  if (tip.distanceTo(tip2) > cfg.arrowTipToleranceFraction * longer) {
    return null;
  }
  final back = (tail - tip).normalized();
  final d1 = (b1 - tip), d2 = (b2 - tip2);
  final s1 = back.cross(d1), s2 = back.cross(d2);
  if (s1 * s2 >= 0) return null; // barbs must be on opposite sides
  final a1 = angleBetween(back, d1), a2 = angleBetween(back, d2);
  final lo = degToRad(cfg.arrowBarbMinAngleDeg);
  final hi = degToRad(cfg.arrowBarbMaxAngleDeg);
  if (a1 < lo || a1 > hi || a2 < lo || a2 > hi) return null;

  // The shaft is also a line: it snaps to 0/45/90°. The tip is the average
  // of the two visits.
  final (t0, t1) = _snapSegment(tail, tip.lerp(tip2, 0.5), cfg);
  return RecognizedShape._arrow(
    tail: t0,
    tip: t1,
    barbLength: (l1 + l2) / 2,
    barbAngle: (a1 + a2) / 2,
    firstBarbSide: s1 >= 0 ? 1 : -1,
  );
}

/// Removes a pen-down / pen-up hook: a very short first or last side.
List<int> _dropHooks(List<Vec2> p, List<int> idx, ToolConfig cfg) {
  if (idx.length < 4) return idx;
  var longest = 0.0;
  for (var k = 0; k + 1 < idx.length; k++) {
    longest = math.max(longest, p[idx[k]].distanceTo(p[idx[k + 1]]));
  }
  bool isHook(double len) =>
      len < cfg.hookMaxFraction * longest && len < cfg.hookMaxPt;
  var out = idx;
  if (isHook(p[out[0]].distanceTo(p[out[1]]))) out = out.sublist(1);
  final n = out.length;
  if (n >= 4 && isHook(p[out[n - 1]].distanceTo(p[out[n - 2]]))) {
    out = out.sublist(0, n - 1);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Closed shapes

RecognizedShape? _recognizeClosed(
  List<Vec2> loopWithEnd,
  double spacing,
  double diagonal,
  double tolerance,
  double width,
  double height,
  ToolConfig cfg,
) {
  if (math.max(width, height) < cfg.closedMinDiameterPt) return null;
  // The cyclic list: drop the end when it only repeats the start.
  final loop = loopWithEnd.last.distanceTo(loopWithEnd.first) < spacing * 1.5
      ? loopWithEnd.sublist(0, loopWithEnd.length - 1)
      : loopWithEnd;
  if (loop.length < 8) return null;

  // One simple loop turns 360°; a figure eight or a double loop does not.
  final turning = totalTurning(loop, closed: true);
  if ((turning.abs() - 2 * math.pi).abs() >
      degToRad(cfg.ellipseTurnToleranceDeg)) {
    return null;
  }
  final dirSign = turning > 0 ? 1.0 : -1.0;
  final start = loop.first;

  // Ellipse candidate.
  EllipseFit? fit = fitEllipse(loop);
  double? ellipseError;
  if (fit != null &&
      fit.meanError <= cfg.ellipseMeanErrorMax &&
      fit.maxError <= cfg.ellipseMaxErrorMax &&
      fit.maxAngularGap <= degToRad(cfg.ellipseMaxAngularGapDeg) &&
      fit.axisRatio >= 0.2) {
    ellipseError = fit.meanError * math.sqrt(fit.a * fit.b);
  } else {
    fit = null;
  }

  // Polygon candidate.
  var idx = douglasPeuckerClosed(loop, tolerance);
  RecognizedShape? polygon;
  double? polygonError;
  if (idx.length <= cfg.polygonMaxVertices) {
    idx = _mergeVertices(loop, idx,
        closed: true, tolerance: tolerance, cfg: cfg);
    idx = _mergeShortEdges(loop, idx, diagonal, cfg);
    if (idx.length == 5 && _allTurnsAtLeast(loop, idx, cfg.polygonRejectTurnDeg)) {
      // A pentagon: not a shape we can draw. Only a convincing ellipse
      // (a rounded circle that happened to get 5 corners) survives.
      if (fit == null || fit.meanError > cfg.ellipseMeanErrorMax / 2) {
        return null;
      }
    } else if (idx.length == 4) {
      final corners = _rectangleCorners(loop, idx, dirSign, start, cfg);
      if (corners != null) {
        final outline = [...corners, corners.first];
        polygon = RecognizedShape._polygon(ShapeKind.rectangle, outline);
        polygonError = _meanDistanceToPolyline(loop, outline);
      }
    } else if (idx.length == 3) {
      final corners = _triangleCorners(loop, idx, start, cfg);
      if (corners != null) {
        final outline = [...corners, corners.first];
        polygon = RecognizedShape._polygon(ShapeKind.triangle, outline);
        polygonError = _meanDistanceToPolyline(loop, outline);
      }
    }
  }

  if (polygon != null &&
      (fit == null || polygonError! <= ellipseError!)) {
    return polygon;
  }
  if (fit == null) return null;
  return _ellipseShape(fit, start, dirSign, spacing, cfg);
}

RecognizedShape _ellipseShape(EllipseFit fit, Vec2 start, double dirSign,
    double spacing, ToolConfig cfg) {
  var a = fit.a, b = fit.b, theta = fit.theta;
  if (fit.axisRatio >= cfg.circleAxisRatio) {
    a = b = (a + b) / 2;
    theta = 0;
  } else {
    final snap = degToRad(cfg.ellipseAxisSnapDeg);
    if (theta.abs() <= snap) {
      theta = 0;
    } else if ((math.pi / 2 - theta.abs()).abs() <= snap) {
      theta = math.pi / 2;
    }
  }
  final d = (start - fit.center).rotate(-theta);
  final t0 = math.atan2(d.y / b, d.x / a);
  final outline = ellipseOutline(fit.center, a, b, theta,
      t0: t0, clockwise: dirSign > 0, spacing: cfg.shapeOutputSpacingPt);
  return RecognizedShape._ellipse(outline, fit.center);
}

bool _allTurnsAtLeast(List<Vec2> p, List<int> v, double minDeg) {
  final m = v.length;
  for (var k = 0; k < m; k++) {
    final before = p[v[(k - 1 + m) % m]], at = p[v[k]], after = p[v[(k + 1) % m]];
    if (radToDeg(angleBetween(at - before, after - at)) < minDeg) return false;
  }
  return true;
}

/// Removes vertices of [indices] (indices into [p]) that barely turn and
/// whose removal leaves the ink within a slightly looser tolerance: wobbly
/// sides then have no extra corners. Smallest turns go first.
List<int> _mergeVertices(
  List<Vec2> p,
  List<int> indices, {
  required bool closed,
  required double tolerance,
  required ToolConfig cfg,
}) {
  final v = List<int>.of(indices);
  final minKeep = closed ? 3 : 2;
  final limit = degToRad(cfg.polygonMergeAngleDeg);
  while (v.length > minKeep) {
    var bestK = -1;
    var bestTurn = limit;
    final first = closed ? 0 : 1;
    final end = closed ? v.length : v.length - 1;
    for (var k = first; k < end; k++) {
      final prev = v[(k - 1 + v.length) % v.length];
      final next = v[(k + 1) % v.length];
      final u = p[v[k]] - p[prev], w = p[next] - p[v[k]];
      final turn = u.lengthSquared == 0 || w.lengthSquared == 0
          ? 0.0
          : angleBetween(u, w);
      if (turn >= bestTurn) continue;
      final dev = closed
          ? cyclicDeviation(p, prev, next)
          : farthestFromSegment(p, prev, next).$2;
      if (dev > tolerance * cfg.polygonMergeErrorFactor) continue;
      bestK = k;
      bestTurn = turn;
    }
    if (bestK < 0) break;
    v.removeAt(bestK);
  }
  return v;
}

/// Closed shapes: two close corners that turn the same way are one rounded
/// corner; they are replaced by the ink point farthest from the chord of
/// their neighbours.
List<int> _mergeShortEdges(
    List<Vec2> p, List<int> indices, double diagonal, ToolConfig cfg) {
  var v = List<int>.of(indices);
  final minLen = cfg.polygonShortEdgeFraction * diagonal;
  var changed = true;
  while (changed && v.length > 3) {
    changed = false;
    final m = v.length;
    for (var k = 0; k < m; k++) {
      final a = v[k], b = v[(k + 1) % m];
      if (p[a].distanceTo(p[b]) >= minLen) continue;
      final before = v[(k - 1 + m) % m], after = v[(k + 2) % m];
      if (before == after) continue;
      final t1 = signedAngleBetween(p[a] - p[before], p[b] - p[a]);
      final t2 = signedAngleBetween(p[b] - p[a], p[after] - p[b]);
      if (t1 * t2 <= 0) continue;
      // The ink point between `before` and `after` farthest from their
      // chord is the corner.
      var best = a;
      var bestD = -1.0;
      for (var i = (before + 1) % p.length;
          i != after;
          i = (i + 1) % p.length) {
        final d = distanceToSegment(p[i], p[before], p[after]);
        if (d > bestD) {
          bestD = d;
          best = i;
        }
      }
      final next = <int>[];
      for (var t = 0; t < m; t++) {
        if (t == k) {
          next.add(best);
        } else if (t != (k + 1) % m) {
          next.add(v[t]);
        }
      }
      v = next;
      changed = true;
      break;
    }
  }
  return v;
}

/// The points of the loop from vertex [a] to vertex [b] with the corners
/// (rounded in hand drawing) cut off at both ends.
List<Vec2> _sidePoints(List<Vec2> loop, int a, int b, double trim) {
  final side = cyclicRange(loop, a, b);
  final cut = (side.length * trim).floor();
  if (side.length - 2 * cut < 2) return side;
  return side.sublist(cut, side.length - cut);
}

/// The 4 corners (in the stroke's drawing direction, starting at the one
/// nearest the stroke's start) of the rectangle the 4 detected vertices
/// describe, or null when they don't form one.
List<Vec2>? _rectangleCorners(List<Vec2> loop, List<int> v, double dirSign,
    Vec2 strokeStart, ToolConfig cfg) {
  final c = [for (final i in v) loop[i]];
  final edges = [for (var k = 0; k < 4; k++) c[(k + 1) % 4] - c[k]];
  for (final e in edges) {
    if (e.lengthSquared == 0) return null;
  }
  // Each corner turns about 90° in the stroke's direction.
  final cornerTol = degToRad(cfg.rectCornerAngleTolDeg);
  for (var k = 0; k < 4; k++) {
    final turn = signedAngleBetween(edges[(k + 3) % 4], edges[k]) * dirSign;
    if ((turn - math.pi / 2).abs() > cornerTol) return null;
  }
  var longest = 0.0, shortest = double.infinity;
  for (final e in edges) {
    longest = math.max(longest, e.length);
    shortest = math.min(shortest, e.length);
  }
  if (shortest < math.max(cfg.rectMinSidePt, cfg.rectMinSideFraction * longest)) {
    return null;
  }

  // The rectangle's orientation: the length-weighted mean of the side
  // directions modulo 90° (multiplying the angles by 4 folds the four
  // sides onto one direction).
  var sx = 0.0, sy = 0.0;
  for (final e in edges) {
    final th = math.atan2(e.y, e.x);
    sx += math.cos(4 * th) * e.length;
    sy += math.sin(4 * th) * e.length;
  }
  var phi = math.atan2(sy, sx) / 4;
  final snap = degToRad(cfg.rectAxisSnapDeg);
  final rem = phi - (phi / (math.pi / 2)).roundToDouble() * (math.pi / 2);
  if (rem.abs() <= snap) phi = (phi / (math.pi / 2)).roundToDouble() * (math.pi / 2);
  final ux = Vec2(math.cos(phi), math.sin(phi));
  final vx = Vec2(-math.sin(phi), math.cos(phi));

  final sideTol = degToRad(cfg.rectSideAngleTolDeg);
  final uCoords = <double>[], vCoords = <double>[];
  for (var k = 0; k < 4; k++) {
    final th = math.atan2(edges[k].y, edges[k].x) - phi;
    final off = th - (th / (math.pi / 2)).roundToDouble() * (math.pi / 2);
    if (off.abs() > sideTol) return null;
    final alongU = math.cos(th).abs() >= math.sin(th).abs();
    final pts = _sidePoints(loop, v[k], v[(k + 1) % 4], cfg.sideTrimFraction);
    if (alongU) {
      // A side along u sits at one v.
      vCoords.add(_mean([for (final p in pts) p.dot(vx)]));
    } else {
      uCoords.add(_mean([for (final p in pts) p.dot(ux)]));
    }
  }
  if (uCoords.length != 2 || vCoords.length != 2) return null;
  final uLo = math.min(uCoords[0], uCoords[1]), uHi = math.max(uCoords[0], uCoords[1]);
  final vLo = math.min(vCoords[0], vCoords[1]), vHi = math.max(vCoords[0], vCoords[1]);
  if (uHi - uLo < cfg.rectMinSidePt || vHi - vLo < cfg.rectMinSidePt) {
    return null;
  }
  Vec2 at(double u, double v) => ux * u + vx * v;
  // (uLo,vLo) → (uHi,vLo) → (uHi,vHi) → (uLo,vHi) is clockwise on screen
  // (v is u rotated clockwise).
  var corners = [at(uLo, vLo), at(uHi, vLo), at(uHi, vHi), at(uLo, vHi)];
  if (dirSign < 0) corners = corners.reversed.toList();
  return _startingNear(corners, strokeStart);
}

/// The 3 corners (in drawing order, starting at the one nearest the
/// stroke's start) of the triangle with the detected vertices, with each
/// corner refined to where its two fitted sides meet when that stays close.
List<Vec2>? _triangleCorners(
    List<Vec2> loop, List<int> v, Vec2 strokeStart, ToolConfig cfg) {
  final c = [for (final i in v) loop[i]];
  final minAngle = degToRad(cfg.triangleMinAngleDeg);
  var shortest = double.infinity;
  for (var k = 0; k < 3; k++) {
    final toPrev = c[(k + 2) % 3] - c[k], toNext = c[(k + 1) % 3] - c[k];
    if (toPrev.lengthSquared == 0 || toNext.lengthSquared == 0) return null;
    if (angleBetween(toPrev, toNext) < minAngle) return null;
    shortest = math.min(shortest, toNext.length);
  }
  if (shortest < cfg.rectMinSidePt) return null;

  // Refine: corner k is where side k-1 (c[k-1] → c[k]) meets side k.
  final lines = [
    for (var k = 0; k < 3; k++)
      fitLine(_sidePoints(loop, v[k], v[(k + 1) % 3], cfg.sideTrimFraction)),
  ];
  var corners = c;
  if (lines.every((l) => l != null)) {
    final refined = <Vec2>[];
    for (var k = 0; k < 3; k++) {
      final q = lines[(k + 2) % 3]!.intersect(lines[k]!);
      if (q == null ||
          q.distanceTo(c[k]) > cfg.triangleCornerShiftFraction * shortest) {
        refined.clear();
        break;
      }
      refined.add(q);
    }
    if (refined.length == 3) corners = refined;
  }
  return _startingNear(corners, strokeStart);
}

List<Vec2> _startingNear(List<Vec2> corners, Vec2 p) {
  var start = 0;
  for (var i = 1; i < corners.length; i++) {
    if (corners[i].distanceTo(p) < corners[start].distanceTo(p)) start = i;
  }
  return [...corners.sublist(start), ...corners.sublist(0, start)];
}

double _mean(List<double> xs) {
  var s = 0.0;
  for (final x in xs) {
    s += x;
  }
  return s / xs.length;
}

/// Mean distance of [pts] to the polyline [outline].
double _meanDistanceToPolyline(List<Vec2> pts, List<Vec2> outline) {
  var sum = 0.0;
  for (final p in pts) {
    var best = double.infinity;
    for (var i = 1; i < outline.length; i++) {
      best = math.min(
          best,
          distanceSquaredToSegmentXY(p.x, p.y, outline[i - 1].x,
              outline[i - 1].y, outline[i].x, outline[i].y));
    }
    sum += math.sqrt(best);
  }
  return sum / pts.length;
}

// ---------------------------------------------------------------------------
// Result

/// A shape found by [recognizeShape]: its kind and clean outline.
class RecognizedShape {
  RecognizedShape._line(List<Vec2> outline)
      : kind = ShapeKind.line,
        outline = List.unmodifiable(outline),
        center = outline.first.lerp(outline.last, 0.5),
        _arrow = null;

  RecognizedShape._arrow({
    required Vec2 tail,
    required Vec2 tip,
    required double barbLength,
    required double barbAngle,
    required int firstBarbSide,
  })  : kind = ShapeKind.arrow,
        outline = List.unmodifiable(arrowOutline(
            tail, tip, barbLength, barbAngle,
            firstBarbSide: firstBarbSide)),
        center = tail.lerp(tip, 0.5),
        _arrow = _ArrowSpec(tail, tip, barbLength, barbAngle, firstBarbSide);

  RecognizedShape._polygon(this.kind, List<Vec2> outline)
      : outline = List.unmodifiable(outline),
        center = _centroid(outline),
        _arrow = null;

  RecognizedShape._ellipse(List<Vec2> outline, this.center)
      : kind = ShapeKind.ellipse,
        outline = List.unmodifiable(outline),
        _arrow = null;

  final ShapeKind kind;

  /// The vertices to draw through, in drawing order. Closed shapes repeat
  /// their first point at the end; an ellipse is already finely sampled.
  final List<Vec2> outline;

  /// Middle of the shape (the pivot when it is resized).
  final Vec2 center;

  final _ArrowSpec? _arrow;

  /// Lines and arrows have a start and an end that can follow the pen.
  bool get isSegment => kind == ShapeKind.line || kind == ShapeKind.arrow;

  /// Line / arrow: where the shape starts (the end that stays put).
  Vec2 get segmentStart => _arrow?.tail ?? outline.first;

  /// Line / arrow: where the shape ends (the arrow's tip).
  Vec2 get segmentEnd => _arrow?.tip ?? outline.last;

  /// The points of this shape for [source] (the hand-drawn stroke it
  /// replaces), with times taken from it.
  ShapeResult toResult(List<InkPoint> source,
      {ToolConfig config = ToolConfig.defaults}) {
    return ShapeResult(
      kind,
      outlineToPoints(
        outline,
        StrokeTiming.fromPoints(source),
        spacing: config.shapeOutputSpacingPt,
        pressure: config.shapeOutputPressure,
        densify: kind != ShapeKind.ellipse,
      ),
    );
  }

  /// This shape after the pen that rested at [from] moved on to [to]
  /// (continuing to move after the snap adjusts the shape).
  ///
  /// * Line / arrow: the end follows the pen (snapping to 45° steps when
  ///   close), the start stays. An arrow's head scales with its shaft.
  /// * Closed shapes: scaled about their centre, so the outline passes
  ///   through the pen again.
  RecognizedShape resizedTo(Vec2 from, Vec2 to,
      {ToolConfig config = ToolConfig.defaults}) {
    if (isSegment) {
      final a = segmentStart;
      if (a.distanceTo(to) < 1) return this;
      final (_, tip) = _snapSegment(a, to, config);
      final arrow = _arrow;
      if (arrow == null) return RecognizedShape._line([a, tip]);
      final oldLen = arrow.tail.distanceTo(arrow.tip);
      final k = oldLen <= 0 ? 1.0 : a.distanceTo(tip) / oldLen;
      return RecognizedShape._arrow(
        tail: a,
        tip: tip,
        barbLength: math.max(3, arrow.barbLength * k),
        barbAngle: arrow.barbAngle,
        firstBarbSide: arrow.firstBarbSide,
      );
    }
    final r0 = from.distanceTo(center);
    if (r0 < 1e-6) return this;
    final s = (to.distanceTo(center) / r0).clamp(0.05, 50.0).toDouble();
    final scaled = [for (final p in outline) center + (p - center) * s];
    return kind == ShapeKind.ellipse
        ? RecognizedShape._ellipse(scaled, center)
        : RecognizedShape._polygon(kind, scaled);
  }

  @override
  String toString() => 'RecognizedShape(${kind.name})';
}

class _ArrowSpec {
  const _ArrowSpec(
      this.tail, this.tip, this.barbLength, this.barbAngle, this.firstBarbSide);

  final Vec2 tail, tip;
  final double barbLength, barbAngle;
  final int firstBarbSide;
}

/// Mean of the distinct corners of a closed [outline] (first point
/// repeated at the end).
Vec2 _centroid(List<Vec2> outline) {
  final n = outline.length - 1;
  var x = 0.0, y = 0.0;
  for (var i = 0; i < n; i++) {
    x += outline[i].x;
    y += outline[i].y;
  }
  return Vec2(x / n, y / n);
}
