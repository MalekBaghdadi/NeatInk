import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/features/lock/app_lock_controller.dart';
import 'package:neatink/features/lock/lock_back_guard.dart';
import 'package:neatink/features/lock/lock_gate.dart';
import 'package:neatink/features/lock/pin_attempt_limiter.dart';
import 'package:neatink/features/lock/pin_lock_screen.dart';
import 'package:neatink/features/settings/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lock_test_support.dart';

/// How many times the guarded content was created (initState).
int notesCreated = 0;

/// Stand-in for the app behind the lock: some "private" text, a counter
/// (to prove its state survives a lock) and a button that pushes a route.
class _Notes extends StatefulWidget {
  const _Notes();

  @override
  State<_Notes> createState() => _NotesState();
}

class _NotesState extends State<_Notes> {
  int _taps = 0;

  @override
  void initState() {
    super.initState();
    notesCreated++;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            const Text('Secret notes'),
            Text('Taps: $_taps'),
            TextButton(
              onPressed: () => setState(() => _taps++),
              child: const Text('Tap'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const Scaffold(body: Text('Editor page')),
                ),
              ),
              child: const Text('Open editor'),
            ),
          ],
        ),
      );
}

void main() {
  late DateTime now;
  late SharedPreferences prefs;

  setUp(() async {
    notesCreated = 0;
    now = DateTime(2026, 10, 25, 9);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  /// Builds the app shell the way `NeatInkApp` does: LockBackGuard above
  /// MaterialApp, LockGate around the Navigator.
  Future<void> pumpApp(WidgetTester tester) async {
    resumeAfterTest(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => now),
      ],
      child: LockBackGuard(
        child: MaterialApp(
          home: const _Notes(),
          builder: (context, navigator) => LockGate(child: navigator!),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(LockGate)));

  Finder notes({bool skipOffstage = true}) =>
      find.text('Secret notes', skipOffstage: skipOffstage);
  final keypad = find.byKey(const ValueKey('pin-key-5'));

  Future<void> leaveFor(WidgetTester tester, Duration away) async {
    await sendLifecycle(tester, AppLifecycleState.paused);
    now = now.add(away);
    await sendLifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  testWidgets('without a PIN the app opens directly', (tester) async {
    await pumpApp(tester);
    expect(notes(), findsOneWidget);
    expect(find.byType(PinLockScreen), findsNothing);
  });

  testWidgets('with a PIN, a cold start shows the keypad and does not build '
      'the app', (tester) async {
    await storePin(prefs, '2468');
    await pumpApp(tester);

    expect(find.text('NeatInk is locked'), findsOneWidget);
    expect(keypad, findsOneWidget);
    expect(notes(skipOffstage: false), findsNothing);
    expect(notesCreated, 0);
  });

  testWidgets('the correct PIN unlocks', (tester) async {
    await storePin(prefs, '2468');
    await pumpApp(tester);

    await enterPin(tester, '2468');

    expect(find.byType(PinLockScreen), findsNothing);
    expect(notes(), findsOneWidget);
    expect(notesCreated, 1);
  });

  testWidgets('a wrong PIN keeps it locked and says so', (tester) async {
    await storePin(prefs, '2468');
    await pumpApp(tester);

    await enterPin(tester, '1357');

    expect(find.byType(PinLockScreen), findsOneWidget);
    expect(pinMessage(tester), 'Wrong PIN. Try again.');
    expect(notesCreated, 0);
  });

  testWidgets('a PIN shorter than 4 digits is not checked', (tester) async {
    await storePin(prefs, '2468');
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('pin-key-2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pin-key-submit')));
    await tester.pumpAndSettle();

    expect(pinMessage(tester), 'Enter 4 to 8 digits');
    expect(prefs.getInt(PinAttemptLimiter.failuresKey), isNull);
  });

  testWidgets('accepts the PIN from a hardware keyboard', (tester) async {
    await storePin(prefs, '2468');
    await pumpApp(tester);

    for (final key in [
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit8,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(notes(), findsOneWidget);
  });

  group('after the background', () {
    Future<void> unlockedApp(WidgetTester tester, int lockAfterSeconds) async {
      await storePin(prefs, '2468', lockAfterSeconds: lockAfterSeconds);
      await pumpApp(tester);
      await enterPin(tester, '2468');
      await tester.tap(find.text('Tap'));
      await tester.pump();
      expect(find.text('Taps: 1'), findsOneWidget);
    }

    testWidgets('does not relock before the timeout', (tester) async {
      await unlockedApp(tester, 60);

      await leaveFor(tester, const Duration(seconds: 59));

      expect(find.byType(PinLockScreen), findsNothing);
      expect(find.text('Taps: 1'), findsOneWidget);
    });

    testWidgets('relocks after the timeout and keeps the app state',
        (tester) async {
      await unlockedApp(tester, 60);

      await leaveFor(tester, const Duration(seconds: 61));

      expect(find.byType(PinLockScreen), findsOneWidget);
      // Still mounted (state kept) but offstage: not visible, not tappable.
      expect(notes(), findsNothing);
      expect(notes(skipOffstage: false), findsOneWidget);

      await enterPin(tester, '2468');
      expect(find.text('Taps: 1'), findsOneWidget);
      expect(notesCreated, 1);
    });

    testWidgets('"Immediately" shows the lock screen before the app is back',
        (tester) async {
      await unlockedApp(tester, 0);

      await sendLifecycle(tester, AppLifecycleState.paused);
      expect(find.byType(PinLockScreen), findsOneWidget);
      expect(notes(), findsNothing);

      await sendLifecycle(tester, AppLifecycleState.resumed);
      expect(find.byType(PinLockScreen), findsOneWidget);
    });

    testWidgets('the app is covered while inactive', (tester) async {
      await unlockedApp(tester, 60);

      await sendLifecycle(tester, AppLifecycleState.inactive);
      expect(find.byType(PrivacyCover), findsOneWidget);
      expect(notes(), findsNothing);

      await sendLifecycle(tester, AppLifecycleState.resumed);
      expect(find.byType(PrivacyCover), findsNothing);
      expect(notes(), findsOneWidget);
    });

    testWidgets('Back does not pop hidden routes while locked',
        (tester) async {
      await unlockedApp(tester, 0);
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      expect(find.text('Editor page'), findsOneWidget);

      await leaveFor(tester, const Duration(seconds: 5));
      expect(container(tester).read(appLockProvider).locked, isTrue);

      await pressSystemBack(tester);
      await enterPin(tester, '2468');
      expect(find.text('Editor page'), findsOneWidget,
          reason: 'Back while locked must not pop the editor');

      // Unlocked, Back works as usual.
      await pressSystemBack(tester);
      expect(find.text('Editor page'), findsNothing);
      expect(notes(), findsOneWidget);
    });
  });

  group('wrong-PIN rate limit', () {
    testWidgets('warns before the cooldown, then disables the keypad',
        (tester) async {
      await storePin(prefs, '2468');
      await pumpApp(tester);

      for (var i = 0; i < 3; i++) {
        await enterPin(tester, '0000');
      }
      expect(pinMessage(tester),
          'Wrong PIN. 2 attempts left before a 30-second wait.');
      await enterPin(tester, '0000');
      expect(pinMessage(tester),
          'Wrong PIN. 1 attempt left before a 30-second wait.');

      await enterPin(tester, '0000');
      expect(pinMessage(tester), 'Too many wrong PINs. Try again in 0:30.');

      // The keypad ignores input during the cooldown, even the right PIN.
      await enterPin(tester, '2468');
      expect(find.byType(PinLockScreen), findsOneWidget);
      expect(notesCreated, 0);

      // The countdown follows the clock.
      now = now.add(const Duration(seconds: 12));
      await tester.pump(const Duration(seconds: 1));
      expect(pinMessage(tester), 'Too many wrong PINs. Try again in 0:18.');

      now = now.add(const Duration(seconds: 18));
      await tester.pump(const Duration(seconds: 1));
      expect(pinMessage(tester), 'You can try again now.');

      await enterPin(tester, '2468');
      expect(notes(), findsOneWidget);
      expect(prefs.getInt(PinAttemptLimiter.failuresKey), isNull);
    });

    testWidgets('the cooldown survives an app restart', (tester) async {
      await storePin(prefs, '2468');
      await pumpApp(tester);
      for (var i = 0; i < 5; i++) {
        await enterPin(tester, '0000');
      }
      now = now.add(const Duration(seconds: 10));

      // Restart: a new widget tree and provider scope over the same prefs.
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester);

      expect(pinMessage(tester), 'Too many wrong PINs. Try again in 0:20.');
      await enterPin(tester, '2468');
      expect(find.byType(PinLockScreen), findsOneWidget);
    });
  });

  testWidgets('removing the PIN in Settings opens a locked app',
      (tester) async {
    await storePin(prefs, '2468');
    await pumpApp(tester);
    expect(find.byType(PinLockScreen), findsOneWidget);

    container(tester).read(settingsProvider.notifier).clearPin();
    await tester.pumpAndSettle();

    expect(find.byType(PinLockScreen), findsNothing);
    expect(notes(), findsOneWidget);
  });

  testWidgets('"Forgot your PIN?" explains that it cannot be recovered',
      (tester) async {
    await storePin(prefs, '2468');
    await pumpApp(tester);

    await tester.tap(find.text('Forgot your PIN?'));
    await tester.pumpAndSettle();

    expect(find.text(ForgotPinHelp.explanation), findsOneWidget);
  });
}
