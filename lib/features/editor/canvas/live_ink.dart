import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../document/notebook_meta.dart';
import '../../../ink/ink_point.dart';
import '../../../ink/stroke.dart';
import '../../../render/stroke_outline.dart';
import 'stroke_builder.dart';

/// The stroke currently being drawn with the pen or highlighter.
///
/// Integrations (hold-to-snap shapes) read its points and may set a
/// [preview] that is shown instead of the hand-drawn ink, e.g. the snapped
/// shape while the pen is held still.
class ActiveStroke {
  ActiveStroke({
    required this.pageId,
    required this.page,
    required this.tool,
    required this.penStyle,
    required this.color,
    required this.size,
    required this.builder,
    required this.pointer,
    required this._live,
  });

  final String pageId;

  /// The page as it was when the stroke started.
  final PageMeta page;
  final StrokeTool tool;
  final PenStyle penStyle;

  /// ARGB.
  final int color;

  /// Width in points.
  final double size;
  final StrokeBuilder builder;

  /// The Flutter pointer id drawing this stroke.
  final int pointer;

  final LiveInk _live;
  Stroke? _preview;
  Stroke? _snapshot;
  int _snapshotLength = -1;

  /// Raw points so far.
  List<InkPoint> get points => builder.points;

  /// Pointer-clock start / latest sample times.
  Duration get startTime => builder.startTime;
  Duration get lastTime => builder.endTime;

  /// The hand-drawn stroke so far (cached until a point is added).
  Stroke get current {
    if (_snapshot == null || _snapshotLength != builder.length) {
      _snapshot = builder.build(
        id: 'live',
        tool: tool,
        penStyle: penStyle,
        color: color,
        size: size,
      );
      _snapshotLength = builder.length;
    }
    return _snapshot!;
  }

  /// Shown instead of [current] while set (and committed instead of it only
  /// if the live-stroke hook returns it from `onFinish`).
  Stroke? get preview => _preview;
  set preview(Stroke? value) {
    if (identical(value, _preview)) return;
    _preview = value;
    _live.markChanged();
  }

  /// What the live layer paints.
  Stroke get displayed => _preview ?? current;
}

/// The live-layer state of one page: the stroke being drawn on it, if any.
///
/// Painting listens to [layer] directly, so drawing never rebuilds
/// widgets. Pen and highlighter strokes have separate listenables because
/// they are painted in different layers (the live highlighter sits under
/// the committed pen ink, see `InkLayer`), and only the layer that shows
/// the active stroke should repaint per sample.
class LiveInk {
  final ValueNotifier<int> _pen = ValueNotifier(0);
  final ValueNotifier<int> _highlighter = ValueNotifier(0);

  ActiveStroke? _active;

  ActiveStroke? get active => _active;

  /// Notifies when the live stroke drawn with [tool] changes.
  Listenable layer(StrokeTool tool) =>
      tool == StrokeTool.highlighter ? _highlighter : _pen;

  void begin(ActiveStroke stroke) {
    final previous = _active;
    _active = stroke;
    if (previous != null && previous.tool != stroke.tool) {
      _bump(previous.tool);
    }
    _bump(stroke.tool);
  }

  /// Call after adding points or changing the preview.
  void markChanged() {
    final active = _active;
    if (active != null) _bump(active.tool);
  }

  void clear() {
    final active = _active;
    if (active == null) return;
    _active = null;
    _bump(active.tool);
  }

  void dispose() {
    _pen.dispose();
    _highlighter.dispose();
  }

  void _bump(StrokeTool tool) {
    final n = tool == StrokeTool.highlighter ? _highlighter : _pen;
    n.value++;
  }
}

/// Paints the active stroke of one page in page coordinates, if it was
/// drawn with [tool].
///
/// The outline is computed with `isComplete: false` so the end of the
/// stroke isn't capped while the pen is still moving; the committed stroke
/// then uses the cached complete outline. A shape preview is already
/// complete, so it is drawn with `isComplete: true`.
class LiveInkPainter extends CustomPainter {
  LiveInkPainter(this.live, this.tool) : super(repaint: live.layer(tool));

  final LiveInk live;
  final StrokeTool tool;

  final Paint _paint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final active = live.active;
    if (active == null || active.tool != tool || active.points.isEmpty) {
      return;
    }
    final s = active.displayed;
    final outline = strokeOutline(s, isComplete: identical(s, active.preview));
    if (outline.length < 3) return;
    _paint.color = strokeFillColor(s);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawPath(outlinePath(outline), _paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(LiveInkPainter oldDelegate) =>
      !identical(oldDelegate.live, live) || oldDelegate.tool != tool;
}
