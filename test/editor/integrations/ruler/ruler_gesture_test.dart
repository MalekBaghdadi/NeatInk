import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_gesture.dart';

import 'ruler_test_utils.dart';

void main() {
  group('one finger', () {
    test('drags: each step is how far the finger moved since the last', () {
      final g = RulerGesture();
      expect(g.add(1, const Offset(100, 100)), isTrue);
      var step = g.move(1, const Offset(110, 95))!;
      expect(step.translation, offsetCloseTo(const Offset(10, -5)));
      expect(step.rotation, 0);
      step = g.move(1, const Offset(110, 95))!;
      expect(step.translation, Offset.zero);
      step = g.move(1, const Offset(90, 120))!;
      expect(step.translation, offsetCloseTo(const Offset(-20, 25)));
    });

    test('the steps add up to the whole drag', () {
      final g = RulerGesture()..add(1, const Offset(50, 60));
      var sum = Offset.zero;
      for (var i = 1; i <= 40; i++) {
        sum += g.move(1, Offset(50 + i * 3.0, 60 - i * 1.5))!.translation;
      }
      expect(sum, offsetCloseTo(const Offset(120, -60), 1e-9));
    });

    test('never turns the ruler', () {
      final g = RulerGesture()..add(1, Offset.zero);
      for (var i = 0; i < 30; i++) {
        final step = g.move(1, Offset(math.cos(i) * 80, math.sin(i) * 80))!;
        expect(step.rotation, 0);
      }
    });

    test('a pointer that is not followed gives no step', () {
      final g = RulerGesture()..add(1, Offset.zero);
      expect(g.move(2, const Offset(5, 5)), isNull);
      expect(RulerGesture().move(1, const Offset(5, 5)), isNull);
    });
  });

  group('two fingers', () {
    test('moving together moves by the midpoint\'s motion and does not turn', () {
      final g = RulerGesture()
        ..add(1, const Offset(100, 100))
        ..add(2, const Offset(300, 100));
      final first = g.move(1, const Offset(110, 120))!;
      // The midpoint moved by half of this finger's move so far...
      expect(first.translation, offsetCloseTo(const Offset(5, 10)));
      final second = g.move(2, const Offset(310, 120))!;
      // ...and by the rest with the other finger.
      expect(second.translation, offsetCloseTo(const Offset(5, 10)));
      // One finger alone seemed to turn the line; the other turns it back.
      expect(first.rotation + second.rotation, closeTo(0, 1e-12));
    });

    test('turning the fingers clockwise gives positive rotation', () {
      final g = RulerGesture()
        ..add(1, const Offset(0, 0))
        ..add(2, const Offset(100, 0));
      // The second finger goes to the right of ... below: clockwise on screen.
      final step = g.move(2, const Offset(100, 100))!;
      expect(step.rotation, closeTo(math.pi / 4, 1e-12));
      expect(step.translation, offsetCloseTo(const Offset(0, 50)));
    });

    test('turning counter-clockwise gives negative rotation', () {
      final g = RulerGesture()
        ..add(1, const Offset(0, 0))
        ..add(2, const Offset(100, 0));
      final step = g.move(2, const Offset(100, -100))!;
      expect(step.rotation, closeTo(-math.pi / 4, 1e-12));
    });

    test('rotation steps add up across the +-pi seam', () {
      final g = RulerGesture()
        ..add(1, const Offset(200, 200))
        ..add(2, const Offset(300, 200));
      // Swing the second finger through half a turn in small steps, both ways.
      var total = 0.0;
      for (var i = 1; i <= 90; i++) {
        final a = i * math.pi / 90;
        total += g.move(2, Offset(200 + 100 * math.cos(a), 200 + 100 * math.sin(a)))!
            .rotation;
      }
      expect(total, closeTo(math.pi, 1e-9));
      for (var i = 89; i >= -90; i--) {
        final a = i * math.pi / 90;
        total += g.move(2, Offset(200 + 100 * math.cos(a), 200 + 100 * math.sin(a)))!
            .rotation;
      }
      // Back through the seam, and on to -pi: net change -pi from the start.
      expect(total, closeTo(-math.pi, 1e-9));
    });

    test('a step is never more than half a turn', () {
      final g = RulerGesture()
        ..add(1, const Offset(0, 0))
        ..add(2, const Offset(100, 0));
      final step = g.move(2, const Offset(-100, 1))!;
      expect(step.rotation.abs(), lessThanOrEqualTo(math.pi));
    });

    test('the first finger turning the ruler counts too', () {
      final g = RulerGesture()
        ..add(1, const Offset(0, 0))
        ..add(2, const Offset(100, 0));
      // Finger 1 moves down: the vector 1 -> 2 now points up-right,
      // counter-clockwise.
      final step = g.move(1, const Offset(0, 100))!;
      expect(step.rotation, closeTo(-math.pi / 4, 1e-12));
    });

    test('fingers closer than the minimum span do not turn the ruler', () {
      final g = RulerGesture()
        ..add(1, const Offset(100, 100))
        ..add(2, const Offset(110, 100));
      final step = g.move(2, const Offset(100, 110))!;
      expect(step.rotation, 0);
      expect(step.translation, offsetCloseTo(const Offset(-5, 5)));
    });

    test('moving apart again takes a fresh reference instead of jumping', () {
      final g = RulerGesture()
        ..add(1, const Offset(100, 100))
        ..add(2, const Offset(110, 100));
      // Still too close: no direction yet.
      expect(g.move(2, const Offset(100, 110))!.rotation, 0);
      // Now far enough: the direction is taken, nothing turns.
      expect(g.move(2, const Offset(100, 200))!.rotation, 0);
      // Turning from here counts.
      final step = g.move(2, const Offset(0, 100))!;
      expect(step.rotation, closeTo(math.pi / 2, 1e-12));
    });
  });

  group('fingers joining and leaving', () {
    test('a second finger joining does not move or turn the ruler', () {
      final g = RulerGesture()..add(1, const Offset(100, 100));
      g.move(1, const Offset(120, 100));
      expect(g.add(2, const Offset(500, 400)), isTrue);
      // The next move is relative to the joined state, not to the old one.
      final step = g.move(2, const Offset(500, 400))!;
      expect(step.translation, Offset.zero);
      expect(step.rotation, 0);
    });

    test('a finger leaving does not move the ruler: the other carries on', () {
      final g = RulerGesture()
        ..add(1, const Offset(100, 100))
        ..add(2, const Offset(300, 300));
      g.remove(1);
      expect(g.pointerCount, 1);
      final step = g.move(2, const Offset(310, 305))!;
      expect(step.translation, offsetCloseTo(const Offset(10, 5)));
      expect(step.rotation, 0);
    });

    test('the finger that arrived second can stay and the first leave', () {
      final g = RulerGesture()
        ..add(1, const Offset(0, 0))
        ..add(2, const Offset(100, 0))
        ..remove(1)
        ..add(3, const Offset(100, 100));
      // 2 is now first, 3 second: the vector points straight down...
      final step = g.move(3, const Offset(0, 100))!;
      // ...and swings to point down-left, a quarter of a turn clockwise.
      expect(step.rotation, closeTo(math.pi / 4, 1e-12));
    });

    test('a third finger is not taken', () {
      final g = RulerGesture()
        ..add(1, Offset.zero)
        ..add(2, const Offset(100, 0));
      expect(g.add(3, const Offset(50, 50)), isFalse);
      expect(g.contains(3), isFalse);
      expect(g.move(3, const Offset(60, 60)), isNull);
      expect(g.pointerCount, 2);
    });

    test('the same finger is not added twice', () {
      final g = RulerGesture()..add(1, Offset.zero);
      expect(g.add(1, const Offset(100, 0)), isFalse);
      expect(g.pointerCount, 1);
    });

    test('removing every finger ends the gesture', () {
      final g = RulerGesture()
        ..add(1, Offset.zero)
        ..add(2, const Offset(100, 0));
      expect(g.isActive, isTrue);
      g.remove(1);
      g.remove(2);
      expect(g.isActive, isFalse);
      // A later finger starts a fresh gesture, with no jump.
      g.add(5, const Offset(700, 700));
      expect(g.move(5, const Offset(701, 700))!.translation,
          offsetCloseTo(const Offset(1, 0)));
    });

    test('removing a finger that is not followed changes nothing', () {
      final g = RulerGesture()..add(1, Offset.zero);
      g.remove(9);
      expect(g.pointerCount, 1);
      expect(g.contains(1), isTrue);
    });

    test('clear forgets everything', () {
      final g = RulerGesture()
        ..add(1, Offset.zero)
        ..add(2, const Offset(100, 0))
        ..clear();
      expect(g.isActive, isFalse);
      expect(g.move(1, const Offset(5, 5)), isNull);
      expect(g.add(7, Offset.zero), isTrue);
    });
  });

  group('bad input', () {
    test('a position that is not a number is ignored', () {
      final g = RulerGesture();
      expect(g.add(1, const Offset(double.nan, 0)), isFalse);
      expect(g.isActive, isFalse);
      g.add(1, const Offset(10, 10));
      expect(g.move(1, const Offset(double.infinity, 0)), isNull);
      // The finger is still where it was; the next good move is relative to it.
      expect(g.move(1, const Offset(12, 10))!.translation,
          offsetCloseTo(const Offset(2, 0)));
    });

    test('huge coordinates stay finite', () {
      final g = RulerGesture()
        ..add(1, const Offset(1e9, 1e9))
        ..add(2, const Offset(-1e9, 1e9 + 5));
      final step = g.move(2, const Offset(-1e9, -1e9))!;
      expect(step.translation.dx.isFinite, isTrue);
      expect(step.translation.dy.isFinite, isTrue);
      expect(step.rotation.isFinite, isTrue);
    });
  });
}
