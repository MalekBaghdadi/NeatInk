import '../../editor_integrations.dart';
import '../../editor_tool.dart';
import 'eraser_cursor.dart';
import 'eraser_handler.dart';
import 'lasso_handler.dart';
import 'selection_menu.dart';
import 'selection_overlay.dart';

/// Eraser (whole-stroke and partial) and lasso selection.
///
/// * The eraser tool also receives the pen's eraser end / barrel button
///   (the input router sends those pointers to `controller.eraserHandler`,
///   which is this handler), whatever tool is selected.
/// * The eraser's mode and size are the core tool row's own options.
/// * The lasso selects strokes, text boxes and images; its frame is a page
///   overlay and its menu a viewport overlay.
// ignore: prefer_function_declarations_over_variables
final EditorIntegration eraseSelectIntegration = (controller, ref) {
  final eraser = EraserHandler(controller);
  final lasso = LassoHandler(controller);
  controller.extensions
    ..toolHandlers[EditorTool.eraser] = eraser
    ..toolHandlers[EditorTool.lasso] = lasso
    ..pageOverlays
        .add((context, page) => SelectionPageOverlay(state: lasso.state, page: page))
    ..viewportOverlays.addAll([
      (context, c) => SelectionMenu(handler: lasso, controller: c),
      (context, c) => EraserCursorOverlay(handler: eraser, viewport: c.viewport),
    ]);
};
