import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/canvas/ink_tool_handler.dart';
import 'package:neatink/ink/vec2.dart';

void main() {
  const w = 100.0, h = 50.0;

  Matcher vecNear(double x, double y) => predicate<Vec2>(
      (v) => (v.x - x).abs() < 1e-9 && (v.y - y).abs() < 1e-9, 'near ($x, $y)');

  test('a segment inside is returned as it is', () {
    final r = clipSegmentToRect(const Vec2(10, 10), const Vec2(90, 40), w, h)!;
    expect(r.$1, vecNear(10, 10));
    expect(r.$2, vecNear(90, 40));
  });

  test('an end outside is cut where the segment leaves the rectangle', () {
    final r = clipSegmentToRect(const Vec2(50, 25), const Vec2(150, 25), w, h)!;
    expect(r.$1, vecNear(50, 25));
    expect(r.$2, vecNear(100, 25));
    final left = clipSegmentToRect(const Vec2(50, 25), const Vec2(-50, 25), w, h)!;
    expect(left.$2, vecNear(0, 25));
  });

  test('a diagonal stays straight: cut, not clamped on each axis', () {
    // 45 degrees from (80, 10): leaves through the right side at (100, 30).
    final r = clipSegmentToRect(const Vec2(80, 10), const Vec2(200, 130), w, h)!;
    expect(r.$1, vecNear(80, 10));
    expect(r.$2, vecNear(100, 30));
    // A steep one leaves through the bottom side first.
    final steep = clipSegmentToRect(const Vec2(80, 10), const Vec2(90, 200), w, h)!;
    expect(steep.$2.y, closeTo(50, 1e-9));
    expect((steep.$2.x - 80) / (steep.$2.y - 10), closeTo(10 / 190, 1e-9));
  });

  test('both ends outside but the segment crosses the rectangle', () {
    final r = clipSegmentToRect(const Vec2(-50, 25), const Vec2(250, 25), w, h)!;
    expect(r.$1, vecNear(0, 25));
    expect(r.$2, vecNear(100, 25));
    final diagonal =
        clipSegmentToRect(const Vec2(-10, -10), const Vec2(110, 110), 100, 100)!;
    expect(diagonal.$1, vecNear(0, 0));
    expect(diagonal.$2, vecNear(100, 100));
  });

  test('the direction is kept when the ends are swapped', () {
    final r = clipSegmentToRect(const Vec2(250, 25), const Vec2(-50, 25), w, h)!;
    expect(r.$1, vecNear(100, 25));
    expect(r.$2, vecNear(0, 25));
  });

  test('a segment entirely outside gives nothing', () {
    expect(clipSegmentToRect(const Vec2(110, 0), const Vec2(200, 50), w, h), isNull);
    expect(clipSegmentToRect(const Vec2(-5, -5), const Vec2(-1, 100), w, h), isNull);
    expect(clipSegmentToRect(const Vec2(0, -1), const Vec2(100, -1), w, h), isNull);
    // Misses the corner.
    expect(clipSegmentToRect(const Vec2(90, -20), const Vec2(130, 20), w, h), isNull);
  });

  test('a segment along a side counts as inside', () {
    final top = clipSegmentToRect(const Vec2(-20, 0), const Vec2(120, 0), w, h)!;
    expect(top.$1, vecNear(0, 0));
    expect(top.$2, vecNear(100, 0));
    final right = clipSegmentToRect(const Vec2(100, -5), const Vec2(100, 80), w, h)!;
    expect(right.$1, vecNear(100, 0));
    expect(right.$2, vecNear(100, 50));
  });

  test('a point is returned when inside and nothing when outside', () {
    final r = clipSegmentToRect(const Vec2(5, 5), const Vec2(5, 5), w, h)!;
    expect(r.$1, vecNear(5, 5));
    expect(r.$2, vecNear(5, 5));
    expect(clipSegmentToRect(const Vec2(500, 5), const Vec2(500, 5), w, h), isNull);
  });

  test('grazing a corner gives a point', () {
    final r = clipSegmentToRect(const Vec2(110, 10), const Vec2(90, -10), w, h)!;
    expect(r.$1, vecNear(100, 0));
    expect(r.$2, vecNear(100, 0));
  });

  test('numbers that are not numbers, or a rectangle that is, give nothing', () {
    expect(clipSegmentToRect(const Vec2(double.nan, 1), const Vec2(5, 5), w, h), isNull);
    expect(clipSegmentToRect(const Vec2(1, 1), const Vec2(5, double.infinity), w, h),
        isNull);
    expect(clipSegmentToRect(const Vec2(1, 1), const Vec2(5, 5), double.nan, h), isNull);
    expect(clipSegmentToRect(const Vec2(1, 1), const Vec2(5, 5), -1, h), isNull);
  });

  test('a rectangle of no size keeps only what is on it', () {
    final r = clipSegmentToRect(const Vec2(-5, 0), const Vec2(5, 0), 0, 0)!;
    expect(r.$1, vecNear(0, 0));
    expect(clipSegmentToRect(const Vec2(-5, 1), const Vec2(5, 1), 0, 0), isNull);
  });

  test('huge coordinates still clip exactly', () {
    final r = clipSegmentToRect(const Vec2(-1e9, 25), const Vec2(1e9, 25), w, h)!;
    expect(r.$1, vecNear(0, 25));
    expect(r.$2, vecNear(100, 25));
  });

  test('the ends never fall outside the rectangle, whatever the rounding', () {
    final rnd = math.Random(5);
    for (var i = 0; i < 2000; i++) {
      final a = Vec2(rnd.nextDouble() * 400 - 150, rnd.nextDouble() * 300 - 125);
      final b = Vec2(rnd.nextDouble() * 400 - 150, rnd.nextDouble() * 300 - 125);
      final r = clipSegmentToRect(a, b, w, h);
      if (r == null) continue;
      for (final v in [r.$1, r.$2]) {
        expect(v.x, inInclusiveRange(0, w));
        expect(v.y, inInclusiveRange(0, h));
      }
      // The cut piece lies on the original line.
      final cross = (b - a).cross(r.$2 - r.$1);
      expect(cross.abs(), lessThan(1e-6 * (1 + (b - a).length * (r.$2 - r.$1).length)));
    }
  });
}
