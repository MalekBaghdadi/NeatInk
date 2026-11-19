import 'dart:math' as math;
import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart';

import '../ink/ink_point.dart';
import '../ink/stroke.dart';

/// Stroke outlines shared by the screen renderer and the PDF exporter, so an
/// exported page looks exactly like the screen.
///
/// Every stroke is drawn as a filled polygon from `perfect_freehand`. Use
/// [PathFillType.nonZero] (PDF: `fill()`, not `fillEvenOdd()`), because
/// outlines can cross themselves on tight loops.

/// Fill opacity of highlighter strokes.
const double highlighterOpacity = 0.35;

/// Slanted highlight ends ([HighlightEnds.slanted]): the cut runs at this
/// angle from the page's horizontal, rising to the right ("/"), like a
/// chisel marker held the usual way.
const double slantedEndAngleDeg = 60;

/// ... and reaches at most this many band widths past the square end (a
/// stroke drawn almost along the cut would otherwise get a long spike).
const double slantedEndMaxReach = 1;

/// Fill opacity of pencil strokes (gives them a lighter, graphite look).
const double pencilOpacity = 0.85;

/// Pressures that vary less than this across a stroke count as "no pressure
/// data" (e.g. a pen that always reports 1.0), and perfect_freehand then
/// simulates pressure from speed instead.
const double _flatPressureEpsilon = 0.01;

/// The perfect_freehand options for [s]. `size` is the stroke diameter in
/// points.
StrokeOptions strokeOptionsFor(Stroke s, {bool isComplete = true}) {
  final simulate = _pressureIsFlat(s.points);
  if (s.tool == StrokeTool.highlighter) {
    return StrokeOptions(
      size: s.size,
      thinning: 0,
      smoothing: 0.5,
      streamline: 0.4,
      simulatePressure: false,
      // Round ends are perfect_freehand's caps; square and slanted start
      // from its flat ones (slanted are reshaped in [strokeOutline]).
      start: StrokeEndOptions.start(cap: s.highlightEnds == HighlightEnds.round),
      end: StrokeEndOptions.end(cap: s.highlightEnds == HighlightEnds.round),
      isComplete: isComplete,
    );
  }
  if (s.shape != null) {
    // Generated shapes: constant width, crisp corners.
    return StrokeOptions(
      size: s.size,
      thinning: 0,
      smoothing: 0.2,
      streamline: 0,
      simulatePressure: false,
      isComplete: isComplete,
    );
  }
  switch (s.penStyle) {
    case PenStyle.ballpoint:
      // Pressing harder draws a visibly thicker line (about 0.7x to 1.3x the
      // width between light and firm pressure). v1.6.0: was 0.25, which
      // Mariam could not see ("no thicker lines if I pressed harder").
      return StrokeOptions(
        size: s.size,
        thinning: 0.5,
        smoothing: 0.6,
        streamline: 0.35,
        simulatePressure: simulate,
        isComplete: isComplete,
      );
    case PenStyle.fountain:
      return StrokeOptions(
        size: s.size * 1.15,
        thinning: 0.65,
        smoothing: 0.6,
        streamline: 0.35,
        easing: _easeOutSine,
        simulatePressure: simulate,
        start: StrokeEndOptions.start(taperEnabled: true, customTaper: s.size * 2),
        end: StrokeEndOptions.end(taperEnabled: true, customTaper: s.size * 3),
        isComplete: isComplete,
      );
    case PenStyle.pencil:
      return StrokeOptions(
        size: s.size * 0.9,
        thinning: 0.4,
        smoothing: 0.5,
        streamline: 0.3,
        simulatePressure: simulate,
        isComplete: isComplete,
      );
  }
}

/// Outline polygon of [s] in page coordinates.
List<Offset> strokeOutline(Stroke s, {bool isComplete = true}) {
  final pts = s.points;
  if (pts.isEmpty) return const [];
  final input = <PointVector>[
    for (final p in pts)
      if (p.isFinite) PointVector(p.x, p.y, p.pressure),
  ];
  if (input.isEmpty) return const [];
  final options = strokeOptionsFor(s, isComplete: isComplete);
  if (s.tool == StrokeTool.highlighter && s.highlightEnds == HighlightEnds.slanted) {
    return _slantedOutline(input, options);
  }
  return getStroke(input, options: options);
}

