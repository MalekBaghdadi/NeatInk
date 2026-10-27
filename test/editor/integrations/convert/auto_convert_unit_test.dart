import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/features/editor/integrations/convert/auto_convert_merge.dart';
import 'package:neatink/features/editor/integrations/convert/auto_convert_session.dart';
import 'package:neatink/features/editor/integrations/convert/convert_layout.dart';
import 'package:neatink/features/editor/integrations/convert/convert_plan.dart';
import 'package:neatink/recognition/htr_channel.dart';
import 'package:neatink/recognition/stroke_grouping.dart';

import 'harness.dart';

/// Text metrics that need no text engine: 8 px per character at size 16.
class _Metrics extends ConvertTextMetrics {
  const _Metrics();

  @override
  double firstBaseline(TextItem item) => item.fontSize * 0.8;

  @override
  double naturalWidth(TextItem item) => item.text.length * item.fontSize * 0.5;

  @override
  double heightOf(TextItem item) => item.fontSize * 1.2;
}

PlannedLine lineWith(List<(String, double)> words) {
  final strokes = writeLine('a', [for (final _ in words) 'hello'], y: 104);
  final line = groupStrokes(strokes).single;
  expect(line.words, hasLength(words.length));
  return plannedLineFrom(
    id: 'p/0',
    pageId: 'p',
    line: line,
    words: [
      for (var i = 0; i < words.length; i++)
        WordResult(
          group: line.words[i],
          text: words[i].$1,
          confidence: words[i].$2,
          raw: words[i].$1,
          alternatives: const [],
        ),
    ],
  );
}

