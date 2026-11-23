import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/line_pattern.dart';
import 'package:neatink/ink/line_style.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/render/stroke_outline.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

/// A horizontal path at y = 100 from x = 0 to [length], with [pressure].
List<InkPoint> hLine(double length,
        {double step = 2, double Function(double x)? pressure}) =>
    [
      for (var x = 0.0; x < length; x += step)
        InkPoint(x, 100, pressure?.call(x) ?? 0.5, x.round()),
      InkPoint(length, 100, pressure?.call(length) ?? 0.5, length.round()),
    ];

Stroke strokeWith(
  List<InkPoint> pts, {
  LineStyle style = LineStyle.solid,
  StrokeTool tool = StrokeTool.pen,
  PenStyle pen = PenStyle.technical,
  double size = 2,
  double concentration = 1,
  int color = 0xFF112233,
  ShapeKind? shape,
  double waveHeight = 3.1,
  double waveWidth = 3.7,
}) =>
    Stroke(
      id: 's',
      tool: tool,
      penStyle: pen,
      color: color,
      size: size,
      raw: pts,
      shape: shape,
      line: LineSettings(
          style: style, waveHeight: waveHeight, waveWidth: waveWidth),
      concentration: concentration,
    );

Rect boundsOf(List<Offset> polygon) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final p in polygon) {
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

Rect allBounds(List<List<Offset>> polygons) =>
    polygons.map(boundsOf).reduce((a, b) => a.expandToInclude(b));

/// The outline the code produced before line styles existed.
List<Offset> oldOutline(Stroke s, {bool isComplete = true}) {
  final input = <PointVector>[
    for (final p in s.points)
      if (p.isFinite) PointVector(p.x, p.y, p.pressure),
  ];
  return getStroke(input, options: strokeOptionsFor(s, isComplete: isComplete));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a solid stroke is outlined exactly as before', () {
    final wobbly = [
      for (var i = 0; i < 80; i++)
        InkPoint(10 + i * 3.0, 200 + 12 * math.sin(i / 6), 0.2 + 0.7 * ((i * 7) % 10) / 10, i * 8),
    ];
    final flat = [for (final p in wobbly) InkPoint(p.x, p.y, 0.5, p.t)];

    test('every pen, with and without pressure, finished and live', () {
      for (final pen in PenStyle.values) {
        for (final pts in [wobbly, flat]) {
          final s = strokeWith(pts, pen: pen, size: 2.2);
          expect(strokeOutlines(s), [oldOutline(s)], reason: pen.name);
          expect(strokeOutlines(s, isComplete: false),
              [oldOutline(s, isComplete: false)],
              reason: '${pen.name} live');
          expect(strokeOutline(s), oldOutline(s));
        }
      }
    });

    test('the highlighter and generated shapes', () {
      final hl = strokeWith(wobbly, tool: StrokeTool.highlighter, size: 14);
      expect(strokeOutlines(hl), [oldOutline(hl)]);
      final shape = strokeWith(hLine(100), shape: ShapeKind.line);
      expect(strokeOutlines(shape), [oldOutline(shape)]);
    });

    test('one point, two points, and points that are not finite', () {
      for (final pts in [
        [const InkPoint(10, 10, 0.5, 0)],
        [const InkPoint(10, 10, 0.5, 0), const InkPoint(10, 10, 0.5, 9)],
        [const InkPoint(10, 10, 0.5, 0), const InkPoint(30, 20, 0.5, 9)],
        [
          const InkPoint(10, 10, 0.5, 0),
          const InkPoint(double.nan, 20, 0.5, 4),
          const InkPoint(30, 20, 0.5, 9),
          const InkPoint(40, 25, 0.5, 12),
        ],
      ]) {
        final s = strokeWith(pts, pen: PenStyle.ballpoint, size: 3);
        expect(strokeOutlines(s), [oldOutline(s)]);
      }
    });

    test('the concentration changes the colour, not the outline', () {
      final a = strokeWith(wobbly, pen: PenStyle.ballpoint);
      final b = strokeWith(wobbly, pen: PenStyle.ballpoint, concentration: 0.3);
      expect(strokeOutlines(b), strokeOutlines(a));
    });

    test('nothing to draw gives no polygon', () {
      expect(strokeOutlines(strokeWith(const [])), isEmpty);
      for (final style in LineStyle.values) {
        expect(strokeOutlines(strokeWith(const [], style: style)), isEmpty,
            reason: style.name);
      }
      expect(
          strokeOutlines(strokeWith(
              const [InkPoint(double.nan, 0, 0.5, 0)],
              style: LineStyle.dashed)),
          isEmpty);
    });
  });

  group('dashed', () {
    test('one polygon per dash, as long as a dash plus the round caps', () {
      // 296 pt, pen 2: 24 dashes, each 6.8 * k long on the centre line.
      final s = strokeWith(hLine(296), style: LineStyle.dashed);
      final polygons = strokeOutlines(s);
      expect(polygons, hasLength(24));
      const k = 296 / (24 * 12.6 - 5.8);
      for (final p in polygons) {
        expect(p.length, greaterThanOrEqualTo(3));
        final b = boundsOf(p);
        expect(b.width, closeTo(6.8 * k + 2, 0.05));
        expect(b.height, closeTo(2, 0.05));
        expect(b.center.dy, closeTo(100, 1e-6));
      }
      // The gaps are what is left: 5.8 * k - 2, about 3.8 pt.
      final gap = boundsOf(polygons[4]).left - boundsOf(polygons[3]).right;
      expect(gap, closeTo(5.8 * k - 2, 0.05));
    });

    test('the video\'s numbers: 8.8 pt dashes with 3.8 pt gaps for a 2 pt pen', () {
      final polygons = strokeOutlines(strokeWith(hLine(296), style: LineStyle.dashed));
      final dash = boundsOf(polygons[7]).width;
      final gap = boundsOf(polygons[8]).left - boundsOf(polygons[7]).right;
      expect(dash, closeTo(8.8, 0.1));
      expect(gap, closeTo(3.8, 0.1));
    });

    test('the first dash starts at the pen-down point and the last ends at the lift', () {
      final polygons = strokeOutlines(strokeWith(hLine(200), style: LineStyle.dashed));
      expect(boundsOf(polygons.first).left, closeTo(-1, 0.05));
      expect(boundsOf(polygons.last).right, closeTo(201, 0.05));
    });

    test('a highlighter has flat ends: a dash is exactly as long as its centre line', () {
      final pen = strokeWith(hLine(200), style: LineStyle.dashed, size: 10);
      final hl = strokeWith(hLine(200),
          style: LineStyle.dashed, size: 10, tool: StrokeTool.highlighter);
      final penDash = boundsOf(strokeOutlines(pen)[2]);
      final hlDash = boundsOf(strokeOutlines(hl)[2]);
      expect(penDash.width - hlDash.width, closeTo(10, 0.1));
      // perfect_freehand spreads a flat cap 1% wider each side.
      expect(hlDash.height, closeTo(10, 0.25));
    });

    test('a path shorter than a dash is one dash', () {
      final polygons = strokeOutlines(strokeWith(hLine(5), style: LineStyle.dashed));
      expect(polygons, hasLength(1));
      expect(boundsOf(polygons.single).width, closeTo(5 + 2, 0.05));
    });
  });

  group('dotted', () {
    test('every dot is a round dot of the pen\'s diameter on the line', () {
      final polygons = strokeOutlines(strokeWith(hLine(200), style: LineStyle.dotted));
      expect(polygons, hasLength(43));
      for (final p in polygons) {
        final b = boundsOf(p);
        expect(p.length, greaterThanOrEqualTo(12));
        for (final v in p) {
          expect((v - b.center).distance, closeTo(1, 1e-9)); // radius 2 / 2
        }
        expect(b.center.dy, closeTo(100, 1e-9));
        expect(b.width, closeTo(2, 1e-9));
        expect(b.height, closeTo(2, 1e-9));
      }
      expect(boundsOf(polygons.first).center.dx, closeTo(0, 1e-9));
      expect(boundsOf(polygons.last).center.dx, closeTo(200, 1e-9));
    });

    test('perfect_freehand cannot draw a one-point dot, so it is not used', () {
      // What the library does with one point: a lopsided capsule, 1.5 times
      // the pen's width and off to the lower right.
      final lib = getStroke(const [PointVector(50, 50, 0.5)],
          options: StrokeOptions(
              size: 2,
              thinning: 0,
              smoothing: 0.2,
              streamline: 0,
              simulatePressure: false,
              isComplete: true));
      final b = boundsOf(lib);
      expect(b.width, greaterThan(2.5));
      expect((b.center - const Offset(50, 50)).distance, greaterThan(0.5));
      // Our dot is centred and round.
      final dot = strokeOutlines(
          strokeWith(const [InkPoint(50, 50, 0.5, 0)], style: LineStyle.dotted))
          .single;
      expect(boundsOf(dot).center.dx, closeTo(50, 1e-9));
      expect(boundsOf(dot).center.dy, closeTo(50, 1e-9));
      expect(boundsOf(dot).width, closeTo(2, 1e-9));
    });

    test('a big dot gets more sides so it stays round', () {
      final small = strokeOutlines(
              strokeWith(const [InkPoint(50, 50, 0.5, 0)], style: LineStyle.dotted, size: 1))
          .single;
      final big = strokeOutlines(
              strokeWith(const [InkPoint(50, 50, 0.5, 0)], style: LineStyle.dotted, size: 40))
          .single;
      expect(small.length, 12);
      expect(big.length, greaterThan(40));
      expect(big.length, lessThanOrEqualTo(64));
      // No side strays more than 0.05 pt from the true circle.
      for (var i = 0; i < big.length; i++) {
        final a = big[i], b = big[(i + 1) % big.length];
        final mid = (a + b) / 2;
        expect(20 - (mid - const Offset(50, 50)).distance, lessThan(0.051));
      }
    });
  });

  group('a tap with a line style', () {
    test('stays a round dot, whatever the style', () {
      for (final style in LineStyle.values.skip(1)) {
        final polygons = strokeOutlines(
            strokeWith(const [InkPoint(70, 80, 0.5, 0)], style: style, size: 4));
        expect(polygons, hasLength(1), reason: style.name);
        final b = boundsOf(polygons.single);
        expect(b.center.dx, closeTo(70, 1e-9), reason: style.name);
        expect(b.center.dy, closeTo(80, 1e-9), reason: style.name);
        expect(b.width, closeTo(4, 1e-9), reason: style.name);
        expect(b.height, closeTo(4, 1e-9), reason: style.name);
      }
    });

    test('a solid tap is still what perfect_freehand makes of it', () {
      final s = strokeWith(const [InkPoint(70, 80, 0.5, 0)], size: 4);
      expect(strokeOutlines(s), [oldOutline(s)]);
    });
  });

  group('wavy and zigzag', () {
    test('one polygon, as tall as the wave plus the pen', () {
      for (final style in [LineStyle.wavy, LineStyle.zigzag]) {
        final polygons = strokeOutlines(strokeWith(hLine(296), style: style));
        expect(polygons, hasLength(1), reason: style.name);
        // 4.96 pt peak to peak on the centre line, plus the pen's 2 pt. The
        // sharp peaks of a zigzag come out up to 0.2 pt per side blunter
        // (perfect_freehand pinches an outline at a corner).
        expect(boundsOf(polygons.single).height,
            closeTo(4.96 + 2, style == LineStyle.zigzag ? 0.4 : 0.12),
            reason: style.name);
        expect(boundsOf(polygons.single).left, closeTo(-1, 0.1));
        expect(boundsOf(polygons.single).right, closeTo(297, 0.1));
      }
    });

    test('the wave scales with the sliders and with the pen', () {
      final normal = strokeOutlines(strokeWith(hLine(296), style: LineStyle.wavy));
      final tall = strokeOutlines(
          strokeWith(hLine(296), style: LineStyle.wavy, waveHeight: 6.2));
      expect(boundsOf(tall.single).height,
          closeTo(2 * 4.96 + 2, 0.15));
      expect(boundsOf(tall.single).height, greaterThan(boundsOf(normal.single).height));
      final thick = strokeOutlines(
          strokeWith(hLine(296), style: LineStyle.wavy, size: 4));
      expect(boundsOf(thick.single).height, closeTo(2 * 4.96 + 4, 0.2));
    });

    test('the pen style does not matter: a pattern has one constant width', () {
      // (Outline points carry the input pressure, so compare positions.)
      List<List<Offset>> plain(Stroke s) => [
            for (final p in strokeOutlines(s))
              [for (final v in p) Offset(v.dx, v.dy)],
          ];
      final base = hLine(200, pressure: (x) => 0.1 + 0.9 * x / 200);
      for (final style in LineStyle.values.skip(1)) {
        final reference =
            plain(strokeWith(base, style: style, pen: PenStyle.technical));
        for (final pen in PenStyle.values) {
          expect(plain(strokeWith(base, style: style, pen: pen)), reference,
              reason: '${style.name} ${pen.name}');
        }
        // Not even the pressure changes it.
        expect(plain(strokeWith(hLine(200), style: style)), reference,
            reason: style.name);
      }
    });

    test('a ruler line (a shape) keeps its straight ends and has no smoothing', () {
      final line = strokeWith(hLine(100), style: LineStyle.wavy, shape: ShapeKind.line);
      final polygon = strokeOutlines(line).single;
      expect(boundsOf(polygon).left, closeTo(-1, 0.1));
      expect(boundsOf(polygon).right, closeTo(101, 0.1));
    });
  });

  group('double', () {
    test('two polygons, their centre lines 2.2 pen widths apart', () {
      final polygons = strokeOutlines(strokeWith(hLine(200), style: LineStyle.parallel));
      expect(polygons, hasLength(2));
      final upper = boundsOf(polygons[0]), lower = boundsOf(polygons[1]);
      expect((upper.center.dy - lower.center.dy).abs(), closeTo(4.4, 1e-6));
      expect(upper.height, closeTo(2, 0.05));
      expect(lower.height, closeTo(2, 0.05));
      // The whole double line, 4.4 + 2 pt wide.
      expect(allBounds(polygons).height, closeTo(6.4, 0.05));
      expect(upper.left, closeTo(-1, 0.05));
      expect(upper.right, closeTo(201, 0.05));
    });
  });

  group('every style', () {
    test('patterns ignore isComplete', () {
      for (final style in LineStyle.values.skip(1)) {
        final s = strokeWith(hLine(120), style: style);
        expect(strokeOutlines(s, isComplete: false), strokeOutlines(s),
            reason: style.name);
      }
    });

    test('fitPattern off keeps the nominal pitch and still draws', () {
      final s = strokeWith(hLine(100), style: LineStyle.dashed);
      final live = strokeOutlines(s, fitPattern: false);
      final fitted = strokeOutlines(s);
      expect(live, isNotEmpty);
      expect(live, isNot(fitted));
      // Nominal dashes: 6.8 pt long (8.8 with the caps) every 12.6 pt.
      expect(boundsOf(live[1]).left - boundsOf(live[0]).left, closeTo(12.6, 0.05));
      expect(boundsOf(live[0]).width, closeTo(8.8, 0.05));
    });

    test('every polygon is a usable, finite polygon', () {
      final rnd = math.Random(3);
      for (final style in LineStyle.values.skip(1)) {
        for (final pen in [PenStyle.ballpoint, PenStyle.technical]) {
          for (final tool in StrokeTool.values) {
            final pts = [
              for (var i = 0; i < 120; i++)
                InkPoint(20 + i * 2.5, 300 + 25 * math.sin(i / 9) + rnd.nextDouble(),
                    rnd.nextDouble(), i * 7),
            ];
            final polygons = strokeOutlines(strokeWith(pts,
                style: style, pen: pen, tool: tool, size: tool == StrokeTool.pen ? 2 : 14));
            expect(polygons, isNotEmpty, reason: '${style.name} ${tool.name}');
            for (final p in polygons) {
              expect(p.length, greaterThanOrEqualTo(3));
              for (final v in p) {
                expect(v.dx.isFinite && v.dy.isFinite, isTrue);
              }
            }
          }
        }
      }
    });

    test('a pen that is not a positive width draws nothing', () {
      for (final bad in [0.0, -2.0, double.nan, double.infinity]) {
        expect(
            strokeOutlines(strokeWith(hLine(100), style: LineStyle.dashed, size: bad)),
            isEmpty,
            reason: '$bad');
      }
    });

    test('the fill colour carries the concentration and the tool\'s opacity', () {
      final pen = strokeWith(hLine(50), concentration: 0.5, color: 0xFF336699);
      expect(strokeFillColor(pen).a, closeTo(0.5, 1e-9));
      expect(strokeFillArgb(pen) >>> 24, closeTo(128, 1));
      expect(strokeFillArgb(pen) & 0xFFFFFF, 0x336699);
      final opaque = strokeWith(hLine(50), color: 0xFF336699);
      expect(strokeFillArgb(opaque) >>> 24, 255);
      final pencil = strokeWith(hLine(50),
          pen: PenStyle.pencil, concentration: 0.5, color: 0xFF336699);
      expect(strokeFillColor(pencil).a, closeTo(0.85 * 0.5, 1e-9));
      final hl = strokeWith(hLine(50),
          tool: StrokeTool.highlighter, concentration: 0.5, color: 0xFFFFE600);
      expect(strokeFillColor(hl).a, closeTo(highlighterOpacity * 0.5, 1e-9));
      // A translucent colour keeps its own alpha too.
      final half = strokeWith(hLine(50), concentration: 0.5, color: 0x80336699);
      expect(strokeFillColor(half).a, closeTo(0.5 * 0.5, 0.01));
    });
  });

  group('caches and paths', () {
    test('cachedStrokeOutlines is computed once per stroke instance', () {
      final s = strokeWith(hLine(100), style: LineStyle.dashed);
      expect(identical(cachedStrokeOutlines(s), cachedStrokeOutlines(s)), isTrue);
      final copy = s.copyWith(color: 0xFF000000);
      expect(identical(cachedStrokeOutlines(copy), cachedStrokeOutlines(s)),
          isFalse);
      expect(cachedStrokeOutlines(copy), cachedStrokeOutlines(s));
    });

    test('a restyled stroke is outlined afresh', () {
      final s = strokeWith(hLine(100), style: LineStyle.dashed);
      final wavy = s.copyWith(line: const LineSettings(style: LineStyle.wavy));
      expect(cachedStrokeOutlines(wavy), hasLength(1));
      expect(cachedStrokeOutlines(s).length, greaterThan(3));
    });

    test('cachedStrokePath holds every polygon, filled non-zero', () {
      final s = strokeWith(hLine(200), style: LineStyle.dashed);
      final path = cachedStrokePath(s);
      expect(path.fillType, PathFillType.nonZero);
      expect(path.computeMetrics().length, strokeOutlines(s).length);
      expect(identical(path, cachedStrokePath(s)), isTrue);
      final all = allBounds(strokeOutlines(s));
      final box = path.getBounds();
      expect(box.left, closeTo(all.left, 1e-3));
      expect(box.right, closeTo(all.right, 1e-3));
      expect(box.top, closeTo(all.top, 1e-3));
      expect(box.bottom, closeTo(all.bottom, 1e-3));
    });

    test('outlinesPath skips anything with fewer than three points', () {
      final path = outlinesPath([
        const [Offset(0, 0), Offset(1, 1)],
        const [Offset(0, 0), Offset(10, 0), Offset(10, 10)],
      ]);
      expect(path.computeMetrics().length, 1);
    });

    test('the painted area stays inside paintBounds', () {
      final rnd = math.Random(1);
      for (final style in LineStyle.values) {
        final pts = [
          for (var i = 0; i < 100; i++)
            InkPoint(30 + i * 3.0, 200 + 40 * math.sin(i / 8) + rnd.nextDouble(), 0.5, i),
        ];
        final s = strokeWith(pts, style: style, size: 3, waveHeight: 5);
        final box = s.paintBounds;
        for (final p in strokeOutlines(s).expand((e) => e)) {
          expect(p.dx, inInclusiveRange(box.left, box.right), reason: style.name);
          expect(p.dy, inInclusiveRange(box.top, box.bottom), reason: style.name);
        }
      }
    });
  });

  group('patternPolylines agrees with the outlines', () {
    test('there is one polygon per mark', () {
      for (final style in LineStyle.values.skip(1)) {
        final s = strokeWith(hLine(150), style: style);
        final marks = patternPolylines(s.points, s.line, s.size, smooth: true);
        expect(strokeOutlines(s), hasLength(marks.length), reason: style.name);
      }
    });
  });
}
