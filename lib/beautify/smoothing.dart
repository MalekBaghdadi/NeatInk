import '../ink/ink_point.dart';
import 'tidy_config.dart';

/// Spec step 5d: one pass of a 3-point weighted moving average on x and y.
///
/// With neighbour weight `w` the weights are `(w, 1 − 2w, w)`; the default
/// `w = 0.25` gives the spec's `(0.25, 0.5, 0.25)`. The first and last points
/// stay fixed (so strokes keep touching what they touched), pressure and time
/// are untouched, and strokes with fewer than `minPointsForSmoothing` points
/// are returned unchanged. The point count never changes, which is what lets
/// the editor animate raw → tidied point by point.
List<InkPoint> smoothPoints(List<InkPoint> points,
    {TidyConfig config = const TidyConfig()}) {
  final n = points.length;
  if (n < config.minPointsForSmoothing) return points;
  final w = config.smoothingNeighbourWeight;
  final c = 1 - 2 * w;
  final out = List<InkPoint>.of(points);
  // Reads come from the unmodified input, so the result does not depend on
  // the direction of the pass.
  for (var i = 1; i < n - 1; i++) {
    final a = points[i - 1], b = points[i], d = points[i + 1];
    out[i] = b.withPos(
        w * a.x + c * b.x + w * d.x, w * a.y + c * b.y + w * d.y);
  }
  return out;
}
