/// Every tunable number used by the editor tool logic (spatial index,
/// erasers, lasso, selection transforms, shape recognition, hold detection).
///
/// All lengths are in page points (1 pt = 1/72 inch) and all angles in
/// degrees. Tools take a `ToolConfig` (defaulting to [ToolConfig.defaults])
/// so tests and future settings can tune them without touching the logic.
class ToolConfig {
  const ToolConfig({
    // Spatial index.
    this.spatialCellSizePt = 64,
    this.spatialMaxCellsPerEntry = 1024,
    // Pixel (partial) eraser.
    this.pixelEraserPenWidthFactor = 1.0,
    this.pixelEraserHighlighterWidthFactor = 0.5,
    this.pixelEraserMinPieceLengthPt = 1.0,
    this.pixelEraserMinPiecePoints = 2,
    // Lasso.
    this.lassoStrokeInsideFraction = 0.6,
    this.lassoItemMinCornersInside = 2,
    this.lassoTapMaxAreaPt2 = 25,
    this.tapHitRadiusPt = 5,
    // Selection transform.
    this.minSelectionSizePt = 8,
    this.minFontSizePt = 4,
    // Shape recognition: input preparation.
    this.shapeMinPathLengthPt = 10,
    this.shapeDwellRadiusPt = 3,
    this.shapeDwellMs = 100,
    this.shapeAnalysisSamples = 128,
    this.shapeMinSpacingPt = 0.5,
    this.shapeMaxSpacingPt = 4,
    // Shape recognition: output.
    this.shapeOutputSpacingPt = 2,
    this.shapeOutputPressure = 0.5,
    // Lines.
    this.lineMinLengthPt = 10,
    this.lineMaxDeviationFraction = 0.05,
    this.lineDeviationSlackPt = 1.0,
    this.lineMaxPathRatio = 1.15,
    this.lineAngleSnapDeg = 4,
    // Closed shapes.
    this.closedGapFraction = 0.2,
    this.closedSearchStartFraction = 0.6,
    this.closedMinDiameterPt = 12,
    // Polygon (corner) detection.
    this.polygonToleranceFraction = 0.035,
    this.polygonToleranceMinPt = 1.0,
    this.polygonToleranceMaxPt = 8,
    this.polygonMergeAngleDeg = 20,
    this.polygonMergeErrorFactor = 1.5,
    this.polygonShortEdgeFraction = 0.1,
    this.polygonMaxVertices = 40,
    this.polygonRejectTurnDeg = 40,
    this.hookMaxFraction = 0.05,
    this.hookMaxPt = 3,
    this.sideTrimFraction = 0.15,
    // Rectangles.
    this.rectCornerAngleTolDeg = 25,
    this.rectSideAngleTolDeg = 18,
    this.rectAxisSnapDeg = 6,
    this.rectMinSideFraction = 0.08,
    this.rectMinSidePt = 3,
    // Triangles.
    this.triangleMinAngleDeg = 20,
    this.triangleCornerShiftFraction = 0.25,
    // Ellipses.
    this.ellipseMeanErrorMax = 0.07,
    this.ellipseMaxErrorMax = 0.2,
    this.ellipseMaxAngularGapDeg = 70,
    this.circleAxisRatio = 0.88,
    this.ellipseAxisSnapDeg = 6,
    this.ellipseTurnToleranceDeg = 60,
    // Arrows.
    this.arrowMinShaftPt = 16,
    this.arrowMinBarbFraction = 0.08,
    this.arrowMinBarbPt = 3,
    this.arrowMaxBarbFraction = 0.6,
    this.arrowMinBarbRatio = 0.35,
    this.arrowBarbMinAngleDeg = 12,
    this.arrowBarbMaxAngleDeg = 75,
    this.arrowTipToleranceFraction = 0.4,
    this.arrowBuildBarbFraction = 0.2,
    this.arrowBuildMinBarbPt = 8,
    this.arrowBuildMaxBarbPt = 28,
    this.arrowBuildBarbAngleDeg = 28,
    // Hold-to-snap.
    this.holdDurationMs = 500,
    this.holdRadiusPt = 3,
    this.holdMinPathLengthPt = 15,
    // Shape tool.
    this.shapeToolSquareSnapFraction = 0.06,
    this.shapeToolMinDragPt = 4,
    // Scribble to delete.
    this.scribbleMinPoints = 8,
    this.scribbleMinWidthPt = 8,
    this.scribbleMinSwingPt = 3,
    this.scribbleMinReversals = 4,
    this.scribbleSwingFraction = 0.3,
    this.scribbleMinPathRatio = 2.5,
    this.scribbleZigzagMinReversals = 5,
    this.scribbleZigzagSwingFraction = 0.6,
    this.scribbleZigzagMinPathRatio = 1.8,
    this.scribbleMarginPt = 2,
    this.scribbleStrokeInsideFraction = 0.6,
    this.scribbleAcrossFraction = 0.6,
    this.scribbleDownFraction = 0.35,
    this.scribbleMinContentFraction = 0.3,
    this.scribbleClosedGapFraction = 0.2,
  });

  /// The values the app ships with.
  static const ToolConfig defaults = ToolConfig();

