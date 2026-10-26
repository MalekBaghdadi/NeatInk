import 'package:uuid/uuid.dart';

import '../../../document/commands.dart';
import '../../../ink/stroke.dart';
import '../editor_controller.dart';
import '../editor_extensions.dart';
import '../editor_tool.dart';
import '../stroke_events.dart';
import 'live_ink.dart';
import 'stroke_builder.dart';

/// Pen and highlighter: records the stroke on the live layer while drawing
/// and commits it with one [AddStrokesCommand] when the pointer lifts.
///
/// One stroke at a time: while a stroke is active, other pointers routed to
/// this tool are not claimed. A stroke stays on the page it started on (its
/// points are clamped to that page).
class InkToolHandler extends CanvasToolHandler {
  InkToolHandler(this.controller, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final EditorController controller;
  final Uuid _uuid;

  ActiveStroke? _active;
  LiveInk? _live;

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
    final builder = StrokeBuilder(
      pageWidth: page.width,
      pageHeight: page.height,
      startTime: e.timeStamp,
    )..add(hit.point.x, hit.point.y, e.pressure, e.timeStamp);
    final live = controller.liveInkFor(hit.pageId);
    final stroke = ActiveStroke(
      pageId: hit.pageId,
      page: page,
      tool: isHighlighter ? StrokeTool.highlighter : StrokeTool.pen,
      penStyle: isHighlighter ? PenStyle.ballpoint : prefs.pen.style,
      color: isHighlighter ? prefs.highlighter.color : prefs.pen.color,
      size: isHighlighter ? prefs.highlighter.size : prefs.pen.size,
      builder: builder,
      pointer: e.pointer,
      live: live,
    );
    _active = stroke;
    _live = live;
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
    if (stroke.builder.add(p.x, p.y, e.pressure, e.timeStamp)) {
      _live?.markChanged();
    }
    return true;
  }

  void _finish(ActiveStroke active) {
    _active = null;
    final live = _live;
    _live = null;
    final raw = active.builder.build(
      id: _uuid.v4(),
      tool: active.tool,
      penStyle: active.penStyle,
      color: active.color,
      size: active.size,
    );
    final hook = controller.extensions.liveStrokeHook;
    var stroke = hook == null ? raw : hook.onFinish(active, raw);
    if (stroke.id != raw.id) stroke = stroke.copyWith(id: raw.id);
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
