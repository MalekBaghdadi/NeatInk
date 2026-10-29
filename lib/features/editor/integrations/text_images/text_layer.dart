import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextPainter, TextSelection;

import '../../../../document/page_items.dart';
import '../../../../recognition/spell_check.dart';
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
/// [showCorrections] says so, words that may be misspelt ([spellMarks]) a
/// wavy one (never in thumbnails or exports).
class TextLayerPainter extends PageLayerPainter {
  TextLayerPainter({this.hiddenId, this.showCorrections, this.spellMarks});

  final String? Function(String pageId)? hiddenId;
  final bool Function()? showCorrections;

  /// The words of a box to mark as possibly misspelt; empty when spell
  /// checking is off or not ready. Set by the autocorrect integration.
  List<SpellMark> Function(TextItem item)? spellMarks;

  /// The colour of the autocorrect underline: a soft blue that shows on
  /// white, cream and dark paper.
  static const ui.Color correctionColor = ui.Color(0xB33D7BE0);

  /// The wavy underlines: red for an unknown word, amber for a suspect one.
  static const ui.Color unknownColor = ui.Color(0xD9E53935);
  static const ui.Color suspectColor = ui.Color(0xD9F59E0B);

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
        final spelling = context.forThumbnail ? null : spellMarks;
        if (spelling != null && item.text.isNotEmpty) _paintSpelling(canvas, item, painter, spelling(item));
      } finally {
        painter.dispose();
      }
    }
  }

  /// A wavy line under each word of [marks] (not under a word autocorrect
  /// changed, which has its own mark).
  static void _paintSpelling(ui.Canvas canvas, TextItem item, TextPainter painter, List<SpellMark> marks) {
    if (marks.isEmpty) return;
    final corrected = item.liveCorrections;
    final amp = (item.fontSize * 0.06).clamp(0.6, 1.8);
    final stroke = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = (item.fontSize * 0.05).clamp(0.6, 1.4);
    for (final m in marks) {
      if (corrected.any((c) => c.start < m.end && m.start < c.end)) continue;
      stroke.color = m.kind == SpellMarkKind.unknown ? unknownColor : suspectColor;
      for (final b in painter.getBoxesForSelection(TextSelection(baseOffset: m.start, extentOffset: m.end))) {
        final r = b.toRect().shift(ui.Offset(item.x, item.y));
        final y = r.bottom - amp;
        final path = ui.Path()..moveTo(r.left, y);
        var up = true;
        for (var x = r.left + 2 * amp; x <= r.right + 1e-6; x += 2 * amp) {
          path.lineTo(x, y + (up ? -amp : amp));
          up = !up;
        }
        canvas.drawPath(path, stroke);
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
