import 'dart:math' as math;

import '../ink/affine2.dart';
import '../ink/ink_point.dart';
import '../ink/ink_rect.dart';
import '../ink/stroke.dart';
import '../ink/vec2.dart';
import 'resample.dart';
import 'stats.dart';
import 'tidy_config.dart';

/// Spec step 3: feature detection on one word.
///
/// Conventions used throughout this file:
/// * Page coordinates, y points **down**. "Above the baseline" means a
///   smaller y. Heights above the baseline are therefore `baseline − y`.
/// * Angles are radians. Skew θ > 0 means the baseline descends to the right
///   (it is rotated clockwise on screen). Slant φ > 0 means strokes lean to
///   the right (their tops are right of their bottoms).
/// * Everything is measured on resampled copies of the points (step 0).

/// Stroke classes from spec step 3d.
enum StrokeClass {
  /// x-height letters: a, c, e, m, n, o, r, s, u, v, w, x, z.
  core,

  /// Ascenders, capitals, digits: b, d, h, k, l, t, A–Z, 0–9.
  tall,

  /// Letters with a tail below the baseline: g, p, y, q, j.
  descender,

  /// Dots, small accents, apostrophes. Never resized.
  mark,
}

/// What feature detection may borrow from the running context when the
/// word's own estimate is unreliable (spec 3a.5, 3a.6, 3c.4).
class FeatureContext {
  const FeatureContext({
    this.lineSkew,
    this.lineSlant,
    this.lineWordCount = 0,
    this.expectedXHeight,
    this.scaleHintPt = 9,
    this.tallRatio,
  });

  /// Median skew of the current line's words (radians), if any.
  final double? lineSkew;

  /// Median slant of the current line's words (radians), if any.
  final double? lineSlant;

  /// Number of words already on the current line.
  final int lineWordCount;

  /// x-height the user is known to write at (line / page medians or the
  /// ruled paper), or null when nothing real is known yet. Used to tell an
  /// all-caps word from a lowercase word written large.
  final double? expectedXHeight;

  /// Rough x-height that is never null (the expected one or the spec's
  /// initial estimate). Sets the scale of the extrema hysteresis and of the
  /// preliminary mark test.
  final double scaleHintPt;

  /// Running median tall-stroke height / x-height on the page, if known.
  final double? tallRatio;
}

/// The fitted baseline of a word, in page coordinates (spec 3a).
class BaselineFit {
  const BaselineFit({
    required this.line,
    required this.extrema,
    required this.ownSlope,
  });

  /// The baseline `y = slope·x + intercept` used for the word.
  final LineFit line;

  /// Bottom extrema kept after descender and outlier removal.
  final List<Vec2> extrema;

  /// Slope the word's own extrema gave, or null when they could not define
  /// one (fewer than two, or all at the same x).
  final double? ownSlope;
}

/// Result of the x-height estimate (spec 3b).
class XHeightEstimate {
  const XHeightEstimate({
    required this.xHeight,
    required this.reliable,
    required this.allCaps,
    this.capHeight,
    this.topCount = 0,
  });

  /// x-height in points. For an all-caps word this is *derived*: cap height
  /// divided by the tall ratio, so the word is sized like its neighbours
  /// instead of shrinking its capitals to lowercase size.
  final double xHeight;

  /// True when the value came from enough letter tops to update the page's
  /// running statistics.
  final bool reliable;

  final bool allCaps;

  /// Measured cap height of an all-caps word.
  final double? capHeight;

  /// Number of letter tops the estimate used.
  final int topCount;
}

/// Result of the slant estimate (spec 3c).
class SlantEstimate {
  const SlantEstimate({
    required this.angle,
    required this.totalLength,
    required this.reliable,
  });

  /// φ in radians, positive = leaning right. When not [reliable] this is the
  /// value borrowed from the line (or 0).
  final double angle;

  /// Total length of the near-vertical segments that were used.
  final double totalLength;
  final bool reliable;
}

