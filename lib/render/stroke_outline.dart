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
      start: StrokeEndOptions.start(cap: false),
      end: StrokeEndOptions.end(cap: false),
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
      return StrokeOptions(
        size: s.size,
        thinning: 0.25,
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
  return getStroke(input, options: strokeOptionsFor(s, isComplete: isComplete));
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
