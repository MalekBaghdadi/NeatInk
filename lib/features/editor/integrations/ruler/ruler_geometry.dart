import 'dart:math' as math;
import 'dart:ui' show Offset;

/// How close (logical pixels) a pen must land to a ruler edge, outside or
/// inside, for the stroke to be pulled onto that edge. Also the band along
/// each edge that a finger which draws is left alone in (see
/// `RulerTouchInterceptor`).
const double rulerSnapDistance = 24;

/// One of the two long edges of the ruler. [top] is the edge on the
/// `-normal` side: above the centre while the ruler is horizontal.
enum RulerEdge { top, bottom }

/// Where the ruler lies on the screen: a rectangle [length] long and
/// [thickness] wide around [center], turned by [angle].
///
/// All positions are in the document view's local space (logical pixels), the
/// space pointer events and the overlay share. The ruler is a screen overlay,
/// so none of this depends on the page, the scroll position or the zoom.
///
/// Immutable; the ruler model swaps in a new one when the ruler moves.
class RulerGeometry {
  const RulerGeometry({
    required this.center,
    this.angle = 0,
    required this.length,
    this.thickness = defaultThickness,
  });

  /// Width of the ruler band when the app first shows it.
  static const double defaultThickness = 96;

  /// A pen this far beyond either end of the ruler (along its axis) still
  /// counts as lying beside it, so landing just past the end draws a line
  /// that starts at the end.
  static const double edgeEndMargin = 16;

  final Offset center;

  /// Radians; 0 is horizontal and positive turns clockwise on screen (y
  /// points down).
  final double angle;

  /// Along the ruler's axis.
  final double length;

  /// Across the ruler (distance between the two edges).
  final double thickness;

  /// Unit vector along the ruler, pointing right while [angle] is 0.
  Offset get axis => Offset(math.cos(angle), math.sin(angle));

  /// Unit vector across the ruler, pointing from the [RulerEdge.top] edge to
  /// the [RulerEdge.bottom] one: "down" while [angle] is 0.
  Offset get normal => Offset(-math.sin(angle), math.cos(angle));

  /// The point of [edge] that lies [along] pixels from the ruler's middle
  /// along its axis (negative towards the end on the left at angle 0).
  Offset edgePoint(RulerEdge edge, double along) =>
      center +
      axis * along +
      normal * (edge == RulerEdge.top ? -thickness / 2 : thickness / 2);

  /// The four corners, clockwise from the top edge's left end.
  List<Offset> get corners => [
        edgePoint(RulerEdge.top, -length / 2),
        edgePoint(RulerEdge.top, length / 2),
        edgePoint(RulerEdge.bottom, length / 2),
        edgePoint(RulerEdge.bottom, -length / 2),
      ];

  /// Whether [p] lies on the ruler body, or within [slop] pixels of it.
  bool containsPoint(Offset p, [double slop = 0]) {
    final d = p - center;
    return _along(d).abs() <= length / 2 + slop &&
        _across(d).abs() <= thickness / 2 + slop;
  }

  /// The edge [p] is nearest to, if it is within [maxDistance] of it (on
  /// either side of the edge) and not further than [edgeEndMargin] beyond
  /// the ruler's ends. Null otherwise.
  RulerEdge? nearestEdge(Offset p, double maxDistance) {
    final d = p - center;
    if (!(_along(d).abs() <= length / 2 + edgeEndMargin)) return null;
    final across = _across(d);
    final toTop = (across + thickness / 2).abs();
    final toBottom = (across - thickness / 2).abs();
    final edge = toTop <= toBottom ? RulerEdge.top : RulerEdge.bottom;
    return math.min(toTop, toBottom) <= maxDistance ? edge : null;
  }

  /// The point of [edge] closest to [p], kept within the ruler's length: a
  /// line drawn along the ruler can't run past its end.
  Offset project(Offset p, RulerEdge edge) {
    final half = length / 2;
    final along = _along(p - center);
    // A position that isn't a number projects to the middle of the edge.
    final clamped =
        along.isNaN ? 0.0 : math.min(math.max(along, -half), half);
    return edgePoint(edge, clamped);
  }

  /// The angle the ruler's badge shows: degrees counter-clockwise (the maths
  /// convention) in [0, 180), to one decimal. A ruler is the same ruler
  /// turned by 180°, so the angle repeats every half turn.
  double get displayAngleDegrees {
    final degrees = (-angle * 180 / math.pi) % 180;
    final rounded = (degrees * 10).round() / 10;
    // 0 also swallows the -0.0 of an unturned ruler, and 179.96 rounding up.
    return rounded <= 0 || rounded >= 180 ? 0 : rounded;
  }

  RulerGeometry copyWith({
    Offset? center,
    double? angle,
    double? length,
    double? thickness,
  }) =>
      RulerGeometry(
        center: center ?? this.center,
        angle: angle ?? this.angle,
        length: length ?? this.length,
        thickness: thickness ?? this.thickness,
      );

  /// [d] (a vector from the centre) along / across the ruler.
  double _along(Offset d) => d.dx * math.cos(angle) + d.dy * math.sin(angle);
  double _across(Offset d) => -d.dx * math.sin(angle) + d.dy * math.cos(angle);

  @override
  bool operator ==(Object other) =>
      other is RulerGeometry &&
      other.center == center &&
      other.angle == angle &&
      other.length == length &&
      other.thickness == thickness;

  @override
  int get hashCode => Object.hash(center, angle, length, thickness);

  @override
  String toString() =>
      'RulerGeometry($center, ${angle.toStringAsFixed(3)} rad, $length x $thickness)';
}
