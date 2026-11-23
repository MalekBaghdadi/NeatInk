import 'dart:math' as math;
import 'dart:ui' show Offset;

/// How far the ruler moves and turns for one pointer move.
class RulerGestureStep {
  const RulerGestureStep(this.translation, this.rotation);

  /// How far the fingers' midpoint moved, in pixels.
  final Offset translation;

  /// How far the line between two fingers turned, in radians (positive is
  /// clockwise on screen). Always 0 for one finger.
  final double rotation;
}

/// The maths of moving and turning the ruler with fingers: one finger drags
/// it, a second finger (anywhere) turns it too.
///
/// A step is the change since the previous event, so the caller just applies
/// each step to the ruler. The reference is taken again whenever a finger
/// joins or leaves, so the ruler never jumps when the number of fingers
/// changes. A third finger is not accepted.
class RulerGesture {
  /// Most fingers a gesture takes.
  static const int maxPointers = 2;

  /// Fingers closer together than this (pixels) don't define a direction, so
  /// they don't turn the ruler.
  static const double minSpan = 24;

  /// Pointer id -> position; iteration is in the order the fingers arrived.
  final Map<int, Offset> _positions = {};

  Offset _midpoint = Offset.zero;

  /// Direction from the first finger to the second at the last step, or null
  /// with one finger or two that are too close.
  double? _direction;

  /// Whether any finger is down.
  bool get isActive => _positions.isNotEmpty;

  int get pointerCount => _positions.length;

  bool contains(int pointer) => _positions.containsKey(pointer);

  /// Starts following [pointer] at [position]. Returns false (and ignores
  /// it) when two fingers are already down, or [pointer] is already followed
  /// or the position isn't a number.
  bool add(int pointer, Offset position) {
    if (_positions.length >= maxPointers ||
        _positions.containsKey(pointer) ||
        !_isFinite(position)) {
      return false;
    }
    _positions[pointer] = position;
    _takeReference();
    return true;
  }

  /// [pointer] moved to [position]. Returns what the ruler should do, or null
  /// for a finger that isn't followed.
  RulerGestureStep? move(int pointer, Offset position) {
    if (!_positions.containsKey(pointer) || !_isFinite(position)) return null;
    _positions[pointer] = position;
    final midpoint = _currentMidpoint();
    final direction = _currentDirection();
    final before = _direction;
    final rotation =
        direction == null || before == null ? 0.0 : _wrap(direction - before);
    final step = RulerGestureStep(midpoint - _midpoint, rotation);
    _midpoint = midpoint;
    _direction = direction;
    return step;
  }

  /// [pointer] lifted. The other finger, if any, carries on as the only one.
  void remove(int pointer) {
    if (_positions.remove(pointer) != null) _takeReference();
  }

  /// Forgets every finger.
  void clear() {
    _positions.clear();
    _takeReference();
  }

  void _takeReference() {
    _midpoint = _currentMidpoint();
    _direction = _currentDirection();
  }

  Offset _currentMidpoint() {
    if (_positions.isEmpty) return Offset.zero;
    var sum = Offset.zero;
    for (final p in _positions.values) {
      sum += p;
    }
    return sum / _positions.length.toDouble();
  }

  double? _currentDirection() {
    if (_positions.length < 2) return null;
    final it = _positions.values.iterator..moveNext();
    final first = it.current;
    it.moveNext();
    final span = it.current - first;
    return span.distance < minSpan ? null : math.atan2(span.dy, span.dx);
  }

  /// [angle] as an equivalent angle in (-π, π].
  static double _wrap(double angle) => math.atan2(math.sin(angle), math.cos(angle));

  static bool _isFinite(Offset p) => p.dx.isFinite && p.dy.isFinite;
}
