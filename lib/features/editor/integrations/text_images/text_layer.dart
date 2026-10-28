import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextPainter;

import '../../../../document/page_items.dart';
import '../../../../render/text_style.dart';
import '../../editor_extensions.dart';

/// Paints the committed text boxes of a page (background fill, then text
/// laid out by [layoutTextItem], the same layout the PDF export uses).
///
/// [hiddenId] names the box currently being edited on a page: the text
/// field overlay shows it instead, so it is skipped here (never in
/// thumbnails, which show the last committed state).
///
/// Words autocorrect changed get a dotted underline on screen while
/// [showCorrections] says so (never in thumbnails or exports).
class TextLayerPainter extends PageLayerPainter {
  TextLayerPainter({this.hiddenId, this.showCorrections});

  final String? Function(String pageId)? hiddenId;
  final bool Function()? showCorrections;

  /// The colour of the autocorrect underline: a soft blue that shows on
  /// white, cream and dark paper.
  static const ui.Color correctionColor = ui.Color(0xB33D7BE0);

  @override
  void paint(ui.Canvas canvas, PagePaintContext context) {
    final hidden = context.forThumbnail ? null : hiddenId?.call(context.pageId);
    final marks = !context.forThumbnail && (showCorrections?.call() ?? false);
    for (final item in context.content.texts) {
      if (item.id == hidden) continue;
      final painter = layoutTextItem(item);
      try {
        if ((item.background >>> 24) & 0xFF != 0) {
          canvas.drawRect(
            ui.Rect.fromLTWH(item.x, item.y, item.width,
                item.height > painter.height ? item.height : painter.height),
            ui.Paint()..color = ui.Color(item.background),
          );
        }
        if (item.text.isNotEmpty) painter.paint(canvas, ui.Offset(item.x, item.y));
        if (marks) _paintCorrections(canvas, item, painter);
      } finally {
        painter.dispose();
      }
    }
  }

  /// A dotted line under each corrected word, just below the baseline.
  static void _paintCorrections(ui.Canvas canvas, TextItem item, TextPainter painter) {
    final r = (item.fontSize * 0.045).clamp(0.5, 2.0);
    final dot = ui.Paint()..color = correctionColor;
    for (final (_, boxes) in correctionBoxes(item, painter)) {
      for (final b in boxes) {
        final y = b.bottom - r;
        for (var x = b.left + r; x <= b.right - r + 1e-6; x += r * 3) {
          canvas.drawCircle(ui.Offset(x, y), r, dot);
        }
      }
    }
  }
}
