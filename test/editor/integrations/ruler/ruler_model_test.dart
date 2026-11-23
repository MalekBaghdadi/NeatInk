import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_model.dart';

import 'ruler_test_utils.dart';

void main() {
  const tablet = Size(1280, 800);

  RulerModel modelWithListener(List<int> calls) {
    final model = RulerModel();
    model.addListener(() => calls.add(1));
    addTearDown(model.dispose);
    return model;
  }

  group('show and hide', () {
    test('starts hidden', () {
      final model = RulerModel();
      addTearDown(model.dispose);
      expect(model.visible, isFalse);
    });

    test('the first time it is centred sideways, 38% down, 92% as long', () {
      final model = RulerModel()..show(tablet);
      addTearDown(model.dispose);
      expect(model.visible, isTrue);
      final g = model.geometry;
      expect(g.center, offsetCloseTo(const Offset(640, 304)));
      expect(g.angle, 0);
      expect(g.length, closeTo(1280 * 0.92, 1e-9));
      expect(g.thickness, 96);
    });

    test('the length is kept between 360 and 1500 px', () {
      // 92% of 380 is 349.6: raised to the minimum.
      final narrow = RulerModel()..show(const Size(380, 800));
      // 92% of 3000 is 2760: lowered to the maximum.
      final wide = RulerModel()..show(const Size(3000, 2000));
      addTearDown(narrow.dispose);
      addTearDown(wide.dispose);
      expect(narrow.geometry.length, 360);
      expect(wide.geometry.length, 1500);
    });

    test('a view narrower than the minimum length limits it', () {
      final model = RulerModel()..show(const Size(300, 700));
      addTearDown(model.dispose);
      expect(model.geometry.length, 300);
    });

    test('hiding keeps the place, showing again restores it', () {
      final model = RulerModel()..show(tablet);
      addTearDown(model.dispose);
      model.translate(const Offset(40, 60));
      model.rotateBy(rad(20));
      final placed = model.geometry;
      model.hide();
      expect(model.visible, isFalse);
      expect(model.geometry, placed);
      model.show(tablet);
      expect(model.visible, isTrue);
      expect(model.geometry, placed);
    });

    test('toggle shows and hides', () {
      final model = RulerModel();
      addTearDown(model.dispose);
      model.toggle(tablet);
      expect(model.visible, isTrue);
      model.toggle(tablet);
      expect(model.visible, isFalse);
    });

    test('showing in a view of another size fits the ruler to it', () {
      final model = RulerModel()..show(tablet);
      addTearDown(model.dispose);
      model.hide();
      model.show(const Size(600, 900));
      expect(model.geometry.length, 600);
      expect(model.geometry.center.dx, lessThanOrEqualTo(600));
    });

    test('notifies once per change, and not when nothing changes', () {
      final calls = <int>[];
      final model = modelWithListener(calls);
      model.show(tablet);
      expect(calls.length, 1);
      model.show(tablet); // already showing
      expect(calls.length, 1);
      model.hide();
      expect(calls.length, 2);
      model.hide(); // already hidden
      expect(calls.length, 2);
    });

    test('showing before the view has a size still gives a usable ruler', () {
      for (final size in [
        Size.zero,
        const Size(double.nan, 100),
        const Size(100, double.infinity),
      ]) {
        final model = RulerModel()..show(size);
        addTearDown(model.dispose);
        expect(model.visible, isTrue);
        final g = model.geometry;
        expect(g.length, greaterThan(0));
        expect(g.center.dx.isFinite && g.center.dy.isFinite, isTrue);
      }
    });
  });

  group('translate', () {
    test('moves the ruler by the given amount', () {
      final model = RulerModel()..show(tablet);
      addTearDown(model.dispose);
      final before = model.geometry.center;
      model.translate(const Offset(25, -10));
      expect(model.geometry.center, offsetCloseTo(before + const Offset(25, -10)));
    });

    test('keeps the centre inside the view', () {
      final model = RulerModel()..show(tablet);
      addTearDown(model.dispose);
      model.translate(const Offset(5000, 5000));
      expect(model.geometry.center, const Offset(1280, 800));
      model.translate(const Offset(-9000, -9000));
      expect(model.geometry.center, Offset.zero);
    });

    test('ignores nothing-moves and numbers that are not numbers', () {
      final calls = <int>[];
      final model = modelWithListener(calls)..show(tablet);
      calls.clear();
      model.translate(Offset.zero);
      model.translate(const Offset(double.nan, 1));
      model.translate(const Offset(1, double.infinity));
      expect(calls, isEmpty);
      expect(model.geometry.center.dx.isFinite, isTrue);
    });

    test('a push against the edge that changes nothing does not notify', () {
      final calls = <int>[];
      final model = modelWithListener(calls)..show(tablet);
      model.translate(const Offset(9000, 0));
      calls.clear();
      model.translate(const Offset(50, 0));
      expect(calls, isEmpty);
    });
  });

  group('rotateBy', () {
    test('turns the ruler about its centre', () {
      final model = RulerModel()..show(tablet);
      addTearDown(model.dispose);
      final centre = model.geometry.center;
      model.rotateBy(rad(40));
      expect(model.geometry.angle, closeTo(rad(40), 1e-12));
      expect(model.geometry.center, centre);
    });

    test('snaps to a multiple of 15 degrees within 2.5 degrees', () {
      for (final entry in {
        14.0: 15.0,
        12.6: 15.0,
        17.4: 15.0,
        15.0: 15.0,
        -14.0: -15.0,
        29.0: 30.0,
        0.8: 0.0,
        -2.0: 0.0,
        90.0: 90.0,
        88.0: 90.0,
      }.entries) {
        final model = RulerModel()..show(tablet);
        addTearDown(model.dispose);
        model.rotateBy(rad(entry.key));
        expect(model.geometry.angle, closeTo(rad(entry.value), 1e-12),
            reason: '${entry.key} degrees');
      }
    });

    test('does not snap further from a multiple than 2.5 degrees', () {
      for (final deg in [10.0, 12.0, 18.0, 20.0, 40.0, -7.0]) {
        final model = RulerModel()..show(tablet);
        addTearDown(model.dispose);
        model.rotateBy(rad(deg));
        expect(model.geometry.angle, closeTo(rad(deg), 1e-12), reason: '$deg');
      }
    });

    test('the snap does not make the ruler stick', () {
      final model = RulerModel()..show(tablet);
      addTearDown(model.dispose);
      final shown = <double>[];
      // Turn by one degree at a time, as slow fingers would.
      for (var i = 0; i < 40; i++) {
        model.rotateBy(rad(1));
        shown.add(model.geometry.angle * 180 / math.pi);
      }
      // It holds at 15 for the whole snap window (12.5..17.5 degrees)...
      expect(shown.sublist(12, 17), everyElement(closeTo(15, 1e-9)));
      // ...then moves on with the fingers, with no lost degrees.
      expect(shown[17], closeTo(18, 1e-9));
      expect(shown[18], closeTo(19, 1e-9));
      // ... and holds at 30 too, then leaves it again.
      expect(shown[29], closeTo(30, 1e-9));
      expect(shown[39], closeTo(40, 1e-9));
    });

    test('turning back through a snap works too', () {
      final model = RulerModel()..show(tablet);
      addTearDown(model.dispose);
      model.rotateBy(rad(20));
      for (var i = 0; i < 6; i++) {
        model.rotateBy(-rad(1));
      }
      // Now at 14 degrees underneath: snapped to 15.
      expect(model.geometry.angle, closeTo(rad(15), 1e-12));
      for (var i = 0; i < 5; i++) {
        model.rotateBy(-rad(1));
      }
      // 9 degrees: free again.
      expect(model.geometry.angle, closeTo(rad(9), 1e-12));
    });

    test('a full turn comes back to where it started', () {
      final model = RulerModel()..show(tablet);
      addTearDown(model.dispose);
      for (var i = 0; i < 36; i++) {
        model.rotateBy(rad(10));
      }
      final a = model.geometry.angle;
      expect(math.cos(a), closeTo(1, 1e-9));
      expect(math.sin(a), closeTo(0, 1e-9));
      expect(a.abs(), lessThanOrEqualTo(math.pi + 1e-9));
    });

    test('ignores zero and numbers that are not numbers', () {
      final calls = <int>[];
      final model = modelWithListener(calls)..show(tablet);
      calls.clear();
      model.rotateBy(0);
      model.rotateBy(double.nan);
      model.rotateBy(double.infinity);
      expect(calls, isEmpty);
      expect(model.geometry.angle, 0);
    });

    test('a turn that snaps back to the same angle does not notify', () {
      final calls = <int>[];
      final model = modelWithListener(calls)..show(tablet);
      model.rotateBy(rad(14)); // snaps to 15
      calls.clear();
      model.rotateBy(rad(1)); // 15 underneath: still shows 15
      expect(calls, isEmpty);
    });
  });

  group('snapAngle', () {
    test('is the identity far from a multiple', () {
      expect(RulerModel.snapAngle(rad(7)), rad(7));
    });

    test('is exact on a multiple', () {
      expect(RulerModel.snapAngle(rad(15.2)), closeTo(rad(15), 1e-12));
      expect(RulerModel.snapAngle(-rad(44)), closeTo(-rad(45), 1e-12));
    });

    test('never returns something that is not a number', () {
      expect(RulerModel.snapAngle(double.nan), 0);
      expect(RulerModel.snapAngle(double.infinity), 0);
    });
  });

  group('fit', () {
    test('shortens a ruler that is longer than the new width', () {
      final model = RulerModel()..show(tablet);
      addTearDown(model.dispose);
      model.fit(const Size(700, 1200));
      expect(model.geometry.length, 700);
    });

    test('does not lengthen a ruler when the view grows', () {
      final model = RulerModel()..show(const Size(700, 1200));
      addTearDown(model.dispose);
      final before = model.geometry.length;
      model.fit(const Size(1400, 900));
      expect(model.geometry.length, before);
    });

    test('brings the centre back into the view', () {
      final model = RulerModel()..show(tablet);
      addTearDown(model.dispose);
      model.translate(const Offset(600, 400));
      model.fit(const Size(800, 500));
      final c = model.geometry.center;
      expect(c.dx, inInclusiveRange(0, 800));
      expect(c.dy, inInclusiveRange(0, 500));
    });

    test('translating respects the new size', () {
      final model = RulerModel()..show(tablet);
      addTearDown(model.dispose);
      model.fit(const Size(500, 400));
      model.translate(const Offset(9999, 9999));
      expect(model.geometry.center, const Offset(500, 400));
    });

    test('notifies only when the ruler changed', () {
      final calls = <int>[];
      final model = modelWithListener(calls)..show(tablet);
      calls.clear();
      model.fit(tablet);
      expect(calls, isEmpty);
      model.fit(const Size(600, 600));
      expect(calls.length, 1);
    });

    test('ignores a size that is empty or not a number', () {
      final model = RulerModel()..show(tablet);
      addTearDown(model.dispose);
      final before = model.geometry;
      model.fit(Size.zero);
      model.fit(const Size(double.nan, 400));
      model.fit(const Size(400, double.infinity));
      expect(model.geometry, before);
    });

    test('before the ruler was ever shown it only remembers the size', () {
      final calls = <int>[];
      final model = modelWithListener(calls);
      model.fit(const Size(900, 700));
      expect(calls, isEmpty);
      expect(model.viewport, const Size(900, 700));
      model.show(const Size(900, 700));
      expect(model.geometry.center, offsetCloseTo(const Offset(450, 266)));
    });
  });
}
