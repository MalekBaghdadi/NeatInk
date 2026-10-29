import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/features/editor/integrations/convert/auto_convert_merge.dart';
import 'package:neatink/features/editor/integrations/convert/auto_convert_session.dart';
import 'package:neatink/features/editor/integrations/convert/convert_config.dart';
import 'package:neatink/features/editor/integrations/convert/convert_layout.dart';
import 'package:neatink/features/editor/integrations/convert/convert_plan.dart';
import 'package:neatink/recognition/text_polish.dart';

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

PlannedLine lineWith(List<(String, double)> words,
        {double? confidence, List<PolishSuggestion> suggestions = const [], bool autoFix = false}) =>
    plannedLineOf(words,
        confidence: confidence, suggestions: suggestions, autoFix: autoFix);

void main() {
  group('autoConvertsLine', () {
    test('the line must reach the minimum confidence (that of its least sure word)', () {
      expect(autoConvertsLine(lineWith([('hello', 0.9)])), isTrue);
      expect(autoConvertsLine(lineWith([('hello', 0.9), ('there', 0.25)])), isTrue,
          reason: 'exactly the minimum is enough');
      expect(
          autoConvertsLine(lineWith([('hello', 0.9), ('there', 0.249)])), isFalse);
      expect(autoConvertsLine(lineWith([('hello', 0.1), ('there', 0.99)])), isFalse,
          reason: 'one unreadable word is enough to keep the line as ink');
      expect(ConvertConfig.autoMinConfidence, 0.25);
    });

    test('it is the confidence of the line that counts, not of its words', () {
      // Every word looks sure, but the recogniser is not sure of the line.
      final unsure = lineWith([('hello', 0.9), ('there', 0.9)], confidence: 0.2);
      expect(unsure.confidence, 0.2);
      expect(autoConvertsLine(unsure), isFalse);
      final sure = lineWith([('hello', 0.9), ('there', 0.9)], confidence: 0.25);
      expect(autoConvertsLine(sure), isTrue);
    });

    test('a line with an unreadable word never converts', () {
      expect(autoConvertsLine(lineWith([('hello', 0.9), ('', 0.99)])), isFalse);
      expect(autoConvertsLine(lineWith([('  ', 0.99)])), isFalse);
    });

    test('a line without any text never converts', () {
      final line = lineWith([('hello', 0.9)]);
      line.text = '   ';
      expect(autoConvertsLine(line), isFalse);
      expect(autoConvertsLine(lineWith([('', 0.9)])), isFalse);
    });

    test('the minimum can be changed', () {
      final line = lineWith([('hello', 0.7)]);
      expect(autoConvertsLine(line, minConfidence: 0.8), isFalse);
      expect(autoConvertsLine(line, minConfidence: 0.6), isTrue);
    });

    test('a confidence that is not a number does not convert', () {
      expect(autoConvertsLine(lineWith([('hello', double.nan)])), isFalse);
    });

    test('spelling fixes are typed only when "Fix spelling automatically" is on', () {
      const slip = PolishSuggestion(
        original: 'helo',
        replacement: 'hello',
        kind: PolishKind.spelling,
        reason: 'Spelling',
        start: 0,
        end: 4,
      );
      final off = lineWith([('helo', 0.9), ('there', 0.9)], suggestions: [slip]);
      expect(autoConvertsLine(off), isTrue);
      expect(off.text, 'helo there', reason: 'suggestions are never applied silently');
      expect(off.suggestions, [slip]);

      final on = lineWith([('helo', 0.9), ('there', 0.9)],
          suggestions: [slip], autoFix: true);
      expect(autoConvertsLine(on), isTrue);
      expect(on.text, 'hello there');
      expect(on.autoApplied, [slip]);
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

    test('punctuation written after the typed text goes on without a space', () {
      expect(plan(line(), text: '?')!.after.text, 'hello?');
      expect(plan(line(), text: '!')!.after.text, 'hello!');
      expect(plan(line(), text: '; world')!.after.text, 'hello; world');
    });

    test('it starts after the typed text (or a little over where the ink ended), up to 4 x-heights after the ink', () {
      // Typed text ends at 140, the ink ended at 200: the writer may go on
      // anywhere from just after the text to 40 after the ink.
      expect(plan(line(left: 200)), isNotNull, reason: 'touching');
      expect(plan(line(left: 150)), isNotNull, reason: 'over the space the ink left');
      expect(plan(line(left: 239.9)), isNotNull);
      expect(plan(line(left: 240)), isNull);
      expect(plan(line(left: 134.9)), isNull, reason: 'starts over the typed text');
      // The tolerance follows the x-height of the new writing.
      expect(plan(line(left: 270, xHeight: 20)), isNotNull);
    });

    test('the baselines must agree within 1 x-height (of the ink or of the typed text)', () {
      // Ink baseline 100, typed baseline 96.8.
      expect(plan(line(baseline: 109.9)), isNotNull);
      expect(plan(line(baseline: 86.9)), isNotNull);
      expect(plan(line(baseline: 110)), isNull);
      expect(plan(line(baseline: 86.7)), isNull);
    });

    test('on ruled paper the same ruled line is the same line', () {
      const ruling = PageRuling([100, 126, 152], 26);
      MergePlan? ruled(double baseline) => planMerge(
            boxes: [box()],
            liveItem: (_) => item(),
            line: line(baseline: baseline),
            text: 'world',
            pageWidth: pageWidth,
            metrics: metrics,
            ruling: ruling,
          );
      expect(ruled(111), isNotNull, reason: 'more than an x-height off, still nearest rule 100');
      expect(ruled(115), isNull, reason: 'nearer the next ruled line');
    });

    test('another box between the text and the new writing stops it', () {
      // Centred, so it cannot be continued itself.
      const between = TextItem(
          id: 'other', x: 160, y: 84, width: 30, height: 19.2, text: 'x', fontSize: 16, align: TextAlignKind.center);
      final p = planMerge(
        boxes: [box()],
        liveItem: (id) => id == 'i1' ? item() : between,
        pageTexts: [item(), between],
        line: line(left: 200),
        text: 'world',
        pageWidth: pageWidth,
        metrics: metrics,
      );
      expect(p, isNull);
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
      // Compared with the grown box: its typed text ends at 188.
      expect(plan(line(left: 150), boxes: [b], live: (_) => grown), isNull);
    });

    group('any one-line box on the page', () {
      // "hello" at size 16 is 40 wide here: typed text ends at x 140.
      MergePlan? onPage(LineGeometry geometry, TextItem t) => planMerge(
            boxes: const [],
            pageTexts: [t],
            liveItem: (id) => id == t.id ? t : null,
            line: geometry,
            text: 'world',
            pageWidth: pageWidth,
            metrics: metrics,
          );

      test('a line just after the typed text continues it', () {
        final p = onPage(line(left: 150), item())!;
        expect(p.after.text, 'hello world');
        expect(p.after.x, 100);
        // Where its ink ended is estimated: writing with x-height 10 is
        // 10 / (16 * 0.52) times as wide as the 40 points of typed text.
        expect(p.base.inkRight, closeTo(100 + 40 * 10 / (16 * 0.52), 1e-9));
      });

      test('exactly one space between the old and the new text', () {
        final p = onPage(line(left: 150), item(text: 'hello ', width: 60))!;
        expect(p.after.text, 'hello world');
      });

      test('from a little over the estimated end of its ink to 4 x-heights after it', () {
        // Estimated ink end 148.08: from 133.08 to 188.08.
        expect(onPage(line(left: 133.1), item()), isNotNull);
        expect(onPage(line(left: 133), item()), isNull);
        expect(onPage(line(left: 188), item()), isNotNull);
        expect(onPage(line(left: 188.1), item()), isNull);
      });

      test('on its baseline (y + first baseline = 84 + 12.8), within an x-height', () {
        expect(onPage(line(left: 150, baseline: 96.8), item()), isNotNull);
        expect(onPage(line(left: 150, baseline: 106.7), item()), isNotNull);
        expect(onPage(line(left: 150, baseline: 106.8), item()), isNull);
      });

      test('centred, right-aligned, gone or taken boxes are left alone', () {
        expect(onPage(line(left: 150), item().copyWith(align: TextAlignKind.center)), isNull);
        expect(onPage(line(left: 150), item().copyWith(align: TextAlignKind.right)), isNull);
        expect(
            planMerge(
              boxes: const [],
              pageTexts: [item()],
              liveItem: (_) => null,
              line: line(left: 150),
              text: 'world',
              pageWidth: pageWidth,
              metrics: metrics,
            ),
            isNull);
        expect(
            planMerge(
              boxes: const [],
              pageTexts: [item()],
              liveItem: (_) => item(),
              line: line(left: 150),
              text: 'world',
              pageWidth: pageWidth,
              metrics: metrics,
              taken: {'i1'},
            ),
            isNull);
      });

      test('an auto box also continues after its typed text, far from its ink', () {
        // ink ended at 200, typed text at 140
        expect(plan(line(left: 150))!.after.text, 'hello world');
      });
    });

    test('the joined text must stay on one line inside the page', () {
      // Room: 200 - 24 margin - 100 = 76; "hello world" needs 88 + 4.
      expect(plan(line(), width: 200), isNull);
      expect(plan(line(), width: 230), isNotNull);
    });

    test('a box that already wrapped is not continued', () {
      expect(plan(line(), live: (_) => item(width: 30)), isNull);
    });

    group('a line below (joining lines)', () {
      // A box whose last line has its baseline at 84 + 12.8; the new line
      // one 26 pt ruling lower, from the box's left edge.
      LineGeometry below({double right = 400}) => LineGeometry(
            left: 100, right: right, baselineY: 122.8, xHeight: 10, inkTop: 102.8);

      MergePlan? join(TextItem t, String text, {List<AutoBox> boxes = const []}) => planMerge(
            boxes: boxes,
            pageTexts: [t],
            liveItem: (id) => id == t.id ? t : null,
            line: below(),
            text: text,
            pageWidth: pageWidth,
            metrics: metrics,
            joinLines: true,
          );

      test('a wrapped box nothing remembers takes a line only when its words go on', () {
        // v1.9.0 took any wrapped box for writing that ran to the edge, so
        // every line of notes below joined it.
        final wrapped = item(text: 'chemical synapses use neurotransmitters between cells', width: 300);
        expect(join(wrapped, 'electrical synapses use gap junctions'), isNull);
        final unfinished = item(text: 'electrical synapses are much faster than', width: 300);
        expect(join(unfinished, 'chemical ones')?.after.text, 'electrical synapses are much faster than chemical ones');
      });

      test("an auto box goes on below when its ink ran out of room for the next line's first word", () {
        final t = item(text: 'Neurons pass electrical', width: 200);
        AutoBox inkTo(double right) => AutoBox(AutoBoxVersion(t, right, 96.8));
        expect(join(t, 'signals to each other', boxes: [inkTo(540)])?.after.text,
            'Neurons pass electrical signals to each other');
        expect(join(t, 'Signals are fast', boxes: [inkTo(540)]), isNull, reason: 'a capital: something new');
        expect(join(t, 'signals to each other', boxes: [inkTo(400)]), isNull, reason: 'it had room');
      });
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
      expect(plan(line(slope: 0.5, baseline: 110.1)), isNull);
    });
  });
}