/// Per-stroke measurements in the deskewed frame (spec 3d).
class StrokeShape {
  const StrokeShape({
    required this.strokeId,
    required this.strokeClass,
    required this.keepBottom,
    required this.top,
    required this.bottom,
    required this.bounds,
  });

  final String strokeId;
  final StrokeClass strokeClass;

  /// Tall *and* descender (an f with a tail): handled as tall, but its
  /// bottom must not be changed.
  final bool keepBottom;

  /// Height of the stroke's highest point above the baseline (pt). Negative
  /// when the whole stroke is below the baseline.
  final double top;

  /// Depth of the stroke's lowest point below the baseline (pt). Negative
  /// when the whole stroke floats above the baseline.
  final double bottom;

  /// Bounds in the deskewed frame.
  final InkRect bounds;
}

/// Everything step 3 measured about one word.
class WordAnalysis {
  WordAnalysis._({
    required this.strokeIds,
    required this.samples,
    required this.preliminaryMarks,
    required this.bounds,
    required this.coreBounds,
    required this.sampleCount,
    required this.scaleHint,
    required this.baseline,
    required this.hasBaselineExtrema,
    required this.wordSkew,
    required this.skewReliable,
    required this.skew,
    required this.baselineStart,
    required this.baselineEnd,
    required this.deskew,
    required this.deskewedBaselineSlope,
    required this.xHeight,
    required this.slant,
    required this.strokes,
    required this.tallRatio,
  });

  /// Ids of the analysed strokes, in input order.
  final List<String> strokeIds;

  /// Resampled points per stroke, in input order (page frame).
  final List<List<Vec2>> samples;

  /// Per stroke: excluded from extrema / slant as a probable dot or accent.
  final List<bool> preliminaryMarks;

  /// Bounds of all finite points (page frame).
  final InkRect bounds;

  /// Bounds of the strokes that are not preliminary marks (page frame).
  final InkRect coreBounds;

  /// Total number of resampled points (spec step 2's `minPointsForTidy`).
  final int sampleCount;

  /// The scale (≈ x-height, pt) used for hysteresis and mark tests.
  final double scaleHint;

  final BaselineFit baseline;

  /// False when no bottom extremum was found at all and the baseline is
  /// only the bottom of the box (dashes, dots, flat lines).
  final bool hasBaselineExtrema;

  /// θ_word: the word's own skew, or the borrowed one when not reliable.
  final double wordSkew;
  final bool skewReliable;

  /// θ_final after blending with the line (spec 3a.6). The word transform
  /// rotates by `−s·skew`.
  final double skew;

  /// P0: left end of the fitted baseline (pivot of the word transform).
  final Vec2 baselineStart;

  /// Right end of the fitted baseline.
  final Vec2 baselineEnd;

  /// Rotation by −θ_final around P0 (page frame → deskewed frame).
  final Affine2 deskew;

  /// Slope of the fitted baseline in the deskewed frame. Zero unless θ_final
  /// was blended away from θ_word.
  final double deskewedBaselineSlope;

  final XHeightEstimate xHeight;
  final SlantEstimate slant;

  /// One entry per input stroke, in input order.
  final List<StrokeShape> strokes;

  /// Median tall-stroke height / x-height of this word, if it has tall
  /// strokes and is not all caps.
  final double? tallRatio;

  /// Baseline y at P0 (page frame).
  double get baselineY => baselineStart.y;

  /// Deskewed-frame baseline height at [x].
  double deskewedBaselineAt(double x) =>
      baselineStart.y + deskewedBaselineSlope * (x - baselineStart.x);

  /// Point on the fitted (page-frame) baseline at [x].
  Vec2 baselinePointAt(double x) => Vec2(x, baseline.line.yAt(x));

  int get nonMarkCount =>
      strokes.where((s) => s.strokeClass != StrokeClass.mark).length;
}

