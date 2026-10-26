import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pin_hasher.dart';
import 'pin_keypad.dart';

/// Checks a submitted PIN. Return true to accept it, false to reject it
/// (the dots shake and clear).
typedef PinSubmitHandler = Future<bool> Function(String pin);

/// A full PIN entry panel: heading, digit dots, a status line and the
/// keypad. Also accepts digits, Backspace and Enter from a hardware
/// keyboard.
///
/// Lays itself out as a column, or side by side (heading left, keypad right)
/// when the space is wide but short, e.g. a phone in landscape.
class PinEntryView extends StatefulWidget {
  const PinEntryView({
    super.key,
    required this.title,
    required this.onSubmit,
    this.subtitle,
    this.message,
    this.messageIsError = false,
    this.enabled = true,
    this.icon = Icons.lock_outline_rounded,
    this.submitLabel = 'OK',
    this.footer,
  });

  final String title;
  final String? subtitle;

  /// Status line under the dots (e.g. "Wrong PIN" or a countdown).
  final String? message;
  final bool messageIsError;

  /// False disables the keypad (cooldown).
  final bool enabled;

  final IconData icon;

  /// Accessibility label of the ✓ key.
  final String submitLabel;

  final PinSubmitHandler onSubmit;

  /// Optional content under the keypad (help text, buttons).
  final Widget? footer;

  @override
  State<PinEntryView> createState() => _PinEntryViewState();
}

class _PinEntryViewState extends State<PinEntryView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  String _digits = '';
  bool _busy = false;
  String? _localError;
  bool _showErrorDots = false;

  bool get _inputEnabled => widget.enabled && !_busy;

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _addDigit(String d) {
    if (!_inputEnabled || _digits.length >= PinHasher.maxLength) return;
    setState(() {
      _digits += d;
      _localError = null;
      _showErrorDots = false;
    });
  }

  void _backspace() {
    if (!_inputEnabled || _digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  void _clear() {
    if (!_inputEnabled) return;
    setState(() => _digits = '');
  }

  Future<void> _submit() async {
    if (!_inputEnabled) return;
    if (_digits.length < PinHasher.minLength) {
      setState(() => _localError =
          'Enter ${PinHasher.minLength} to ${PinHasher.maxLength} digits');
      _playShake();
      return;
    }
    final pin = _digits;
    setState(() => _busy = true);
    final accepted = await widget.onSubmit(pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!accepted) {
        _digits = '';
        _showErrorDots = true;
      }
    });
    if (!accepted) _playShake();
  }

  void _playShake() {
    unawaited(HapticFeedback.mediumImpact());
    unawaited(_shake.forward(from: 0));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) unawaited(_submit());
      return KeyEventResult.handled;
    }
    final char = event.character;
    if (char != null && char.length == 1 && '0123456789'.contains(char)) {
      _addDigit(char);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final message = _localError ?? widget.message;
    final messageIsError = _localError != null || widget.messageIsError;

    final heading = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(widget.icon, size: 32, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(height: 20),
        Text(
          widget.title,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              widget.subtitle!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        const SizedBox(height: 28),
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            // Damped sine: three left-right swings that die out.
            final t = _shake.value;
            final dx = math.sin(t * math.pi * 6) * 14 * (1 - t);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: PinDots(
            length: _digits.length,
            error: _showErrorDots || (messageIsError && _digits.isEmpty),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: Center(
            child: message == null
                ? null
                : Text(
                    message,
                    key: const ValueKey('pin-message'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: messageIsError
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                  ),
          ),
        ),
      ],
    );

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sideBySide = constraints.maxWidth > constraints.maxHeight &&
              constraints.maxHeight < 620;
          // Fit four rows of keys into the available height.
          final keypadHeightBudget = sideBySide
              ? constraints.maxHeight - 32
              : constraints.maxHeight - 360 - (widget.footer == null ? 0 : 80);
          final keySize = (keypadHeightBudget /
                  (4 + PinKeypad.gapFactor * 3))
              .clamp(52.0, 84.0);
          final keypad = PinKeypad(
            keySize: keySize,
            enabled: _inputEnabled,
            canSubmit: _digits.isNotEmpty,
            submitLabel: widget.submitLabel,
            onDigit: _addDigit,
            onBackspace: _backspace,
            onClear: _clear,
            onSubmit: _submit,
          );
          final footer = widget.footer;
          final content = sideBySide
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [heading, ?footer],
                      ),
                    ),
                    const SizedBox(width: 48),
                    keypad,
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    heading,
                    const SizedBox(height: 8),
                    keypad,
                    if (footer != null) ...[
                      const SizedBox(height: 16),
                      footer,
                    ],
                  ],
                );
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: content,
            ),
          );
        },
      ),
    );
  }
}
