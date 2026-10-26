import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/tools/hold_detector.dart';
import 'package:neatink/features/editor/tools/tool_config.dart';

void main() {
  /// Draws a horizontal line of [length] pt at 0.25 pt/ms (8 ms samples)
  /// and returns the time of its last sample.
  int drawLine(HoldDetector d, double length, {int t0 = 0}) {
    var t = t0;
    for (var x = 0.0; x <= length; x += 2) {
      expect(d.addPoint(x, 0, t), isFalse, reason: 'fired while moving');
      t += 8;
    }
    return t - 8;
  }

  group('HoldDetector', () {
    test('fires once after ~500 ms still at the end of a long stroke', () {
      final d = HoldDetector();
      final tEnd = drawLine(d, 40);
      // The pen jitters by ±0.8 pt around the end of the line.
      int? firedAt;
      var fireCount = 0;
      for (var k = 1; k <= 100; k++) {
        final t = tEnd + k * 8;
        if (d.addPoint(40 + (k.isEven ? 0.8 : -0.8), 0.5, t)) {
          fireCount++;
          firedAt ??= t;
        }
      }
      expect(fireCount, 1);
      expect(d.fired, isTrue);
      // The pen came within 3 pt of its resting place ~12 ms before the
      // last line sample (it moves 0.25 pt/ms), so the 500 ms hold
      // completes just under 500 ms after that sample.
      expect(firedAt! - tEnd, inInclusiveRange(480, 500));
      // Never again for this stroke.
      expect(d.check(tEnd + 5000), isFalse);
    });

    test('check() detects a perfectly still pen that sends no events', () {
      final d = HoldDetector();
      final tEnd = drawLine(d, 40);
      expect(d.check(tEnd + 300), isFalse);
      expect(d.check(tEnd + 480), isFalse);
      expect(d.check(tEnd + 500), isTrue);
      expect(d.check(tEnd + 600), isFalse, reason: 'fires only once');
    });

    test('does not fire for strokes of 15 pt or less', () {
      final d = HoldDetector();
      final tEnd = drawLine(d, 14);
      expect(d.pathLength, lessThanOrEqualTo(15));
      expect(d.check(tEnd + 2000), isFalse);
      expect(d.fired, isFalse);
    });

    test('slow drift beyond the radius is not a hold', () {
      final d = HoldDetector();
      final tEnd = drawLine(d, 40);
      // Creep 0.1 pt every 8 ms: 6 pt over 480 ms.
      var x = 40.0;
      for (var t = tEnd + 8; t <= tEnd + 1200; t += 8) {
        x += 0.1;
        expect(d.addPoint(x, 0, t), isFalse, reason: 'fired at t=$t');
      }
    });

    test('moving again restarts the hold timer', () {
      final d = HoldDetector();
      var t = drawLine(d, 40);
      expect(d.check(t + 400), isFalse);
      // Moves on after 400 ms (pen events resume)...
      for (var k = 1; k <= 10; k++) {
        t += 8;
        d.addPoint(40 + k * 2.0, 0, t);
      }
      // ...so the 400 ms already spent no longer counts.
      expect(d.check(t + 300), isFalse);
      expect(d.check(t + 500), isTrue);
    });

    test('the position at the window start is interpolated', () {
      final d = HoldDetector();
      // One long, slow segment ending at x = 40: at 500 ms before the end
      // the pen was still 10 pt away, so this is not a hold yet.
      d.addPoint(0, 0, 0);
      d.addPoint(30, 0, 100);
      d.addPoint(40, 0, 1100);
      expect(d.check(1100), isFalse);
      // 500 ms after the pen arrived, it is.
      expect(d.check(1600), isTrue);
    });

    test('the stroke must cover the whole window', () {
      final d = HoldDetector();
      d.addPoint(0, 0, 0);
      d.addPoint(20, 0, 10);
      // Only 10 ms of ink so far; 400 ms later the window is not covered.
      expect(d.check(410), isFalse);
      expect(d.check(510), isTrue);
    });

    test('reset forgets the stroke', () {
      final d = HoldDetector();
      final tEnd = drawLine(d, 40);
      expect(d.check(tEnd + 500), isTrue);
      d.reset();
      expect(d.fired, isFalse);
      expect(d.pointCount, 0);
      expect(d.pathLength, 0);
      final t2 = drawLine(d, 40, t0: 10000);
      expect(d.check(t2 + 500), isTrue);
    });

    test('honours a custom configuration', () {
      final d = HoldDetector(
          config: const ToolConfig(
              holdDurationMs: 200, holdRadiusPt: 1, holdMinPathLengthPt: 5));
      final tEnd = drawLine(d, 40);
      // At 195 ms the window starts while the pen was still 1.25 pt away.
      expect(d.check(tEnd + 195), isFalse);
      expect(d.check(tEnd + 200), isTrue);
    });

    test('ignores non-finite samples and out-of-order times', () {
      final d = HoldDetector();
      final tEnd = drawLine(d, 40);
      expect(d.addPoint(double.nan, 0, tEnd + 8), isFalse);
      expect(d.pointCount, 21);
      // A late sample with an older timestamp counts as simultaneous.
      d.addPoint(40, 0, tEnd - 100);
      expect(d.check(tEnd + 500), isTrue);
    });
  });
}
