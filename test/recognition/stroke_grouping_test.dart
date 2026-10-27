import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:neatink/recognition/stroke_grouping.dart';

import '../beautify/synthetic_font.dart';

/// A 'k' written as three strokes: stem and two arms (x-height 10, tall 19).
List<List<Vec2>> kPolylines() => [
      densify(const [Vec2(0, -fontTall), Vec2(0, 0)]),
      densify(const [Vec2(7, -10), Vec2(0, -4)]),
      densify(const [Vec2(2, -6), Vec2(8, 0)]),
    ];

/// Several words on one line, [offsets] apart (the first at 0), with [m]
/// applied. Polylines of word i are shifted right by offsets[i].
List<Stroke> line(List<String> words, List<double> offsets,
    {String prefix = 'l',
    double rotateDeg = 0,
    double x = 100,
    double y = 300,
    double scale = 1,
    double gap = 4}) {
  final polylines = <List<Vec2>>[];
  for (var i = 0; i < words.length; i++) {
    for (final p in wordPolylines(words[i], gap: gap)) {
      polylines.add([for (final v in p) Vec2(v.x + offsets[i], v.y)]);
    }
  }
  return toStrokes(polylines,
      prefix: prefix, m: distortion(rotateDeg: rotateDeg, x: x, y: y, scale: scale));
}

/// Glyphs the shared synthetic font lacks (x-height 10, tall 19).
Glyph localGlyph(String ch) {
  switch (ch) {
    case 't':
      return Glyph([
        [const Vec2(3, -14), const Vec2(3, 0)],
        [const Vec2(0, -9), const Vec2(6, -9)],
      ], 6);
    case 'b':
      return Glyph([
        [const Vec2(0, -fontTall), const Vec2(0, 0)],
        arc(4, -5, 4, 5, 180, 540),
      ], 8);
    case 'k':
      return Glyph(kPolylines(), 8);
    case 'a':
      return Glyph([
        arc(4, -5, 4, 5, 0, 360),
        [const Vec2(8, -10), const Vec2(8, 0)],
      ], 8);
    case 'c':
      return Glyph([arc(4, -5, 4, 5, 40, 320)], 8);
    case 'O':
      return Glyph([arc(5, -9.5, 5, 9.5, 90, 450)], 10);
    case '0':
      return Glyph([arc(4, -9.5, 4, 9.5, 90, 450)], 8);
    case '1':
      return Glyph([
        [const Vec2(1, -fontTall), const Vec2(1, 0)],
      ], 2);
    case '2':
      return Glyph([
        [
          const Vec2(0, -14),
          const Vec2(2, -18.5),
          const Vec2(6, -18.5),
          const Vec2(8, -14),
          const Vec2(0, 0),
          const Vec2(8, 0),
        ],
      ], 8);
    case '6':
      return Glyph([
        [
          const Vec2(6, -fontTall),
          const Vec2(1, -8),
          ...arc(4, -4.5, 4, 4.5, 160, 520, steps: 36).skip(1),
        ],
      ], 8);
    case '7':
      return Glyph([
        [const Vec2(0, -fontTall), const Vec2(8, -fontTall), const Vec2(2, 0)],
      ], 8);
  }
  return glyph(ch);
}

/// [text] written left to right on the baseline y = 0. Letters are [gap]
/// apart (or `gaps[i]` before the character at index i) and words are
/// [wordGap] apart; a space in [text] is the word gap.
List<Stroke> writeText(String text,
    {double gap = 4,
    double wordGap = 14,
    Map<int, double> gaps = const {},
    double scale = 1,
    String prefix = 'w'}) {
  final polylines = <List<Vec2>>[];
  var x = 0.0;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == ' ') {
      x += wordGap;
      continue;
    }
    if (i > 0 && text[i - 1] != ' ') x += gaps[i] ?? gap;
    final g = localGlyph(ch);
    for (final s in g.strokes) {
      polylines.add(densify([for (final p in s) Vec2(p.x + x, p.y)]));
    }
    x += g.width;
  }
  return toStrokes(polylines, prefix: prefix, m: distortion(scale: scale));
}

/// The number of strokes of every word, line by line.
List<int> strokeCounts(List<RecognizedLine> lines) =>
    [for (final l in lines) for (final w in l.words) w.strokes.length];

