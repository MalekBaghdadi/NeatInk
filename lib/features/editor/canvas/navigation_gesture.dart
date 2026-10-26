import 'dart:math' as math;

import 'package:flutter/gestures.dart';

import 'viewport_controller.dart';

/// Turns navigation pointers (fingers, or a mouse dragged with a
/// non-primary button) into pans and zooms of a [ViewportController].
///
/// * One pointer pans once it has moved past [touchSlop] (so a resting
///   finger doesn't jitter the page); lifting it may start a fling.
/// * Two or more pointers pinch: the content under their centroid follows
///   the centroid, and the zoom follows their mean distance from it.
/// * Pointers can join or leave at any time (e.g. a finger that was
///   drawing becomes part of a pinch) without the view jumping: the
///   reference centroid and span are re-taken whenever the set changes.
///
/// We track pointers ourselves instead of using a ScaleGestureRecognizer
/// because the gesture arena only admits pointers at pointer-down, and the
/// editor needs to move an already-down pointer into a pinch.
class NavigationGesture {
  NavigationGesture(
    this.viewport, {
    this.touchSlop = kTouchSlop,
    this.minFlingVelocity = kMinFlingVelocity,
    this.maxFlingVelocity = kMaxFlingVelocity,
  });

  final ViewportController viewport;

  /// Distance one pointer must travel before it starts panning, in logical
  /// pixels.
  final double touchSlop;

  /// Fling speed limits in logical pixels per second.
  final double minFlingVelocity;
  final double maxFlingVelocity;

  final Map<int, _NavPointer> _pointers = {};

  /// Centroid and mean span at the last applied step (viewport-local).
  Offset _focal = Offset.zero;
  double _span = 0;

  /// Where a single pointer went down (for the slop check).
  Offset _slopOrigin = Offset.zero;
  bool _moving = false;

  /// The most pointers that took part in the current gesture. A gesture
  /// that was ever a pinch does not fling.
  int _maxPointers = 0;

  /// True while any pointer navigates.
  bool get isActive => _pointers.isNotEmpty;

  int get pointerCount => _pointers.length;

  bool contains(int pointer) => _pointers.containsKey(pointer);

  /// True once the gesture actually moved the view.
  bool get isMoving => _moving;

  /// Adds a pointer at viewport-local [position].
  void addPointer(int pointer, Offset position, Duration time,
      {PointerDeviceKind kind = PointerDeviceKind.touch}) {
    final p = _NavPointer(position, VelocityTracker.withKind(kind));
    p.tracker.addPosition(time, position);
    _pointers[pointer] = p;
    _maxPointers = math.max(_maxPointers, _pointers.length);
    if (_pointers.length == 1) {
      _slopOrigin = position;
      _moving = false;
    } else {
      // A second finger means the user is deliberately navigating.
      _moving = true;
    }
    _resetReference();
  }

  /// Moves [pointer] to viewport-local [position]. Ignored for unknown
  /// pointers.
  void movePointer(int pointer, Offset position, Duration time) {
    final p = _pointers[pointer];
    if (p == null) return;
    p.position = position;
    p.tracker.addPosition(time, position);

    if (!_moving) {
      if ((position - _slopOrigin).distance < touchSlop) return;
      // Start from here, so the slop distance doesn't make the page jump.
      _moving = true;
      _resetReference();
      return;
    }

    final focal = _centroid();
    final span = _meanSpan(focal);
    var zoom = viewport.zoom;
    if (_pointers.length >= 2 && _span > 0 && span > 0) {
      zoom *= span / _span;
    }
    viewport.moveFocal(_focal, focal, zoom);
    _focal = focal;
    _span = span;
  }

  /// Removes [pointer]. When it was the last pointer of a one-pointer pan,
  /// returns its fling velocity (logical pixels per second, the direction
  /// the content should keep moving), or null for no fling.
  Offset? removePointer(int pointer, Duration time) {
    final p = _pointers.remove(pointer);
    if (p == null) return null;
    if (_pointers.isNotEmpty) {
      _resetReference();
      return null;
    }
    final wasPan = _moving && _maxPointers == 1;
    _reset();
    if (!wasPan) return null;
    final v = p.tracker.getVelocity().pixelsPerSecond;
    final speed = v.distance;
    if (speed < minFlingVelocity) return null;
    return speed > maxFlingVelocity ? v * (maxFlingVelocity / speed) : v;
  }

  /// Drops every pointer without a fling (e.g. the pen came down, so these
  /// touches are a resting palm).
  Iterable<int> cancel() {
    final ids = List.of(_pointers.keys);
    _reset();
    return ids;
  }

  void _reset() {
    _pointers.clear();
    _moving = false;
    _maxPointers = 0;
    _span = 0;
  }

  void _resetReference() {
    if (_pointers.isEmpty) return;
    _focal = _centroid();
    _span = _meanSpan(_focal);
  }

  Offset _centroid() {
    var x = 0.0, y = 0.0;
    for (final p in _pointers.values) {
      x += p.position.dx;
      y += p.position.dy;
    }
    final n = _pointers.length;
    return Offset(x / n, y / n);
  }

  /// Mean distance of the pointers from [focal] (0 for one pointer).
  double _meanSpan(Offset focal) {
    if (_pointers.length < 2) return 0;
    var sum = 0.0;
    for (final p in _pointers.values) {
      sum += (p.position - focal).distance;
    }
    return sum / _pointers.length;
  }
}

class _NavPointer {
  _NavPointer(this.position, this.tracker);
  Offset position;
  final VelocityTracker tracker;
}
