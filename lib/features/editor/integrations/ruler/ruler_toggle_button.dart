import 'package:flutter/material.dart';

import '../../toolbar/toolbar_widgets.dart' show toolbarTargetSize;
import 'ruler_model.dart';

/// The tool row's ruler button: shows or hides the ruler, and looks pressed
/// while it shows. It listens to the model itself.
///
/// [viewportSize] gives the size of the document view when the ruler is shown
/// (the first time it is placed relative to it).
class RulerToggleButton extends StatelessWidget {
  const RulerToggleButton({
    super.key,
    required this.model,
    required this.viewportSize,
  });

  static const String tooltip = 'Ruler';

  final RulerModel model;
  final Size Function() viewportSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The look of the tool buttons next to it.
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => IconButton(
        key: const ValueKey('ruler-toggle'),
        tooltip: tooltip,
        isSelected: model.visible,
        icon: const Icon(Icons.straighten),
        onPressed: () => model.toggle(viewportSize()),
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
              Size(toolbarTargetSize, toolbarTargetSize)),
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? scheme.secondaryContainer
                  : null),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
