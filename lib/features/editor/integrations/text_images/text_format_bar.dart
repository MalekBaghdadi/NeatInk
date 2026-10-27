import 'package:flutter/material.dart';

import '../../../../document/page_items.dart';
import '../../editor_controller.dart';
import '../../toolbar/color_picker_dialog.dart';
import '../../toolbar/toolbar_widgets.dart';
import '../../tool_prefs.dart';
import 'text_editor.dart';

/// Font sizes offered by the size stepper, in points.
const List<double> textFontSizes = [
  8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 40, 48, 64, 80, //
];

/// Fills offered for the box background (ARGB; the first is "none").
const List<int> textBackgrounds = [
  0x00000000,
  0xFFFFF59D, // yellow
  0xFFC8E6C9, // green
  0xFFBBDEFB, // blue
  0xFFF8BBD0, // pink
  0xFFE0E0E0, // grey
  0xFFFFFFFF, // white
];

/// The size next to [current] in [textFontSizes] (one step up or down).
double steppedFontSize(double current, {required bool up}) {
  if (up) {
    for (final s in textFontSizes) {
      if (s > current + 0.01) return s;
    }
    return textFontSizes.last;
  }
  for (final s in textFontSizes.reversed) {
    if (s < current - 0.01) return s;
  }
  return textFontSizes.first;
}

/// The tool-row options of the text tool: a new-box button, then the
/// formatting of the box being edited (or of the next new box).
class TextFormatBar extends StatelessWidget {
  const TextFormatBar({
    super.key,
    required this.editor,
    required this.controller,
  });

