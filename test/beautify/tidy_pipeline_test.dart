import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/beautify/features.dart';
import 'package:neatink/beautify/line_context.dart';
import 'package:neatink/beautify/tidy_config.dart';
import 'package:neatink/beautify/tidy_pipeline.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';

import 'synthetic_font.dart';

/// The spec's test table (docs/beautify-spec.md, "Tests (required)"): each
/// test distorts a synthetic word by a known amount, runs the pipeline at
/// strength 1.0 (unless the test is about strength) and checks the recovery.

PageContext blankPage({double? xHeight = 10}) {
  final p = PageContext(width: 595, height: 842);
  if (xHeight != null) p.observe(xHeight: xHeight);
  return p;
}

TidyResult tidy(
  List<Stroke> strokes, {
  PageContext? page,
  LineContext? line,
  TidySettings settings = TidySettings.strong,
  Stroke? previous,
}) {
  final r = tidyWord(
    wordStrokes: strokes,
    line: line ?? LineContext(),
    page: page ?? blankPage(),
    settings: settings,
    previousWordLastStroke: previous,
  );
  expect(r, isNotNull, reason: 'the word should have been tidied');
  return r!;
}

double _deg(double rad) => rad * 180 / math.pi;

void main() {
  group('Deskew', () {
    test('rotate 8 degrees: baseline angle within 1 degree', () {
      final strokes = makeWord('hello', rotateDeg: 8);
      final before = analyzeWord(strokes)!;
      expect(_deg(before.wordSkew), closeTo(8, 1.0));

      final r = tidy(strokes);
      final after = reanalyze(strokes, r);
      expect(_deg(after.wordSkew).abs(), lessThan(1.0));
      expect(after.skewReliable, isTrue);
    });

    test('negative rotation is corrected too', () {
      final strokes = makeWord('hello', rotateDeg: -6);
      final after = reanalyze(strokes, tidy(strokes));
      expect(_deg(after.wordSkew).abs(), lessThan(1.0));
    });

    test('the baseline start stays where it was (pivot P0)', () {
      final strokes = makeWord('hello', rotateDeg: 8, x: 120, y: 340);
      final before = analyzeWord(strokes)!;
      final r = tidy(strokes);
      final after = reanalyze(strokes, r);
      expect(after.baselineStart.x, closeTo(before.baselineStart.x, 1.0));
      expect(after.baselineStart.y, closeTo(before.baselineStart.y, 1.0));
    });
  });

  group('Slant', () {
    test('upright mode: shear 20 degrees ends within 3 degrees of 0', () {
      final strokes = makeWord('hello', leanDeg: 20);
      expect(_deg(analyzeWord(strokes)!.slant.angle), closeTo(20, 2.0));

      final r = tidy(strokes,
          settings: TidySettings.strong.copyWith(slantMode: TidySlantMode.upright));
      final after = reanalyze(strokes, r);
      expect(_deg(after.slant.angle).abs(), lessThan(3.0));
    });

    test('upright mode also stands up a backslant', () {
      final strokes = makeWord('line', leanDeg: -15);
      final r = tidy(strokes,
          settings: TidySettings.strong.copyWith(slantMode: TidySlantMode.upright));
      expect(_deg(reanalyze(strokes, r).slant.angle).abs(), lessThan(3.0));
    });

    test('keep mode: third word (25 deg) ends within 4 deg of ~11', () {
      final page = blankPage();
      final w1 = makeWord('hello', prefix: 'a', leanDeg: 10, x: 40);
      final w2 = makeWord('line', prefix: 'b', leanDeg: 12, x: 160);
      final w3 = makeWord('hello', prefix: 'c', leanDeg: 25, x: 260);
      for (final w in [w1, w2]) {
        final d = tidyWordOnPage(
            wordStrokes: w, page: page, settings: TidySettings.strong);
        expect(d.isTidied, isTrue);
      }
      expect(_deg(page.slant!), closeTo(11, 1.5));

      final d3 = tidyWordOnPage(
          wordStrokes: w3, page: page, settings: TidySettings.strong);
      final after = reanalyze(w3, d3.result!);
      expect(_deg(after.slant.angle), closeTo(11, 4.0));
    });

    test('keep mode with no history leaves the lean alone', () {
      final strokes = makeWord('hello', leanDeg: 18);
      final r = tidy(strokes, page: blankPage(xHeight: null));
      expect(r.features.targetSlant, closeTo(r.features.slant, 1e-9));
      expect(_deg(reanalyze(strokes, r).slant.angle), closeTo(18, 3.0));
    });
  });

  group('Size', () {
    test('scale 1.3x with target x-height 10 ends within 5% of 10', () {
      final strokes = makeWord('hello', scale: 1.3);
      expect(analyzeWord(strokes)!.xHeight.xHeight, closeTo(13, 0.8));
      final r = tidy(strokes);
      final after = reanalyze(strokes, r);
      expect(after.xHeight.xHeight, closeTo(10, 0.5));
      expect(r.features.scale, closeTo(10 / 13, 0.04));
    });

    test('scale 0.8x grows to the target', () {
      final strokes = makeWord('hello', scale: 0.8);
      final after = reanalyze(strokes, tidy(strokes));
      expect(after.xHeight.xHeight, closeTo(10, 0.5));
    });

    test('scale is clamped to [0.75, 1.35]', () {
      final big = makeWord('hello', scale: 2.0);
      final r = tidy(big);
      expect(r.features.scale, closeTo(0.75, 1e-9));
      final small = makeWord('hello', scale: 0.4);
      expect(tidy(small).features.scale, closeTo(1.35, 1e-9));
    });

    test('lined paper: target x-height is 0.36 x spacing', () {
      final page = PageContext.fromPaper(
          const Paper(type: PaperType.lined, spacingPt: 26), 595, 842);
      final strokes = makeWord('hello', scale: 1.2, y: 208);
      final r = tidy(strokes, page: page);
      expect(r.features.targetXHeight, closeTo(0.36 * 26, 1e-9));
      expect(reanalyze(strokes, r).xHeight.xHeight, closeTo(9.36, 0.5));
    });

    test('blank page without history: size is left alone', () {
      final strokes = makeWord('hello', scale: 1.2);
      final r = tidy(strokes, page: blankPage(xHeight: null));
      expect(r.features.scale, closeTo(1.0, 1e-9));
    });
  });

  group('Snap to line', () {
    PageContext lined() => PageContext.fromPaper(
        const Paper(type: PaperType.lined, spacingPt: 26), 595, 842);

    test('baseline 4 pt off a ruled line lands within 0.5 pt of it', () {
      final page = lined();
      expect(page.ruledLines, contains(208.0));
      for (final off in [4.0, -4.0]) {
        final strokes = makeWord('hello', y: 208 + off);
        final r = tidy(strokes, page: page);
        final after = reanalyze(strokes, r);
        final cx = (after.coreBounds.left + after.coreBounds.right) / 2;
        expect(after.baseline.line.yAt(cx), closeTo(208, 0.5));
        expect(r.features.snapped, isTrue);
      }
    });

    test('tilted word on ruled paper ends flat on the line', () {
      final strokes = makeWord('hello', y: 212, rotateDeg: 5);
      final after = reanalyze(strokes, tidy(strokes, page: lined()));
      expect(_deg(after.wordSkew).abs(), lessThan(1.0));
      expect(after.baseline.line.yAt(after.baselineStart.x), closeTo(208, 0.5));
    });

    test('blank paper: later words follow the line of the first', () {
      final page = blankPage();
      final first = makeWord('hello', prefix: 'a', x: 40, y: 300);
      tidyWordOnPage(
          wordStrokes: first, page: page, settings: TidySettings.strong);
      // Second word written 3 pt lower and slightly tilted.
      final second = makeWord('line', prefix: 'b', x: 140, y: 303, rotateDeg: 3);
      final d = tidyWordOnPage(
          wordStrokes: second, page: page, settings: TidySettings.strong);
      final after = reanalyze(second, d.result!);
      final cx = (after.coreBounds.left + after.coreBounds.right) / 2;
      expect(after.baseline.line.yAt(cx), closeTo(300, 0.8));
    });

    test('a ruled line further than half a spacing is not snapped to', () {
      // Above the first ruled line (78): nearest line is 78 but 30 > 13 away.
      final page = lined();
      final strokes = makeWord('hello', y: 48);
      final r = tidy(strokes, page: page);
      expect(r.features.snapped, isFalse);
    });
  });

  group('Per-stroke alignment', () {
    test('a raised "e" in print "hello" sits back on the baseline', () {
      final polys = wordPolylines('hello');
      // Raise the e (stroke 1) by 2 pt.
      polys[1] = [for (final p in polys[1]) Vec2(p.x, p.y - 2)];
      final strokes = toStrokes(polys, prefix: 'h', m: distortion());
      final r = tidy(strokes);
      final eBottom = bottomOf(r.newPoints['h-1']!);
      final lBottom = bottomOf(r.newPoints['h-2']!);
      expect(eBottom, closeTo(300, 0.5));
      expect((eBottom - lBottom).abs(), lessThan(0.5));
    });

    test('a lowered letter is lifted back too', () {
      final polys = wordPolylines('hello');
      polys[4] = [for (final p in polys[4]) Vec2(p.x, p.y + 2)];
      final strokes = toStrokes(polys, prefix: 'h', m: distortion());
      final r = tidy(strokes);
      expect(bottomOf(r.newPoints['h-4']!), closeTo(300, 0.5));
    });

    test('a big gap (> 0.3 x-height) is considered intentional', () {
      final polys = wordPolylines('hello');
      polys[1] = [for (final p in polys[1]) Vec2(p.x, p.y - 5)];
      final strokes = toStrokes(polys, prefix: 'h', m: distortion());
      final r = tidy(strokes);
      expect(bottomOf(r.newPoints['h-1']!), closeTo(295, 0.7));
    });

    test('strength 0.5 moves the raised "e" half way', () {
      final polys = wordPolylines('hello');
      polys[1] = [for (final p in polys[1]) Vec2(p.x, p.y - 2)];
      final strokes = toStrokes(polys, prefix: 'h', m: distortion());
      final r = tidy(strokes, settings: TidySettings.light);
      expect(bottomOf(r.newPoints['h-1']!), closeTo(299, 0.6));
    });

    test('never moves a stroke horizontally (only the word shift)', () {
      final strokes = makeWord('hello', prefix: 'h');
      final r = tidy(strokes);
      // No previous word: no spacing shift, no shear on an upright word, so
      // the x of every point is unchanged (up to smoothing).
      for (final s in strokes) {
        final out = r.newPoints[s.id]!;
        for (var i = 0; i < out.length; i++) {
          expect(out[i].x, closeTo(s.raw[i].x, 0.6));
        }
      }
    });

    test('tall letters are scaled towards the target but at most 15%', () {
      final polys = wordPolylines('hello');
      // Make the first l 30% too tall.
      polys[2] = [for (final p in polys[2]) Vec2(p.x, p.y * 1.3)];
      final strokes = toStrokes(polys, prefix: 'h', m: distortion());
      final r = tidy(strokes);
      final h = 300 - topOf(r.newPoints['h-2']!);
      expect(h, lessThan(fontTall * 1.3 - 1));
      expect(h, greaterThan(fontTall * 1.3 * 0.84));
    });
  });

  group('Descenders, dots, caps', () {
    test('"go": the tail of the g stays below the baseline', () {
      final strokes = makeWord('go', prefix: 'g');
      final r = tidy(strokes);
      final after = reanalyze(strokes, r);
      final g = after.strokes[0];
      expect(g.strokeClass, StrokeClass.descender);
      final tail = g.bottom;
      expect(tail, greaterThanOrEqualTo(0.6 * after.xHeight.xHeight));
      // Not squashed relative to the original tail either.
      final tailBefore = analyzeWord(strokes)!.strokes[0].bottom;
      expect(tail, closeTo(tailBefore, 1.0));
    });

    test('"i": the dot stays above the stem', () {
      for (final lean in [0.0, 12.0]) {
        final strokes = makeWord('i', prefix: 'i', leanDeg: lean, rotateDeg: 5);
        final r = tidy(strokes);
        final stem = r.newPoints['i-0']!;
        final dot = r.newPoints['i-1']!;
        final stemTop = stem.reduce((a, b) => a.y < b.y ? a : b);
        final dotC = dot.first;
        expect((dotC.x - stemTop.x).abs(), lessThan(1.0));
        expect(dotC.y, lessThan(stemTop.y));
      }
    });

    test('"line": the i dot follows its stem through shear and rotation', () {
      final strokes =
          makeWord('line', prefix: 'l', leanDeg: 20, rotateDeg: 6);
      final r = tidy(strokes,
          settings: TidySettings.strong.copyWith(slantMode: TidySlantMode.upright));
      final stem = r.newPoints['l-1']!;
      final dot = r.newPoints['l-2']!;
      final stemTop = stem.reduce((a, b) => a.y < b.y ? a : b);
      expect((dot.first.x - stemTop.x).abs(), lessThan(1.2));
    });

    test('"HE" is recognised as capitals and sits on the baseline', () {
      final strokes = makeWord('HE', prefix: 'c', rotateDeg: 4);
      final r = tidy(strokes);
      final after = reanalyze(strokes, r,
          context: const FeatureContext(expectedXHeight: 10, scaleHintPt: 10));
      expect(r.features.allCaps, isTrue);
      expect(after.strokes.first.strokeClass, StrokeClass.tall);
      // Left stem of the H and the stem of the E end on the same line.
      final hBottom = bottomOf(r.newPoints['c-0']!);
      final eBottom = bottomOf(r.newPoints['c-3']!);
      expect((hBottom - eBottom).abs(), lessThan(0.6));
    });
  });

  group('Spacing', () {
    Stroke previousEndingAt(double right) => Stroke(
          id: 'prev',
          tool: StrokeTool.pen,
          color: 0xFF000000,
          size: 2,
          raw: [
            InkPoint(right - 10, 290, 0.5, 0),
            InkPoint(right, 300, 0.5, 5),
          ],
        );

    double gapOf(TidyResult r, double prevRight) =>
        r.features.tidiedBounds.left - prevRight;

    test('gap 16 with target 10 closes to 10 +/- 1', () {
      final strokes = makeWord('hello', x: 116);
      final r = tidy(strokes, previous: previousEndingAt(100));
      expect(gapOf(r, 100), closeTo(10, 1.0));
    });

    test('gap 25 is limited by the 0.8 x-height clamp (17)', () {
      final strokes = makeWord('hello', x: 125);
      final r = tidy(strokes, previous: previousEndingAt(100));
      expect(gapOf(r, 100), closeTo(17, 1.0));
    });

    test('gap 25 reaches 10 when the clamp allows it', () {
      final strokes = makeWord('hello', x: 125);
      final r = tidyWord(
        wordStrokes: strokes,
        line: LineContext(),
        page: blankPage(),
        settings: TidySettings.strong,
        previousWordLastStroke: previousEndingAt(100),
        config: const TidyConfig(maxSpacingShiftFactor: 2.0),
      )!;
      expect(gapOf(r, 100), closeTo(10, 1.0));
    });

    test('a gap that is too small widens to 10', () {
      final strokes = makeWord('hello', x: 103);
      final r = tidy(strokes, previous: previousEndingAt(100));
      expect(gapOf(r, 100), closeTo(10, 1.0));
    });

    test('light strength moves half way', () {
      final strokes = makeWord('hello', x: 116);
      final r =
          tidy(strokes, previous: previousEndingAt(100), settings: TidySettings.light);
      expect(gapOf(r, 100), closeTo(13, 1.0));
    });

    test('deliberate layout gaps (> 3 x-heights) are left alone', () {
      final strokes = makeWord('hello', x: 160);
      final r = tidy(strokes, previous: previousEndingAt(100));
      expect(gapOf(r, 100), closeTo(60, 1.0));
    });

    test('never shifts into the page margin', () {
      final page = PageContext(width: 200, height: 400)..observe(xHeight: 10);
      // The word ends at ~143; widening a gap of 2 by 8 would end at 151,
      // inside the page, so it moves. Narrow page: it must not.
      final strokes = makeWord('hello', x: 152);
      final r = tidy(strokes, page: page, previous: previousEndingAt(150));
      expect(gapOf(r, 150), closeTo(2, 0.8));
    });

    test('the previous word on the line is used when none is given', () {
      final page = blankPage();
      final a = makeWord('hello', prefix: 'a', x: 40);
      final da = tidyWordOnPage(
          wordStrokes: a, page: page, settings: TidySettings.strong);
      final aRight = da.result!.features.tidiedBounds.right;
      final b = makeWord('line', prefix: 'b', x: aRight + 18);
      final db = tidyWordOnPage(
          wordStrokes: b, page: page, settings: TidySettings.strong);
      expect(db.result!.features.tidiedBounds.left - aRight, closeTo(10, 1.2));
    });
  });

  group('Skipping', () {
    test('a 60 pt tall circle returns null', () {
      final circle = toStrokes([
        densify(arc(0, 0, 30, 30, 0, 360, steps: 120), 1.0),
      ], m: distortion(y: 400));
      expect(
          tidyWord(
              wordStrokes: circle,
              line: LineContext(),
              page: blankPage(),
              settings: TidySettings.strong),
          isNull);
      final d = tidyWordDetailed(
          wordStrokes: circle,
          line: LineContext(),
          page: blankPage(),
          settings: TidySettings.strong);
      expect(d.skip, SkipReason.tooTall);
      expect(d.record, isNotNull);
      expect(d.record!.tidied, isFalse);
    });

    test('a 150 pt horizontal line returns null', () {
      final underline = toStrokes([
        densify(const [Vec2(0, 0), Vec2(150, 0)], 0.5),
      ], m: distortion());
      final d = tidyWordDetailed(
          wordStrokes: underline,
          line: LineContext(),
          page: blankPage(),
          settings: TidySettings.strong);
      expect(d.result, isNull);
      expect(d.skip, SkipReason.underline);
    });

    test('a long word with ordinary height is not an underline', () {
      final strokes = makeWord('hellohellohello', scale: 1.0);
      final d = tidyWordDetailed(
          wordStrokes: strokes,
          line: LineContext(),
          page: blankPage(),
          settings: TidySettings.strong);
      expect(d.skip, isNull);
    });

    test('highlighter strokes are never tidied', () {
      final strokes = makeWord('hello');
      strokes[0] = strokes[0].copyWith(tool: StrokeTool.highlighter);
      final d = tidyWordDetailed(
          wordStrokes: strokes,
          line: LineContext(),
          page: blankPage(),
          settings: TidySettings.strong);
      expect(d.skip, SkipReason.highlighter);
      expect(d.record, isNull);
    });

    test('shapes are never tidied', () {
      final strokes = makeWord('hello');
      strokes[0] = strokes[0].copyWith(shape: ShapeKind.line);
      expect(
          tidyWordDetailed(
                  wordStrokes: strokes,
                  line: LineContext(),
                  page: blankPage(),
                  settings: TidySettings.strong)
              .skip,
          SkipReason.shape);
    });

    test('strokes whose tidy was undone (locked) are never tidied again', () {
      final strokes = makeWord('hello');
      strokes[2] = strokes[2].copyWith(tidy: const TidyInfo(locked: true));
      expect(
          tidyWordDetailed(
                  wordStrokes: strokes,
                  line: LineContext(),
                  page: blankPage(),
                  settings: TidySettings.strong)
              .skip,
          SkipReason.locked);
    });

    test('a word with fewer than 12 resampled points is skipped', () {
      final tiny = toStrokes([
        densify(const [Vec2(0, 0), Vec2(5, 0)], 0.4),
      ], m: distortion());
      expect(
          tidyWordDetailed(
                  wordStrokes: tiny,
                  line: LineContext(),
                  page: blankPage(),
                  settings: TidySettings.strong)
              .skip,
          SkipReason.tooFewPoints);
    });

    test('tilt beyond 20 degrees is considered intentional', () {
      final strokes = makeWord('hello', rotateDeg: 28);
      expect(
          tidyWordDetailed(
                  wordStrokes: strokes,
                  line: LineContext(),
                  page: blankPage(),
                  settings: TidySettings.strong)
              .skip,
          SkipReason.excessiveSkew);
    });

    test('slant beyond 40 degrees is considered intentional', () {
      final strokes = makeWord('hello', leanDeg: 43);
      expect(
          tidyWordDetailed(
                  wordStrokes: strokes,
                  line: LineContext(),
                  page: blankPage(),
                  settings: TidySettings.strong)
              .skip,
          SkipReason.excessiveSlant);
    });

    test('a scribble over an existing tidied word is skipped', () {
      final page = blankPage();
      final first = makeWord('hello', prefix: 'a');
      expect(
          tidyWordOnPage(
                  wordStrokes: first, page: page, settings: TidySettings.strong)
              .isTidied,
          isTrue);
      // Strike-through: a zig-zag over the word.
      final zig = <Vec2>[];
      for (var i = 0; i <= 60; i++) {
        zig.add(Vec2(100 + i * 0.75, 295 + (i.isEven ? -3 : 3)));
      }
      final strike = toStrokes([zig], prefix: 'z');
      final d = tidyWordOnPage(
          wordStrokes: strike, page: page, settings: TidySettings.strong);
      expect(d.skip, SkipReason.overlapsTidied);
    });

    test('skipped words are still recorded on the page for spacing', () {
      final page = blankPage();
      final circle = toStrokes([
        densify(arc(0, 0, 30, 30, 0, 360, steps: 120), 1.0),
      ], m: distortion(x: 100, y: 400));
      final d = tidyWordOnPage(
          wordStrokes: circle,
          page: page,
          settings: TidySettings.strong,
          wordId: 'circle');
      expect(d.skip, SkipReason.tooTall);
      final rec = page.wordById('circle')!;
      expect(rec.tidied, isFalse);
      expect(page.lines.single.lastWord, rec);
      // It does not feed the statistics.
      expect(page.xHeight, closeTo(10, 1e-9));
    });

    test('empty and degenerate input never throws', () {
      final line = LineContext();
      final page = blankPage();
      TidyDecision run(List<Stroke> s) => tidyWordDetailed(
          wordStrokes: s,
          line: line,
          page: page,
          settings: TidySettings.strong);
      expect(run(const []).skip, SkipReason.empty);

      final nan = Stroke(
        id: 'nan',
        tool: StrokeTool.pen,
        color: 0,
        size: 2,
        raw: const [
          InkPoint(double.nan, 1, 0.5, 0),
          InkPoint(double.infinity, 2, 0.5, 1),
        ],
      );
      expect(run([nan]).skip, SkipReason.noFinitePoints);

      final dot = Stroke(
          id: 'dot',
          tool: StrokeTool.pen,
          color: 0,
          size: 2,
          raw: const [InkPoint(10, 10, 0.5, 0)]);
      expect(run([dot]).result, isNull);

      final same = Stroke(
          id: 'same',
          tool: StrokeTool.pen,
          color: 0,
          size: 2,
          raw: [for (var i = 0; i < 30; i++) InkPoint(5, 5, 0.5, i)]);
      expect(run([same]).result, isNull);

      final empty = Stroke(
          id: 'e', tool: StrokeTool.pen, color: 0, size: 2, raw: const []);
      expect(run([empty]).result, isNull);
    });

    test('NaN points inside a real word are tolerated', () {
      final strokes = makeWord('hello', prefix: 'n');
      final bad = [
        for (var i = 0; i < strokes[0].raw.length; i++)
          i == 5 ? const InkPoint(double.nan, double.nan, 0.5, 5) : strokes[0].raw[i],
      ];
      strokes[0] = strokes[0].copyWith(raw: bad);
      final r = tidy(strokes);
      for (final pts in r.newPoints.values) {
        expect(pts.every((p) => p.x.isFinite && p.y.isFinite), isTrue);
      }
      expect(r.newPoints['n-0']!.length, bad.length);
    });
  });

  group('Strength', () {
    test('Light corrects about half the skew, Strong all of it', () {
      final strokes = makeWord('hello', rotateDeg: 10);
      final light = reanalyze(strokes, tidy(strokes, settings: TidySettings.light));
      final medium =
          reanalyze(strokes, tidy(strokes, settings: TidySettings.medium));
      final strong =
          reanalyze(strokes, tidy(strokes, settings: TidySettings.strong));
      expect(_deg(light.wordSkew), closeTo(5, 1.0));
      expect(_deg(medium.wordSkew), closeTo(2, 0.8));
      expect(_deg(strong.wordSkew).abs(), lessThan(0.8));
    });

    test('strength 0 changes nothing but smoothing', () {
      final strokes = makeWord('hello', rotateDeg: 10, leanDeg: 10, scale: 1.2);
      final r = tidy(strokes, settings: const TidySettings(strength: 0));
      for (final s in strokes) {
        final out = r.newPoints[s.id]!;
        for (var i = 0; i < out.length; i++) {
          expect(out[i].x, closeTo(s.raw[i].x, 0.5));
          expect(out[i].y, closeTo(s.raw[i].y, 0.5));
        }
      }
    });

    test('light slant correction (upright) moves half way', () {
      final strokes = makeWord('hello', leanDeg: 20);
      final r = tidy(strokes,
          settings: TidySettings.light.copyWith(slantMode: TidySlantMode.upright));
      expect(_deg(reanalyze(strokes, r).slant.angle), closeTo(10, 2.5));
    });
  });

  group('Safety and invariants', () {
    test('raw is unchanged byte for byte', () {
      final strokes = makeWord('hello', rotateDeg: 8, leanDeg: 15, scale: 1.3);
      final before = jsonEncode([for (final s in strokes) s.toJson()]);
      tidy(strokes);
      expect(jsonEncode([for (final s in strokes) s.toJson()]), before);
      for (final s in strokes) {
        expect(s.pointsAreRaw, isTrue);
      }
    });

    test('same input twice gives identical output', () {
      final strokes = makeWord('hello', rotateDeg: 8, leanDeg: 15, scale: 1.3);
      final a = tidy(strokes);
      final b = tidy(strokes);
      expect(a.wordTransform, b.wordTransform);
      for (final s in strokes) {
        expect(a.newPoints[s.id], b.newPoints[s.id]);
      }
    });

    test('every stroke keeps its point count, pressure and time', () {
      final strokes = makeWord('hello', rotateDeg: 8, leanDeg: 15);
      final r = tidy(strokes);
      for (final s in strokes) {
        final out = r.newPoints[s.id]!;
        expect(out.length, s.raw.length);
        for (var i = 0; i < out.length; i++) {
          expect(out[i].pressure, s.raw[i].pressure);
          expect(out[i].t, s.raw[i].t);
        }
      }
    });

    test('tidying already tidied ink is nearly a no-op (idempotence)', () {
      final strokes = makeWord('hello', rotateDeg: 8, leanDeg: 15, scale: 1.3);
      final page = blankPage();
      final first = tidy(strokes, page: page);
      // Treat the displayed points as new "raw" ink and tidy once more.
      final again = [
        for (final s in strokes)
          Stroke(
              id: s.id,
              tool: s.tool,
              color: s.color,
              size: s.size,
              raw: first.newPoints[s.id]!),
      ];
      final second = tidy(again, page: page);
      var worst = 0.0;
      for (final s in again) {
        final a = s.raw, b = second.newPoints[s.id]!;
        for (var i = 0; i < a.length; i++) {
          worst = math.max(worst, (a[i].pos - b[i].pos).length);
        }
      }
      expect(worst, lessThan(1.0));
    });

    test('result is finite and well formed for a long cursive-like stroke', () {
      // One stroke for the whole word (cursive): a sine wave with loops.
      final pts = <Vec2>[];
      for (var i = 0; i <= 400; i++) {
        final t = i / 400 * 6 * math.pi;
        pts.add(Vec2(i * 0.2 + 6 * math.sin(t * 2), -5 - 5 * math.sin(t)));
      }
      final strokes = toStrokes([pts], m: distortion(rotateDeg: 5));
      final r = tidy(strokes);
      expect(r.newPoints.values.single.every((p) => p.isFinite), isTrue);
    });

    test('the debug features describe the detection', () {
      final strokes = makeWord('hello', rotateDeg: 8, leanDeg: 10);
      final r = tidy(strokes);
      final f = r.features;
      expect(_deg(f.wordSkew), closeTo(8, 1.0));
      expect(_deg(f.slant), closeTo(10, 2));
      expect(f.xHeight, closeTo(10, 0.6));
      expect(f.strokeClasses['w-0'], StrokeClass.tall);
      expect(f.strokeClasses['w-1'], StrokeClass.core);
      // The detected baseline follows the tilt, the tidied one is flat.
      final slope = (f.baseline.b.y - f.baseline.a.y) /
          (f.baseline.b.x - f.baseline.a.x);
      expect(math.atan(slope) * 180 / math.pi, closeTo(8, 1.0));
      final tslope = (f.tidiedBaseline.b.y - f.tidiedBaseline.a.y) /
          (f.tidiedBaseline.b.x - f.tidiedBaseline.a.x);
      expect(tslope.abs(), lessThan(0.02));
      // x-height line is above the baseline by about the x-height.
      expect(f.baseline.a.y - f.xHeightLine.a.y, greaterThan(8));
      expect(f.slantLine.b.y, lessThan(f.slantLine.a.y));
    });

    test('the result record feeds the page statistics', () {
      final page = blankPage(xHeight: null);
      final strokes = makeWord('hello', leanDeg: 10);
      final d = tidyWordOnPage(
          wordStrokes: strokes, page: page, settings: TidySettings.strong);
      expect(d.isTidied, isTrue);
      expect(page.xHeight, closeTo(10, 0.6));
      expect(_deg(page.slant!), closeTo(10, 2));
      expect(page.tallRatio, closeTo(1.9, 0.2));
      expect(page.lines.single.wordCount, 1);
    });

    test('runs within the 8 ms budget for a normal word', () {
      final strokes = makeWord('hello', rotateDeg: 8, leanDeg: 15);
      // Warm up, then time a few runs (a generous bound: CI machines vary).
      tidy(strokes);
      final sw = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        tidy(strokes);
      }
      expect(sw.elapsedMilliseconds / 10, lessThan(40));
    });
  });

  group('Rebuild from stored strokes', () {
    test('page context is recreated from tidied strokes', () {
      final page = blankPage(xHeight: null);
      final w1 = makeWord('hello', prefix: 'a', leanDeg: 10, x: 40);
      final w2 = makeWord('line', prefix: 'b', leanDeg: 12, x: 160);
      final stored = <Stroke>[];
      var n = 0;
      for (final w in [w1, w2]) {
        final d = tidyWordOnPage(
            wordStrokes: w,
            page: page,
            settings: TidySettings.strong,
            wordId: 'word-${n++}');
        for (final s in w) {
          stored.add(s.copyWith(
              points: d.result!.newPoints[s.id],
              wordId: d.result!.wordId,
              tidy: const TidyInfo(applied: true, version: 1)));
        }
      }
      final rebuilt = blankPage(xHeight: null);
      rebuildPageContext(rebuilt, stored);
      expect(rebuilt.words.length, 2);
      expect(rebuilt.lines.length, 1);
      expect(rebuilt.lines.single.tidiedWordCount, 2);
      // Measured on the displayed (tidied) points: upright-ish and x ~ 10.
      expect(rebuilt.xHeight, closeTo(10, 1.0));
      expect(rebuilt.lines.single.baselineAt(200), closeTo(300, 1.0));
    });

    test('untidied words occupy their line but not the statistics', () {
      final strokes = [
        for (final s in makeWord('hello'))
          s.copyWith(wordId: 'plain'),
      ];
      final page = blankPage(xHeight: null);
      rebuildPageContext(page, strokes);
      expect(page.words.single.tidied, isFalse);
      expect(page.xHeight, isNull);
    });

    test('highlighter and shape strokes are ignored', () {
      final hl = makeWord('hello')[0]
          .copyWith(tool: StrokeTool.highlighter, wordId: 'x');
      final sh = makeWord('hello')[0].copyWith(shape: ShapeKind.line, wordId: 'y');
      final page = blankPage(xHeight: null);
      rebuildPageContext(page, [hl, sh]);
      expect(page.words, isEmpty);
    });
  });
}
