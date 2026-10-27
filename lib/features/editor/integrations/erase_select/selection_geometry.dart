import 'dart:math' as math;

import '../../../../ink/ink_rect.dart';
import '../../../../ink/vec2.dart';
import '../../tools/selection_transform.dart';

/// Gap between the selection's content and its frame, in screen pixels.
const double selectionPadPx = 5;

/// The frame is never smaller than this on screen, so the handles of a thin
/// selection (a single line) don't sit on top of each other.
const double selectionMinFramePx = 44;

/// How close (screen pixels) the pen must be to a handle to grab it.
const double handleGrabPx = 22;

/// The frame drawn around a selection with content [bounds], in page
/// points. [scale] is screen pixels per page point: the frame keeps a
/// constant on-screen padding and minimum size at every zoom.
InkRect selectionFrame(InkRect bounds, double scale) {
  final s = math.max(scale, 1e-6);
  final pad = selectionPadPx / s;
  final minSize = selectionMinFramePx / s;
  final w = math.max(bounds.width + 2 * pad, minSize);
  final h = math.max(bounds.height + 2 * pad, minSize);
  final c = bounds.center;
  return InkRect(c.x - w / 2, c.y - h / 2, c.x + w / 2, c.y + h / 2);
}

/// The resize handle of [frame] nearest to [p] within [handleGrabPx], or
/// null.
ResizeHandle? handleAt(InkRect frame, Vec2 p, double scale) {
  final reach = handleGrabPx / math.max(scale, 1e-6);
  ResizeHandle? best;
  var bestDistance = reach * reach;
  for (final h in ResizeHandle.values) {
    final d = h.positionOn(frame).distanceSquaredTo(p);
    if (d <= bestDistance) {
      best = h;
      bestDistance = d;
    }
  }
  return best;
}

/// Whether dragging from [p] moves the selection: [p] is inside its frame
/// (with a little slack).
bool insideFrame(InkRect frame, Vec2 p, double scale) =>
    frame.inflate(4 / math.max(scale, 1e-6)).contains(p);
