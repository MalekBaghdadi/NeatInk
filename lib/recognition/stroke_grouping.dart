import 'dart:math' as math;

import '../beautify/features.dart';
import '../beautify/resample.dart';
import '../beautify/stats.dart';
import '../ink/ink_rect.dart';
import '../ink/stroke.dart';
import '../ink/vec2.dart';

/// Tuning numbers for [groupStrokes]. Lengths are fractions of the writing's
/// x-height, so they scale with the handwriting.
class GroupingConfig {
  const GroupingConfig({
    this.maxSkewDeg = 20,
    this.minLineHeightFactor = 2.0,
    this.lineValleyRatio = 0.3,
    this.tinyFactor = 0.45,
    this.overlapTolFactor = 0.08,
    this.wordGapFactor = 0.6,
    this.tinyAttachFactor = 0.35,
  });

  /// Page lines are searched within ±this many degrees of horizontal.
  final double maxSkewDeg;

  /// Two lines are never closer than this (baseline to baseline would need
  /// to be larger still); a cut between lines leaves at least this much ink
  /// height on each side.
  final double minLineHeightFactor;

  /// A cut is made where the ink density between two lines drops below this
  /// fraction of the sparser line's peak density.
  final double lineValleyRatio;

  /// Strokes whose box diagonal is below this are dots and bars (i-dots,
  /// t-bars, full stops) that attach to a neighbouring word.
  final double tinyFactor;

  /// Letters closer than this (or overlapping) are the same letter block.
  final double overlapTolFactor;

  /// Default gap that separates two words. A clear gap pattern in the line
  /// (small letter gaps, large word gaps) overrides it.
  final double wordGapFactor;

  /// A dot or bar further than this from every word stays on its own.
  final double tinyAttachFactor;
}

/// The strokes of one written word, ready to be rendered and recognised.
class WordGroup {
  WordGroup({
    required this.strokes,
    required this.bounds,
    this.baselineSlope = 0,
    this.xHeight,
  });

  /// Pen strokes in left-to-right order of their start along the line.
  final List<Stroke> strokes;

  /// Page-frame bounds of the ink points.
  final InkRect bounds;

  /// Slope (dy/dx, y down) of the baseline of the line the word sits on.
  final double baselineSlope;

  /// x-height of the line in points, when it could be estimated.
  final double? xHeight;
}

/// One line of handwriting: words in reading order on a (possibly slanted)
/// baseline `y = baselineY + baselineSlope * (x - left)`.
class RecognizedLine {
  RecognizedLine({
    required this.words,
    required this.baselineY,
    required this.baselineSlope,
    required this.left,
    required this.right,
    required this.xHeight,
  });

  final List<WordGroup> words;

  /// Baseline height at x = [left] (page frame, y down).
  final double baselineY;
  final double baselineSlope;
  final double left;
  final double right;
  final double xHeight;

  double baselineAt(double x) => baselineY + baselineSlope * (x - left);

  Iterable<Stroke> get strokes => words.expand((w) => w.strokes);
}

/// Splits pen strokes into lines and words.
///
/// 1. Estimate the writing size `u` (x-height) from the stroke heights, or
///    take [expectedXHeight].
/// 2. Find the dominant page slope: the angle at which the ink's vertical
///    profile is peakiest (ruled lines pile up into sharp peaks).
/// 3. In the levelled frame, cut the vertical ink profile at its valleys:
///    each region between cuts is one line.
/// 4. Fit every line's own baseline with [analyzeWord].
/// 5. Along each line, merge strokes that overlap horizontally into letter
///    blocks, then join blocks closer than a word gap; dots and bars attach
///    to the nearest word.
///
/// Highlighter strokes and shapes are ignored. Lines come top to bottom,
/// words left to right.
List<RecognizedLine> groupStrokes(
  List<Stroke> strokes, {
  double? expectedXHeight,
  GroupingConfig config = const GroupingConfig(),
}) {
  final items = <_Item>[];
  for (final s in strokes) {
    if (s.tool != StrokeTool.pen || s.shape != null) continue;
    final b = finiteBounds(s.points);
    if (b == null) continue;
    items.add(_Item(s, b));
  }
  if (items.isEmpty) return const [];

  final u = _estimateUnit(items, expectedXHeight);
  final step = math.max(u / 6, 0.4);
  for (final it in items) {
    it.samples = resampleInkPoints(it.stroke.points, step);
  }

  final angle = _estimatePageAngle(items, u, config);
  final lines = _splitLines(items, angle, u, config);

  final out = <RecognizedLine>[];
  for (final lineItems in lines) {
    out.add(_buildLine(lineItems, angle, u, expectedXHeight, config));
  }
  return out;
}

