/// Every tuning number of the "tidy as you write" pipeline lives here
/// (docs/beautify-spec.md, "Tuning constants"). Nothing else in
/// `lib/beautify/` hard-codes a threshold: the pipeline receives a
/// [TidyConfig] so tests (and the owner, with the debug overlay) can change
/// any value.
///
/// Units: `…Pt` values are page points, `…Ms` values milliseconds, `…Deg`
/// values degrees. `…Factor` values multiply an x-height, a line height or a
/// line spacing, as each doc comment says.
library;

/// How "Keep my slant" vs "Upright" picks the target slant (spec step 4).
enum TidySlantMode {
  /// Make the lean consistent: target = running median of recent words.
  keep,

  /// Stand words up: target slant = 0.
  upright,
}

/// The user-facing tidy settings, already reduced to numbers.
class TidySettings {
  const TidySettings({
    this.strength = mediumStrength,
    this.slantMode = TidySlantMode.keep,
  });

  /// Blend amount for "Light" (spec step 5).
  static const double lightStrength = 0.5;

  /// Blend amount for "Medium" (the default).
  static const double mediumStrength = 0.8;

  /// Blend amount for "Strong".
  static const double strongStrength = 1.0;

  static const TidySettings light = TidySettings(strength: lightStrength);
  static const TidySettings medium = TidySettings(strength: mediumStrength);
  static const TidySettings strong = TidySettings(strength: strongStrength);

  /// Blend factor `s` in [0, 1]: each correction moves `s` of the way from
  /// "no change" to its ideal value.
  final double strength;
  final TidySlantMode slantMode;

  TidySettings copyWith({double? strength, TidySlantMode? slantMode}) =>
      TidySettings(
        strength: strength ?? this.strength,
        slantMode: slantMode ?? this.slantMode,
      );

  @override
  bool operator ==(Object other) =>
      other is TidySettings &&
      other.strength == strength &&
      other.slantMode == slantMode;

  @override
  int get hashCode => Object.hash(strength, slantMode);
}

/// All tuning constants of the tidy pipeline, with the spec's defaults.
class TidyConfig {
  const TidyConfig({
    this.resampleStepPt = 1.0,
    this.wordIdleMs = 650,
    this.wordGapFactor = 0.9,
    this.newLineFactor = 0.7,
    this.blankLineHeightFactor = 2.5,
    this.initialXHeightRuledFactor = 0.4,
    this.initialXHeightPt = 9.0,
    this.smallMarkFactor = 0.45,
    this.lateStrokeMaxWidthFactor = 1.5,
    this.lateStrokeMaxHeightFactor = 0.3,
    this.lateMarkBoxPadFactor = 0.3,
    this.maxWordHeightFactor = 2.2,
    this.maxStrokeWidthFactor = 12,
    this.underlineMaxHeightFactor = 0.5,
    this.minPointsForTidy = 12,
    this.maxTidiedOverlapFraction = 0.5,
    this.maxSkewDeg = 20,
    this.maxSlantDeg = 40,
    this.extremaWindow = 3,
    this.extremaMinDropFactor = 0.05,
    this.extremaScaleBboxFactor = 0.4,
    this.descenderExtremaFactor = 0.35,
    this.outlierResidualFactor = 2.0,
    this.outlierResidualFloorFactor = 0.03,
    this.minWidthForSkew = 2.5,
    this.minExtremaForSkew = 3,
    this.wordSkewWeight = 0.6,
    this.minLineWordsForSkewBlend = 2,
    this.xHeightReferenceQuantile = 0.25,
    this.minTopHeightFraction = 0.3,
    this.ascenderTopFactor = 1.45,
    this.allCapsDropFraction = 0.6,
    this.xHeightFallbackFactor = 0.45,
    this.slantMaxFromVerticalDeg = 45,
    this.slantMinSegmentPt = 0.5,
    this.slantMinTotalLengthFactor = 1.5,
    this.descenderFactor = 0.35,
    this.tallFactor = 1.45,
    this.lineXFactor = 0.36,
    this.snapMaxDistanceFactor = 0.5,
    this.xHeightWindow = 12,
    this.slantWindow = 20,
    this.tallRatioWindow = 20,
    this.defaultTallRatio = 1.9,
    this.minTallRatio = 1.6,
    this.maxTallRatio = 2.4,
    this.minScale = 0.75,
    this.maxScale = 1.35,
    this.minNonMarkStrokesForAlignment = 2,
    this.perStrokeMaxGapFactor = 0.3,
    this.maxPerStrokeScale = 0.15,
    this.minStrokeHeightForScaleFactor = 0.5,
    this.wordSpaceFactor = 1.0,
    this.maxSpacingShiftFactor = 0.8,
    this.maxSpacingGapFactor = 3.0,
    this.pageRightMarginPt = 8.0,
    this.smoothingNeighbourWeight = 0.25,
    this.minPointsForSmoothing = 5,
    this.lineGroupFactor = 0.5,
    this.animMs = 180,
    this.slowWordWarnMs = 8,
    this.unreliableXHeightBlend = 0.5,
    this.overlapMinBoxPt = 1.0,
    this.rememberedWordLimit = 400,
    this.baselineInlierTolFactor = 0.15,
    this.baselinePairMinDxFactor = 0.5,
    this.baselineCandidateMaxSkewDeg = 35,
    this.baselineMaxRansacPoints = 60,
  });

