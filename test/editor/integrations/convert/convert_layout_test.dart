import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/integrations/convert/convert_config.dart';
import 'package:neatink/features/editor/integrations/convert/convert_layout.dart';
import 'package:neatink/features/editor/integrations/text_images/text_editor.dart';
import 'package:neatink/render/text_style.dart';

/// Deterministic text engine: every character is [charW] em wide, the first
/// baseline is [asc] em below the top and a line is [lh] em tall.
class FakeMetrics extends ConvertTextMetrics {
  const FakeMetrics({this.charW = 0.5, this.asc = 0.8, this.lh = 1.2});

  final double charW;
  final double asc;
  final double lh;

  @override
  double firstBaseline(TextItem item) => asc * item.fontSize;

  @override
  double naturalWidth(TextItem item) => item.text.length * charW * item.fontSize;

  @override
  double heightOf(TextItem item) {
    final lines = (naturalWidth(item) / item.width).ceil().clamp(1, 1 << 20);
    return lines * (item.lineSpacing ?? lh * item.fontSize);
  }
}

LineGeometry geo({
  double left = 100,
  double baseline = 300,
  double xHeight = 10,
  double? inkTop,
  double right = 400,
  double slope = 0,
}) =>
    LineGeometry(
      left: left,
      right: right,
      baselineY: baseline,
      baselineSlope: slope,
      xHeight: xHeight,
      inkTop: inkTop ?? baseline - 2.2 * xHeight,
    );

LayoutLineInput input(String id, String text, LineGeometry g,
        {int color = 0xFF1E1E1E, bool include = true}) =>
    LayoutLineInput(id: id, text: text, geometry: g, color: color, include: include);

List<LaidOutLine> layout(
  List<LayoutLineInput> lines, {
  ConvertStyle style = const ConvertStyle(),
  PageRuling? ruling,
  double width = 595,
  ConvertTextMetrics metrics = const FakeMetrics(),
}) =>
    layoutPage(
      pageWidth: width,
      pageHeight: 842,
      lines: lines,
      style: style,
      ruling: ruling,
      metrics: metrics,
    );

PageRuling lined() => PageRuling.of(const Paper(), 595, 842)!;