  // ---------------------------------------------------------------- index

  /// Side of one grid cell of the spatial index. About a word wide, so a
  /// typical eraser or tap query touches 1–4 cells.
  final double spatialCellSizePt;

  /// Items covering more cells than this (huge shapes, far-off coordinates)
  /// go to an always-checked overflow list instead of the grid.
  final int spatialMaxCellsPerEntry;

  // ------------------------------------------------------------- erasers

  /// The pixel eraser cuts pen strokes where the eraser circle comes within
  /// `radius + factor × width / 2` of the centre line. With 1.0 and round
  /// caps, the visible gap matches the eraser's footprint.
  final double pixelEraserPenWidthFactor;

  /// Same for highlighters, whose ends are flat (no cap eats into the gap),
  /// so only half the width is added.
  final double pixelEraserHighlighterWidthFactor;

  /// Pixel-eraser pieces shorter than this are dropped.
  final double pixelEraserMinPieceLengthPt;

  /// Pixel-eraser pieces with fewer points than this are dropped.
  final int pixelEraserMinPiecePoints;

  // --------------------------------------------------------------- lasso

  /// A stroke is lassoed when at least this fraction of its points is inside.
  final double lassoStrokeInsideFraction;

  /// A text box or image is lassoed when its centre is inside or at least
  /// this many of its 4 corners are.
  final int lassoItemMinCornersInside;

  /// A lasso enclosing less area than this (pt²) is treated as a tap.
  final double lassoTapMaxAreaPt2;

  /// How far from a stroke (beyond its half width) or item a tap still hits.
  final double tapHitRadiusPt;

  // ---------------------------------------------------- selection editing

  /// Resizing never makes a selection smaller than this (unless it already
  /// was).
  final double minSelectionSizePt;

  /// Corner resizes never shrink a text box's font below this.
  final double minFontSizePt;

  // ----------------------------------------------- shapes: input handling

  /// Strokes shorter than this are never shapes.
  final double shapeMinPathLengthPt;

  /// A pen resting within this radius at the start or end of a stroke...
  final double shapeDwellRadiusPt;

  /// ...for at least this long is collapsed to one point before analysis
  /// (e.g. the hold-to-snap pause).
  final int shapeDwellMs;

  /// Analysis resamples the stroke to about this many points.
  final int shapeAnalysisSamples;

  /// Bounds of the analysis resampling step.
  final double shapeMinSpacingPt;
  final double shapeMaxSpacingPt;

  // ------------------------------------------------------ shapes: output

  /// Spacing of the generated shape's points.
  final double shapeOutputSpacingPt;

  /// Constant pressure of the generated shape's points.
  final double shapeOutputPressure;

  // ---------------------------------------------------------------- lines

  /// Minimum start-to-end distance of a line.
  final double lineMinLengthPt;

  /// Max distance of any point from the chord, as a fraction of its length,
  /// plus [lineDeviationSlackPt].
  final double lineMaxDeviationFraction;
  final double lineDeviationSlackPt;

  /// Max path length / chord length. Rejects zigzags and squiggles whose
  /// points all stay near the chord.
  final double lineMaxPathRatio;

  /// Lines (and arrow shafts) within this of 0/45/90/135° snap to it.
  final double lineAngleSnapDeg;

  // ------------------------------------------------------- closed shapes

  /// A stroke is closed when it comes back within this fraction of its
  /// bounding-box diagonal of its start.
  final double closedGapFraction;

  /// Only points after this fraction of the path length can close the loop.
  final double closedSearchStartFraction;

  /// Closed loops smaller than this (max of width and height) never snap,
  /// so handwritten "o", "e" or "a" stay letters.
  final double closedMinDiameterPt;

  // ---------------------------------------------------- corner detection

  /// Douglas–Peucker tolerance as a fraction of the bounding-box diagonal,
  /// clamped to [polygonToleranceMinPt, polygonToleranceMaxPt].
  final double polygonToleranceFraction;
  final double polygonToleranceMinPt;
  final double polygonToleranceMaxPt;

  /// Vertices turning less than this are merged away (wobbly sides)...
  final double polygonMergeAngleDeg;

  /// ...if the merged side still fits the ink within this × tolerance.
  final double polygonMergeErrorFactor;

  /// Closed shapes: two corners closer than this fraction of the diagonal
  /// that turn the same way are one rounded corner.
  final double polygonShortEdgeFraction;

  /// More corners than this means "not a polygon"; skips the merge work.
  final int polygonMaxVertices;

  /// A closed 5-corner polygon whose corners all turn at least this much is
  /// a pentagon, which we can't draw, so recognition gives up.
  final double polygonRejectTurnDeg;

  /// Open shapes: a first/last side shorter than this fraction of the
  /// longest side (and than [hookMaxPt]) is a pen-down/up hook and dropped.
  final double hookMaxFraction;
  final double hookMaxPt;

  /// Fraction of each side's points ignored at both ends when fitting the
  /// side (corners are rounded in hand drawing).
  final double sideTrimFraction;

  // ----------------------------------------------------------- rectangles

