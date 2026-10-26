import 'package:flutter/material.dart';

import 'verify_pin_view.dart';

/// Full-screen lock shown by `LockGate` until the right PIN is entered.
///
/// It is built above the app's Navigator, so it must not open dialogs or
/// routes; help is shown inline instead.
class PinLockScreen extends StatelessWidget {
  const PinLockScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: VerifyPinView(
          title: 'NeatInk is locked',
          subtitle: 'Enter your PIN to open your notebooks.',
          submitLabel: 'Unlock',
          onVerified: onUnlocked,
          footer: const ForgotPinHelp(),
        ),
      ),
    );
  }
}

/// "Forgot your PIN?" link that expands into an honest explanation.
class ForgotPinHelp extends StatefulWidget {
  const ForgotPinHelp({super.key});

  /// What happens when the PIN is forgotten. Also shown in Settings.
  static const String explanation =
      "A forgotten PIN can't be recovered: NeatInk keeps no copy of it and "
      'has no account to reset it with. The only way back in is to clear '
      "NeatInk's data in Android Settings › Apps › NeatInk › Storage, which "
      'permanently deletes all your notebooks.';

  @override
  State<ForgotPinHelp> createState() => _ForgotPinHelpState();
}

class _ForgotPinHelpState extends State<ForgotPinHelp> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? 'Hide' : 'Forgot your PIN?'),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  ForgotPinHelp.explanation,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
