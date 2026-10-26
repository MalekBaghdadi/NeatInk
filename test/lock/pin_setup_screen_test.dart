import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/features/lock/pin_attempt_limiter.dart';
import 'package:neatink/features/lock/pin_setup_screen.dart';
import 'package:neatink/features/settings/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lock_test_support.dart';

void main() {
  late SharedPreferences prefs;
  late DateTime now;

  setUp(() async {
    now = DateTime(2026, 10, 25, 9);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  /// The result [PinSetupScreen.open] completed with, or null while open.
  bool? result;

  Future<ProviderContainer> openFlow(
    WidgetTester tester,
    PinSetupMode mode,
  ) async {
    result = null;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async =>
                    result = await PinSetupScreen.open(context, mode),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(Scaffold).last));
  }

  group('set', () {
    testWidgets('asks for the PIN twice and turns the lock on',
        (tester) async {
      final c = await openFlow(tester, PinSetupMode.set);
      expect(find.text('Choose a PIN'), findsOneWidget);
      // The recovery warning is shown before the PIN is chosen.
      expect(find.textContaining("can't be recovered"), findsOneWidget);

      await enterPin(tester, '482193');
      expect(find.text('Enter the PIN again'), findsOneWidget);
      await enterPin(tester, '482193');

      expect(result, isTrue);
      expect(find.byType(PinSetupScreen), findsNothing);
      final notifier = c.read(settingsProvider.notifier);
      expect(c.read(settingsProvider).appLockEnabled, isTrue);
      expect(notifier.verifyPin('482193'), isTrue);
    });

    testWidgets('a mismatch starts over and changes nothing', (tester) async {
      final c = await openFlow(tester, PinSetupMode.set);

      await enterPin(tester, '1111');
      await enterPin(tester, '2222');

      expect(find.text('Choose a PIN'), findsOneWidget);
      expect(pinMessage(tester), "The PINs didn't match. Choose a PIN again.");
      expect(c.read(settingsProvider).appLockEnabled, isFalse);

      await enterPin(tester, '3333');
      await enterPin(tester, '3333');
      expect(result, isTrue);
      expect(c.read(settingsProvider.notifier).verifyPin('3333'), isTrue);
    });

    testWidgets('requires at least 4 digits', (tester) async {
      await openFlow(tester, PinSetupMode.set);

      await enterPin(tester, '123');

      expect(find.text('Choose a PIN'), findsOneWidget);
      expect(pinMessage(tester), 'Enter 4 to 8 digits');
    });

    testWidgets('accepts at most 8 digits', (tester) async {
      final c = await openFlow(tester, PinSetupMode.set);

      await enterPin(tester, '1234567890'); // the 9th and 10th are ignored
      await enterPin(tester, '12345678');

      expect(result, isTrue);
      expect(c.read(settingsProvider.notifier).verifyPin('12345678'), isTrue);
    });

    testWidgets('backing out changes nothing', (tester) async {
      final c = await openFlow(tester, PinSetupMode.set);
      await enterPin(tester, '1234');

      // A full-screen dialog route: the app bar shows a close (×) button.
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(c.read(settingsProvider).appLockEnabled, isFalse);
    });
  });

  group('change', () {
    testWidgets('needs the current PIN, then a new one twice',
        (tester) async {
      await storePin(prefs, '1234');
      final c = await openFlow(tester, PinSetupMode.change);
      expect(find.text('Enter your current PIN'), findsOneWidget);

      await enterPin(tester, '9999');
      expect(find.text('Enter your current PIN'), findsOneWidget);
      expect(pinMessage(tester), 'Wrong PIN. Try again.');

      await enterPin(tester, '1234');
      expect(find.text('Choose a new PIN'), findsOneWidget);
      await enterPin(tester, '5678');
      await enterPin(tester, '5678');

      expect(result, isTrue);
      final notifier = c.read(settingsProvider.notifier);
      expect(notifier.verifyPin('5678'), isTrue);
      expect(notifier.verifyPin('1234'), isFalse);
      // The correct current PIN reset the wrong-attempt counter.
      expect(prefs.getInt(PinAttemptLimiter.failuresKey), isNull);
    });

    testWidgets('shares the wrong-PIN cooldown with the lock screen',
        (tester) async {
      await storePin(prefs, '1234');
      await openFlow(tester, PinSetupMode.change);

      for (var i = 0; i < 5; i++) {
        await enterPin(tester, '0000');
      }

      expect(pinMessage(tester), 'Too many wrong PINs. Try again in 0:30.');
      await enterPin(tester, '1234');
      expect(find.text('Enter your current PIN'), findsOneWidget);
      expect(prefs.getInt(PinAttemptLimiter.failuresKey), 5);
    });
  });

  group('remove', () {
    testWidgets('needs the current PIN and turns the lock off',
        (tester) async {
      await storePin(prefs, '1234');
      final c = await openFlow(tester, PinSetupMode.remove);
      expect(find.text('This turns the app lock off.'), findsOneWidget);

      await enterPin(tester, '4321');
      expect(c.read(settingsProvider).appLockEnabled, isTrue);

      await enterPin(tester, '1234');
      expect(result, isTrue);
      expect(c.read(settingsProvider).appLockEnabled, isFalse);
    });
  });
}
