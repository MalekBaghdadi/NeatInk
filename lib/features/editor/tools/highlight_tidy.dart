import 'dart:math' as math;

import '../../../ink/ink_point.dart';
import '../../../ink/stroke.dart';
import '../../../recognition/stroke_grouping.dart';

/// Tuning numbers of [tidyHighlight] in one place. Lengths in page points
/// unless they say otherwise.
class HighlightTidyConfig {
  const HighlightTidyConfig({
    this.maxAngleDeg = 20,
    this.minLength = 6,
    this.maxWobble = 0.75,
    this.maxOffset = 0.75,
    this.coverFraction = 0.35,
    this.pad = 0.12,
    this.pointStep = 2,
    this.inkBandAbove = 1.6,
    this.inkBandBelow = 0.35,
    this.inkWordGap = 0.5,
    this.inkSearchRows = 3,
  });

  /// A highlight is a swipe: its fitted line is at most this many degrees
  /// from horizontal.
  final double maxAngleDeg;

  /// ... at least this long ...
  final double minLength;

  /// ... and its points stay within this many of its widths of the fitted
  /// line (a scribble over two lines is not one band).
  final double maxWobble;

  /// The swipe belongs to a line of text when its middle is at most this many
  /// band heights (the larger of the line's band and the drawn width) from
  /// the middle of the line's band.
  final double maxOffset;

  /// A word counts as highlighted when the swipe covers at least this
  /// fraction of it (a swipe that ends a little into the next word does not
  /// take that word).
  final double coverFraction;

  /// The band runs this many of its heights past the first and last word.
  final double pad;

  /// Distance between the points of the tidied band.
  final double pointStep;

  /// Over handwriting, the band covers from this many x-heights above the
  /// baseline ...
  final double inkBandAbove;

  /// ... to this many below it (letters, most of the ascenders, a little of
  /// the descenders).
  final double inkBandBelow;

  /// Pieces of ink closer than this many x-heights are one word.
  final double inkWordGap;

  /// Only handwriting within this many band heights above and below the
  /// swipe is grouped into lines (the rest of the page cannot be under it).
  final double inkSearchRows;
}

/// A line of text a highlight may be laid over, in page points: handwriting,
/// a line of a typed text box, or a line of a PDF page's text.
class HighlightLine {
  const HighlightLine({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
    required this.words,
    this.slope = 0,
  });

  /// Horizontal extent of the line.
  final double left;
  final double right;

  /// The band a highlight should cover, at x = [left]; it follows [slope]
  /// (dy/dx) along the line.
  final double top;
  final double bottom;
  final double slope;

  /// Horizontal extents of the words on the line, left to right.
  final List<({double left, double right})> words;

  double get thickness => bottom - top;

  /// Middle of the band at [x].
  double centerAt(double x) => (top + bottom) / 2 + slope * (x - left);
}

/// The lines of handwriting near [highlight] that a highlight could cover:
/// the pen strokes of [strokes] within [HighlightTidyConfig.inkSearchRows]
/// rows of it, grouped into lines like the recogniser does.
List<HighlightLine> inkHighlightLines(
  Stroke highlight,
  List<Stroke> strokes, {
  HighlightTidyConfig config = const HighlightTidyConfig(),
}) {
  final hb = highlight.bounds;
  final reach = config.inkSearchRows * math.max(highlight.size, hb.height);
  final near = [
    for (final s in strokes)
      if (s.tool == StrokeTool.pen &&
          s.shape == null &&
          s.points.isNotEmpty &&
          s.bounds.bottom >= hb.top - reach &&
          s.bounds.top <= hb.bottom + reach)
        s,
  ];
  if (near.isEmpty) return const [];
  final out = <HighlightLine>[];
  for (final line in groupStrokes(near)) {
    final xh = line.xHeight;
    if (!xh.isFinite || xh <= 0 || line.inkStrokes.isEmpty) continue;
    final extents = [
      for (final s in line.inkStrokes) (left: s.bounds.left, right: s.bounds.right),
    ]..sort((a, b) => a.left.compareTo(b.left));
    final words = <({double left, double right})>[];
    for (final e in extents) {
      if (words.isNotEmpty && e.left - words.last.right < config.inkWordGap * xh) {
        if (e.right > words.last.right) words[words.length - 1] = (left: words.last.left, right: e.right);
      } else {
        words.add(e);
      }
    }
    final baseline = line.baselineAt(line.left);
    out.add(HighlightLine(
      left: line.left,
      right: line.right,
      top: baseline - config.inkBandAbove * xh,
      bottom: baseline + config.inkBandBelow * xh,
      slope: line.baselineSlope,
      words: words,
    ));
  }
  return out;
}

