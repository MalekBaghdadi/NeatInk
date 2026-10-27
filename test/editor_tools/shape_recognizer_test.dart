import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/tools/geometry.dart';
import 'package:neatink/features/editor/tools/shape_geometry.dart';
import 'package:neatink/features/editor/tools/shape_recognizer.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';

/// A hand-drawn-looking stroke along [vertices]: points about [spacing]
/// apart with white noise and a slow wobble, 8 ms apart.
List<InkPoint> handDrawn(
  List<Vec2> vertices, {
  double spacing = 2.5,
  double sigma = 0.5,
  double wobble = 0.8,
  int seed = 1,
}) {
  final rng = math.Random(seed);
  final dense = densifyPolyline(vertices, spacing);
  final phase = rng.nextDouble() * 6;
  return [
    for (var i = 0; i < dense.length; i++)
      InkPoint(
        dense[i].x +
            (rng.nextDouble() - 0.5) * 2 * sigma +
            wobble * math.sin(i / 9 + phase),
        dense[i].y +
            (rng.nextDouble() - 0.5) * 2 * sigma +
            wobble * math.cos(i / 11 + phase),
        0.5,
        i * 8,
      ),
  ];
}

List<Vec2> ellipseVertices(Vec2 c, double a, double b,
    {double theta = 0, double sweep = 2 * math.pi, double t0 = 0, int n = 120}) {
  return [
    for (var i = 0; i <= n; i++)
      c +
          Vec2(a * math.cos(t0 + sweep * i / n), b * math.sin(t0 + sweep * i / n))
              .rotate(theta),
  ];
}

List<Vec2> rotatedRect(Vec2 c, double w, double h, double theta,
    {bool close = true}) {
  final corners = [
    Vec2(-w / 2, -h / 2),
    Vec2(w / 2, -h / 2),
    Vec2(w / 2, h / 2),
    Vec2(-w / 2, h / 2),
  ];
  return [
    for (final p in corners) c + p.rotate(theta),
    if (close) c + corners.first.rotate(theta),
  ];
}

ShapeKind? kindOf(List<InkPoint> pts) => recognizeShape(pts)?.kind;

double distanceToOutline(Vec2 p, List<Vec2> outline) {
  var best = double.infinity;
  for (var i = 1; i < outline.length; i++) {
    best = math.min(best, distanceToSegment(p, outline[i - 1], outline[i]));
  }
  return best;
}

