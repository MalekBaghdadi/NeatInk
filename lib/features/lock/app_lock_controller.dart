import 'dart:math' as math;
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../settings/app_settings.dart';
import '../settings/settings_controller.dart';
import 'auto_lock_suspension.dart';

/// What the PIN app lock currently shows. See [AppLockController].
@immutable
class AppLockState {
  const AppLockState({
    required this.locked,
    required this.obscured,
    required this.contentMounted,
  });

  /// The app lock is off (or has just been unlocked) and the app is in the
  /// foreground.
  static const AppLockState open =
      AppLockState(locked: false, obscured: false, contentMounted: true);

  /// The PIN screen is up; the app's content is hidden.
  final bool locked;

  /// The app is not in the foreground (app switcher, notification shade,
  /// background), so its content is covered.
  final bool obscured;

  /// The app's content has been built at least once. False only between a
  /// locked cold start and the first unlock, so no notebook is even loaded
  /// before the right PIN is entered.
  final bool contentMounted;

  /// Whether the app's content must not be visible right now.
  bool get contentHidden => locked || obscured;

  AppLockState copyWith({bool? locked, bool? obscured, bool? contentMounted}) =>
      AppLockState(
        locked: locked ?? this.locked,
        obscured: obscured ?? this.obscured,
        contentMounted: contentMounted ?? this.contentMounted,
      );

  @override
  bool operator ==(Object other) =>
      other is AppLockState &&
      other.locked == locked &&
      other.obscured == obscured &&
      other.contentMounted == contentMounted;

  @override
  int get hashCode => Object.hash(locked, obscured, contentMounted);

  @override
  String toString() => 'AppLockState(locked: $locked, obscured: $obscured, '
      'contentMounted: $contentMounted)';
}

/// The app lock's state: whether the PIN screen or the privacy cover is up.
/// `LockGate` shows it and feeds it the app lifecycle.
final appLockProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);

/// Decides when the app is locked, from the app lifecycle, the settings
/// ([AppSettings.appLockEnabled], [AppSettings.lockAfterSeconds]) and the
/// wall clock ([clockProvider], replaceable in tests).
///
/// * Cold start with a PIN set: locked.
/// * Hidden/paused: the content is covered, and the time is noted. With
///   "Lock after: immediately" it locks right away, so the content is
///   already gone when the app becomes visible again.
/// * Resumed after at least `lockAfterSeconds` in the background: locked.
/// * Inactive (notification shade, app switcher): covered, not locked.
/// * While [AutoLockSuspension.during] runs (a file picker or share sheet
///   is open), the app may stay in the background for at least
///   [AutoLockSuspension.minimumTimeout] before it locks.
/// * Setting a PIN does not lock the running app; removing it unlocks it.
class AppLockController extends Notifier<AppLockState> {
  /// When the app was last hidden, or null while it's in the foreground.
  DateTime? _backgroundedAt;

  /// The app went to the background inside [AutoLockSuspension.during].
  bool _backgroundedWhileSuspended = false;

  @override
  AppLockState build() {
    ref.listen(
      settingsProvider.select((s) => s.appLockEnabled),
      (_, enabled) {
        if (!enabled) {
          _backgroundedAt = null;
          state = AppLockState.open;
        }
      },
    );
    // Read, not watch: turning the lock on must not lock the running app.
    final enabled = ref.read(settingsProvider).appLockEnabled;
    return enabled
        ? const AppLockState(
            locked: true,
            obscured: false,
            contentMounted: false,
          )
        : AppLockState.open;
  }

  @override
  bool updateShouldNotify(AppLockState previous, AppLockState next) =>
      previous != next;

  /// Whether the PIN screen is up.
  bool get isLocked => state.locked;

  DateTime _now() => ref.read(clockProvider)();

  /// Feeds an app lifecycle change (from an `AppLifecycleListener`).
  void handleLifecycle(AppLifecycleState lifecycle) {
    final settings = ref.read(settingsProvider);
    if (!settings.appLockEnabled) {
      _backgroundedAt = null;
      state = AppLockState.open;
      return;
    }
    switch (lifecycle) {
      case AppLifecycleState.inactive:
        state = state.copyWith(obscured: true);
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_backgroundedAt == null) {
          _backgroundedAt = _now();
          _backgroundedWhileSuspended = AutoLockSuspension.isActive;
        }
        final lockNow =
            settings.lockAfterSeconds <= 0 && !_backgroundedWhileSuspended;
        state = state.copyWith(obscured: true, locked: state.locked || lockNow);
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        final timedOut =
            since != null && _timedOut(since, settings.lockAfterSeconds);
        state =
            state.copyWith(obscured: false, locked: state.locked || timedOut);
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Opens the app. Call only after the PIN was verified.
  void unlock() {
    state = state.copyWith(locked: false, contentMounted: true);
  }

  bool _timedOut(DateTime backgroundedAt, int lockAfterSeconds) {
    var timeout = Duration(seconds: math.max(0, lockAfterSeconds));
    if (_backgroundedWhileSuspended &&
        timeout < AutoLockSuspension.minimumTimeout) {
      timeout = AutoLockSuspension.minimumTimeout;
    }
    final away = _now().difference(backgroundedAt);
    // A clock that moved backwards can't prove the timeout hasn't passed.
    return away.isNegative || away >= timeout;
  }
}
