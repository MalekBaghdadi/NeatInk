import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_geometry.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_model.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_touch_interceptor.dart';

import 'ruler_test_utils.dart';

void main() {
  // A ruler centred at (500, 304), 920 long, 96 wide, flat: the body is
  // x 40..960, y 256..352; its edges are at y = 256 and y = 352.
  const view = Size(1000, 800);

  late RulerModel model;
  late RulerTouchInterceptor interceptor;

  setUp(() {
    model = RulerModel()..show(view);
    interceptor = RulerTouchInterceptor(model);
    addTearDown(model.dispose);
  });

  bool down(int pointer, Offset at, {bool fingerDraws = false}) =>
      interceptor.onPointerDown(fingerDown(pointer, at), fingerDraws: fingerDraws);

  test('the ruler is where the tests assume', () {
    expect(model.geometry.center, const Offset(500, 304));
    expect(model.geometry.length, closeTo(920, 1e-9));
    expect(model.geometry.thickness, 96);
  });

  group('which fingers are claimed', () {
    test('a finger on the ruler body', () {
      expect(down(1, const Offset(500, 304)), isTrue);
    });

    test('a finger just beside the body, within the slop', () {
      expect(down(1, const Offset(500, 256 - RulerTouchInterceptor.bodySlop + 1)),
          isTrue);
    });

    test('not a finger beyond the slop', () {
      expect(down(1, const Offset(500, 256 - RulerTouchInterceptor.bodySlop - 1)),
          isFalse);
      expect(down(1, const Offset(40 - RulerTouchInterceptor.bodySlop - 1, 304)),
          isFalse);
      expect(down(1, const Offset(500, 600)), isFalse);
    });

    test('not any finger while the ruler is hidden', () {
      model.hide();
      expect(down(1, const Offset(500, 304)), isFalse);
    });

    test('a finger at an edge, when fingers do not draw', () {
      expect(down(1, const Offset(300, 262)), isTrue);
    });

    test('with finger drawing on, the band along each edge draws instead', () {
      // Inside the body, 6 px from the top edge; and outside it, 10 px away.
      expect(down(1, const Offset(300, 262), fingerDraws: true), isFalse);
      expect(down(2, const Offset(300, 246), fingerDraws: true), isFalse);
      // Along the bottom edge.
      expect(down(3, const Offset(300, 346), fingerDraws: true), isFalse);
      expect(down(4, const Offset(300, 360), fingerDraws: true), isFalse);
    });

    test('with finger drawing on, the middle of the body still moves it', () {
      expect(down(1, const Offset(300, 304), fingerDraws: true), isTrue);
    });

    test('the band is exactly the snap distance wide', () {
      const edge = 256.0;
      expect(down(1, Offset(300, edge + rulerSnapDistance + 1), fingerDraws: true),
          isTrue);
      interceptor.onPointerUp(fingerUp(1, Offset.zero));
      expect(down(2, Offset(300, edge + rulerSnapDistance - 1), fingerDraws: true),
          isFalse);
    });

    test('a finger beside the end of the ruler still moves it', () {
      expect(down(1, const Offset(960 + 10, 304), fingerDraws: true), isTrue);
    });
  });

  group('moving the ruler', () {
    test('one finger drags it by the distance the finger moves', () {
      final start = model.geometry.center;
      down(1, const Offset(500, 304));
      interceptor.onPointerMove(fingerMove(1, const Offset(520, 310)));
      expect(model.geometry.center, offsetCloseTo(start + const Offset(20, 6)));
      interceptor.onPointerMove(fingerMove(1, const Offset(480, 290)));
      expect(model.geometry.center, offsetCloseTo(start + const Offset(-20, -14)));
      expect(model.geometry.angle, 0);
    });

    test('a drag that stays on the ruler body keeps grip', () {
      final start = model.geometry.center;
      down(1, const Offset(100, 304));
      // Dragging far away, the finger leaves the body but still moves it.
      for (var i = 1; i <= 10; i++) {
        interceptor.onPointerMove(fingerMove(1, Offset(100 + i * 20.0, 304 + i * 30.0)));
      }
      expect(model.geometry.center, offsetCloseTo(start + const Offset(200, 300)));
    });

    test('lifting ends the drag', () {
      down(1, const Offset(500, 304));
      interceptor.onPointerUp(fingerUp(1, const Offset(500, 304)));
      final center = model.geometry.center;
      interceptor.onPointerMove(fingerMove(1, const Offset(600, 400)));
      expect(model.geometry.center, center);
      // And a finger off the ruler is not claimed any more.
      expect(down(2, const Offset(500, 700)), isFalse);
    });

    test('a cancelled touch ends the drag too', () {
      down(1, const Offset(500, 304));
      interceptor.onPointerCancel(fingerCancel(1, const Offset(500, 304)));
      expect(down(2, const Offset(500, 700)), isFalse);
    });

    test('moves of fingers that were not claimed do nothing', () {
      final before = model.geometry;
      interceptor.onPointerMove(fingerMove(7, const Offset(900, 900)));
      expect(model.geometry, before);
    });

    test('the ruler cannot be dragged out of the view', () {
      down(1, const Offset(500, 304));
      interceptor.onPointerMove(fingerMove(1, const Offset(5000, 5000)));
      final c = model.geometry.center;
      expect(c.dx, lessThanOrEqualTo(view.width));
      expect(c.dy, lessThanOrEqualTo(view.height));
    });
  });

  group('two fingers', () {
    test('a second finger anywhere joins the first', () {
      expect(down(1, const Offset(300, 304)), isTrue);
      expect(down(2, const Offset(900, 700)), isTrue);
    });

    test('the second finger joins even in the bands that fingers draw in',
        () {
      expect(down(1, const Offset(300, 304), fingerDraws: true), isTrue);
      expect(down(2, const Offset(300, 262), fingerDraws: true), isTrue);
    });

    test('a third finger is not claimed', () {
      down(1, const Offset(300, 304));
      down(2, const Offset(400, 304));
      expect(down(3, const Offset(350, 304)), isFalse);
    });

    test('turning two fingers turns the ruler about its centre', () {
      final centre = model.geometry.center;
      down(1, const Offset(300, 304));
      down(2, const Offset(700, 304));
      // The right finger swings down by 40 degrees about the left one.
      final end = Offset(300 + 400 * math.cos(rad(40)), 304 + 400 * math.sin(rad(40)));
      for (var i = 1; i <= 20; i++) {
        final a = rad(40) * i / 20;
        interceptor.onPointerMove(fingerMove(
            2, Offset(300 + 400 * math.cos(a), 304 + 400 * math.sin(a))));
      }
      expect(model.geometry.angle, closeTo(rad(40), 1e-9));
      // The midpoint moved from (500, 304) to halfway to the end finger.
      final mid = (const Offset(300, 304) + end) / 2;
      expect(model.geometry.center,
          offsetCloseTo(centre + (mid - const Offset(500, 304)), 1e-6));
    });

    test('moving both fingers together drags without turning', () {
      final centre = model.geometry.center;
      down(1, const Offset(300, 304));
      down(2, const Offset(700, 304));
      for (var i = 1; i <= 10; i++) {
        interceptor.onPointerMove(fingerMove(1, Offset(300 + i * 5.0, 304 + i * 2.0)));
        interceptor.onPointerMove(fingerMove(2, Offset(700 + i * 5.0, 304 + i * 2.0)));
      }
      expect(model.geometry.angle, closeTo(0, 1e-9));
      expect(model.geometry.center, offsetCloseTo(centre + const Offset(50, 20), 1e-6));
    });

    test('a turn near a multiple of 15 degrees snaps', () {
      down(1, const Offset(300, 304));
      down(2, const Offset(700, 304));
      final a = rad(14);
      interceptor.onPointerMove(fingerMove(
          2, Offset(300 + 400 * math.cos(a), 304 + 400 * math.sin(a))));
      expect(model.geometry.angle, closeTo(rad(15), 1e-12));
    });

    test('lifting one finger leaves the other dragging, without a jump', () {
      down(1, const Offset(300, 304));
      down(2, const Offset(700, 304));
      interceptor.onPointerUp(fingerUp(1, const Offset(300, 304)));
      final centre = model.geometry.center;
      interceptor.onPointerMove(fingerMove(2, const Offset(710, 314)));
      expect(model.geometry.center, offsetCloseTo(centre + const Offset(10, 10)));
      expect(model.geometry.angle, 0);
    });

    test('with one finger left, a new finger joins anywhere', () {
      down(1, const Offset(300, 304));
      down(2, const Offset(700, 304));
      interceptor.onPointerUp(fingerUp(1, const Offset(300, 304)));
      expect(down(3, const Offset(100, 700)), isTrue);
    });

    test('after both lift, a finger off the ruler is not claimed', () {
      down(1, const Offset(300, 304));
      down(2, const Offset(700, 304));
      interceptor.onPointerUp(fingerUp(1, const Offset(300, 304)));
      interceptor.onPointerCancel(fingerCancel(2, const Offset(700, 304)));
      expect(down(3, const Offset(100, 700)), isFalse);
    });
  });

  group('hiding', () {
    test('a ruler hidden during a drag lets the finger go on harmlessly', () {
      down(1, const Offset(500, 304));
      model.hide();
      interceptor.onPointerMove(fingerMove(1, const Offset(520, 304)));
      interceptor.onPointerUp(fingerUp(1, const Offset(520, 304)));
      expect(down(2, const Offset(500, 304)), isFalse);
    });
  });
}
