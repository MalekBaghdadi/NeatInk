import 'package:flutter/material.dart';

import '../library_palette.dart';

/// A round colour swatch that shows a check mark when [selected].
class ColorSwatchButton extends StatelessWidget {
  const ColorSwatchButton({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.size = 36,
  });

  /// ARGB colour.
  final int color;
  final bool selected;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = Color(color);
    final onColor =
        ThemeData.estimateBrightnessForColor(c) == Brightness.dark
            ? Colors.white
            : Colors.black87;
    return Semantics(
      button: true,
      selected: selected,
      label: colorName(color),
      excludeSemantics: true,
      child: Tooltip(
        message: colorName(color),
        child: InkResponse(
          onTap: onTap,
          radius: size * 0.65,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? Icon(Icons.check, size: size * 0.55, color: onColor)
                : null,
          ),
        ),
      ),
    );
  }
}

/// A wrapping row of [ColorSwatchButton]s.
class ColorSwatchPicker extends StatelessWidget {
  const ColorSwatchPicker({
    super.key,
    required this.colors,
    required this.selected,
    required this.onSelected,
    this.size = 36,
  });

  final List<int> colors;
  final int? selected;
  final ValueChanged<int> onSelected;
  final double size;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final c in colors)
            ColorSwatchButton(
              color: c,
              size: size,
              selected: c == selected,
              onTap: () => onSelected(c),
            ),
        ],
      );
}
