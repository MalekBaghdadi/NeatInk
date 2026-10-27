import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../document/page_items.dart';
import '../../../../ink/ink_rect.dart';
import '../../../../ink/vec2.dart';
import '../../canvas/viewport_controller.dart';
import '../../editor_controller.dart';
import '../../editor_extensions.dart';
import '../../editor_tool.dart';
import 'frame_geometry.dart';
import 'image_editor.dart';
import 'image_layer.dart';

enum _Drag { none, tap, move, resize }

/// The image tool for pen and mouse: tap a picture to select it, drag it to
/// move, drag a corner handle to resize (aspect kept). Fingers select
/// through [ImagePageOverlay] instead, since they navigate.
class ImageToolHandler extends CanvasToolHandler {
  ImageToolHandler(this.controller, this.editor);

  final EditorController controller;
  final ImageEditor editor;

  static const double dragSlopPx = 8;

  _Drag _drag = _Drag.none;
  int? _pointer;
  String _pageId = '';
  int _pageIndex = 0;
  Offset? _downLocal;
  Vec2 _downPoint = Vec2.zero;
  ImageItem? _target;
  ImageCorner _corner = ImageCorner.bottomRight;
  InkRect _startFrame = InkRect.empty;

  @override
  bool onPointerDown(CanvasPointerEvent e) {
    if (_pointer != null) return false;
    final hit = e.hit;
    if (hit == null) {
      editor.select(null);
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

    final s = editor.selection;
    if (s != null && s.pageId == hit.pageId) {
      final corner = imageCornerAt(s.frame, hit.point, scale);
      if (corner != null) {
        _corner = corner;
        _startFrame = s.frame;
        _drag = _Drag.resize;
        return true;
      }
      if (s.frame.contains(hit.point)) {
        _startFrame = s.frame;
        _drag = _Drag.move;
        return true;
      }
    }
    _target = hitImageItem(controller.doc.page(hit.pageId).images, hit.point,
        slop: 2 / scale);
    _drag = _Drag.tap;
    return true;
  }

  @override
  void onPointerMove(CanvasPointerEvent e) {
    if (e.pointer != _pointer) return;
    if (_drag == _Drag.tap) {
      final down = _downLocal;
      if (down == null || (e.localPosition - down).distance < dragSlopPx) {
        return;
      }
      final target = _target;
      if (target == null) {
        _drag = _Drag.none;
        return;
      }
      editor.select(ImageSelection(_pageId, target));
      _startFrame = target.frame;
      _drag = _Drag.move;
    }
    final page = controller.doc.pageMeta(_pageId);
    if (page == null) return;
    final p = controller.viewport.localToPage(e.localPosition, _pageIndex);
    switch (_drag) {
      case _Drag.move:
        final origin = clampMovedOrigin(
            _startFrame, p - _downPoint, page.width, page.height);
        editor.dragTo(InkRect.fromLTWH(
            origin.x, origin.y, _startFrame.width, _startFrame.height));
      case _Drag.resize:
        // Keep the grab offset so the corner doesn't jump to the pen tip.
        final grab = imageCornerPoint(_startFrame, _corner) - _downPoint;
        editor.dragTo(resizedImageFrame(_startFrame, _corner, p + grab));
      case _Drag.tap:
      case _Drag.none:
        break;
    }
  }

  @override
  void onPointerUp(CanvasPointerEvent e) {
    if (e.pointer != _pointer) return;
    final drag = _drag;
    _reset();
    switch (drag) {
      case _Drag.tap:
        editor.tap(_pageId, _downPoint, controller.viewport.scale);
      case _Drag.move:
        editor.commitDrag(resized: false);
      case _Drag.resize:
        editor.commitDrag(resized: true);
      case _Drag.none:
        break;
    }
  }

  @override
  void onPointerCancel(CanvasPointerEvent e) {
    if (e.pointer != _pointer) return;
    _reset();
    editor.cancelDrag();
  }

  void _reset() {
    _drag = _Drag.none;
    _pointer = null;
    _target = null;
    _downLocal = null;
  }

  @override
  void commitPending() {
    if (_drag == _Drag.move || _drag == _Drag.resize) {
      final resized = _drag == _Drag.resize;
      _reset();
      editor.commitDrag(resized: resized);
    }
  }

  @override
  void onDeactivated() {
    _reset();
    editor.cancelDrag();
    editor.select(null);
  }
}

/// The page overlay of the image tool: the finger tap layer, and the
/// selection frame with corner handles (and the picture at its dragged
/// position while it moves).
PageOverlayBuilder imagePageOverlay(
        ImageEditor editor, ImageLayerPainter layer) =>
    (context, page) => ImagePageOverlay(editor: editor, layer: layer, info: page);

class ImagePageOverlay extends StatelessWidget {
  const ImagePageOverlay({
    super.key,
    required this.editor,
    required this.layer,
    required this.info,
  });

  final ImageEditor editor;
  final ImageLayerPainter layer;
  final EditorPageInfo info;

  @override
  Widget build(BuildContext context) {
    final controller = info.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([editor, controller]),
      builder: (context, _) {
        if (controller.tool != EditorTool.image) return const SizedBox.shrink();
        final s = editor.selection;
        final mine = s != null && s.pageId == info.pageId ? s : null;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (d) {
                final finger = d.kind == PointerDeviceKind.touch ||
                    d.kind == PointerDeviceKind.unknown;
                if (!finger ||
                    controller.settings.drawWithFinger ||
                    controller.inputRouter.stylusDown) {
                  return;
                }
                editor.tap(info.pageId,
                    Vec2(d.localPosition.dx, d.localPosition.dy),
                    controller.viewport.scale);
              },
            ),
            if (mine != null)
              IgnorePointer(
                child: CustomPaint(
                  painter: _SelectionPainter(
                    selection: mine,
                    frame: mine.frame,
                    notebookId: controller.notebookId,
                    layer: layer,
                    viewport: controller.viewport,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter({
    required this.selection,
    required this.frame,
    required this.notebookId,
    required this.layer,
    required this.viewport,
    required this.color,
  }) : super(repaint: viewport);

  final ImageSelection selection;
  final InkRect frame;
  final String notebookId;
  final ImageLayerPainter layer;
  final ViewportController viewport;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = viewport.scale;
    final f = frame;
    final rect = Rect.fromLTRB(f.left, f.top, f.right, f.bottom);
    if (selection.moved) {
      final image = layer.imageFor(notebookId, selection.item.asset);
      if (image != null) {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          rect,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = const Color(0xE6FFFFFF),
        );
      }
    }
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / s;
    canvas.drawRect(rect, line);
    for (final c in ImageCorner.values) {
      final p = imageCornerPoint(f, c);
      final center = Offset(p.x, p.y);
      canvas
        ..drawCircle(center, handleRadiusPx * 0.7 / s, Paint()..color = Colors.white)
        ..drawCircle(center, handleRadiusPx * 0.7 / s, line);
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter old) =>
      old.selection != selection ||
      old.frame.left != frame.left ||
      old.frame.top != frame.top ||
      old.frame.right != frame.right ||
      old.frame.bottom != frame.bottom ||
      old.color != color;
}
