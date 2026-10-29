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
}