  /// Each corner must turn 90° ± this.
  final double rectCornerAngleTolDeg;

  /// Each side must be within this of the rectangle's axes.
  final double rectSideAngleTolDeg;

  /// Rectangles (and ellipses, see [ellipseAxisSnapDeg]) within this of
  /// axis-aligned become exactly axis-aligned.
  final double rectAxisSnapDeg;

  /// Shortest side ≥ this fraction of the longest side, and ≥
  /// [rectMinSidePt].
  final double rectMinSideFraction;
  final double rectMinSidePt;

  // ------------------------------------------------------------ triangles

  /// Every interior angle must be at least this.
  final double triangleMinAngleDeg;

  /// A corner refined by intersecting fitted sides may move at most this
  /// fraction of the shortest side from the detected corner.
  final double triangleCornerShiftFraction;

  // ------------------------------------------------------------- ellipses

  /// Mean and max of |normalized radius − 1| over the ink.
  final double ellipseMeanErrorMax;
  final double ellipseMaxErrorMax;

  /// Largest angle around the centre not covered by ink.
  final double ellipseMaxAngularGapDeg;

  /// Minor/major axis ratio at or above which the ellipse becomes a circle
  /// (0.88 = axes within about 12%).
  final double circleAxisRatio;

  /// Ellipses within this of axis-aligned become exactly axis-aligned.
  final double ellipseAxisSnapDeg;

  /// The loop's total turning must be 360° ± this (one simple loop; rejects
  /// figure eights and double loops).
  final double ellipseTurnToleranceDeg;

  // --------------------------------------------------------------- arrows

  /// Minimum shaft length.
  final double arrowMinShaftPt;

  /// Each barb is at least this fraction of the shaft and [arrowMinBarbPt],
  /// and at most [arrowMaxBarbFraction] of the shaft.
  final double arrowMinBarbFraction;
  final double arrowMinBarbPt;
  final double arrowMaxBarbFraction;

  /// Shorter barb / longer barb.
  final double arrowMinBarbRatio;

  /// Angle between each barb and the shaft (pointing back from the tip).
  final double arrowBarbMinAngleDeg;
  final double arrowBarbMaxAngleDeg;

  /// When the head is drawn by going back to the tip, the return must land
  /// within this fraction of the longer barb from the tip.
  final double arrowTipToleranceFraction;

  /// Arrows built by the shape tool: each barb is this fraction of the shaft
  /// long, clamped to [arrowBuildMinBarbPt, arrowBuildMaxBarbPt]...
  final double arrowBuildBarbFraction;
  final double arrowBuildMinBarbPt;
  final double arrowBuildMaxBarbPt;

  /// ...and makes this angle with the shaft.
  final double arrowBuildBarbAngleDeg;

  // ----------------------------------------------------------------- hold

  /// The pen must stay still this long at the end of a stroke...
  final int holdDurationMs;

  /// ...within this radius...
  final double holdRadiusPt;

  /// ...after drawing more than this much ink.
  final double holdMinPathLengthPt;

  // ----------------------------------------------------------- shape tool

  /// A dragged rectangle / ellipse whose width and height differ by less than
  /// this fraction becomes a square / circle.
  final double shapeToolSquareSnapFraction;

  /// A shape-tool drag shorter than this draws nothing (an accidental tap).
  final double shapeToolMinDragPt;

  // ------------------------------------------------------ scribble to delete

  /// A scribble (a scratch-out over writing or typed text) has at least this
  /// many points and is at least this long along its main direction, and
  /// every swing counted below is at least [scribbleMinSwingPt].
  final int scribbleMinPoints;
  final double scribbleMinWidthPt;
  final double scribbleMinSwingPt;

  /// It goes back and forth along its main direction at least this many
  /// times, each swing at least this fraction of its length, with a path at
  /// least this many times its length...
  final int scribbleMinReversals;
  final double scribbleSwingFraction;
  final double scribbleMinPathRatio;

  /// ...or it zig-zags across that direction ("\/\/\/"): at least this many
  /// turns, each at least this fraction of its height, with a path at least
  /// this many times its length.
  final int scribbleZigzagMinReversals;
  final double scribbleZigzagSwingFraction;
  final double scribbleZigzagMinPathRatio;

  /// The scribble's area is its bounds grown by this much.
  final double scribbleMarginPt;

  /// A stroke is scribbled out when at least [scribbleStrokeInsideFraction]
  /// of its points lie in the area, or when the area covers at least
  /// [scribbleAcrossFraction] of its width and [scribbleDownFraction] of its
  /// height (a tall `l` crossed out through the middle). A word of typed
  /// text by the second rule.
  final double scribbleStrokeInsideFraction;
  final double scribbleAcrossFraction;
  final double scribbleDownFraction;

  /// What it covers must fill at least this fraction of the scribble's area,
  /// or the scribble is a drawing (or writing) that happens to cross
  /// something, and stays.
  final double scribbleMinContentFraction;

  /// A stroke whose ends are closer than this fraction of its size is a
  /// closed outline (a circle, a box, a cell drawn by hand). One around the
  /// whole scribble stays: that is shading inside a drawing.
  final double scribbleClosedGapFraction;
}
