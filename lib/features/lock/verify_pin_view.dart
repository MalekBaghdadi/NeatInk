import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings_controller.dart';
import 'lock_providers.dart';
import 'pin_attempt_limiter.dart';
import 'pin_entry_view.dart';

/// Asks for the current PIN and calls [onVerified] when it's right.
///
/// Wrong PINs go through the shared [PinAttemptLimiter]: after too many, the
/// keypad is disabled and a countdown shows until the next try is allowed.
/// Used by the lock screen and by "Change PIN" / "Remove PIN".
class VerifyPinView extends ConsumerStatefulWidget {
  const VerifyPinView({
    super.key,
    required this.title,
    required this.onVerified,
    this.subtitle,
    this.submitLabel = 'Unlock',
    this.icon = Icons.lock_outline_rounded,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final String submitLabel;
  final IconData icon;
  final VoidCallback onVerified;
  final Widget? footer;

  @override
  ConsumerState<VerifyPinView> createState() => _VerifyPinViewState();
}

class _VerifyPinViewState extends ConsumerState<VerifyPinView> {
  Timer? _ticker;
  Duration _cooldown = Duration.zero;
  String? _message;
  bool _messageIsError = false;

  PinAttemptLimiter get _limiter => ref.read(pinAttemptLimiterProvider);

  @override
  void initState() {
    super.initState();
    _syncCooldown();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Reads the remaining cooldown and starts/stops the 1 s countdown ticker.
  void _syncCooldown() {
    final wasCoolingDown = _cooldown > Duration.zero;
    _cooldown = _limiter.remainingCooldown();
    if (_cooldown > Duration.zero) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(_syncCooldown);
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
      if (wasCoolingDown) {
        _message = 'You can try again now.';
        _messageIsError = false;
      }
    }
  }

  Future<bool> _check(String pin) async {
    final limiter = _limiter;
    if (!limiter.canAttempt) {
      setState(_syncCooldown);
      return false;
    }
    if (ref.read(settingsProvider.notifier).verifyPin(pin)) {
      await limiter.recordSuccess();
      if (mounted) widget.onVerified();
      return true;
    }
    final cooldown = await limiter.recordFailure();
    if (!mounted) return false;
    setState(() {
      if (cooldown > Duration.zero) {
        _message = null;
        _syncCooldown();
      } else {
        final left = limiter.attemptsBeforeCooldown;
        final wait =
            PinAttemptLimiter.cooldownAfter(PinAttemptLimiter.freeAttempts);
        _message = left <= 2
            ? 'Wrong PIN. $left ${left == 1 ? 'attempt' : 'attempts'} left '
                'before a ${describeWait(wait)} wait.'
            : 'Wrong PIN. Try again.';
        _messageIsError = true;
      }
    });
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final coolingDown = _cooldown > Duration.zero;
    return PinEntryView(
      title: widget.title,
      subtitle: widget.subtitle,
      icon: widget.icon,
      submitLabel: widget.submitLabel,
      enabled: !coolingDown,
      message: coolingDown
          ? 'Too many wrong PINs. Try again in ${formatCountdown(_cooldown)}.'
          : _message,
      messageIsError: coolingDown || _messageIsError,
      onSubmit: _check,
      footer: widget.footer,
    );
  }
}

/// `m:ss`, rounding up so the countdown never shows 0:00 while waiting.
String formatCountdown(Duration d) {
  final total = (d.inMilliseconds / 1000).ceil();
  final m = total ~/ 60, s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// "30-second", "2-minute": the length of a wait as an adjective.
String describeWait(Duration d) => d.inSeconds < 60
    ? '${d.inSeconds}-second'
    : '${d.inMinutes}-minute';
