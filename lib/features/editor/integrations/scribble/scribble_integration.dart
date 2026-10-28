import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show debugPrint;

import '../../../../document/commands.dart';
import '../../../../document/page_items.dart';
import '../../../../ink/ink_rect.dart';
import '../../../../ink/stroke.dart';
import '../../../../render/text_style.dart';
import '../../editor_controller.dart';
import '../../editor_integrations.dart';
import '../../tools/scribble.dart';
import '../text_images/text_editor.dart';

/// "Scribble to delete": a scratch-out with the pen over handwriting or
/// typed text deletes the strokes and words it covers, in one undo step
/// ("Scribble to delete"), and the scribble itself is not kept. Anything
/// else (including a scribble over empty paper) stays ink. Follows the
/// `scribbleToDelete` setting. See `tools/scribble.dart` for the rules.
// ignore: prefer_function_declarations_over_variables
final EditorIntegration scribbleIntegration = (controller, ref) {
  bool gesture(String pageId, Stroke stroke) {
    if (!controller.settings.scribbleToDelete) return false;
    try {
      return applyScribble(controller, pageId, stroke);
    } catch (e, st) {
      // Never lose a stroke over a gesture: it stays ink.
      debugPrint('NeatInk: scribble to delete failed: $e\n$st');
      return false;
    }
  }

  controller.extensions.strokeGestures.add(gesture);
  controller.addDisposeCallback(() => controller.extensions.strokeGestures.remove(gesture));
};

/// Deletes what [scribble] covers on [pageId]; false (nothing changed) when
/// it is not a scribble over anything.
bool applyScribble(EditorController controller, String pageId, Stroke scribble) {
  final page = controller.doc.page(pageId);
  final hidden = controller.extensions.hiddenStrokeIds;
  final plan = planScribble(
    scribble: scribble,
    strokes: [for (final s in page.strokes) if (!hidden.contains(s.id)) s],
    texts: page.texts,
    wordsOf: scribbleWordsOf,
    measureHeight: TextBoxEditor.measureHeight,
  );
  if (plan == null) return false;
  const label = 'Scribble to delete';
  controller.execute(CompositeCommand(label, [
    if (plan.strokeIds.isNotEmpty) RemoveStrokesCommand(pageId, plan.strokeIds, label: label),
    if (plan.textChanges.isNotEmpty)
      PageItemsCommand(pageId, label: label, textChanges: [
        for (final (before, after) in plan.textChanges) (before, after),
      ]),
  ]));
  return true;
}

/// The words of [item] where the page shows them.
List<ScribbleWord> scribbleWordsOf(TextItem item) {
  final painter = layoutTextItem(item);
  try {
    return [
      for (final m in RegExp(r'\S+').allMatches(item.text))
        (
          start: m.start,
          end: m.end,
          boxes: [
            for (final b in painter.getBoxesForSelection(TextSelection(baseOffset: m.start, extentOffset: m.end)))
              InkRect(item.x + b.left, item.y + b.top, item.x + b.right, item.y + b.bottom),
          ],
        ),
    ];
  } finally {
    painter.dispose();
  }
}
