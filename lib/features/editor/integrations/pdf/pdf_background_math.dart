import 'dart:math' as math;

import '../../../../pdf/pdf_engine.dart';

/// Widest thumbnail background render, in pixels.
const int maxThumbnailBackgroundPx = 2048;

/// The full-page region to render for a thumbnail that shows a page of
/// [pageWidthPt] x [pageHeightPt] at [pixelsPerPoint]. Null for a page
/// without a usable size.
PdfRenderRegion? thumbnailRegion(
    double pageWidthPt, double pageHeightPt, double pixelsPerPoint) {
  if (!(pageWidthPt > 0) || !(pageHeightPt > 0) || !(pixelsPerPoint > 0)) {
    return null;
  }
  final w = math.min(maxThumbnailBackgroundPx,
      math.max(1, (pageWidthPt * pixelsPerPoint).ceil()));
  final h = math.max(1, (w * pageHeightPt / pageWidthPt).round());
  return PdfRenderRegion(fullWidth: w, fullHeight: h);
}
