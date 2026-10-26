import 'dart:io';

import 'package:flutter/material.dart';

import '../../../document/notebook_meta.dart';
import '../../../render/paper_painter.dart';
import 'stamped_file_image.dart';

/// Width / height of a notebook cover in the grid.
const double notebookCoverAspect = 3 / 4;

/// A notebook cover: the cover colour with a spine on the left and the
/// first page inset on it. The page shows `thumb.png` when there is one
/// (refreshed through [thumbnailStamp]), otherwise the page's paper.
class NotebookCover extends StatelessWidget {
  const NotebookCover({
    super.key,
    required this.notebook,
    this.thumbnailPath,
    this.thumbnailStamp,
  });

  final NotebookMeta notebook;

  /// Path of `thumb.png`; only used when [thumbnailStamp] is non-null.
  final String? thumbnailPath;

  /// Changes whenever the thumbnail file changes; null = no thumbnail.
  final int? thumbnailStamp;

  @override
  Widget build(BuildContext context) {
    final cover = Color(notebook.coverColor);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cover,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(4),
          right: Radius.circular(10),
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Spine: a darker band with a highlight line, like a bound edge.
          const Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0x2E000000),
                border: Border(
                    right: BorderSide(color: Color(0x33FFFFFF), width: 1)),
                borderRadius:
                    BorderRadius.horizontal(left: Radius.circular(4)),
              ),
            ),
          ),
          Positioned.fill(
            left: 18,
            top: 10,
            right: 10,
            bottom: 10,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(3)),
                boxShadow: [
                  BoxShadow(color: Color(0x40000000), blurRadius: 3),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: _CoverPage(
                  notebook: notebook,
                  thumbnailPath: thumbnailPath,
                  thumbnailStamp: thumbnailStamp,
                ),
              ),
            ),
          ),
          if (notebook.isPdf)
            const Positioned(left: 24, bottom: 16, child: _PdfBadge()),
        ],
      ),
    );
  }
}

class _CoverPage extends StatelessWidget {
  const _CoverPage({
    required this.notebook,
    required this.thumbnailPath,
    required this.thumbnailStamp,
  });

  final NotebookMeta notebook;
  final String? thumbnailPath;
  final int? thumbnailStamp;

  @override
  Widget build(BuildContext context) {
    final first = notebook.pages.isEmpty ? null : notebook.pages.first;
    final paperView = _PaperPage(notebook: notebook, page: first);
    final path = thumbnailPath, stamp = thumbnailStamp;
    if (path == null || stamp == null) return paperView;
    return LayoutBuilder(builder: (context, constraints) {
      // Decode at the size it is shown, not the thumbnail's full size.
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final cacheWidth = constraints.maxWidth.isFinite
          ? (constraints.maxWidth * dpr).round().clamp(1, 2048)
          : null;
      return Image(
        image: ResizeImage.resizeIfNeeded(
            cacheWidth, null, StampedFileImage(File(path), stamp)),
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => paperView,
      );
    });
  }
}

/// The first page's paper, used before the editor has made a thumbnail.
class _PaperPage extends StatelessWidget {
  const _PaperPage({required this.notebook, required this.page});

  final NotebookMeta notebook;
  final PageMeta? page;

  @override
  Widget build(BuildContext context) {
    final paper = page?.paper ?? notebook.defaultPaper;
    return CustomPaint(
      painter: PaperPainter(
        paper,
        page?.width ?? a4WidthPt,
        page?.height ?? a4HeightPt,
      ),
      child: notebook.isPdf
          ? Center(
              child: Icon(
                Icons.picture_as_pdf_outlined,
                size: 40,
                color: Color(paper.lineColor),
              ),
            )
          : const SizedBox.expand(),
    );
  }
}

class _PdfBadge extends StatelessWidget {
  const _PdfBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFD32F2F),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'PDF',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );
}
