import 'dart:ui' as ui;

import '../../../../render/text_style.dart';
import '../../editor_extensions.dart';

/// Paints the committed text boxes of a page (background fill, then text
/// laid out by [layoutTextItem], the same layout the PDF export uses).
///
/// [hiddenId] names the box currently being edited on a page: the text
/// field overlay shows it instead, so it is skipped here (never in
/// thumbnails, which show the last committed state).
class TextLayerPainter extends PageLayerPainter {
  TextLayerPainter({this.hiddenId});

  final String? Function(String pageId)? hiddenId;

  @override
  void paint(ui.Canvas canvas, PagePaintContext context) {
    final hidden = context.forThumbnail ? null : hiddenId?.call(context.pageId);
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
      } finally {
        painter.dispose();
      }
    }
  }
}
