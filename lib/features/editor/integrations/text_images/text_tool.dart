import 'dart:ui' show Offset;

import '../../../../document/page_items.dart';
import '../../../../ink/ink_rect.dart';
import '../../../../ink/vec2.dart';
import '../../editor_controller.dart';
import '../../editor_extensions.dart';
import 'frame_geometry.dart';
import 'text_editor.dart';

enum _Gesture { none, tap, move, resize }

/// The text tool for pen and mouse pointers (fingers normally navigate and
/// tap through the page overlay instead).
///
/// * Tap on empty paper: a new box; tap on a box: edit it; tap elsewhere
///   while editing: commit.
/// * Drag a box (not being edited): move it. While editing, drag the band
///   around the box to move it and the round handle on its right edge to
///   change its width. Touches on the text itself are claimed and left to
///   the text field.
/// * Commits on tool change and when the editor closes.
class TextToolHandler extends CanvasToolHandler {
  TextToolHandler(this.controller, this.editor);

  final EditorController controller;
  final TextBoxEditor editor;

  /// Screen distance a pointer must travel before a tap becomes a drag.
  static const double dragSlopPx = 8;

  _Gesture _gesture = _Gesture.none;
  int? _pointer;
  String _pageId = '';
  int _pageIndex = 0;
  Offset? _downLocal;
  Vec2 _downPoint = Vec2.zero;
  TextItem? _target;

  // Frame at the start of a drag, to restore on cancel and to offset moves.
  double _startX = 0, _startY = 0, _startWidth = 0;

  Vec2 _pagePoint(CanvasPointerEvent e) =>
      controller.viewport.localToPage(e.localPosition, _pageIndex);

  @override
  bool onPointerDown(CanvasPointerEvent e) {
    if (_pointer != null) return false;
    final hit = e.hit;
    if (hit == null) {
      editor.commit();
      return false;
    }
    if (!controller.isPageEditable(hit.pageId)) return false;
    _pageId = hit.pageId;
    _pageIndex = hit.pageIndex;
    _downLocal = e.localPosition;
    _downPoint = hit.point;
    _pointer = e.pointer;
    _target = null;
    final scale = controller.viewport.scale;

    final s = editor.session;
    if (s != null && s.pageId == hit.pageId) {
      switch (textZone(s.draft.frame, hit.point, scale)) {
        case TextZone.inside:
          // The text field takes it; claiming keeps a finger from scrolling.
          _gesture = _Gesture.none;
          return true;
        case TextZone.move:
          _beginDrag(_Gesture.move, s.draft);
          return true;
        case TextZone.resize:
          _beginDrag(_Gesture.resize, s.draft);
          return true;
        case TextZone.none:
          break;
      }
    }
    _target = hitTextItem(controller.doc.page(hit.pageId).texts, hit.point,
        slop: 4 / scale);
    _gesture = _Gesture.tap;
    return true;
  }

  void _beginDrag(_Gesture gesture, TextItem frame) {
    _gesture = gesture;
    _startX = frame.x;
    _startY = frame.y;
    _startWidth = frame.width;
  }

  @override
  void onPointerMove(CanvasPointerEvent e) {
    if (e.pointer != _pointer) return;
    if (_gesture == _Gesture.tap) {
      final down = _downLocal;
      if (down == null || (e.localPosition - down).distance < dragSlopPx) {
        return;
      }
      final target = _target;
      if (target == null) {
        _gesture = _Gesture.none; // dragging over empty paper does nothing
        return;
      }
      // Dragging a box that is not being edited picks it up.
      editor.begin(_pageId, target, focus: false);
      _beginDrag(_Gesture.move, editor.session!.draft);
    }
    final s = editor.session;
    if (s == null) return;
    final page = controller.doc.pageMeta(_pageId);
    if (page == null) return;
    final p = _pagePoint(e);
    switch (_gesture) {
      case _Gesture.move:
        final delta = p - _downPoint;
        final origin = clampMovedOrigin(
          InkRect.fromLTWH(_startX, _startY, s.draft.width, s.draft.height),
          delta,
          page.width,
          page.height,
        );
        editor.setFrame(x: origin.x, y: origin.y);
      case _Gesture.resize:
        final frame = s.draft.frame;
        // The handle sits on the right edge; keep the grab offset.
        final width = resizedTextWidth(
            frame, _startX + _startWidth + (p.x - _downPoint.x), page.width);
        editor.setFrame(width: width);
      case _Gesture.tap:
      case _Gesture.none:
        break;
    }
  }

  @override
  void onPointerUp(CanvasPointerEvent e) {
    if (e.pointer != _pointer) return;
    final gesture = _gesture;
    _reset();
    if (gesture == _Gesture.tap) {
      editor.tap(_pageId, _downPoint, controller.viewport.scale);
    }
    // A finished move / resize leaves the box open; it commits later.
  }

  @override
  void onPointerCancel(CanvasPointerEvent e) {
    if (e.pointer != _pointer) return;
    final gesture = _gesture;
    _reset();
    if (gesture == _Gesture.move || gesture == _Gesture.resize) {
      editor.setFrame(x: _startX, y: _startY, width: _startWidth);
    }
  }

  void _reset() {
    _gesture = _Gesture.none;
    _pointer = null;
    _target = null;
    _downLocal = null;
  }

  @override
  void commitPending() => editor.commit();

  @override
  void onDeactivated() {
    _reset();
    editor.commit();
  }
}
