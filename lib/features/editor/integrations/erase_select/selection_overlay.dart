import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../ink/ink_rect.dart';
import '../../../../ink/vec2.dart';
import '../../editor_extensions.dart';
import '../../tools/selection_transform.dart';
import 'lasso_state.dart';
import 'selection_geometry.dart';

/// Page overlay of the lasso: the loop being drawn, and the selection's
/// frame with its eight resize handles. Ignores pointers (the lasso handler
/// does the hit testing).
class SelectionPageOverlay extends StatelessWidget {
  const SelectionPageOverlay({super.key, required this.state, required this.page});

  final LassoState state;
  final EditorPageInfo page;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: Listenable.merge([state, page.controller.viewport]),
        builder: (context, _) {
          final sel = state.selection;
          final bounds = sel != null && sel.pageId == page.pageId
              ? sel.bounds
              : null;
          final showLasso =
              state.lassoPageId == page.pageId && state.lassoPath.length > 1;
          if (bounds == null && !showLasso) return const SizedBox.shrink();
          return RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: SelectionPainter(
                accent: accent,
                scale: page.controller.viewport.scale,
                bounds: bounds,
                lasso: showLasso ? state.lassoPath : const [],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Paints in page points; line widths and handle sizes are divided by
/// [scale] so they stay the same size on screen at every zoom.
class SelectionPainter extends CustomPainter {
  SelectionPainter({
    required this.accent,
    required this.scale,
    required this.bounds,
    required this.lasso,
  });

  final Color accent;
  final double scale;
  final InkRect? bounds;
  final List<Vec2> lasso;

  static const double _handlePx = 11;

  @override
  void paint(Canvas canvas, Size size) {
    final px = 1 / math.max(scale, 1e-6);
    if (lasso.length > 1) _paintLasso(canvas, px);
    final b = bounds;
    if (b != null) _paintSelection(canvas, selectionFrame(b, scale), px);
  }

  void _paintLasso(Canvas canvas, double px) {
    final path = Path()..moveTo(lasso.first.x, lasso.first.y);
    for (final p in lasso.skip(1)) {
      path.lineTo(p.x, p.y);
    }
    canvas.drawPath(
        Path.from(path)..close(), Paint()..color = accent.withValues(alpha: 0.08));
    _dashed(canvas, path, 1.6 * px, accent, dash: 7 * px, gap: 5 * px);
  }

  void _paintSelection(Canvas canvas, InkRect f, double px) {
    final rect = Rect.fromLTRB(f.left, f.top, f.right, f.bottom);
    canvas.drawRect(rect, Paint()..color = accent.withValues(alpha: 0.06));
    final outline = Path()..addRect(rect);
    _dashed(canvas, outline, 1.4 * px, accent, dash: 6 * px, gap: 4 * px);
    final half = _handlePx * px / 2;
    final fill = Paint()..color = Colors.white;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * px
      ..color = accent;
    for (final h in ResizeHandle.values) {
      final c = h.positionOn(f);
      final r = Rect.fromCenter(
          center: Offset(c.x, c.y), width: half * 2, height: half * 2);
      if (h.isCorner) {
        canvas.drawCircle(r.center, half, fill);
        canvas.drawCircle(r.center, half, ring);
      } else {
        final rr = RRect.fromRectAndRadius(r, Radius.circular(2 * px));
        canvas.drawRRect(rr, fill);
        canvas.drawRRect(rr, ring);
      }
    }
  }

  static void _dashed(Canvas canvas, Path path, double width, Color color,
      {required double dash, required double gap}) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
            metric.extractPath(d, math.min(d + dash, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(SelectionPainter old) =>
      old.accent != accent ||
      old.scale != scale ||
      old.bounds != bounds ||
      !identical(old.lasso, lasso);
}