class _Item {
  _Item(this.stroke, this.bounds);

  final Stroke stroke;
  final InkRect bounds;
  List<Vec2> samples = const [];

  /// Mean sample position in the levelled page frame (set by line search).
  double meanLevelY = 0;

  // Horizontal extent along the line (set per line).
  double xl = 0, xr = 0;
}

/// Rotation by −[angle]: x runs along a line of slope tan(angle), y is the
/// distance across it, so the line `y = tan(a)·x + b` becomes y' = b·cos(a).
double _levelX(Vec2 p, double c, double s) => p.x * c + p.y * s;
double _levelY(Vec2 p, double c, double s) => p.y * c - p.x * s;

double _estimateUnit(List<_Item> items, double? hint) {
  if (hint != null && hint > 0) return hint;
  final heights = [for (final it in items) it.bounds.height];
  final med = median(heights) ?? 0;
  final usable = [
    for (final h in heights)
      if (h >= 0.3 * med && h > 0) h,
  ];
  // Capitals and ascenders are taller than the x-height, and about half of
  // English letters are x-height only, so a low quantile finds the x-height.
  final low = lowerQuantile(usable, 0.3);
  if (low != null && low > 0) return low;
  final widths = [for (final it in items) it.bounds.width];
  final w = median(widths) ?? 0;
  return w > 0 ? w : 8.0;
}

double _estimatePageAngle(List<_Item> items, double u, GroupingConfig config) {
  final bin = math.max(0.35 * u, 0.3);
  double score(double a) {
    final c = math.cos(a), s = math.sin(a);
    final counts = <int, int>{};
    for (final it in items) {
      for (final p in it.samples) {
        final k = (_levelY(p, c, s) / bin).floor();
        counts[k] = (counts[k] ?? 0) + 1;
      }
    }
    var sum = 0.0;
    for (final n in counts.values) {
      sum += n * n;
    }
    // Prefer level lines when the evidence is a tie.
    return sum * (1 - 0.003 * radToDeg(a).abs());
  }

  var best = 0.0;
  var bestScore = score(0);
  for (var d = -config.maxSkewDeg; d <= config.maxSkewDeg; d += 1) {
    if (d == 0) continue;
    final sc = score(degToRad(d));
    if (sc > bestScore) {
      bestScore = sc;
      best = degToRad(d);
    }
  }
  final centre = best;
  for (var d = -0.75; d <= 0.75; d += 0.25) {
    if (d == 0) continue;
    final a = centre + degToRad(d);
    final sc = score(a);
    if (sc > bestScore) {
      bestScore = sc;
      best = a;
    }
  }
  return best;
}