/// A highlighter outline with slanted ends: perfect_freehand's flat ends,
/// each with one corner pushed outward along the stroke so the end runs at
/// [slantedEndAngleDeg] ("/" at both ends whichever way it was drawn).
/// Only ever adds a small triangle past each square end, so it never cuts
/// into the band or the words under it.
List<Offset> _slantedOutline(List<PointVector> input, StrokeOptions options) {
  final pts = getStrokePoints(input, options: options);
  final outline = getStrokeOutlinePoints(pts, options: options);
  // A dot has no ends; a flat end is four points (see perfect_freehand's
  // getStrokeOutlinePoints): the end's after the left side, the start's last.
  if (pts.length < 2 || outline.length < 10) return outline;
  final last = pts.last.point;
  final across = (-pts.last.vector).perpendicular();
  final r = options.size / 2; // no thinning: the radius is constant
  final e0 = last + across * r, e3 = last - across * r;
  int? end;
  for (var i = 0; i + 3 < outline.length - 4; i++) {
    if ((outline[i] - e0).distanceSquared < 1e-12 && (outline[i + 3] - e3).distanceSquared < 1e-12) {
      end = i;
      break;
    }
  }
  if (end == null) return outline; // not the shape expected: keep it square
  final n = outline.length;
  final previous = pts[pts.length - 2].point;
  final endCap = _slantedEnd(outline[end], outline[end + 3], Offset(last.dx - previous.dx, last.dy - previous.dy));
  final first = pts.first.point, second = pts[1].point;
  final startCap = _slantedEnd(outline[n - 4], outline[n - 1], Offset(first.dx - second.dx, first.dy - second.dy));
  return [
    ...outline.sublist(0, end),
    ...endCap,
    ...outline.sublist(end + 4, n - 4),
    ...startCap,
  ];
}

/// The flat end from corner [a] to corner [b], slanted: one corner moves
/// outward ([out] points away from the stroke) until the end lies along the
/// cut direction. Returns the two corners in the same order.
List<Offset> _slantedEnd(Offset a, Offset b, Offset out) {
  final width = (a - b).distance;
  if (width <= 0) return [a, b];
  // Outward unit vector: across the end, on the side [out] points to.
  var u = Offset(-(a.dy - b.dy) / width, (a.dx - b.dx) / width);
  if (u.dx * out.dx + u.dy * out.dy < 0) u = -u;
  final angle = slantedEndAngleDeg * math.pi / 180;
  final cut = Offset(math.cos(angle), -math.sin(angle)); // page y points down
  double cross(Offset p, Offset q) => p.dx * q.dy - p.dy * q.dx;
  // Moving a by u*k puts the end (a + u*k) - b along the cut when
  // cross(a - b + u*k, cut) = 0; a negative k means b moves instead.
  final k = -cross(a - b, cut) / cross(u, cut);
  final reach = slantedEndMaxReach * width;
  final step = k.isNaN ? 0.0 : k.clamp(-reach, reach).toDouble();
  return step >= 0 ? [a + u * step, b] : [a, b + u * -step];
}

final Expando<Path> _pathCache = Expando('strokePath');
final Expando<List<Offset>> _outlineCache = Expando('strokeOutline');

/// Cached outline of a finished stroke. Strokes are immutable, so the cache
/// is keyed by instance and a changed stroke (a new instance) recomputes.
List<Offset> cachedStrokeOutline(Stroke s) =>
    _outlineCache[s] ??= strokeOutline(s);

/// Cached fill path of a finished stroke (see [cachedStrokeOutline]).
Path cachedStrokePath(Stroke s) => _pathCache[s] ??= outlinePath(cachedStrokeOutline(s));

/// Builds a closed, non-zero-filled path from an outline polygon.
Path outlinePath(List<Offset> outline) {
  final path = Path()..fillType = PathFillType.nonZero;
  if (outline.length >= 3) path.addPolygon(outline, true);
  return path;
}

/// The colour to fill [s]'s outline with, including tool opacity.
Color strokeFillColor(Stroke s) {
  final base = Color(s.color);
  final opacity = switch (s.tool) {
    StrokeTool.highlighter => highlighterOpacity,
    StrokeTool.pen => s.penStyle == PenStyle.pencil ? pencilOpacity : 1.0,
  };
  return base.withValues(alpha: base.a * opacity);
}

/// ARGB int of [strokeFillColor], for the PDF exporter.
int strokeFillArgb(Stroke s) => strokeFillColor(s).toARGB32();

/// Pressure easing for the fountain pen: responsive at light pressure,
/// flattening out near full pressure.
double _easeOutSine(double t) => math.sin(t * math.pi / 2);

bool _pressureIsFlat(List<InkPoint> pts) {
  if (pts.length < 2) return true;
  var lo = pts.first.pressure, hi = lo;
  for (final p in pts) {
    if (p.pressure < lo) lo = p.pressure;
    if (p.pressure > hi) hi = p.pressure;
  }
  return hi - lo < _flatPressureEpsilon;
}
