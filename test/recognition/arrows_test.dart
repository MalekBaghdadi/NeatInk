import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:neatink/recognition/arrows.dart';
import 'package:neatink/recognition/stroke_grouping.dart';

import '../beautify/synthetic_font.dart';

// The synthetic font: x-height 10, baseline at y = 0 (moved to y = 300 by
// toStrokes' default distortion... here no distortion: identity).
List<List<Vec2>> textAt(String text, double x) => [
      for (final p in wordPolylines(text)) [for (final v in p) Vec2(v.x + x, v.y)],
    ];

RecognizedLine lineOf(List<List<Vec2>> polylines, {List<Stroke> extra = const []}) {
  final lines = groupStrokes([...toStrokes(polylines), ...extra]);
  expect(lines, hasLength(1));
  return lines.single;
}

/// "hen", an arrow from x 40 to 80 at half the x-height, "ne".
List<List<Vec2>> withArrow(List<List<Vec2>> arrow) => [...textAt('hen', 0), ...arrow, ...textAt('ne', 90)];

void main() {
  test('a shaft with a head drawn as a stroke of its own points right', () {
    final line = lineOf(withArrow([
      densify(const [Vec2(40, -5), Vec2(80, -5)]),
      densify(const [Vec2(74, -10), Vec2(80, -5), Vec2(74, 0)]),
    ]));
    final arrows = findArrows(line);
    expect(arrows, hasLength(1));
    expect(arrows.single.text, '→');
    expect(arrows.single.strokes, hasLength(2));
    expect(arrows.single.centerX, closeTo(60, 1));
  });

  test('an arrow in one stroke, and one pointing left', () {
    final right = findArrows(lineOf(withArrow([
      densify(const [Vec2(40, -5), Vec2(80, -5), Vec2(74, -10), Vec2(80, -5), Vec2(74, 0)]),
    ])));
    expect(right.single.text, '→');
    final left = findArrows(lineOf(withArrow([
      densify(const [Vec2(80, -5), Vec2(40, -5)]),
      densify(const [Vec2(46, -10), Vec2(40, -5), Vec2(46, 0)]),
    ])));
    expect(left.single.text, '←');
  });

  test('a dash, an underline or a short stroke is no arrow', () {
    expect(findArrows(lineOf(withArrow([densify(const [Vec2(40, -5), Vec2(80, -5)])]))), isEmpty, reason: 'no head');
    expect(findArrows(lineOf(withArrow([densify(const [Vec2(40, -5), Vec2(52, -5)])]))), isEmpty, reason: 'too short');
    expect(findArrows(lineOf([...textAt('hen', 0)])), isEmpty);
  });

  test('a stroke the pen snapped to an arrow is read in its line', () {
    final snapped = Stroke(
      id: 'arrow',
      tool: StrokeTool.pen,
      color: 0xFF1E1E1E,
      size: 2.2,
      shape: ShapeKind.arrow,
      raw: [for (final v in densify(const [Vec2(40, -5), Vec2(80, -5), Vec2(74, -10), Vec2(80, -5), Vec2(74, 0)])) InkPoint(v.x, v.y, 0.5, 0)],
    );
    final line = lineOf([...textAt('hen', 0), ...textAt('ne', 90)], extra: [snapped]);
    expect(line.inkStrokes, contains(snapped), reason: 'grouped with the text');
    expect(findArrows(line).single.strokes, [snapped]);
  });

  // v1.10.0: 2 of Mariam's 8 arrows were found. The ways people draw an
  // arrow, with a hand's wobble, of 2 to 7 x-heights, the next word close.
  group('hand-drawn arrows', () {
    List<Vec2> hand(List<Vec2> pts) {
      final d = densify(pts);
      return [for (var i = 0; i < d.length; i++) Vec2(d[i].x, d[i].y + 0.4 * math.sin(i * 0.37))];
    }

    Map<String, List<List<Vec2>>> variants(double end) {
      const y = -5.0;
      final length = end - 40;
      Vec2 v(double x, double yy) => Vec2(x, yy);
      return {
        'small head of its own': [hand([v(40, y), v(end, y)]), hand([v(end - 6, y - 5), v(end, y), v(end - 6, y + 5)])],
        'big head': [hand([v(40, y), v(end, y)]), hand([v(end - 9, y - 8), v(end, y), v(end - 9, y + 8)])],
        'huge head': [hand([v(40, y), v(end, y)]), hand([v(end - 11, y - 11), v(end, y), v(end - 11, y + 11)])],
        'head tip past the shaft': [hand([v(40, y), v(end - 6, y)]), hand([v(end - 10, y - 6), v(end, y), v(end - 10, y + 6)])],
        'shaft past the head tip': [hand([v(40, y), v(end + 5, y)]), hand([v(end - 6, y - 6), v(end, y), v(end - 6, y + 6)])],
        'one stroke': [hand([v(40, y), v(end, y), v(end - 7, y - 6), v(end, y), v(end - 7, y + 6)])],
        'one stroke, lower barb first': [hand([v(40, y), v(end, y), v(end - 7, y + 6), v(end, y), v(end - 7, y - 6)])],
        'one stroke, round tip': [
          hand([v(40, y), v(end - 1, y), v(end, y - 1), v(end - 7, y - 6), v(end - 6, y - 5), v(end, y + 0.5), v(end - 7, y + 6)])
        ],
        'two barbs from the tip': [hand([v(40, y), v(end, y)]), hand([v(end, y), v(end - 7, y - 6)]), hand([v(end, y), v(end - 7, y + 6)])],
        'two barbs into the tip': [hand([v(40, y), v(end, y)]), hand([v(end - 7, y - 6), v(end, y)]), hand([v(end - 7, y + 6), v(end, y)])],
        'upper barb in the stroke, lower apart': [hand([v(40, y), v(end, y), v(end - 7, y - 6)]), hand([v(end, y), v(end - 7, y + 6)])],
        'steep barbs': [hand([v(40, y), v(end, y)]), hand([v(end - 4, y - 7), v(end, y), v(end - 4, y + 7)])],
        'flat barbs': [hand([v(40, y), v(end, y)]), hand([v(end - 10, y - 4.5), v(end, y), v(end - 10, y + 4.5)])],
        'head drawn first': [hand([v(end - 7, y - 6), v(end, y), v(end - 7, y + 6)]), hand([v(40, y), v(end, y)])],
        'tilted': [
          hand([v(40, y + 0.06 * length), v(end, y - 0.06 * length)]),
          hand([v(end - 7, y - 0.06 * length - 6), v(end, y - 0.06 * length), v(end - 7, y - 0.06 * length + 6)])
        ],
        'sagging shaft': [hand([v(40, y), v(40 + length / 2, y + 2), v(end, y)]), hand([v(end - 7, y - 6), v(end, y), v(end - 7, y + 6)])],
        'lopsided head': [hand([v(40, y), v(end, y)]), hand([v(end - 9, y - 9), v(end, y), v(end - 5, y + 4)])],
        'on the baseline': [hand([v(40, -1), v(end, -1)]), hand([v(end - 7, -7), v(end, -1), v(end - 7, 5)])],
        'tail flick': [hand([v(38, y - 3), v(41, y), v(end, y)]), hand([v(end - 7, y - 6), v(end, y), v(end - 7, y + 6)])],
      };
    }

    for (final length in [20.0, 30.0, 70.0]) {
      for (final gap in [5.0, 12.0]) {
        test('$length long, the next word $gap after it', () {
          final missed = <String>[];
          variants(40 + length).forEach((name, arrow) {
            final lines = groupStrokes(toStrokes([...textAt('hen', 0), ...arrow, ...textAt('ne', 40 + length + gap)]));
            final found = lines.length == 1 ? findArrows(lines.single) : const <LineArrow>[];
            if (found.length != 1 || found.single.text != '→' || found.single.strokes.length != arrow.length) {
              missed.add(name);
            }
          });
          expect(missed, isEmpty);
        });
      }
    }
  });

  test('t-bars, letters, signs and dashes are no arrows', () {
    Vec2 v(double x, double y) => Vec2(x, y);
    List<Vec2> d(List<Vec2> p) => densify(p);
    final cases = <String, List<List<Vec2>>>{
      // Mariam's "the": a long t-bar with the stem crossing near its end.
      for (final bar in [16.0, 20.0, 26.0])
        for (final stemAt in [2.0, 4.0, 6.0])
          for (final lean in [-3.0, 0.0, 3.0]) ...{
            't-bar $bar, stem $stemAt from the right end, lean $lean': [
              d([v(40, -10), v(40 + bar, -10)]),
              d([v(40 + bar - stemAt + lean, -18), v(40 + bar - stemAt - lean, 0)]),
            ],
            't-bar $bar, stem $stemAt from the left end, lean $lean': [
              d([v(40, -10), v(40 + bar, -10)]),
              d([v(40 + stemAt + lean, -18), v(40 + stemAt - lean, 0)]),
            ],
          },
      'E': [d([v(40, -16), v(40, 0)]), d([v(40, -16), v(56, -16)]), d([v(40, -8), v(54, -8)]), d([v(40, 0), v(56, 0)])],
      'F': [d([v(56, -16), v(40, -16), v(40, 0)]), d([v(40, -8), v(54, -8)])],
      'z': [d([v(40, -10), v(58, -10), v(40, 0), v(58, 0)])],
      'dash, x': [d([v(40, -5), v(60, -5)]), d([v(63, -10), v(70, 0)]), d([v(70, -10), v(63, 0)])],
      'dash, v': [d([v(40, -5), v(60, -5)]), d([v(63, -10), v(66.5, 0), v(70, -10)])],
      'dash, l': [d([v(40, -5), v(60, -5)]), d([v(63, -18), v(63, 0)])],
      'dash, k': [d([v(40, -5), v(60, -5)]), d([v(63, -18), v(63, 0)]), d([v(70, -10), v(63, -4), v(70, 0)])],
      'dash, <': [d([v(40, -5), v(60, -5)]), d([v(70, -10), v(63, -5), v(70, 0)])],
      'dash, *': [d([v(40, -5), v(58, -5)]), d([v(64, -10), v(64, 0)]), d([v(60, -8), v(68, -2)]), d([v(68, -8), v(60, -2)])],
      'a joining stroke into v': [d([v(40, -5), v(58, -5), v(61, -10), v(64, 0), v(67, -10)])],
      'a joining stroke into a small v': [d([v(40, -5), v(58, -5), v(60, -9), v(62, -1), v(64, -9)])],
      '+': [d([v(40, -5), v(58, -5)]), d([v(49, -14), v(49, 4)])],
      '=': [d([v(40, -8), v(58, -8)]), d([v(40, -2), v(58, -2)])],
      '≠': [d([v(40, -8), v(58, -8)]), d([v(40, -2), v(58, -2)]), d([v(52, -14), v(46, 4)])],
      '#': [d([v(40, -8), v(58, -8)]), d([v(40, -2), v(58, -2)]), d([v(45, -14), v(43, 4)]), d([v(53, -14), v(51, 4)])],
      'underline': [d([v(0, 3), v(70, 3)])],
      'long dash': [d([v(40, -5), v(70, -5)])],
    };
    final found = <String>[];
    cases.forEach((name, ink) {
      for (final line in groupStrokes(toStrokes([...textAt('hen', 0), ...ink, ...textAt('ne', 80)]))) {
        if (findArrows(line).isNotEmpty) found.add(name);
      }
    });
    expect(found, isEmpty);
  });

  test('an arrow the recogniser read as characters is typed as one', () {
    expect(typedArrows('brain->cord'), 'brain → cord');
    expect(typedArrows('->'), '→');
    expect(typedArrows('-->'), '→');
    expect(typedArrows('=>'), '→');
    expect(typedArrows('<-'), '←');
    expect(typedArrows('<->'), '↔');
    expect(typedArrows('x <= y'), 'x <= y', reason: 'less or equal');
    expect(typedArrows('well-known'), 'well-known');
    expect(typedArrows('a > b'), 'a > b');
  });
}
