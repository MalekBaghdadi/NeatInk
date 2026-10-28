import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../../pdf/pdf_page_cache.dart';
import '../../editor_controller.dart';
import '../../editor_extensions.dart';
import 'pdf_background_math.dart';
import 'pdf_page_words.dart';

/// Shows the PDF page behind the ink of PDF-backed notebook pages and in
/// the library thumbnail.
///
/// This is the only integration file that depends on pdfrx (through
/// [PdfPageCache]); keep logic out of it so it stays testable elsewhere.
void installPdfBackground(EditorController controller, {PdfPageCache? cache}) {
  PdfPageCache pages() => cache ?? PdfPageCache.shared;
  String sourcePath(String notebookId) =>
      controller.repository.sourcePdfPath(notebookId);

  controller.extensions.pageTextWords = PdfPageWords(
    controller,
    words: (notebookId, index) => pages().words(sourcePath(notebookId), index),
  );

  controller.extensions.pageBackgroundBuilder = (context, request) {
    final index = request.page.pdfPageIndex;
    if (index == null) return null;
    return ValueListenableBuilder<double>(
      valueListenable: request.viewport.settledScale,
      builder: (context, scale, _) => PdfPageBackground(
        pdfPath: sourcePath(request.notebookId),
        pageIndex: index,
        pageWidthPt: request.page.contentWidth,
        pageHeightPt: request.page.height,
        scale: scale,
        cache: cache,
      ),
    );
  };

  controller.extensions.thumbnailBackground =
      (ui.Canvas canvas, PagePaintContext context, double pixelsPerPoint) async {
    final page = context.page;
    final index = page.pdfPageIndex;
    final region =
        thumbnailRegion(page.contentWidth, page.height, pixelsPerPoint);
    if (index == null || region == null) return;
    final path = sourcePath(context.notebookId);
    final cacheNow = pages();
    cacheNow.retainDocument(path);
    try {
      final image = await cacheNow.request(path, index, region).result;
      if (image == null) return; // The thumbnail keeps its white page.
      try {
        canvas.drawImageRect(
          image.image,
          Rect.fromLTWH(0, 0, image.image.width.toDouble(),
              image.image.height.toDouble()),
          Rect.fromLTWH(
              page.contentLeft, 0, page.contentWidth, page.height),
          Paint()..filterQuality = FilterQuality.medium,
        );
      } finally {
        image.dispose();
      }
    } finally {
      cacheNow.releaseDocument(path);
    }
  };
}
