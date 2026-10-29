import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/features/editor/integrations/convert/auto_convert_dots.dart';
import 'package:neatink/features/editor/integrations/convert/auto_convert_merge.dart';
import 'package:neatink/features/editor/integrations/convert/convert_layout.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';

/// Every character is 8 points wide at size 16; first baseline 12.8 below
/// the top; a line 19.2 tall.
class _Metrics extends ConvertTextMetrics {
  const _Metrics();

  @override
  double firstBaseline(TextItem item) => 0.8 * item.fontSize;

  @override
  double naturalWidth(TextItem item) => item.text.length * 0.5 * item.fontSize;

  @override
  double heightOf(TextItem item) => 1.2 * item.fontSize;
}

Stroke stroke(String id, double x, double y, double w, double h) => Stroke(
      id: id,
      tool: StrokeTool.pen,
      color: 0xFF000000,
      size: 2,
      raw: [InkPoint(x, y, 0.5, 0), InkPoint(x + w, y + h, 0.5, 20)],
    );

void main() {
  test('dots and short bars are dots; letters are not', () {
    expect(onlyDots([stroke('a', 0, 0, 2, 2)], reference: 26), isTrue, reason: 'an i-dot');
    expect(onlyDots([stroke('a', 0, 0, 12, 1)], reference: 26), isTrue, reason: 'a t-bar');
    expect(onlyDots([stroke('a', 0, 0, 1, 14)], reference: 26), isFalse, reason: 'an i or l stem');
    expect(onlyDots([stroke('a', 0, 0, 30, 1)], reference: 26), isFalse, reason: 'a long line');
    expect(onlyDots([stroke('a', 0, 0, 2, 2), stroke('b', 0, 0, 10, 10)], reference: 26), isFalse);
    expect(onlyDots(const [], reference: 26), isFalse);
  });

  group('lateDotsTarget', () {
    // "hello" typed at (100, 84): text 40 wide, baseline 96.8; the
    // handwriting it replaced ended at x 160 on baseline 100, x-height 10.
    const box = TextItem(id: 'b', x: 100, y: 84, width: 44, height: 19.2, text: 'hello', fontSize: 16);
    const memory = AutoBoxVersion(box, 160, 100, inkXHeight: 10);
    LateDots? target(List<Stroke> s, {bool remembered = true, TextItem item = box}) => lateDotsTarget(
          strokes: s,
          boxes: [item],
          memory: (_) => remembered ? memory : null,
          metrics: const _Metrics(),
        );

    test('a dot at the end of the writing, on its baseline, is a full stop', () {
      final t = target([stroke('p', 162, 98, 2, 2)])!;
      expect(t.box.id, 'b');
      expect(t.mark, '.');
    });

    test('a full stop a little below the line, as small writing puts it, still counts', () {
      expect(target([stroke('p', 162, 104, 2, 2)])!.mark, '.', reason: '0.5 x-height below');
      expect(target([stroke('p', 162, 108, 2, 2)])!.mark, '.', reason: '0.9 x-height below');
      expect(target([stroke('p', 162, 91, 2, 2)])!.mark, '.', reason: 'just above the line');
      expect(target([stroke('i', 162, 84, 2, 2)])!.mark, isNull, reason: 'an i-dot height');
    });

    test('one reaching below the baseline is a comma', () {
      expect(target([stroke('c', 162, 98, 2, 7)])!.mark, ',');
      expect(target([stroke('c', 161, 97, 3, 12)])!.mark, ',', reason: 'a long comma');
    });

    test('a dot over a full stop is a colon, over a comma a semicolon', () {
      expect(target([stroke('u', 162, 92, 2, 2), stroke('l', 162, 98, 2, 2)])!.mark, ':');
      expect(target([stroke('u', 162, 92, 2, 2), stroke('c', 162, 98, 2, 7)])!.mark, ';');
      // Not stacked: nothing added.
      expect(target([stroke('u', 150, 92, 2, 2), stroke('l', 162, 98, 2, 2)])!.mark, isNull);
    });

    test('a dot above the writing is an i-dot: it goes, nothing is added', () {
      final t = target([stroke('i', 130, 78, 2, 2)])!;
      expect(t.mark, isNull);
    });

    test('nothing is added after punctuation, or for several dots', () {
      expect(target([stroke('p', 162, 98, 2, 2)], item: box.copyWith(text: 'hello!'))!.mark, isNull);
      expect(target([stroke('p', 162, 98, 2, 2), stroke('q', 166, 98, 2, 2)])!.mark, isNull);
    });

    test('far from the text and its writing it belongs to nothing', () {
      expect(target([stroke('f', 300, 98, 2, 2)]), isNull);
      expect(target([stroke('f', 130, 140, 2, 2)]), isNull, reason: 'the line below');
    });

    test('without memory the typed text is the area', () {
      final t = target([stroke('p', 142, 95, 2, 2)], remembered: false)!;
      expect(t.mark, '.');
      expect(target([stroke('f', 200, 95, 2, 2)], remembered: false), isNull);
    });
  });
}
