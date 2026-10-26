import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../lock/pin_setup_screen.dart';
import '../settings_controller.dart';
import 'settings_section.dart';

/// Settings › Security: set, change or remove the app-lock PIN and choose
/// how soon the app locks again in the background.
class SecuritySettings extends ConsumerWidget {
  const SecuritySettings({super.key});

  /// "Lock after" choices in seconds, with their labels.
  static const List<(int, String)> lockAfterChoices = [
    (0, 'Immediately'),
    (60, '1 min'),
    (300, '5 min'),
    (900, '15 min'),
  ];

  /// Label for a delay of [seconds]; also covers values that aren't one of
  /// [lockAfterChoices] (e.g. edited by a future version).
  static String lockAfterLabel(int seconds) {
    for (final (s, label) in lockAfterChoices) {
      if (s == seconds) return label;
    }
    if (seconds > 0 && seconds % 60 == 0) return '${seconds ~/ 60} min';
    return '$seconds s';
  }

  Future<void> _run(
    BuildContext context,
    PinSetupMode mode,
    String doneMessage,
  ) async {
    final done = await PinSetupScreen.open(context, mode);
    if (!done || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(doneMessage)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final scheme = Theme.of(context).colorScheme;
    final enabled = settings.appLockEnabled;
    final lockAfter = settings.lockAfterSeconds;
    final choices = [
      ...lockAfterChoices,
      if (!lockAfterChoices.any((c) => c.$1 == lockAfter))
        (lockAfter, lockAfterLabel(lockAfter)),
    ];

    return SettingsSection(
      title: 'Security',
      icon: Icons.shield_outlined,
      children: [
        if (!enabled)
          ListTile(
            key: const ValueKey('settings-set-pin'),
            leading: const Icon(Icons.lock_open_rounded),
            title: const Text('App lock'),
            subtitle: const Text(
                'Off. Set a 4 to 8 digit PIN to lock NeatInk.'),
            trailing: FilledButton.tonal(
              onPressed: () =>
                  _run(context, PinSetupMode.set, 'App lock is on.'),
              child: const Text('Set PIN'),
            ),
            onTap: () => _run(context, PinSetupMode.set, 'App lock is on.'),
          )
        else ...[
          ListTile(
            leading: Icon(Icons.lock_rounded, color: scheme.primary),
            title: const Text('App lock is on'),
            subtitle: const Text(
                'NeatInk asks for your PIN when it opens and when you come '
                'back to it.'),
          ),
          SettingsChoiceTile<int>(
            key: const ValueKey('settings-lock-after'),
            title: 'Lock after',
            subtitle: 'How long NeatInk can be in the background before '
                'the PIN is needed again.',
            value: lockAfter,
            choices: choices,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(lockAfterSeconds: v)),
          ),
          ListTile(
            key: const ValueKey('settings-change-pin'),
            leading: const Icon(Icons.pin_outlined),
            title: const Text('Change PIN'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _run(context, PinSetupMode.change, 'PIN changed.'),
          ),
          ListTile(
            key: const ValueKey('settings-remove-pin'),
            leading: Icon(Icons.no_encryption_outlined, color: scheme.error),
            title: Text('Remove PIN', style: TextStyle(color: scheme.error)),
            subtitle: const Text('Turns the app lock off.'),
            onTap: () =>
                _run(context, PinSetupMode.remove, 'App lock is off.'),
          ),
        ],
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: PinRecoveryWarning(),
        ),
      ],
    );
  }
}
