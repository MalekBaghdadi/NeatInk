import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../document/notebook_meta.dart';
import '../../../ink/stroke.dart';
import '../../../render/paper_painter.dart';
import '../editor_controller.dart';
import '../editor_extensions.dart';
import 'live_ink.dart';
import 'page_painting.dart';

/// One page of the document view, laid out at its size in page points.
/// The document view scales and positions it with the viewport transform,
/// so everything inside paints in page coordinates.
///
/// Layers, bottom to top, each in its own [RepaintBoundary] so drawing or
/// committing a stroke repaints only the layer that changed:
///
/// 1. background: paper ([PaperPainter]) or the PDF page
///    (`EditorExtensions.pageBackgroundBuilder`);
/// 2. committed images + highlighter strokes (cached picture);
/// 3. the live highlighter stroke;
/// 4. committed text boxes + pen strokes (cached picture);
/// 5. the live pen stroke;
/// 6. page overlays from `EditorExtensions.pageOverlays` (tidy animation,
///    lasso, selection, debug overlay).
class EditorPageView extends StatelessWidget {
  const EditorPageView({
    super.key,
    required this.controller,
    required this.pageIndex,
    required this.page,
  });

  final EditorController controller;
  final int pageIndex;
  final PageMeta page;

  @override
  Widget build(BuildContext context) {
    final version = controller.pageRenderVersion(page.id);
    final live = controller.liveInkFor(page.id);
    final info = EditorPageInfo(
      controller: controller,
      pageId: page.id,
      pageIndex: pageIndex,
      page: page,
    );
    final overlays = <Widget>[
      for (final build in controller.extensions.pageOverlays)
        ?build(context, info),
    ];
    return SizedBox(
      width: page.width,
      height: page.height,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          RepaintBoundary(child: _background(context)),
          RepaintBoundary(
            child: CustomPaint(
              painter: CommittedInkPainter(
                pictureFor: () => _picture(InkLayer.lower),
                version: version,
              ),
            ),
          ),
          RepaintBoundary(
            child: CustomPaint(
              painter: LiveInkPainter(live, StrokeTool.highlighter),
            ),
          ),
          RepaintBoundary(
            child: CustomPaint(
              painter: CommittedInkPainter(
                pictureFor: () => _picture(InkLayer.upper),
                version: version,
              ),
            ),
          ),
          RepaintBoundary(
            child: CustomPaint(
              painter: LiveInkPainter(live, StrokeTool.pen),
            ),
          ),
          if (controller.unreadablePageIds.contains(page.id))
            const _UnreadablePageNotice(),
          ...overlays,
        ],
      ),
    );
  }

  Widget _background(BuildContext context) {
    Widget? pdf;
    if (page.isPdf) {
      pdf = controller.extensions.pageBackgroundBuilder?.call(
        context,
        PageBackgroundRequest(
          notebookId: controller.notebookId,
          pageIndex: pageIndex,
          page: page,
          viewport: controller.viewport,
        ),
      );
      pdf ??= _PdfPlaceholder(pdfPageIndex: page.pdfPageIndex!);
      if (page.hasMargins) {
        // Writing margins: paper beside the PDF page.
        pdf = Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: PdfPageFramePainter(page), isComplex: true),
            Positioned(
              left: page.contentLeft,
              top: 0,
              width: page.contentWidth,
              height: page.height,
              child: pdf,
            ),
          ],
        );
      }
    }
    return DecoratedBox(
      // A thin shadow in page points, so pages stand out from the backdrop
      // at every zoom.
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: pdf ??
          CustomPaint(
            painter: PaperPainter(page.paper, page.width, page.height),
            isComplex: true,
          ),
    );
  }

  ui.Picture? _picture(InkLayer layer) {
    if (!controller.isReady) return null;
    final content = controller.doc.pages[page.id];
    if (content == null || content.isEmpty) return null;
    final ext = controller.extensions;
    final paintContext = PagePaintContext(
      notebookId: controller.notebookId,
      pageId: page.id,
      pageIndex: pageIndex,
      page: page,
      content: content,
    );
    return controller.renderCache.picture(
      page.id,
      layer,
      content: content,
      generation: controller.renderGeneration(page.id),
      bounds: Rect.fromLTWH(0, 0, page.width, page.height),
      record: (canvas) => paintPageLayer(
        canvas,
        paintContext,
        layer,
        imageLayer: ext.imageLayer,
        textLayer: ext.textLayer,
        hiddenStrokeIds: ext.hiddenStrokeIds,
      ),
    );
  }
}

/// Stand-in for a PDF page until the PDF integration provides its
/// background: a white page with a quiet label.
class _PdfPlaceholder extends StatelessWidget {
  const _PdfPlaceholder({required this.pdfPageIndex});

  final int pdfPageIndex;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFFFFFFFF),
        child: Center(
          child: Text(
            'PDF page ${pdfPageIndex + 1}',
            style: const TextStyle(
              color: Color(0x66000000),
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
}

/// Shown over a page whose file couldn't be read.
class _UnreadablePageNotice extends StatelessWidget {
  const _UnreadablePageNotice();

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFB74D)),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                "This page couldn't be read, so it can't be edited. Its file "
                'was left untouched.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF5D4037), fontSize: 12),
              ),
            ),
          ),
        ),
      );
}
