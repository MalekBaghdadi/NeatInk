import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../../../../document/commands.dart';
import '../../../../document/notebook_doc.dart';
import '../../../../document/page_content.dart';
import '../../../../ink/affine2.dart';
import '../../../../ink/stroke.dart';
import '../../../../ink/vec2.dart';
import '../../editor_controller.dart';
import '../../editor_extensions.dart';
import '../../tools/lasso.dart';
import '../../tools/selection_transform.dart';
import '../../tools/spatial_index.dart';
import 'lasso_state.dart';
import 'live_edit.dart';
import 'selection_geometry.dart';

/// A move / resize drag of the selection.
class _Drag {
  _Drag({
    required this.handle,
    required this.grab,
    required this.handleOrigin,
    required this.original,
    required this.base,
  });

  /// The grabbed resize handle, or null when moving.
  final ResizeHandle? handle;

  /// Where the pen first touched, in page points.
  final Vec2 grab;

  /// Where the grabbed handle sat then (resizing measures the pen's travel
  /// from it, so the handle doesn't jump to the pen).
  final Vec2 handleOrigin;

  /// The page as it was when the drag started; every preview is computed
  /// from it, so the previews never accumulate rounding.
  final PageContent original;
  final Selection base;

  /// Once the pen has travelled a few pixels (a tap inside the selection
  /// must not nudge it).
  bool started = false;
}

