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

  // v1.11.0: Mariam draws the shaft and the head in one stroke, and "it
  // sometimes picks up". Arrows drawn with a hand's variety (3 to 6
  // x-heights; barbs of 0.5 to 1.2 x-heights at 25-55 degrees, each its own;
  // the head tilted, rounded at the corners, not quite back at the tip; the
  // shaft sloping and bowed): 1.10.0 found 68-78% of them.
  group('arrows drawn with a hand\'s variety', () {
    List<Vec2> round(List<Vec2> p) {
      var pts = p;
      for (var k = 0; k < 2; k++) {
        pts = [
          pts.first,
          for (var i = 0; i + 1 < pts.length; i++) ...[pts[i].lerp(pts[i + 1], 0.25), pts[i].lerp(pts[i + 1], 0.75)],
          pts.last,
        ];
      }
      return pts;
    }

    for (final style in ['one stroke, back over the first barb', 'one stroke, a closed head', 'shaft and head', 'shaft and two barbs']) {
      test(style, () {
        final rnd = math.Random(11);
        double r(double a, double b) => a + rnd.nextDouble() * (b - a);
        const n = 120;
        var found = 0;
        for (var t = 0; t < n; t++) {
          const xh = 10.0;
          final length = r(2, 6) * xh, slope = r(-0.08, 0.08), bow = r(-1.5, 1.5), y0 = r(-6, -3);
          final tip = Vec2(40 + length, y0 + slope * length);
          final dir = Vec2(1, slope) * (1 / math.sqrt(1 + slope * slope));
          final tilt = r(-0.15, 0.15);
          Vec2 barb(double side) {
            final a = math.pi - r(25, 55) * math.pi / 180 * side + tilt;
            final c = math.cos(a), s = math.sin(a);
            return tip + Vec2(dir.x * c - dir.y * s, dir.x * s + dir.y * c) * (r(0.5, 1.2) * xh);
          }

          final one = barb(1), two = barb(-1);
          final back = tip + Vec2(r(-3, 3), r(-3, 3));
          final shaft = [Vec2(40, y0), Vec2(40 + length / 2, y0 + slope * length / 2 + bow), tip];
          final arrow = switch (style) {
            'one stroke, back over the first barb' => [round(densify([...shaft, one, back, two]))],
            'one stroke, a closed head' => [round(densify([...shaft, one, two, back]))],
            'shaft and head' => [round(densify(shaft)), round(densify([one, back, two]))],
            _ => [round(densify(shaft)), densify([back, one]), densify([back, two])],
          };
          final ink = [
            for (final s in arrow) [for (final p in s) Vec2(p.x + r(-0.25, 0.25), p.y + r(-0.25, 0.25))],
          ];
          final lines = groupStrokes(toStrokes([...textAt('hen', 0), ...ink, ...textAt('ne', tip.x + 12)]));
          final a = lines.length == 1 ? findArrows(lines.single) : const <LineArrow>[];
          if (a.length == 1 && a.single.text == '→' && a.single.strokes.length == arrow.length) found++;
        }
        expect(found, greaterThanOrEqualTo(n * 0.95));
      });
    }
  });

  test('a dash before a c or an e, a flick, a tilde, joining strokes into letters are no arrows', () {
    Vec2 v(double x, double y) => Vec2(x, y);
    List<Vec2> arc(double cx, double cy, double r, double from, double to) => [
          for (var k = 0; k <= 24; k++)
            Vec2(cx + r * math.cos(from + (to - from) * k / 24), cy + r * math.sin(from + (to - from) * k / 24)),
        ];
    final cases = <String, List<List<Vec2>>>{};
    for (final len in [16.0, 22.0, 30.0]) {
      final e = 40 + len;
      cases.addAll({
        // 1.10.0 typed "→" for these two.
        'dash, c ($len)': [densify([v(40, -5), v(e, -5)]), densify(arc(e + 6, -5, 4, -0.6, -math.pi * 1.7))],
        'dash, e ($len)': [densify([v(40, -5), v(e, -5)]), densify([v(e + 3, -4), v(e + 9, -6), ...arc(e + 6, -5, 4, -0.3, -math.pi * 1.8)])],
        'dash, a ($len)': [densify([v(40, -5), v(e, -5)]), densify([...arc(e + 6, -5, 4, -0.5, -math.pi * 2.1), v(e + 10, 0)])],
        'into c ($len)': [densify([v(40, -5), v(e, -5), ...arc(e + 4, -5, 4, -0.6, -math.pi * 1.7)])],
        'into o ($len)': [densify([v(40, -9), v(e, -9), ...arc(e + 2, -5, 4, -math.pi / 2, -math.pi / 2 - 2 * math.pi)])],
        'into e ($len)': [densify([v(40, -4), v(e, -4), v(e + 6, -6), ...arc(e + 3, -5, 4, -0.3, -math.pi * 1.8)])],
        'into r ($len)': [densify([v(40, -5), v(e, -5), v(e + 1, -10), v(e + 1, 0), v(e + 1, -7), v(e + 5, -10)])],
        'into n ($len)': [densify([v(40, -5), v(e, -5), v(e + 1, -10), v(e + 1, 0), v(e + 1, -8), v(e + 5, -10), v(e + 7, -6), v(e + 7, 0)])],
        'into s ($len)': [densify([v(40, -5), v(e, -5), v(e + 5, -10), v(e + 1, -8), v(e + 5, -3), v(e, 0)])],
        'into m ($len)': [densify([v(40, -5), v(e, -5), v(e, 0), v(e, -9), v(e + 3, -10), v(e + 4, 0), v(e + 4, -9), v(e + 7, -10), v(e + 8, 0)])],
        'dash, flick up ($len)': [densify([v(40, -5), v(e, -5), v(e - 3, -9)])],
        'dash, flick down and up ($len)': [densify([v(40, -5), v(e, -5), v(e - 2, -2), v(e + 1, -8)])],
        'tilde ($len)': [densify([for (var k = 0; k <= 20; k++) v(40 + len * k / 20, -5 + 2 * math.sin(k / 20 * 2 * math.pi))])],
      });
    }
    final found = <String>[];
    cases.forEach((name, ink) {
      for (final line in groupStrokes(toStrokes([...textAt('hen', 0), ...ink, ...textAt('ne', 90)]))) {
        if (findArrows(line).isNotEmpty) found.add(name);
      }
    });
    expect(found, isEmpty);
  });
}
