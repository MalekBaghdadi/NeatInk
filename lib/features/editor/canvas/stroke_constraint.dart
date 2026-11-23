import 'dart:ui';

/// Pulls a pen stroke onto a straight line: a ruler's edge, or "Horizontal
/// drawing".
///
/// While a constrained stroke is drawn, the line goes from
/// `project(where the pen landed)` to `project(where the pen is now)`, so the
/// pen can wander and the ink stays straight. The stroke is then committed as
/// a `ShapeKind.line` whose `raw` keeps what the pen really drew.
abstract class StrokeConstraint {
  /// The point of the constrained line that a pen at viewport-local position
  /// [local] stands for.
  Offset project(Offset local);
}

/// "Horizontal drawing": keeps y where the pen landed.
class HorizontalConstraint implements StrokeConstraint {
  const HorizontalConstraint(this.y);

  /// Viewport-local y of the line.
  final double y;

  @override
  Offset project(Offset local) => Offset(local.dx, y);
}
