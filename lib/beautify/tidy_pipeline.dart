import 'dart:math' as math;

import '../ink/affine2.dart';
import '../ink/ink_point.dart';
import '../ink/ink_rect.dart';
import '../ink/stroke.dart';
import '../ink/vec2.dart';
import 'features.dart';
import 'line_context.dart';
import 'resample.dart';
import 'smoothing.dart';
import 'stats.dart';
import 'tidy_config.dart';
import 'transform.dart';

/// Spec step 2 and the top-level API of the tidy engine: take the strokes of
/// a finished word plus the page / line context and produce new display
/// points for every stroke, together with the detection data the debug
/// overlay draws. Pure Dart: runs in an isolate if the editor wants.

/// Why a word was left alone (spec step 2, plus the never-tidy rules).
enum SkipReason {
  /// No strokes.
  empty,

  /// A highlighter stroke is part of the word.
  highlighter,

  /// A stroke was snapped to a shape.
  shape,

  /// The user undid / restored this word's tidy; never tidy it again
  /// automatically.
  locked,

  /// Not a single finite point.
  noFinitePoints,

  /// Fewer than `minPointsForTidy` resampled points, or no usable size.
  tooFewPoints,

  /// Word box taller than `maxWordHeightFactor × lineHeight`: a drawing.
  tooTall,

  /// A very wide, flat stroke: an underline or a ruler line.
  underline,

  /// More than half of the word lies on another tidied word.
  overlapsTidied,

  /// Tilted more than `maxSkewDeg`: intentional.
  excessiveSkew,

  /// Leaning more than `maxSlantDeg`: intentional.
  excessiveSlant,
}

/// A line segment in page coordinates, for the overlay.
class Seg {
  const Seg(this.a, this.b);
  final Vec2 a;
  final Vec2 b;
}

/// What the tidy step detected and decided, for the debug overlay (spec,
/// "Debug overlay"). All geometry is in page coordinates; "detected" values
/// describe the raw ink, "tidied" values the result.
class WordFeatures {
  const WordFeatures({
    required this.skew,
    required this.wordSkew,
    required this.skewReliable,
    required this.slant,
    required this.slantReliable,
    required this.xHeight,
    required this.xHeightReliable,
    required this.allCaps,
    required this.scale,
    required this.targetXHeight,
    required this.targetSlant,
    required this.snapped,
    required this.baseline,
    required this.xHeightLine,
    required this.slantLine,
    required this.bounds,
    required this.tidiedBaseline,
    required this.tidiedXHeightLine,
    required this.tidiedBounds,
    required this.strokeClasses,
  });

  /// θ_final (radians) the word was rotated by (scaled by strength).
  final double skew;

  /// θ_word, before blending with the line.
  final double wordSkew;
  final bool skewReliable;

  /// φ (radians, positive = leaning right) measured after deskewing.
  final double slant;
  final bool slantReliable;

  /// Measured x-height (pt) and whether it came from enough letter tops.
  final double xHeight;
  final bool xHeightReliable;
  final bool allCaps;

  /// Word scale factor `k` and the targets it aimed for.
  final double scale;
  final double targetXHeight;
  final double? targetSlant;

  /// True when the baseline was moved to a ruled line / the running line.
  final bool snapped;

  /// Detected fitted baseline (blue), x-height line (green) and slant line
  /// (orange), and the bounding box (grey), in the raw ink's frame.
  final Seg baseline;
  final Seg xHeightLine;
  final Seg slantLine;
  final InkRect bounds;

  /// The same after tidying.
  final Seg tidiedBaseline;
  final Seg tidiedXHeightLine;
  final InkRect tidiedBounds;

  /// Stroke classes (colored dots in the overlay), by stroke id.
  final Map<String, StrokeClass> strokeClasses;
}

/// The outcome of tidying one word.
class TidyResult {
  const TidyResult({
    required this.wordId,
    required this.newPoints,
    required this.wordTransform,
    required this.features,
    required this.record,
  });

  final String wordId;

  /// Strokes' new display points, by stroke id. Each list has exactly as many
  /// points as the stroke's raw list, with the same pressure and time, so the
  /// editor can animate raw → tidied point by point.
  final Map<String, List<InkPoint>> newPoints;

  /// The word-level affine (rotate, shear, scale, vertical and spacing
  /// shift). Per-stroke alignment and smoothing come on top of it.
  final Affine2 wordTransform;

  final WordFeatures features;

  /// What to remember about this word: pass it to `PageContext.recordWord`.
  final WordRecord record;
}

/// [tidyWordDetailed]'s answer: either a result, or why the word was
/// skipped. A skipped word still has a [record] (when it could be measured)
/// so spacing for the next word works.
class TidyDecision {
  const TidyDecision.tidied(TidyResult this.result)
      : skip = null,
        record = null;
  const TidyDecision.skipped(SkipReason this.skip, {this.record})
      : result = null;

