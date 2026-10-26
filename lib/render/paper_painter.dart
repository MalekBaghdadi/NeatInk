import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../document/paper.dart';

/// Thinnest line the painter draws, in logical pixels. Page rulings are
/// hairlines in points; in small previews (or zoomed out) they would
/// otherwise vanish.
const double minPaperLineWidth = 0.5;

/// Smallest dot radius on dotted paper, in logical pixels.
const double minPaperDotRadius = 0.6;

/// Paints a page's paper: the background colour plus the ruling from
/// [PaperGeometry], scaled from page points to the canvas size.
///
/// Used by the library previews, the settings screen and the editor's page
/// background. The canvas should have the page's aspect ratio; if it does
/// not, x and y are scaled independently so lines still span the page.
class PaperPainter extends CustomPainter {
  PaperPainter(this.paper, this.pageWidthPt, this.pageHeightPt);

  final Paper paper;
  final double pageWidthPt;
  final double pageHeightPt;

  @override
  void paint(Canvas canvas, Size size) =>
      paintPaper(canvas, size, paper, pageWidthPt, pageHeightPt);

  // A change of canvas size triggers a repaint by itself (new layout), so
  // only the inputs need comparing here.
  @override
  bool shouldRepaint(PaperPainter oldDelegate) =>
      oldDelegate.paper != paper ||
      oldDelegate.pageWidthPt != pageWidthPt ||
      oldDelegate.pageHeightPt != pageHeightPt;
}

/// Paints [paper] for a page of [pageWidthPt] × [pageHeightPt] points onto
/// a [size] canvas. Set [fillBackground] to false to draw only the ruling
/// (e.g. over an image).
void paintPaper(
  Canvas canvas,
  Size size,
  Paper paper,
  double pageWidthPt,
  double pageHeightPt, {
  bool fillBackground = true,
}) {
  if (size.isEmpty) return;
  if (fillBackground) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Color(paper.color));
  }
  if (pageWidthPt <= 0 || pageHeightPt <= 0 || paper.type == PaperType.blank) {
    return;
  }

  final sx = size.width / pageWidthPt;
  final sy = size.height / pageHeightPt;
  // Widths and radii use the smaller scale so a slightly squashed canvas
  // never makes the ruling heavier than on the real page.
  final widthScale = math.min(sx, sy);
  final geometry = _cachedGeometry(paper, pageWidthPt, pageHeightPt);

  for (final role in PaperLineRole.values) {
    final paint = Paint()
      ..color = Color(
          role == PaperLineRole.rule ? paper.lineColor : paper.accentColor)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = math.max(
          PaperGeometry.strokeWidthFor(role) * widthScale, minPaperLineWidth);
    final path = Path();
    var any = false;
    for (final line in geometry.lines) {
      if (line.role != role) continue;
      path
        ..moveTo(line.from.x * sx, line.from.y * sy)
        ..lineTo(line.to.x * sx, line.to.y * sy);
      any = true;
    }
    if (any) canvas.drawPath(path, paint);
  }

  if (geometry.dots.isNotEmpty) {
    final radius =
        math.max(PaperGeometry.dotRadius * widthScale, minPaperDotRadius);
    // One drawPoints call with round caps is far cheaper than a circle per
    // dot (an A4 page has ~700 dots).
    final paint = Paint()
      ..color = Color(paper.lineColor)
      ..strokeWidth = radius * 2
      ..strokeCap = StrokeCap.round;
    canvas.drawPoints(
      ui.PointMode.points,
      [for (final d in geometry.dots) Offset(d.x * sx, d.y * sy)],
      paint,
    );
  }
}

/// [PaperGeometry] is pure and deterministic, and the editor repaints the
/// same few (paper, size) combinations over and over, so keep a small LRU.
const int _geometryCacheSize = 24;
final LinkedHashMap<(Paper, double, double), PaperGeometry> _geometryCache =
    LinkedHashMap();

PaperGeometry _cachedGeometry(Paper paper, double width, double height) {
  final key = (paper, width, height);
  final hit = _geometryCache.remove(key);
  if (hit != null) {
    _geometryCache[key] = hit; // Move to the most-recent end.
    return hit;
  }
  final geometry = PaperGeometry(paper, width, height);
  _geometryCache[key] = geometry;
  if (_geometryCache.length > _geometryCacheSize) {
    _geometryCache.remove(_geometryCache.keys.first);
  }
  return geometry;
}
