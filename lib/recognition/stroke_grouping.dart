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
    this.markReachX = 1.2,
    this.markReachY = 2.0,
    this.markAboveWeight = 4.0,
    this.markDirectX = 0.5,
    this.markDirectY = 1.2,
    this.minXHeightStrokes = 3,
    this.flatStrokeFactor = 0.4,
    this.xHeightQuantile = 0.35,
    this.xHeightBandLow = 0.6,
    this.xHeightBandHigh = 1.4,
  });

  /// Page lines are searched within ±this many degrees of horizontal.
  final double maxSkewDeg;

  /// Two line bodies (peaks of the ink density across the page) are never
  /// closer than this; a smaller peak nearer than this to a stronger one is
  /// a hump of the same line (a descender tail, a row of i-dots).
  final double minLineHeightFactor;

  /// Two neighbouring line bodies are separate lines only when the ink
  /// density in the valley between them drops to at most this fraction of
  /// the sparser body's peak density. The cut is then made at the deepest
  /// valley between the two peaks (never at a valley inside a descender
  /// tail, which is deeper but is not between two lines).
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

  /// A dot or bar (i-dot, comma, full stop) belongs to the line of the
  /// nearest bigger stroke that is no further than this many x-heights away
  /// sideways ...
  final double markReachX;

  /// ... and this many x-heights vertically (see [nearestSupport]).
  final double markReachY;

  /// A stroke entirely above a mark counts this many times its gap (a stroke
  /// under the mark is the likelier owner of an i-dot).
  final double markAboveWeight;

  /// A stroke starting under a mark within this many x-heights sideways ...
  final double markDirectX;

  /// ... and this many x-heights down owns the mark whatever else is near
  /// (the stem under an i-dot).
  final double markDirectY;

  /// A line needs at least this many bigger strokes before its x-height is
  /// estimated from them; fewer and the page-wide value is the best guess.
  final int minXHeightStrokes;

  /// Strokes flatter than this fraction of the line's median stroke height
  /// (t-bars, hyphens, underlines) are not counted as letters when the
  /// line's x-height is estimated.
  final double flatStrokeFactor;

  /// The first guess of a line's x-height is this lower quantile of its
  /// letter heights (about half of English letters are x-height only).
  final double xHeightQuantile;

  /// The x-height is the median of the strokes whose height is within
  /// [xHeightBandLow] and [xHeightBandHigh] times that first guess (tall
  /// letters and descenders are left out).
  final double xHeightBandLow;
  final double xHeightBandHigh;
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

/// One line of handwriting: a (possibly slanted) baseline
/// `y = baselineY + baselineSlope * (x - left)` and every pen stroke on it.
///
/// [inkStrokes] is the authority: it holds every stroke of the line, whatever
/// the word splitter made of them. [words] is the legacy word grouping
/// (geometric, fragile for loosely spaced writing); the recogniser reads the
/// whole line and derives its own word groups from the model's spaces.
class RecognizedLine {
  RecognizedLine({
    required this.words,
    required this.baselineY,
    required this.baselineSlope,
    required this.left,
    required this.right,
    required this.xHeight,
    List<Stroke>? inkStrokes,
  }) : inkStrokes = inkStrokes ?? [for (final w in words) ...w.strokes];

  final List<WordGroup> words;

  /// Baseline height at x = [left] (page frame, y down).
  final double baselineY;
  final double baselineSlope;
  final double left;
  final double right;

  /// x-height of this line in points (estimated from the line's own
  /// strokes whenever they give evidence).
  final double xHeight;

  /// Every pen stroke of the line, in input (writing) order. Dots, bars and
  /// stray marks included.
  final List<Stroke> inkStrokes;

  double baselineAt(double x) => baselineY + baselineSlope * (x - left);

  Iterable<Stroke> get strokes => inkStrokes;

  /// The same line with other [words] (for example the word groups the
  /// recogniser found); the ink, baseline and size stay.
  RecognizedLine copyWith({List<WordGroup>? words}) => RecognizedLine(
        words: words ?? this.words,
        baselineY: baselineY,
        baselineSlope: baselineSlope,
        left: left,
        right: right,
        xHeight: xHeight,
        inkStrokes: inkStrokes,
      );
}

