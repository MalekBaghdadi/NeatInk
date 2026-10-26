import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/features/editor/tools/spatial_index.dart';
import 'package:neatink/features/editor/tools/stroke_eraser.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';

import 'tool_test_utils.dart';

void main() {
  group('strokeTouchedBySweep', () {
    final horizontal = strokeOf('h', linePoints(40, 50, 60, 50), size: 2);

    test('a fast diagonal flick erases a stroke between two samples', () {
      // One pointer event jumps from (0, 0) to (100, 100): neither sample is
      // anywhere near the stroke, but the swept path crosses it at (50, 50).
      const from = Vec2(0, 0), to = Vec2(100, 100);
      expect(horizontal.points.first.pos.distanceTo(from), greaterThan(60));
      expect(strokeTouchedBySweep(horizontal, from, to, 3), isTrue);
      // Testing only the end points would have missed it.
      expect(strokeTouchedBySweep(horizontal, to, to, 3), isFalse);
      expect(strokeTouchedBySweep(horizontal, from, from, 3), isFalse);
    });

    test('a sweep crossing between two samples of the stroke still hits', () {
      // A stroke with only two points far apart: the eraser crosses the
      // segment's middle, nowhere near a sample point.
      final sparse = strokeOf('s', [const Vec2(0, 50), const Vec2(200, 50)]);
      expect(
          strokeTouchedBySweep(
              sparse, const Vec2(100, 0), const Vec2(100, 100), 1),
          isTrue);
    });

    test('reach is the eraser radius plus half the stroke width', () {
      // Sweep parallel to the stroke, 5 pt below its centre line.
      const radius = 3.0; // 3 + 2/2 = 4 pt reach
      expect(
          strokeTouchedBySweep(
              horizontal, const Vec2(30, 55), const Vec2(70, 55), radius),
          isFalse);
      expect(
          strokeTouchedBySweep(
              horizontal, const Vec2(30, 53.9), const Vec2(70, 53.9), radius),
          isTrue);
      // Beyond the end of the stroke: distance to the end point counts.
      expect(
          strokeTouchedBySweep(
              horizontal, const Vec2(64.5, 40), const Vec2(64.5, 60), radius),
          isFalse);
      expect(
          strokeTouchedBySweep(
              horizontal, const Vec2(63.5, 40), const Vec2(63.5, 60), radius),
          isTrue);
    });

    test('single-point strokes (dots)', () {
      final dot = strokeOf('dot', [const Vec2(10, 10)], size: 4);
      // Reach 2 + 2 = 4.
      expect(strokeTouchedBySweep(dot, const Vec2(13.9, 10), const Vec2(13.9, 10), 2),
          isTrue);
      expect(strokeTouchedBySweep(dot, const Vec2(14.1, 10), const Vec2(14.1, 10), 2),
          isFalse);
      // Swept past the dot.
      expect(
          strokeTouchedBySweep(dot, const Vec2(0, 13), const Vec2(30, 13), 2),
          isTrue);
      expect(
          strokeTouchedBySweep(dot, const Vec2(0, 15), const Vec2(30, 15), 2),
          isFalse);
    });

    test('wide highlighters are hit on their painted band', () {
      final hl = strokeOf('hl', linePoints(0, 100, 100, 100),
          tool: StrokeTool.highlighter, size: 16);
      // 9 pt from the centre line: inside 8 (half width) + 2 (radius).
      expect(
          strokeTouchedBySweep(hl, const Vec2(50, 109), const Vec2(60, 109), 2),
          isTrue);
      expect(
          strokeTouchedBySweep(hl, const Vec2(50, 110.5), const Vec2(60, 110.5), 2),
          isFalse);
    });

    test('empty strokes are never hit', () {
      final empty = strokeOf('e', const []);
      expect(strokeTouchedBySweep(empty, Vec2.zero, Vec2.zero, 100), isFalse);
    });
  });

  group('eraseHits and StrokeEraseSession', () {
    test('index-backed hits equal brute force on random pages', () {
      final rnd = math.Random(11);
      final strokes = <Stroke>[];
      for (var i = 0; i < 1500; i++) {
        final start = Vec2(rnd.nextDouble() * 595, rnd.nextDouble() * 842);
        final pts = [
          for (var k = 0; k < 1 + rnd.nextInt(12); k++)
            start + Vec2(k * 2.0, math.sin(k + i) * 3),
        ];
        strokes.add(strokeOf('s$i', pts, size: 1 + rnd.nextDouble() * 4));
      }
      final page = PageContent(strokes: strokes);
      final index = SpatialIndex.forPage(page);
      for (var k = 0; k < 300; k++) {
        final from = Vec2(rnd.nextDouble() * 595, rnd.nextDouble() * 842);
        final to = from + Vec2(rnd.nextDouble() * 80 - 40, rnd.nextDouble() * 80 - 40);
        final radius = 1 + rnd.nextDouble() * 15;
        expect(eraseHits(index, from, to, radius),
            strokesHitBySweep(page.strokes, from, to, radius));
      }
    });

    test('a session collects one drag and reports each stroke once', () {
      final page = PageContent(strokes: [
        strokeOf('a', linePoints(10, 10, 10, 100)),
        strokeOf('b', linePoints(30, 10, 30, 100)),
        strokeOf('c', linePoints(50, 10, 50, 100)),
      ]);
      final session = StrokeEraseSession(SpatialIndex.forPage(page));
      expect(session.isEmpty, isTrue);
      expect(session.sweep(const Vec2(0, 50), const Vec2(20, 50), 2), {'a'});
      // Going back over 'a' reports only the new stroke.
      expect(session.sweep(const Vec2(20, 50), const Vec2(0, 60), 2), isEmpty);
      expect(session.sweep(const Vec2(0, 60), const Vec2(35, 60), 2), {'b'});
      expect(session.erasedIds, {'a', 'b'});
      expect(session.isEmpty, isFalse);
      expect(() => session.erasedIds.add('x'), throwsUnsupportedError);
    });
  });
}
