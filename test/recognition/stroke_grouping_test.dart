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
    {String prefix = 'l', double rotateDeg = 0, double x = 100, double y = 300, double scale = 1}) {
  final polylines = <List<Vec2>>[];
  for (var i = 0; i < words.length; i++) {
    for (final p in wordPolylines(words[i])) {
      polylines.add([for (final v in p) Vec2(v.x + offsets[i], v.y)]);
    }
  }
  return toStrokes(polylines,
      prefix: prefix, m: distortion(rotateDeg: rotateDeg, x: x, y: y, scale: scale));
}

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
    final c = line(['hen', 'one'], [0, 40], prefix: 'c', y: 180);
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
}
