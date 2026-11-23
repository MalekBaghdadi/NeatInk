import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/integrations/convert/convert_scope.dart';
import 'package:neatink/features/editor/tools/selection.dart';
import 'package:neatink/ink/line_style.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/recognition/stroke_grouping.dart';

import '../beautify/synthetic_font.dart';
import '../editor/integrations/convert/harness.dart';

/// Handwriting is never dashed, wavy or double: Convert must leave such lines
/// as the ink they are (underlines, borders, decoration).
const List<LineSettings> styles = [
  LineSettings(style: LineStyle.dashed),
  LineSettings(style: LineStyle.dotted),
  LineSettings(style: LineStyle.wavy),
  LineSettings(style: LineStyle.zigzag),
  LineSettings(style: LineStyle.parallel),
];

List<Stroke> restyled(List<Stroke> strokes, LineSettings line, String prefix) => [
      for (final s in strokes) s.copyWith(id: '$prefix${s.id}', line: line),
    ];

void main() {
  group('groupStrokes', () {
    final word = makeWord('hello');

    test('ignores strokes with a line style', () {
      final plain = groupStrokes(word);
      expect(plain, hasLength(1));
      for (final line in styles) {
        final styled = restyled(word, line, 'x');
        expect(groupStrokes(styled), isEmpty, reason: line.style.name);
        final mixed = groupStrokes([...word, ...styled]);
        expect(mixed, hasLength(1), reason: line.style.name);
        expect(mixed.single.strokes.length, plain.single.strokes.length);
        expect([for (final s in mixed.single.strokes) s.id],
            isNot(contains(startsWith('x'))));
      }
    });

    test('a solid stroke that was restyled to solid again is read as before', () {
      final back = restyled(word, const LineSettings(style: LineStyle.wavy), 'x')
          .map((s) => s.copyWith(line: LineSettings.solid))
          .toList();
      expect(groupStrokes(back), hasLength(1));
    });
  });

  group('hasConvertibleStrokes', () {
    testWidgets('a selection of styled lines has nothing to convert',
        (tester) async {
      final plain = makeWord('hello', prefix: 'p');
      final dashed = restyled(makeWord('hello', prefix: 'd'),
          const LineSettings(style: LineStyle.dashed), '');
      final h = await ConvertHarness.open(tester, pages: [
        [...plain, ...dashed],
      ]);
      bool convertible(Iterable<Stroke> strokes) => hasConvertibleStrokes(
          h.controller,
          Selection.fromPage(h.page,
              pageId: h.pageIdAt(0), strokeIds: [for (final s in strokes) s.id]));

      expect(convertible(dashed), isFalse);
      expect(convertible(plain), isTrue);
      expect(convertible([...plain, ...dashed]), isTrue,
          reason: 'one readable stroke is enough');
      expect(convertible(const []), isFalse);
    });
  });

  group('auto-convert', () {
    testWidgets('leaves a styled stroke alone and still converts the writing',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: FakeRecognizer({'aw0': ('hello', 0.9)}),
          autoConvert: true);
      final writing = writeLine('a', ['hello'], y: 104);
      final underline =
          restyled([writing.first], const LineSettings(style: LineStyle.wavy), 'u-');
      await h.write(underline);
      await tester.pump(const Duration(milliseconds: 2000));
      expect(h.recognizer.calls, 0, reason: 'only a wavy line was drawn');
      expect(h.page.strokes, hasLength(1));

      await h.write(writing);
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump();
      expect([for (final t in h.page.texts) t.text], ['hello']);
      expect([for (final s in h.page.strokes) s.id], ['u-${writing.first.id}'],
          reason: 'the wavy line is still ink');
    });

    testWidgets('every style is skipped', (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: FakeRecognizer(const {}), autoConvert: true);
      final base = writeLine('a', ['hello'], y: 104).first;
      await h.write([
        for (final line in styles)
          base.copyWith(id: 's-${line.style.name}', line: line),
      ]);
      await tester.pump(const Duration(milliseconds: 2000));
      expect(h.recognizer.calls, 0);
      expect(h.page.strokes, hasLength(styles.length));
    });
  });
}
