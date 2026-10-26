import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/beautify/features.dart';
import 'package:neatink/beautify/line_context.dart';
import 'package:neatink/beautify/smoothing.dart';
import 'package:neatink/beautify/tidy_config.dart';
import 'package:neatink/beautify/transform.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/ink/affine2.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/ink_rect.dart';
import 'package:neatink/ink/vec2.dart';

import 'synthetic_font.dart';

/// Spec steps 4, 5 (transform math, spacing, smoothing) and 7 (context).

double _rad(double deg) => deg * math.pi / 180;

WordTransform build({
  required WordAnalysis a,
  double s = 1,
  double targetX = 10,
  double? targetSlant = 0,
  double? Function(double, double)? baseline,
}) =>
    buildWordTransform(
        analysis: a,
        strength: s,
        targetXHeight: targetX,
        targetSlant: targetSlant,
        targetBaseline: baseline ?? (x, y) => null);

void main() {
  group('5a: word transform', () {
    test('rotation levels the baseline and keeps the pivot fixed', () {
      final a = analyzeWord(makeWord('hello', rotateDeg: 8))!;
      final t = build(a: a, targetSlant: null, targetX: a.xHeight.xHeight);
      expect(t.rotation, closeTo(-a.skew, 1e-12));
      final p0 = t.matrix.apply(a.baselineStart);
      expect(p0.x, closeTo(a.baselineStart.x, 1e-9));
      expect(p0.y, closeTo(a.baselineStart.y, 1e-9));
      final end = t.matrix.apply(a.baselineEnd);
      expect(end.y, closeTo(a.baselineStart.y, 0.6));
    });

    test('shear does not move points on the baseline and stands a lean up', () {
      final a = analyzeWord(makeWord('hello', leanDeg: 20))!;
      final t = build(a: a, targetX: a.xHeight.xHeight);
      expect(t.shear, closeTo(math.tan(a.slant.angle), 1e-9));
      final onBase = Vec2(a.baselineStart.x + 5, a.baselineStart.y);
      expect(t.matrix.apply(onBase).x, closeTo(onBase.x, 0.05));
      // A point 10 above the baseline moves left by 10 * tan(lean).
      final above = Vec2(a.baselineStart.x + 5, a.baselineStart.y - 10);
      expect(above.x - t.matrix.apply(above).x,
          closeTo(10 * math.tan(a.slant.angle), 0.1));
    });

    test('a target slant leaves exactly that lean (exact tangent form)', () {
      final a = analyzeWord(makeWord('hello', leanDeg: 25))!;
      final t = build(
          a: a, targetSlant: _rad(11), targetX: a.xHeight.xHeight);
      // Lean of a vertical-ish segment after the shear: tan(new) = tan(old) - k.
      final newLean = math.atan(math.tan(a.slant.angle) - t.shear);
      expect(degrees(newLean), closeTo(11, 1e-6));
    });

    test('strength blends the correction', () {
      final a = analyzeWord(makeWord('hello', rotateDeg: 10, leanDeg: 20))!;
      final full = build(a: a, s: 1);
      final half = build(a: a, s: 0.5);
      expect(half.rotation, closeTo(full.rotation / 2, 1e-12));
      final lean = a.slant.angle + 0.5 * a.skew; // after half the rotation
      expect(half.shear,
          closeTo(math.tan(lean) - math.tan(lean / 2), 1e-9));
      final none = build(a: a, s: 0);
      expect(none.matrix.closeTo(Affine2.identity), isTrue);
    });

    test('scale goes to the target x-height and is clamped', () {
      final a = analyzeWord(makeWord('hello', scale: 1.2))!;
      final t = build(a: a, targetSlant: null, targetX: 10);
      expect(t.scale, closeTo(10 / a.xHeight.xHeight, 1e-9));
      expect(build(a: a, targetX: 100, targetSlant: null).scale, 1.35);
      expect(build(a: a, targetX: 1, targetSlant: null).scale, 0.75);
    });

    test('an unreliable x-height is trusted only half as much', () {
      final a = analyzeWord(makeWord('i'))!;
      expect(a.xHeight.reliable, isFalse);
      final t = build(a: a, targetSlant: null, targetX: a.xHeight.xHeight * 1.2);
      expect(t.scale, closeTo(1.1, 0.01));
    });

    test('vertical translation puts the baseline on the target', () {
      final a = analyzeWord(makeWord('hello', y: 304))!;
      final t = build(a: a, baseline: (x, y) => 300);
      expect(t.snapped, isTrue);
      expect(t.targetBaselineY, 300);
      expect(t.baselineAfter.y, closeTo(300, 1e-9));
      final half = build(a: a, s: 0.5, baseline: (x, y) => 300);
      expect(half.baselineAfter.y, closeTo(302, 0.05));
    });

    test('no target: the baseline stays where it is', () {
      final a = analyzeWord(makeWord('hello', y: 304))!;
      final t = build(a: a);
      expect(t.snapped, isFalse);
      expect(t.dy, 0);
      expect(t.baselineAfter.y, closeTo(t.baselineBefore.y, 0.05));
    });
  });

  group('5b: per-stroke alignment', () {

    test('needs at least two non-mark strokes', () {
      final a = analyzeWord(makeWord('i'))!;
      final strokes = [
        for (final s in makeWord('i')) sanitizePositions(s.raw)!,
      ];
      final out = alignStrokes(
          strokes: strokes,
          shapes: a.strokes,
          baselineAt: (x) => 300,
          targetXHeight: 10,
          targetTallHeight: 19,
          strength: 1);
      expect(identical(out, strokes), isTrue);
    });

    test('marks follow the top of their nearest stroke', () {
      final polys = wordPolylines('line');
      polys[1] = [for (final p in polys[1]) Vec2(p.x, p.y - 2)]; // raise i stem
      final strokes = toStrokes(polys, m: distortion());
      final a = analyzeWord(strokes)!;
      final input = [for (final s in strokes) sanitizePositions(s.raw)!];
      final out = alignStrokes(
          strokes: input,
          shapes: a.strokes,
          baselineAt: (x) => 300,
          targetXHeight: 10,
          targetTallHeight: 19,
          strength: 1);
      // Stem back on the baseline (down 2) and the dot comes down with it.
      expect(out[1].map((p) => p.y).reduce(math.max), closeTo(300, 0.01));
      expect(out[2].first.y - input[2].first.y, closeTo(2, 0.01));
      expect(out[2].first.x, input[2].first.x);
    });

    test('descender body top is aligned with the x-height line', () {
      final polys = wordPolylines('ogo');
      polys[1] = [for (final p in polys[1]) Vec2(p.x, p.y - 2)];
      final strokes = toStrokes(polys, m: distortion());
      final a = analyzeWord(strokes)!;
      final input = [for (final s in strokes) sanitizePositions(s.raw)!];
      final out = alignStrokes(
          strokes: input,
          shapes: a.strokes,
          baselineAt: (x) => 300,
          targetXHeight: 10,
          targetTallHeight: 19,
          strength: 1);
      expect(a.strokes[1].strokeClass, StrokeClass.descender);
      expect(out[1].map((p) => p.y).reduce(math.min), closeTo(290, 0.01));
      // The tail length is unchanged (a pure move).
      final lenBefore = input[1].map((p) => p.y).reduce(math.max) -
          input[1].map((p) => p.y).reduce(math.min);
      final lenAfter = out[1].map((p) => p.y).reduce(math.max) -
          out[1].map((p) => p.y).reduce(math.min);
      expect(lenAfter, closeTo(lenBefore, 1e-9));
    });

    test('vertical scaling is limited to 15% per stroke', () {
      final polys = wordPolylines('hello');
      polys[4] = [for (final p in polys[4]) Vec2(p.x, p.y * 1.3)]; // big o
      final strokes = toStrokes(polys, m: distortion());
      final a = analyzeWord(strokes)!;
      final input = [for (final s in strokes) sanitizePositions(s.raw)!];
      final out = alignStrokes(
          strokes: input,
          shapes: a.strokes,
          baselineAt: (x) => 300,
          targetXHeight: 10,
          targetTallHeight: 19,
          strength: 1);
      double h(List<Vec2> p) =>
          p.map((e) => e.y).reduce(math.max) - p.map((e) => e.y).reduce(math.min);
      expect(h(out[4]) / h(input[4]), closeTo(0.85, 0.01));
    });

    test('x never changes', () {
      final strokes = makeWord('hello');
      final a = analyzeWord(strokes)!;
      final input = [for (final s in strokes) sanitizePositions(s.raw)!];
      final out = alignStrokes(
          strokes: input,
          shapes: a.strokes,
          baselineAt: (x) => 300,
          targetXHeight: 10,
          targetTallHeight: 19,
          strength: 0.8);
      for (var i = 0; i < input.length; i++) {
        for (var k = 0; k < input[i].length; k++) {
          expect(out[i][k].x, input[i][k].x);
        }
      }
    });
  });

  group('5c: spacing shift', () {
    InkRect box(double l, double r) => InkRect(l, 0, r, 10);
    double shift(double left, {double? prev = 100, double s = 1, double pageW = 595, double right = 150}) =>
        spacingShift(
            wordBounds: box(left, right),
            previousRight: prev,
            targetXHeight: 10,
            strength: s,
            pageWidth: pageW);

    test('moves toward the target gap of 1 x-height', () {
      expect(shift(105), 5);
      expect(shift(116), -6);
      expect(shift(110), 0);
    });

    test('blended by strength', () {
      expect(shift(116, s: 0.5), -3);
    });

    test('clamped to 0.8 x-height', () {
      expect(shift(125), -8);
      expect(shift(100.5), 8);
    });

    test('no previous word, overlap, and layout gaps give no shift', () {
      expect(shift(105, prev: null), 0);
      expect(shift(95), 0);
      expect(shift(131), 0); // gap 31 > 3 x-heights
    });

    test('never past the right margin', () {
      expect(shift(105, pageW: 150, right: 148), 0);
      expect(shift(116, pageW: 150, right: 148), -6); // moving left is fine
    });

    test('does not overlap the previous word', () {
      final s = spacingShift(
          wordBounds: box(101, 150),
          previousRight: 100,
          targetXHeight: 10,
          strength: 1,
          pageWidth: 595,
          config: const TidyConfig(wordSpaceFactor: -1));
      expect(s, 0);
    });
  });

  group('5d: smoothing', () {
    List<InkPoint> line(int n) => [
          for (var i = 0; i < n; i++)
            InkPoint(i.toDouble(), i.isEven ? 0.0 : 1.0, 0.1 + i / 100, i * 4),
        ];

    test('weights (0.25, 0.5, 0.25), ends fixed, pressure and time kept', () {
      final pts = line(7);
      final out = smoothPoints(pts);
      expect(out.length, pts.length);
      expect(out.first, pts.first);
      expect(out.last, pts.last);
      // Index 2: 0.25*1 + 0.5*0 + 0.25*1 = 0.5; x stays (linear).
      expect(out[2].y, closeTo(0.5, 1e-12));
      expect(out[2].x, closeTo(2, 1e-12));
      for (var i = 0; i < pts.length; i++) {
        expect(out[i].pressure, pts[i].pressure);
        expect(out[i].t, pts[i].t);
      }
    });

    test('short strokes (fewer than 5 points) are untouched', () {
      final pts = line(4);
      expect(identical(smoothPoints(pts), pts), isTrue);
    });

    test('reduces a shake and is a single pass of the same input', () {
      final pts = line(30);
      final once = smoothPoints(pts);
      final amp = once.skip(1).take(27).map((p) => p.y).reduce(math.max);
      expect(amp, lessThan(0.6));
      expect(smoothPoints(pts), once);
    });

    test('a straight line is unchanged', () {
      final pts = [for (var i = 0; i < 10; i++) InkPoint(i * 2.0, i * 1.0, 0.5, i)];
      final out = smoothPoints(pts);
      for (var i = 0; i < pts.length; i++) {
        expect(out[i].x, closeTo(pts[i].x, 1e-12));
        expect(out[i].y, closeTo(pts[i].y, 1e-12));
      }
    });
  });

  group('sanitizePositions', () {
    test('fills non-finite points from neighbours, keeps the count', () {
      final out = sanitizePositions(const [
        InkPoint(double.nan, 0, 0.5, 0),
        InkPoint(1, 1, 0.5, 1),
        InkPoint(double.infinity, 5, 0.5, 2),
        InkPoint(3, 3, 0.5, 3),
      ])!;
      expect(out, [
        const Vec2(1, 1),
        const Vec2(1, 1),
        const Vec2(1, 1),
        const Vec2(3, 3),
      ]);
      expect(sanitizePositions(const [InkPoint(double.nan, 0, 0.5, 0)]), isNull);
    });
  });

  group('step 4: targets (PageContext)', () {
    PageContext lined() => PageContext.fromPaper(
        const Paper(type: PaperType.lined, spacingPt: 26), 595, 842);

    test('lined paper: ruled lines, spacing, x-height and line height', () {
      final p = lined();
      expect(p.isRuled, isTrue);
      expect(p.ruledSpacing, 26);
      expect(p.ruledLines.first, 78);
      expect(p.initialXHeight, closeTo(10.4, 1e-9));
      expect(p.targetXHeight(7), closeTo(9.36, 1e-9));
      expect(p.lineHeight(), 26);
    });

    test('nearest ruled line within half a spacing', () {
      final p = lined();
      expect(p.nearestRuledLine(104 + 4), 104);
      expect(p.nearestRuledLine(104 - 12.9), 104);
      expect(p.nearestRuledLine(10), isNull);
      expect(PageContext(width: 1, height: 1).nearestRuledLine(5), isNull);
    });

    test('grid and Cornell paper are ruled; blank, dotted, music are not', () {
      for (final t in [PaperType.grid, PaperType.cornell]) {
        expect(PageContext.fromPaper(Paper(type: t), 595, 842).isRuled, isTrue,
            reason: '$t');
      }
      for (final t in [PaperType.blank, PaperType.dotted, PaperType.music]) {
        expect(PageContext.fromPaper(Paper(type: t), 595, 842).isRuled, isFalse,
            reason: '$t');
      }
    });

    test('blank paper: target x-height is the median of the last 12', () {
      final p = PageContext(width: 595, height: 842);
      expect(p.targetXHeight(8), 8);
      for (var i = 0; i < 20; i++) {
        p.observe(xHeight: i < 8 ? 100.0 : 10.0);
      }
      // Only the last 12 count: 8 x 10 would be... values 8..19 are all 10.
      expect(p.targetXHeight(8), 10);
      expect(p.lineHeight(), closeTo(25, 1e-9));
    });

    test('slant target: keep = median of last 20, upright = 0', () {
      final p = PageContext(width: 595, height: 842);
      expect(p.targetSlant(TidySlantMode.keep, 0.3), 0.3);
      for (var i = 0; i < 25; i++) {
        p.observe(slant: i < 5 ? 1.0 : 0.2);
      }
      expect(p.slant, closeTo(0.2, 1e-12));
      expect(p.targetSlant(TidySlantMode.keep, 0.3), closeTo(0.2, 1e-12));
      expect(p.targetSlant(TidySlantMode.upright, 0.3), 0.0);
    });

    test('tall target: running ratio clamped to [1.6, 2.4], default 1.9', () {
      final p = PageContext(width: 595, height: 842);
      expect(p.targetTallHeight(10), closeTo(19, 1e-9));
      p.observe(tallRatio: 3.5);
      expect(p.targetTallHeight(10), closeTo(24, 1e-9));
      final q = PageContext(width: 595, height: 842)..observe(tallRatio: 1.0);
      expect(q.targetTallHeight(10), closeTo(16, 1e-9));
    });
  });

  group('step 7: line context', () {
    WordRecord word(String id, double cx, double y,
            {double slope = 0, bool tidied = true, double? skew, double? slant, double? xh}) =>
        WordRecord(
            wordId: id,
            bounds: InkRect(cx - 20, y - 15, cx + 20, y + 3),
            baselineCenter: Vec2(cx, y),
            baselineSlope: slope,
            tidied: tidied,
            skew: skew,
            slant: slant,
            xHeight: xh);

    test('medians of skew, slant and x-height', () {
      final l = LineContext();
      expect(l.skew, isNull);
      l.add(word('a', 50, 300, skew: 0.1, slant: 0.2, xh: 10));
      l.add(word('b', 120, 300, skew: 0.3, slant: 0.4, xh: 12));
      l.add(word('c', 190, 300, skew: 0.2, slant: 0.3, xh: 11));
      expect(l.skew, closeTo(0.2, 1e-12));
      expect(l.slant, closeTo(0.3, 1e-12));
      expect(l.xHeight, 11);
      expect(l.wordCount, 3);
      expect(l.lastWord!.wordId, 'c');
    });

    test('baseline: one word extends its own, several are fitted', () {
      final l = LineContext();
      expect(l.baselineAt(10), isNull);
      l.add(word('a', 50, 300, slope: 0.02));
      expect(l.baselineAt(50), closeTo(300, 1e-9));
      expect(l.baselineAt(150), closeTo(302, 1e-9));
      l.add(word('b', 150, 310));
      expect(l.baselineAt(100), closeTo(305, 1e-9));
      expect(l.baselineAt(200), closeTo(315, 1e-9));
    });

    test('the fitted slope is limited to the skew limit', () {
      final l = LineContext();
      l.add(word('a', 50, 300));
      l.add(word('b', 60, 400));
      expect(l.baselineFit!.slope, closeTo(math.tan(_rad(20)), 1e-9));
    });

    test('skipped words count for spacing but not for baselines', () {
      final l = LineContext();
      l.add(word('a', 50, 300));
      l.add(word('skip', 120, 500, tidied: false));
      expect(l.wordCount, 2);
      expect(l.tidiedWordCount, 1);
      expect(l.baselineAt(120), closeTo(300, 1e-9));
      expect(l.lastWord!.wordId, 'skip');
    });

    test('adding the same id replaces; remove deletes', () {
      final l = LineContext();
      l.add(word('a', 50, 300));
      l.add(word('a', 60, 310));
      expect(l.wordCount, 1);
      expect(l.lastWord!.baselineCenter.y, 310);
      l.remove('a');
      expect(l.isEmpty, isTrue);
    });

    test('lineFor groups words with baselines within half a line height', () {
      final p = PageContext(width: 595, height: 842)..observe(xHeight: 10);
      final l1 = p.lineFor(300, 50);
      expect(l1.isEmpty, isTrue);
      p.recordWord(l1, word('a', 50, 300));
      expect(identical(p.lineFor(305, 120), l1), isTrue);
      // lineHeight = 25, half = 12.5
      expect(identical(p.lineFor(330, 120), l1), isFalse);
      final l2 = p.lineFor(330, 120);
      p.recordWord(l2, word('b', 120, 330));
      expect(p.lines.length, 2);
      expect(identical(p.lineFor(331, 400), l2), isTrue);
      expect(identical(p.lastLine, l2), isTrue);
    });

    test('recordWord feeds the windows only for tidied words', () {
      final p = PageContext(width: 595, height: 842);
      final l = LineContext();
      p.recordWord(l, word('a', 50, 300, xh: 10, slant: 0.2, skew: 0.0));
      p.recordWord(l, word('skip', 120, 300, tidied: false, xh: 99));
      expect(p.xHeight, 10);
      expect(p.slant, 0.2);
    });

    test('words can be removed again (undo / erase)', () {
      final p = PageContext(width: 595, height: 842);
      final l = LineContext();
      p.recordWord(l, word('a', 50, 300));
      p.removeWord('a');
      expect(p.words, isEmpty);
      expect(p.lines, isEmpty);
      expect(p.lastLine, isNull);
    });

    test('a page remembers a bounded number of words', () {
      final p = PageContext(
          width: 595, height: 842, config: const TidyConfig(rememberedWordLimit: 5));
      final l = LineContext();
      for (var i = 0; i < 9; i++) {
        p.recordWord(l, word('w$i', i * 10.0, 300));
      }
      expect(p.words.length, 5);
      expect(p.words.first.wordId, 'w4');
    });

    test('overlapsTidied: only tidied words, more than 50 percent', () {
      final p = PageContext(width: 595, height: 842);
      final l = LineContext();
      p.recordWord(l, word('a', 100, 300)); // box 80..120 x 285..303
      expect(p.overlapsTidied(const InkRect(85, 288, 115, 300)), isTrue);
      expect(p.overlapsTidied(const InkRect(110, 288, 160, 300)), isFalse);
      expect(p.overlapsTidied(const InkRect(85, 288, 115, 300), exceptId: 'a'),
          isFalse);
      // A flat strike line through the box still counts.
      expect(p.overlapsTidied(const InkRect(80, 294, 120, 294)), isTrue);
      p.recordWord(l, word('skip', 300, 300, tidied: false));
      expect(p.overlapsTidied(const InkRect(285, 288, 315, 300)), isFalse);
    });
  });
}
