import 'package:flutter/material.dart';

import '../../../../document/notebook_meta.dart';
import '../../../../document/page_content.dart';
import '../../../../render/paper_painter.dart';
import '../../canvas/page_painting.dart';
import '../../editor_controller.dart';
import '../../editor_extensions.dart';

/// A small live picture of a page: paper, ink, text and images, painted
/// directly (no image encoding). PDF pages show their PDF page under the ink
/// when the PDF feature is installed (`pageThumbnailBackgroundBuilder`),
/// plain white otherwise.
class PageThumbnail extends StatelessWidget {
  const PageThumbnail({
    super.key,
    required this.controller,
    required this.pageIndex,
  });

  final EditorController controller;
  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    final page = controller.doc.meta.pages[pageIndex];
    final content = controller.doc.pages[page.id] ?? PageContent();
    final ext = controller.extensions;
    final pdfBuilder = page.isPdf ? ext.pageThumbnailBackgroundBuilder : null;
    CustomPaint ink({required bool background}) => CustomPaint(
          painter: _ThumbPainter(
            page: page,
            content: content,
            revision: content.revision,
            pageIndex: pageIndex,
            notebookId: controller.notebookId,
            imageLayer: ext.imageLayer,
            textLayer: ext.textLayer,
            paintBackground: background,
          ),
        );
    return AspectRatio(
      aspectRatio: page.width / page.height,
      child: RepaintBoundary(
        child: pdfBuilder == null
            ? ink(background: true)
            : LayoutBuilder(builder: (context, box) {
                final scale = page.width > 0 ? box.maxWidth / page.width : 0.0;
                final pdf = scale > 0
                    ? pdfBuilder(context, controller.notebookId, page, scale)
                    : null;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // The frame: white page, or paper in the writing margins.
                    CustomPaint(painter: PdfPageFramePainter(page)),
                    if (pdf != null)
                      Positioned(
                        key: const ValueKey('page-thumb-pdf'),
                        left: page.contentLeft * scale,
                        top: 0,
                        width: page.contentWidth * scale,
                        bottom: 0,
                        child: pdf,
                      ),
                    ink(background: false),
                  ],
                );
              }),
      ),
    );
  }
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter({
    required this.page,
    required this.content,
    required this.revision,
    required this.pageIndex,
    required this.notebookId,
    this.imageLayer,
    this.textLayer,
    this.paintBackground = true,
  });

  final PageMeta page;
  final PageContent content;
  final int revision;
  final int pageIndex;
  final String notebookId;
  final PageLayerPainter? imageLayer;
  final PageLayerPainter? textLayer;

  /// False when the page's background is a widget below this painter.
  final bool paintBackground;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (paintBackground && page.isPdf) {
      paintPdfPageFrame(canvas, size, page);
    } else if (paintBackground) {
      paintPaper(canvas, size, page.paper, page.width, page.height);
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / page.width, size.height / page.height);
    paintPageContent(
      canvas,
      PagePaintContext(
        notebookId: notebookId,
        pageId: page.id,
        pageIndex: pageIndex,
        page: page,
        content: content,
        forThumbnail: true,
      ),
      imageLayer: imageLayer,
      textLayer: textLayer,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThumbPainter old) =>
      old.page != page ||
      old.content != content ||
      old.revision != revision ||
      old.pageIndex != pageIndex ||
      old.paintBackground != paintBackground;
}
