import '../../editor_integrations.dart';
import 'ruler_edge_constraint.dart';
import 'ruler_model.dart';
import 'ruler_painter.dart';
import 'ruler_toggle_button.dart';
import 'ruler_touch_interceptor.dart';

/// The ruler: a button in the tool row puts a ruler over the page; fingers
/// move and turn it, and a pen that lands at one of its edges draws a
/// perfectly straight line along it.
///
/// The ruler is a screen overlay, not part of the notebook: it stays put
/// while the page scrolls or zooms, is never saved, and starts hidden each
/// time the editor opens. Lines drawn along it are ordinary `line` strokes
/// whose `raw` keeps the pen's own path (see `InkToolHandler`).
// ignore: prefer_function_declarations_over_variables
final EditorIntegration rulerIntegration = (controller, ref) {
  final model = RulerModel();
  controller.extensions
    ..touchInterceptor = RulerTouchInterceptor(model)
    ..strokeConstraint = rulerConstraintProvider(model)
    ..viewportOverlays.add((context, c) => RulerOverlay(model: model))
    ..toolRowActions.add((context, c) => RulerToggleButton(
          model: model,
          viewportSize: () => c.viewport.viewportSize,
        ));
  controller.addDisposeCallback(model.dispose);
};
