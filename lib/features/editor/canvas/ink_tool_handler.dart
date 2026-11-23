import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:uuid/uuid.dart';

import '../../../document/commands.dart';
import '../../../ink/stroke.dart';
import '../../../ink/vec2.dart';
import '../editor_controller.dart';
import '../editor_extensions.dart';
import '../editor_tool.dart';
import '../stroke_events.dart';
import '../tools/shape_geometry.dart';
import 'live_ink.dart';
import 'stroke_builder.dart';
import 'stroke_constraint.dart';

/// Pen and highlighter: records the stroke on the live layer while drawing
/// and commits it with one [AddStrokesCommand] when the pointer lifts.
///
/// One stroke at a time: while a stroke is active, other pointers routed to
/// this tool are not claimed. A stroke stays on the page it started on (its
/// points are clamped to that page).
///
/// A stroke can be pulled onto a straight line by a [StrokeConstraint] (a
/// ruler edge, or "Horizontal drawing"): it is then shown and committed like
/// the shape tool's line, from where the pen landed to where it is now, with
/// the real pen path kept as `raw`.
class InkToolHandler extends CanvasToolHandler {
  InkToolHandler(this.controller, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final EditorController controller;
  final Uuid _uuid;

  ActiveStroke? _active;
  LiveInk? _live;

  /// Where the pen landed and where it is now, in viewport-local pixels (the
  /// space a [StrokeConstraint] works in). Only read for a constrained stroke.
  Offset _startLocal = Offset.zero;
  Offset _lastLocal = Offset.zero;

  /// The stroke being drawn, if any.
  ActiveStroke? get active => _active;

  @override
  bool onPointerDown(CanvasPointerEvent e) {
    final hit = e.hit;
    if (_active != null || hit == null) return false;
    if (!controller.isPageEditable(hit.pageId)) return false;
    final page = controller.doc.pageMeta(hit.pageId);
    if (page == null) return false;
    final isHighlighter = controller.tool == EditorTool.highlighter;
    final prefs = controller.toolPrefs;
    // A ruler edge near the pen wins; otherwise "Horizontal drawing".
    final horizontal =
        isHighlighter ? prefs.highlighter.horizontal : prefs.pen.horizontal;
    final constraint = controller.extensions.strokeConstraint?.call(e) ??
        (horizontal ? HorizontalConstraint(e.localPosition.dy) : null);
    final builder = StrokeBuilder(
      pageWidth: page.width,
      pageHeight: page.height,
      startTime: e.timeStamp,
      writtenAt: controller.now().millisecondsSinceEpoch,
    )..add(hit.point.x, hit.point.y, e.pressure, e.timeStamp);
    final live = controller.liveInkFor(hit.pageId);
    final stroke = ActiveStroke(
      pageId: hit.pageId,
      page: page,
      tool: isHighlighter ? StrokeTool.highlighter : StrokeTool.pen,
      penStyle: isHighlighter ? PenStyle.ballpoint : prefs.pen.style,
      highlightEnds: isHighlighter ? prefs.highlighter.ends : HighlightEnds.square,
      color: isHighlighter ? prefs.highlighter.color : prefs.pen.color,
      size: isHighlighter ? prefs.highlighter.size : prefs.pen.size,
      line: isHighlighter ? prefs.highlighter.line : prefs.pen.line,
      concentration: isHighlighter
          ? prefs.highlighter.concentration
          : prefs.pen.concentration,
      builder: builder,
      pointer: e.pointer,
      live: live,
      constraint: constraint,
    );
    _active = stroke;
    _live = live;
    _startLocal = _lastLocal = e.localPosition;
    live.begin(stroke);
    controller.strokeEvents.emitStarted(StrokeStartedEvent(
      pageId: stroke.pageId,
      tool: stroke.tool,
      startMs: builder.startMs,
    ));
    final hook = controller.extensions.liveStrokeHook;
    hook?.onStart(stroke);
    hook?.onSample(stroke, e);
    return true;
  }

  @override
  void onPointerMove(CanvasPointerEvent e) {
    final stroke = _active;
    if (stroke == null || e.pointer != stroke.pointer) return;
    if (!_addSample(stroke, e)) return;
    controller.extensions.liveStrokeHook?.onSample(stroke, e);
  }

  @override
  void onPointerUp(CanvasPointerEvent e) {
    final stroke = _active;
    if (stroke == null || e.pointer != stroke.pointer) return;
    // The lift-off sample often reports zero pressure; keep its position
    // with the last pressure so the stroke doesn't end in a sharp taper.
    final index = controller.viewport.layout.indexOfPage(stroke.pageId);
    if (index < 0) {
      cancelActive();
      return;
    }
    final p = controller.viewport.localToPage(e.localPosition, index);
    stroke.builder.add(p.x, p.y, stroke.builder.last?.pressure ?? e.pressure,
        e.timeStamp);
    _lastLocal = e.localPosition;
    _finish(stroke);
  }

  @override
  void onPointerCancel(CanvasPointerEvent e) {
    final stroke = _active;
    if (stroke == null || e.pointer != stroke.pointer) return;
    cancelActive();
  }

  /// Discards the active stroke (if any) without committing it.
  void cancelActive() {
    final stroke = _active;
    if (stroke == null) return;
    _active = null;
    _live?.clear();
    _live = null;
    controller.extensions.liveStrokeHook?.onCancel(stroke);
  }

  /// Commits the active stroke now (e.g. when the editor is closing while
  /// the pen is still down).
  void commitActive() {
    final stroke = _active;
    if (stroke != null) _finish(stroke);
  }

  /// Adds one sample; returns false (and cancels) when the stroke's page
  /// disappeared meanwhile (e.g. its insertion was undone).
  bool _addSample(ActiveStroke stroke, CanvasPointerEvent e) {
    final index = controller.viewport.layout.indexOfPage(stroke.pageId);
    if (index < 0) {
      cancelActive();
      return false;
    }
    final p = controller.viewport.localToPage(e.localPosition, index);
    final added = stroke.builder.add(p.x, p.y, e.pressure, e.timeStamp);
    _lastLocal = e.localPosition;
    if (stroke.constraint != null) {
      // The line can change even when the pen's own point didn't (the pen
      // left the page, or moved off the line's direction). A new preview
      // repaints by itself; with no line the hand-drawn ink shows instead.
      stroke.preview = _constrainedLine(stroke)?.applyTo(stroke.current);
      if (added && stroke.preview == null) _live?.markChanged();
    } else if (added) {
      _live?.markChanged();
    }
    return true;
  }

  /// A pen tap rather than a stroke: short, and the pen barely moved
  /// (in screen pixels, so it does not depend on the zoom).
  static const Duration tapMaxDuration = Duration(milliseconds: 350);
  static const double tapMaxTravelPx = 6;

  bool _isTap(ActiveStroke active) {
    final points = active.builder.points;
    if (points.isEmpty) return false;
    if (active.builder.endMs - active.builder.startMs >
        tapMaxDuration.inMilliseconds) {
      return false;
    }
    final scale = controller.viewport.scale;
    final reach = tapMaxTravelPx / (scale > 0 ? scale : 1);
    final first = points.first;
    return points.every(
        (p) => (p.x - first.x).abs() <= reach && (p.y - first.y).abs() <= reach);
  }

  /// The line a constrained stroke is drawing: from where the pen landed to
  /// where it is now, both pulled onto the constraint (so it stays straight
  /// whatever the pen does) and cut to the page. Cut, not clamped per axis,
  /// so a ruler that runs over the page edge still gives a straight line.
  ///
  /// Null for a stroke that isn't constrained, and when there is no line to
  /// draw: a tap, or a line that lies outside the page. The stroke is then
  /// kept as the pen drew it (a tap stays a dot).
  ShapeResult? _constrainedLine(ActiveStroke stroke) {
    final constraint = stroke.constraint;
    final points = stroke.points;
    final viewport = controller.viewport;
    final index = viewport.layout.indexOfPage(stroke.pageId);
    if (constraint == null || points.isEmpty || index < 0) return null;
    final from = viewport.localToPage(constraint.project(_startLocal), index);
    final to = viewport.localToPage(constraint.project(_lastLocal), index);
    final visible =
        clipSegmentToRect(from, to, stroke.page.width, stroke.page.height);
    if (visible == null) return null;
    return buildShape(
      ShapeKind.line,
      visible.$1,
      visible.$2,
      t0: points.first.t,
      t1: points.last.t,
    );
  }

  void _finish(ActiveStroke active) {
    _active = null;
    final live = _live;
    _live = null;
    // A tap something on the page wants (e.g. a corrected word) is not ink.
    if (controller.extensions.pageTapHandlers.isNotEmpty && _isTap(active)) {
      final p = active.builder.points.first;
      if (controller.extensions.handleTap(active.pageId, Vec2(p.x, p.y))) {
        live?.clear();
        controller.extensions.liveStrokeHook?.onCancel(active);
        return;
      }
    }
    final penStroke = active.builder.build(
      id: _uuid.v4(),
      tool: active.tool,
      penStyle: active.penStyle,
      highlightEnds: active.highlightEnds,
      color: active.color,
      size: active.size,
      line: active.line,
      concentration: active.concentration,
    );
    // A constrained stroke commits as its straight line. `raw` stays the
    // real pen path; only `points` and `shape` change.
    final drawn = _constrainedLine(active)?.applyTo(penStroke) ?? penStroke;
    final hook = controller.extensions.liveStrokeHook;
    if (active.tool == StrokeTool.pen && controller.isPageEditable(active.pageId)) {
      for (final gesture in controller.extensions.strokeGestures) {
        if (gesture(active.pageId, drawn)) {
          hook?.onCancel(active);
          live?.clear();
          return;
        }
      }
    }
    var stroke = hook == null ? drawn : hook.onFinish(active, drawn);
    for (final finish in controller.extensions.strokeFinishers) {
      stroke = finish(active.pageId, stroke);
    }
    if (stroke.id != drawn.id) stroke = stroke.copyWith(id: drawn.id);
    // Commit before clearing the live layer: both repaint in the same
    // frame, so the stroke never blinks.
    if (controller.isPageEditable(active.pageId)) {
      controller.execute(AddStrokesCommand(
        active.pageId,
        [stroke],
        label: stroke.shape != null
            ? 'Shape'
            : stroke.isHighlighter
                ? 'Highlighter'
                : 'Pen stroke',
      ));
      controller.strokeEvents.emitFinished(FinishedStroke(
        pageId: active.pageId,
        stroke: stroke,
        startMs: active.builder.startMs,
        endMs: active.builder.endMs,
      ));
    }
    live?.clear();
  }

  @override
  void commitPending() => commitActive();

  @override
  void onDeactivated() => commitActive();

  @override
  void dispose() => cancelActive();
}

/// The part of the segment [a]–[b] that lies inside the rectangle
/// `[0, width] × [0, height]` (Liang–Barsky), or null when none of it does or
/// an end isn't a number. The ends of the result are on the segment, so its
/// direction is kept.
///
/// A segment lying along a side of the rectangle counts as inside.
(Vec2, Vec2)? clipSegmentToRect(Vec2 a, Vec2 b, double width, double height) {
  if (!a.isFinite || !b.isFinite || !(width >= 0) || !(height >= 0)) {
    return null;
  }
  final dx = b.x - a.x, dy = b.y - a.y;
  var t0 = 0.0, t1 = 1.0;

  // Narrows [t0, t1] to where `p * t <= q`; false once nothing is left.
  bool clip(double p, double q) {
    if (p == 0) return q >= 0; // parallel to this side: in or out for good
    final r = q / p;
    if (p < 0) {
      if (r > t1) return false;
      t0 = math.max(t0, r);
    } else {
      if (r < t0) return false;
      t1 = math.min(t1, r);
    }
    return true;
  }

  if (!clip(-dx, a.x) ||
      !clip(dx, width - a.x) ||
      !clip(-dy, a.y) ||
      !clip(dy, height - a.y)) {
    return null;
  }
  // Rounding can leave an end a hair outside the rectangle.
  Vec2 at(double t) => Vec2(
        math.min(math.max(a.x + dx * t, 0.0), width),
        math.min(math.max(a.y + dy * t, 0.0), height),
      );
  return (at(t0), at(t1));
}
