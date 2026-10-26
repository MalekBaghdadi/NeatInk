import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/beautify/line_context.dart';
import 'package:neatink/beautify/tidy_config.dart';
import 'package:neatink/beautify/tidy_pipeline.dart';
import 'package:neatink/beautify/word_segmenter.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';

import 'synthetic_font.dart';

/// Spec step 1 with timed stroke sequences: idle timeout, a large gap, a new
/// line and a late dot.

PageContext blank() => PageContext(width: 595, height: 842)..observe(xHeight: 10);

/// Feeds the strokes of [text] to [seg], one every 120 ms starting at
/// [t0]; returns the time of the last pen-up and everything committed.
({int lastUp, List<CommittedWord> committed}) write(
  WordSegmenter seg,
  String text, {
  double x = 100,
  double y = 300,
  String prefix = 's',
  int t0 = 0,
}) {
  final strokes = makeWord(text, prefix: prefix, x: x, y: y);
  final committed = <CommittedWord>[];
  var t = t0;
  for (final s in strokes) {
    final down = seg.onPenDown(tool: StrokeTool.pen, nowMs: t);
    if (down != null) committed.add(down);
    t += 100;
    final out = seg.onStrokeEnd(s, upMs: t);
    if (out.committed != null) committed.add(out.committed!);
    t += 20;
  }
  return (lastUp: t - 20, committed: committed);
}

