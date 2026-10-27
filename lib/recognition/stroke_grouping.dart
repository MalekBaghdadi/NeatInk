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
    this.wordGapRatio = 2.5,
    this.wordGapMaxFactor = 1.4,
    this.minLetterGaps = 3,
    this.wordGapJumpRatio = 2.5,
    this.fragmentWidthFactor = 1.2,
    this.fragmentMergeFactor = 1.5,
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

  /// The least gap that separates two words (the split threshold never goes
  /// below it).
  final double wordGapFactor;

  /// A dot or bar further than this from every word stays on its own.
  final double tinyAttachFactor;

  /// Adaptive word gap: a gap splits two words only when it is also at least
  /// this many times the line's typical letter gap (the median of its gaps
  /// below [wordGapFactor]). Handwriting is uneven; a letter gap that
  /// happens to be 0.8 x-heights wide inside one word must not split it.
  final double wordGapRatio;

  /// The split threshold is at most this many x-heights, so a line written
  /// with wide letter spacing still splits at its real word gaps.
  final double wordGapMaxFactor;

  /// The ratio rule needs this many letter gaps in the line to estimate the
  /// typical one; fewer and the plain [wordGapFactor] applies.
  final int minLetterGaps;

  /// A line written with wide letter spacing has no letter gap below
  /// [wordGapFactor]; then the word gaps are told by a jump: the first gap
  /// at least this many times larger than the one before it (in the sorted
  /// gaps of a line of five or more).
  final double wordGapJumpRatio;

  /// A "word" that is a single letter block (one letter, however many
  /// strokes) narrower than this many x-heights is a fragment of a
  /// neighbouring word (the last letter of "notebook" written a little away
  /// from the rest), unless it looks like a digit, bar or full stop.
  final double fragmentWidthFactor;

  /// A fragment is merged into its nearer neighbour when that neighbour is
  /// within this many split thresholds.
  final double fragmentMergeFactor;
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
///    blocks, then join blocks closer than the line's word-gap threshold
///    (adaptive: see [GroupingConfig.wordGapRatio]); dots and bars attach to
///    the nearest word, and a lone narrow letter written a little apart from
///    its word is merged back into it ([GroupingConfig.fragmentWidthFactor]).
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

/// Strokes of one word while the line is being split.
class _Acc {
  _Acc(this.items, this.blocks);

  final List<_Item> items;

  /// Letter blocks (clusters of overlapping strokes) merged into this word.
  int blocks;

  /// Made only of dots and bars that found no word to attach to.
  bool dotOnly = false;

  double get xl => items.map((i) => i.xl).reduce(math.min);
  double get xr => items.map((i) => i.xr).reduce(math.max);
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

  final words = <_Acc>[];
  for (var i = 0; i < blocks.length; i++) {
    if (i > 0 && gaps[i - 1] <= limit) {
      words.last
        ..items.addAll(blocks[i])
        ..blocks += 1;
    } else {
      words.add(_Acc([...blocks[i]], 1));
    }
  }

  // Dots and bars join the nearest word, if it is close enough.
  final loners = <_Item>[];
  for (final d in dots) {
    var bestDist = double.infinity;
    var bestWord = -1;
    for (var i = 0; i < words.length; i++) {
      final dist = math.max(0.0, math.max(words[i].xl - d.xr, d.xl - words[i].xr));
      if (dist < bestDist) {
        bestDist = dist;
        bestWord = i;
      }
    }
    if (bestWord >= 0 && bestDist <= config.tinyAttachFactor * u) {
      words[bestWord].items.add(d);
    } else {
      loners.add(d);
    }
  }
  for (final group in clusters(loners, limit)) {
    words.add(_Acc(group, 1)..dotOnly = true);
  }

  words.sort((a, b) => a.xl.compareTo(b.xl));
  _mergeFragments(words, u, limit, config);

