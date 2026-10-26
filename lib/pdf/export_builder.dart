import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';

import '../document/notebook_doc.dart';
import '../document/notebook_meta.dart';
import '../document/page_content.dart';
import '../document/page_items.dart';
import '../document/paper.dart';
import '../render/stroke_outline.dart';
import '../render/text_style.dart';
import '../storage/notebook_repository.dart';
import 'pdf_export_request.dart';

/// Turns a notebook into the drawing instructions the Kotlin PdfBox
/// exporter needs ([ExportPage]s), using the same outlines, paper geometry
/// and text layout as the screen.
///
/// Pages come out in notebook order. A page backed by the source PDF keeps
/// its `pdfPageIndex` (so reordered or duplicated PDF pages work); a plain
/// page gets its paper colour and, when [exportPaperLines] is set, its
/// ruling.
///
/// Page contents are taken from [doc] when loaded there, otherwise read
/// from [repo], so a notebook can be exported without opening the editor
/// (pass a [NotebookDoc] with only its meta).
class ExportBuilder {
  ExportBuilder({
    required this.doc,
    required this.repo,
    required this.exportPaperLines,
  });

  final NotebookDoc doc;
  final NotebookRepository repo;
  final bool exportPaperLines;

  NotebookMeta get meta => doc.meta;

  int get pageCount => meta.pages.length;

  /// The notebook's `source.pdf` when any page shows a PDF page, else null.
  String? get sourcePdfPath =>
      meta.pages.any((p) => p.isPdf) ? repo.sourcePdfPath(meta.id) : null;

  /// Builds page [index] and then yields to the event loop, so a long
  /// export keeps the UI (and its progress indicator) responsive.
  Future<ExportPage> buildPage(int index) async {
    final pageMeta = meta.pages[index];
    final content =
        doc.pages[pageMeta.id] ?? await repo.loadPage(meta.id, pageMeta.id);
    final page = buildExportPage(
      pageMeta,
      content,
      exportPaperLines: exportPaperLines,
      assetPath: (asset) => repo.assetPath(meta.id, asset),
    );
    await Future<void>.delayed(Duration.zero);
    return page;
  }

  /// Builds the whole request at once. [onProgress] reports pages built.
  ///
  /// For large notebooks prefer streaming pages with [buildPage] into
  /// `PdfExporter.exportPages`, which keeps only a page or two in memory.
  Future<ExportRequest> buildRequest({
    required String outputPath,
    void Function(int done, int total)? onProgress,
  }) async {
    final pages = <ExportPage>[];
    onProgress?.call(0, pageCount);
    for (var i = 0; i < pageCount; i++) {
      pages.add(await buildPage(i));
      onProgress?.call(i + 1, pageCount);
    }
    return ExportRequest(
      outputPath: outputPath,
      sourcePdfPath: sourcePdfPath,
      title: meta.title,
      pages: pages,
    );
  }
}

/// The export instructions for one page.
///
/// Layers follow the screen's paint order: background, paper ruling,
/// images, highlighter, text boxes, pen ink (each group in list order).
ExportPage buildExportPage(
  PageMeta page,
  PageContent content, {
  required bool exportPaperLines,
  required String Function(String asset) assetPath,
}) {
  final highlighter = <ExportPolygon>[];
  final ink = <ExportPolygon>[];
  for (final stroke in content.strokes) {
    final outline = cachedStrokeOutline(stroke);
    if (outline.length < 3) continue;
    final polygon = ExportPolygon(_flatten(outline), strokeFillArgb(stroke));
    (stroke.isHighlighter ? highlighter : ink).add(polygon);
  }

  final images = [
    for (final img in content.images)
      if (img.width > 0 && img.height > 0)
        ExportImage(assetPath(img.asset), img.x, img.y, img.width, img.height),
  ];

  final textRects = <ExportRect>[];
  final textLines = <ExportTextLine>[];
  for (final item in content.texts) {
    final exported = exportTextItem(item);
    if (exported.background != null) textRects.add(exported.background!);
    textLines.addAll(exported.lines);
  }

  final pdfIndex = page.pdfPageIndex;
  if (pdfIndex != null) {
    return ExportPage(
      width: page.width,
      height: page.height,
      pdfPageIndex: pdfIndex,
      images: images,
      highlighter: highlighter,
      textRects: textRects,
      textLines: textLines,
      ink: ink,
    );
  }

  final paper = page.paper;
  var lines = const <ExportLine>[];
  List<double> dots = const <double>[];
  if (exportPaperLines && paper.type != PaperType.blank) {
    final geometry = PaperGeometry(paper, page.width, page.height);
    lines = [
      for (final l in geometry.lines)
        ExportLine(
          l.from.x,
          l.from.y,
          l.to.x,
          l.to.y,
          PaperGeometry.strokeWidthFor(l.role),
          l.role == PaperLineRole.rule ? paper.lineColor : paper.accentColor,
        ),
    ];
    final flat = Float32List(geometry.dots.length * 2);
    for (var i = 0; i < geometry.dots.length; i++) {
      flat[i * 2] = geometry.dots[i].x;
      flat[i * 2 + 1] = geometry.dots[i].y;
    }
    dots = flat;
  }

  return ExportPage(
    width: page.width,
    height: page.height,
    background: paper.color,
    lines: lines,
    dots: dots,
    dotRadius: PaperGeometry.dotRadius,
    dotColor: paper.lineColor,
    images: images,
    highlighter: highlighter,
    textRects: textRects,
    textLines: textLines,
    ink: ink,
  );
}

