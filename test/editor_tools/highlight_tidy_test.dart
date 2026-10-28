import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/tools/highlight_tidy.dart';
import 'package:neatink/features/editor/tools/selection_transform.dart';
import 'package:neatink/ink/affine2.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';

import '../beautify/synthetic_font.dart';

/// Three handwritten words (x-height 10) on a baseline at y = 300, starting
/// at x = 100 + 0, 52 and 110, optionally on a slope of [rotateDeg].
List<Stroke> writing({double rotateDeg = 0}) {
  final m = distortion(x: 100, y: 300, rotateDeg: rotateDeg);
  return [
    for (final (i, (word, x)) in [('hello', 0.0), ('online', 52.0), ('hen', 110.0)].indexed)
      ...toStrokes(
        [for (final p in wordPolylines(word)) [for (final v in p) Vec2(v.x + x, v.y)]],
        m: m,
        prefix: 'w$i',
      ),
  ];
}

/// The x-extent of word [i] of [writing].
({double left, double right}) wordExtent(List<Stroke> strokes, int i) {
  final mine = strokes.where((s) => s.id.startsWith('w$i-'));
  return (
    left: mine.map((s) => s.bounds.left).reduce(math.min),
    right: mine.map((s) => s.bounds.right).reduce(math.max),
  );
}

/// A wobbly highlighter swipe from [x0] to [x1] around height [y].
Stroke swipe(double x0, double x1, double y, {double size = 14, double wobble = 2, String id = 'h'}) {
  final n = 30;
  return Stroke(
    id: id,
    tool: StrokeTool.highlighter,
    color: 0xFFFFEB3B,
    size: size,
    raw: [
      for (var i = 0; i < n; i++)
        InkPoint(x0 + (x1 - x0) * i / (n - 1), y + wobble * math.sin(i * 1.3), 0.5, i * 10),
    ],
  );
}

