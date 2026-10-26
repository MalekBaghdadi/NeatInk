import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings_controller.dart';
import 'pin_entry_view.dart';
import 'pin_lock_screen.dart';
import 'verify_pin_view.dart';

/// What [PinSetupScreen] does.
enum PinSetupMode {
  /// Choose a PIN (twice) to turn the app lock on.
  set,

  /// Current PIN, then a new one (twice).
  change,

  /// Current PIN, then the lock is turned off.
  remove,
}

enum _Step { current, choose, confirm }

/// The Settings flows for setting, changing and removing the app-lock PIN.
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key, required this.mode});

  final PinSetupMode mode;

  /// Pushes the flow. Completes with true if the PIN was set, changed or
  /// removed, false if the user backed out.
  static Future<bool> open(BuildContext context, PinSetupMode mode) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        settings: RouteSettings(name: '/pin/${mode.name}'),
        builder: (_) => PinSetupScreen(mode: mode),
      ),
    );
    return done ?? false;
  }

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  late _Step _step =
      widget.mode == PinSetupMode.set ? _Step.choose : _Step.current;

  /// The PIN typed in the "choose" step, awaiting confirmation.
  String? _chosenPin;

  /// Shown on the "choose" step after a mismatch.
  String? _chooseError;

  String get _title => switch (widget.mode) {
        PinSetupMode.set => 'Set a PIN',
        PinSetupMode.change => 'Change PIN',
        PinSetupMode.remove => 'Remove PIN',
      };

  void _onCurrentVerified() {
    if (widget.mode == PinSetupMode.remove) {
      ref.read(settingsProvider.notifier).clearPin();
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _step = _Step.choose);
  }

  Future<bool> _onChosen(String pin) async {
    setState(() {
      _chosenPin = pin;
      _chooseError = null;
      _step = _Step.confirm;
    });
    return true;
  }

  Future<bool> _onConfirmed(String pin) async {
    if (pin != _chosenPin) {
      setState(() {
        _chosenPin = null;
        _chooseError = "The PINs didn't match. Choose a PIN again.";
        _step = _Step.choose;
      });
      return false;
    }
    ref.read(settingsProvider.notifier).setPin(pin);
    Navigator.of(context).pop(true);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (_step) {
      _Step.current => VerifyPinView(
          key: const ValueKey('pin-step-current'),
          title: 'Enter your current PIN',
          subtitle: widget.mode == PinSetupMode.remove
              ? 'This turns the app lock off.'
              : null,
          submitLabel: 'Continue',
          onVerified: _onCurrentVerified,
        ),
      _Step.choose => PinEntryView(
          key: const ValueKey('pin-step-choose'),
          title: widget.mode == PinSetupMode.change
              ? 'Choose a new PIN'
              : 'Choose a PIN',
          subtitle: 'Use 4 to 8 digits.',
          icon: Icons.pin_outlined,
          message: _chooseError,
          messageIsError: _chooseError != null,
          submitLabel: 'Continue',
          onSubmit: _onChosen,
          footer: const PinRecoveryWarning(),
        ),
      _Step.confirm => PinEntryView(
          key: const ValueKey('pin-step-confirm'),
          title: 'Enter the PIN again',
          subtitle: 'To make sure it was typed correctly.',
          icon: Icons.pin_outlined,
          submitLabel: 'Save PIN',
          onSubmit: _onConfirmed,
        ),
    };
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(child: body),
    );
  }
}

/// A short, visible warning that a forgotten PIN can't be recovered.
class PinRecoveryWarning extends StatelessWidget {
  const PinRecoveryWarning({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: scheme.onErrorContainer, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ForgotPinHelp.explanation,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
