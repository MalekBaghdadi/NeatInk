import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/app_info.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/app/theme.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/debug/pointer_debug_screen.dart';
import 'package:neatink/features/settings/app_settings.dart';
import 'package:neatink/features/settings/settings_controller.dart';
import 'package:neatink/features/settings/settings_screen.dart';
import 'package:neatink/features/settings/widgets/settings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lock/lock_test_support.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  /// Pumps the settings screen on a tall tablet-sized surface (so every
  /// section is built without scrolling) and returns its provider scope.
  Future<ProviderContainer> pumpSettings(
    WidgetTester tester, {
    Size size = const Size(1200, 4200),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)));
  }

  AppSettings settingsOf(ProviderContainer c) => c.read(settingsProvider);

  /// Taps the segment labelled [label] inside the choice tile [tileKey].
  Future<void> choose(WidgetTester tester, String tileKey, String label) async {
    await tester.tap(find.descendant(
      of: find.byKey(ValueKey(tileKey)),
      matching: find.text(label),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> toggle(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('shows every section, the offline promise and the version',
      (tester) async {
    await pumpSettings(tester);

    for (final title in [
      'Appearance',
      'Writing',
      'New notebooks',
      'Export',
      'Security',
      'Developer',
      'About',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text(AppInfo.offlineStatement), findsOneWidget);
    expect(find.text('Version ${AppInfo.displayVersion}'), findsOneWidget);
    expect(find.text('Open-source licenses'), findsOneWidget);
  });

  testWidgets('content width is capped on a wide tablet', (tester) async {
    await pumpSettings(tester, size: const Size(2000, 4200));
    final cardWidth = tester.getSize(find.byType(Card).first).width;
    expect(cardWidth, lessThanOrEqualTo(settingsMaxWidth));
    expect(cardWidth, greaterThan(settingsMaxWidth - 40));
  });

  testWidgets('fits a portrait tablet without overflow', (tester) async {
    await pumpSettings(tester, size: const Size(800, 1280));
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Open-source licenses'), 400);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme choice updates the settings', (tester) async {
    final c = await pumpSettings(tester);

    await choose(tester, 'settings-theme', 'Dark');
    expect(settingsOf(c).themeMode, AppThemeMode.dark);

    await choose(tester, 'settings-theme', 'Light');
    expect(settingsOf(c).themeMode, AppThemeMode.light);
  });

  testWidgets('writing options update the settings', (tester) async {
    final c = await pumpSettings(tester);

    await toggle(tester, 'settings-shape-snap');
    expect(settingsOf(c).shapeSnapEnabled, isFalse);

    await toggle(tester, 'settings-draw-with-finger');
    expect(settingsOf(c).drawWithFinger, isTrue);
    expect(find.textContaining('palm rejection'), findsOneWidget);

    await toggle(tester, 'settings-pen-button-erases');
    expect(settingsOf(c).stylusButtonErases, isFalse);
  });

  testWidgets('auto-convert has a switch with a one-line explanation, off by default',
      (tester) async {
    final c = await pumpSettings(tester);
    expect(find.byKey(const ValueKey('settings-auto-convert')), findsOneWidget);
    expect(find.text('Auto-convert handwriting'), findsOneWidget);
    expect(find.textContaining('turns into text by itself'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(
            find.byKey(const ValueKey('settings-auto-convert'))).value,
        isFalse);
    expect(settingsOf(c).autoConvert, isFalse);

    await toggle(tester, 'settings-auto-convert');
    expect(settingsOf(c).autoConvert, isTrue);
    expect(tester.widget<SwitchListTile>(
            find.byKey(const ValueKey('settings-auto-convert'))).value,
        isTrue);
    // It is saved: a fresh start sees it.
    final stored = prefs.getString(AppSettings.prefsKey)!;
    expect(stored, contains('"autoConvert":true'));

    await toggle(tester, 'settings-auto-convert');
    expect(settingsOf(c).autoConvert, isFalse);
  });

  testWidgets('auto-convert switch shows the saved value', (tester) async {
    SharedPreferences.setMockInitialValues({
      AppSettings.prefsKey: '{"autoConvert": true}',
    });
    prefs = await SharedPreferences.getInstance();
    await pumpSettings(tester);
    expect(tester.widget<SwitchListTile>(
            find.byKey(const ValueKey('settings-auto-convert'))).value,
        isTrue);
  });

  testWidgets('"Fix spelling automatically" has a switch, off by default',
      (tester) async {
    final c = await pumpSettings(tester);
    const key = ValueKey('settings-auto-fix-spelling');
    expect(find.byKey(key), findsOneWidget);
    expect(find.text('Fix spelling automatically'), findsOneWidget);
    expect(find.textContaining('corrections are suggested in the review sheet'),
        findsOneWidget);
    expect(find.textContaining('you can undo each one'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(key)).value, isFalse);
    expect(settingsOf(c).autoFixSpelling, isFalse);

    await toggle(tester, 'settings-auto-fix-spelling');
    expect(settingsOf(c).autoFixSpelling, isTrue);
    expect(settingsOf(c).autoConvert, isFalse, reason: 'a separate setting');
    expect(tester.widget<SwitchListTile>(find.byKey(key)).value, isTrue);
    expect(prefs.getString(AppSettings.prefsKey)!,
        contains('"autoFixSpelling":true'));

    await toggle(tester, 'settings-auto-fix-spelling');
    expect(settingsOf(c).autoFixSpelling, isFalse);
  });

  testWidgets('the fix-spelling switch shows the saved value', (tester) async {
    SharedPreferences.setMockInitialValues({
      AppSettings.prefsKey: '{"autoFixSpelling": true}',
    });
    prefs = await SharedPreferences.getInstance();
    await pumpSettings(tester);
    expect(
        tester
            .widget<SwitchListTile>(
                find.byKey(const ValueKey('settings-auto-fix-spelling')))
            .value,
        isTrue);
  });

  testWidgets('tidy settings are gone', (tester) async {
    await pumpSettings(tester);
    for (final k in [
      'settings-tidy',
      'settings-tidy-strength',
      'settings-slant',
      'settings-debug-overlay',
    ]) {
      expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
    }
  });

  testWidgets('export switch updates the settings',
      (tester) async {
    final c = await pumpSettings(tester);

    await toggle(tester, 'settings-export-lines');
    expect(settingsOf(c).exportPaperLines, isFalse);
  });

  testWidgets('new-notebook paper: type, colour and spacing', (tester) async {
    final c = await pumpSettings(tester);

    for (final type in PaperType.values) {
      expect(find.byKey(ValueKey('paper-type-${type.name}')), findsOneWidget);
    }

    await toggle(tester, 'paper-type-grid');
    expect(settingsOf(c).defaultPaper.type, PaperType.grid);

    await toggle(tester, 'paper-color-Cream');
    expect(settingsOf(c).defaultPaper.color, Paper.cream);
    expect(settingsOf(c).defaultPaper.type, PaperType.grid);

    // Drag the spacing slider to its right end.
    final slider = find.byKey(const ValueKey('paper-spacing'));
    await tester.drag(slider, const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(settingsOf(c).defaultPaper.spacingPt, 40);

    await toggle(tester, 'paper-type-blank');
    expect(find.text('No lines'), findsOneWidget);
  });

  testWidgets('changes are persisted', (tester) async {
    await pumpSettings(tester);

    await choose(tester, 'settings-theme', 'Dark');

    final stored = prefs.getString(AppSettings.prefsKey);
    expect(stored, contains('"themeMode":"dark"'));
  });

  group('security', () {
    testWidgets('without a PIN offers to set one, with the warning',
        (tester) async {
      await pumpSettings(tester);

      expect(find.text('Set PIN'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-change-pin')), findsNothing);
      expect(find.byKey(const ValueKey('settings-lock-after')), findsNothing);
      expect(find.textContaining("can't be recovered"), findsOneWidget);
    });

    testWidgets('setting a PIN from Settings turns the lock on',
        (tester) async {
      final c = await pumpSettings(tester);

      await tester.tap(find.text('Set PIN'));
      await tester.pumpAndSettle();
      await enterPin(tester, '2580');
      await enterPin(tester, '2580');

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('App lock is on.'), findsOneWidget); // snack bar
      expect(settingsOf(c).appLockEnabled, isTrue);
      expect(c.read(settingsProvider.notifier).verifyPin('2580'), isTrue);
    });

    testWidgets('with a PIN offers change, remove and the lock delay',
        (tester) async {
      await storePin(prefs, '1234');
      final c = await pumpSettings(tester);

      expect(find.text('App lock is on'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-change-pin')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-remove-pin')), findsOneWidget);

      for (final (seconds, label) in [
        (60, '1 min'),
        (300, '5 min'),
        (900, '15 min'),
        (0, 'Immediately'),
      ]) {
        await choose(tester, 'settings-lock-after', label);
        expect(settingsOf(c).lockAfterSeconds, seconds, reason: label);
      }
    });

    testWidgets('shows a lock delay that is not one of the choices',
        (tester) async {
      await storePin(prefs, '1234', lockAfterSeconds: 120);
      await pumpSettings(tester);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('settings-lock-after')),
          matching: find.text('2 min'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('removing the PIN needs the current one', (tester) async {
      await storePin(prefs, '1234');
      final c = await pumpSettings(tester);

      await tester.tap(find.byKey(const ValueKey('settings-remove-pin')));
      await tester.pumpAndSettle();
      await enterPin(tester, '1234');

      expect(settingsOf(c).appLockEnabled, isFalse);
      expect(find.text('App lock is off.'), findsOneWidget);
      expect(find.text('Set PIN'), findsOneWidget);
    });
  });

  testWidgets('opens the pointer test screen', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byKey(const ValueKey('settings-pointer-test')));
    await tester.pumpAndSettle();

    expect(find.byType(PointerDebugScreen), findsOneWidget);
  });

  testWidgets('opens the open-source licenses', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byKey(const ValueKey('settings-licenses')));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
  });
}
