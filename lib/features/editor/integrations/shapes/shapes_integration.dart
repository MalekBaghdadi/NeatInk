import '../../editor_integrations.dart';
import '../../editor_tool.dart';
import 'hold_snap_hook.dart';
import 'shape_tool_handler.dart';
import 'shape_tool_options.dart';

/// Shapes: the shape tool (drag out a line, arrow, rectangle, ellipse or
/// triangle) and hold-to-snap of pen / highlighter strokes.
///
/// Hold-to-snap is the editor's live-stroke hook and follows the "snap
/// shapes" setting.
// ignore: prefer_function_declarations_over_variables
final EditorIntegration shapesIntegration = (controller, ref) {
  final hook = HoldSnapHook(controller);
  controller.extensions
    ..toolHandlers[EditorTool.shape] = ShapeToolHandler(controller)
    ..toolOptions[EditorTool.shape] =
        ((context, c) => ShapeToolOptions(controller: c))
    ..liveStrokeHook = hook;
  controller.addDisposeCallback(hook.dispose);
};