/// A text box as PDF instructions: one [ExportTextLine] per visual line,
/// positioned by Flutter's own layout ([layoutTextItem]) so the PDF wraps
/// and aligns exactly like the screen, plus the background fill if any.
({List<ExportTextLine> lines, ExportRect? background}) exportTextItem(
    TextItem item) {
  final painter = layoutTextItem(item);
  try {
    final hasBackground = (item.background >>> 24) & 0xFF != 0;
    final background = hasBackground
        ? ExportRect(item.x, item.y, item.width,
            math.max(item.height, painter.height), item.background)
        : null;
    if (item.text.trim().isEmpty) {
      return (lines: const <ExportTextLine>[], background: background);
    }
    return (lines: _textLines(item, painter), background: background);
  } finally {
    painter.dispose();
  }
}

List<ExportTextLine> _textLines(TextItem item, TextPainter painter) {
  final text = item.text;
  final out = <ExportTextLine>[];
  for (final line in painter.computeLineMetrics()) {
    // Probe just outside both ends of the line, halfway up the x-height,
    // to find which characters it holds. (Probing the ends avoids the
    // ambiguity of an offset that is both the end of one line and the
    // start of the next.)
    final y = line.baseline - line.ascent / 2;
    final a =
        painter.getPositionForOffset(Offset(line.left - 1, y)).offset;
    final b = painter
        .getPositionForOffset(Offset(line.left + line.width + 1, y))
        .offset;
    final start = math.max(0, math.min(a, b));
    final end = math.min(text.length, math.max(a, b));
    if (end <= start) continue;

    // Trailing spaces at a soft wrap are invisible; drop them (and any
    // stray line break) so the PDF line has no dangling underline.
    final content = text.substring(start, end).replaceAll('\n', '');
    final trimmed = content.trimRight();
    if (trimmed.trim().isEmpty) continue;
    final trimmedEnd = start + text.substring(start, end).indexOf(trimmed) +
        trimmed.length;

    var left = line.left, right = line.left + line.width;
    final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: trimmedEnd));
    if (boxes.isNotEmpty) {
      left = boxes.map((b) => b.left).reduce(math.min);
      right = boxes.map((b) => b.right).reduce(math.max);
    }

    out.add(ExportTextLine(
      text: trimmed,
      x: item.x + left,
      baselineY: item.y + line.baseline,
      fontSize: item.fontSize,
      color: item.color,
      bold: item.bold,
      italic: item.italic,
      underline: item.underline,
      font: item.font,
      width: math.max(0, right - left),
    ));
  }
  return out;
}

/// Outline points as a flat `[x0, y0, x1, y1, ...]` list. Float32 halves
/// the platform-channel payload; its precision (~1e-4 pt on a page) is far
/// below anything visible.
Float32List _flatten(List<Offset> outline) {
  final xy = Float32List(outline.length * 2);
  for (var i = 0; i < outline.length; i++) {
    xy[i * 2] = outline[i].dx;
    xy[i * 2 + 1] = outline[i].dy;
  }
  return xy;
}
