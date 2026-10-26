import 'dart:collection';
import 'dart:math' as math;

import '../../../ink/stroke.dart';
import '../../../ink/vec2.dart';
import 'geometry.dart';
import 'spatial_index.dart';

/// Whole-stroke eraser hit testing.
///
/// The eraser is a circle of `radius` pt that moved from `from` to `to`
/// since the last pointer event. Sweeping the segment (rather than testing
/// only the sampled positions) means a fast flick still erases every stroke
/// it crossed.

/// True when the eraser circle of [radius] swept from [from] to [to] touches
/// the painted area of [stroke]: its polyline inflated by half its width.
/// Works for single-point strokes (dots) and wide highlighters alike.
bool strokeTouchedBySweep(Stroke stroke, Vec2 from, Vec2 to, double radius) {
  final pts = stroke.points;
  if (pts.isEmpty) return false;
  final reach = radius + stroke.size / 2;
  final reach2 = reach * reach;
  if (!stroke.paintBounds.overlaps(sweepBounds(from, to, radius))) {
    return false;
  }
  if (pts.length == 1) {
    final p = pts.first;
    return distanceSquaredToSegmentXY(p.x, p.y, from.x, from.y, to.x, to.y) <=
        reach2;
  }
  // Per-segment box rejection keeps long strokes cheap.
  final minX = math.min(from.x, to.x) - reach;
  final maxX = math.max(from.x, to.x) + reach;
  final minY = math.min(from.y, to.y) - reach;
  final maxY = math.max(from.y, to.y) + reach;
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    if ((a.x < minX && b.x < minX) ||
        (a.x > maxX && b.x > maxX) ||
        (a.y < minY && b.y < minY) ||
        (a.y > maxY && b.y > maxY)) {
      continue;
    }
    if (segmentDistanceSquaredXY(
            a.x, a.y, b.x, b.y, from.x, from.y, to.x, to.y) <=
        reach2) {
      return true;
    }
  }
  return false;
}

/// Ids of the strokes in [candidates] touched by the sweep (see
/// [strokeTouchedBySweep]).
Set<String> strokesHitBySweep(
    Iterable<Stroke> candidates, Vec2 from, Vec2 to, double radius) {
  return {
    for (final s in candidates)
      if (strokeTouchedBySweep(s, from, to, radius)) s.id,
  };
}

/// Ids of the page's strokes touched by the sweep, using [index] to find
/// candidates. The index must be in sync with the page.
Set<String> eraseHits(
    SpatialIndex index, Vec2 from, Vec2 to, double radius) {
  return strokesHitBySweep(
      index.strokesIn(sweepBounds(from, to, radius)), from, to, radius);
}

/// Collects the strokes erased during one eraser drag, so the whole drag
/// becomes a single `RemoveStrokesCommand` (one undo step).
///
/// While dragging, the canvas hides [erasedIds]; on pen-up, if [isEmpty] is
/// false, run `RemoveStrokesCommand(pageId, session.erasedIds)`.
class StrokeEraseSession {
  StrokeEraseSession(this.index);

  /// The page's index, in sync with the page at the start of the drag.
  final SpatialIndex index;

  final Set<String> _erased = {};

  /// Every stroke erased so far in this drag.
  Set<String> get erasedIds => UnmodifiableSetView(_erased);

  bool get isEmpty => _erased.isEmpty;

  /// Erases along one pointer move and returns the ids newly hit by it.
  Set<String> sweep(Vec2 from, Vec2 to, double radius) {
    final hits = <String>{};
    for (final s in index.strokesIn(sweepBounds(from, to, radius))) {
      if (_erased.contains(s.id)) continue;
      if (strokeTouchedBySweep(s, from, to, radius)) hits.add(s.id);
    }
    _erased.addAll(hits);
    return hits;
  }
}
