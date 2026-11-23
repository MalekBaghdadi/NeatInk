import 'package:flutter/material.dart';

import '../editor_controller.dart';
import '../editor_tool.dart';
import 'ink_settings_model.dart';
import 'ink_settings_panel.dart';
import 'tool_options.dart';
import 'toolbar_widgets.dart';

/// The tool row under the top bar: the tools, the extra buttons integrations
/// added (the ruler), the options of the selected tool.
///
/// Wide screens (landscape tablets) fit everything in one row; narrower
/// ones put the options on a second row. The options scroll sideways when
/// they don't fit.
///
/// The pen settings panel opens under the whole row (see
/// [InkSettingsAnchor]): from the pill in the options, or by tapping the pen
/// or the highlighter while it is already selected.
class EditorToolRow extends StatelessWidget {
  const EditorToolRow({super.key, required this.controller});

  final EditorController controller;

  /// Below this width the options get their own row.
  // Below it the tools and their options take a row each, so the options
  // (all pen colours, "any colour" and the widths) fit without scrolling.
  static const double twoRowBreakpoint = 1000;

  static const double rowHeight = 56;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkSettingsAnchor(
      child: Material(
        color: scheme.surfaceContainerLow,
        elevation: 1,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final tools = _ToolButtons(controller: controller);
              final options = _ScrollableOptions(
                child: toolOptionsFor(context, controller, controller.tool),
              );
              if (constraints.maxWidth >= twoRowBreakpoint) {
                return SizedBox(
                  height: rowHeight,
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      tools,
                      const ToolbarDivider(),
                      Expanded(child: options),
                      const SizedBox(width: 12),
                    ],
                  ),
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: rowHeight,
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: tools,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  SizedBox(
                    height: rowHeight,
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        Expanded(child: options),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ToolButtons extends StatelessWidget {
  const _ToolButtons({required this.controller});

  final EditorController controller;

  /// Selects [tool]; a second tap on the selected pen or highlighter opens
  /// its settings panel instead.
  void _onPressed(BuildContext context, EditorTool tool) {
    if (tool != controller.tool) {
      controller.selectTool(tool);
      return;
    }
    final model = switch (tool) {
      EditorTool.pen => InkSettingsModel.forPen(controller),
      EditorTool.highlighter => InkSettingsModel.forHighlighter(controller),
      _ => null,
    };
    if (model != null) showInkSettingsPanel(context, model);
  }

  @override
  Widget build(BuildContext context) {
    final actions = controller.extensions.toolRowActions;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final tool in EditorTool.values)
          ToolButton(
            key: ValueKey('tool-${tool.name}'),
            tool: tool,
            selected: controller.tool == tool,
            enabled: controller.isToolAvailable(tool),
            onPressed: () => _onPressed(context, tool),
          ),
        if (actions.isNotEmpty) ...[
          const ToolbarDivider(),
          for (final action in actions) action(context, controller),
        ],
      ],
    );
  }
}

class _ScrollableOptions extends StatelessWidget {
  const _ScrollableOptions({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: child,
        ),
      );
}
