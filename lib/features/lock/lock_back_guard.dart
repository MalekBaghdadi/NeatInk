import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_lock_controller.dart';

/// Swallows the system Back action while the app is locked.
///
/// `LockGate` keeps the app's Navigator mounted (offstage) under the lock
/// screen. Without this guard, Back would silently pop the hidden editor
/// or a dialog while the PIN screen is showing.
///
/// It must wrap the `MaterialApp`, not sit inside it: the binding offers
/// Back to its observers in registration order and stops at the first one
/// that handles it, so this observer has to register before the app's own
/// (an ancestor's `initState` runs first).
class LockBackGuard extends ConsumerStatefulWidget {
  const LockBackGuard({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LockBackGuard> createState() => _LockBackGuardState();
}

class _LockBackGuardState extends ConsumerState<LockBackGuard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// True ("handled") while locked, so nothing behind the lock screen pops.
  @override
  Future<bool> didPopRoute() async => ref.read(appLockProvider).locked;

  @override
  Widget build(BuildContext context) => widget.child;
}
