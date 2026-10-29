import 'dart:async';
import 'dart:math' as math;

import '../../../../ink/vec2.dart';
import '../../canvas/live_ink.dart';
import '../../editor_controller.dart';
import '../../editor_extensions.dart';
import '../../tools/hold_detector.dart';
import '../../tools/shape_recognizer.dart';
import '../../tools/tool_config.dart';
import '../../../../ink/stroke.dart';

/// Hold-to-snap: when the pen rests at the end of a pen / highlighter
/// stroke, the stroke is recognized as a line, arrow, rectangle, ellipse or
/// triangle and the clean shape replaces it.
///
/// * While the pen is down and still for [ToolConfig.holdDurationMs], the
///   snapped shape appears as the stroke's `preview` (the hand-drawn ink
///   stays in the stroke, so nothing is lost).
/// * Moving the pen on afterwards adjusts the shape instead of continuing
///   the stroke: a line or arrow's end follows the pen, a closed shape is
///   scaled about its centre.
/// * Lifting commits the shape: `points` = the shape, `shape` set, `raw` =
///   what the pen drew.
/// * If nothing is recognized, nothing happens and the stroke goes on; the
///   hold re-arms once the pen moves again.
///
/// Only active when the "snap shapes" setting is on.
class HoldSnapHook extends LiveStrokeHook {
  HoldSnapHook(
    this.controller, {
    this.config = ToolConfig.defaults,
    this.tick = const Duration(milliseconds: 40),
  });

  final EditorController controller;
  final ToolConfig config;

  /// How often a still pen (which produces no events) is checked.
  final Duration tick;

  ActiveStroke? _stroke;
  HoldDetector _detector = HoldDetector();
  Timer? _timer;

  /// False after a failed recognition until the pen moves again.
  bool _armed = true;

  /// Stroke-relative time of the latest sample, and how long the pen has
  /// been silent since (counted in timer ticks, so it is independent of
  /// the wall clock).
  int _lastMs = 0;
  int _silentMs = 0;
  Vec2 _lastPos = Vec2.zero;

  RecognizedShape? _shape;
  Vec2 _holdPos = Vec2.zero;

  /// Set once the pen left the hold radius, which starts the adjusting.
  bool _adjusting = false;

  /// Whether the stroke being drawn has snapped.
  bool get hasSnapped => _shape != null;

  @override
  void onStart(ActiveStroke stroke) {
    _end();
    if (!controller.settings.shapeSnapEnabled) return;
    _stroke = stroke;
    _detector = HoldDetector(config: config);
    _armed = true;
    _lastMs = 0;
    _silentMs = 0;
    _shape = null;
    _adjusting = false;
    _timer = Timer.periodic(tick, (_) => _onTick());
  }

  @override
  void onSample(ActiveStroke stroke, CanvasPointerEvent e) {
    if (!identical(stroke, _stroke)) return;
    final index = controller.viewport.layout.indexOfPage(stroke.pageId);
    if (index < 0) return;
    final pos = controller.viewport.localToPage(e.localPosition, index);
    final ms = math.max(_lastMs, (e.timeStamp - stroke.startTime).inMilliseconds);
    _lastMs = ms;
    _silentMs = 0;
    _lastPos = pos;

    final shape = _shape;
    if (shape != null) {
      _adjust(stroke, shape, pos);
      return;
    }
    if (!_armed) {
      _detector.reset();
      _armed = true;
    }
    if (_detector.addPoint(pos.x, pos.y, ms)) _snap(stroke);
  }

  void _onTick() {
    final stroke = _stroke;
    if (stroke == null || _shape != null || !_armed) return;
    _silentMs += tick.inMilliseconds;
    if (_detector.check(_lastMs + _silentMs)) _snap(stroke);
  }

  void _snap(ActiveStroke stroke) {
    final shape = recognizeShape(stroke.points, config: config);
    if (shape == null) {
      _armed = false;
      return;
    }
    _shape = shape;
    _holdPos = _lastPos;
    _adjusting = false;
    _timer?.cancel();
    _timer = null;
    _show(stroke, shape);
  }

  /// The pen moved after the snap: resize the shape once it left the hold
  /// radius (so the tremor of a resting pen doesn't wobble the shape).
  void _adjust(ActiveStroke stroke, RecognizedShape shape, Vec2 pos) {
    if (!_adjusting) {
      if (pos.distanceTo(_holdPos) <= config.holdRadiusPt) return;
      switch (_turn(shape, pos)) {
        case _Turn.head:
          return _unsnap(stroke);
        case _Turn.undecided:
          return;
        case _Turn.adjust:
          _adjusting = true;
      }
    }
    final next = shape.resizedTo(_holdPos, pos, config: config);
    if (identical(next, shape)) return;
    _shape = next;
    _holdPos = pos;
    _show(stroke, next);
  }

  /// What the pen does on leaving the hold after a line snapped. Heading
  /// back beside the line, it draws an arrow's head: the writer rested at the
  /// tip of the shaft and goes on in the same stroke (v1.11.0: the head moved
  /// the line's end and the arrow was lost). Going back along the line
  /// (shortening it) or anywhere ahead of its end adjusts the line. Heading
  /// back, it waits until the pen is clearly off the line or
  /// [ToolConfig.unsnapDecidePt] away.
  _Turn _turn(RecognizedShape shape, Vec2 pos) {
    if (shape.kind != ShapeKind.line) return _Turn.adjust;
    final axis = shape.segmentEnd - shape.segmentStart;
    final length = axis.length;
    if (length < 1e-6) return _Turn.adjust;
    final ux = axis.x / length, uy = axis.y / length;
    final mx = pos.x - _holdPos.x, my = pos.y - _holdPos.y;
    final along = mx * ux + my * uy;
    if (along >= 0) return _Turn.adjust;
    final off = (mx * uy - my * ux).abs();
    if (off > math.max(config.holdRadiusPt, config.unsnapOffsetRatio * -along)) return _Turn.head;
    return pos.distanceTo(_holdPos) < config.unsnapDecidePt ? _Turn.undecided : _Turn.adjust;
  }

  /// Gives the pen's ink back: the stroke goes on as drawn.
  void _unsnap(ActiveStroke stroke) {
    _shape = null;
    _adjusting = false;
    stroke.preview = null;
    _detector.reset();
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) => _onTick());
  }

  void _show(ActiveStroke stroke, RecognizedShape shape) {
    stroke.preview =
        shape.toResult(stroke.points, config: config).applyTo(stroke.current);
  }

  @override
  Stroke onFinish(ActiveStroke stroke, Stroke finished) {
    final shape = identical(stroke, _stroke) ? _shape : null;
    _end();
    if (shape == null) return finished;
    return shape.toResult(finished.raw, config: config).applyTo(finished);
  }

  @override
  void onCancel(ActiveStroke stroke) {
    if (identical(stroke, _stroke)) _end();
  }

  void _end() {
    _timer?.cancel();
    _timer = null;
    _stroke = null;
    _shape = null;
  }

  void dispose() => _end();
}

enum _Turn { adjust, head, undecided }
