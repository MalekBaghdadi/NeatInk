import 'package:flutter/material.dart';

import '../../../ink/stroke.dart';
import '../editor_controller.dart';
import '../editor_tool.dart';
import '../tool_prefs.dart';
import 'color_picker_dialog.dart';
import 'toolbar_widgets.dart';

/// The options shown in the tool row for the selected [tool]: colours,
/// widths and styles for the built-in tools, or whatever an integration
/// registered in `EditorExtensions.toolOptions`.
Widget toolOptionsFor(
    BuildContext context, EditorController controller, EditorTool tool) {
  final custom = controller.extensions.toolOptions[tool];
  if (custom != null) return custom(context, controller);
  return switch (tool) {
    EditorTool.pen => PenOptions(controller: controller),
    EditorTool.highlighter => HighlighterOptions(controller: controller),
    EditorTool.eraser => EraserOptions(controller: controller),
    _ => const SizedBox.shrink(),
  };
}

/// Pen style, the eight preset colours, the custom colour picker and the
/// three widths.
class PenOptions extends StatelessWidget {
  const PenOptions({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final pen = controller.toolPrefs.pen;
    final isPreset = ToolPresets.penColors.contains(pen.color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PenStyleMenu(
          style: pen.style,
          color: pen.color,
          onSelected: controller.setPenStyle,
        ),
        const ToolbarDivider(),
        for (final c in ToolPresets.penColors)
          ColorSwatchButton(
            color: c,
            selected: c == pen.color,
            onPressed: () => controller.setPenColor(c),
          ),
        CustomColorButton(
          customColor: isPreset ? null : pen.color,
          onPressed: () => pickCustomPenColor(context, controller),
        ),
        const ToolbarDivider(),
        for (var i = 0; i < ToolPresets.penWidths.length; i++)
          WidthDotButton(
            index: i,
            width: ToolPresets.penWidths[i],
            color: pen.color,
            selected: ToolPresets.penWidths[i] == pen.size,
            onPressed: () => controller.setPenSize(ToolPresets.penWidths[i]),
          ),
      ],
    );
  }
}

/// Opens the custom colour picker for the pen. Starts from the current
/// colour when it is a custom one, else from the latest custom colour.
Future<void> pickCustomPenColor(
    BuildContext context, EditorController controller) async {
  final prefs = controller.toolPrefs;
  final recent = customRecentColors(prefs);
  final current = prefs.pen.color;
  final initial = ToolPresets.penColors.contains(current)
      ? (recent.isEmpty ? defaultCustomColor : recent.first)
      : current;
  final picked = await showColorPickerDialog(
    context,
    initialColor: initial,
    recentColors: recent,
    title: 'Pen colour',
  );
  if (picked == null) return;
  controller.setPenColor(picked,
      custom: !ToolPresets.penColors.contains(picked));
}

/// The six highlighter colours and three widths.
class HighlighterOptions extends StatelessWidget {
  const HighlighterOptions({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final hl = controller.toolPrefs.highlighter;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in ToolPresets.highlighterColors)
          ColorSwatchButton(
            color: c,
            selected: c == hl.color,
            onPressed: () => controller.setHighlighterColor(c),
          ),
        const ToolbarDivider(),
        for (var i = 0; i < ToolPresets.highlighterWidths.length; i++)
          WidthDotButton(
            index: i,
            width: ToolPresets.highlighterWidths[i],
            color: hl.color,
            selected: ToolPresets.highlighterWidths[i] == hl.size,
            onPressed: () =>
                controller.setHighlighterSize(ToolPresets.highlighterWidths[i]),
          ),
      ],
    );
  }
}

/// Whole-stroke or partial erasing, and the eraser size.
class EraserOptions extends StatelessWidget {
  const EraserOptions({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final eraser = controller.toolPrefs.eraser;
    final neutral = Theme.of(context).colorScheme.onSurfaceVariant.toARGB32();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<EraserMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: EraserMode.stroke,
              label: Text('Whole stroke'),
              tooltip: 'Erase every stroke you touch',
            ),
            ButtonSegment(
              value: EraserMode.pixel,
              label: Text('Partial'),
              tooltip: 'Erase only the part you rub over',
            ),
          ],
          selected: {eraser.mode},
          onSelectionChanged: (s) => controller.setEraserMode(s.first),
        ),
        const ToolbarDivider(),
        for (var i = 0; i < ToolPresets.eraserSizes.length; i++)
          WidthDotButton(
            index: i,
            width: ToolPresets.eraserSizes[i],
            color: neutral,
            selected: ToolPresets.eraserSizes[i] == eraser.size,
            onPressed: () =>
                controller.setEraserSize(ToolPresets.eraserSizes[i]),
          ),
      ],
    );
  }
}

/// A button showing the current pen style; opens a menu of the three
/// styles, each with a sample stroke.
class PenStyleMenu extends StatelessWidget {
  const PenStyleMenu({
    super.key,
    required this.style,
    required this.color,
    required this.onSelected,
  });

  final PenStyle style;

  /// Colour of the sample strokes (the pen colour, or the theme's text
  /// colour when it would be invisible).
  final int color;
  final ValueChanged<PenStyle> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = Color(color);
    // A white pen on a light toolbar (or black on dark) would be invisible.
    final visible = scheme.brightness == Brightness.light
        ? c.computeLuminance() < 0.8
        : c.computeLuminance() > 0.08;
    final sample = visible ? color : scheme.onSurface.toARGB32();
    return PopupMenuButton<PenStyle>(
      tooltip: 'Pen style: ${penStyleName(style)}',
      initialValue: style,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final s in PenStyle.values)
          PopupMenuItem(
            value: s,
            child: Row(
              children: [
                PenStylePreview(style: s, color: sample),
                const SizedBox(width: 12),
                Text(penStyleName(s)),
                if (s == style) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.check, size: 18, color: scheme.primary),
                ],
              ],
            ),
          ),
      ],
      child: SizedBox(
        height: toolbarTargetSize,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 6),
            PenStylePreview(style: style, color: sample, width: 44),
            Icon(Icons.arrow_drop_down, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
