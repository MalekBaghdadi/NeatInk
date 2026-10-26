import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/lock/pin_hasher.dart';
import 'package:neatink/features/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lifecycle states Android reports when the app leaves the foreground, in
/// order (each step is a valid `AppLifecycleListener` transition).
const List<AppLifecycleState> backgroundStates = [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];

/// Lifecycle states Android reports when the app comes back, in order.
const List<AppLifecycleState> foregroundStates = [
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
];

/// Writes settings with [pin] set straight into [prefs], as if the user had
/// set it in an earlier session. Uses a fixed salt so tests are repeatable.
Future<void> storePin(
  SharedPreferences prefs,
  String pin, {
  int lockAfterSeconds = 0,
}) async {
  const salt = '0f1e2d3c4b5a69788796a5b4c3d2e1f0';
  final settings = AppSettings(
    pinSalt: salt,
    pinHash: PinHasher.hash(pin, salt),
    lockAfterSeconds: lockAfterSeconds,
  );
  await prefs.setString(AppSettings.prefsKey, jsonEncode(settings.toJson()));
}

/// Sends a lifecycle change as the engine does. The binding fills in the
/// intermediate states (resumed → paused goes through inactive and hidden).
Future<void> sendLifecycle(WidgetTester tester, AppLifecycleState state) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
    (_) {},
  );
  await tester.pump();
}

/// Puts the app back in the foreground at the end of a test, so the next
/// test starts from `resumed` (the binding is shared between tests).
void resumeAfterTest(WidgetTester tester) {
  addTearDown(() async {
    if (tester.binding.lifecycleState == AppLifecycleState.resumed) return;
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.lifecycle.name,
      SystemChannels.lifecycle.codec
          .encodeMessage(AppLifecycleState.resumed.toString()),
      (_) {},
    );
  });
}

/// Presses the system Back button.
Future<void> pressSystemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    SystemChannels.navigation.codec
        .encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
  await tester.pumpAndSettle();
}

/// Types [pin] on the on-screen keypad and presses ✓.
Future<void> enterPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.byKey(ValueKey('pin-key-$digit')));
    await tester.pump();
  }
  await tester.tap(find.byKey(const ValueKey('pin-key-submit')));
  await tester.pumpAndSettle();
}

/// The status line under the PIN dots, or null when there is none.
String? pinMessage(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('pin-message'));
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Text>(finder).data;
}