  return [
    for (final acc in words)
      () {
        final w = acc.items..sort((a, b) => a.xl.compareTo(b.xl));
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

/// Threshold above which two letter blocks belong to different words: the
/// larger of the default fraction of the x-height and a multiple of the
/// line's typical letter gap (the median of its gaps below the default), at
/// most [GroupingConfig.wordGapMaxFactor] x-heights. A gap that is
/// large only in absolute terms (one wide letter space in an unevenly
/// spaced word) therefore does not split a word, while single letters
/// written with clear spaces between them stay separate.
double _wordGapLimit(List<double> gaps, double u, GroupingConfig config) {
  final floor = config.wordGapFactor * u;
  final letterGaps = [
    for (final g in gaps)
      if (g <= floor) math.max(g, 0.0),
  ];
  if (letterGaps.length < config.minLetterGaps) {
    return _jumpLimit(gaps, u, floor, config) ?? floor;
  }
  final typical = median(letterGaps) ?? 0;
  final adaptive = config.wordGapRatio * typical;
  return math.min(math.max(floor, adaptive), math.max(floor, config.wordGapMaxFactor * u));
}

/// The word-gap threshold of a line whose letter gaps are all wide: halfway
/// (geometrically) across the largest jump in its sorted gaps, or null when
/// the gaps show no jump.
double? _jumpLimit(List<double> gaps, double u, double floor, GroupingConfig config) {
  if (gaps.length < 5) return null;
  final sorted = [...gaps.map((g) => math.max(g, 0.0))]..sort();
  var bestRatio = 0.0;
  double? limit;
  for (var i = 3; i < sorted.length; i++) {
    final lower = math.max(sorted[i - 1], 0.15 * u);
    final ratio = sorted[i] / lower;
    if (ratio >= config.wordGapJumpRatio && ratio > bestRatio && sorted[i] >= floor) {
      bestRatio = ratio;
      limit = math.sqrt(lower * sorted[i]);
    }
  }
  if (limit == null) return null;
  return math.min(math.max(floor, limit), math.max(floor, config.wordGapMaxFactor * u));
}

/// Merges fragments into their nearer neighbour (see
/// [GroupingConfig.fragmentWidthFactor]). Fragments never merge into each
/// other, so single letters written apart ("a b c") stay separate.
void _mergeFragments(List<_Acc> words, double u, double limit, GroupingConfig config) {
  bool isFragment(_Acc w) {
    if (w.dotOnly || w.blocks != 1) return false;
    if (w.xr - w.xl >= config.fragmentWidthFactor * u) return false;
    if (w.items.length == 1 && (_isBarLike(w.items.first) || _isLoopLike(w.items.first, u))) {
      return false; // 1, I, l, -, 0, o ...
    }
    return true;
  }

  var i = 0;
  while (i < words.length) {
    final w = words[i];
    if (!isFragment(w)) {
      i++;
      continue;
    }
    _Acc? left = i > 0 ? words[i - 1] : null;
    _Acc? right = i + 1 < words.length ? words[i + 1] : null;
    if (left != null && (left.dotOnly || isFragment(left))) left = null;
    if (right != null && (right.dotOnly || isFragment(right))) right = null;
    final gapLeft = left == null ? double.infinity : math.max(0.0, w.xl - left.xr);
    final gapRight = right == null ? double.infinity : math.max(0.0, right.xl - w.xr);
    final reach = config.fragmentMergeFactor * limit;
    final target = gapLeft <= gapRight ? left : right;
    final gap = math.min(gapLeft, gapRight);
    if (target == null || gap > reach) {
      i++;
      continue;
    }
    target
      ..items.addAll(w.items)
      ..blocks += 1;
    words.removeAt(i);
    if (target == right) words.sort((a, b) => a.xl.compareTo(b.xl));
  }
}

/// A single stroke that is nearly straight (a 1, an I, a dash).
bool _isBarLike(_Item it) {
  final s = it.samples;
  if (s.length < 2) return true;
  var length = 0.0;
  for (var i = 1; i < s.length; i++) {
    length += s[i].distanceTo(s[i - 1]);
  }
  final chord = s.first.distanceTo(s.last);
  return chord > 0 && length <= 1.25 * chord;
}

/// A single stroke that returns to where it began (a 0, an o).
bool _isLoopLike(_Item it, double u) {
  final s = it.samples;
  if (s.length < 3) return false;
  final diag = it.bounds.diagonal;
  return diag >= 0.5 * u && s.first.distanceTo(s.last) <= 0.4 * diag;
}
