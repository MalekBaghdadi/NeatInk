import 'dart:math' as math;

import 'package:neatink/beautify/features.dart';
import 'package:neatink/beautify/tidy_pipeline.dart';
import 'package:neatink/ink/affine2.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';

/// A tiny synthetic "print" font for the tidy tests: simple polyline letters
/// with the baseline at y = 0, an x-height of 10 and ascenders / capitals 19
/// high (y points down, so letters live at negative y). Every glyph is a list
/// of strokes, like print handwriting.
const double fontXHeight = 10;
const double fontTall = 19;

class Glyph {
  const Glyph(this.strokes, this.width);
  final List<List<Vec2>> strokes;
  final double width;
}

/// Points of an elliptical arc, angles in degrees counter-clockwise on
/// screen (0 = right, 90 = up).
List<Vec2> arc(double cx, double cy, double rx, double ry, double from,
    double to, {int steps = 48}) {
  return [
    for (var i = 0; i <= steps; i++)
      () {
        final a = (from + (to - from) * i / steps) * math.pi / 180;
        return Vec2(cx + rx * math.cos(a), cy - ry * math.sin(a));
      }(),
  ];
}

List<Vec2> _line(List<Vec2> corners) => corners;

Glyph glyph(String ch) {
  switch (ch) {
    case 'l':
      return Glyph([
        _line(const [Vec2(0, -fontTall), Vec2(0, 0)]),
      ], 0);
    case 'o':
      return Glyph([arc(4, -5, 4, 5, 90, 450)], 8);
    case 'e':
      return Glyph([
        [
          const Vec2(0, -5),
          const Vec2(8, -5),
          ...arc(4, -5, 4, 5, 0, 315).skip(1),
        ],
      ], 8);
    case 'h':
      return Glyph([
        [
          const Vec2(0, -fontTall),
          const Vec2(0, 0),
          const Vec2(0, -6),
          ...arc(3.5, -6, 3.5, 4, 180, 0, steps: 24).skip(1),
          const Vec2(7, 0),
        ],
      ], 7);
    case 'n':
      return Glyph([
        [
          const Vec2(0, -10),
          const Vec2(0, 0),
          const Vec2(0, -7),
          ...arc(3.5, -7, 3.5, 3, 180, 0, steps: 24).skip(1),
          const Vec2(7, 0),
        ],
      ], 7);
    case 'g':
      return Glyph([
        [
          ...arc(4, -5, 4, 5, 0, 360),
          const Vec2(8, -10),
          const Vec2(8, 2),
          ...arc(4, 2, 4, 5.5, 0, -90, steps: 12).skip(1),
          const Vec2(0, 6.5),
        ],
      ], 8);
    case 'i':
      return Glyph([
        _line(const [Vec2(0, -10), Vec2(0, 0)]),
        _line(const [Vec2(-0.3, -14), Vec2(0.3, -14)]),
      ], 0);
    case 'H':
      return Glyph([
        _line(const [Vec2(0, -fontTall), Vec2(0, 0)]),
        _line(const [Vec2(9, -fontTall), Vec2(9, 0)]),
        _line(const [Vec2(0, -9.5), Vec2(9, -9.5)]),
      ], 9);
    case 'E':
      return Glyph([
        _line(const [Vec2(0, -fontTall), Vec2(0, 0)]),
        _line(const [Vec2(0, -fontTall), Vec2(8, -fontTall)]),
        _line(const [Vec2(0, -9.5), Vec2(7, -9.5)]),
        _line(const [Vec2(0, 0), Vec2(8, 0)]),
      ], 8);
  }
  throw ArgumentError('no glyph for $ch');
}

/// Inserts points so no two neighbours are further apart than [step].
List<Vec2> densify(List<Vec2> pts, [double step = 0.4]) {
  final out = <Vec2>[pts.first];
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    final n = (a.distanceTo(b) / step).ceil();
    for (var k = 1; k <= n; k++) {
      out.add(a.lerp(b, k / n));
    }
  }
  return out;
}

/// The strokes of [text] laid out left to right from x = 0 (baseline y = 0),
/// letters [gap] apart. Each stroke is a dense polyline.
List<List<Vec2>> wordPolylines(String text, {double gap = 4}) {
  final out = <List<Vec2>>[];
  var x = 0.0;
  for (final ch in text.split('')) {
    final g = glyph(ch);
    for (final s in g.strokes) {
      out.add(densify([for (final p in s) Vec2(p.x + x, p.y)]));
    }
    x += g.width + gap;
  }
  return out;
}

/// A known distortion: scale, then lean (shear, degrees, positive = leaning
/// right), then rotation (degrees, positive = clockwise on screen, i.e. the
/// baseline descends to the right), then placement at ([x], [y]).
Affine2 distortion({
  double scale = 1,
  double leanDeg = 0,
  double rotateDeg = 0,
  double x = 100,
  double y = 300,
}) {
  final sc = Affine2.scaling(scale, scale);
  // x' = x − tan(lean)·y: above the baseline y < 0, so the top moves right.
  final lean = Affine2.shearX(-math.tan(leanDeg * math.pi / 180));
  final rot = Affine2.rotation(rotateDeg * math.pi / 180);
  return Affine2.translation(x, y) * rot * lean * sc;
}

/// Builds pen strokes from polylines, applying [m]. Point times advance
/// 5 ms per point, strokes are numbered `<prefix>-0`, `<prefix>-1` …
List<Stroke> toStrokes(List<List<Vec2>> polylines,
    {Affine2 m = Affine2.identity, String prefix = 's', int t0 = 0}) {
  var t = t0;
  return [
    for (var i = 0; i < polylines.length; i++)
      Stroke(
        id: '$prefix-$i',
        tool: StrokeTool.pen,
        color: 0xFF1E1E1E,
        size: 2.2,
        raw: [
          for (final p in polylines[i])
            () {
              final q = m.apply(p);
              t += 5;
              return InkPoint(q.x, q.y, 0.5, t);
            }(),
        ],
      ),
  ];
}

/// Convenience: the strokes of [text] with a distortion applied.
List<Stroke> makeWord(String text,
        {String prefix = 'w',
        double gap = 4,
        double scale = 1,
        double leanDeg = 0,
        double rotateDeg = 0,
        double x = 100,
        double y = 300}) =>
    toStrokes(wordPolylines(text, gap: gap),
        prefix: prefix,
        m: distortion(
            scale: scale,
            leanDeg: leanDeg,
            rotateDeg: rotateDeg,
            x: x,
            y: y));

/// Re-measures a tidied word: the strokes of [original] showing the result's
/// new points, analysed on their displayed points.
WordAnalysis reanalyze(List<Stroke> original, TidyResult result,
    {FeatureContext context = const FeatureContext()}) {
  return analyzeWord([
    for (final s in original) s.copyWith(points: result.newPoints[s.id]),
  ], useRaw: false, context: context)!;
}

/// Lowest y (largest) of a stroke's displayed points.
double bottomOf(List<InkPoint> pts) => pts.map((p) => p.y).reduce(math.max);

/// Highest point (smallest y).
double topOf(List<InkPoint> pts) => pts.map((p) => p.y).reduce(math.min);

double degrees(double rad) => rad * 180 / math.pi;
