import 'dart:collection';

import '../../../ink/ink_point.dart';
import '../../../ink/stroke.dart';

/// Accumulates the points of a stroke while it is being drawn.
///
/// * Points are clamped to the page the stroke started on (a stroke never
///   leaves its page) and quantized to the precision we persist, so `raw`
///   survives a save/load round trip unchanged.
/// * Every point carries `t` = milliseconds since the stroke started; the
///   absolute start/end times (pointer clock) are kept for the tidy feature.
/// * Consecutive samples that quantize to exactly the same position and
///   pressure are merged (they add nothing to the shape); the end time
///   still advances.
class StrokeBuilder {
  StrokeBuilder({
    required this.pageWidth,
    required this.pageHeight,
    required this.startTime,
  }) : _endTime = startTime;

  /// Page size in points; points are clamped to [0, width] × [0, height].
  final double pageWidth;
  final double pageHeight;

  /// Pointer-clock time of the first sample.
  final Duration startTime;

  final List<InkPoint> _points = [];
  late final UnmodifiableListView<InkPoint> _view =
      UnmodifiableListView(_points);
  Duration _endTime;

  /// The points so far (live view; do not keep across changes).
  List<InkPoint> get points => _view;

  int get length => _points.length;
  bool get isEmpty => _points.isEmpty;
  InkPoint? get last => _points.isEmpty ? null : _points.last;

  /// Pointer-clock time of the latest sample.
  Duration get endTime => _endTime;

  /// [startTime] / [endTime] in whole milliseconds.
  int get startMs => startTime.inMilliseconds;
  int get endMs => _endTime.inMilliseconds;

  /// Adds a sample at page position ([x], [y]) with normalized [pressure]
  /// taken at pointer-clock [time]. Returns true when a point was added
  /// (false when it duplicated the previous point or wasn't finite).
  bool add(double x, double y, double pressure, Duration time) {
    if (!x.isFinite || !y.isFinite) return false;
    if (time > _endTime) _endTime = time;
    final p = InkPoint.quantized(
      x.clamp(0.0, pageWidth).toDouble(),
      y.clamp(0.0, pageHeight).toDouble(),
      pressure.isFinite ? pressure : 0.5,
      // Timestamps never run backwards within a stroke.
      (_endTime - startTime).inMilliseconds,
    );
    final prev = last;
    if (prev != null &&
        prev.x == p.x &&
        prev.y == p.y &&
        prev.pressure == p.pressure) {
      return false;
    }
    _points.add(p);
    return true;
  }

  /// The finished stroke. `raw` and `points` are the same list until the
  /// stroke is tidied or snapped.
  Stroke build({
    required String id,
    required StrokeTool tool,
    PenStyle penStyle = PenStyle.ballpoint,
    required int color,
    required double size,
  }) =>
      Stroke(
        id: id,
        tool: tool,
        penStyle: penStyle,
        color: color,
        size: size,
        raw: _points,
      );
}
