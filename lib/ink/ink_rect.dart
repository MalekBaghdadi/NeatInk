import 'dart:math' as math;

import 'vec2.dart';

/// An immutable axis-aligned rectangle in page coordinates (y down).
class InkRect {
  const InkRect(this.left, this.top, this.right, this.bottom);

  const InkRect.fromLTWH(double left, double top, double width, double height)
      : this(left, top, left + width, top + height);

  static const InkRect empty = InkRect(0, 0, 0, 0);

  /// Bounding box of [points]. Returns [empty] for an empty iterable.
  factory InkRect.fromPoints(Iterable<Vec2> points) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    if (minX == double.infinity) return empty;
    return InkRect(minX, minY, maxX, maxY);
  }

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get area => width * height;
  double get diagonal => math.sqrt(width * width + height * height);
  Vec2 get center => Vec2((left + right) / 2, (top + bottom) / 2);
  Vec2 get topLeft => Vec2(left, top);
  Vec2 get bottomRight => Vec2(right, bottom);
  bool get isEmpty => width <= 0 || height <= 0;

  bool contains(Vec2 p) =>
      p.x >= left && p.x <= right && p.y >= top && p.y <= bottom;

  /// True when the rectangles touch or overlap (inclusive edges, so
  /// zero-height rects such as a flat line still count).
  bool overlaps(InkRect o) =>
      left <= o.right && o.left <= right && top <= o.bottom && o.top <= bottom;

  InkRect intersect(InkRect o) {
    final l = math.max(left, o.left), t = math.max(top, o.top);
    final r = math.min(right, o.right), b = math.min(bottom, o.bottom);
    if (r < l || b < t) return empty;
    return InkRect(l, t, r, b);
  }

  InkRect union(InkRect o) => InkRect(math.min(left, o.left),
      math.min(top, o.top), math.max(right, o.right), math.max(bottom, o.bottom));

  InkRect inflate(double d) => InkRect(left - d, top - d, right + d, bottom + d);

  InkRect translate(double dx, double dy) =>
      InkRect(left + dx, top + dy, right + dx, bottom + dy);

  @override
  bool operator ==(Object other) =>
      other is InkRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'InkRect(${left.toStringAsFixed(1)}, '
      '${top.toStringAsFixed(1)}, ${right.toStringAsFixed(1)}, '
      '${bottom.toStringAsFixed(1)})';
}