/// Runs spec step 3 on [strokes]. Uses each stroke's `raw` points unless
/// [useRaw] is false (then the displayed `points`, e.g. to measure where a
/// stored tidied word sits now). Returns null when no stroke has a finite
/// point.
WordAnalysis? analyzeWord(
  List<Stroke> strokes, {
  FeatureContext context = const FeatureContext(),
  TidyConfig config = const TidyConfig(),
  bool useRaw = true,
}) {
  final ids = <String>[];
  final samples = <List<Vec2>>[];
  final boxes = <InkRect?>[];
  var sampleCount = 0;
  InkRect? bounds;
  for (final s in strokes) {
    final pts = useRaw ? s.raw : s.points;
    final r = resampleInkPoints(pts, config.resampleStepPt);
    final b = finiteBounds(pts);
    ids.add(s.id);
    samples.add(r);
    boxes.add(b);
    sampleCount += r.length;
    if (b != null) bounds = bounds == null ? b : bounds.union(b);
  }
  if (bounds == null) return null;

  // Scale hint u ≈ x-height. Large writing raises it through the box height
  // so the hysteresis below stays proportional to the letters.
  final u = math.max(
      context.scaleHintPt, config.extremaScaleBboxFactor * bounds.height);

  // Preliminary marks: tiny strokes (i-dots) would otherwise add bogus
  // extrema far above the baseline. If *every* stroke is tiny, analyse them
  // all anyway.
  var marks = [
    for (final b in boxes) b == null || b.diagonal < config.smallMarkFactor * u,
  ];
  if (marks.every((m) => m)) marks = List.filled(marks.length, false);
  InkRect? core;
  for (var i = 0; i < boxes.length; i++) {
    final b = boxes[i];
    if (marks[i] || b == null) continue;
    core = core == null ? b : core.union(b);
  }
  final coreBounds = core ?? bounds;

  // ---- 3a: baseline and skew ------------------------------------------
  final minDrop = config.extremaMinDropFactor * u;
  final bottoms = <Vec2>[];
  for (var i = 0; i < samples.length; i++) {
    if (marks[i]) continue;
    final pts = samples[i];
    final ys = [for (final p in pts) p.y];
    for (final k in findPeaks(ys,
        minDrop: minDrop,
        window: config.extremaWindow,
        includeStart: false,
        includeEnd: true)) {
      bottoms.add(pts[k]);
    }
  }
  final fit = fitBaseline(bottoms,
      boxHeight: coreBounds.height, scale: u, config: config);

  final ownSlope = fit?.ownSlope;
  final inliers = fit?.extrema ?? const <Vec2>[];
  final skewReliable = ownSlope != null &&
      inliers.length >= config.minExtremaForSkew &&
      coreBounds.width >= config.minWidthForSkew * u;
  final wordSkew =
      skewReliable ? math.atan(ownSlope) : (context.lineSkew ?? 0.0);

  final LineFit line;
  if (skewReliable) {
    line = fit!.line;
  } else {
    // Borrowed slope; intercept from the inliers' median so one stray
    // extremum cannot drag the baseline. No extrema at all: sit the
    // baseline on the bottom of the box.
    final slope = math.tan(wordSkew);
    final b = median([for (final p in inliers) p.y - slope * p.x]) ??
        (coreBounds.bottom - slope * coreBounds.left);
    line = LineFit(slope, b);
  }

  final lineSkew = context.lineSkew;
  final skew =
      lineSkew != null && context.lineWordCount >= config.minLineWordsForSkewBlend
          ? config.wordSkewWeight * wordSkew +
              (1 - config.wordSkewWeight) * lineSkew
          : wordSkew;

  final p0 = Vec2(coreBounds.left, line.yAt(coreBounds.left));
  final p1 = Vec2(coreBounds.right, line.yAt(coreBounds.right));
  // Affine2.rotation turns clockwise on screen for positive angles, and a
  // positive skew is a clockwise tilt, so −θ levels the baseline.
  final deskew = Affine2.rotation(-skew, pivot: p0);
  final q1 = deskew.apply(p1);
  final dxBase = q1.x - p0.x;
  final residualSlope = dxBase.abs() > 1e-9 ? (q1.y - p0.y) / dxBase : 0.0;
  double baseAt(double x) => p0.y + residualSlope * (x - p0.x);

  final deskewed = [
    for (final pts in samples) [for (final p in pts) deskew.apply(p)],
  ];

  // ---- 3b: x-height ---------------------------------------------------
  final tops = <double>[];
  for (var i = 0; i < deskewed.length; i++) {
    if (marks[i]) continue;
    final pts = deskewed[i];
    // Tops are maxima of −y. Stroke *starts* are often letter tops (l, h, i,
    // n begin at the top), stroke ends rarely are (they are usually exit
    // hooks), so starts count and ends do not.
    final negY = [for (final p in pts) -p.y];
    for (final k in findPeaks(negY,
        minDrop: minDrop,
        window: config.extremaWindow,
        includeStart: true,
        includeEnd: false)) {
      tops.add(baseAt(pts[k].x) - pts[k].y);
    }
  }
  final tallRatioHint = (context.tallRatio ?? config.defaultTallRatio)
      .clamp(config.minTallRatio, config.maxTallRatio);
  final xh = estimateXHeight(
    tops,
    boxHeight: coreBounds.height,
    expectedXHeight: context.expectedXHeight,
    tallRatio: tallRatioHint,
    minHeight: minDrop,
    config: config,
  );

  // ---- 3c: slant -----------------------------------------------------
  final slant = estimateSlant(
    [
      for (var i = 0; i < deskewed.length; i++)
        if (!marks[i]) deskewed[i],
    ],
    xHeight: xh.xHeight,
    fallback: context.lineSlant,
    config: config,
  );

  // ---- 3d: stroke classes ----------------------------------------------
  final shapes = <StrokeShape>[];
  final tallTops = <double>[];
  for (var i = 0; i < deskewed.length; i++) {
    final shape = _classify(ids[i], deskewed[i], baseAt, xh.xHeight, config);
    shapes.add(shape);
    if (shape.strokeClass == StrokeClass.tall) tallTops.add(shape.top);
  }
  final tallRatio = xh.allCaps || tallTops.isEmpty || xh.xHeight <= 0
      ? null
      : median(tallTops)! / xh.xHeight;

  return WordAnalysis._(
    strokeIds: ids,
    samples: samples,
    preliminaryMarks: marks,
    bounds: bounds,
    coreBounds: coreBounds,
    sampleCount: sampleCount,
    scaleHint: u,
    baseline: BaselineFit(
        line: line, extrema: inliers, ownSlope: fit?.ownSlope),
    hasBaselineExtrema: inliers.isNotEmpty,
    wordSkew: wordSkew,
    skewReliable: skewReliable,
    skew: skew,
    baselineStart: p0,
    baselineEnd: p1,
    deskew: deskew,
    deskewedBaselineSlope: residualSlope,
    xHeight: xh,
    slant: slant,
    strokes: shapes,
    tallRatio: tallRatio,
  );
}

