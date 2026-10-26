import 'package:flutter/material.dart';

/// A large numeric keypad for entering a PIN with a finger or the pen:
///
/// ```
///  1  2  3
///  4  5  6
///  7  8  9
///  ⌫  0  ✓
/// ```
///
/// Long-pressing ⌫ clears everything.
class PinKeypad extends StatelessWidget {
  const PinKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.onSubmit,
    this.enabled = true,
    this.canSubmit = true,
    this.keySize = 76,
    this.submitLabel = 'OK',
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSubmit;

  /// False while waiting out a cooldown or checking a PIN.
  final bool enabled;

  /// Whether the ✓ key is active (enough digits entered).
  final bool canSubmit;

  /// Diameter of each key in logical pixels.
  final double keySize;

  /// Accessibility label of the ✓ key, e.g. "Unlock".
  final String submitLabel;

  /// Gap between keys relative to [keySize].
  static const double gapFactor = 0.28;

  /// Total height of the keypad for a given [keySize].
  static double heightFor(double keySize) =>
      keySize * 4 + keySize * gapFactor * 3;

  @override
  Widget build(BuildContext context) {
    final gap = keySize * gapFactor;
    Widget digit(String d) => _KeypadButton(
          key: ValueKey('pin-key-$d'),
          size: keySize,
          semanticLabel: d,
          onPressed: enabled ? () => onDigit(d) : null,
          child: Text(d),
        );
    Widget row(List<Widget> keys) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < keys.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              keys[i],
            ],
          ],
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row([digit('1'), digit('2'), digit('3')]),
        SizedBox(height: gap),
        row([digit('4'), digit('5'), digit('6')]),
        SizedBox(height: gap),
        row([digit('7'), digit('8'), digit('9')]),
        SizedBox(height: gap),
        row([
          _KeypadButton(
            key: const ValueKey('pin-key-backspace'),
            size: keySize,
            semanticLabel: 'Delete',
            subtle: true,
            onPressed: enabled ? onBackspace : null,
            onLongPress: enabled ? onClear : null,
            child: const Icon(Icons.backspace_outlined),
          ),
          digit('0'),
          _KeypadButton(
            key: const ValueKey('pin-key-submit'),
            size: keySize,
            semanticLabel: submitLabel,
            emphasized: true,
            onPressed: enabled && canSubmit ? onSubmit : null,
            child: const Icon(Icons.check_rounded),
          ),
        ]),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({
    super.key,
    required this.size,
    required this.semanticLabel,
    required this.onPressed,
    required this.child,
    this.onLongPress,
    this.emphasized = false,
    this.subtle = false,
  });

  final double size;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final Widget child;

  /// The primary action (✓): filled with the primary colour.
  final bool emphasized;

  /// Secondary actions (⌫): no fill.
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final Color background;
    final Color foreground;
    if (emphasized) {
      background = enabled ? scheme.primary : scheme.onSurface.withValues(alpha: 0.08);
      foreground = enabled ? scheme.onPrimary : scheme.onSurface.withValues(alpha: 0.38);
    } else {
      background = subtle ? Colors.transparent : scheme.surfaceContainerHighest;
      foreground = enabled
          ? scheme.onSurface
          : scheme.onSurface.withValues(alpha: 0.38);
    }
    final textStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w500,
          fontSize: size * 0.36,
        );

    // One clean semantics node per key ("7, button") instead of the
    // InkWell's and the label's nodes.
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      onTap: onPressed,
      onLongPress: onLongPress,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            onLongPress: onLongPress,
            child: Center(
              child: IconTheme.merge(
                data: IconThemeData(color: foreground, size: size * 0.36),
                child: DefaultTextStyle.merge(
                  style: textStyle,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Row of dots showing how many PIN digits have been typed (never the
/// digits). Shows at least [minSlots] slots so "4 to 8 digits" is visible.
class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.length,
    this.minSlots = 4,
    this.maxSlots = 8,
    this.error = false,
  });

  final int length;
  final int minSlots;
  final int maxSlots;

  /// Tints the dots with the error colour (wrong PIN).
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slots = length.clamp(minSlots, maxSlots);
    final filledColor = error ? scheme.error : scheme.primary;
    return Semantics(
      label: length == 1 ? '1 digit entered' : '$length digits entered',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < slots; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.symmetric(horizontal: 7),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < length ? filledColor : Colors.transparent,
                border: Border.all(
                  color: i < length ? filledColor : scheme.outline,
                  width: 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