  // ---- Step 0: preprocessing -------------------------------------------

  /// Analysis resampling distance (pt). Resampled points are never stored.
  final double resampleStepPt;

  // ---- Step 1: word segmentation ---------------------------------------

  /// Idle time after the last pen-up that ends a word.
  final int wordIdleMs;

  /// Horizontal gap (× xHeight estimate) that starts a new word.
  final double wordGapFactor;

  /// Vertical jump (× line height) from the pending word's baseline that
  /// starts a new line.
  final double newLineFactor;

  /// Line height on unruled paper, × the x-height estimate.
  final double blankLineHeightFactor;

  /// x-height estimate before any word exists on ruled paper (× spacing).
  final double initialXHeightRuledFactor;

  /// x-height estimate before any word exists on unruled paper (pt).
  final double initialXHeightPt;

  /// Max bounding-box diagonal (× xHeight) of a dot / mark. Used both for
  /// late marks (step 1) and for the "mark" stroke class (step 3d).
  final double smallMarkFactor;

  /// A late "short horizontal" stroke (t-crossing) is narrower than this
  /// (× xHeight) …
  final double lateStrokeMaxWidthFactor;

  /// … and flatter than this (× xHeight).
  final double lateStrokeMaxHeightFactor;

  /// A late mark attaches to a tidied word when it lands inside the word's
  /// box grown by this (× the word's x-height).
  final double lateMarkBoxPadFactor;

  // ---- Step 2: when not to tidy ----------------------------------------

  /// Words taller than this (× line height) are drawings: skip.
  final double maxWordHeightFactor;

  /// A stroke wider than this (× xHeight) …
  final double maxStrokeWidthFactor;

  /// … and flatter than this (× xHeight) is an underline: skip.
  final double underlineMaxHeightFactor;

  /// Fewer resampled points than this: skip.
  final int minPointsForTidy;

  /// Skip a word whose box is covered by another tidied word's box by more
  /// than this fraction (strike-through / scribble).
  final double maxTidiedOverlapFraction;

  /// More measured tilt than this is intentional: skip.
  final double maxSkewDeg;

  /// More measured slant than this is intentional: skip.
  final double maxSlantDeg;

  // ---- Step 3a: baseline and skew --------------------------------------

  /// Extrema must be the max (or min) within ± this many samples.
  final int extremaWindow;

  /// Hysteresis for extrema: the stroke must turn back by at least this
  /// (× the word's scale hint, ≈ x-height) so pen jitter and flat bars
  /// (E, H, t-crossings) do not create extrema.
  final double extremaMinDropFactor;

  /// The scale hint is max(x-height estimate, this × word box height), so
  /// unusually large writing still gets a sensible hysteresis.
  final double extremaScaleBboxFactor;

  /// Bottom extrema lower than median + this × box height are descenders.
  final double descenderExtremaFactor;

  /// Outlier removal drops extrema with residual > this × the median
  /// absolute residual, then refits.
  final double outlierResidualFactor;

  /// Floor for that residual threshold (× scale hint), so near-perfect data
  /// does not lose good points to rounding noise.
  final double outlierResidualFloorFactor;

  /// Words narrower than this (× xHeight) borrow the line's skew.
  final double minWidthForSkew;

  /// Fewer bottom extrema than this: borrow the line's skew.
  final int minExtremaForSkew;

  /// θ_final = w·θ_word + (1 − w)·line.skew once the line has words.
  final double wordSkewWeight;

  /// The line must have at least this many words for that blend.
  final int minLineWordsForSkewBlend;

  // ---- Step 3b: x-height -----------------------------------------------