StrokeShape _classify(String id, List<Vec2> pts, double Function(double) baseAt,
    double xHeight, TidyConfig config) {
  if (pts.isEmpty) {
    return StrokeShape(
        strokeId: id,
        strokeClass: StrokeClass.mark,
        keepBottom: false,
        top: 0,
        bottom: 0,
        bounds: InkRect.empty);
  }
  var top = double.negativeInfinity, bottom = double.negativeInfinity;
  for (final p in pts) {
    final d = p.y - baseAt(p.x); // > 0 below the baseline
    if (-d > top) top = -d;
    if (d > bottom) bottom = d;
  }
  final box = InkRect.fromPoints(pts);
  final StrokeClass cls;
  var keepBottom = false;
  if (box.diagonal < config.smallMarkFactor * xHeight) {
    cls = StrokeClass.mark;
  } else {
    final isTall = top > config.tallFactor * xHeight;
    final isDescender = bottom > config.descenderFactor * xHeight;
    if (isTall) {
      cls = StrokeClass.tall;
      keepBottom = isDescender;
    } else if (isDescender) {
      cls = StrokeClass.descender;
    } else {
      cls = StrokeClass.core;
    }
  }
  return StrokeShape(
      strokeId: id,
      strokeClass: cls,
      keepBottom: keepBottom,
      top: top,
      bottom: bottom,
      bounds: box);
}

