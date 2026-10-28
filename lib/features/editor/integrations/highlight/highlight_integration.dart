import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show debugPrint;

import '../../../../document/page_items.dart';
import '../../../../ink/stroke.dart';
import '../../../../render/text_style.dart';
import '../../../settings/settings_controller.dart';
import '../../editor_controller.dart';
import '../../editor_integrations.dart';
import '../../tools/highlight_tidy.dart';

/// "Tidy highlighter": a highlight drawn over a line of handwriting, a line
/// of a typed text box or a line of a PDF page's text becomes a straight
/// band laid over that line (see [tidyHighlight]). Follows the
/// `tidyHighlighter` setting; the drawn stroke stays in `raw` for "Restore
/// original".
///
/// It runs as a stroke finisher, inside the pen path, so it only does cheap
/// work there: the handwriting near the stroke is grouped, text boxes are
/// laid out, and a PDF page's words come from a cache that starts loading
/// when a highlight starts on the page (until they are there, a highlight
/// over PDF text is only straightened).
// ignore: prefer_function_declarations_over_variables
final EditorIntegration highlightIntegration = (controller, ref) {
  Stroke finish(String pageId, Stroke stroke) {
    if (stroke.tool != StrokeTool.highlighter || stroke.shape != null) return stroke;
    if (!ref.read(settingsProvider).tidyHighlighter) return stroke;
    try {
      return tidyHighlight(stroke, highlightLinesOn(controller, pageId, stroke)) ?? stroke;
    } catch (e, st) {
      // Never lose a stroke over a tidy.
      debugPrint('NeatInk: tidying a highlight failed: $e\n$st');
      return stroke;
    }
  }

  controller.extensions.strokeFinishers.add(finish);
  final started = controller.strokeEvents.started.listen((e) {
    if (e.tool == StrokeTool.highlighter) controller.extensions.pageTextWords?.prepare(e.pageId);
  });
  controller.addDisposeCallback(() {
    started.cancel();
    controller.extensions.strokeFinishers.remove(finish);
  });
};

/// Every line of text on the page a highlight could lie over: handwriting
/// near [highlight], the lines of the typed text boxes and the lines of the
/// PDF page's words.
List<HighlightLine> highlightLinesOn(EditorController controller, String pageId, Stroke highlight) {
  final page = controller.doc.page(pageId);
  return [
    ...inkHighlightLines(highlight, page.strokes),
    for (final t in page.texts) ...textItemHighlightLines(t),
    ...wordBoxHighlightLines(controller.extensions.pageTextWords?.wordsOn(pageId) ?? const []),
  ];
}

/// The lines of a typed text box as laid out on the page.
List<HighlightLine> textItemHighlightLines(TextItem item) {
  if (item.text.trim().isEmpty) return const [];
  final painter = layoutTextItem(item);
  try {
    final metrics = painter.computeLineMetrics();
    if (metrics.isEmpty) return const [];
    final words = <List<({double left, double right})>>[for (final _ in metrics) []];
    for (final m in RegExp(r'\S+').allMatches(item.text)) {
      for (final box in painter.getBoxesForSelection(TextSelection(baseOffset: m.start, extentOffset: m.end))) {
        final cy = (box.top + box.bottom) / 2;
        var line = 0;
        for (var i = 0; i < metrics.length; i++) {
          final lm = metrics[i];
          if (cy >= lm.baseline - lm.ascent && cy <= lm.baseline + lm.descent) {
            line = i;
            break;
          }
        }
        words[line].add((left: item.x + box.left, right: item.x + box.right));
      }
    }
    return [
      for (var i = 0; i < metrics.length; i++)
        if (words[i].isNotEmpty)
          () {
            final lm = metrics[i];
            final ws = words[i]..sort((a, b) => a.left.compareTo(b.left));
            final baseline = item.y + lm.baseline;
            return HighlightLine(
              left: ws.first.left,
              right: ws.map((w) => w.right).reduce(math.max),
              // Letters and most of the capitals, a little of the descenders.
              top: baseline - 0.8 * lm.ascent,
              bottom: baseline + 0.45 * lm.descent,
              words: ws,
            );
          }(),
    ];
  } finally {
    painter.dispose();
  }
}

/// Lines of a printed page from its word boxes: words that overlap
/// vertically by more than half of the lower one are one line.
List<HighlightLine> wordBoxHighlightLines(List<({double left, double top, double right, double bottom})> boxes) {
  if (boxes.isEmpty) return const [];
  final sorted = [...boxes]..sort((a, b) => ((a.top + a.bottom) / 2).compareTo((b.top + b.bottom) / 2));
  final lines = <List<({double left, double top, double right, double bottom})>>[];
  for (final w in sorted) {
    final last = lines.isEmpty ? null : lines.last;
    if (last != null) {
      final top = last.map((b) => b.top).reduce(math.min);
      final bottom = last.map((b) => b.bottom).reduce(math.max);
      final overlap = math.min(bottom, w.bottom) - math.max(top, w.top);
      if (overlap > 0.5 * math.min(bottom - top, w.bottom - w.top)) {
        last.add(w);
        continue;
      }
    }
    lines.add([w]);
  }
  return [
    for (final l in lines)
      () {
        l.sort((a, b) => a.left.compareTo(b.left));
        final top = l.map((b) => b.top).reduce(math.min);
        final bottom = l.map((b) => b.bottom).reduce(math.max);
        return HighlightLine(
          left: l.first.left,
          right: l.map((b) => b.right).reduce(math.max),
          top: top,
          bottom: bottom,
          words: [for (final b in l) (left: b.left, right: b.right)],
        );
      }(),
  ];
}
