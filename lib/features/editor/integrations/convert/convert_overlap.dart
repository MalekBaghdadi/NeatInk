import 'dart:ui' show Rect;

import '../../../../document/page_items.dart';
import 'convert_layout.dart';

// Keeping converted text from covering other text: a new box that would sit
// on another one moves down to the next free line, the way a writer would
// carry on below (v1.6.0; text appended by auto-convert used to wrap over
// the line written below it).

Rect _rectOf(TextItem t) => Rect.fromLTWH(t.x, t.y, t.width, t.height);

/// Whether [item] covers any of [others] (boxes with [item]'s id are
/// skipped). Touching edges do not count.
bool overlapsAny(TextItem item, Iterable<TextItem> others) {
  final r = _rectOf(item).deflate(0.5);
  for (final o in others) {
    if (o.id == item.id) continue;
    if (r.overlaps(_rectOf(o).deflate(0.5))) return true;
  }
  return false;
}

/// [item], moved down line by line (to the next ruled line on ruled paper)
/// until it covers none of [others]. It stays where it is when it is clear
/// already, or when no free place is found before the bottom of the page
/// ([pageHeight]).
TextItem placeClear(
  TextItem item,
  Iterable<TextItem> others, {
  required double pageHeight,
  required ConvertTextMetrics metrics,
  PageRuling? ruling,
  int maxSteps = 80,
}) {
  final obstacles = others.toList();
  if (!overlapsAny(item, obstacles)) return item;
  final ascent = metrics.firstBaseline(item);
  final step = item.lineSpacing ??
      metrics.heightOf(item.copyWith(text: 'x', width: 1e6));
  if (!(step > 0)) return item;
  var baseline = item.y + ascent;
  for (var i = 0; i < maxSteps; i++) {
    double? next;
    for (final r in ruling?.baselines ?? const <double>[]) {
      if (r > baseline + 0.5) {
        next = r;
        break;
      }
    }
    baseline = next ?? baseline + step;
    final moved = item.copyWith(y: baseline - ascent);
    if (moved.y + moved.height > pageHeight) return item;
    if (!overlapsAny(moved, obstacles)) return moved;
  }
  return item;
}
