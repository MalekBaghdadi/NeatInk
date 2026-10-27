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
      _adjusting = true;
    }
    final next = shape.resizedTo(_holdPos, pos, config: config);
    if (identical(next, shape)) return;
    _shape = next;
    _holdPos = pos;
    _show(stroke, next);
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
