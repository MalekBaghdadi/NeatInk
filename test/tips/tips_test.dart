import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/app.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/features/settings/app_settings.dart';
import 'package:neatink/features/settings/settings_controller.dart';
import 'package:neatink/features/settings/settings_screen.dart';
import 'package:neatink/features/tips/tips_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lock/lock_test_support.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  /// The real app shell (lock gate included) with a stand-in library.
  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    resumeAfterTest(tester);
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 28, 9)),
      ],
      child: const NeatInkApp(home: Scaffold(body: Text('Library'))),
    ));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(NeatInkApp)));
  }

  testWidgets('the first start shows the tips once, then never again', (tester) async {
    final c = await pumpApp(tester);
    expect(find.byType(TipsScreen), findsOneWidget);
    expect(c.read(settingsProvider).tipsSeen, isTrue);
    final saved = jsonDecode(prefs.getString(AppSettings.prefsKey)!) as Map<String, dynamic>;
    expect(saved['tipsSeen'], isTrue);

    await tester.tap(find.byKey(const ValueKey('tips-done')));
    await tester.pumpAndSettle();
    expect(find.byType(TipsScreen), findsNothing);
    expect(find.text('Library'), findsOneWidget);

    // Next start.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester);
    expect(find.byType(TipsScreen), findsNothing);
    expect(find.text('Library'), findsOneWidget);
  });

  testWidgets('with an app lock the tips wait until the PIN is entered', (tester) async {
    await storePin(prefs, '2468');
    await pumpApp(tester);
    expect(find.byType(TipsScreen, skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('pin-key-5')), findsOneWidget);

    await enterPin(tester, '2468');
    expect(find.byType(TipsScreen), findsOneWidget);
  });

  testWidgets('every tip is listed, and Settings opens them', (tester) async {
    tester.view.physicalSize = const Size(1200, 4600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-tips')));
    await tester.pumpAndSettle();
    expect(find.byType(TipsScreen), findsOneWidget);
    for (final tip in appTips) {
      await tester.scrollUntilVisible(find.text(tip.title), 200,
          scrollable: find.descendant(
              of: find.byKey(const ValueKey('tips-list')), matching: find.byType(Scrollable)));
      expect(find.text(tip.body), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.byKey(const ValueKey('tips-done')), 200,
        scrollable: find.descendant(
            of: find.byKey(const ValueKey('tips-list')), matching: find.byType(Scrollable)));
    await tester.tap(find.byKey(const ValueKey('tips-done')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(TipsScreen), findsNothing);
  });
}