  final TidyResult? result;
  final SkipReason? skip;

  /// Record of a skipped word.
  final WordRecord? record;

  bool get isTidied => result != null;

  /// The record to store for this word, tidied or skipped.
  WordRecord? get wordRecord => result?.record ?? record;
}

/// Spec API: tidies one finished word, or returns null when it should be
/// left alone. See [tidyWordDetailed] for the reason.
TidyResult? tidyWord({
  required List<Stroke> wordStrokes,
  required LineContext line,
  required PageContext page,
  required TidySettings settings,
  Stroke? previousWordLastStroke,
  String? wordId,
  TidyConfig? config,
}) =>
    tidyWordDetailed(
      wordStrokes: wordStrokes,
      line: line,
      page: page,
      settings: settings,
      previousWordLastStroke: previousWordLastStroke,
      wordId: wordId,
      config: config,
    ).result;

/// The whole tidy pipeline for one word (spec steps 0 to 5).
///
/// Uses each stroke's `raw` points and never modifies a stroke. Pure: it
/// reads [line] and [page] but changes neither; call [PageContext.recordWord]
/// with the decision's record afterwards (or use [tidyWordOnPage]).
TidyDecision tidyWordDetailed({
  required List<Stroke> wordStrokes,
  required LineContext line,
  required PageContext page,
  required TidySettings settings,
  Stroke? previousWordLastStroke,
  String? wordId,
  TidyConfig? config,
}) {
  final cfg = config ?? page.config;
  if (wordStrokes.isEmpty) return const TidyDecision.skipped(SkipReason.empty);
  for (final s in wordStrokes) {
    if (s.isHighlighter) {
      return const TidyDecision.skipped(SkipReason.highlighter);
    }
    if (s.shape != null) return const TidyDecision.skipped(SkipReason.shape);
    if (s.tidy.locked) return const TidyDecision.skipped(SkipReason.locked);
  }

  // Strokes without a single finite point carry no ink: ignore them.
  final strokes = <Stroke>[];
  final positions = <List<Vec2>>[];
  for (final s in wordStrokes) {
    final p = sanitizePositions(s.raw);
    if (p == null) continue;
    strokes.add(s);
    positions.add(p);
  }
  if (strokes.isEmpty) {
    return const TidyDecision.skipped(SkipReason.noFinitePoints);
  }
  final id = wordId ?? strokes.first.wordId ?? 'w:${strokes.first.id}';

  // ---- Step 3: features, with the running context as fallback ----------
  final xHint = page.xHeightEstimate(line);
  final analysis = analyzeWord(
    strokes,
    config: cfg,
    context: FeatureContext(
      lineSkew: line.skew,
      lineSlant: line.slant,
      lineWordCount: line.tidiedWordCount,
      expectedXHeight: line.xHeight ?? page.xHeight,
      scaleHintPt: xHint,
      tallRatio: page.tallRatio,
    ),
  );
  if (analysis == null) {
    return const TidyDecision.skipped(SkipReason.noFinitePoints);
  }

  final cx = (analysis.coreBounds.left + analysis.coreBounds.right) / 2;
  final skipRecord = WordRecord(
    wordId: id,
    bounds: analysis.bounds,
    baselineCenter: analysis.baselinePointAt(cx),
    baselineSlope: analysis.baseline.line.slope,
    tidied: false,
    strokeIds: [for (final s in strokes) s.id],
  );
  TidyDecision skip(SkipReason r) =>
      TidyDecision.skipped(r, record: skipRecord);

  // ---- Step 2: when not to tidy ----------------------------------------
  final xRef = analysis.xHeight.reliable
      ? analysis.xHeight.xHeight
      : analysis.scaleHint;
  if (analysis.sampleCount < cfg.minPointsForTidy ||
      !(analysis.xHeight.xHeight > 1e-6) ||
      !analysis.xHeight.xHeight.isFinite) {
    return skip(SkipReason.tooFewPoints);
  }
  if (analysis.bounds.height > cfg.maxWordHeightFactor * page.lineHeight(line)) {
    return skip(SkipReason.tooTall);
  }
  for (final s in strokes) {
    final b = finiteBounds(s.raw)!;
    if (b.width > cfg.maxStrokeWidthFactor * xRef &&
        b.height < cfg.underlineMaxHeightFactor * xRef) {
      return skip(SkipReason.underline);
    }
  }
  if (page.overlapsTidied(analysis.bounds, exceptId: id)) {
    return skip(SkipReason.overlapsTidied);
  }
  if (analysis.skewReliable &&
      analysis.wordSkew.abs() > degToRad(cfg.maxSkewDeg)) {
    return skip(SkipReason.excessiveSkew);
  }
  if (analysis.slant.reliable &&
      analysis.slant.angle.abs() > degToRad(cfg.maxSlantDeg)) {
    return skip(SkipReason.excessiveSlant);
  }

  // ---- Step 4: targets --------------------------------------------------
  final s = settings.strength.clamp(0.0, 1.0);
  final targetX = page.targetXHeight(analysis.xHeight.xHeight);
  final targetTall = page.targetTallHeight(targetX);
  // Without a reliable lean (and none to borrow) there is nothing to correct
  // from, so the lean is left alone rather than "corrected" from a guess.
  final slantKnown = analysis.slant.reliable || line.slant != null;
  final double? targetSlant = slantKnown
      ? page.targetSlant(settings.slantMode, analysis.slant.angle)
      : null;
  final lineHeight = page.lineHeight(line);
  double? targetBaseline(double x, double measuredY) {
    if (page.isRuled) return page.nearestRuledLine(measuredY);
    final lb = line.baselineAt(x);
    if (lb == null || (lb - measuredY).abs() > cfg.snapMaxDistanceFactor * lineHeight) {
      return null; // first word of a line (or far away): its own baseline
    }
    return lb;
  }

  // ---- Step 5a: word transform -----------------------------------------
  final wt = buildWordTransform(
    analysis: analysis,
    strength: s,
    targetXHeight: targetX,
    targetSlant: targetSlant,
    targetBaseline: targetBaseline,
    config: cfg,
  );
  final moved = [
    for (final p in positions) [for (final v in p) wt.matrix.apply(v)],
  ];

  // ---- Step 5b: per-stroke alignment -----------------------------------
  final line0 = analysis.baseline.line;
  final a0 = wt.matrix.apply(Vec2(analysis.coreBounds.left, line0.yAt(analysis.coreBounds.left)));
  final b0 = wt.matrix.apply(Vec2(analysis.coreBounds.right, line0.yAt(analysis.coreBounds.right)));
  final slopeAfter = (b0.x - a0.x).abs() > 1e-9 ? (b0.y - a0.y) / (b0.x - a0.x) : 0.0;
  double baseAt(double x) => a0.y + slopeAfter * (x - a0.x);
  final aligned = alignStrokes(
    strokes: moved,
    shapes: analysis.strokes,
    baselineAt: baseAt,
    targetXHeight: targetX,
    targetTallHeight: targetTall,
    strength: s,
    config: cfg,
  );

  // ---- Step 5c: spacing -------------------------------------------------
  final boxAfter = InkRect.fromPoints([for (final p in aligned) ...p]);
  final double? previousRight = previousWordLastStroke != null
      ? finiteBounds(previousWordLastStroke.points)?.right
      : line.lastWord?.bounds.right;
  final dx = spacingShift(
    wordBounds: boxAfter,
    previousRight: previousRight,
    targetXHeight: targetX,
    strength: s,
    pageWidth: page.width,
    config: cfg,
  );

  // ---- Step 5d: build the display points and smooth them ---------------
  final newPoints = <String, List<InkPoint>>{};
  for (var i = 0; i < strokes.length; i++) {
    final raw = strokes[i].raw;
    final pos = aligned[i];
    final pts = [
      for (var k = 0; k < raw.length; k++)
        InkPoint(pos[k].x + dx, pos[k].y,
            raw[k].pressure.isFinite ? raw[k].pressure : 0.5, raw[k].t),
    ];
    newPoints[strokes[i].id] = smoothPoints(pts, config: cfg);
  }

  final tidiedBounds = InkRect.fromPoints([
    for (final pts in newPoints.values) for (final p in pts) p.pos,
  ]);
  final matrix = Affine2.translation(dx, 0) * wt.matrix;
  final tidiedBase = Seg(matrix.apply(Vec2(analysis.coreBounds.left, line0.yAt(analysis.coreBounds.left))),
      matrix.apply(Vec2(analysis.coreBounds.right, line0.yAt(analysis.coreBounds.right))));

  // ---- Bookkeeping for the context and the debug overlay ---------------
  final center = matrix.apply(analysis.baselinePointAt(cx));
  final record = WordRecord(
    wordId: id,
    bounds: tidiedBounds,
    baselineCenter: center,
    baselineSlope: slopeAfter,
    tidied: true,
    strokeIds: [for (final st in strokes) st.id],
    xHeight: analysis.xHeight.reliable ? analysis.xHeight.xHeight : null,
    slant: analysis.slant.reliable ? analysis.slant.angle : null,
    skew: analysis.skewReliable ? analysis.wordSkew : null,
    tallRatio: analysis.tallRatio,
  );

  final up = const Vec2(0, -1).rotate(analysis.skew);
  final xh = analysis.xHeight.xHeight;
  final rawBase = Seg(
      Vec2(analysis.coreBounds.left, line0.yAt(analysis.coreBounds.left)),
      Vec2(analysis.coreBounds.right, line0.yAt(analysis.coreBounds.right)));
  final lean = analysis.slant.angle + analysis.skew; // lean in the raw frame
  final slantBase = analysis.baselinePointAt(cx);
  final features = WordFeatures(
    skew: analysis.skew,
    wordSkew: analysis.wordSkew,
    skewReliable: analysis.skewReliable,
    slant: analysis.slant.angle,
    slantReliable: analysis.slant.reliable,
    xHeight: xh,
    xHeightReliable: analysis.xHeight.reliable,
    allCaps: analysis.xHeight.allCaps,
    scale: wt.scale,
    targetXHeight: targetX,
    targetSlant: targetSlant,
    snapped: wt.snapped,
    baseline: rawBase,
    xHeightLine: Seg(rawBase.a + up * xh, rawBase.b + up * xh),
    slantLine: Seg(
        slantBase,
        slantBase +
            Vec2(math.sin(lean), -math.cos(lean)) *
                (analysis.xHeight.allCaps ? xh * page.targetTallHeight(1.0) : xh * 2)),
    bounds: analysis.bounds,
    tidiedBaseline: tidiedBase,
    tidiedXHeightLine: Seg(tidiedBase.a + Vec2(0, -xh * wt.scale),
        tidiedBase.b + Vec2(0, -xh * wt.scale)),
    tidiedBounds: tidiedBounds,
    strokeClasses: {
      for (final sh in analysis.strokes) sh.strokeId: sh.strokeClass,
    },
  );

  return TidyDecision.tidied(TidyResult(
    wordId: id,
    newPoints: newPoints,
    wordTransform: matrix,
    features: features,
    record: record,
  ));
}