  /// Reference height for dropping ascender tops: this quantile of the top
  /// heights (see `estimateXHeight` for why not the plain median).
  final double xHeightReferenceQuantile;

  /// Tops lower than this fraction of the tallest top are pen hooks, not
  /// letter tops.
  final double minTopHeightFraction;

  /// Tops higher than this × the reference are ascenders / capitals.
  final double ascenderTopFactor;

  /// More than this fraction of tops dropped means an all-caps word.
  final double allCapsDropFraction;

  /// x-height fallback with fewer than two tops (× box height).
  final double xHeightFallbackFactor;

  // ---- Step 3c: slant --------------------------------------------------

  /// Segments within this angle of vertical count for slant.
  final double slantMaxFromVerticalDeg;

  /// Shorter segments are ignored.
  final double slantMinSegmentPt;

  /// Less near-vertical length than this (× xHeight) is unreliable.
  final double slantMinTotalLengthFactor;

  // ---- Step 3d: stroke classes -----------------------------------------

  /// Bottom below the baseline by more than this (× xHeight): descender.
  final double descenderFactor;

  /// Top above the baseline by more than this (× xHeight): tall.
  final double tallFactor;

  // ---- Step 4: targets -------------------------------------------------

  /// Target x-height on ruled paper (× spacing).
  final double lineXFactor;

  /// Only snap to a ruled line within this distance (× spacing).
  final double snapMaxDistanceFactor;

  /// Page window sizes: recent x-heights, slants and tall ratios.
  final int xHeightWindow;
  final int slantWindow;
  final int tallRatioWindow;

  /// Tall-stroke height / x-height when nothing is known yet.
  final double defaultTallRatio;

  /// Clamp for the tall target ratio.
  final double minTallRatio;
  final double maxTallRatio;

  // ---- Step 5: transform -----------------------------------------------

  /// Word scale clamp.
  final double minScale;
  final double maxScale;

  /// Per-stroke alignment needs at least this many non-mark strokes.
  final int minNonMarkStrokesForAlignment;

  /// Per-stroke moves only when the gap is below this (× x-height).
  final double perStrokeMaxGapFactor;

  /// Per-stroke vertical scale limit (±).
  final double maxPerStrokeScale;

  /// Strokes shorter than this (× x-height) are never rescaled (flat bars on
  /// the baseline, small loops).
  final double minStrokeHeightForScaleFactor;

  /// Target word gap (× target x-height).
  final double wordSpaceFactor;

  /// Max horizontal spacing shift (× target x-height).
  final double maxSpacingShiftFactor;

  /// Gaps wider than this (× target x-height) are deliberate layout (columns,
  /// a date at the end of a line) and are left alone.
  final double maxSpacingGapFactor;

  /// Spacing never pushes a word closer than this to the page's right edge.
  final double pageRightMarginPt;

  /// 3-point smoothing weights are (w, 1 − 2w, w).
  final double smoothingNeighbourWeight;

  /// Strokes with fewer points are not smoothed.
  final int minPointsForSmoothing;

  // ---- Step 7: running context -----------------------------------------

  /// Words whose baselines are within this (× line height) share a line.
  final double lineGroupFactor;

  // ---- Step 6 / performance --------------------------------------------

  /// Tidy animation length.
  final int animMs;

  /// Words slower than this should be logged by the caller.
  final int slowWordWarnMs;

  // ---- Additions of the implementation (not in the spec table) ---------

  /// When the x-height came from too few letter tops to be trusted (and is
  /// not an all-caps word), the size correction is blended by only this
  /// fraction of the strength, so one odd word is not rescaled by a guess.
  final double unreliableXHeightBlend;

  /// Thickness floor (pt) for a word box when measuring overlap with another
  /// word, so a perfectly flat strike-through line still has an area.
  final double overlapMinBoxPt;

  /// A page remembers at most this many words (oldest forgotten first).
  final int rememberedWordLimit;

  /// Baseline search: an extremum is an inlier of a candidate line when it is
  /// within this (× scale hint) of it.
  final double baselineInlierTolFactor;

  /// Candidate baselines are drawn through pairs of extrema at least this far
  /// apart horizontally (× scale hint), so near-vertical pairs (the ends of a
  /// stem, a column of bar ends) never define a baseline.
  final double baselinePairMinDxFactor;

  /// Candidate baselines steeper than this are ignored.
  final double baselineCandidateMaxSkewDeg;

  /// Above this many extrema the search falls back to plain least squares.
  final int baselineMaxRansacPoints;
}