/// Splits pen strokes into lines (and, as a fallback, words).
///
/// 1. Estimate the writing size `u` (x-height) from the stroke heights, or
///    take [expectedXHeight].
/// 2. Find the dominant page slope: the angle at which the ink's vertical
///    profile is peakiest (ruled lines pile up into sharp peaks).
/// 3. In the levelled frame, find the line bodies as peaks of the vertical
///    ink density, and cut at the deepest valley between neighbouring
///    peaks. Peaks too close to a stronger one, or not separated by a deep
///    enough valley ([GroupingConfig.lineValleyRatio]), are one line.
/// 4. Every stroke goes to a line: letters by where their ink lies, dots and
///    bars (i-dots, full stops) to the line of the stroke they sit over or
///    beside ([nearestSupport]), never by their own, ambiguous height.
/// 5. Fit every line's own baseline with [analyzeWord] and estimate its own
///    x-height.
/// 6. Along each line, merge strokes that overlap horizontally into letter
///    blocks, then join blocks closer than the line's word-gap threshold
///    (adaptive: see [GroupingConfig.wordGapRatio]); dots and bars attach to
///    the nearest word, and a lone narrow letter written a little apart from
///    its word is merged back into it ([GroupingConfig.fragmentWidthFactor]).
///    These [RecognizedLine.words] are only a fallback: the recogniser reads
///    whole lines ([RecognizedLine.inkStrokes]).
///
/// Highlighter strokes and shapes are ignored. Lines come top to bottom,
/// words left to right; every pen stroke ends up in exactly one line.
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
    items.add(_Item(s, b, items.length));
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

/// An axis-aligned box in a levelled frame (x along the line, y across it).
typedef LevelBox = ({double left, double top, double right, double bottom});

class _Item {
  _Item(this.stroke, this.bounds, this.index);

  final Stroke stroke;
  final InkRect bounds;

  /// Position in the input list (the strokes of a line keep this order).
  final int index;
  List<Vec2> samples = const [];

  /// A dot or bar next to the writing (set by the line search, judged
  /// against the page-wide size).
  bool tiny = false;

  /// Box of the samples in the levelled page frame (set by the line search).
  double lvLeft = 0, lvRight = 0, lvTop = 0, lvBottom = 0;

  /// Median sample height in the levelled page frame.
  double medianLevelY = 0;

  // Horizontal extent along the line (set per line).
  double xl = 0, xr = 0;

  LevelBox get levelBox => (left: lvLeft, top: lvTop, right: lvRight, bottom: lvBottom);
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
  for (final it in items) {
    var l = double.infinity, r = double.negativeInfinity;
    var t = double.infinity, b = double.negativeInfinity;
    final ys = <double>[];
    for (final p in it.samples) {
      final x = _levelX(p, c, s), y = _levelY(p, c, s);
      if (x < l) l = x;
      if (x > r) r = x;
      if (y < t) t = y;
      if (y > b) b = y;
      ys.add(y);
    }
    it.lvLeft = l;
    it.lvRight = r;
    it.lvTop = t;
    it.lvBottom = b;
    it.medianLevelY = median(ys) ?? 0;
    it.tiny = it.bounds.diagonal < config.tinyFactor * u;
  }

  // The line bodies are found from the letters; dots and bars would only add
  // small humps. A page of nothing but dots is still a page of lines.
  final letters = [
    for (final it in items)
      if (!it.tiny) it,
  ];
  final body = letters.isEmpty ? items : letters;