  final TextBoxEditor editor;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) {
        final item = editor.session?.draft ?? editor.format;
        final editing = editor.session != null;
        final scheme = Theme.of(context).colorScheme;
        final isPreset = ToolPresets.penColors.contains(item.color);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const ValueKey('text-new'),
              tooltip: 'New text box',
              onPressed: controller.isReady ? editor.createInView : null,
              icon: const Icon(Icons.add_box_outlined),
            ),
            if (editing)
              IconButton(
                key: const ValueKey('text-delete'),
                tooltip: 'Delete text box',
                onPressed: editor.deleteSession,
                icon: Icon(Icons.delete_outline, color: scheme.error),
              ),
            const ToolbarDivider(),
            PopupMenuButton<FontKind>(
              key: const ValueKey('text-font'),
              tooltip: 'Font',
              initialValue: item.font,
              onSelected: (f) => editor.applyFormat((t) => t.copyWith(font: f)),
              itemBuilder: (_) => fontPickerItems(item.font),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(
                  height: toolbarTargetSize,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.font.label,
                        key: const ValueKey('text-font-label'),
                        style: TextStyle(fontFamily: item.font.family),
                      ),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('text-size-down'),
              tooltip: 'Smaller',
              onPressed: () => editor.applyFormat((t) => t.copyWith(
                  fontSize: steppedFontSize(t.fontSize, up: false))),
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 30,
              child: Text(
                item.fontSize == item.fontSize.roundToDouble()
                    ? item.fontSize.round().toString()
                    : item.fontSize.toStringAsFixed(1),
                key: const ValueKey('text-size'),
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              key: const ValueKey('text-size-up'),
              tooltip: 'Larger',
              onPressed: () => editor.applyFormat((t) =>
                  t.copyWith(fontSize: steppedFontSize(t.fontSize, up: true))),
              icon: const Icon(Icons.add),
            ),
            const ToolbarDivider(),
            _toggle('text-bold', 'Bold', Icons.format_bold, item.bold,
                () => editor.applyFormat((t) => t.copyWith(bold: !t.bold))),
            _toggle('text-italic', 'Italic', Icons.format_italic, item.italic,
                () => editor.applyFormat((t) => t.copyWith(italic: !t.italic))),
            _toggle(
                'text-underline',
                'Underline',
                Icons.format_underlined,
                item.underline,
                () => editor
                    .applyFormat((t) => t.copyWith(underline: !t.underline))),
            const ToolbarDivider(),
            for (final a in TextAlignKind.values)
              _toggle('text-align-${a.name}', 'Align ${a.name}', _alignIcon(a),
                  item.align == a,
                  () => editor.applyFormat((t) => t.copyWith(align: a))),
            const ToolbarDivider(),
            for (final c in ToolPresets.penColors)
              ColorSwatchButton(
                color: c,
                selected: c == item.color,
                onPressed: () =>
                    editor.applyFormat((t) => t.copyWith(color: c)),
              ),
            CustomColorButton(
              customColor: isPreset ? null : item.color,
              onPressed: () => _pickColor(context, item.color, (c) {
                editor.applyFormat((t) => t.copyWith(color: c));
              }),
            ),
            const ToolbarDivider(),
            _BackgroundButton(
              color: item.background,
              onSelected: (c) =>
                  editor.applyFormat((t) => t.copyWith(background: c)),
              onCustom: () => _pickColor(
                  context,
                  (item.background >>> 24) == 0 ? 0xFFFFF59D : item.background,
                  (c) => editor.applyFormat((t) => t.copyWith(background: c))),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickColor(
      BuildContext context, int initial, void Function(int) apply) async {
    final recent = customRecentColors(controller.toolPrefs);
    final picked = await showColorPickerDialog(
      context,
      initialColor: initial | 0xFF000000,
      recentColors: recent,
    );
    if (picked != null) {
      controller.updateToolPrefs((p) => p.withRecentColor(picked));
      apply(picked);
    }
  }

  Widget _toggle(String key, String tooltip, IconData icon, bool on,
          VoidCallback onPressed) =>
      IconButton(
        key: ValueKey(key),
        tooltip: tooltip,
        isSelected: on,
        onPressed: onPressed,
        icon: Icon(icon),
        selectedIcon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: on ? const Color(0x22000000) : null,
        ),
      );

  /// The font picker's menu: one non-selectable heading per [FontCategory],
  /// each followed by its fonts, every font name shown in its own font.
  /// Entry keys are `text-font-<id>`; the current font is highlighted.
  static List<PopupMenuEntry<FontKind>> fontPickerItems(FontKind current) => [
        for (final category in FontCategory.values) ...[
          PopupMenuItem<FontKind>(
            key: ValueKey('text-font-heading-${category.name}'),
            enabled: false,
            height: 30,
            child: Text(
              category.label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8),
            ),
          ),
          for (final f in FontKind.inCategory(category))
            PopupMenuItem<FontKind>(
              key: ValueKey('text-font-${f.name}'),
              value: f,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      f.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: f.family, fontSize: 18),
                    ),
                  ),
                  if (f == current) ...[
                    const SizedBox(width: 10),
                    const Icon(Icons.check, size: 18),
                  ],
                ],
              ),
            ),
        ],
      ];

  static IconData _alignIcon(TextAlignKind a) => switch (a) {
        TextAlignKind.left => Icons.format_align_left,
        TextAlignKind.center => Icons.format_align_center,
        TextAlignKind.right => Icons.format_align_right,
      };
}

class _BackgroundButton extends StatelessWidget {
  const _BackgroundButton({
    required this.color,
    required this.onSelected,
    required this.onCustom,
  });

  final int color;
  final ValueChanged<int> onSelected;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    final none = (color >>> 24) == 0;
    return PopupMenuButton<int>(
      key: const ValueKey('text-background'),
      tooltip: 'Background',
      onSelected: (c) => c == -1 ? onCustom() : onSelected(c),
      itemBuilder: (_) => [
        for (final c in textBackgrounds)
          PopupMenuItem(
            value: c,
            child: Row(children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: (c >>> 24) == 0 ? null : Color(c),
                  border: Border.all(color: Colors.black38),
                  shape: BoxShape.circle,
                ),
                child: (c >>> 24) == 0
                    ? const Icon(Icons.block, size: 16, color: Colors.black45)
                    : null,
              ),
              const SizedBox(width: 12),
              Text((c >>> 24) == 0 ? 'No background' : colorName(c)),
            ]),
          ),
        const PopupMenuItem(value: -1, child: Text('Custom colour...')),
      ],
      child: SizedBox.square(
        dimension: toolbarTargetSize,
        child: Center(
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: none ? null : Color(color),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(6),
            ),
            child: none
                ? const Icon(Icons.format_color_fill, size: 16)
                : null,
          ),
        ),
      ),
    );
  }
}