/// Convenience for the editor: finds the line for the word, tidies it and
/// records it (tidied or skipped) on [page] so the next word sees it.
TidyDecision tidyWordOnPage({
  required List<Stroke> wordStrokes,
  required PageContext page,
  required TidySettings settings,
  String? wordId,
  Stroke? previousWordLastStroke,
  TidyConfig? config,
}) {
  final cfg = config ?? page.config;
  InkRect? box;
  for (final s in wordStrokes) {
    final b = finiteBounds(s.raw);
    if (b != null) box = box == null ? b : box.union(b);
  }
  if (box == null) {
    return TidyDecision.skipped(
        wordStrokes.isEmpty ? SkipReason.empty : SkipReason.noFinitePoints);
  }
  final baselineY = estimateBaselineY(
          [for (final s in wordStrokes) s.raw],
          scaleHint: page.xHeightEstimate(page.lastLine),
          config: cfg) ??
      box.bottom;
  final line = page.lineFor(baselineY, box.center.x);
  final decision = tidyWordDetailed(
    wordStrokes: wordStrokes,
    line: line,
    page: page,
    settings: settings,
    previousWordLastStroke: previousWordLastStroke,
    wordId: wordId,
    config: cfg,
  );
  final record = decision.wordRecord;
  if (record != null) page.recordWord(line, record);
  return decision;
}