  var lo = double.infinity, hi = double.negativeInfinity;
  for (final it in body) {
    if (it.lvTop < lo) lo = it.lvTop;
    if (it.lvBottom > hi) hi = it.lvBottom;
  }
  final bh = math.max(u / 6, 0.25);
  final nb = ((hi - lo) / bh).floor() + 1;
  final hist = List<double>.filled(nb, 0);
  for (final it in body) {
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
  final peaks = _linePeaks(sm, minBins, config.lineValleyRatio);
  final cutBins = [
    for (var k = 0; k + 1 < peaks.length; k++) _valleyBetween(sm, peaks[k], peaks[k + 1]),
  ];
  final cutYs = [for (final k in cutBins) lo + (k + 0.5) * bh];

  int regionOf(double y) {
    var idx = 0;
    while (idx < cutYs.length && y > cutYs[idx]) {
      idx++;
    }
    return idx;
  }

  // The body of a line: the stretch around its peak where the density is at
  // least half the peak, kept between the cuts.
  final bodies = <({double lo, double hi})>[];
  for (var k = 0; k < peaks.length; k++) {
    var l = peaks[k], r = peaks[k];
    final half = sm[peaks[k]] / 2;
    final from = k == 0 ? 0 : cutBins[k - 1] + 1;
    final to = k == peaks.length - 1 ? nb - 1 : cutBins[k];
    while (l - 1 >= from && sm[l - 1] >= half) {
      l--;
    }
    while (r + 1 <= to && sm[r + 1] >= half) {
      r++;
    }
    bodies.add((lo: lo + l * bh, hi: lo + (r + 1) * bh));
  }

  // A letter belongs to the line whose body holds most of its ink. (Not to
  // the side of the cut its median falls on: the long tail of a y reaches
  // beyond the cut, and a tall l starts above it, and each belongs to the
  // line where it has its body.)
  int lineOf(_Item it) {
    final byMedian = regionOf(it.medianLevelY);
    if (bodies.length < 2) return byMedian;
    var best = byMedian;
    var bestCount = 0;
    for (var k = 0; k < bodies.length; k++) {
      var count = 0;
      for (final p in it.samples) {
        final y = _levelY(p, c, s);
        if (y >= bodies[k].lo && y < bodies[k].hi) count++;
      }
      if (count > bestCount || (count == bestCount && count > 0 && k == byMedian)) {
        bestCount = count;
        best = k;
      }
    }
    return best;
  }

  final region = <_Item, int>{for (final it in items) it: lineOf(it)};
  // Dots and bars follow the stroke they belong to: an i-dot hovers over its
  // stem and may well be nearer to the neighbouring line's descender, or to
  // the cut, than to its own line's body.
  if (letters.isNotEmpty) {
    final boxes = [for (final it in letters) it.levelBox];
    for (final it in items) {
      if (!it.tiny) continue;
      final k = nearestSupport(
        it.levelBox,
        boxes,
        u: u,
        reachX: config.markReachX,
        reachY: config.markReachY,
        aboveWeight: config.markAboveWeight,
        directX: config.markDirectX,
        directY: config.markDirectY,
      );
      if (k != null) region[it] = region[letters[k]]!;
    }
  }

  final groups = List.generate(cutYs.length + 1, (_) => <_Item>[]);
  for (final it in items) {
    groups[region[it]!].add(it);
  }
  return [
    for (final g in groups)
      if (g.isNotEmpty) g,
  ];
}

/// Local maxima of the ink density [sm] that are line bodies, as bin indices
/// from top to bottom. Starting from all local maxima, the weaker of two
/// neighbouring peaks is dropped while they are closer than [minBins] or the
/// valley between them is shallower than [ratio] of the weaker one's height
/// (the weakest offender first). What remains is separated by real valleys.
List<int> _linePeaks(List<double> sm, int minBins, double ratio) {
  const eps = 1e-9;
  final nb = sm.length;
  final peaks = <int>[];
  var i = 0;
  while (i < nb) {
    var j = i;
    while (j + 1 < nb && (sm[j + 1] - sm[i]).abs() <= eps) {
      j++;
    }
    final risesBefore = i == 0 || sm[i - 1] < sm[i] - eps;
    final fallsAfter = j == nb - 1 || sm[j + 1] < sm[i] - eps;
    if (sm[i] > eps && risesBefore && fallsAfter) peaks.add((i + j) ~/ 2);
    i = j + 1;
  }

  double valleyOf(int a, int b) {
    var v = double.infinity;
    for (var k = a; k <= b; k++) {
      if (sm[k] < v) v = sm[k];
    }
    return v;
  }

  while (peaks.length > 1) {
    var worst = -1;
    var worstHeight = double.infinity;
    for (var k = 0; k + 1 < peaks.length; k++) {
      final a = peaks[k], b = peaks[k + 1];
      final weaker = math.min(sm[a], sm[b]);
      final tooClose = b - a < minBins;
      final tooShallow = valleyOf(a, b) > ratio * weaker;
      if ((tooClose || tooShallow) && weaker < worstHeight) {
        worst = k;
        worstHeight = weaker;
      }
    }
    if (worst < 0) break;
    peaks.removeAt(sm[peaks[worst]] >= sm[peaks[worst + 1]] ? worst + 1 : worst);
  }
  return peaks;
}

/// Centre of the flat floor of the deepest valley between bins [a] and [b].
int _valleyBetween(List<double> sm, int a, int b) {
  var minV = double.infinity;
  var at = a;
  for (var i = a; i <= b; i++) {
    if (sm[i] < minV) {
      minV = sm[i];
      at = i;
    }
  }
  var l = at, r = at;
  while (l - 1 >= a && sm[l - 1] <= minV + 1e-9) {
    l--;
  }
  while (r + 1 <= b && sm[r + 1] <= minV + 1e-9) {
    r++;
  }
  return (l + r) ~/ 2;
}

/// Index into [candidates] of the stroke a small [mark] (an i-dot, a comma,
/// a full stop) belongs to, or null when no stroke is near enough.
///
/// 1. A stroke directly under the mark (starting at or below its lower
///    edge, no more than [directX] x-heights [u] sideways and [directY]
///    x-heights down) owns it: the stem of an i. The nearest such stroke
///    wins. Nothing else may take an i-dot from its stem, not even the
///    descender tail of the line above that happens to pass next to it.
/// 2. Otherwise the nearest stroke within [reachX] x-heights sideways and
///    [reachY] vertically wins, with the distance scaled by those reaches
///    (an i-dot hovers well above its stem, but a word on the same line is
///    not that close sideways). A candidate overlapping the mark in height
///    (the letter before a full stop) counts at its real gap; one entirely
///    above it counts [aboveWeight] times its gap (a full stop written a
///    hair under the baseline still finds the letter above it).
///
/// [underOnly] skips the second step's candidates that are not under the
/// mark.
int? nearestSupport(
  LevelBox mark,
  List<LevelBox> candidates, {
  required double u,
  double reachX = 1.2,
  double reachY = 2.0,
  double aboveWeight = 4.0,
  double directX = 0.5,
  double directY = 1.2,
  bool underOnly = false,
}) {
  int? best;
  var bestCost = double.infinity;
  int? direct;
  var directCost = double.infinity;
  final rx = reachX * u, ry = reachY * u;
  final dxx = directX * u, dyy = directY * u;
  for (var k = 0; k < candidates.length; k++) {
    final c = candidates[k];
    final dx = math.max(0.0, math.max(c.left - mark.right, mark.left - c.right));
    final double dy;
    if (c.top >= mark.bottom) {
      dy = c.top - mark.bottom;
      if (dx <= dxx && dy <= dyy) {
        final cost = (dx / dxx) * (dx / dxx) + (dy / dyy) * (dy / dyy);
        if (cost < directCost) {
          directCost = cost;
          direct = k;
        }
      }
    } else if (underOnly) {
      continue;
    } else if (c.bottom <= mark.top) {
      dy = aboveWeight * (mark.top - c.bottom);
    } else {
      dy = 0;
    }
    if (dx > rx || dy > ry) continue;
    final cost = (dx / rx) * (dx / rx) + (dy / ry) * (dy / ry);
    if (cost < bestCost) {
      bestCost = cost;
      best = k;
    }
  }
  return direct ?? best;
}

/// The x-height of a line from the heights of its bigger strokes, or null
/// when the line has too few of them. Flat strokes (bars) are ignored; the
/// first guess is a low quantile of the letter heights, refined to the
/// median of the strokes of about that height (tall letters and descenders
/// are left out), see [GroupingConfig.xHeightQuantile].
double? _strokeXHeight(List<_Item> items, GroupingConfig config) {
  final heights = [
    for (final it in items)
      if (!it.tiny) it.lvBottom - it.lvTop,
  ];
  if (heights.length < config.minXHeightStrokes) return null;
  final med = median(heights) ?? 0;
  if (med <= 0) return null;
  final letters = [
    for (final h in heights)
      if (h >= config.flatStrokeFactor * med) h,
  ];
  final guess = lowerQuantile(letters, config.xHeightQuantile);
  if (guess == null || guess <= 0) return null;
  final band = [
    for (final h in heights)
      if (h >= config.xHeightBandLow * guess && h <= config.xHeightBandHigh * guess) h,
  ];
  return median(band) ?? guess;
}

RecognizedLine _buildLine(
  List<_Item> lineItems,
  double pageAngle,
  double u,
  double? expectedXHeight,
  GroupingConfig config,
) {
  final items = [...lineItems]..sort((a, b) => a.index.compareTo(b.index));
  final strokes = [for (final it in items) it.stroke];

  // The line's own size, from its own strokes, steers the baseline fit; the
  // page-wide size is only a last resort.
  final own = _strokeXHeight(items, config);
  final hint = expectedXHeight ?? own ?? u;
  final analysis = analyzeWord(
    strokes,
    context: FeatureContext(
      lineSkew: pageAngle,
      scaleHintPt: hint,
      expectedXHeight: expectedXHeight,
    ),
    useRaw: false,
  );

  var slope = math.tan(pageAngle);
  double? fittedXHeight;
  if (analysis != null) {
    final fitted = analysis.baseline.line.slope;
    if (fitted.isFinite && math.atan(fitted).abs() < degToRad(config.maxSkewDeg + 10)) {
      slope = fitted;
    }
    // The letter tops above the fitted baseline are the best evidence, even
    // when they are all of one kind (a line of capitals: the analysis then
    // derives the x-height from the cap height).
    final xh = analysis.xHeight;
    if ((xh.reliable || xh.topCount >= 2) && xh.xHeight.isFinite && xh.xHeight > 0) {
      fittedXHeight = xh.xHeight;
    }
  }
  final lineU = expectedXHeight ?? fittedXHeight ?? own ?? u;

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
  for (final it in items) {
    if (it.bounds.left < left) left = it.bounds.left;
    if (it.bounds.right > right) right = it.bounds.right;
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
    inkStrokes: strokes,
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
