import '../../../../ink/stroke.dart';
import '../../editor_controller.dart';
import '../../tools/selection.dart';

/// Whether [selection] holds pen strokes that conversion can read (not just
/// highlighter strokes, shapes, text boxes or images).
bool hasConvertibleStrokes(EditorController controller, Selection selection) {
  if (!selection.hasStrokes || !controller.isReady) return false;
  final page = controller.doc.pages[selection.pageId];
  if (page == null) return false;
  return selection
      .strokesOn(page)
      .any((s) => s.tool == StrokeTool.pen && s.shape == null);
}