void main() {
  group('lines', () {
    test('a roughly horizontal line snaps to a horizontal segment', () {
      final s = recognizeShape(
          handDrawn([const Vec2(50, 100), const Vec2(250, 107)]))!;
      expect(s.kind, ShapeKind.line);
      expect(s.segmentStart.distanceTo(const Vec2(50, 100)), lessThan(4));
      // 7pt over 200pt is 2°: snaps to exactly horizontal.
      expect(s.segmentStart.y, closeTo(s.segmentEnd.y, 1e-6));
    });

    test('a 30 degree line keeps its angle', () {
      final end = const Vec2(50, 50) + const Vec2(200, 0).rotate(math.pi / 6);
      final s = recognizeShape(handDrawn([const Vec2(50, 50), end]))!;
      expect(s.kind, ShapeKind.line);
      final d = s.segmentEnd - s.segmentStart;
      expect(math.atan2(d.y, d.x), closeTo(math.pi / 6, 0.04));
    });

    test('a nearly 45 degree line snaps to 45 degrees', () {
      final end = const Vec2(50, 50) + const Vec2(180, 0).rotate(0.79);
      final s = recognizeShape(handDrawn([const Vec2(50, 50), end]))!;
      final d = s.segmentEnd - s.segmentStart;
      expect(math.atan2(d.y, d.x), closeTo(math.pi / 4, 1e-9));
    });

    test('a short line is still a line, a tick is not', () {
      expect(kindOf(handDrawn([const Vec2(0, 0), const Vec2(30, 0)])),
          ShapeKind.line);
      expect(kindOf(handDrawn([const Vec2(0, 0), const Vec2(6, 0)])), isNull);
    });

    test('the dwell at the end of the stroke is ignored', () {
      final pts = handDrawn([const Vec2(50, 100), const Vec2(250, 100)]);
      final last = pts.last;
      final rng = math.Random(4);
      // The pen rests 700 ms with 1pt tremor: the hold itself.
      for (var i = 1; i <= 80; i++) {
        pts.add(InkPoint(last.x + rng.nextDouble() * 1 - 0.5,
            last.y + rng.nextDouble() * 1 - 0.5, 0.5, last.t + i * 9));
      }
      final s = recognizeShape(pts)!;
      expect(s.kind, ShapeKind.line);
      expect(s.segmentEnd.x, closeTo(250, 3));
    });
  });

  group('arrows', () {
    List<Vec2> arrow(Vec2 tail, Vec2 tip, {int side = 1, double barb = 24}) =>
        arrowOutline(tail, tip, barb, 0.5, firstBarbSide: side);

    test('shaft with two barbs is an arrow pointing at the tip', () {
      final s = recognizeShape(
          handDrawn(arrow(const Vec2(40, 200), const Vec2(300, 200))))!;
      expect(s.kind, ShapeKind.arrow);
      expect(s.segmentStart.distanceTo(const Vec2(40, 200)), lessThan(5));
      expect(s.segmentEnd.distanceTo(const Vec2(300, 200)), lessThan(5));
    });

    test('works for either barb first and for a diagonal arrow', () {
      for (final side in [1, -1]) {
        final s = recognizeShape(handDrawn(
            arrow(const Vec2(40, 40), const Vec2(220, 190), side: side),
            seed: 3 + side))!;
        expect(s.kind, ShapeKind.arrow, reason: 'side $side');
        expect(s.segmentEnd.distanceTo(const Vec2(220, 190)), lessThan(6));
      }
    });

    test('the output is a clean tail-tip-barb-tip-barb outline', () {
      final s = recognizeShape(
          handDrawn(arrow(const Vec2(40, 200), const Vec2(300, 200))))!;
      expect(s.outline.length, 5);
      expect(s.outline[1].distanceTo(s.outline[3]), lessThan(1e-9));
    });

    test('a plain line with a small hook is not an arrow', () {
      final v = [const Vec2(0, 0), const Vec2(200, 0), const Vec2(200, 40)];
      expect(kindOf(handDrawn(v)), isNull);
    });
  });

  group('rectangles', () {
    test('an axis-aligned rectangle snaps exactly axis-aligned', () {
      final v = rotatedRect(const Vec2(200, 200), 180, 100, 0.03);
      final s = recognizeShape(handDrawn(v))!;
      expect(s.kind, ShapeKind.rectangle);
      expect(s.outline.length, 5);
      for (var i = 0; i < 4; i++) {
        final a = s.outline[i], b = s.outline[i + 1];
        expect(a.x == b.x || a.y == b.y, isTrue, reason: 'side $i');
      }
      final xs = s.outline.map((p) => p.x);
      expect(xs.reduce(math.min), closeTo(110, 4));
      expect(xs.reduce(math.max), closeTo(290, 4));
    });

    test('a rotated rectangle stays rotated', () {
      final v = rotatedRect(const Vec2(250, 250), 200, 100, 0.5);
      final s = recognizeShape(handDrawn(v, seed: 2))!;
      expect(s.kind, ShapeKind.rectangle);
      final truth = rotatedRect(const Vec2(250, 250), 200, 100, 0.5);
      for (final c in s.outline) {
        expect(distanceToOutline(c, truth), lessThan(5));
      }
      final d = s.outline[1] - s.outline[0];
      expect(math.atan2(d.y, d.x).abs() % (math.pi / 2),
          isNot(closeTo(0, 0.1)));
    });

    test('closing with an overshoot or a small gap still works', () {
      final over = [
        ...rotatedRect(const Vec2(200, 200), 160, 90, 0, close: true),
        const Vec2(200 - 80 + 14, 200 - 45), // overshoot along the top edge
      ];
      expect(kindOf(handDrawn(over)), ShapeKind.rectangle);
      final gap = rotatedRect(const Vec2(200, 200), 160, 90, 0, close: false);
      gap.add(gap.first + const Vec2(0, 14));
      expect(kindOf(handDrawn(gap)), ShapeKind.rectangle);
    });

    test('the drawing direction and start corner are kept', () {
      final cw = rotatedRect(const Vec2(200, 200), 160, 90, 0);
      final ccw = cw.reversed.toList();
      final a = recognizeShape(handDrawn(cw))!;
      final b = recognizeShape(handDrawn(ccw))!;
      expect(a.outline.first.distanceTo(const Vec2(120, 155)), lessThan(5));
      expect(b.outline.first.distanceTo(const Vec2(120, 155)), lessThan(5));
      expect(signedPolygonArea(a.outline.sublist(0, 4)) *
              signedPolygonArea(b.outline.sublist(0, 4)),
          lessThan(0));
    });

    test('a square with rounded corners is a rectangle', () {
      // Corner cut: each corner replaced by a short diagonal.
      const c = 12.0;
      final v = <Vec2>[
        const Vec2(100 + c, 100), const Vec2(300 - c, 100),
        const Vec2(300, 100 + c), const Vec2(300, 300 - c),
        const Vec2(300 - c, 300), const Vec2(100 + c, 300),
        const Vec2(100, 300 - c), const Vec2(100, 100 + c),
        const Vec2(100 + c, 100),
      ];
      expect(kindOf(handDrawn(v)), ShapeKind.rectangle);
    });
  });

  group('ellipses', () {
    test('a circle becomes an ellipse with equal axes', () {
      final s = recognizeShape(handDrawn(
          ellipseVertices(const Vec2(200, 200), 80, 80, t0: 1)))!;
      expect(s.kind, ShapeKind.ellipse);
      expect(s.center.distanceTo(const Vec2(200, 200)), lessThan(3));
      for (final p in s.outline) {
        expect(p.distanceTo(s.center), closeTo(80, 3));
      }
      // Starts where the stroke started.
      expect(s.outline.first.distanceTo(
              const Vec2(200, 200) + Vec2(80 * math.cos(1), 80 * math.sin(1))),
          lessThan(6));
    });

    test('a slightly oval circle is still a circle', () {
      final s = recognizeShape(handDrawn(
          ellipseVertices(const Vec2(200, 200), 80, 72)))!;
      final radii = [for (final p in s.outline) p.distanceTo(s.center)];
      expect(radii.reduce(math.max) - radii.reduce(math.min), lessThan(0.1));
    });

    test('an axis-aligned ellipse stays elongated and snaps to the axes', () {
      final s = recognizeShape(handDrawn(
          ellipseVertices(const Vec2(250, 200), 120, 55, theta: 0.04)))!;
      expect(s.kind, ShapeKind.ellipse);
      final xs = s.outline.map((p) => p.x), ys = s.outline.map((p) => p.y);
      expect(xs.reduce(math.max) - xs.reduce(math.min), closeTo(240, 6));
      expect(ys.reduce(math.max) - ys.reduce(math.min), closeTo(110, 6));
      expect(s.outline.first.y == s.outline.last.y, isTrue);
    });

    test('a tilted ellipse keeps its tilt', () {
      final s = recognizeShape(handDrawn(
          ellipseVertices(const Vec2(250, 250), 120, 50, theta: 0.7),
          seed: 5))!;
      expect(s.kind, ShapeKind.ellipse);
      final truth = ellipseVertices(const Vec2(250, 250), 120, 50, theta: 0.7);
      for (final p in s.outline) {
        expect(distanceToOutline(p, truth), lessThan(5));
      }
    });

    test('an almost closed circle (gap) and counter-clockwise both work', () {
      final gap = ellipseVertices(const Vec2(200, 200), 80, 80,
          sweep: 2 * math.pi * 0.95);
      expect(kindOf(handDrawn(gap)), ShapeKind.ellipse);
      final ccw = ellipseVertices(const Vec2(200, 200), 80, 80, sweep: -2 * math.pi);
      expect(kindOf(handDrawn(ccw)), ShapeKind.ellipse);
    });
  });

  group('triangles', () {
    test('a triangle is recognized with its corners', () {
      const a = Vec2(200, 100), b = Vec2(320, 280), c = Vec2(80, 280);
      final s = recognizeShape(handDrawn([a, b, c, a]))!;
      expect(s.kind, ShapeKind.triangle);
      expect(s.outline.length, 4);
      for (final corner in [a, b, c]) {
        expect(s.outline.map((p) => p.distanceTo(corner)).reduce(math.min),
            lessThan(8));
      }
    });

    test('a skewed triangle drawn from a base corner', () {
      const a = Vec2(60, 260), b = Vec2(300, 270), c = Vec2(140, 90);
      expect(kindOf(handDrawn([a, b, c, a], seed: 8)), ShapeKind.triangle);
    });
  });

  group('no confident match', () {
    test('cursive handwriting', () {
      // A wave with loops: "ellell".
      final pts = <Vec2>[];
      for (var i = 0; i < 400; i++) {
        final t = i / 400 * 6 * math.pi;
        pts.add(Vec2(40 + t * 12 + 14 * math.sin(2 * t), 100 + 18 * math.cos(t)));
      }
      expect(kindOf(handDrawn(pts, spacing: 2)), isNull);
    });

    test('a spiral', () {
      final pts = <Vec2>[];
      for (var i = 0; i <= 300; i++) {
        final t = i / 300 * 5 * math.pi;
        final r = 8 + 9 * t;
        pts.add(Vec2(200 + r * math.cos(t), 200 + r * math.sin(t)));
      }
      expect(kindOf(handDrawn(pts, spacing: 2)), isNull);
    });

    test('an inward spiral that ends at the centre', () {
      final pts = <Vec2>[];
      for (var i = 0; i <= 300; i++) {
        final t = i / 300 * 5 * math.pi;
        final r = 100 - 6 * t;
        pts.add(Vec2(200 + r * math.cos(t), 200 + r * math.sin(t)));
      }
      expect(kindOf(handDrawn(pts, spacing: 2)), isNull);
    });

    test('a zigzag', () {
      final v = [
        for (var i = 0; i < 9; i++) Vec2(40.0 + i * 25, i.isEven ? 100 : 140),
      ];
      expect(kindOf(handDrawn(v)), isNull);
    });

    test('a closed zigzag / scribble', () {
      final rng = math.Random(11);
      final v = [
        for (var i = 0; i < 14; i++)
          Vec2(100 + rng.nextDouble() * 120, 100 + rng.nextDouble() * 120),
      ];
      v.add(v.first);
      expect(kindOf(handDrawn(v)), isNull);
    });

    test('a circle drawn twice (double loop)', () {
      final v = ellipseVertices(const Vec2(200, 200), 70, 70,
          sweep: 4 * math.pi, n: 240);
      expect(kindOf(handDrawn(v)), isNull);
    });

    test('a figure eight', () {
      final v = [
        for (var i = 0; i <= 160; i++)
          Vec2(200 + 90 * math.sin(i / 160 * 2 * math.pi),
              200 + 50 * math.sin(i / 160 * 4 * math.pi)),
      ];
      expect(kindOf(handDrawn(v)), isNull);
    });

    test('a pentagon', () {
      final v = [
        for (var i = 0; i <= 5; i++)
          Vec2(200 + 90 * math.cos(i * 2 * math.pi / 5 - 1.2),
              200 + 90 * math.sin(i * 2 * math.pi / 5 - 1.2)),
      ];
      expect(kindOf(handDrawn(v)), isNull);
    });

    test('an L, a V and a C', () {
      expect(
          kindOf(handDrawn(
              [const Vec2(0, 0), const Vec2(0, 90), const Vec2(60, 90)])),
          isNull);
      expect(
          kindOf(handDrawn(
              [const Vec2(0, 0), const Vec2(40, 90), const Vec2(80, 0)])),
          isNull);
      expect(
          kindOf(handDrawn(ellipseVertices(const Vec2(100, 100), 60, 60,
              sweep: 1.5 * math.pi, t0: 0.6))),
          isNull);
    });

    test('a letter-sized o stays a letter', () {
      expect(
          kindOf(handDrawn(ellipseVertices(const Vec2(100, 100), 4, 4),
              spacing: 1, sigma: 0.2, wobble: 0.2)),
          isNull);
    });

    test('too little ink and non-finite input', () {
      expect(recognizeShape(const []), isNull);
      expect(recognizeShape(const [InkPoint(1, 1, 0.5, 0)]), isNull);
      expect(
          recognizeShape(const [
            InkPoint(double.nan, 1, 0.5, 0),
            InkPoint(5, 5, 0.5, 8),
          ]),
          isNull);
    });
  });

  group('robustness over many noisy samples', () {
    test('every circle, rectangle and line across seeds is recognized', () {
      for (var seed = 0; seed < 25; seed++) {
        final rng = math.Random(seed);
        final c = Vec2(150 + rng.nextDouble() * 200, 150 + rng.nextDouble() * 200);
        final r = 40 + rng.nextDouble() * 80;
        expect(
            kindOf(handDrawn(ellipseVertices(c, r, r, t0: rng.nextDouble() * 6),
                seed: seed)),
            ShapeKind.ellipse,
            reason: 'circle seed $seed');
        expect(
            kindOf(handDrawn(
                rotatedRect(c, 80 + rng.nextDouble() * 120,
                    50 + rng.nextDouble() * 60, rng.nextDouble() * 3),
                seed: seed)),
            ShapeKind.rectangle,
            reason: 'rect seed $seed');
        expect(
            kindOf(handDrawn(
                [c, c + Vec2(60 + rng.nextDouble() * 150, 0).rotate(rng.nextDouble() * 6)],
                seed: seed)),
            ShapeKind.line,
            reason: 'line seed $seed');
      }
    });
  });

  group('RecognizedShape', () {
    test('toResult carries the source times and constant pressure', () {
      final src = handDrawn([const Vec2(50, 100), const Vec2(250, 100)]);
      final s = recognizeShape(src)!;
      final r = s.toResult(src);
      expect(r.kind, ShapeKind.line);
      expect(r.points.first.t, src.first.t);
      expect(r.points.last.t, src.last.t);
      expect(r.points.every((p) => p.pressure == 0.5), isTrue);
    });

    test('a line end follows the pen', () {
      final s = recognizeShape(
          handDrawn([const Vec2(50, 100), const Vec2(250, 100)]))!;
      final moved = s.resizedTo(s.segmentEnd, const Vec2(250, 180));
      expect(moved.kind, ShapeKind.line);
      expect(moved.segmentStart, s.segmentStart);
      expect(moved.segmentEnd.distanceTo(const Vec2(250, 180)), lessThan(1e-9));
    });

    test('an arrow keeps its head while its end follows the pen', () {
      final s = recognizeShape(handDrawn(
          arrowOutline(const Vec2(40, 200), const Vec2(300, 200), 24, 0.5)))!;
      final moved = s.resizedTo(s.segmentEnd, const Vec2(340, 200));
      expect(moved.kind, ShapeKind.arrow);
      // The 45-degree snap may nudge the end a fraction of a point.
      expect(moved.segmentEnd.distanceTo(const Vec2(340, 200)), lessThan(0.5));
      expect(moved.outline.length, 5);
      expect(moved.outline[2].distanceTo(moved.segmentEnd), greaterThan(20));
    });

    test('a closed shape scales about its centre through the pen', () {
      final s = recognizeShape(handDrawn(
          ellipseVertices(const Vec2(200, 200), 80, 80)))!;
      final pen = s.outline.last;
      final out = pen + (pen - s.center).normalized() * 40;
      final big = s.resizedTo(pen, out);
      expect(big.center, s.center);
      expect(big.outline.first.distanceTo(big.center), closeTo(120, 4));
      final small = s.resizedTo(pen, s.center + (pen - s.center) * 0.5);
      expect(small.outline.first.distanceTo(s.center), closeTo(40, 3));
    });
  });
}
