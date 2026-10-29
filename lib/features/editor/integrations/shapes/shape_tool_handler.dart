import 'package:uuid/uuid.dart';

import '../../../../document/commands.dart';
import '../../../../ink/stroke.dart';
import '../../../../ink/vec2.dart';
import '../../canvas/live_ink.dart';
import '../../canvas/stroke_builder.dart';
import '../../editor_controller.dart';
import '../../editor_extensions.dart';
import '../../stroke_events.dart';
import '../../tools/shape_geometry.dart';
import '../../tools/tool_config.dart';
import 'shape_prefs.dart';

/// The shape tool: drag to draw the selected shape (line, arrow, rectangle,
/// ellipse or triangle) between the pen-down and the current pen position,
/// drawn with the pen's colour and width.
///
/// The shape follows the pen live on the page's live layer; lifting commits
/// it as one undo step. The user's drag is kept as the stroke's `raw`.
/// A cancelled drag, or one too short to draw anything, adds nothing.
class ShapeToolHandler extends CanvasToolHandler {
  ShapeToolHandler(
    this.controller, {
    this.config = ToolConfig.defaults,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  final EditorController controller;
  final ToolConfig config;
  final Uuid _uuid;

  ActiveStroke? _active;
  LiveInk? _live;

  /// The shape being dragged, if any.
  ActiveStroke? get active => _active;

  @override
  bool onPointerDown(CanvasPointerEvent e) {
    final hit = e.hit;
    if (_active != null || hit == null) return false;
    if (!controller.isPageEditable(hit.pageId)) return false;
    final page = controller.doc.pageMeta(hit.pageId);
    if (page == null) return false;
    final pen = controller.toolPrefs.pen;
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
      tool: StrokeTool.pen,
      penStyle: pen.style,
      color: pen.color,
      size: pen.size,
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
    return true;
  }

  @override
  void onPointerMove(CanvasPointerEvent e) {
    final stroke = _active;
    if (stroke == null || e.pointer != stroke.pointer) return;
    if (!_addSample(stroke, e)) return;
    _updatePreview(stroke);
  }

  @override
  void onPointerUp(CanvasPointerEvent e) {
    final stroke = _active;
    if (stroke == null || e.pointer != stroke.pointer) return;
    if (!_addSample(stroke, e)) return;
    _finish(stroke);
  }

  @override
  void onPointerCancel(CanvasPointerEvent e) {
    final stroke = _active;
    if (stroke == null || e.pointer != stroke.pointer) return;
    cancelActive();
  }

  @override
  void commitPending() {
    final stroke = _active;
    if (stroke != null) _finish(stroke);
  }

  @override
  void onDeactivated() => commitPending();

  @override
  void dispose() => cancelActive();

  /// Discards the shape being dragged, if any.
  void cancelActive() {
    if (_active == null) return;
    _active = null;
    _live?.clear();
    _live = null;
  }

  bool _addSample(ActiveStroke stroke, CanvasPointerEvent e) {
    final index = controller.viewport.layout.indexOfPage(stroke.pageId);
    if (index < 0) {
      cancelActive();
      return false;
    }
    final p = controller.viewport.localToPage(e.localPosition, index);
    stroke.builder.add(p.x, p.y, e.pressure, e.timeStamp);
    return true;
  }

  ShapeResult? _build(ActiveStroke stroke) {
    final pts = stroke.points;
    if (pts.length < 2) return null;
    final Vec2 from = pts.first.pos;
    final Vec2 to = pts.last.pos;
    return buildShape(
      selectedShapeKind(controller.toolPrefs),
      from,
      to,
      t0: pts.first.t,
      t1: pts.last.t,
      config: config,
    );
  }

  void _updatePreview(ActiveStroke stroke) {
    final result = _build(stroke);
    stroke.preview = result?.applyTo(stroke.current);
  }

  void _finish(ActiveStroke active) {
    _active = null;
    final live = _live;
    _live = null;
    final result = _build(active);
    if (result != null && controller.isPageEditable(active.pageId)) {
      final raw = active.builder.build(
        id: _uuid.v4(),
        tool: active.tool,
        penStyle: active.penStyle,
        color: active.color,
        size: active.size,
      );
      final stroke = result.applyTo(raw);
      controller.execute(
          AddStrokesCommand(active.pageId, [stroke], label: 'Shape'));
      controller.strokeEvents.emitFinished(FinishedStroke(
        pageId: active.pageId,
        stroke: stroke,
        startMs: active.builder.startMs,
        endMs: active.builder.endMs,
      ));
    }
    live?.clear();
  }
}
