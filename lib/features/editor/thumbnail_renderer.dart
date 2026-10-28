import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../render/paper_painter.dart';
import 'canvas/page_painting.dart';
import 'editor_extensions.dart';

/// Default width of the library cover thumbnail, in pixels.
const double defaultThumbnailWidth = 320;

/// Renders one page (paper or PDF background, then images, highlighter,
/// text boxes and pen ink, in the same order as the screen) to PNG bytes
/// [width] pixels wide. Returns null for a page without a usable size.
///
/// [imageLayer] and [textLayer] are awaited in `prepare` first, so pictures
/// and fonts are ready when the page is painted. [pdfBackground] paints PDF
/// pages; without it they get a plain white background.
Future<Uint8List?> renderPageThumbnail(
  PagePaintContext context, {
  double width = defaultThumbnailWidth,
  PageLayerPainter? imageLayer,
  PageLayerPainter? textLayer,
  ThumbnailBackgroundPainter? pdfBackground,
}) async {
  final page = context.page;
  if (!(page.width > 0) || !(page.height > 0) || !(width > 0)) return null;
  final pixelsPerPoint = width / page.width;
  final w = width.round();
  final h = (page.height * pixelsPerPoint).round().clamp(1, 8192);

  await imageLayer?.prepare(context);
  await textLayer?.prepare(context);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  final pixelSize = Size(w.toDouble(), h.toDouble());
  if (page.isPdf) {
    paintPdfPageFrame(canvas, pixelSize, page);
  } else {
    // Paper is painted in pixels (not under the point scale) so its
    // minimum line width keeps the ruling visible at thumbnail size.
    paintPaper(canvas, pixelSize, page.paper, page.width, page.height);
  }
  canvas.scale(pixelsPerPoint);
  if (page.isPdf && pdfBackground != null) {
    await pdfBackground(canvas, context, pixelsPerPoint);
  }
  paintPageContent(canvas, context,
      imageLayer: imageLayer, textLayer: textLayer);

  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(w, h);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}