List<List<_Item>> _splitLines(List<_Item> items, double angle, double u, GroupingConfig config) {
  final c = math.cos(angle), s = math.sin(angle);
  var lo = double.infinity, hi = double.negativeInfinity;
  for (final it in items) {
    var sum = 0.0;
    for (final p in it.samples) {
      final y = _levelY(p, c, s);
      sum += y;
      if (y < lo) lo = y;
      if (y > hi) hi = y;
    }
    it.meanLevelY = it.samples.isEmpty ? 0 : sum / it.samples.length;
  }

  final bh = math.max(u / 6, 0.25);
  final nb = ((hi - lo) / bh).floor() + 1;
  final hist = List<double>.filled(nb, 0);
  for (final it in items) {
    for (final p in it.samples) {
      hist[((_levelY(p, c, s) - lo) / bh).floor().clamp(0, nb - 1)] += 1;
    }
  }
  const kernel = [1.0, 2.0, 3.0, 2.0, 1.0];
  final sm = List<double>.filled(nb, 0);
  for (var i = 0; i < nb; i++) {
    var acc = 0.0;
    for (var k = -2; k <= 2; k++) {
      final j = i + k;
      if (j >= 0 && j < nb) acc += hist[j] * kernel[k + 2];
    }
    sm[i] = acc / 9;
  }

  final minBins = (config.minLineHeightFactor * u / bh).ceil();
  final cutBins = <int>[];
  final pending = <(int, int)>[(0, nb)];
  while (pending.isNotEmpty) {
    final (a, b) = pending.removeLast();
    final from = a + minBins, to = b - minBins;
    if (to < from) continue;
    var minV = double.infinity;
    var at = from;
    for (var i = from; i <= to; i++) {
      if (sm[i] < minV) {
        minV = sm[i];
        at = i;
      }
    }
    // Centre of the flat valley floor around the first minimum.
    var l = at, r = at;
    while (l - 1 >= from && sm[l - 1] <= minV + 1e-9) {
      l--;
    }
    while (r + 1 <= to && sm[r + 1] <= minV + 1e-9) {
      r++;
    }
    final cut = (l + r) ~/ 2;
    var leftMax = 0.0, rightMax = 0.0;
    for (var i = a; i < cut; i++) {
      leftMax = math.max(leftMax, sm[i]);
    }
    for (var i = cut + 1; i < b; i++) {
      rightMax = math.max(rightMax, sm[i]);
    }
    if (minV <= config.lineValleyRatio * math.min(leftMax, rightMax)) {
      cutBins.add(cut);
      pending.add((a, cut));
      pending.add((cut + 1, b));
    }
  }
  cutBins.sort();
  final cutYs = [for (final k in cutBins) lo + (k + 0.5) * bh];

  final groups = List.generate(cutYs.length + 1, (_) => <_Item>[]);
  for (final it in items) {
    var idx = 0;
    while (idx < cutYs.length && it.meanLevelY > cutYs[idx]) {
      idx++;
    }
    groups[idx].add(it);
  }
  return [
    for (final g in groups)
      if (g.isNotEmpty) g,
  ];
}

RecognizedLine _buildLine(
  List<_Item> items,
  double pageAngle,
  double u,
  double? expectedXHeight,
  GroupingConfig config,
) {
  final strokes = [for (final it in items) it.stroke];
  final analysis = analyzeWord(
    strokes,
    context: FeatureContext(
      lineSkew: pageAngle,
      scaleHintPt: u,
      expectedXHeight: expectedXHeight,
    ),
    useRaw: false,
  );

  var slope = math.tan(pageAngle);
  double? xHeight;
  if (analysis != null) {
    final fitted = analysis.baseline.line.slope;
    if (fitted.isFinite && math.atan(fitted).abs() < degToRad(config.maxSkewDeg + 10)) {
      slope = fitted;
    }
    final xh = analysis.xHeight;
    if (xh.reliable && xh.xHeight >= 0.4 * u && xh.xHeight <= 2.5 * u) xHeight = xh.xHeight;
  }
  final lineU = expectedXHeight ?? xHeight ?? u;

  final phi = math.atan(slope);
  final c = math.cos(phi), s = math.sin(phi);
  for (final it in items) {
    var l = double.infinity, r = double.negativeInfinity;
    for (final p in it.samples) {
      final x = _levelX(p, c, s);
      if (x < l) l = x;
      if (x > r) r = x;
    }
    it.xl = l;
    it.xr = r;
  }

  final words = _splitWords(items, lineU, slope, config);
  var left = double.infinity, right = double.negativeInfinity;
  for (final w in words) {
    if (w.bounds.left < left) left = w.bounds.left;
    if (w.bounds.right > right) right = w.bounds.right;
  }

  // Baseline: the analysis' fit when it exists, else the bottom of the ink.
  final double baselineAtLeft;
  if (analysis != null && analysis.baseline.line.slope == slope) {
    baselineAtLeft = analysis.baseline.line.yAt(left);
  } else if (analysis != null) {
    final b = median([for (final p in analysis.baseline.extrema) p.y - slope * p.x]);
    baselineAtLeft = b != null ? slope * left + b : analysis.bounds.bottom;
  } else {
    baselineAtLeft = words.first.bounds.bottom;
  }

  return RecognizedLine(
    words: words,
    baselineY: baselineAtLeft,
    baselineSlope: slope,
    left: left,
    right: right,
    xHeight: lineU,
  );
}