/// Rebuilds a page's running context from stored strokes (spec step 7: done
/// lazily when a page is opened, never persisted). Strokes are grouped by
/// `wordId`; each group is measured where it is displayed now. Words whose
/// strokes were tidied count as tidied, the others only occupy their line.
void rebuildPageContext(PageContext page, List<Stroke> strokes,
    {TidyConfig? config}) {
  final cfg = config ?? page.config;
  final groups = <String, List<Stroke>>{};
  for (final s in strokes) {
    final w = s.wordId;
    if (w == null || s.isHighlighter || s.shape != null) continue;
    groups.putIfAbsent(w, () => []).add(s);
  }
  groups.forEach((id, group) {
    final a = analyzeWord(group,
        config: cfg,
        useRaw: false,
        context: FeatureContext(
            expectedXHeight: page.xHeight,
            scaleHintPt: page.xHeightEstimate(page.lastLine),
            tallRatio: page.tallRatio));
    if (a == null) return;
    final cx = (a.coreBounds.left + a.coreBounds.right) / 2;
    final base = a.baselinePointAt(cx);
    final line = page.lineFor(base.y, cx);
    final tidied = group.any((s) => s.tidy.applied);
    page.recordWord(
        line,
        WordRecord(
          wordId: id,
          bounds: a.bounds,
          baselineCenter: base,
          baselineSlope: a.baseline.line.slope,
          tidied: tidied,
          strokeIds: [for (final s in group) s.id],
          xHeight: tidied && a.xHeight.reliable ? a.xHeight.xHeight : null,
          slant: tidied && a.slant.reliable ? a.slant.angle : null,
          skew: tidied && a.skewReliable ? a.wordSkew : null,
          tallRatio: tidied ? a.tallRatio : null,
        ));
  });
}