/// Indices of the local maxima of [v] along a stroke (spec 3a.1).
///
/// A maximum must be the largest value within ±[window] samples **and** the
/// signal must drop by at least [minDrop] on its way to the next maximum
/// (hysteresis). The hysteresis is what makes this robust: pen jitter and
/// flat bars (E, H, t-crossings) never move far enough to create extrema,
/// and a plateau yields a single extremum (its first sample).
///
/// [includeStart] / [includeEnd] also report the first / last stretch of
/// the stroke when it is a maximum (it only needs the drop on one side).
List<int> findPeaks(
  List<double> v, {
  required double minDrop,
  required int window,
  required bool includeStart,
  required bool includeEnd,
}) {
  final n = v.length;
  final peaks = <int>[];
  if (n < 2) return peaks;

  // Phase 0: find the first move of at least minDrop to learn the initial
  // direction. hi / lo are the running max / min since the start.
  var phase = 0; // +1 rising (tracking a max), −1 falling (tracking a min)
  var cand = 0;
  var hi = 0, lo = 0;
  var k = 1;
  for (; k < n && phase == 0; k++) {
    if (v[k] > v[hi]) hi = k;
    if (v[k] < v[lo]) lo = k;
    if (v[hi] - v[lo] >= minDrop) {
      if (lo < hi) {
        phase = 1; // went up first: keep tracking this rise
        cand = hi;
      } else {
        phase = -1; // went down first: the start region was a maximum
        cand = lo;
        if (includeStart && _isWindowMax(v, hi, window)) peaks.add(hi);
      }
    }
  }
  for (; k < n; k++) {
    if (phase == 1) {
      if (v[k] > v[cand]) {
        cand = k;
      } else if (v[cand] - v[k] >= minDrop) {
        if (_isWindowMax(v, cand, window)) peaks.add(cand);
        phase = -1;
        cand = k;
      }
    } else if (phase == -1) {
      if (v[k] < v[cand]) {
        cand = k;
      } else if (v[k] - v[cand] >= minDrop) {
        phase = 1;
        cand = k;
      }
    }
  }
  // Ended while rising: the last maximum is the stroke's end (or just
  // before a tiny exit hook smaller than minDrop).
  if (phase == 1 && includeEnd && _isWindowMax(v, cand, window)) {
    peaks.add(cand);
  }
  return peaks;
}

bool _isWindowMax(List<double> v, int i, int window) {
  final from = math.max(0, i - window), to = math.min(v.length - 1, i + window);
  for (var j = from; j <= to; j++) {
    if (v[j] > v[i]) return false;
  }
  return true;
}

/// Spec 3a.2–3a.3: drops descender extrema, fits `y = a·x + b` by least
/// squares, removes outliers once and refits. Returns null when there are
/// no extrema.
///
/// [boxHeight] is the word's box height (descender threshold) and [scale]
/// its approximate x-height (floor of the outlier threshold).
BaselineFit? fitBaseline(
  List<Vec2> bottoms, {
  required double boxHeight,
  required double scale,
  TidyConfig config = const TidyConfig(),
}) {
  if (bottoms.isEmpty) return null;
  // Descenders: lower (larger y) than the median by a good part of the box.
  final m = median([for (final p in bottoms) p.y])!;
  final limit = m + config.descenderExtremaFactor * boxHeight;
  var pts = [
    for (final p in bottoms)
      if (p.y <= limit) p,
  ];
  if (pts.isEmpty) pts = bottoms;

  var line = _fit(pts);
  if (line != null && pts.length > 2) {
    final res = [for (final p in pts) (p.y - line.yAt(p.x)).abs()];
    final mar = median(res)!;
    final thr = math.max(config.outlierResidualFactor * mar,
        config.outlierResidualFloorFactor * scale);
    final kept = [
      for (var i = 0; i < pts.length; i++)
        if (res[i] <= thr) pts[i],
    ];
    final refit = kept.length >= 2 ? _fit(kept) : null;
    if (refit != null) {
      pts = kept;
      line = refit;
    }
  }
  if (line != null) {
    return BaselineFit(line: line, extrema: pts, ownSlope: line.slope);
  }
  // One extremum (or all at the same x): horizontal through their median.
  final y = median([for (final p in pts) p.y])!;
  return BaselineFit(line: LineFit(0, y), extrema: pts, ownSlope: null);
}

