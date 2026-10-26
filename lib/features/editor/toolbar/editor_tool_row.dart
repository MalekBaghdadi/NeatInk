import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/settings_controller.dart';
import '../editor_controller.dart';
import '../editor_tool.dart';
import 'tool_options.dart';
import 'toolbar_widgets.dart';

/// The tool row under the top bar: the tools, the options of the selected
/// tool and the "Tidy as you write" toggle.
///
/// Wide screens (landscape tablets) fit everything in one row; narrower
/// ones put the options on a second row. The options scroll sideways when
/// they don't fit.
class EditorToolRow extends StatelessWidget {
  const EditorToolRow({super.key, required this.controller});

  final EditorController controller;

  /// Below this width the options get their own row.
  static const double twoRowBreakpoint = 720;

  static const double rowHeight = 56;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
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
                    const ToolbarDivider(),
                    const TidyToggle(),
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
                      const TidyToggle(),
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
    );
  }
}

class _ToolButtons extends StatelessWidget {
  const _ToolButtons({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final tool in EditorTool.values)
            ToolButton(
              key: ValueKey('tool-${tool.name}'),
              tool: tool,
              selected: controller.tool == tool,
              enabled: controller.isToolAvailable(tool),
              onPressed: () => controller.selectTool(tool),
            ),
        ],
      );
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

/// "Tidy as you write" on/off, bound to the app setting.
class TidyToggle extends ConsumerWidget {
  const TidyToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(settingsProvider.select((s) => s.tidyEnabled));
    return FilterChip(
      key: const ValueKey('tidy-toggle'),
      avatar: const Icon(Icons.auto_awesome, size: 18),
      label: const Text('Tidy'),
      selected: on,
      showCheckmark: false,
      tooltip: on ? 'Tidy as you write is on' : 'Tidy as you write is off',
      onSelected: (value) => ref
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(tidyEnabled: value)),
    );
  }
}
