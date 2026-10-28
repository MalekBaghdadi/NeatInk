import 'dart:math' as math;

import '../ink/affine2.dart';

/// Mapping from app page coordinates to PDF user space.
///
/// This file mirrors `PdfCoords.kt` (the PdfBox exporter) line for line, so
/// the math can be unit-tested in Dart. Change both together.
///
/// App coordinates: points, origin at the top-left of the page *as
/// displayed* (after /Rotate), y pointing down.
///
/// PDF user space: points, origin at the bottom-left of the unrotated page,
/// y pointing up. The visible area is the CropBox (clipped to the MediaBox),
/// whose lower-left corner is often not (0, 0). Viewers show the page turned
/// clockwise by /Rotate degrees.

/// A rectangle in PDF user space (y up).
class PdfBox {
  const PdfBox(this.left, this.bottom, this.right, this.top);

  /// Builds a box from any two opposite corners, like PDF rectangle arrays
  /// (`[x1 y1 x2 y2]` in any order).
  factory PdfBox.fromCorners(double x1, double y1, double x2, double y2) =>
      PdfBox(math.min(x1, x2), math.min(y1, y2), math.max(x1, x2),
          math.max(y1, y2));

  final double left;
  final double bottom;
  final double right;
  final double top;

  double get width => right - left;
  double get height => top - bottom;

  bool get isEmpty => width <= 0 || height <= 0;

  @override
  bool operator ==(Object other) =>
      other is PdfBox &&
      other.left == left &&
      other.bottom == bottom &&
      other.right == right &&
      other.top == top;

  @override
  int get hashCode => Object.hash(left, bottom, right, top);

  @override
  String toString() => 'PdfBox($left, $bottom, $right, $top)';
}

/// US Letter, the PDF default when a page has no usable MediaBox.
const PdfBox letterPdfBox = PdfBox(0, 0, 612, 792);

/// The visible box of a page: the CropBox intersected with the MediaBox, or
/// the MediaBox when the CropBox is missing or the intersection is empty.
/// Same rule as PDFium (what pdfrx shows) and PdfBox's `getCropBox()`.
PdfBox visiblePdfBox(PdfBox? mediaBox, PdfBox? cropBox) {
  final media =
      (mediaBox == null || mediaBox.isEmpty) ? letterPdfBox : mediaBox;
  if (cropBox == null || cropBox.isEmpty) return media;
  final clipped = PdfBox(
    math.max(cropBox.left, media.left),
    math.max(cropBox.bottom, media.bottom),
    math.min(cropBox.right, media.right),
    math.min(cropBox.top, media.top),
  );
  return clipped.isEmpty ? media : clipped;
}

/// Number of clockwise quarter turns for a /Rotate value, interpreted like
/// PDFium (`rotate / 90 % 4`, truncating): 90 → 1, -90 → 3, 450 → 1, and
/// values that are not multiples of 90 round toward zero (45 → 0, 135 → 1).
int pdfQuarterTurns(int rotate) =>
    // `~/` truncates toward zero like C; Dart's `%` is never negative.
    (rotate ~/ 90) % 4;

/// Page size as displayed (after rotation) for a visible [box].
({double width, double height}) displayedPdfPageSize(
    PdfBox box, int quarterTurns) {
  final q = quarterTurns % 4;
  return q.isOdd
      ? (width: box.height, height: box.width)
      : (width: box.width, height: box.height);
}

/// The affine map from app coordinates (top-left origin, y down, displayed
/// orientation, page of [appWidth] × [appHeight] points) to PDF user space
/// of a page whose visible box is [box] and which is shown turned clockwise
/// by [quarterTurns] × 90°.
///
/// If the app size differs from the displayed PDF size (rounding, or a page
/// size edited in the app), x and y are scaled to fit.
///
/// The matrix is `[a b c d e f]` with `u = a·x + c·y + e`,
/// `v = b·x + d·y + f`, i.e. exactly the operands of a PDF `cm` operator.
///
/// Derivation: let (X, Y) be the display position scaled to the PDF's
/// displayed size. Turning the unrotated page clockwise by 90° moves its
/// bottom-left corner to the display's top-left, so for each rotation:
///
/// | turns | u (PDF x)   | v (PDF y)   |
/// |-------|-------------|-------------|
/// | 0     | left + X    | top − Y     |
/// | 1     | left + Y    | bottom + X  |
/// | 2     | right − X   | bottom + Y  |
/// | 3     | right − Y   | top − X     |
Affine2 appToPdfMatrix({
  required PdfBox box,
  required int quarterTurns,
  required double appWidth,
  required double appHeight,
}) {
  final q = quarterTurns % 4;
  final shown = displayedPdfPageSize(box, q);
  final sx = appWidth > 0 ? shown.width / appWidth : 1.0;
  final sy = appHeight > 0 ? shown.height / appHeight : 1.0;
  switch (q) {
    case 0:
      return Affine2(sx, 0, 0, -sy, box.left, box.top);
    case 1:
      return Affine2(0, sx, sy, 0, box.left, box.bottom);
    case 2:
      return Affine2(-sx, 0, 0, sy, box.right, box.bottom);
    default:
      return Affine2(0, -sx, -sy, 0, box.right, box.top);
  }
}

/// [box] grown by [left] and [right] PDF units beside the page *as
/// displayed* (turned clockwise by [quarterTurns] × 90°): the visible box of
/// a PDF page given writing margins. Which side of the unrotated box is the
/// displayed left follows the table of [appToPdfMatrix] (where X = 0 lands):
///
/// | turns | displayed left | displayed right |
/// |-------|----------------|-----------------|
/// | 0     | left           | right           |
/// | 1     | bottom         | top             |
/// | 2     | right          | left            |
/// | 3     | top            | bottom          |
PdfBox pdfBoxWithSideMargins(
    PdfBox box, int quarterTurns, double left, double right) {
  switch (quarterTurns % 4) {
    case 0:
      return PdfBox(box.left - left, box.bottom, box.right + right, box.top);
    case 1:
      return PdfBox(box.left, box.bottom - left, box.right, box.top + right);
    case 2:
      return PdfBox(box.left - right, box.bottom, box.right + left, box.top);
    default:
      return PdfBox(box.left, box.bottom - right, box.right, box.top + left);
  }
}
