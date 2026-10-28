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

  group('line splitting', () {
    // Polylines of [text] in the shared font with the baseline at [y], the
    // first letter at [x].
    List<List<Vec2>> textAt(String text, double x, double y, {double gap = 4}) => [
          for (final p in wordPolylines(text, gap: gap)) [for (final v in p) Vec2(v.x + x, v.y + y)],
        ];

    // A vertical stroke from y0 to y1: the long tail of a y or q, or an l.
    List<Vec2> vline(double x, double y0, double y1) => densify([Vec2(x, y0), Vec2(x, y1)]);

    List<Stroke> strokesOf(List<List<Vec2>> polylines, String prefix) =>
        toStrokes(polylines, prefix: prefix, m: distortion(x: 0, y: 0));

    List<String> idsOf(RecognizedLine l) => [for (final s in l.inkStrokes) s.id];

    test('two lines whose descenders and ascenders interleave are not merged', () {
      // The page the old splitter failed on: the deepest valley of the whole
      // ink profile lies in the long tail of the LAST line, where only one
      // stroke crosses; the real valley between the lines holds two strokes
      // at every height (two tails above, two ascenders below) and was never
      // tried. Peak-first splitting cuts between the line bodies.
      final a = [
        ...textAt('hello', 100, 100),
        ...textAt('online', 160, 100),
        vline(150, 90, 124), // tail of a y
        vline(214, 90, 124), // tail of a q
      ];
      final b = [
        ...textAt('hello', 100, 128),
        ...textAt('hen', 150, 128),
        vline(190, 118, 160), // the long tail of a g, the last ink of the page
      ];
      final lines = groupStrokes([...strokesOf(a, 'a'), ...strokesOf(b, 'b')]);
      expect(lines, hasLength(2));
      expect(idsOf(lines[0]).every((id) => id.startsWith('a')), isTrue);
      expect(idsOf(lines[1]).every((id) => id.startsWith('b')), isTrue);
      expect(lines[0].inkStrokes.length, a.length);
      expect(lines[1].inkStrokes.length, b.length);
      expect(lines[0].baselineY, lessThan(lines[1].baselineY));
    });

    test('the same page without the descender tail of the last line', () {
      final a = [
        ...textAt('hello', 100, 100),
        ...textAt('online', 160, 100),
        vline(150, 90, 124),
        vline(214, 90, 124),
      ];
      final b = [...textAt('hello', 100, 128), ...textAt('hen', 150, 128)];
      final lines = groupStrokes([...strokesOf(a, 'a'), ...strokesOf(b, 'b')]);
      expect(strokeCounts(lines).length, greaterThan(0));
      expect(lines, hasLength(2));
    });

    test('a long descender does not make a line of its own', () {
      final polylines = [
        ...textAt('hello', 100, 100),
        ...textAt('online', 160, 100),
        vline(150, 90, 140), // 5 x-heights of tail
        vline(214, 90, 135),
      ];
      final lines = groupStrokes(strokesOf(polylines, 's'));
      expect(lines, hasLength(1));
      expect(lines.single.inkStrokes, hasLength(polylines.length));
    });

    test('a row of i-dots above the letters is part of the line', () {
      final polylines = [
        ...textAt('online', 100, 100),
        ...textAt('line', 160, 100),
        ...textAt('online', 100, 140),
      ];
      final lines = groupStrokes(strokesOf(polylines, 's'));
      expect(lines, hasLength(2));
    });

    test('dots hovering between two lines follow the stem under them', () {
      // Line B's i-dots are written high: closer to line A's baseline than
      // to B's own letters. They still belong to B.
      List<List<Vec2>> lineWithHighDots(double y, double dotLift) => [
            ...textAt('hello', 100, y),
            // i stems with their dots 'dotLift' above the stem top
            for (final x in [160.0, 172.0, 184.0]) ...[
              vline(x, y - 10, y),
              densify([Vec2(x - 0.3, y - 10 - dotLift), Vec2(x + 0.3, y - 10 - dotLift)]),
            ],
          ];
      for (final lift in [4.0, 7.0, 9.0]) {
        final a = lineWithHighDots(100, 4);
        final b = lineWithHighDots(125, lift);
        final lines = groupStrokes([...strokesOf(a, 'a'), ...strokesOf(b, 'b')]);
        expect(lines, hasLength(2), reason: 'lift $lift');
        expect(idsOf(lines[0]).every((id) => id.startsWith('a')), isTrue, reason: 'lift $lift');
        expect(idsOf(lines[1]).every((id) => id.startsWith('b')), isTrue, reason: 'lift $lift');
        expect(lines[1].inkStrokes.length, b.length);
      }
    });

    test('a full stop at the end of a line stays with its line', () {
      final a = [...textAt('hello', 100, 100), ...textAt('online', 160, 100)];
      final stop = densify([const Vec2(222, 99.6), const Vec2(222.4, 100)]);
      final b = textAt('hello', 100, 126);
      final lines = groupStrokes([...strokesOf([...a, stop], 'a'), ...strokesOf(b, 'b')]);
      expect(lines, hasLength(2));
      expect(lines[0].inkStrokes.length, a.length + 1);
      expect(lines[1].inkStrokes.length, b.length);
    });

    test('three lines, whatever their x positions, keep all their strokes', () {
      final a = [...textAt('hello', 100, 100), ...textAt('online', 170, 100)];
      final b = [...textAt('hen', 140, 140), ...textAt('hello', 190, 140)];
      final c = [...textAt('online', 100, 180), ...textAt('hello', 175, 180)];
      final all = [...strokesOf(a, 'a'), ...strokesOf(b, 'b'), ...strokesOf(c, 'c')];
      final lines = groupStrokes(all.reversed.toList());
      expect(lines, hasLength(3));
      expect([for (final l in lines) l.inkStrokes.length], [a.length, b.length, c.length]);
      for (var i = 0; i < 3; i++) {
        final prefix = 'abc'[i];
        expect(idsOf(lines[i]).every((id) => id.startsWith(prefix)), isTrue);
      }
    });

    test('a sparse line next to a dense one is still a line', () {
      final dense = [
        ...textAt('hello', 100, 100),
        ...textAt('online', 160, 100),
        ...textAt('hello', 230, 100),
        ...textAt('online', 290, 100),
      ];
      final sparse = textAt('hen', 100, 140);
      final lines = groupStrokes([...strokesOf(dense, 'a'), ...strokesOf(sparse, 'b')]);
      expect(lines, hasLength(2));
      expect(lines[1].inkStrokes.length, sparse.length);
    });

    test('inkStrokes keeps every stroke in input order', () {
      final a = [...textAt('hello', 100, 100), ...textAt('online', 160, 100)];
      final b = [...textAt('hen', 100, 140)];
      final sa = strokesOf(a, 'a'), sb = strokesOf(b, 'b');
      // interleaved input: a0 b0 a1 b1 ...
      final input = <Stroke>[];
      for (var i = 0; i < sa.length || i < sb.length; i++) {
        if (i < sa.length) input.add(sa[i]);
        if (i < sb.length) input.add(sb[i]);
      }
      final lines = groupStrokes(input);
      expect(lines, hasLength(2));
      for (final l in lines) {
        final positions = [for (final s in l.inkStrokes) input.indexOf(s)];
        expect(positions, orderedEquals([...positions]..sort()));
      }
      expect(lines[0].inkStrokes.length + lines[1].inkStrokes.length, input.length);
      // the legacy word groups cover the same strokes
      for (final l in lines) {
        expect({for (final w in l.words) ...w.strokes}, {...l.inkStrokes});
        expect(l.strokes, same(l.inkStrokes));
      }
    });

    test('copyWith keeps the ink and the geometry', () {
      final lines = groupStrokes(line(['hello', 'online'], [0, 52]));
      final l = lines.single;
      final one = l.copyWith(words: [l.words.first]);
      expect(one.words, hasLength(1));
      expect(one.inkStrokes, same(l.inkStrokes));
      expect(one.baselineY, l.baselineY);
      expect(one.baselineSlope, l.baselineSlope);
      expect(one.left, l.left);
      expect(one.right, l.right);
      expect(one.xHeight, l.xHeight);
      expect(l.copyWith().words, same(l.words));
    });

    test('a RecognizedLine built without inkStrokes takes the words strokes', () {
      final l = groupStrokes(line(['hello', 'online'], [0, 52])).single;
      final built = RecognizedLine(
        words: l.words,
        baselineY: l.baselineY,
        baselineSlope: l.baselineSlope,
        left: l.left,
        right: l.right,
        xHeight: l.xHeight,
      );
      expect(built.inkStrokes.length, 12);
      expect(built.strokes.length, 12);
    });
  });

  group('per-line x-height', () {
    test('each line has its own x-height, not the page-wide one', () {
      final small = line(['hello', 'online'], [0, 52], prefix: 'a', y: 100, scale: 0.7);
      final medium = line(['hello', 'online'], [0, 52], prefix: 'b', y: 200);
      final big = line(['hello', 'online'], [0, 52], prefix: 'c', y: 330, scale: 2);
      final lines = groupStrokes([...small, ...medium, ...big]);
      expect(lines, hasLength(3));
      expect(lines[0].xHeight, closeTo(7, 1.8));
      expect(lines[1].xHeight, closeTo(10, 2.5));
      expect(lines[2].xHeight, closeTo(20, 4.5));
      expect(lines[2].xHeight, greaterThan(2 * lines[0].xHeight));
      // and the word groups carry it
      expect(lines[2].words.first.xHeight, lines[2].xHeight);
    });

    test('a line of a few strokes still gets an x-height from its own letters', () {
      final lines = groupStrokes([
        ...line(['hello', 'online'], [0, 52], prefix: 'a', y: 100),
        ...line(['hen'], [0], prefix: 'b', y: 230, scale: 2.5),
      ]);
      expect(lines, hasLength(2));
      expect(lines[1].xHeight, closeTo(25, 7));
    });

    test('an expected x-height hint still wins', () {
      final lines = groupStrokes(line(['hello', 'online'], [0, 52]), expectedXHeight: 12);
      expect(lines.single.xHeight, 12);
    });
  });

  group('nearestSupport', () {
    const u = 10.0;
    LevelBox box(double l, double t, double r, double b) => (left: l, top: t, right: r, bottom: b);

    test('an i-dot picks the stem under it', () {
      final dot = box(100, 80, 101, 81);
      final stems = [box(60, 85, 68, 95), box(100, 85, 101, 95)];
      expect(nearestSupport(dot, stems, u: u), 1);
    });

    test('a full stop picks the letter before it, not the line below', () {
      final stop = box(120, 94, 121, 95);
      final before = box(108, 85, 118, 95); // overlaps the stop in height
      final below = box(120, 108, 130, 118); // next line, within reach
      expect(nearestSupport(stop, [below, before], u: u), 1);
    });

    test('nothing within reach gives null', () {
      final dot = box(0, 0, 1, 1);
      expect(nearestSupport(dot, [box(50, 5, 60, 15)], u: u), isNull); // too far sideways
      expect(nearestSupport(dot, [box(0, 40, 10, 50)], u: u), isNull); // too far down
      expect(nearestSupport(dot, const [], u: u), isNull);
    });

    test('strokes above count several times their gap and underOnly ignores them', () {
      final mark = box(0, 50, 1, 51);
      final above = box(0, 30, 10, 45);
      final under = box(0, 60, 10, 70);
      expect(nearestSupport(mark, [above], u: u), 0);
      expect(nearestSupport(mark, [above], u: u, underOnly: true), isNull);
      expect(nearestSupport(mark, [above, under], u: u), 1);
    });

    test('a stroke directly under the mark beats a tail passing beside it', () {
      // The i-dot at x 100, the stem under it, and the descender tail of the
      // line above running down past the dot, one point to its left.
      final dot = box(100, 80, 101, 81);
      final stem = box(100, 86, 101, 96);
      final tail = box(95, 40, 99, 85);
      expect(nearestSupport(dot, [tail, stem], u: u), 1);
      expect(nearestSupport(dot, [stem, tail], u: u), 0);
      // Without a stem under it the tail is the nearest stroke.
      expect(nearestSupport(dot, [tail], u: u), 0);
    });

    test('a stroke far under the mark is not "directly under"', () {
      // The next line's letter 1.5 x-heights below a full stop does not
      // take it from the letter before it.
      final stop = box(120, 94, 121, 95);
      final before = box(108, 85, 118, 95);
      final next = box(120, 110, 130, 120);
      expect(nearestSupport(stop, [next, before], u: u), 1);
    });
  });
}
