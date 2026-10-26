import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/features/lock/app_lock_controller.dart';
import 'package:neatink/features/lock/auto_lock_suspension.dart';
import 'package:neatink/features/settings/app_settings.dart';
import 'package:neatink/features/settings/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lock_test_support.dart';

void main() {
  late DateTime now;
  late SharedPreferences prefs;

  setUp(() async {
    now = DateTime(2026, 10, 25, 9);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<ProviderContainer> create({
    String? pin,
    int lockAfterSeconds = 0,
  }) async {
    if (pin != null) {
      await storePin(prefs, pin, lockAfterSeconds: lockAfterSeconds);
    }
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  AppLockState lockOf(ProviderContainer c) => c.read(appLockProvider);

  void lifecycle(ProviderContainer c, List<AppLifecycleState> states) {
    final notifier = c.read(appLockProvider.notifier);
    for (final s in states) {
      notifier.handleLifecycle(s);
    }
  }

  void toBackground(ProviderContainer c) => lifecycle(c, backgroundStates);
  void toForeground(ProviderContainer c) => lifecycle(c, foregroundStates);

  group('cold start', () {
    test('without a PIN the app is open', () async {
      final c = await create();
      expect(lockOf(c), AppLockState.open);
      expect(c.read(appLockProvider.notifier).isLocked, isFalse);
    });

    test('with a PIN it is locked and the content is not built yet', () async {
      final c = await create(pin: '1234');
      final s = lockOf(c);
      expect(s.locked, isTrue);
      expect(s.contentMounted, isFalse);
      expect(s.contentHidden, isTrue);
    });

    test('unlock opens it and mounts the content', () async {
      final c = await create(pin: '1234');
      c.read(appLockProvider.notifier).unlock();
      expect(lockOf(c), AppLockState.open);
    });
  });

  group('lock after a timeout', () {
    late ProviderContainer c;

    setUp(() async {
      c = await create(pin: '1234', lockAfterSeconds: 60);
      c.read(appLockProvider.notifier).unlock();
    });

    test('covers the content while in the background', () {
      toBackground(c);
      expect(lockOf(c).obscured, isTrue);
      expect(lockOf(c).locked, isFalse);
      expect(lockOf(c).contentHidden, isTrue);
    });

    test('does not lock when back before the timeout', () {
      toBackground(c);
      now = now.add(const Duration(seconds: 59));
      toForeground(c);
      expect(lockOf(c), AppLockState.open);
    });

    test('locks when back after the timeout', () {
      toBackground(c);
      now = now.add(const Duration(seconds: 60));
      toForeground(c);
      expect(lockOf(c).locked, isTrue);
      expect(lockOf(c).obscured, isFalse);
      // The content stays mounted (offstage) so the editor keeps its place.
      expect(lockOf(c).contentMounted, isTrue);
    });

    test('measures from when the app was first hidden', () {
      // hidden → paused must not restart the timer.
      lifecycle(c, [AppLifecycleState.inactive, AppLifecycleState.hidden]);
      now = now.add(const Duration(seconds: 40));
      lifecycle(c, [AppLifecycleState.paused]);
      now = now.add(const Duration(seconds: 20));
      toForeground(c);
      expect(lockOf(c).locked, isTrue);
    });

    test('a clock moved backwards locks', () {
      toBackground(c);
      now = now.subtract(const Duration(hours: 1));
      toForeground(c);
      expect(lockOf(c).locked, isTrue);
    });

    test('each background trip is timed on its own', () {
      toBackground(c);
      now = now.add(const Duration(seconds: 50));
      toForeground(c);
      now = now.add(const Duration(minutes: 10)); // in use, in the foreground
      toBackground(c);
      now = now.add(const Duration(seconds: 50));
      toForeground(c);
      expect(lockOf(c).locked, isFalse);
    });
  });

  test('"Immediately" locks as soon as the app is hidden', () async {
    final c = await create(pin: '1234', lockAfterSeconds: 0);
    c.read(appLockProvider.notifier).unlock();
    lifecycle(c, [AppLifecycleState.inactive]);
    expect(lockOf(c).locked, isFalse);
    lifecycle(c, [AppLifecycleState.hidden]);
    expect(lockOf(c).locked, isTrue);
    toForeground(c);
    expect(lockOf(c).locked, isTrue);
  });

  test('inactive only (notification shade) covers but never locks', () async {
    final c = await create(pin: '1234', lockAfterSeconds: 0);
    c.read(appLockProvider.notifier).unlock();
    lifecycle(c, [AppLifecycleState.inactive]);
    expect(lockOf(c).obscured, isTrue);
    now = now.add(const Duration(hours: 2));
    lifecycle(c, [AppLifecycleState.resumed]);
    expect(lockOf(c), AppLockState.open);
  });

  group('while a system picker is open (AutoLockSuspension)', () {
    test('"Immediately" waits at least the minimum timeout', () async {
      final c = await create(pin: '1234', lockAfterSeconds: 0);
      c.read(appLockProvider.notifier).unlock();
      final picker = Completer<void>();
      final during = AutoLockSuspension.during(() => picker.future);

      toBackground(c);
      expect(lockOf(c).locked, isFalse);
      now = now.add(AutoLockSuspension.minimumTimeout -
          const Duration(seconds: 1));
      toForeground(c);
      expect(lockOf(c).locked, isFalse);

      picker.complete();
      await during;
      expect(AutoLockSuspension.isActive, isFalse);
    });

    test('still locks after the minimum timeout', () async {
      final c = await create(pin: '1234', lockAfterSeconds: 0);
      c.read(appLockProvider.notifier).unlock();
      final picker = Completer<void>();
      final during = AutoLockSuspension.during(() => picker.future);

      toBackground(c);
      now = now.add(AutoLockSuspension.minimumTimeout);
      toForeground(c);
      expect(lockOf(c).locked, isTrue);

      picker.complete();
      await during;
    });

    test('a longer user timeout is kept', () async {
      final c = await create(pin: '1234', lockAfterSeconds: 900);
      c.read(appLockProvider.notifier).unlock();
      final picker = Completer<void>();
      final during = AutoLockSuspension.during(() => picker.future);

      toBackground(c);
      now = now.add(const Duration(minutes: 10));
      toForeground(c);
      expect(lockOf(c).locked, isFalse);

      picker.complete();
      await during;
    });
  });

  group('settings changes', () {
    test('setting a PIN does not lock the running app', () async {
      final c = await create();
      // LockGate reads the lock state on the first frame, before any PIN
      // can be set in Settings.
      expect(lockOf(c), AppLockState.open);
      c.read(settingsProvider.notifier).setPin('2468');
      expect(lockOf(c), AppLockState.open);
      // ...but it locks once the app goes to the background.
      toBackground(c);
      toForeground(c);
      expect(lockOf(c).locked, isTrue);
    });

    test('removing the PIN unlocks and uncovers the app', () async {
      final c = await create(pin: '1234');
      expect(lockOf(c).locked, isTrue);
      c.read(settingsProvider.notifier).clearPin();
      expect(lockOf(c), AppLockState.open);
    });

    test('without a PIN, lifecycle changes never cover the app', () async {
      final c = await create();
      toBackground(c);
      expect(lockOf(c), AppLockState.open);
      toForeground(c);
      expect(lockOf(c), AppLockState.open);
    });

    test('the timeout is read when the app returns', () async {
      final c = await create(pin: '1234', lockAfterSeconds: 900);
      c.read(appLockProvider.notifier).unlock();
      toBackground(c);
      c
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(lockAfterSeconds: 60));
      now = now.add(const Duration(minutes: 2));
      toForeground(c);
      expect(lockOf(c).locked, isTrue);
    });
  });

  test('AppLockState equality and copyWith', () {
    const a =
        AppLockState(locked: true, obscured: false, contentMounted: false);
    expect(a.copyWith(), a);
    expect(a.copyWith(locked: false),
        const AppLockState(locked: false, obscured: false, contentMounted: false));
    expect(a.hashCode, a.copyWith().hashCode);
    expect(AppLockState.open.contentHidden, isFalse);
    expect(const AppSettings().appLockEnabled, isFalse);
  });
}
