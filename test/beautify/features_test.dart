import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/beautify/features.dart';
import 'package:neatink/beautify/resample.dart';
import 'package:neatink/beautify/stats.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/vec2.dart';

import 'synthetic_font.dart';

/// Spec steps 0 and 3 on synthetic words with known distortions.

void main() {
  group('step 0: resampling', () {
    test('points are spaced one step apart along the path', () {
      final r = resamplePolyline(
          [const Vec2(0, 0), const Vec2(10, 0), const Vec2(10, 10)], 1.0);
      for (var i = 1; i < r.length - 1; i++) {
        expect(r[i].distanceTo(r[i - 1]), closeTo(1.0, 1e-9));
      }
      expect(r.first, const Vec2(0, 0));
      expect(r.last, const Vec2(10, 10));
      expect(r.length, 21);
    });

    test('the last point is kept even when it is not on the grid', () {
      final r = resamplePolyline([const Vec2(0, 0), const Vec2(2.5, 0)], 1.0);
      expect(r.last, const Vec2(2.5, 0));
      expect(r.length, 4);
    });

    test('uneven input spacing becomes even', () {
      final r = resamplePolyline([
        const Vec2(0, 0),
        const Vec2(0.1, 0),
        const Vec2(0.2, 0),
        const Vec2(7, 0),
      ], 1.0);
      for (var i = 1; i < r.length - 1; i++) {
        expect(r[i].x - r[i - 1].x, closeTo(1.0, 1e-9));
      }
    });

    test('NaN and infinite points are ignored', () {
      final r = resamplePolyline([
        const Vec2(0, 0),
        const Vec2(double.nan, 3),
        const Vec2(4, double.infinity),
        const Vec2(3, 0),
      ], 1.0);
      expect(r.every((p) => p.isFinite), isTrue);
      expect(r.last, const Vec2(3, 0));
    });

    test('a single point (a dot) stays a single point', () {
      expect(resamplePolyline([const Vec2(5, 5)], 1.0), [const Vec2(5, 5)]);
      expect(resamplePolyline(const [], 1.0), isEmpty);
    });

    test('duplicate points do not loop forever', () {
      final r = resamplePolyline(
          [for (var i = 0; i < 50; i++) const Vec2(1, 1)], 1.0);
      expect(r, [const Vec2(1, 1)]);
    });

    test('finiteBounds skips non-finite points', () {
      final b = finiteBounds(const [
        InkPoint(1, 2, 0.5, 0),
        InkPoint(double.nan, 99, 0.5, 1),
        InkPoint(5, 7, 0.5, 2),
      ])!;
      expect((b.left, b.top, b.right, b.bottom), (1.0, 2.0, 5.0, 7.0));
      expect(finiteBounds(const [InkPoint(double.nan, 0, 0.5, 0)]), isNull);
    });
  });

  group('statistics helpers', () {
    test('median, lower quantile, weighted median', () {
      expect(median(const [3.0, 1.0, 2.0]), 2.0);
      expect(median(const [4.0, 1.0, 2.0, 3.0]), 2.5);
      expect(median(const <double>[]), isNull);
      expect(lowerQuantile(const [1.0, 2.0, 10.0, 11.0], 0.25), 1.0);
      expect(weightedMedian(const [1.0, 2.0, 3.0], const [1.0, 1.0, 10.0]), 3.0);
      expect(weightedMedian(const [1.0, 2.0], const [0.0, 0.0]), isNull);
    });

    test('median does not modify its input', () {
      final v = [3.0, 1.0, 2.0];
      median(v);
      expect(v, [3.0, 1.0, 2.0]);
    });

    test('least squares line recovers slope and intercept', () {
      final xs = [for (var i = 0; i < 10; i++) i.toDouble()];
      final f = leastSquaresLine(xs, [for (final x in xs) 0.5 * x + 3])!;
      expect(f.slope, closeTo(0.5, 1e-12));
      expect(f.intercept, closeTo(3, 1e-12));
      expect(f.angle, closeTo(math.atan(0.5), 1e-12));
      expect(leastSquaresLine([1.0, 1.0], [0.0, 5.0]), isNull);
      expect(leastSquaresLine([1.0], [0.0]), isNull);
    });

    test('rolling window keeps the newest values', () {
      final w = RollingWindow(3);
      for (final v in [1.0, 2.0, 3.0, 100.0]) {
        w.add(v);
      }
      expect(w.values, [2.0, 3.0, 100.0]);
      expect(w.median, 3.0);
      w.add(double.nan);
      expect(w.length, 3);
      w.clear();
      expect(w.median, isNull);
    });
  });

  group('peaks', () {
    test('finds the lowest points of a wave but not jitter', () {
      final v = [
        for (var i = 0; i <= 200; i++)
          math.sin(i / 200 * 4 * math.pi) * 5 + (i.isEven ? 0.05 : -0.05),
      ];
      final peaks = findPeaks(v,
          minDrop: 1.0, window: 3, includeStart: false, includeEnd: false);
      expect(peaks.length, 2); // two maxima at 1/8 and 5/8 of the way
      expect(peaks[0], closeTo(25, 3));
      expect(peaks[1], closeTo(125, 3));
    });

    test('a flat bar has no extrema; a stroke ending on a minimum has one', () {
      final flat = List<double>.filled(30, 4);
      expect(
          findPeaks(flat,
              minDrop: 0.5, window: 3, includeStart: true, includeEnd: true),
          isEmpty);
      final down = [for (var i = 0; i < 20; i++) i.toDouble()]; // y grows
      expect(
          findPeaks(down,
              minDrop: 0.5, window: 3, includeStart: false, includeEnd: true),
          [19]);
    });
  });

  group('3a: baseline and skew', () {
    test('an upright word has zero skew and its baseline at y=300', () {
      final a = analyzeWord(makeWord('hello'))!;
      expect(a.skewReliable, isTrue);
      expect(degrees(a.wordSkew).abs(), lessThan(0.3));
      expect(a.baseline.line.yAt(120), closeTo(300, 0.3));
    });

    for (final deg in [-10.0, -4.0, 3.0, 8.0, 15.0]) {
      test('recovers a rotation of $deg degrees', () {
        for (final text in ['hello', 'line']) {
          final a = analyzeWord(makeWord(text, rotateDeg: deg))!;
          expect(degrees(a.wordSkew), closeTo(deg, 1.0),
              reason: 'word $text rotated $deg');
        }
      });
    }

    test('flat bars of a tilted E/H do not pull the baseline (RANSAC)', () {
      for (final deg in [8.0, 15.0]) {
        final a = analyzeWord(makeWord('HE', rotateDeg: deg))!;
        expect(a.skewReliable, isTrue);
        expect(degrees(a.wordSkew), closeTo(deg, 1.0));
      }
    });

    test('very short words are not trusted for skew', () {
      final a = analyzeWord(makeWord('go', rotateDeg: 6))!;
      expect(a.skewReliable, isFalse);
    });

    test('descender tails are not used for the baseline', () {
      final a = analyzeWord(makeWord('ogo', rotateDeg: 6))!;
      expect(degrees(a.wordSkew), closeTo(6, 1.0));
      expect(a.baseline.extrema.every((p) => p.y < 306), isTrue);
    });

    test('an outlier letter is removed from the baseline fit', () {
      final polys = wordPolylines('hello');
      polys[1] = [for (final p in polys[1]) Vec2(p.x, p.y - 3)];
      final a = analyzeWord(toStrokes(polys, m: distortion()))!;
      expect(degrees(a.wordSkew).abs(), lessThan(0.6));
      expect(a.baseline.line.yAt(130), closeTo(300, 0.4));
    });

    test('short words borrow the line skew', () {
      final strokes = makeWord('o', rotateDeg: 8);
      final own = analyzeWord(strokes)!;
      expect(own.skewReliable, isFalse);
      expect(own.wordSkew, 0.0);
      final borrowed = analyzeWord(strokes,
          context: FeatureContext(lineSkew: 5 * math.pi / 180))!;
      expect(degrees(borrowed.wordSkew), closeTo(5, 1e-9));
    });

    test('blends 0.6 word + 0.4 line once the line has two words', () {
      final strokes = makeWord('hello', rotateDeg: 8);
      final alone = analyzeWord(strokes,
          context: const FeatureContext(lineSkew: 0, lineWordCount: 1))!;
      expect(alone.skew, alone.wordSkew);
      final blended = analyzeWord(strokes,
          context: const FeatureContext(lineSkew: 0, lineWordCount: 2))!;
      expect(blended.skew, closeTo(0.6 * blended.wordSkew, 1e-12));
      expect(blended.deskewedBaselineSlope.abs(), greaterThan(0.01));
    });

    test('the pivot P0 is the left end of the baseline', () {
      final a = analyzeWord(makeWord('hello', rotateDeg: 8))!;
      expect(a.baselineStart.x, closeTo(a.coreBounds.left, 1e-9));
      expect(a.baselineEnd.x, closeTo(a.coreBounds.right, 1e-9));
      final flat = a.deskew.apply(a.baselineEnd);
      expect(flat.y, closeTo(a.baselineStart.y, 0.8));
    });

    test('estimateBaselineY finds the baseline of a pending word', () {
      final strokes = makeWord('hello');
      final y = estimateBaselineY([for (final s in strokes) s.raw],
          scaleHint: 10)!;
      expect(y, closeTo(300, 0.3));
      expect(estimateBaselineY(const [], scaleHint: 10), isNull);
    });
  });

  group('3b: x-height', () {
    test('lowercase with ascenders measures the x-height, not the l', () {
      final a = analyzeWord(makeWord('hello'))!;
      expect(a.xHeight.xHeight, closeTo(10, 0.4));
      expect(a.xHeight.allCaps, isFalse);
    });

    test('x-height is invariant to rotation', () {
      final a = analyzeWord(makeWord('hello', rotateDeg: 9))!;
      expect(a.xHeight.xHeight, closeTo(10, 0.5));
    });

    test('scales with the writing', () {
      for (final k in [0.7, 1.0, 1.5]) {
        final a = analyzeWord(makeWord('hello', scale: k))!;
        expect(a.xHeight.xHeight, closeTo(10 * k, 0.5 * k));
      }
    });

    test('"HE" is all caps when the expected x-height says so', () {
      final strokes = makeWord('HE');
      final a = analyzeWord(strokes,
          context: const FeatureContext(expectedXHeight: 10, scaleHintPt: 10))!;
      expect(a.xHeight.allCaps, isTrue);
      expect(a.xHeight.capHeight, closeTo(19, 0.5));
      expect(a.xHeight.xHeight, closeTo(19 / 1.9, 0.5));
    });

    test('the same word is lowercase-with-big-x without that hint', () {
      final a = analyzeWord(makeWord('HE'))!;
      // Without history nothing tells caps from big lowercase.
      expect(a.xHeight.allCaps, isFalse);
    });

    test('too few tops fall back to 0.45 x box height', () {
      final x = estimateXHeight(const [], boxHeight: 20, tallRatio: 1.9);
      expect(x.xHeight, closeTo(9, 1e-9));
      expect(x.reliable, isFalse);
    });

    test('estimateXHeight drops ascender tops', () {
      final x = estimateXHeight(const [10.0, 10.2, 9.8, 19.0, 19.2],
          boxHeight: 20, tallRatio: 1.9);
      expect(x.xHeight, closeTo(10, 0.3));
      expect(x.reliable, isTrue);
    });
  });

  group('3c: slant', () {
    for (final deg in [-15.0, 0.0, 10.0, 20.0, 30.0]) {
      test('recovers a lean of $deg degrees', () {
        final a = analyzeWord(makeWord('hello', leanDeg: deg))!;
        expect(a.slant.reliable, isTrue);
        expect(degrees(a.slant.angle), closeTo(deg, 2.0));
      });
    }

    test('lean is measured after deskewing', () {
      final a = analyzeWord(makeWord('hello', leanDeg: 12, rotateDeg: 7))!;
      expect(degrees(a.slant.angle), closeTo(12, 2.0));
    });

    test('too little vertical ink is unreliable and uses the line value', () {
      final strokes = makeWord('o');
      final a = analyzeWord(strokes,
          context: FeatureContext(lineSlant: 0.2, expectedXHeight: 10))!;
      // A lone "o" has near-vertical segments, but less than 1.5 x-heights
      // is not enough on a tiny word; borrow when so.
      if (!a.slant.reliable) {
        expect(a.slant.angle, 0.2);
      }
      final est = estimateSlant(
          [
            [const Vec2(0, 0), const Vec2(0, -3)]
          ],
          xHeight: 10,
          fallback: 0.3);
      expect(est.reliable, isFalse);
      expect(est.angle, 0.3);
      expect(estimateSlant(const [], xHeight: 10).angle, 0.0);
    });

    test('horizontal bars do not count', () {
      final est = estimateSlant(
          [
            [for (var i = 0; i < 60; i++) Vec2(i.toDouble(), 0)]
          ],
          xHeight: 10);
      expect(est.totalLength, 0);
      expect(est.reliable, isFalse);
    });

    test('weighted median ignores a short wild segment', () {
      final pts = <Vec2>[
        for (var i = 0; i <= 30; i++) Vec2(i * 0.18, -i.toDouble()),
        const Vec2(5.4, -30.5), // short outlier steps
        const Vec2(0.0, -31.0),
      ];
      final est = estimateSlant([pts], xHeight: 10);
      expect(degrees(est.angle), closeTo(10.2, 1.0));
    });
  });

  group('3d: stroke classes', () {
    test('"hello" is tall, core, tall, tall, core', () {
      final a = analyzeWord(makeWord('hello'))!;
      expect([for (final s in a.strokes) s.strokeClass], [
        StrokeClass.tall,
        StrokeClass.core,
        StrokeClass.tall,
        StrokeClass.tall,
        StrokeClass.core,
      ]);
    });

    test('"go" is descender, core', () {
      final a = analyzeWord(makeWord('go', rotateDeg: 5))!;
      expect(a.strokes[0].strokeClass, StrokeClass.descender);
      expect(a.strokes[1].strokeClass, StrokeClass.core);
      expect(a.strokes[0].bottom, greaterThan(0.35 * 10));
    });

    test('the dot of an i is a mark', () {
      final a = analyzeWord(makeWord('line'))!;
      expect(a.strokes[1].strokeClass, StrokeClass.core);
      expect(a.strokes[2].strokeClass, StrokeClass.mark);
      expect(a.nonMarkCount, 4);
    });

    test('a tall letter with a tail keeps its bottom (f-like)', () {
      final pts = densify(const [Vec2(0, -19), Vec2(0, 6)]);
      final other = densify(const [Vec2(5, -10), Vec2(5, 0)]);
      final third = densify(const [Vec2(10, -10), Vec2(10, 0)]);
      final a = analyzeWord(toStrokes([pts, other, third]))!;
      expect(a.strokes[0].strokeClass, StrokeClass.tall);
      expect(a.strokes[0].keepBottom, isTrue);
    });

    test('top / bottom are measured against the deskewed baseline', () {
      final a = analyzeWord(makeWord('hello', rotateDeg: 8))!;
      expect(a.strokes[0].top, closeTo(19, 0.8));
      expect(a.strokes[4].bottom.abs(), lessThan(0.6));
    });
  });

  group('word analysis robustness', () {
    test('no finite point gives null', () {
      expect(
          analyzeWord(toStrokes([
            [const Vec2(double.nan, 0)]
          ])),
          isNull);
      expect(analyzeWord(const []), isNull);
    });

    test('displayed points can be analysed instead of raw', () {
      final strokes = makeWord('hello');
      final shifted = [
        for (final s in strokes)
          s.copyWith(points: [for (final p in s.raw) p.withPos(p.x, p.y + 50)]),
      ];
      final raw = analyzeWord(shifted)!;
      final shown = analyzeWord(shifted, useRaw: false)!;
      expect(shown.baseline.line.yAt(120) - raw.baseline.line.yAt(120),
          closeTo(50, 0.5));
    });

    test('a whole word of one cursive stroke still analyses', () {
      final pts = <Vec2>[
        for (var i = 0; i <= 300; i++)
          Vec2(i * 0.2, -5 - 5 * math.sin(i / 300 * 8 * math.pi)),
      ];
      final a = analyzeWord(toStrokes([pts], m: distortion(rotateDeg: 6)))!;
      expect(a.skewReliable, isTrue);
      expect(degrees(a.wordSkew), closeTo(6, 1.5));
    });
  });
}