void main() {
  group('autoFontSize', () {
    test('is the handwriting x-height divided by the font ratio', () {
      expect(autoFontSize(FontKind.sans, 8), closeTo(8 / 0.52, 1e-9));
      expect(autoFontSize(FontKind.serif, 8), closeTo(8 / 0.48, 1e-9));
      expect(autoFontSize(FontKind.mono, 8), closeTo(8 / 0.52, 1e-9));
      expect(autoFontSize(FontKind.lexend, 8), closeTo(8 / 0.52, 1e-9));
      expect(autoFontSize(FontKind.caveat, 8), closeTo(8 / 0.42, 1e-9));
    });

    test('is clamped to 10..30 pt', () {
      expect(autoFontSize(FontKind.sans, 2), 10);
      expect(autoFontSize(FontKind.sans, 40), 30);
    });

    test('is at most 0.8 of the ruling on ruled paper', () {
      expect(autoFontSize(FontKind.sans, 14, ruling: 26), closeTo(20.8, 1e-9));
      expect(autoFontSize(FontKind.sans, 14, ruling: 40), closeTo(14 / 0.52, 1e-9));
    });

    test('survives a nonsense x-height', () {
      expect(autoFontSize(FontKind.sans, double.nan), 10);
      expect(autoFontSize(FontKind.sans, 0), 10);
    });

    test('every font category has a ratio', () {
      for (final c in FontCategory.values) {
        expect(ConvertConfig.fontXHeightRatio.containsKey(c), isTrue, reason: '$c');
      }
    });
  });

  group('PageRuling', () {
    test('lined, grid and Cornell paper have ruled lines', () {
      expect(PageRuling.of(const Paper(), 595, 842)!.baselines, isNotEmpty);
      expect(PageRuling.of(const Paper(type: PaperType.grid), 595, 842), isNotNull);
      expect(PageRuling.of(const Paper(type: PaperType.cornell), 595, 842), isNotNull);
    });

    test('blank, dotted and music paper and PDF pages have none', () {
      expect(PageRuling.of(const Paper(type: PaperType.blank), 595, 842), isNull);
      expect(PageRuling.of(const Paper(type: PaperType.dotted), 595, 842), isNull);
      expect(PageRuling.of(const Paper(type: PaperType.music), 595, 842), isNull);
      expect(PageRuling.of(const Paper(), 595, 842, isPdf: true), isNull);
    });

    test('spacing is the paper spacing, or 26 when it is nonsense', () {
      expect(PageRuling.of(const Paper(spacingPt: 30), 595, 842)!.spacing, 30);
      expect(PageRuling.of(const Paper(spacingPt: 0), 595, 842)!.spacing, 26);
    });
  });

  group('baseline', () {
    test('the first text baseline sits on the handwriting baseline at its left', () {
      final out = layout([input('a', 'hello world', geo(left: 120, baseline: 333))]);
      final l = out.single;
      expect(l.item.x, 120);
      expect(l.item.y + const FakeMetrics().firstBaseline(l.item), closeTo(333, 1e-9));
      expect(l.baselineY, 333);
      expect(l.snapped, isFalse);
    });

    test('a slanted line is anchored where it starts', () {
      final g = geo(left: 100, baseline: 300, slope: 0.1);
      expect(g.baselineAt(100), 300);
      final out = layout([input('a', 'hello', g)]);
      expect(out.single.baselineY, 300);
    });

    test('snaps to the nearest ruled line', () {
      final r = lined(); // rules at 78, 104, 130, ...
      var out = layout([input('a', 'hello', geo(baseline: 107))], ruling: r);
      expect(out.single.baselineY, 104);
      expect(out.single.snapped, isTrue);
      out = layout([input('a', 'hello', geo(baseline: 121))], ruling: r);
      expect(out.single.baselineY, 130);
      final item = out.single.item;
      expect(item.y + const FakeMetrics().firstBaseline(item), closeTo(130, 1e-9));
    });

    test('two lines never snap to the same rule', () {
      final r = lined();
      final out = layout([
        input('a', 'first', geo(baseline: 104)),
        input('b', 'second', geo(baseline: 115, xHeight: 6)),
      ], ruling: r);
      expect(out[0].baselineY, 104);
      expect(out[1].baselineY, 130);
      expect(out[1].snapped, isTrue);
    });

    test('a line too far from every free rule keeps its own baseline', () {
      final r = PageRuling(const [100], 26);
      final out = layout([
        input('a', 'first', geo(baseline: 99)),
        input('b', 'second', geo(baseline: 150)),
      ], ruling: r);
      expect(out[0].baselineY, 100);
      expect(out[1].snapped, isFalse);
      expect(out[1].baselineY, 150);
    });

    test('no ruling, no snapping', () {
      final out = layout([input('a', 'hello', geo(baseline: 107))]);
      expect(out.single.snapped, isFalse);
      expect(out.single.baselineY, 107);
    });
  });

  group('size', () {
    test('auto size follows the x-height of the writing', () {
      final out = layout([input('a', 'hi', geo(xHeight: 8))]);
      expect(out.single.item.fontSize, closeTo(8 / 0.52, 1e-9));
      expect(out.single.fit, ConvertFit.natural);
    });

    test('auto size depends on the font category', () {
      final out = layout([input('a', 'hi', geo(xHeight: 8))],
          style: const ConvertStyle(font: FontKind.caveat));
      expect(out.single.item.fontSize, closeTo(8 / 0.42, 1e-9));
    });

    test('auto size is limited by the ruling', () {
      final out = layout([input('a', 'hi', geo(xHeight: 14, baseline: 104))],
          ruling: lined());
      expect(out.single.item.fontSize, closeTo(20.8, 1e-9));
    });

    test('a fixed size is used as is', () {
      final out = layout([input('a', 'hi', geo(xHeight: 8))],
          style: const ConvertStyle(fixedSize: 24));
      expect(out.single.item.fontSize, 24);
    });

    test('a short line is one tight single-line box', () {
      final out = layout([input('a', 'hello', geo(xHeight: 10))]);
      final item = out.single.item;
      expect(item.width, closeTo(5 * 0.5 * item.fontSize + ConvertConfig.lineSlack, 1e-9));
      expect(item.height, closeTo(1.2 * item.fontSize, 1e-9));
    });

    test('the box carries the style: font, bold, italic, left alignment', () {
      final out = layout([input('a', 'hi', geo())],
          style: const ConvertStyle(font: FontKind.lora, bold: true, italic: true));
      final item = out.single.item;
      expect(item.font, FontKind.lora);
      expect(item.bold, isTrue);
      expect(item.italic, isTrue);
      expect(item.align, TextAlignKind.left);
      expect(item.text, 'hi');
      expect(item.id, isNotEmpty);
    });

    test('line breaks and runs of spaces collapse to single spaces', () {
      expect(normalizeLineText('  a \n b\t\tc  '), 'a b c');
      final out = layout([input('a', 'one\ntwo   three', geo())]);
      expect(out.single.item.text, 'one two three');
    });
  });

  group('too wide: shrink, then wrap', () {
    // x = 100: room = 595 - 24 - 100 = 471. Matching the handwriting, an
    // x-height of 10.4 gives 20 pt.
    test('shrinks gently first', () {
      // 52 chars * 0.5 * 20 = 520 > 467 -> about 17.96, which is >= 85% of 20.
      final out = layout([input('a', 'x' * 52, geo(xHeight: 10.4))]);
      final l = out.single;
      expect(l.fit, ConvertFit.softShrink);
      expect(l.item.fontSize, lessThan(20));
      expect(l.item.fontSize, greaterThanOrEqualTo(20 * 0.85));
      expect(l.item.x + l.item.width, lessThanOrEqualTo(595 - 24 + 1e-9));
      expect(l.item.height, closeTo(1.2 * l.item.fontSize, 1e-9)); // one line
    });

    test('then shrinks further, down to the floor', () {
      // 100 chars: needs about 9.3 pt.
      final out = layout([input('a', 'x' * 100, geo(xHeight: 10.4))]);
      final l = out.single;
      expect(l.fit, ConvertFit.hardShrink);
      expect(l.item.fontSize, lessThan(20 * 0.85));
      expect(l.item.fontSize, greaterThanOrEqualTo(ConvertConfig.floorSize));
      expect(l.item.height, closeTo(1.2 * l.item.fontSize, 1e-9)); // still one line
      expect(l.item.x + l.item.width, lessThanOrEqualTo(595 - 24 + 1e-9));
    });

    test('and only then wraps inside the available width', () {
      final out = layout([input('a', 'x' * 300, geo())],
          style: const ConvertStyle(fixedSize: 20));
      final l = out.single;
      expect(l.fit, ConvertFit.wrapped);
      expect(l.item.width, closeTo(471, 1e-9));
      expect(l.item.x + l.item.width, closeTo(595 - 24, 1e-9));
      expect(l.item.fontSize, greaterThanOrEqualTo(ConvertConfig.floorSize));
      expect(l.item.height, greaterThan(1.2 * l.item.fontSize * 1.5));
      // The first line still sits on the baseline.
      expect(l.item.y + 0.8 * l.item.fontSize, closeTo(300, 1e-9));
    });

    test('a line starting near the right edge is moved left to get some room', () {
      final out = layout([input('a', 'hello world', geo(left: 560))]);
      expect(out.single.item.x, lessThan(560));
      expect(out.single.item.x + out.single.item.width, lessThanOrEqualTo(595 - 24 + 1e-9));
    });
  });

  group('lines below', () {
    test('a wrapped box shrinks rather than run into the next line', () {
      final lines = [
        input('a', 'x' * 300, geo(baseline: 300)),
        input('b', 'next', geo(baseline: 380)),
      ];
      final out = layout(lines, style: const ConvertStyle(fixedSize: 20));
      expect(out, hasLength(2));
      final a = out[0].item, b = out[1].item;
      expect(a.y + a.height, lessThanOrEqualTo(b.y + 0.01));
      expect(out[0].collides, isFalse);
    });

    test('a stack of tight lines never overlaps: matching the handwriting it shrinks', () {
      final lines = [
        for (var i = 0; i < 6; i++)
          input('l$i', 'some words of text number $i',
              geo(baseline: 200.0 + i * 22, xHeight: 12)),
      ];
      final out = layout(lines);
      expect(out, hasLength(6));
      for (var i = 0; i + 1 < out.length; i++) {
        final a = out[i].item, b = out[i + 1].item;
        expect(a.y + a.height, lessThanOrEqualTo(b.y + 0.01), reason: 'line $i');
        expect(out[i].collides, isFalse);
      }
    });

    test('a stack of tight lines never overlaps: a chosen size stays and the boxes move down', () {
      final lines = [
        for (var i = 0; i < 6; i++)
          input('l$i', 'some words of text number $i',
              geo(baseline: 200.0 + i * 22, xHeight: 12)),
      ];
      for (final style in const [ConvertStyle(fixedSize: 30), ConvertStyle(evenSize: true)]) {
        final out = layout(lines, style: style);
        expect(out, hasLength(6));
        expect(out.map((l) => l.item.fontSize).toSet(), hasLength(1), reason: 'one size');
        for (var i = 0; i + 1 < out.length; i++) {
          final a = out[i].item, b = out[i + 1].item;
          expect(a.y + a.height, lessThanOrEqualTo(b.y + 0.01), reason: 'line $i');
          expect(out[i].collides, isFalse);
        }
      }
    });

    test('pushed down on ruled paper, a box lands on the next free ruled line', () {
      final ruling = lined();
      final r = ruling.baselines;
      final out = layout([
        input('a', 'x' * 60, geo(baseline: r[4], left: 100)),
        input('b', 'next line', geo(baseline: r[5], left: 100)),
      ], style: const ConvertStyle(evenSize: true), ruling: ruling);
      expect(out[0].fit, ConvertFit.wrapped);
      expect(out[0].item.height, closeTo(2 * ruling.spacing, 1e-9), reason: 'two lines, one ruling apart');
      expect(out[1].baselineY, r[6], reason: 'the wrapped line took rule 5');
      expect(out[1].snapped, isTrue);
    });

    test('a line stays clear of an unchecked line below it (matching the handwriting)', () {
      final lines = [
        input('a', 'hello there', geo(baseline: 300, xHeight: 12)),
        input('b', 'ink stays', geo(baseline: 318, xHeight: 12, inkTop: 306), include: false),
      ];
      final out = layout(lines);
      expect(out, hasLength(1));
      final a = out.single.item;
      expect(a.y + a.height, lessThanOrEqualTo(306 + 0.01));
    });

    test('an even or chosen size is never made smaller for the writing around it', () {
      final lines = [
        input('a', 'hello there', geo(baseline: 300, xHeight: 12)),
        input('b', 'ink stays', geo(baseline: 318, xHeight: 12, inkTop: 306), include: false),
        input('c', 'tight', geo(baseline: 330, xHeight: 12)),
      ];
      expect(layout(lines, style: const ConvertStyle(fixedSize: 30)).map((l) => l.item.fontSize), [30, 30]);
      expect(layout(lines, style: const ConvertStyle(evenSize: true), ruling: lined()).map((l) => l.item.fontSize),
          [16, 16]);
    });

    test('the last resort is flagged when nothing small enough fits', () {
      final lines = [
        input('a', 'hello there my friend', geo(baseline: 300)),
        input('b', 'x', geo(baseline: 302, xHeight: 1, inkTop: 290)),
      ];
      final out = layout(lines);
      expect(out[0].item.fontSize, greaterThanOrEqualTo(ConvertConfig.absoluteMinSize));
      expect(out[0].collides, isTrue);
    });

    test('lines come back in input order', () {
      final out = layout([
        input('a', 'one', geo(baseline: 200)),
        input('b', 'two', geo(baseline: 260)),
        input('c', 'three', geo(baseline: 320)),
      ]);
      expect([for (final l in out) l.id], ['a', 'b', 'c']);
      expect([for (final l in out) l.item.text], ['one', 'two', 'three']);
      expect({for (final l in out) l.item.id}, hasLength(3));
    });
  });

  group('included lines and colour', () {
    test('unchecked and empty lines get no box', () {
      final out = layout([
        input('a', 'one', geo(baseline: 200)),
        input('b', 'two', geo(baseline: 260), include: false),
        input('c', '   ', geo(baseline: 320)),
        input('d', 'four', geo(baseline: 380)),
      ]);
      expect([for (final l in out) l.id], ['a', 'd']);
    });

    test('keeps the ink colour of each line', () {
      final out = layout([
        input('a', 'one', geo(baseline: 200), color: 0xFF0D47A1),
        input('b', 'two', geo(baseline: 260), color: 0xFFB71C1C),
      ]);
      expect(out[0].item.color, 0xFF0D47A1);
      expect(out[1].item.color, 0xFFB71C1C);
    });

    test('a colour override wins', () {
      final out = layout([
        input('a', 'one', geo(baseline: 200), color: 0xFF0D47A1),
        input('b', 'two', geo(baseline: 260), color: 0xFFB71C1C),
      ], style: const ConvertStyle(colorOverride: 0xFF1E1E1E));
      expect(out.map((l) => l.item.color), everyElement(0xFF1E1E1E));
    });
  });

  group('with the real text engine', () {
    test('the first baseline lands on the handwriting baseline for every font', () {
      for (final font in FontKind.values) {
        final out = layout(
          [input('a', 'Hello world', geo(baseline: 333.5, xHeight: 9))],
          style: ConvertStyle(font: font),
          metrics: const FlutterTextMetrics(),
        );
        final item = out.single.item;
        final painter = layoutTextItem(item);
        addTearDown(painter.dispose);
        final first = painter.computeLineMetrics().first.baseline;
        expect(item.y + first, closeTo(333.5, 0.01), reason: font.name);
      }
    });

    test('the stored height is what the editor measures', () {
      final out = layout(
        [input('a', 'Hello world, how are you today', geo(baseline: 333, xHeight: 9))],
        style: const ConvertStyle(bold: true),
        metrics: const FlutterTextMetrics(),
      );
      final item = out.single.item;
      expect(item.height, closeTo(TextBoxEditor.measureHeight(item), 1e-9));
    });

    test('a single-line box does not wrap in the real engine', () {
      final out = layout(
        [input('a', 'Hello world, how are you today', geo(baseline: 333, xHeight: 9))],
        metrics: const FlutterTextMetrics(),
      );
      final item = out.single.item;
      final painter = layoutTextItem(item);
      addTearDown(painter.dispose);
      expect(painter.computeLineMetrics(), hasLength(1));
    });

    test('a long line fits the page: it shrinks or wraps, never overflows', () {
      final out = layout(
        [input('a', 'The quick brown fox jumps over the lazy dog ' * 4, geo(left: 60, baseline: 333, xHeight: 9))],
        metrics: const FlutterTextMetrics(),
      );
      final item = out.single.item;
      expect(item.x + item.width, lessThanOrEqualTo(595 - ConvertConfig.rightMargin + 1e-6));
    });
  });

  group('even size', () {
    test('fits the ruling, 16 pt on paper without lines', () {
      expect(evenFontSize(lined()), 16, reason: '26 pt ruling (the default)');
      expect(evenFontSize(PageRuling.of(const Paper(spacingPt: 20), 595, 842)), 12);
      expect(evenFontSize(PageRuling.of(const Paper(spacingPt: 32), 595, 842)), 20);
      expect(evenFontSize(null), ConvertConfig.defaultFixedSize);
    });

    test('every line gets it, however big the handwriting', () {
      final out = layout([
        input('a', 'small', geo(baseline: 100, xHeight: 6)),
        input('b', 'big', geo(baseline: 160, xHeight: 16)),
      ], style: const ConvertStyle(evenSize: true));
      expect(out.map((l) => l.item.fontSize), [16, 16]);
    });

    test('a long line wraps instead of shrinking (custom sizes too)', () {
      for (final style in const [ConvertStyle(evenSize: true), ConvertStyle(fixedSize: 16)]) {
        final l = layout([input('a', 'x' * 80, geo())], style: style).single;
        expect(l.item.fontSize, 16);
        expect(l.fit, ConvertFit.wrapped);
        expect(l.item.x + l.item.width, lessThanOrEqualTo(595 - ConvertConfig.rightMargin + 1e-9));
        expect(l.item.height, closeTo(2 * 1.2 * 16, 1e-9), reason: 'two lines');
      }
    });
  });

  group('joining lines into sentences', () {
    // The first line runs to the right edge (ink to x 560 of 595) without a
    // full stop; the second starts at the left, one line lower.
    List<LayoutLineInput> sentence({String first = 'Neurons send signals', double right = 560, double drop = 26}) => [
          input('a', first, geo(baseline: 300, right: right)),
          input('b', 'to other neurons.', geo(baseline: 300 + drop, left: 102)),
        ];

    test('a sentence over two lines becomes one box that wraps at the margin', () {
      final out = layout(sentence(), style: const ConvertStyle(evenSize: true, joinLines: true), ruling: lined());
      final box = out.single;
      expect(box.item.text, 'Neurons send signals to other neurons.');
      expect(box.members, ['a', 'b']);
      expect(box.item.x, 100);
      expect(box.item.fontSize, 16);
      // 38 chars * 8 = 304 + slack: fits on one line here, one ruling tall
      // (the ruling is its line spacing).
      expect(box.item.lineSpacing, 26);
      expect(box.item.height, closeTo(26, 1e-9));
    });

    test('a long joined sentence wraps at the right margin', () {
      final out = layout([
        input('a', 'x' * 50, geo(baseline: 300, right: 570)),
        input('b', 'y' * 50, geo(baseline: 326, left: 100)),
      ], style: const ConvertStyle(evenSize: true, joinLines: true), ruling: lined());
      final box = out.single;
      expect(box.item.width, closeTo(595 - ConvertConfig.rightMargin - 100, 1e-9));
      expect(box.fit, ConvertFit.wrapped);
    });

    test('three lines join; matching the handwriting, the joined box wraps rather than shrinks', () {
      final out = layout([
        input('a', 'one two three', geo(baseline: 300, right: 565)),
        input('b', 'four five six', geo(baseline: 326, right: 570)),
        input('c', 'seven.', geo(baseline: 352)),
      ], style: const ConvertStyle(joinLines: true), ruling: lined());
      expect(out.single.members, ['a', 'b', 'c']);
      expect(out.single.item.text, 'one two three four five six seven.');
    });

    test('lines are kept apart when the sentence ended, the line was short, or far below', () {
      const style = ConvertStyle(evenSize: true, joinLines: true);
      expect(layout(sentence(first: 'Neurons send signals.'), style: style, ruling: lined()), hasLength(2));
      expect(layout(sentence(first: 'Key terms:'), style: style, ruling: lined()), hasLength(2));
      expect(layout(sentence(drop: 80), style: style, ruling: lined()), hasLength(2), reason: 'a new paragraph');
      final indented = [
        input('a', 'Neurons send signals', geo(baseline: 300, right: 560)),
        input('b', 'to other neurons.', geo(baseline: 326, left: 300)),
      ];
      expect(layout(indented, style: style, ruling: lined()), hasLength(2));
    });

    test('a short line joins when the words carry on', () {
      const style = ConvertStyle(evenSize: true, joinLines: true);
      // Mariam's and the owner's writing: lines break long before the edge,
      // and big handwriting skips a ruled line.
      final ruling = lined();
      final r = ruling.baselines;
      List<LaidOutLine> two(String a, String b, {int skip = 2}) => layout([
            input('a', a, geo(baseline: r[4], right: 330)),
            input('b', b, geo(baseline: r[4 + skip], left: 104, right: 330)),
          ], style: style, ruling: ruling);
      expect(two('I am the danger. When', 'a man gets knocked').single.item.text,
          'I am the danger. When a man gets knocked', reason: 'ends on a word no sentence ends on');
      // v1.10.0: a lowercase start alone no longer joins: the writer had
      // room for "even" and went to a new line (notes rarely end in a full
      // stop; v1.9.0 joined a page of them into one paragraph).
      expect(two('The lines are not auto joining', 'even when a sentence is not'), hasLength(2),
          reason: 'room was left for the next word');
      expect(two('Neurons send signals', 'to other neurons.', skip: 1), hasLength(2), reason: 'room was left for "to"');
      expect(two('signals travel along the axon,', 'Then they cross'), hasLength(1), reason: 'a comma');
      expect(two('a man gets knocked', 'The lines are not joining'), hasLength(2), reason: 'a new sentence');
      expect(two('Neurons send signals', 'to other neurons.', skip: 3), hasLength(2), reason: 'too far below');
      expect(two('Key points of the lecture', '- neurons send signals'), hasLength(2), reason: 'a list item');
    });

    test('a line that ran out of room carries on in lowercase, not with a capital', () {
      const style = ConvertStyle(evenSize: true, joinLines: true);
      final ruling = lined();
      final r = ruling.baselines;
      // The next line's first word gets its share of the 230 pt of ink by
      // letters: 'signals' about 77 pt, 'I' 11 pt. The margin is at 571.
      List<LaidOutLine> two(String b, {double right = 555}) => layout([
            input('a', 'Neurons pass electrical', geo(baseline: r[4], right: right)),
            input('b', b, geo(baseline: r[5], left: 100, right: 330)),
          ], style: style, ruling: ruling);
      expect(two('signals to each other').single.item.text, 'Neurons pass electrical signals to each other');
      expect(two('Signals are fast'), hasLength(2), reason: 'a capital starts something new');
      expect(two('I think they are fast'), hasLength(1), reason: '"I" is no new start');
      expect(two('signals to each other', right: 420), hasLength(2), reason: 'there was room for "signals"');
    });

    test('a page of notes without full stops stays line by line (Mariam, 1.9.0)', () {
      const style = ConvertStyle(evenSize: true, joinLines: true);
      final ruling = lined();
      final r = ruling.baselines;
      final notes = [
        ('Synapse types', 220.0),
        ('chemical synapses use neurotransmitters between cells', 470.0),
        ('electrical synapses use gap junctions which are faster than', 480.0),
        ('chemical ones', 210.0),
        ('Action potential steps', 300.0),
        ('resting potential is about minus seventy', 430.0),
        ('depolarisation opens the sodium channels', 440.0),
      ];
      final out = layout([
        for (final (i, (text, right)) in notes.indexed) input('l$i', text, geo(baseline: r[4 + i], right: right)),
      ], style: style, ruling: ruling);
      expect(out.map((l) => l.item.text), [
        'Synapse types',
        'chemical synapses use neurotransmitters between cells',
        'electrical synapses use gap junctions which are faster than chemical ones',
        'Action potential steps',
        'resting potential is about minus seventy',
        'depolarisation opens the sodium channels',
      ]);
    });

    test("a list written one word per line stays a list (Mariam's step 7)", () {
      const style = ConvertStyle(evenSize: true, joinLines: true);
      final ruling = lined();
      final r = ruling.baselines;
      final out = layout([
        for (final (i, w) in ['brain', 'neurons', 'synapse'].indexed)
          input('l$i', w, geo(baseline: r[4 + 2 * i], right: 160)),
      ], style: style, ruling: ruling);
      expect(out.map((l) => l.item.text), ['brain', 'neurons', 'synapse']);
    });

    test('textCarriesOn and startsListItem', () {
      expect(textCarriesOn('the cell is', 'Neuron'), isTrue);
      expect(textCarriesOn('brain', 'neurons'), isFalse);
      expect(textCarriesOn('sodium ions', 'potassium ions'), isFalse);
      expect(textCarriesOn('ions flow in through', 'channels'), isTrue);
      expect(textCarriesOn('ions flow in quickly', 'channels'), isFalse, reason: 'one word below');
      for (final item in ['- a', '• a', '* a', '1. a', '2) a', 'a) a', '(3) a']) {
        expect(startsListItem(item), isTrue, reason: item);
      }
      expect(startsListItem('alpha waves'), isFalse);
      expect(startsListItem('3.5 volts'), isFalse);
    });

    test('with the setting off every line stays its own box', () {
      expect(layout(sentence(), style: const ConvertStyle(evenSize: true), ruling: lined()), hasLength(2));
    });

    test('a line that stays handwriting is never joined', () {
      final lines = sentence();
      final out = layout([lines[0], input('b', 'to other neurons.', lines[1].geometry, include: false)],
          style: const ConvertStyle(evenSize: true, joinLines: true), ruling: lined());
      expect(out.single.members, ['a']);
      expect(out.single.item.text, 'Neurons send signals');
    });

    test('joinSentence and endsSentence', () {
      expect(joinSentence('a neuro-', 'transmitter'), 'a neurotransmitter');
      expect(joinSentence('well-', 'Known'), 'well- Known');
      expect(joinSentence('one ', ' two'), 'one two');
      expect(endsSentence('the end.'), isTrue);
      expect(endsSentence('really?"'), isTrue);
      expect(endsSentence('(see above)'), isFalse);
      expect(endsSentence('the end'), isFalse);
    });
  });

  group('PDF writing margins', () {
    // A 595 pt PDF page with 150 pt margins each side.
    const pdf = PageMeta(id: 'p', width: 895, height: 842, pdfPageIndex: 0, marginLeft: 150, marginRight: 150);

    test('each margin is a column with the margin paper\'s lines; the PDF between has none', () {
      final left = textColumnAt(pdf, 20)!;
      expect(left.left, 0);
      expect(left.right, 150 - ConvertConfig.pdfEdgeGap);
      expect(left.ruling, isNotNull);
      final middle = textColumnAt(pdf, 400)!;
      expect((middle.left, middle.ruling), (150, null));
      final right = textColumnAt(pdf, 800)!;
      expect(right.left, 745 + ConvertConfig.pdfEdgeGap);
      expect(right.right, 895 - ConvertConfig.rightMargin);
      expect(textColumnAt(const PageMeta(id: 'q'), 20), isNull, reason: 'a plain page is one page');
      expect(textColumnAt(const PageMeta(id: 'r', pdfPageIndex: 0), 20), isNull, reason: 'no margins');
    });

    test('typed notes in a margin wrap at the PDF\'s edge and sit on its lines', () {
      final column = textColumnAt(pdf, 20)!;
      final ruling = column.ruling!;
      final out = layoutPage(
        pageWidth: pdf.width,
        pageHeight: pdf.height,
        lines: [input('a', 'the hippocampus consolidates memories', geo(left: 20, right: 140, baseline: ruling.baselines[5] + 3))],
        style: const ConvertStyle(evenSize: true),
        ruling: ruling,
        column: column,
        metrics: const FakeMetrics(),
      ).single;
      expect(out.item.x, greaterThanOrEqualTo(0));
      expect(out.item.x + out.item.width, lessThanOrEqualTo(column.right + 1e-9));
      expect(out.snapped, isTrue);
      expect(out.baselineY, ruling.baselines[5]);
      expect(out.item.height, greaterThan(ruling.spacing), reason: 'it wraps inside the margin');
    });

    test('a margin line that ran to the PDF\'s edge carries on below', () {
      final column = textColumnAt(pdf, 20)!;
      final ruling = column.ruling!;
      bool joins(double right) => continuesOnNextLine(
            line: geo(left: 20, right: right, baseline: ruling.baselines[3]),
            text: 'Neurons send',
            next: geo(left: 20, right: 100, baseline: ruling.baselines[4]),
            nextText: 'signals',
            pageWidth: pdf.width,
            ruling: ruling,
            column: column,
          );
      expect(joins(140), isTrue);
      expect(joins(30), isFalse, reason: '"signals" (80 pt) fitted in the margin after it');
    });
  });
}
