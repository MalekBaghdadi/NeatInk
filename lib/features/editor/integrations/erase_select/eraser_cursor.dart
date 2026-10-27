import 'package:flutter/material.dart';

import '../../canvas/viewport_controller.dart';
import 'eraser_handler.dart';

/// The eraser circle under the pen, drawn over the document view (screen
/// space, ignores pointers). It is sized in page points, so it matches what
/// will be erased at any zoom.
class EraserCursorOverlay extends StatelessWidget {
  const EraserCursorOverlay(
      {super.key, required this.handler, required this.viewport});

  final EraserHandler handler;
  final ViewportController viewport;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: ListenableBuilder(
          listenable: Listenable.merge([handler.cursor, viewport]),
          builder: (context, _) {
            final c = handler.cursor.value;
            if (c == null) return const SizedBox.shrink();
            return CustomPaint(
              size: Size.infinite,
              painter: _CursorPainter(c.position, c.radiusPt * viewport.scale),
            );
          },
        ),
      ),
    );
  }
}

class _CursorPainter extends CustomPainter {
  _CursorPainter(this.center, this.radiusPx);

  final Offset center;
  final double radiusPx;

  @override
  void paint(Canvas canvas, Size size) {
    // Never smaller than a small dot, so a fine eraser stays visible.
    final r = radiusPx < 4 ? 4.0 : radiusPx;
    canvas.drawCircle(center, r, Paint()..color = const Color(0x22FFFFFF));
    // Light and dark rings so the circle reads on white, cream and dark paper.
    canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = const Color(0xAAFFFFFF));
    canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xCC3C4043));
  }

  @override
  bool shouldRepaint(_CursorPainter old) =>
      old.center != center || old.radiusPx != radiusPx;
}