void main() {
  group('over handwriting', () {
    final ink = writing();
    final lines = inkHighlightLines(swipe(100, 200, 293), ink);
    final hello = wordExtent(ink, 0), online = wordExtent(ink, 1), hen = wordExtent(ink, 2);

    test('the writing is one line with a band from 1.6 x-heights over the baseline to 0.35 under', () {
      expect(lines, hasLength(1));
      final l = lines.single;
      expect(l.top, closeTo(300 - 16, 1.5));
      expect(l.bottom, closeTo(300 + 3.5, 1.5));
      expect(l.words, hasLength(3));
    });

    test('a wobbly swipe becomes a straight band over the line, trimmed to the words', () {
      // From the gap before "hello" to a little into "hen" (not enough to take it).
      final h = swipe(hello.left - 6, hen.left + 3, 291);
      final t = tidyHighlight(h, lines)!;
      final band = lines.single;
      expect(t.id, h.id);
      expect(t.raw, h.raw, reason: 'the drawn stroke is kept');
      expect(t.size, closeTo(band.thickness, 1e-9));
      expect(t.rawSize, 14);
      final ys = t.points.map((p) => p.y).toSet();
      expect(ys.every((y) => (y - band.centerAt(band.left)).abs() < 0.02), isTrue, reason: 'straight and on the line');
      final pad = 0.12 * band.thickness;
      expect(t.points.first.x, closeTo(hello.left - pad, 0.02));
      expect(t.points.last.x, closeTo(online.right + pad, 0.02));
      // evenly spaced, ordered
      for (var i = 1; i < t.points.length; i++) {
        expect(t.points[i].x, greaterThan(t.points[i - 1].x));
      }
    });

    test('a swipe ending past the last word is trimmed back to it', () {
      final t = tidyHighlight(swipe(online.left + 2, hen.right + 40, 296), lines)!;
      final pad = 0.12 * lines.single.thickness;
      expect(t.points.first.x, closeTo(online.left - pad, 0.02));
      expect(t.points.last.x, closeTo(hen.right + pad, 0.02));
    });

    test('a swipe inside one long word covers that word', () {
      final t = tidyHighlight(swipe(online.left + 8, online.left + 16, 294), lines)!;
      final pad = 0.12 * lines.single.thickness;
      expect(t.points.first.x, closeTo(online.left - pad, 0.02));
      expect(t.points.last.x, closeTo(online.right + pad, 0.02));
    });

    test('on a sloped line the band follows the slope', () {
      final sloped = writing(rotateDeg: 4);
      final l = inkHighlightLines(swipe(100, 220, 300), sloped);
      expect(l, hasLength(1));
      final h = swipe(110, 200, 300 + math.tan(4 * math.pi / 180) * 50 - 6);
      final t = tidyHighlight(h, l)!;
      final rise = (t.points.last.y - t.points.first.y) / (t.points.last.x - t.points.first.x);
      expect(rise, closeTo(math.tan(4 * math.pi / 180), 0.01));
    });
  });

  group('left alone', () {
    final lines = inkHighlightLines(swipe(100, 200, 293), writing());

    test('pen strokes and snapped shapes', () {
      final pen = swipe(100, 200, 293).copyWith(tool: StrokeTool.pen);
      expect(tidyHighlight(pen, lines), isNull);
      final shape = swipe(100, 200, 293).copyWith(shape: ShapeKind.line);
      expect(tidyHighlight(shape, lines), isNull);
    });

    test('a steep stroke, a scribble over two lines and a dot', () {
      final steep = Stroke(
        id: 's',
        tool: StrokeTool.highlighter,
        color: 0xFFFFEB3B,
        size: 14,
        raw: [for (var i = 0; i < 10; i++) InkPoint(100 + i * 2.0, 260 + i * 6.0, 0.5, i)],
      );
      expect(tidyHighlight(steep, lines), isNull);
      expect(tidyHighlight(swipe(100, 200, 293, wobble: 30), lines), isNull);
      expect(tidyHighlight(swipe(150, 152, 293), lines), isNull);
    });
  });

  test('a swipe over no text is only straightened, as wide as drawn', () {
    final h = swipe(100, 300, 500, wobble: 3);
    final t = tidyHighlight(h, const [])!;
    expect(t.size, 14);
    expect(t.points.first.x, closeTo(100, 0.01));
    expect(t.points.last.x, closeTo(300, 0.01));
    final ys = t.points.map((p) => p.y).toList();
    expect(ys.reduce(math.max) - ys.reduce(math.min), lessThan(1.0));
  });

  test('a swipe far above or below the line is not snapped to it', () {
    final lines = inkHighlightLines(swipe(100, 200, 293), writing());
    final t = tidyHighlight(swipe(110, 200, 250), lines)!;
    expect(t.size, 14, reason: 'only straightened');
  });

  test('Restore original gives back the drawn points and width', () {
    final lines = inkHighlightLines(swipe(100, 200, 293), writing());
    final h = swipe(100, 200, 293);
    final t = tidyHighlight(h, lines)!;
    final back = restoreOriginalStroke(t);
    expect(back.points, h.raw);
    expect(back.size, 14);
    expect(back.rawSize, isNull);
  });

  test('rawSize survives JSON and scales with a resize', () {
    final t = tidyHighlight(swipe(100, 200, 293), inkHighlightLines(swipe(100, 200, 293), writing()))!;
    final again = Stroke.fromJson(t.toJson());
    expect(again.rawSize, 14);
    expect(again.size, t.size);
    expect(Stroke.fromJson(swipe(0, 10, 0).toJson()).rawSize, isNull);
    final bigger = t.transformed(Affine2.scaling(2, 2));
    expect(bigger.rawSize, closeTo(28, 1e-9));
  });

  test('printed lines are built from word boxes, one line per row', () {
    // (wordBoxHighlightLines lives in the integration; the band of a printed
    // line is the union of its word boxes)
    const l = HighlightLine(left: 0, right: 100, top: 10, bottom: 22, words: [(left: 0, right: 40), (left: 50, right: 100)]);
    final t = tidyHighlight(swipe(-5, 70, 18, size: 22), const [l])!;
    expect(t.size, 12);
    expect(t.points.first.x, closeTo(0 - 0.12 * 12, 0.02));
    expect(t.points.last.x, closeTo(100 + 0.12 * 12, 0.02));
  });
}
