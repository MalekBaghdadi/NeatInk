import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

/// Matches an [Offset] within [epsilon] of [expected] on both axes.
Matcher offsetCloseTo(Offset expected, [double epsilon = 1e-6]) =>
    _OffsetCloseTo(expected, epsilon);

class _OffsetCloseTo extends Matcher {
  const _OffsetCloseTo(this.expected, this.epsilon);

  final Offset expected;
  final double epsilon;

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) =>
      item is Offset &&
      (item.dx - expected.dx).abs() <= epsilon &&
      (item.dy - expected.dy).abs() <= epsilon;

  @override
  Description describe(Description description) =>
      description.add('an Offset within $epsilon of $expected');

  @override
  Description describeMismatch(Object? item, Description mismatchDescription,
          Map<Object?, Object?> matchState, bool verbose) =>
      mismatchDescription.add('was $item');
}

/// Degrees to radians.
double rad(double degrees) => degrees * math.pi / 180;

/// Fingers' pointer events at a position, as the document view delivers them
/// (no transform: local equals global).
PointerDownEvent fingerDown(int pointer, Offset at) =>
    PointerDownEvent(pointer: pointer, position: at);
PointerMoveEvent fingerMove(int pointer, Offset at) =>
    PointerMoveEvent(pointer: pointer, position: at);
PointerUpEvent fingerUp(int pointer, Offset at) =>
    PointerUpEvent(pointer: pointer, position: at);
PointerCancelEvent fingerCancel(int pointer, Offset at) =>
    PointerCancelEvent(pointer: pointer, position: at);
