import 'package:flutter/material.dart';

/// The app bar's "Auto" switch for auto-convert (handwriting turns into text
/// by itself a moment after the pen stops).
///
/// A labelled button with the font in use where there is room, an icon button
/// on narrower screens; highlighted while on. The font the text will be typed
/// in ([fontLabel]) shows next to the label when on.
class AutoConvertToggle extends StatelessWidget {
  const AutoConvertToggle({
    super.key,
    required this.enabled,
    required this.fontLabel,
    required this.wide,
    required this.onPressed,
  });

  /// Tooltip of the toggle.
  static const String tooltip = 'Auto-convert handwriting to text';

  final bool enabled;
  final String fontLabel;

  /// Room for icon and label (tablet landscape).
  final bool wide;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onColor = scheme.onPrimaryContainer;
    if (wide) {
      return Tooltip(
        message: tooltip,
        child: TextButton.icon(
          key: const ValueKey('auto-convert-toggle'),
          style: enabled
              ? TextButton.styleFrom(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: onColor,
                )
              : null,
          icon: Icon(enabled ? Icons.auto_awesome : Icons.auto_awesome_outlined),
          label: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Auto'),
              if (enabled)
                Text(
                  fontLabel,
                  key: const ValueKey('auto-convert-font'),
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: onColor, height: 1),
                ),
            ],
          ),
          onPressed: onPressed,
        ),
      );
    }
    return IconButton(
      key: const ValueKey('auto-convert-toggle'),
      isSelected: enabled,
      icon: const Icon(Icons.auto_awesome_outlined),
      selectedIcon: const Icon(Icons.auto_awesome),
      tooltip: tooltip,
      style: enabled
          ? IconButton.styleFrom(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: onColor,
            )
          : null,
      onPressed: onPressed,
    );
  }
}