/// Tidies a highlighter [stroke] (see the "Tidy highlighter" setting).
///
/// A swipe over a line of [lines] becomes a straight band laid over that
/// line: as high as the line's band, along its slope, from the first to the
/// last word the swipe covers. A swipe over no text is only straightened
/// (along its own fitted line, as wide as it was drawn). Anything else (not
/// a highlighter stroke, a snapped shape, a scribble, a stroke more upright
/// than flat) gives null: leave it as drawn.
///
/// The result keeps [Stroke.raw] and records the drawn width in
/// [Stroke.rawSize], so "Restore original" gives the hand-drawn highlight
/// back.
Stroke? tidyHighlight(
  Stroke stroke,
  List<HighlightLine> lines, {
  HighlightTidyConfig config = const HighlightTidyConfig(),
}) {
  if (stroke.tool != StrokeTool.highlighter || stroke.shape != null) return null;
  final pts = stroke.raw;
  if (pts.length < 2) return null;

  // Least-squares line through the drawn points: y = a + b x.
  var minX = double.infinity, maxX = double.negativeInfinity;
  var sx = 0.0, sy = 0.0;
  for (final p in pts) {
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    sx += p.x;
    sy += p.y;
  }
  final n = pts.length;
  final mx = sx / n, my = sy / n;
  var sxx = 0.0, sxy = 0.0;
  for (final p in pts) {
    sxx += (p.x - mx) * (p.x - mx);
    sxy += (p.x - mx) * (p.y - my);
  }
  if (maxX - minX < config.minLength || sxx <= 0) return null;
  final b = sxy / sxx;
  if (math.atan(b.abs()) * 180 / math.pi > config.maxAngleDeg) return null;
  final a = my - b * mx;
  var wobble = 0.0;
  for (final p in pts) {
    wobble = math.max(wobble, (p.y - (a + b * p.x)).abs());
  }
  if (wobble > config.maxWobble * math.max(stroke.size, 1)) return null;

  // The line under the middle of the swipe, nearest first.
  final midX = (minX + maxX) / 2;
  HighlightLine? best;
  var bestD = double.infinity;
  for (final l in lines) {
    if (l.words.isEmpty || l.right < minX || l.left > maxX || l.thickness <= 0) continue;
    final x = midX.clamp(l.left, l.right).toDouble();
    final d = ((a + b * x) - l.centerAt(x)).abs();
    if (d > config.maxOffset * math.max(l.thickness, stroke.size)) continue;
    if (d < bestD) {
      bestD = d;
      best = l;
    }
  }

  double from, to, size;
  double Function(double x) yAt;
  final line = best;
  final covered = line == null ? const <({double left, double right})>[] : _covered(line, minX, maxX, config);
  if (line != null && covered.isNotEmpty) {
    size = line.thickness;
    final pad = config.pad * size;
    from = covered.first.left - pad;
    to = covered.last.right + pad;
    yAt = line.centerAt;
  } else {
    // No text under it: only straighten.
    size = stroke.size;
    from = minX;
    to = maxX;
    yAt = (x) => a + b * x;
  }
  if (!(to > from)) return null;
  // Keep the time span of the drawing, spread along the band.
  final t0 = pts.first.t, t1 = pts.last.t;
  final count = math.max(2, ((to - from) / config.pointStep).ceil() + 1);
  final band = [
    for (var i = 0; i < count; i++)
      () {
        final f = i / (count - 1);
        final x = from + (to - from) * f;
        return InkPoint.quantized(x, yAt(x), 0.5, (t0 + (t1 - t0) * f).round());
      }(),
  ];
  return stroke.copyWith(points: band, size: size, rawSize: stroke.rawSize ?? stroke.size);
}

/// The words of [line] the swipe from [minX] to [maxX] covers enough of; all
/// it touches when it covers none enough (a swipe inside one long word).
List<({double left, double right})> _covered(
  HighlightLine line,
  double minX,
  double maxX,
  HighlightTidyConfig config,
) {
  double overlap(({double left, double right}) w) => math.min(w.right, maxX) - math.max(w.left, minX);
  final enough = [
    for (final w in line.words)
      if (overlap(w) >= config.coverFraction * (w.right - w.left)) w,
  ];
  if (enough.isNotEmpty) return enough;
  return [
    for (final w in line.words)
      if (overlap(w) > 0) w,
  ];
}
