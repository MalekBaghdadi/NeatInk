import '../ink/ink_point.dart';
import '../ink/ink_rect.dart';
import '../ink/vec2.dart';

/// Spec step 0: uniform resampling, for analysis only.
///
/// Pen samples arrive at a fixed *time* rate, so slow parts of a stroke are
/// dense and fast parts sparse. Feature detection (extrema windows, slant
/// segment weights) assumes evenly spaced points, so it works on a copy
/// resampled every [step] points of arc length. The resampled points are
/// never stored or displayed.
///
/// * Non-finite input points (NaN / infinity) are ignored.
/// * The first finite point is always kept; the last finite point is
///   appended when it is not already the last sample, so stroke ends (where
///   letters often touch the baseline) are never lost.
/// * A stroke with a single finite point (a dot) resamples to that point.
List<Vec2> resamplePolyline(Iterable<Vec2> points, double step) {
  assert(step > 0);
  final out = <Vec2>[];
  Vec2? prev;
  Vec2? last;
  // Arc length walked since the last emitted sample.
  var carried = 0.0;
  for (final q in points) {
    if (!q.isFinite) continue;
    last = q;
    if (prev == null) {
      out.add(q);
      prev = q;
      continue;
    }
    var from = prev;
    var segLen = from.distanceTo(q);
    // Emit every point where the walked length reaches a multiple of step.
    while (carried + segLen >= step && segLen > 0) {
      final t = (step - carried) / segLen;
      final p = from.lerp(q, t);
      out.add(p);
      from = p;
      segLen = from.distanceTo(q);
      carried = 0;
    }
    carried += segLen;
    prev = q;
  }
  if (last != null && out.isNotEmpty && out.last.distanceSquaredTo(last) > 1e-12) {
    out.add(last);
  }
  return out;
}

/// Resamples a stroke's points (usually its `raw` points) for analysis.
List<Vec2> resampleInkPoints(List<InkPoint> points, double step) =>
    resamplePolyline(points.map((p) => p.pos), step);

/// Bounding box of the finite points in [points], or null when there are
/// none.
InkRect? finiteBounds(Iterable<InkPoint> points) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  for (final p in points) {
    if (!p.x.isFinite || !p.y.isFinite) continue;
    if (p.x < minX) minX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.x > maxX) maxX = p.x;
    if (p.y > maxY) maxY = p.y;
  }
  if (minX == double.infinity) return null;
  return InkRect(minX, minY, maxX, maxY);
}
