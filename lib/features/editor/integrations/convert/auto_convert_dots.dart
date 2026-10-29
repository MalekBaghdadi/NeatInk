import 'dart:math' as math;

import '../../../../document/page_items.dart';
import '../../../../ink/stroke.dart';
import 'auto_convert_merge.dart';
import 'convert_layout.dart';

// Late dots: the dot of an i, the bar of a t or a full stop, written a moment
// after auto-convert had already typed the word. On their own they say
// nothing to the recogniser, so they used to stay on the page as a stray
// mark next to the typed text (v1.6.0: Mariam's "one (i) wasn't converted",
// the dot after "skyler" on the owner's page).

/// Whether every stroke of [strokes] is a dot or a short bar, not a letter:
/// at most [reference] x 0.35 across, or a flat bar at most 0.8 [reference]
/// wide (a t-cross). [reference] is the ruling (or 26 points without one).
/// Upright strokes (an `i` or `l` without its dot) are letters.
bool onlyDots(Iterable<Stroke> strokes, {required double reference}) {
  var any = false;
  for (final s in strokes) {
    any = true;
    final b = s.bounds;
    final w = b.right - b.left, h = b.bottom - b.top;
    final small = math.sqrt(w * w + h * h) <= 0.35 * reference;
    final bar = w >= 2.5 * h && h <= 0.2 * reference && w <= 0.8 * reference;
    if (!small && !bar) return false;
  }
  return any;
}

/// Where late dots belong: the text box [box] whose writing they finish,
/// and the punctuation [mark] they add to its text (`.`, `,`, `:`, `;`), or null
/// when they are an i-dot, a t-bar or a stray mark that just goes.
typedef LateDots = ({TextItem box, String? mark});

/// The typed box [strokes] (all dots, see [onlyDots]) were written on, or
/// null when they are not on any. A box's area is its typed text and, when
/// auto-convert remembers it ([memory]), the handwriting it replaced. A
/// single dot at the end of that writing, on its baseline, is a full stop
/// (one that reaches below the baseline a comma), unless the text already
/// ends with punctuation.
LateDots? lateDotsTarget({
  required List<Stroke> strokes,
  required Iterable<TextItem> boxes,
  required AutoBoxVersion? Function(TextItem box) memory,
  required ConvertTextMetrics metrics,
}) {
  if (strokes.isEmpty) return null;
  var left = double.infinity, top = double.infinity;
  var right = double.negativeInfinity, bottom = double.negativeInfinity;
  for (final s in strokes) {
    left = math.min(left, s.bounds.left);
    top = math.min(top, s.bounds.top);
    right = math.max(right, s.bounds.right);
    bottom = math.max(bottom, s.bounds.bottom);
  }
  final cx = (left + right) / 2, cy = (top + bottom) / 2;

  TextItem? best;
  AutoBoxVersion? bestMemory;
  var bestDistance = double.infinity;
  for (final box in boxes) {
    if (box.text.trim().isEmpty) continue;
    final mem = memory(box);
    final u = box.fontSize;
    final inkXh = mem?.inkXHeight ?? 0.5 * u;
    final typedEnd = box.x + math.min(metrics.naturalWidth(box), box.width);
    var zl = box.x - 0.5 * u, zt = box.y - 0.6 * u;
    var zr = math.max(box.x + box.width, typedEnd) + u;
    var zb = box.y + box.height + 0.3 * u;
    if (mem != null) {
      zr = math.max(zr, mem.inkRight + 1.5 * inkXh);
      zt = math.min(zt, mem.inkBaseline - 3 * inkXh);
      zb = math.max(zb, mem.inkBaseline + inkXh);
    }
    if (cx < zl || cx > zr || cy < zt || cy > zb) continue;
    // Nearest typed text wins.
    final dx = cx < box.x ? box.x - cx : (cx > typedEnd ? cx - typedEnd : 0.0);
    final dy = cy < box.y ? box.y - cy : (cy > box.y + box.height ? cy - box.y - box.height : 0.0);
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance < bestDistance) {
      best = box;
      bestMemory = mem;
      bestDistance = distance;
    }
  }
  final box = best;
  if (box == null) return null;
  final mark = switch (strokes.length) {
    1 => _markOf(strokes.single, box, bestMemory, metrics),
    2 => _colonOf(strokes, box, bestMemory, metrics),
    _ => null,
  };
  return (box: box, mark: mark);
}

/// `:` or `;` for two marks [strokes] one above the other at the end of
/// [box]'s writing: a dot floating at the x-height over a full stop or a
/// comma (v1.9.0; before, only `.` and `,` were added late). Null otherwise.
String? _colonOf(List<Stroke> strokes, TextItem box, AutoBoxVersion? mem, ConvertTextMetrics metrics) {
  final sorted = [...strokes]..sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
  final upper = sorted.first.bounds, lowerStroke = sorted.last;
  final lower = lowerStroke.bounds;
  final xh = mem?.inkXHeight ?? 0.5 * box.fontSize;
  final aligned = ((upper.left + upper.right) / 2 - (lower.left + lower.right) / 2).abs() <= 0.6 * xh;
  final small = upper.right - upper.left <= 0.7 * xh && upper.bottom - upper.top <= 0.7 * xh;
  final above = lower.top - upper.bottom >= 0.1 * xh && lower.top - upper.bottom <= 1.5 * xh;
  if (!aligned || !small || !above) return null;
  return switch (_markOf(lowerStroke, box, mem, metrics)) {
    '.' => ':',
    ',' => ';',
    _ => null,
  };
}

/// `.` or `,` for a single dot [s] at the end of [box]'s writing, on its
/// baseline; null otherwise.
String? _markOf(Stroke s, TextItem box, AutoBoxVersion? mem, ConvertTextMetrics metrics) {
  if (RegExp(r'[.,;:!?…]["\x27”’)\]]*$').hasMatch(box.text.trimRight())) return null;
  final xh = mem?.inkXHeight ?? 0.5 * box.fontSize;
  final double baseline;
  final double end;
  if (mem != null) {
    baseline = mem.inkBaseline;
    end = mem.inkRight;
  } else {
    final one = metrics.heightOf(box.copyWith(text: 'x', width: 1e6));
    final lines = one > 0 ? (box.height / one).round().clamp(1, 1000) : 1;
    baseline = box.y + metrics.firstBaseline(box) + (lines - 1) * one;
    end = box.x + math.min(metrics.naturalWidth(box), box.width);
  }
  final b = s.bounds;
  final w = b.right - b.left, h = b.bottom - b.top;
  if ((b.left + b.right) / 2 < end - 0.5 * xh) return null; // not at the end
  final cy = (b.top + b.bottom) / 2;
  // A full stop sits on the line or a little below it (small writing puts
  // it most of an x-height below: Mariam's 1.6 test); higher up it is the
  // dot of an i. v1.8.0: the band was +-0.5 x-heights.
  // A thin upright mark is a comma even when it is short.
  final upright = h >= 2.5 * math.max(w, 0.5) && h >= 0.45 * xh;
  final small = w <= 0.7 * xh && h <= 0.7 * xh && !upright;
  if (small && cy >= baseline - 0.8 * xh && cy <= baseline + 1.1 * xh) return '.';
  // A comma: taller than a dot, hanging below the line.
  if (!small && w <= 0.8 * xh && h <= 1.6 * xh && b.top >= baseline - 0.8 * xh && b.bottom > baseline + 0.3 * xh) {
    return ',';
  }
  return null;
}