LineFit? _fit(List<Vec2> pts) =>
    leastSquaresLine([for (final p in pts) p.x], [for (final p in pts) p.y]);

/// Spec 3b: x-height from the heights of letter tops above the baseline.
///
/// The spec's literal rule (reference = median of all tops, drop tops above
/// 1.45 × median, "all caps" when > 60 % are dropped) cannot work: at most
/// half the values exceed the median, so the all-caps branch can never fire,
/// and a word like "hello" (three ascender tops, three x-height tops) gets a
/// median halfway between the two levels and drops nothing. This keeps the
/// spec's structure with a lower-quartile reference, and uses the expected
/// x-height (when known) to tell "HE" from a lowercase word written large:
///
/// 1. Ignore tops lower than [TidyConfig.minTopHeightFraction] × the highest
///    top, and tops below [minHeight] (pen hooks near the baseline).
/// 2. `ref` = lower quartile. Tops above `1.45 × ref` are ascenders/capitals.
/// 3. More than 60 % dropped → all caps, unless the low tops agree with the
///    expected x-height (then it is lowercase with many ascenders, "Hill").
/// 4. Nothing dropped (one cluster) → all caps when the cluster is at least
///    1.45 × the expected x-height, otherwise those tops are the x-height.
/// 5. All caps: x-height = cap height / [tallRatio], so capitals are sized
///    like capitals of the surrounding words.
/// 6. Fewer than two tops: the spec's fallback, 0.45 × box height (a single
///    top is used when the expected x-height can classify it).
XHeightEstimate estimateXHeight(
  List<double> topHeights, {
  required double boxHeight,
  double? expectedXHeight,
  required double tallRatio,
  double minHeight = 0,
  TidyConfig config = const TidyConfig(),
}) {
  final positive = [
    for (final h in topHeights)
      if (h > minHeight && h.isFinite) h,
  ];
  final fallback = XHeightEstimate(
    xHeight: math.max(config.xHeightFallbackFactor * boxHeight, 1e-3),
    reliable: false,
    allCaps: false,
  );
  if (positive.isEmpty) return fallback;
  final maxH = positive.reduce(math.max);
  final valid = [
    for (final h in positive)
      if (h >= config.minTopHeightFraction * maxH) h,
  ];
  final e = expectedXHeight;
  final tallLimit = config.ascenderTopFactor;

  XHeightEstimate caps(double capHeight, int count) => XHeightEstimate(
        xHeight: capHeight / tallRatio,
        reliable: false,
        allCaps: true,
        capHeight: capHeight,
        topCount: count,
      );

  if (valid.length < 2) {
    final h = valid.single;
    if (e == null) return fallback;
    if (h >= tallLimit * e) return caps(h, 1);
    return XHeightEstimate(
        xHeight: h, reliable: false, allCaps: false, topCount: 1);
  }

  final ref = lowerQuantile(valid, config.xHeightReferenceQuantile)!;
  final kept = [
    for (final h in valid)
      if (h <= tallLimit * ref) h,
  ];
  final droppedFraction = 1 - kept.length / valid.length;

  if (droppedFraction > config.allCapsDropFraction) {
    final lowTopsAreXHeight = e != null && ref * tallLimit >= e;
    if (!lowTopsAreXHeight) return caps(median(valid)!, valid.length);
    return XHeightEstimate(
        xHeight: median(kept)!,
        reliable: true,
        allCaps: false,
        topCount: kept.length);
  }
  if (kept.length == valid.length) {
    // One cluster: x-height letters only ("one") or capitals/ascenders only
    // ("HE", "ll"). Only the expected x-height can tell them apart.
    final level = median(valid)!;
    if (e != null && level >= tallLimit * e) return caps(level, valid.length);
    return XHeightEstimate(
        xHeight: level,
        reliable: e != null,
        allCaps: false,
        topCount: valid.length);
  }
  return XHeightEstimate(
      xHeight: median(kept)!,
      reliable: true,
      allCaps: false,
      topCount: kept.length);
}