List<WordGroup> _splitWords(
  List<_Item> items,
  double u,
  double slope,
  GroupingConfig config,
) {
  final normal = <_Item>[], tiny = <_Item>[];
  for (final it in items) {
    (it.bounds.diagonal < config.tinyFactor * u ? tiny : normal).add(it);
  }
  // A line of nothing but dots is still a line.
  final base = normal.isEmpty ? tiny.toList() : normal;
  final dots = normal.isEmpty ? <_Item>[] : tiny;

  List<List<_Item>> clusters(List<_Item> list, double gapLimit) {
    final sorted = [...list]..sort((a, b) => a.xl.compareTo(b.xl));
    final out = <List<_Item>>[];
    var curR = double.negativeInfinity;
    for (final it in sorted) {
      if (out.isNotEmpty && it.xl - curR <= gapLimit) {
        out.last.add(it);
        if (it.xr > curR) curR = it.xr;
      } else {
        out.add([it]);
        curR = it.xr;
      }
    }
    return out;
  }

  // Letter blocks: strokes that overlap (or nearly touch) horizontally.
  final blocks = clusters(base, config.overlapTolFactor * u);
  double blockRight(List<_Item> b) => b.map((i) => i.xr).reduce(math.max);
  final gaps = <double>[
    for (var i = 1; i < blocks.length; i++)
      blocks[i].map((it) => it.xl).reduce(math.min) - blockRight(blocks[i - 1]),
  ];
  final limit = _wordGapLimit(gaps, u, config);

  final words = <List<_Item>>[];
  for (var i = 0; i < blocks.length; i++) {
    if (i > 0 && gaps[i - 1] <= limit) {
      words.last.addAll(blocks[i]);
    } else {
      words.add([...blocks[i]]);
    }
  }

  // Dots and bars join the nearest word, if it is close enough.
  final loners = <_Item>[];
  for (final d in dots) {
    var bestDist = double.infinity;
    var bestWord = -1;
    for (var i = 0; i < words.length; i++) {
      final wl = words[i].map((it) => it.xl).reduce(math.min);
      final wr = words[i].map((it) => it.xr).reduce(math.max);
      final dist = math.max(0.0, math.max(wl - d.xr, d.xl - wr));
      if (dist < bestDist) {
        bestDist = dist;
        bestWord = i;
      }
    }
    if (bestWord >= 0 && bestDist <= config.tinyAttachFactor * u) {
      words[bestWord].add(d);
    } else {
      loners.add(d);
    }
  }
  for (final group in clusters(loners, limit)) {
    words.add(group);
  }

  final ordered = [...words]
    ..sort((a, b) => a.map((i) => i.xl).reduce(math.min).compareTo(b.map((i) => i.xl).reduce(math.min)));
  return [
    for (final w in ordered)
      () {
        w.sort((a, b) => a.xl.compareTo(b.xl));
        InkRect? bounds;
        for (final it in w) {
          bounds = bounds == null ? it.bounds : bounds.union(it.bounds);
        }
        return WordGroup(
          strokes: [for (final it in w) it.stroke],
          bounds: bounds!,
          baselineSlope: slope,
          xHeight: u,
        );
      }(),
  ];
}

/// Gap above which two letter blocks belong to different words. A line with
/// small letter gaps and clearly larger word gaps is cut between the two
/// groups; otherwise the default fraction of the x-height applies.
double _wordGapLimit(List<double> gaps, double u, GroupingConfig config) {
  final fallback = config.wordGapFactor * u;
  if (gaps.length < 4) return fallback;
  final sorted = [...gaps.map((g) => math.max(g, 0.0))]..sort();
  var bestJump = 0.0, mid = fallback;
  for (var i = 1; i < sorted.length; i++) {
    final jump = sorted[i] - sorted[i - 1];
    if (jump > bestJump && sorted[i - 1] <= 0.5 * u && sorted[i] >= 0.6 * u) {
      bestJump = jump;
      mid = (sorted[i] + sorted[i - 1]) / 2;
    }
  }
  if (bestJump < 0.25 * u) return fallback;
  return mid.clamp(0.45 * u, 1.0 * u);
}
