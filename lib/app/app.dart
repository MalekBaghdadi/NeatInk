import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/library/library_screen.dart';
import '../features/lock/lock_back_guard.dart';
import '../features/lock/lock_gate.dart';
import '../features/settings/settings_controller.dart';
import '../features/tips/tips_once.dart';
import 'app_info.dart';
import 'theme.dart';

/// The root widget: Material 3 app with light/dark themes from settings,
/// the library as home, and the PIN app lock in front of every route. The
/// Tips screen opens by itself the first time.
class NeatInkApp extends ConsumerWidget {
  const NeatInkApp({super.key, this.home = const LibraryScreen()});

  /// The first screen. Overridable for tests.
  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return LockBackGuard(
      child: MaterialApp(
        title: AppInfo.name,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: AppTheme.themeModeFor(themeMode),
        home: TipsOnce(child: home),
        // LockGate wraps the Navigator (not just `home`), so a locked app
        // also hides the editor and any dialog pushed over the library.
        builder: (context, navigator) =>
            LockGate(child: navigator ?? const SizedBox.shrink()),
      ),
    );
  }
}
