import '../../../ink/ink_rect.dart';
import '../../../ink/vec2.dart';

/// Whether the eraser circle of [radius] swept from [from] to [to] touches
/// [rect] (a word of typed text): the segment against the rectangle grown by
/// the radius (square corners, a little generous at the very corners).
bool sweepTouchesRect(Vec2 from, Vec2 to, double radius, InkRect rect) {
  final r = rect.inflate(radius);
  if (r.contains(from) || r.contains(to)) return true;
  // Liang-Barsky: clip the segment to the rectangle.
  final dx = to.x - from.x, dy = to.y - from.y;
  var t0 = 0.0, t1 = 1.0;
  bool clip(double p, double q) {
    if (p == 0) return q >= 0;
    final t = q / p;
    if (p < 0) {
      if (t > t1) return false;
      if (t > t0) t0 = t;
    } else {
      if (t < t0) return false;
      if (t < t1) t1 = t;
    }
    return true;
  }

  return clip(-dx, from.x - r.left) &&
      clip(dx, r.right - from.x) &&
      clip(-dy, from.y - r.top) &&
      clip(dy, r.bottom - from.y) &&
      t0 <= t1;
}