void main() {
  group('idle timeout', () {
    test('the word is committed 650 ms after the last pen-up', () {
      final seg = WordSegmenter(page: blank());
      final w = write(seg, 'hello');
      expect(w.committed, isEmpty);
      expect(seg.pending.length, 5);
      expect(seg.idleDeadlineMs, w.lastUp + 650);
      expect(seg.onTick(w.lastUp + 649), isNull);
      final c = seg.onTick(w.lastUp + 650)!;
      expect(c.reason, CommitReason.idle);
      expect(c.strokes.length, 5);
      expect(seg.hasPending, isFalse);
      expect(seg.idleDeadlineMs, isNull);
    });

    test('a pen-down before the timeout keeps the word open', () {
      final seg = WordSegmenter(page: blank());
      final w = write(seg, 'hel');
      expect(seg.onPenDown(tool: StrokeTool.pen, nowMs: w.lastUp + 600), isNull);
      expect(seg.hasPending, isTrue);
    });

    test('a pen-down after the timeout commits the old word', () {
      final seg = WordSegmenter(page: blank());
      final w = write(seg, 'hel');
      final c = seg.onPenDown(tool: StrokeTool.pen, nowMs: w.lastUp + 700);
      expect(c!.reason, CommitReason.idle);
    });

    test('the idle time is configurable', () {
      final seg = WordSegmenter(
          page: blank(), config: const TidyConfig(wordIdleMs: 300));
      final w = write(seg, 'hi');
      expect(seg.onTick(w.lastUp + 299), isNull);
      expect(seg.onTick(w.lastUp + 300), isNotNull);
    });

    test('ticking with nothing pending is harmless', () {
      final seg = WordSegmenter(page: blank());
      expect(seg.onTick(100000), isNull);
      expect(seg.flush(CommitReason.pageChange), isNull);
    });
  });

  group('gap', () {
    test('a stroke far right of the word starts a new word', () {
      final seg = WordSegmenter(page: blank());
      // "hello" spans x 100..139; a gap of 0.9 * 10 = 9 pt is the limit.
      final w = write(seg, 'hello');
      final next = makeWord('l', prefix: 'n', x: 160)[0];
      final out = seg.onStrokeEnd(next, upMs: w.lastUp + 200);
      expect(out.committed!.reason, CommitReason.gap);
      expect(out.committed!.strokes.length, 5);
      expect(seg.pending.single.id, 'n-0');
    });

    test('a small gap stays in the same word', () {
      final seg = WordSegmenter(page: blank());
      final w = write(seg, 'hello');
      final next = makeWord('l', prefix: 'n', x: 139 + 6)[0];
      final out = seg.onStrokeEnd(next, upMs: w.lastUp + 200);
      expect(out.committed, isNull);
      expect(seg.pending.length, 6);
    });

    test('the gap threshold scales with the x-height estimate', () {
      final page = PageContext(width: 595, height: 842)..observe(xHeight: 20);
      final seg = WordSegmenter(page: page);
      final w = write(seg, 'hello');
      // 15 pt gap: beyond 0.9 * 10, within 0.9 * 20.
      final next = makeWord('l', prefix: 'n', x: 139 + 15)[0];
      expect(seg.onStrokeEnd(next, upMs: w.lastUp + 200).committed, isNull);
    });

    test('on ruled paper the initial estimate is 0.4 x spacing', () {
      final page = PageContext.fromPaper(
          const Paper(type: PaperType.lined, spacingPt: 26), 595, 842);
      final seg = WordSegmenter(page: page);
      expect(seg.xHeightEstimate, closeTo(10.4, 1e-9));
    });

    test('unruled paper starts at 9 pt', () {
      final seg = WordSegmenter(page: PageContext(width: 100, height: 100));
      expect(seg.xHeightEstimate, 9);
    });
  });

  group('new line', () {
    test('a stroke 30 pt below starts a new line (and word)', () {
      final seg = WordSegmenter(page: blank());
      final w = write(seg, 'hello');
      final next = makeWord('l', prefix: 'n', x: 105, y: 330)[0];
      final out = seg.onStrokeEnd(next, upMs: w.lastUp + 300);
      expect(out.committed!.reason, CommitReason.newLine);
    });

    test('a descender or an ascender is not a new line', () {
      final seg = WordSegmenter(page: blank());
      final w = write(seg, 'go');
      final next = makeWord('l', prefix: 'n', x: 120, y: 300)[0];
      expect(seg.onStrokeEnd(next, upMs: w.lastUp + 100).committed, isNull);
    });

    test('on ruled paper the line height is the spacing', () {
      PageContext lined() => PageContext.fromPaper(
          const Paper(type: PaperType.lined, spacingPt: 26), 595, 842);
      // A stroke centred 17 pt below the baseline is within 0.7 * 26 = 18.2
      // (same line) on ruled paper, but would be a new line on blank paper
      // (0.7 * 22.5 = 15.75).
      final seg = WordSegmenter(page: lined());
      final w = write(seg, 'hello', y: 208);
      final near = makeWord('l', prefix: 'a', x: 110, y: 234.5)[0];
      expect(seg.onStrokeEnd(near, upMs: w.lastUp + 100).committed, isNull);

      final seg2 = WordSegmenter(page: lined());
      final w2 = write(seg2, 'hello', y: 208);
      final far = makeWord('l', prefix: 'a', x: 110, y: 238.5)[0];
      expect(seg2.onStrokeEnd(far, upMs: w2.lastUp + 100).committed!.reason,
          CommitReason.newLine);
    });
  });

  group('tool change and flush', () {
    test('a non-pen pen-down commits the word', () {
      final seg = WordSegmenter(page: blank());
      write(seg, 'hel');
      final c = seg.onPenDown(tool: StrokeTool.highlighter, nowMs: 700);
      expect(c!.reason, CommitReason.toolChange);
      expect(seg.hasPending, isFalse);
    });

    test('an eraser / lasso (null tool) commits the word', () {
      final seg = WordSegmenter(page: blank());
      write(seg, 'hel');
      expect(seg.onPenDown(tool: null, nowMs: 500)!.reason,
          CommitReason.toolChange);
    });

    test('highlighter strokes never join a word', () {
      final seg = WordSegmenter(page: blank());
      write(seg, 'hel');
      final hl = makeWord('hello', prefix: 'hl')[0]
          .copyWith(tool: StrokeTool.highlighter);
      final out = seg.onStrokeEnd(hl, upMs: 900);
      expect(out.committed!.reason, CommitReason.toolChange);
      expect(seg.hasPending, isFalse);
    });

    test('shape strokes never join a word', () {
      final seg = WordSegmenter(page: blank());
      final shape = makeWord('hello', prefix: 'sh')[0]
          .copyWith(shape: ShapeKind.rectangle);
      seg.onStrokeEnd(shape, upMs: 10);
      expect(seg.hasPending, isFalse);
    });

    test('flush for page change and tidy off returns the strokes', () {
      final seg = WordSegmenter(page: blank());
      write(seg, 'hello');
      final c = seg.flush(CommitReason.pageChange)!;
      expect(c.reason, CommitReason.pageChange);
      expect(c.strokes.length, 5);
      write(seg, 'hi', prefix: 'b');
      expect(seg.flush(CommitReason.tidyOff)!.reason, CommitReason.tidyOff);
    });

    test('reset forgets pending strokes without committing', () {
      final seg = WordSegmenter(page: blank());
      write(seg, 'hello');
      seg.reset();
      expect(seg.hasPending, isFalse);
      expect(seg.idleDeadlineMs, isNull);
    });

    test('strokes without finite points are ignored', () {
      final seg = WordSegmenter(page: blank());
      final nan = Stroke(
          id: 'n',
          tool: StrokeTool.pen,
          color: 0,
          size: 2,
          raw: const [InkPoint(double.nan, double.nan, 0.5, 0)]);
      final out = seg.onStrokeEnd(nan, upMs: 5);
      expect(out.committed, isNull);
      expect(seg.hasPending, isFalse);
    });
  });

  group('late marks', () {
    /// Tidies "line" (with its i dot) and returns the page and the result.
    ({PageContext page, TidyResult result, List<Stroke> strokes}) tidiedLine() {
      final page = blank();
      final strokes = makeWord('line', prefix: 'l');
      final d = tidyWordOnPage(
          wordStrokes: strokes,
          page: page,
          settings: TidySettings.strong,
          wordId: 'word-line');
      return (page: page, result: d.result!, strokes: strokes);
    }

    test('a dot landing in a tidied word attaches without moving', () {
      final t = tidiedLine();
      final seg = WordSegmenter(page: t.page);
      // Where the i's dot is now (tidied), drawn again as a late dot.
      final dot = t.result.newPoints['l-2']!.first;
      final late = Stroke(
        id: 'late',
        tool: StrokeTool.pen,
        color: 0xFF000000,
        size: 2,
        raw: [
          InkPoint(dot.x - 0.5, dot.y, 0.5, 0),
          InkPoint(dot.x + 0.5, dot.y + 0.3, 0.5, 5),
        ],
      );
      final out = seg.onStrokeEnd(late, upMs: 5000);
      expect(out.lateMarkWordId, 'word-line');
      expect(out.committed, isNull);
      expect(seg.hasPending, isFalse, reason: 'a late mark is not a new word');
    });

    test('a short horizontal bar (t-crossing) attaches too', () {
      final t = tidiedLine();
      final seg = WordSegmenter(page: t.page);
      final box = t.result.features.tidiedBounds;
      final y = box.center.y;
      final bar = Stroke(
        id: 'bar',
        tool: StrokeTool.pen,
        color: 0xFF000000,
        size: 2,
        raw: [
          for (var i = 0; i <= 10; i++)
            InkPoint(box.left + 3 + i * 0.9, y, 0.5, i),
        ],
      );
      expect(seg.onStrokeEnd(bar, upMs: 100).lateMarkWordId, 'word-line');
    });

    test('a small stroke far from any word starts a new word', () {
      final t = tidiedLine();
      final seg = WordSegmenter(page: t.page);
      final far = Stroke(
        id: 'far',
        tool: StrokeTool.pen,
        color: 0,
        size: 2,
        raw: const [InkPoint(400, 500, 0.5, 0), InkPoint(401, 500, 0.5, 5)],
      );
      final out = seg.onStrokeEnd(far, upMs: 100);
      expect(out.lateMarkWordId, isNull);
      expect(seg.pending.single.id, 'far');
    });

    test('a big stroke inside the word box is not a late mark', () {
      final t = tidiedLine();
      final seg = WordSegmenter(page: t.page);
      final box = t.result.features.tidiedBounds;
      final big = Stroke(
        id: 'big',
        tool: StrokeTool.pen,
        color: 0,
        size: 2,
        raw: [
          for (var i = 0; i <= 20; i++)
            InkPoint(box.center.x, box.top + i, 0.5, i),
        ],
      );
      expect(seg.onStrokeEnd(big, upMs: 100).lateMarkWordId, isNull);
    });

    test('skipped (untidied) words do not take late marks', () {
      final page = blank();
      final circle = toStrokes([
        densify(arc(0, 0, 30, 30, 0, 360, steps: 120), 1.0),
      ], m: distortion(y: 400));
      tidyWordOnPage(
          wordStrokes: circle, page: page, settings: TidySettings.strong);
      final seg = WordSegmenter(page: page);
      final dot = Stroke(
        id: 'd',
        tool: StrokeTool.pen,
        color: 0,
        size: 2,
        raw: const [InkPoint(100, 400, 0.5, 0), InkPoint(100.5, 400, 0.5, 5)],
      );
      expect(seg.onStrokeEnd(dot, upMs: 10).lateMarkWordId, isNull);
    });

    test('the nearest of several candidate words wins', () {
      final page = blank();
      final a = makeWord('line', prefix: 'a', x: 100);
      final b = makeWord('line', prefix: 'b', x: 140);
      final da = tidyWordOnPage(
          wordStrokes: a, page: page, settings: TidySettings.strong, wordId: 'A');
      tidyWordOnPage(
          wordStrokes: b, page: page, settings: TidySettings.strong, wordId: 'B');
      final seg = WordSegmenter(page: page);
      final dot = da.result!.newPoints['a-2']!.first;
      final late = Stroke(
        id: 'late',
        tool: StrokeTool.pen,
        color: 0,
        size: 2,
        raw: [InkPoint(dot.x, dot.y, 0.5, 0), InkPoint(dot.x + 0.4, dot.y, 0.5, 5)],
      );
      expect(seg.onStrokeEnd(late, upMs: 10).lateMarkWordId, 'A');
    });
  });

  test('a full session: write, pause, write the next word', () {
    final page = blank();
    final seg = WordSegmenter(page: page);
    final committed = <CommittedWord>[];
    var t = 0;
    for (final (word, x) in [('hello', 100.0), ('line', 170.0)]) {
      final w = write(seg, word, x: x, prefix: word, t0: t);
      committed.addAll(w.committed);
      t = w.lastUp + 800;
      final idle = seg.onTick(t);
      if (idle != null) committed.add(idle);
    }
    expect(committed.length, 2);
    expect(committed[0].strokes.length, 5);
    expect(committed[1].strokes.length, 5); // l, i, dot, n, e
    expect(committed.every((c) => c.reason == CommitReason.idle), isTrue);
  });
}