/// The lasso tool: draw a loop around strokes, text boxes and images to
/// select them, then drag inside to move, drag a handle to resize, or use
/// the floating menu (delete, colour, restore original, duplicate).
///
/// A tap selects the single thing under the pen. A pen-down outside the
/// selection starts a new lasso (and drops the old selection); changing tool
/// clears it. Every move, resize and menu action is one undo step; the
/// selection follows undo / redo and drops ids that no longer exist.
class LassoHandler extends CanvasToolHandler {
  LassoHandler(this.controller, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid(),
        _live = LiveEdit(controller);

  /// Pen travel (screen pixels) before a drag inside the selection starts
  /// moving it.
  static const double dragSlopPx = 4;

  /// Offset of a duplicate from the original, in page points.
  static const double duplicateOffsetPt = 16;

  final EditorController controller;
  final Uuid _uuid;
  final LiveEdit _live;

  /// What the overlay and the menu show.
  final LassoState state = LassoState();

  int? _pointer;
  String? _pageId;
  List<Vec2>? _lasso;
  _Drag? _drag;
  NotebookDoc? _hookedDoc;

  double get _scale => math.max(controller.viewport.scale, 1e-6);

  // ---------------------------------------------------------------------------
  // Pointer handling

  @override
  bool onPointerDown(CanvasPointerEvent e) {
    final hit = e.hit;
    if (_pointer != null || hit == null) return false;
    if (!controller.isPageEditable(hit.pageId)) return false;
    // Taps on the floating menu belong to its buttons.
    final menu = state.menuRect;
    if (menu != null && menu.contains(e.localPosition)) return false;

    _pointer = e.pointer;
    _pageId = hit.pageId;
    final sel = state.selection;
    if (sel != null && sel.pageId == hit.pageId) {
      final frame = selectionFrame(sel.bounds, _scale);
      final handle = handleAt(frame, hit.point, _scale);
      if (handle != null || insideFrame(frame, hit.point, _scale)) {
        _drag = _Drag(
          handle: handle,
          grab: hit.point,
          handleOrigin: handle?.positionOn(sel.bounds) ?? hit.point,
          original: controller.doc.page(hit.pageId).copy(),
          base: sel,
        );
        state.setBusy(true);
        return true;
      }
    }
    // A new lasso replaces the selection.
    _lasso = [hit.point];
    state.clear();
    state.setBusy(true);
    state.setLasso(hit.pageId, List.of(_lasso!));
    return true;
  }

  @override
  void onPointerMove(CanvasPointerEvent e) {
    if (e.pointer != _pointer) return;
    final p = _pagePoint(e);
    if (p == null) {
      _abort();
      return;
    }
    final lasso = _lasso;
    if (lasso != null) {
      if (lasso.isEmpty || lasso.last.distanceTo(p) >= 1 / _scale) {
        lasso.add(p);
        state.setLasso(_pageId, List.of(lasso));
      }
      return;
    }
    final drag = _drag;
    if (drag != null) _dragTo(drag, p);
  }

  @override
  void onPointerUp(CanvasPointerEvent e) {
    if (e.pointer != _pointer) return;
    final p = _pagePoint(e);
    final lasso = _lasso;
    if (lasso != null) {
      if (p != null) lasso.add(p);
      _finishLasso(lasso);
      return;
    }
    final drag = _drag;
    if (drag != null) {
      if (p != null) _dragTo(drag, p);
      _finishDrag(drag);
    }
  }

  @override
  void onPointerCancel(CanvasPointerEvent e) {
    if (e.pointer != _pointer) return;
    _abort();
  }

  @override
  void commitPending() {
    final drag = _drag;
    if (drag != null) _finishDrag(drag);
    if (_lasso != null) _abort();
  }

  @override
  void onActivated() => _hookDocument();

  @override
  void onDeactivated() {
    commitPending();
    state.clear();
    _unhookDocument();
  }

  @override
  void dispose() {
    if (_drag != null) _abort();
    _unhookDocument();
    state.dispose();
  }

  Vec2? _pagePoint(CanvasPointerEvent e) {
    final index = controller.viewport.layout.indexOfPage(_pageId!);
    if (index < 0) return null;
    return controller.viewport.localToPage(e.localPosition, index);
  }

  // ---------------------------------------------------------------------------
  // Lasso

  void _finishLasso(List<Vec2> path) {
    final pageId = _pageId!;
    _endGesture();
    state.setLasso(null, const []);
    state.setBusy(false);
    if (!controller.isPageEditable(pageId)) return;
    final content = controller.doc.page(pageId);
    // Taps pick the topmost thing under the pen; the tolerance is about a
    // fingertip on screen at any zoom.
    final tapRadius = (10 / _scale).clamp(2.0, 14.0);
    final selection = lassoSelect(
      pageId: pageId,
      page: content,
      lasso: path,
      index: SpatialIndex.forPage(content),
      tapRadius: tapRadius,
    );
    state.setSelection(selection);
  }

  // ---------------------------------------------------------------------------
  // Move and resize

  void _dragTo(_Drag drag, Vec2 p) {
    if (!drag.started) {
      if ((p - drag.grab).length * _scale < dragSlopPx) return;
      drag.started = true;
    }
    final delta = p - drag.grab;
    final Affine2 m;
    final String label;
    if (drag.handle == null) {
      m = moveTransform(delta.x, delta.y);
      label = 'Move selection';
    } else {
      m = resizeTransform(drag.base.bounds, drag.handle!, drag.handleOrigin + delta);
      label = 'Resize selection';
    }
    final edit = transformSelection(drag.original, drag.base, m);
    _live.show(drag.base.pageId, edit.toCommand(drag.base.pageId, label: label));
  }

  void _finishDrag(_Drag drag) {
    _live.commit();
    _endGesture();
    state.setBusy(false);
  }

  void _abort() {
    _live.discard();
    _endGesture();
    state.setLasso(null, const []);
    state.setBusy(false);
  }

  void _endGesture() {
    _pointer = null;
    _pageId = null;
    _lasso = null;
    _drag = null;
  }

  // ---------------------------------------------------------------------------
  // Selection follows the document

  void _hookDocument() {
    if (!controller.isReady || _hookedDoc != null) return;
    _hookedDoc = controller.doc..addListener(_onDocChange);
  }

  void _unhookDocument() {
    _hookedDoc?.removeListener(_onDocChange);
    _hookedDoc = null;
  }

  /// Keeps the selection in step with the page: bounds follow edits, ids
  /// that disappeared (undo of a duplicate, an eraser) are dropped, and a
  /// deleted page clears it.
  void _onDocChange(DocChange change) {
    final sel = state.selection;
    if (sel == null) return;
    if (!controller.isReady || controller.doc.pageMeta(sel.pageId) == null) {
      state.setSelection(null);
      return;
    }
    if (!change.pageIds.contains(sel.pageId)) return;
    state.setSelection(sel.refreshed(controller.doc.page(sel.pageId)));
  }

  // ---------------------------------------------------------------------------
  // Menu actions

  /// The page content of the selection, or null when it can't be edited.
  PageContent? get _content {
    final sel = state.selection;
    if (sel == null || !controller.isPageEditable(sel.pageId)) return null;
    return controller.doc.page(sel.pageId);
  }

  /// Whether "Restore original" has anything to do: some selected stroke was
  /// tidied, shape-snapped or otherwise differs from its hand-drawn `raw`.
  bool get canRestoreOriginal {
    final page = _content;
    final sel = state.selection;
    if (page == null || sel == null) return false;
    return sel.strokesOn(page).any(isRestorable);
  }

  /// True when [s] shows something other than its hand-drawn points.
  static bool isRestorable(Stroke s) => s.shape != null || !s.pointsAreRaw;

  /// Whether the selection has anything a colour can be applied to.
  bool get canRecolor {
    final page = _content;
    final sel = state.selection;
    if (page == null || sel == null) return false;
    return sel.hasStrokes || sel.textIds.isNotEmpty;
  }

  /// The colour shared by every selected stroke and text box, or null when
  /// they differ.
  int? get commonColor {
    final page = _content;
    final sel = state.selection;
    if (page == null || sel == null) return null;
    final colors = {
      for (final s in sel.strokesOn(page)) s.color,
      for (final t in sel.textsOn(page)) t.color,
    };
    return colors.length == 1 ? colors.first : null;
  }

  /// Deletes the selection (one undo step) and clears it.
  void deleteSelected() {
    final sel = state.selection;
    final page = _content;
    if (sel == null || page == null) return;
    _run(deleteSelection(page, sel), 'Delete selection');
    state.setSelection(null);
  }

  /// Sets the colour of the selected pen strokes and text boxes. Highlighter
  /// strokes keep theirs, unless the selection holds nothing else.
  void recolorSelected(int argb) {
    final sel = state.selection;
    final page = _content;
    if (sel == null || page == null) return;
    final onlyHighlighters = sel.textIds.isEmpty &&
        sel.strokesOn(page).every((s) => s.isHighlighter);
    _run(
        recolorSelection(page, sel, argb, includeHighlighters: onlyHighlighters),
        'Change colour');
  }

  /// Puts tidied and shape-snapped strokes back to their hand-drawn points.
  /// Strokes that were never changed are left alone.
  void restoreOriginal() {
    final sel = state.selection;
    final page = _content;
    if (sel == null || page == null) return;
    final restorable = Selection.fromPage(page,
        pageId: sel.pageId,
        strokeIds: [
          for (final s in sel.strokesOn(page))
            if (isRestorable(s)) s.id,
        ]);
    _run(restoreOriginalSelection(page, restorable), 'Restore original');
  }

  /// Copies the selection, a little down and to the right, and selects the
  /// copy.
  void duplicateSelected() {
    final sel = state.selection;
    final page = _content;
    if (sel == null || page == null) return;
    const d = duplicateOffsetPt;
    final shift = Affine2.translation(d, d);
    final strokes = [
      for (final s in sel.strokesOn(page))
        s.transformed(shift).copyWith(id: _uuid.v4()),
    ];
    final texts = [
      for (final t in sel.textsOn(page))
        t.copyWith(id: _uuid.v4(), x: t.x + d, y: t.y + d),
    ];
    final images = [
      for (final i in sel.imagesOn(page))
        i.copyWith(id: _uuid.v4(), x: i.x + d, y: i.y + d),
    ];
    controller.execute(CompositeCommand('Duplicate', [
      if (strokes.isNotEmpty)
        AddStrokesCommand(sel.pageId, strokes, label: 'Duplicate'),
      if (texts.isNotEmpty || images.isNotEmpty)
        PageItemsCommand(sel.pageId,
            label: 'Duplicate',
            textChanges: [for (final t in texts) (null, t)],
            imageChanges: [for (final i in images) (null, i)]),
    ]));
    state.setSelection(Selection.fromPage(controller.doc.page(sel.pageId),
        pageId: sel.pageId,
        strokeIds: [for (final s in strokes) s.id],
        textIds: [for (final t in texts) t.id],
        imageIds: [for (final i in images) i.id]));
  }

  void _run(SelectionEdit edit, String label) {
    final sel = state.selection;
    if (sel == null) return;
    final command = edit.toCommand(sel.pageId, label: label);
    if (command != null) controller.execute(command);
  }
}
