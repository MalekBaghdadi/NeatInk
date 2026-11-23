import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_geometry.dart';

import 'ruler_test_utils.dart';

void main() {
  // A horizontal ruler: top edge y = 352, bottom edge y = 448, x = 100..900.
  const flat = RulerGeometry(center: Offset(500, 400), length: 800);

  group('axes and corners', () {
    test('a horizontal ruler points right and its normal points down', () {
      expect(flat.axis, offsetCloseTo(const Offset(1, 0)));
      expect(flat.normal, offsetCloseTo(const Offset(0, 1)));
    });

    test('a positive angle turns clockwise on screen', () {
      final g = flat.copyWith(angle: math.pi / 2);
      expect(g.axis, offsetCloseTo(const Offset(0, 1)));
      // The top edge, above the centre when flat, is now on the right.
      expect(g.edgePoint(RulerEdge.top, 0), offsetCloseTo(const Offset(548, 400)));
      expect(g.edgePoint(RulerEdge.bottom, 0), offsetCloseTo(const Offset(452, 400)));
    });

    test('the corners run clockwise from the top edge\'s left end', () {
      expect(flat.corners, [
        const Offset(100, 352),
        const Offset(900, 352),
        const Offset(900, 448),
        const Offset(100, 448),
      ]);
    });

    test('axis and normal stay perpendicular unit vectors at any angle', () {
      for (var deg = -360.0; deg <= 360; deg += 17) {
        final g = flat.copyWith(angle: rad(deg));
        expect(g.axis.distance, closeTo(1, 1e-12));
        expect(g.normal.distance, closeTo(1, 1e-12));
        expect(g.axis.dx * g.normal.dx + g.axis.dy * g.normal.dy, closeTo(0, 1e-12));
      }
    });
  });

  group('containsPoint', () {
    test('the body is inside, outside is not', () {
      expect(flat.containsPoint(const Offset(500, 400)), isTrue);
      expect(flat.containsPoint(const Offset(101, 353)), isTrue);
      expect(flat.containsPoint(const Offset(99, 400)), isFalse);
      expect(flat.containsPoint(const Offset(500, 351)), isFalse);
      expect(flat.containsPoint(const Offset(500, 449)), isFalse);
    });

    test('the slop grows the body on every side', () {
      expect(flat.containsPoint(const Offset(90, 400), 14), isTrue);
      expect(flat.containsPoint(const Offset(85, 400), 14), isFalse);
      expect(flat.containsPoint(const Offset(500, 340), 14), isTrue);
      expect(flat.containsPoint(const Offset(500, 330), 14), isFalse);
      expect(flat.containsPoint(const Offset(500, 460), 14), isTrue);
    });

    test('it follows the rotation', () {
      final upright = flat.copyWith(angle: math.pi / 2);
      expect(upright.containsPoint(const Offset(520, 700)), isTrue);
      expect(upright.containsPoint(const Offset(520, 810)), isFalse);
      expect(upright.containsPoint(const Offset(700, 400)), isFalse);
      // The same point is on the flat ruler, but not on the upright one.
      expect(flat.containsPoint(const Offset(800, 400)), isTrue);
      expect(upright.containsPoint(const Offset(800, 400)), isFalse);
    });

    test('a position that is not a number is nowhere', () {
      expect(flat.containsPoint(const Offset(double.nan, 400), 14), isFalse);
      expect(flat.containsPoint(const Offset(500, double.nan), 14), isFalse);
    });
  });

  group('nearestEdge', () {
    test('finds the edge within reach, outside or inside the body', () {
      expect(flat.nearestEdge(const Offset(300, 340), 24), RulerEdge.top);
      expect(flat.nearestEdge(const Offset(300, 372), 24), RulerEdge.top);
      expect(flat.nearestEdge(const Offset(300, 352), 24), RulerEdge.top);
      expect(flat.nearestEdge(const Offset(300, 460), 24), RulerEdge.bottom);
      expect(flat.nearestEdge(const Offset(300, 430), 24), RulerEdge.bottom);
    });

    test('the middle of the body and far-away points are not near an edge', () {
      expect(flat.nearestEdge(const Offset(300, 400), 24), isNull);
      expect(flat.nearestEdge(const Offset(300, 320), 24), isNull);
      expect(flat.nearestEdge(const Offset(300, 480), 24), isNull);
    });

    test('the reach is exactly maxDistance', () {
      expect(flat.nearestEdge(const Offset(300, 328), 24), RulerEdge.top);
      expect(flat.nearestEdge(const Offset(300, 327.9), 24), isNull);
      expect(flat.nearestEdge(const Offset(300, 340), 5), isNull);
    });

    test('the point must lie along the ruler, give or take a small margin', () {
      const margin = RulerGeometry.edgeEndMargin;
      expect(flat.nearestEdge(Offset(100 - margin + 1, 345), 24), RulerEdge.top);
      expect(flat.nearestEdge(Offset(900 + margin - 1, 345), 24), RulerEdge.top);
      expect(flat.nearestEdge(Offset(100 - margin - 1, 345), 24), isNull);
      expect(flat.nearestEdge(Offset(900 + margin + 1, 345), 24), isNull);
      expect(flat.nearestEdge(const Offset(2000, 345), 24), isNull);
    });

    test('works on a turned ruler', () {
      final g = flat.copyWith(angle: rad(90));
      // Top edge is now the vertical line x = 548, bottom x = 452.
      expect(g.nearestEdge(const Offset(560, 500), 24), RulerEdge.top);
      expect(g.nearestEdge(const Offset(440, 500), 24), RulerEdge.bottom);
      expect(g.nearestEdge(const Offset(500, 500), 24), isNull);
      expect(g.nearestEdge(const Offset(560, 5000), 24), isNull);
    });

    test('on a ruler thinner than the reach, the nearer edge wins', () {
      const thin = RulerGeometry(
          center: Offset(500, 400), length: 800, thickness: 10);
      expect(thin.nearestEdge(const Offset(300, 397), 24), RulerEdge.top);
      expect(thin.nearestEdge(const Offset(300, 403), 24), RulerEdge.bottom);
      // Dead centre is a tie: the top edge.
      expect(thin.nearestEdge(const Offset(300, 400), 24), RulerEdge.top);
    });

    test('a position that is not a number is near nothing', () {
      expect(flat.nearestEdge(const Offset(double.nan, 345), 24), isNull);
      expect(flat.nearestEdge(const Offset(300, double.nan), 24), isNull);
    });
  });

  group('project', () {
    test('lands on the edge line, straight up or down from the point', () {
      expect(flat.project(const Offset(300, 330), RulerEdge.top),
          offsetCloseTo(const Offset(300, 352)));
      expect(flat.project(const Offset(300, 400), RulerEdge.top),
          offsetCloseTo(const Offset(300, 352)));
      expect(flat.project(const Offset(300, 500), RulerEdge.bottom),
          offsetCloseTo(const Offset(300, 448)));
    });

    test('is clamped to the ruler\'s length', () {
      expect(flat.project(const Offset(50, 360), RulerEdge.top),
          offsetCloseTo(const Offset(100, 352)));
      expect(flat.project(const Offset(5000, 360), RulerEdge.top),
          offsetCloseTo(const Offset(900, 352)));
      expect(flat.project(const Offset(950, 500), RulerEdge.bottom),
          offsetCloseTo(const Offset(900, 448)));
    });

    test('works on a turned ruler', () {
      final g = flat.copyWith(angle: rad(90));
      expect(g.project(const Offset(560, 700), RulerEdge.top),
          offsetCloseTo(const Offset(548, 700)));
      expect(g.project(const Offset(560, 900), RulerEdge.top),
          offsetCloseTo(const Offset(548, 800)));
      expect(g.project(const Offset(420, 100), RulerEdge.bottom),
          offsetCloseTo(const Offset(452, 100)));
    });

    test('is the closest point of the edge at any angle', () {
      final rnd = math.Random(7);
      for (var i = 0; i < 200; i++) {
        final g = RulerGeometry(
          center: Offset(rnd.nextDouble() * 1000, rnd.nextDouble() * 800),
          angle: rnd.nextDouble() * 2 * math.pi - math.pi,
          length: 200 + rnd.nextDouble() * 1000,
          thickness: 40 + rnd.nextDouble() * 100,
        );
        final p = Offset(rnd.nextDouble() * 1400 - 200, rnd.nextDouble() * 1200 - 200);
        for (final edge in RulerEdge.values) {
          final q = g.project(p, edge);
          final a = g.edgePoint(edge, -g.length / 2);
          final b = g.edgePoint(edge, g.length / 2);
          // q is on the segment a-b ...
          expect((q - a).distance + (q - b).distance,
              closeTo(g.length, 1e-6), reason: '$g $p $edge');
          // ... and no sampled point of the segment is closer to p.
          for (var k = 0; k <= 20; k++) {
            final other = Offset.lerp(a, b, k / 20)!;
            expect((p - q).distance, lessThanOrEqualTo((p - other).distance + 1e-9));
          }
        }
      }
    });

    test('a position that is not a number lands in the middle of the edge', () {
      expect(flat.project(const Offset(double.nan, 5), RulerEdge.top),
          offsetCloseTo(const Offset(500, 352)));
      expect(flat.project(const Offset(300, double.nan), RulerEdge.bottom),
          offsetCloseTo(const Offset(500, 448)));
    });

    test('an infinite position lands on the end it points at', () {
      expect(flat.project(const Offset(double.infinity, 5), RulerEdge.top),
          offsetCloseTo(const Offset(900, 352)));
      expect(flat.project(const Offset(double.negativeInfinity, 5), RulerEdge.top),
          offsetCloseTo(const Offset(100, 352)));
    });

    test('a ruler of no length projects every position to one point', () {
      const dot = RulerGeometry(center: Offset(10, 10), length: 0);
      expect(dot.project(const Offset(300, 300), RulerEdge.top),
          offsetCloseTo(const Offset(10, -38)));
    });
  });

  group('displayAngleDegrees', () {
    test('an unturned ruler shows 0, never -0', () {
      final text = flat.displayAngleDegrees.toString();
      expect(text, '0.0');
    });

    test('counts counter-clockwise, as in maths', () {
      expect(flat.copyWith(angle: -rad(30)).displayAngleDegrees, 30);
      expect(flat.copyWith(angle: rad(30)).displayAngleDegrees, 150);
      expect(flat.copyWith(angle: rad(90)).displayAngleDegrees, 90);
      expect(flat.copyWith(angle: -rad(90)).displayAngleDegrees, 90);
    });

    test('is the same every half turn', () {
      expect(flat.copyWith(angle: math.pi).displayAngleDegrees, 0);
      expect(flat.copyWith(angle: -math.pi).displayAngleDegrees, 0);
      expect(flat.copyWith(angle: rad(210)).displayAngleDegrees, 150);
      expect(flat.copyWith(angle: -rad(750)).displayAngleDegrees, 30);
    });

    test('has one decimal and never reaches 180', () {
      expect(flat.copyWith(angle: -rad(12.34)).displayAngleDegrees, 12.3);
      expect(flat.copyWith(angle: -rad(12.36)).displayAngleDegrees, 12.4);
      // 179.96 rounds up to 180, which is 0 again.
      expect(flat.copyWith(angle: rad(0.04)).displayAngleDegrees, 0);
      expect(flat.copyWith(angle: -rad(0.04)).displayAngleDegrees, 0);
      expect(flat.copyWith(angle: rad(0.2)).displayAngleDegrees, 179.8);
    });

    test('is always in [0, 180)', () {
      for (var deg = -1000.0; deg <= 1000; deg += 0.37) {
        final shown = flat.copyWith(angle: rad(deg)).displayAngleDegrees;
        expect(shown, inInclusiveRange(0, 179.9), reason: '$deg');
      }
    });
  });

  test('value equality', () {
    expect(flat, const RulerGeometry(center: Offset(500, 400), length: 800));
    expect(flat.hashCode,
        const RulerGeometry(center: Offset(500, 400), length: 800).hashCode);
    expect(flat == flat.copyWith(angle: 0.1), isFalse);
    expect(flat == flat.copyWith(thickness: 50), isFalse);
  });
}