void main() {
  group('autoConvertsLine', () {
    test('every word must reach the minimum confidence', () {
      expect(autoConvertsLine(lineWith([('hello', 0.9)])), isTrue);
      expect(autoConvertsLine(lineWith([('hello', 0.9), ('there', 0.5)])), isTrue,
          reason: 'exactly the minimum is enough');
      expect(
          autoConvertsLine(lineWith([('hello', 0.9), ('there', 0.499)])), isFalse);
      expect(autoConvertsLine(lineWith([('hello', 0.2), ('there', 0.99)])), isFalse,
          reason: 'one doubtful word is enough to keep the line as ink');
    });

    test('a line with an unreadable word never converts', () {
      expect(autoConvertsLine(lineWith([('hello', 0.9), ('', 0.99)])), isFalse);
      expect(autoConvertsLine(lineWith([('  ', 0.99)])), isFalse);
    });

    test('the minimum can be changed', () {
      final line = lineWith([('hello', 0.7)]);
      expect(autoConvertsLine(line, minConfidence: 0.8), isFalse);
      expect(autoConvertsLine(line, minConfidence: 0.6), isTrue);
    });

    test('a confidence that is not a number does not convert', () {
      expect(autoConvertsLine(lineWith([('hello', double.nan)])), isFalse);
    });
  });

  group('planMerge', () {
    const metrics = _Metrics();
    const pageWidth = 595.0;

    TextItem item({String text = 'hello', double width = 44}) => TextItem(
          id: 'i1',
          x: 100,
          y: 84,
          width: width,
          height: 19.2,
          text: text,
          fontSize: 16,
        );

    AutoBox box([TextItem? it]) =>
        AutoBox(AutoBoxVersion(it ?? item(), 200, 100));

    LineGeometry line({
      double left = 220,
      double baseline = 100,
      double xHeight = 10,
      double slope = 0,
    }) =>
        LineGeometry(
          left: left,
          right: left + 80,
          baselineY: baseline,
          baselineSlope: slope,
          xHeight: xHeight,
          inkTop: baseline - 2 * xHeight,
        );

    MergePlan? plan(
      LineGeometry geometry, {
      List<AutoBox>? boxes,
      TextItem? Function(String)? live,
      String text = 'world',
      double width = pageWidth,
      Set<String> taken = const {},
    }) =>
        planMerge(
          boxes: boxes ?? [box()],
          liveItem: live ?? (id) => item(),
          line: geometry,
          text: text,
          pageWidth: width,
          metrics: metrics,
          taken: taken,
        );

    test('a line just after the box on the same baseline is appended', () {
      final p = plan(line())!;
      expect(p.after.id, 'i1');
      expect(p.after.text, 'hello world');
      expect((p.after.x, p.after.y), (100, 84));
      expect(p.after.fontSize, 16);
      expect(p.after.width, 11 * 8 + 4);
      expect(p.after.height, closeTo(19.2, 1e-9));
      expect(p.before.text, 'hello');
    });

    test('the gap must be from 0 up to 2.5 x-heights', () {
      expect(plan(line(left: 200)), isNotNull, reason: 'touching');
      expect(plan(line(left: 224.9)), isNotNull);
      expect(plan(line(left: 225)), isNull);
      expect(plan(line(left: 199.9)), isNull, reason: 'starts before the end');
      // The tolerance follows the x-height of the new writing.
      expect(plan(line(left: 240, xHeight: 20)), isNotNull);
    });

    test('the baselines must agree within 0.6 x-heights', () {
      expect(plan(line(baseline: 105.9)), isNotNull);
      expect(plan(line(baseline: 94.1)), isNotNull);
      expect(plan(line(baseline: 106)), isNull);
      expect(plan(line(baseline: 94)), isNull);
    });

    test('a box that already took a line this pass is skipped', () {
      expect(plan(line(), taken: {'i1'}), isNull);
    });

    test('a box that is gone, or that the user changed, is left alone', () {
      expect(plan(line(), live: (_) => null), isNull);
      expect(plan(line(), live: (_) => item(text: 'hello!')), isNull);
      expect(plan(line(), live: (_) => item().copyWith(x: 101)), isNull);
      expect(plan(line(), live: (_) => item().copyWith(bold: true)), isNull);
    });

    test('an older state of the box is still recognised (after an undo)', () {
      final b = box();
      final grown = item(text: 'hello world', width: 92);
      b.versions.add(AutoBoxVersion(grown, 300, 100));
      // The live box is the old one again.
      expect(plan(line(), boxes: [b])!.before.text, 'hello');
      // The live box is the grown one: compared with where its ink ended.
      expect(plan(line(left: 310), boxes: [b], live: (_) => grown)!.after.text,
          'hello world world');
      expect(plan(line(left: 220), boxes: [b], live: (_) => grown), isNull);
    });

    test('the joined text must stay on one line inside the page', () {
      // Room: 200 - 24 margin - 100 = 76; "hello world" needs 88 + 4.
      expect(plan(line(), width: 200), isNull);
      expect(plan(line(), width: 230), isNotNull);
    });

    test('a box that already wrapped is not continued', () {
      expect(plan(line(), live: (_) => item(width: 30)), isNull);
    });

    test('the nearest of several boxes wins', () {
      final far = AutoBox(AutoBoxVersion(item().copyWith(id: 'i2'), 190, 100));
      final near = AutoBox(AutoBoxVersion(item(), 215, 100));
      final p = planMerge(
        boxes: [far, near],
        liveItem: (id) => id == 'i2' ? item().copyWith(id: 'i2') : item(),
        line: line(),
        text: 'world',
        pageWidth: pageWidth,
        metrics: metrics,
      )!;
      expect(p.box, near);
    });

    test('nothing to append, or no usable x-height, merges nothing', () {
      expect(plan(line(), text: ''), isNull);
      expect(plan(line(xHeight: 0)), isNull);
      expect(plan(line(xHeight: double.nan)), isNull);
    });

    test('a slanted baseline is compared where the new line starts', () {
      // The baseline at the left edge is what counts, not further along.
      expect(plan(line(slope: 0.5)), isNotNull);
      expect(plan(line(slope: 0.5, baseline: 107)), isNull);
    });
  });
}
