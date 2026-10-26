import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import 'app_lock_controller.dart';
import 'pin_lock_screen.dart';

/// Guards [child] (the whole app, including every pushed route) with the
/// PIN app lock. When to lock is decided by [AppLockController]; this
/// widget feeds it the app lifecycle and shows its state:
///
/// * Locked on a cold start: only the lock screen is built. [child] is not
///   built at all until the PIN is entered, so no notebook is loaded.
/// * Locked again after the background: [child] stays mounted but
///   offstage (not painted, not hit-testable, no semantics, no focus,
///   tickers off), so the editor's place and unsaved strokes survive.
/// * Inactive or in the background: a neutral cover hides [child], so the
///   recent-apps thumbnail doesn't show notes.
///
/// Put it above the Navigator (in `MaterialApp.builder`) so it also covers
/// routes pushed on top of the home screen, and put a `LockBackGuard`
/// above the `MaterialApp` so Back can't pop hidden routes while locked.
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) =>
          ref.read(appLockProvider.notifier).handleLifecycle(state),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _unlock() => ref.read(appLockProvider.notifier).unlock();

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final hidden = lock.contentHidden;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (lock.contentMounted || !lock.locked)
          KeyedSubtree(
            key: const ValueKey('lock-gate-content'),
            child: Offstage(
              offstage: hidden,
              child: TickerMode(
                enabled: !hidden,
                child: ExcludeFocus(excluding: lock.locked, child: widget.child),
              ),
            ),
          ),
        if (lock.locked)
          // The lock screen sits above the Navigator, so give it its own
          // Overlay for tooltips, ink splashes and text selection.
          Overlay.wrap(
            key: const ValueKey('lock-gate-lock-screen'),
            child: PinLockScreen(onUnlocked: _unlock),
          )
        else if (lock.obscured)
          const PrivacyCover(key: ValueKey('lock-gate-cover')),
      ],
    );
  }
}

/// Neutral screen shown instead of the app's content while it's inactive.
class PrivacyCover extends StatelessWidget {
  const PrivacyCover({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 40, color: scheme.primary),
            const SizedBox(height: 12),
            Text(AppInfo.name, style: theme.textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