void main() {
  test('nothing in, nothing out', () {
    expect(groupStrokes(const []), isEmpty);
  });

  test('a k written as three strokes is one word', () {
    final k = toStrokes(kPolylines(), prefix: 'k', m: distortion());
    final lines = groupStrokes(k);
    expect(lines, hasLength(1));
    expect(lines.single.words, hasLength(1));
    expect(lines.single.words.single.strokes, hasLength(3));
  });

  test('letters of one word stay together, including a separate k', () {
    final polylines = <List<Vec2>>[...wordPolylines('hello')];
    for (final p in kPolylines()) {
      polylines.add([for (final v in p) Vec2(v.x + 43, v.y)]);
    }
    final lines = groupStrokes(toStrokes(polylines, m: distortion()));
    expect(lines.single.words, hasLength(1));
    expect(lines.single.words.single.strokes, hasLength(8));
  });

  test('two words are split by the gap, left to right', () {
    final strokes = line(['hello', 'online'], [0, 52]);
    final lines = groupStrokes(strokes);
    expect(lines, hasLength(1));
    final words = lines.single.words;
    expect(words, hasLength(2));
    expect(words[0].strokes, hasLength(5));
    expect(words[1].strokes, hasLength(7)); // the i has a dot
    expect(words[0].bounds.right, lessThan(words[1].bounds.left));
    expect(lines.single.left, closeTo(words[0].bounds.left, 1e-9));
    expect(lines.single.right, closeTo(words[1].bounds.right, 1e-9));
  });

  test('i-dots attach to their word', () {
    final lines = groupStrokes(line(['line', 'online'], [0, 45]));
    final words = lines.single.words;
    expect(words, hasLength(2));
    expect(words[0].strokes, hasLength(5)); // l, i + dot, n, e
    expect(words[1].strokes, hasLength(7));
  });

  test('wider letter spacing and larger writing still group the same', () {
    final lines = groupStrokes(line(['hello', 'online'], [0, 104], scale: 2));
    expect(lines.single.words, hasLength(2));
    expect(lines.single.words.first.strokes, hasLength(5));
  });

  test('three lines come back top to bottom whatever the input order', () {
    final a = line(['hello'], [0], prefix: 'a', y: 100);
    final b = line(['online'], [0], prefix: 'b', y: 140);
    final c = line(['hen', 'one'], [0, 44], prefix: 'c', y: 180);
    final lines = groupStrokes([...c, ...a, ...b]);
    expect(lines, hasLength(3));
    expect(lines[0].words.single.strokes.first.id, startsWith('a'));
    expect(lines[1].words.single.strokes.first.id, startsWith('b'));
    expect(lines[2].words, hasLength(2));
    expect(lines[2].words.first.strokes.first.id, startsWith('c'));
    expect(lines[0].baselineY, lessThan(lines[1].baselineY));
    expect(lines[1].baselineY, lessThan(lines[2].baselineY));
    expect(lines[0].baselineY, closeTo(100, 3));
    expect(lines[2].baselineY, closeTo(180, 3));
    expect(lines[1].xHeight, closeTo(10, 4));
  });

  test('lines closer together than three x-heights are still separated', () {
    final lines = groupStrokes([
      ...line(['hello', 'online'], [0, 52], prefix: 'a', y: 100),
      ...line(['hello', 'online'], [0, 52], prefix: 'b', y: 128),
    ]);
    expect(lines, hasLength(2));
    expect(lines.every((l) => l.words.length == 2), isTrue);
  });

  test('a rotated line is one line with its slope', () {
    final lines = groupStrokes(line(['hello', 'online'], [0, 52], rotateDeg: 8));
    expect(lines, hasLength(1));
    expect(lines.single.words, hasLength(2));
    expect(lines.single.baselineSlope, closeTo(math.tan(8 * math.pi / 180), 0.04));
    expect(lines.single.words.first.baselineSlope, lines.single.baselineSlope);
  });

  test('two rotated lines stay two lines', () {
    final lines = groupStrokes([
      ...line(['hello', 'online'], [0, 52], prefix: 'a', rotateDeg: 6, y: 200),
      ...line(['online', 'hello'], [0, 52], prefix: 'b', rotateDeg: 6, y: 245),
    ]);
    expect(lines, hasLength(2));
    expect(lines[0].words.first.strokes.first.id, startsWith('a'));
    expect(lines[1].words.first.strokes.first.id, startsWith('b'));
  });

  test('highlighter strokes and shapes are ignored', () {
    final pen = line(['hello'], [0]);
    final hl = Stroke(
      id: 'hl',
      tool: StrokeTool.highlighter,
      color: 0xFFFFFF00,
      size: 12,
      raw: [for (var x = 90.0; x < 160; x += 2) InkPoint(x, 295, 0.5, 0)],
    );
    final shape = Stroke(
      id: 'sh',
      tool: StrokeTool.pen,
      color: 0xFF000000,
      size: 2,
      shape: ShapeKind.rectangle,
      raw: [for (var x = 90.0; x < 160; x += 2) InkPoint(x, 330, 0.5, 0)],
    );
    final lines = groupStrokes([...pen, hl, shape]);
    expect(lines, hasLength(1));
    expect(lines.single.words.single.strokes.map((s) => s.id), isNot(contains('hl')));
    expect(lines.single.strokes.length, 5);
    expect(groupStrokes([hl, shape]), isEmpty);
  });

  test('a lone full stop stays its own group when far from any word', () {
    final word = line(['hello'], [0]);
    final dot = toStrokes([
      densify(const [Vec2(80, -0.3), Vec2(80, 0.3)]),
    ], prefix: 'dot', m: distortion());
    final lines = groupStrokes([...word, ...dot]);
    expect(lines, hasLength(1));
    expect(lines.single.words, hasLength(2));
  });

  test('a full stop right after a word joins it', () {
    final word = line(['hello'], [0]);
    final dot = toStrokes([
      densify(const [Vec2(42, -0.3), Vec2(42, 0.3)]),
    ], prefix: 'dot', m: distortion());
    final lines = groupStrokes([...word, ...dot]);
    expect(lines.single.words, hasLength(1));
    expect(lines.single.words.single.strokes, hasLength(6));
  });

  test('an expected x-height hint is accepted', () {
    final lines = groupStrokes(line(['hello', 'online'], [0, 52]), expectedXHeight: 10);
    expect(lines.single.words, hasLength(2));
  });

  group('adaptive word splitting', () {
    test('notebook with an uneven letter space stays one word', () {
      // Spaces of 7.5 and 8 (0.75 and 0.8 x-heights) before the b and the
      // k: wider than the fixed 0.6 x-height, but nowhere near a word gap
      // next to letter gaps of 0.4.
      final lines = groupStrokes(writeText('notebook', gaps: {4: 7.5, 7: 8}));
      expect(lines, hasLength(1));
      expect(lines.single.words, hasLength(1));
      expect(lines.single.words.single.strokes, hasLength(12));
    });

    test('the real word gaps next to it still split', () {
      final lines = groupStrokes(writeText('notebook 27 Oct', gaps: {4: 7.5, 7: 8}, wordGap: 16));
      expect(strokeCounts(lines), [12, 2, 4]); // notebook, 27, Oct
    });

    test('a k written a little apart is merged back into its word', () {
      // 11 is beyond the split threshold (10) but within 1.5 of it.
      final lines = groupStrokes(writeText('notebook', gaps: {7: 11}));
      expect(lines.single.words, hasLength(1));
      expect(lines.single.words.single.strokes, hasLength(12));
    });

    test('it is the fragment rule that rejoins that k', () {
      final lines = groupStrokes(
        writeText('notebook', gaps: {7: 11}),
        config: const GroupingConfig(fragmentMergeFactor: 0),
      );
      expect(strokeCounts(lines), [9, 3]);
    });

    test('a k clearly apart stays its own word', () {
      final lines = groupStrokes(writeText('notebook', gaps: {7: 17}));
      expect(strokeCounts(lines), [9, 3]);
    });

    test('single letters written apart stay separate: a b c', () {
      final far = groupStrokes(writeText('a b c', wordGap: 16));
      expect(strokeCounts(far), [2, 2, 1]);
      // ... even when they are close: fragments never merge into each other
      final near = groupStrokes(writeText('a b c', wordGap: 8));
      expect(strokeCounts(near), [2, 2, 1]);
    });

    test('numbers and words: 27 Oct 2026', () {
      final lines = groupStrokes(writeText('27 Oct 2026', wordGap: 16));
      expect(lines, hasLength(1));
      expect(strokeCounts(lines), [2, 4, 4]);
      final hinted = groupStrokes(writeText('27 Oct 2026', wordGap: 16), expectedXHeight: 10);
      expect(strokeCounts(hinted), [2, 4, 4]);
    });

    test('a lone 1 stays its own word even close to the preceding word', () {
      // The 1 is a straight bar: never taken for the fragment of a letter.
      final lines = groupStrokes(writeText('one 1', wordGap: 8));
      expect(strokeCounts(lines), [3, 1]);
    });

    test('a lone 0 is not merged either', () {
      final lines = groupStrokes(writeText('one 0', wordGap: 8));
      expect(strokeCounts(lines), [3, 1]);
    });

    test('wide letter spacing still splits at the word gap', () {
      final lines = groupStrokes(line(['hello', 'online'], [0, 81], gap: 8));
      expect(lines.single.words, hasLength(2));
      expect(lines.single.words.first.strokes, hasLength(5));
    });

    test('a very wide word gap is a word gap whatever the letter gaps', () {
      final lines = groupStrokes(writeText('hello online', wordGap: 40));
      expect(lines.single.words, hasLength(2));
    });

    test('the thresholds scale with the writing', () {
      final lines =
          groupStrokes(writeText('notebook 27', gaps: {4: 7.5, 7: 8}, wordGap: 16, scale: 2));
      expect(strokeCounts(lines), [12, 2]);
    });

    test('config: a stricter ratio and no fragment merging split the uneven notebook', () {
      final lines = groupStrokes(
        writeText('notebook', gaps: {4: 7.5, 7: 8}),
        config: const GroupingConfig(wordGapRatio: 1.0, fragmentMergeFactor: 0),
      );
      expect(lines.single.words.length, greaterThan(1));
    });
  });
}
