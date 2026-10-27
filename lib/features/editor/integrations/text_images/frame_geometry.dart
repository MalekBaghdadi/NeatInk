import 'dart:math' as math;

import '../../../../document/page_items.dart';
import '../../../../ink/ink_rect.dart';
import '../../../../ink/vec2.dart';

// Pure geometry shared by the text box and image tools: hit zones around a
// frame, move / resize maths and fitting a picture on a page. Sizes that
// should stay constant on screen are given in logical pixels and divided by
// the viewport scale (pixels per page point).

/// Radius of the round resize handle, in screen pixels.
const double handleRadiusPx = 11;

/// Extra grab radius around a handle so a pen tip hits it easily.
const double handleSlopPx = 8;

/// Width of the band around a text box that drags it, in screen pixels.
const double moveBandPx = 14;

/// Smallest text box width, in page points.
const double minTextWidth = 36;

/// Smallest picture side, in page points.
const double minImageSide = 24;

/// Part of a box that must stay on the page when it is moved.
const double keepOnPage = 24;

/// What a point is over, relative to the text box being edited.
enum TextZone {
  /// Away from the box.
  none,

  /// On the text itself (the text field handles it).
  inside,

  /// On the band around the text: dragging moves the box.
  move,

  /// On the width handle: dragging resizes the box.
  resize,
}

/// Centre of the width handle of a text box: the middle of its right edge.
Vec2 textResizeHandle(InkRect frame) =>
    Vec2(frame.right, frame.top + frame.height / 2);

TextZone textZone(InkRect frame, Vec2 p, double scale) {
  final reach = (handleRadiusPx + handleSlopPx) / scale;
  if (p.distanceTo(textResizeHandle(frame)) <= reach) return TextZone.resize;
  if (frame.contains(p)) return TextZone.inside;
  if (frame.inflate(moveBandPx / scale).contains(p)) return TextZone.move;
  return TextZone.none;
}

/// The topmost text box under [p] (later boxes paint on top), or null.
/// [slop] grows every box so thin one-line boxes are easy to hit.
TextItem? hitTextItem(List<TextItem> items, Vec2 p, {double slop = 0}) {
  for (var i = items.length - 1; i >= 0; i--) {
    if (items[i].frame.inflate(slop).contains(p)) return items[i];
  }
  return null;
}

/// The topmost picture under [p], or null.
ImageItem? hitImageItem(List<ImageItem> items, Vec2 p, {double slop = 0}) {
  for (var i = items.length - 1; i >= 0; i--) {
    if (items[i].frame.inflate(slop).contains(p)) return items[i];
  }
  return null;
}

/// Moves [frame] by [delta], keeping at least [keepOnPage] of it on the page.
Vec2 clampMovedOrigin(
    InkRect frame, Vec2 delta, double pageWidth, double pageHeight) {
  final w = frame.width, h = frame.height;
  final x = (frame.left + delta.x)
      .clamp(math.min(0.0, keepOnPage - w), math.max(0.0, pageWidth - keepOnPage))
      .toDouble();
  final y = (frame.top + delta.y)
      .clamp(math.min(0.0, keepOnPage - h), math.max(0.0, pageHeight - keepOnPage))
      .toDouble();
  return Vec2(x, y);
}

/// New width of a text box whose right edge is dragged to [pointerX].
double resizedTextWidth(InkRect frame, double pointerX, double pageWidth) {
  final maxWidth = math.max(minTextWidth, pageWidth - frame.left);
  return (pointerX - frame.left).clamp(minTextWidth, maxWidth).toDouble();
}

enum ImageCorner { topLeft, topRight, bottomLeft, bottomRight }

Vec2 imageCornerPoint(InkRect f, ImageCorner c) => switch (c) {
      ImageCorner.topLeft => Vec2(f.left, f.top),
      ImageCorner.topRight => Vec2(f.right, f.top),
      ImageCorner.bottomLeft => Vec2(f.left, f.bottom),
      ImageCorner.bottomRight => Vec2(f.right, f.bottom),
    };

ImageCorner _opposite(ImageCorner c) => switch (c) {
      ImageCorner.topLeft => ImageCorner.bottomRight,
      ImageCorner.topRight => ImageCorner.bottomLeft,
      ImageCorner.bottomLeft => ImageCorner.topRight,
      ImageCorner.bottomRight => ImageCorner.topLeft,
    };

/// The corner handle of a picture under [p], or null.
ImageCorner? imageCornerAt(InkRect frame, Vec2 p, double scale) {
  final reach = (handleRadiusPx + handleSlopPx) / scale;
  ImageCorner? best;
  var bestDistance = reach;
  for (final c in ImageCorner.values) {
    final d = p.distanceTo(imageCornerPoint(frame, c));
    if (d <= bestDistance) {
      best = c;
      bestDistance = d;
    }
  }
  return best;
}

/// The picture frame after dragging [corner] to [p]: the opposite corner
/// stays put and the aspect ratio of [start] is kept.
InkRect resizedImageFrame(InkRect start, ImageCorner corner, Vec2 p) {
  final anchor = imageCornerPoint(start, _opposite(corner));
  final aspect = start.width / start.height;
  final signX = corner == ImageCorner.topLeft || corner == ImageCorner.bottomLeft
      ? -1.0
      : 1.0;
  final signY = corner == ImageCorner.topLeft || corner == ImageCorner.topRight
      ? -1.0
      : 1.0;
  // Distance dragged past the anchor along each axis, never negative.
  final dx = math.max(0.0, (p.x - anchor.x) * signX);
  final dy = math.max(0.0, (p.y - anchor.y) * signY);
  // Follow the axis the pen moved further from the start (relative to the
  // start size), so shrinking along one axis shrinks the picture too.
  final sx = dx / start.width;
  final sy = dy / start.height;
  var w = ((sx - 1).abs() >= (sy - 1).abs() ? sx : sy) * start.width;
  w = math.max(w, math.max(minImageSide, minImageSide * aspect));
  final h = w / aspect;
  final x = signX > 0 ? anchor.x : anchor.x - w;
  final y = signY > 0 ? anchor.y : anchor.y - h;
  return InkRect.fromLTWH(x, y, w, h);
}

/// Where a new picture goes: centred on the page, [widthFraction] of the
/// page width wide, aspect kept, and never taller than [maxHeightFraction]
/// of the page.
InkRect fitImageOnPage({
  required double pageWidth,
  required double pageHeight,
  required int pixelWidth,
  required int pixelHeight,
  double widthFraction = 0.6,
  double maxHeightFraction = 0.85,
}) {
  final aspect = pixelWidth > 0 && pixelHeight > 0
      ? pixelWidth / pixelHeight
      : 1.0;
  var w = pageWidth * widthFraction;
  var h = w / aspect;
  final maxH = pageHeight * maxHeightFraction;
  if (h > maxH) {
    h = maxH;
    w = h * aspect;
  }
  return InkRect.fromLTWH((pageWidth - w) / 2, (pageHeight - h) / 2, w, h);
}
