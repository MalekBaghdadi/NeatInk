import 'package:flutter/material.dart';

import '../../../../ink/stroke.dart';
import '../../editor_controller.dart';
import '../../toolbar/tool_options.dart';
import '../../toolbar/toolbar_widgets.dart';
import 'shape_prefs.dart';

/// Tool-row options of the shape tool: which shape to draw, then the pen's
/// colours and widths (shapes are drawn with the pen's look).
class ShapeToolOptions extends StatelessWidget {
  const ShapeToolOptions({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final selected = selectedShapeKind(controller.toolPrefs);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final kind in ShapeKind.values)
          _ShapeButton(
            kind: kind,
            selected: kind == selected,
            onPressed: () => selectShapeKind(controller, kind),
          ),
        const ToolbarDivider(),
        PenOptions(controller: controller),
      ],
    );
  }
}

IconData shapeKindIcon(ShapeKind kind) => switch (kind) {
      ShapeKind.line => Icons.horizontal_rule,
      ShapeKind.arrow => Icons.arrow_right_alt,
      ShapeKind.rectangle => Icons.crop_square,
      ShapeKind.ellipse => Icons.circle_outlined,
      ShapeKind.triangle => Icons.change_history,
    };

class _ShapeButton extends StatelessWidget {
  const _ShapeButton({
    required this.kind,
    required this.selected,
    required this.onPressed,
  });

  final ShapeKind kind;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: shapeKindName(kind),
      child: Tooltip(
        message: shapeKindName(kind),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: toolbarTargetSize,
            height: toolbarTargetSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? scheme.primaryContainer : null,
            ),
            child: Icon(
              shapeKindIcon(kind),
              size: 26,
              color: selected
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