/// Spec 3c: length-weighted median angle from vertical of the near-vertical
/// segments of [strokes] (deskewed resampled points). Positive = leaning
/// right. Unreliable (and replaced by [fallback], or 0) when the segments
/// total less than 1.5 × [xHeight].
SlantEstimate estimateSlant(
  List<List<Vec2>> strokes, {
  required double xHeight,
  double? fallback,
  TidyConfig config = const TidyConfig(),
}) {
  final maxFromVertical = math.tan(degToRad(config.slantMaxFromVerticalDeg));
  final angles = <double>[];
  final weights = <double>[];
  var total = 0.0;
  for (final pts in strokes) {
    for (var i = 1; i < pts.length; i++) {
      var dx = pts[i].x - pts[i - 1].x;
      var dy = pts[i].y - pts[i - 1].y;
      if (dy == 0 || dx.abs() > maxFromVertical * dy.abs()) continue;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < config.slantMinSegmentPt) continue;
      // Orient every segment upward (dy < 0, y is down) so that "top to the
      // right of the bottom" always gives a positive angle.
      if (dy > 0) {
        dx = -dx;
        dy = -dy;
      }
      angles.add(math.atan2(dx, -dy));
      weights.add(len);
      total += len;
    }
  }
  final reliable = total >= config.slantMinTotalLengthFactor * xHeight &&
      angles.isNotEmpty;
  if (!reliable) {
    return SlantEstimate(
        angle: fallback ?? 0.0, totalLength: total, reliable: false);
  }
  return SlantEstimate(
      angle: weightedMedian(angles, weights)!,
      totalLength: total,
      reliable: true);
}

/// Bottom extrema of [strokes] (resampled, page frame), skipping tiny
/// strokes. Cheap enough to run on every pen-up; the word segmenter uses it
/// to estimate where a pending word's baseline is.
double? estimateBaselineY(
  List<List<InkPoint>> strokes, {
  required double scaleHint,
  TidyConfig config = const TidyConfig(),
}) {
  final res = [
    for (final s in strokes) resampleInkPoints(s, config.resampleStepPt),
  ];
  InkRect? box;
  for (final r in res) {
    if (r.isEmpty) continue;
    final b = InkRect.fromPoints(r);
    box = box == null ? b : box.union(b);
  }
  if (box == null) return null;
  final u = math.max(scaleHint, config.extremaScaleBboxFactor * box.height);
  final bottoms = <Vec2>[];
  for (final r in res) {
    if (r.isEmpty || InkRect.fromPoints(r).diagonal < config.smallMarkFactor * u) {
      continue;
    }
    final ys = [for (final p in r) p.y];
    for (final k in findPeaks(ys,
        minDrop: config.extremaMinDropFactor * u,
        window: config.extremaWindow,
        includeStart: false,
        includeEnd: true)) {
      bottoms.add(r[k]);
    }
  }
  if (bottoms.isEmpty) return box.bottom;
  final m = median([for (final p in bottoms) p.y])!;
  final limit = m + config.descenderExtremaFactor * box.height;
  return median([
    for (final p in bottoms)
      if (p.y <= limit) p.y,
  ]);
}
