import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings_controller.dart';
import 'tips_screen.dart';

/// Opens the [TipsScreen] over [child] the first time the app is shown
/// (`AppSettings.tipsSeen`), then never again; Settings keeps a link to it.
///
/// It sits under the app lock's gate, which builds nothing while locked, so
/// the tips appear after the PIN is entered, not behind the keypad.
class TipsOnce extends ConsumerStatefulWidget {
  const TipsOnce({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TipsOnce> createState() => _TipsOnceState();
}

class _TipsOnceState extends ConsumerState<TipsOnce> {
  @override
  void initState() {
    super.initState();
    if (ref.read(settingsProvider).tipsSeen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ref.read(settingsProvider).tipsSeen) return;
      // Marked first, so they show once even if the app is closed on them.
      ref.read(settingsProvider.notifier).update((s) => s.copyWith(tipsSeen: true));
      TipsScreen.open(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
