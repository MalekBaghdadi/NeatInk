import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/lock/pin_hasher.dart';
import 'package:neatink/features/settings/app_settings.dart';
import 'package:neatink/features/settings/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> containerWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final instance = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(instance),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  /// A fresh container over the same prefs, as after an app restart.
  ProviderContainer restart(SharedPreferences prefs) {
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('starts with the defaults when nothing is stored', () async {
    final c = await containerWith({});
    final s = c.read(settingsProvider);
    expect(s.themeMode, AppThemeMode.system);
    expect(s.drawWithFinger, isFalse);
    expect(s.shapeSnapEnabled, isTrue);
    expect(s.appLockEnabled, isFalse);
    expect(s.lockAfterSeconds, 0);
  });

  test('update changes the state and persists every field', () async {
    final c = await containerWith({});
    const paper = Paper(type: PaperType.grid, spacingPt: 20, color: Paper.cream);
    c.read(settingsProvider.notifier).update((s) => s.copyWith(
          themeMode: AppThemeMode.dark,
          drawWithFinger: true,
          stylusButtonErases: false,
          shapeSnapEnabled: false,
          exportPaperLines: false,
          defaultPaper: paper,
          librarySort: LibrarySort.title,
          lockAfterSeconds: 300,
          autoConvert: true,
        ));

    final s = c.read(settingsProvider);
    expect(s.themeMode, AppThemeMode.dark);
    expect(s.defaultPaper, paper);

    final prefs = c.read(sharedPreferencesProvider);
    final stored = prefs.getString(AppSettings.prefsKey);
    expect(stored, isNotNull);
    expect(jsonDecode(stored!), isA<Map<String, dynamic>>());

    final reloaded = restart(prefs).read(settingsProvider);
    expect(reloaded.themeMode, AppThemeMode.dark);
    expect(reloaded.drawWithFinger, isTrue);
    expect(reloaded.stylusButtonErases, isFalse);
    expect(reloaded.shapeSnapEnabled, isFalse);
    expect(reloaded.exportPaperLines, isFalse);
    expect(reloaded.defaultPaper, paper);
    expect(reloaded.librarySort, LibrarySort.title);
    expect(reloaded.lockAfterSeconds, 300);
    expect(reloaded.autoConvert, isTrue);
  });

  group('autoConvert', () {
    test('is off by default', () async {
      final c = await containerWith({});
      expect(c.read(settingsProvider).autoConvert, isFalse);
      expect(const AppSettings().autoConvert, isFalse);
    });

    test('copyWith changes only it', () {
      const base = AppSettings(shapeSnapEnabled: false, lockAfterSeconds: 60);
      final on = base.copyWith(autoConvert: true);
      expect(on.autoConvert, isTrue);
      expect(on.shapeSnapEnabled, isFalse);
      expect(on.lockAfterSeconds, 60);
      expect(on.copyWith(shapeSnapEnabled: true).autoConvert, isTrue,
          reason: 'other changes keep it');
      expect(on.copyWith(autoConvert: false).autoConvert, isFalse);
    });

    test('JSON round trip', () {
      expect(const AppSettings(autoConvert: true).toJson()['autoConvert'], isTrue);
      expect(const AppSettings().toJson()['autoConvert'], isFalse);
      expect(
          AppSettings.fromJson(const AppSettings(autoConvert: true).toJson())
              .autoConvert,
          isTrue);
    });

    test('settings saved before it existed load with it off', () async {
      final c = await containerWith({
        AppSettings.prefsKey: jsonEncode({
          'themeMode': 'dark',
          'drawWithFinger': true,
          'shapeSnapEnabled': false,
        }),
      });
      final s = c.read(settingsProvider);
      expect(s.autoConvert, isFalse);
      expect(s.themeMode, AppThemeMode.dark);
      expect(s.shapeSnapEnabled, isFalse);
    });

    test('a value of the wrong type falls back to off', () async {
      final c = await containerWith({
        AppSettings.prefsKey: jsonEncode({'autoConvert': 'yes'}),
      });
      expect(c.read(settingsProvider).autoConvert, isFalse);
    });

    test('survives a restart', () async {
      final c = await containerWith({});
      c
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(autoConvert: true));
      final again = restart(c.read(sharedPreferencesProvider));
      expect(again.read(settingsProvider).autoConvert, isTrue);
    });
  });

  group('autoConvertDelayMs', () {
    test('is 2 s by default, also for settings saved before it existed', () async {
      expect(const AppSettings().autoConvertDelayMs, 2000);
      final c = await containerWith({
        AppSettings.prefsKey: jsonEncode({'autoConvert': true}),
      });
      expect(c.read(settingsProvider).autoConvertDelayMs, 2000);
    });

    test('JSON round trip, and copyWith changes only it', () {
      const s = AppSettings(autoConvert: true);
      final changed = s.copyWith(autoConvertDelayMs: 4500);
      expect(changed.autoConvertDelayMs, 4500);
      expect(changed.autoConvert, isTrue);
      expect(AppSettings.fromJson(changed.toJson()).autoConvertDelayMs, 4500);
    });

    test('is kept between 1 and 10 s, and a wrong type gives the default', () async {
      expect(const AppSettings().copyWith(autoConvertDelayMs: 50).autoConvertDelayMs, 1000);
      expect(const AppSettings().copyWith(autoConvertDelayMs: 60000).autoConvertDelayMs, 10000);
      expect(AppSettings.fromJson({'autoConvertDelayMs': 99999}).autoConvertDelayMs, 10000);
      final c = await containerWith({
        AppSettings.prefsKey: jsonEncode({'autoConvertDelayMs': 'slow', 'autoConvert': true}),
      });
      expect(c.read(settingsProvider).autoConvertDelayMs, 2000);
      expect(c.read(settingsProvider).autoConvert, isTrue, reason: 'the rest is kept');
    });

    test('survives a restart', () async {
      final c = await containerWith({});
      c.read(settingsProvider.notifier).update((s) => s.copyWith(autoConvertDelayMs: 3000));
      final again = restart(c.read(sharedPreferencesProvider));
      expect(again.read(settingsProvider).autoConvertDelayMs, 3000);
    });
  });

  group('autoFixSpelling', () {
    test('is off by default', () async {
      final c = await containerWith({});
      expect(c.read(settingsProvider).autoFixSpelling, isFalse);
      expect(const AppSettings().autoFixSpelling, isFalse);
    });

    test('copyWith changes only it', () {
      const base = AppSettings(autoConvert: true, lockAfterSeconds: 60);
      final on = base.copyWith(autoFixSpelling: true);
      expect(on.autoFixSpelling, isTrue);
      expect(on.autoConvert, isTrue);
      expect(on.lockAfterSeconds, 60);
      expect(on.copyWith(autoConvert: false).autoFixSpelling, isTrue,
          reason: 'other changes keep it');
      expect(on.copyWith(autoFixSpelling: false).autoFixSpelling, isFalse);
    });

    test('JSON round trip under the key autoFixSpelling', () {
      expect(const AppSettings().toJson()['autoFixSpelling'], isFalse);
      expect(const AppSettings(autoFixSpelling: true).toJson()['autoFixSpelling'],
          isTrue);
      expect(
          AppSettings.fromJson(
                  const AppSettings(autoFixSpelling: true).toJson())
              .autoFixSpelling,
          isTrue);
      expect(
          AppSettings.fromJson(const AppSettings().toJson()).autoFixSpelling,
          isFalse);
    });

    test('settings saved before it existed load with it off', () async {
      final c = await containerWith({
        AppSettings.prefsKey: jsonEncode({
          'themeMode': 'dark',
          'autoConvert': true,
        }),
      });
      final s = c.read(settingsProvider);
      expect(s.autoFixSpelling, isFalse);
      expect(s.autoConvert, isTrue);
      expect(s.themeMode, AppThemeMode.dark);
    });

    test('a value of the wrong type falls back to off', () async {
      final c = await containerWith({
        AppSettings.prefsKey: jsonEncode({'autoFixSpelling': 'yes'}),
      });
      expect(c.read(settingsProvider).autoFixSpelling, isFalse);
    });

    test('is independent of autoConvert', () async {
      final c = await containerWith({});
      c
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(autoFixSpelling: true));
      expect(c.read(settingsProvider).autoConvert, isFalse);
      c
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(autoConvert: true));
      expect(c.read(settingsProvider).autoFixSpelling, isTrue);
    });

    test('survives a restart', () async {
      final c = await containerWith({});
      c
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(autoFixSpelling: true));
      final again = restart(c.read(sharedPreferencesProvider));
      expect(again.read(settingsProvider).autoFixSpelling, isTrue);
    });
  });

  test('listeners see each update', () async {
    final c = await containerWith({});
    final seen = <bool>[];
    c.listen(settingsProvider.select((s) => s.shapeSnapEnabled),
        (_, next) => seen.add(next));
    final notifier = c.read(settingsProvider.notifier);
    notifier.update((s) => s.copyWith(shapeSnapEnabled: false));
    notifier.update((s) => s.copyWith(shapeSnapEnabled: true));
    expect(seen, [false, true]);
  });

  group('corrupt or unexpected prefs fall back to defaults', () {
    for (final (name, stored) in [
      ('invalid JSON', '{"themeMode": "dark",'),
      ('a JSON array', '[1, 2, 3]'),
      ('a JSON string', '"dark"'),
      ('JSON null', 'null'),
      ('an empty string', ''),
      ('a wrong field type', '{"shapeSnapEnabled": "yes"}'),
      ('a wrong nested type', '{"defaultPaper": "lined"}'),
      ('a bad paper colour', '{"defaultPaper": {"color": "#zz"}}'),
    ]) {
      test(name, () async {
        final c = await containerWith({AppSettings.prefsKey: stored});
        final s = c.read(settingsProvider);
        expect(s.themeMode, AppThemeMode.system);
        expect(s.shapeSnapEnabled, isTrue);
        expect(s.appLockEnabled, isFalse);
      });
    }

    test('unknown enum names and missing fields fall back one by one',
        () async {
      final c = await containerWith({
        AppSettings.prefsKey: jsonEncode({
          'themeMode': 'sepia',
          'librarySort': 'title',
          'futureSetting': 42,
        }),
      });
      final s = c.read(settingsProvider);
      expect(s.themeMode, AppThemeMode.system);
      expect(s.librarySort, LibrarySort.title);
      expect(s.drawWithFinger, isFalse);
    });

    test('prefs saved by older versions (removed tidy keys) still load',
        () async {
      final c = await containerWith({
        AppSettings.prefsKey: jsonEncode({
          'themeMode': 'dark',
          'tidyEnabled': false,
          'tidyStrength': 'strong',
          'slantMode': 'upright',
          'debugOverlay': true,
          'drawWithFinger': true,
        }),
      });
      final s = c.read(settingsProvider);
      expect(s.themeMode, AppThemeMode.dark);
      expect(s.drawWithFinger, isTrue);
      final json = s.toJson();
      for (final k in [
        'tidyEnabled',
        'tidyStrength',
        'slantMode',
        'debugOverlay',
      ]) {
        expect(json.containsKey(k), isFalse, reason: k);
      }
    });

    test('a corrupt entry is overwritten by the next change', () async {
      final c = await containerWith({AppSettings.prefsKey: 'garbage'});
      c
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(themeMode: AppThemeMode.light));
      final prefs = c.read(sharedPreferencesProvider);
      expect(restart(prefs).read(settingsProvider).themeMode,
          AppThemeMode.light);
    });
  });

  group('PIN', () {
    test('setPin stores a salted hash, never the PIN', () async {
      final c = await containerWith({});
      c.read(settingsProvider.notifier).setPin('4821');
      final s = c.read(settingsProvider);
      expect(s.appLockEnabled, isTrue);
      expect(s.pinSalt, hasLength(PinHasher.saltBytes * 2));
      expect(s.pinHash, PinHasher.hash('4821', s.pinSalt!));
      final stored =
          c.read(sharedPreferencesProvider).getString(AppSettings.prefsKey)!;
      expect(stored, isNot(contains('4821')));
    });

    test('verifyPin checks against the stored hash', () async {
      final c = await containerWith({});
      final notifier = c.read(settingsProvider.notifier);
      expect(notifier.verifyPin('4821'), isFalse, reason: 'no PIN set');
      notifier.setPin('4821');
      expect(notifier.verifyPin('4821'), isTrue);
      expect(notifier.verifyPin('4822'), isFalse);
      expect(notifier.verifyPin(''), isFalse);
    });

    test('the PIN survives a restart', () async {
      final c = await containerWith({});
      c.read(settingsProvider.notifier).setPin('13572468');
      final prefs = c.read(sharedPreferencesProvider);
      final again = restart(prefs);
      expect(again.read(settingsProvider).appLockEnabled, isTrue);
      expect(again.read(settingsProvider.notifier).verifyPin('13572468'),
          isTrue);
    });

    test('changing the PIN uses a new salt', () async {
      final c = await containerWith({});
      final notifier = c.read(settingsProvider.notifier);
      notifier.setPin('1111');
      final firstSalt = c.read(settingsProvider).pinSalt;
      notifier.setPin('2222');
      expect(c.read(settingsProvider).pinSalt, isNot(firstSalt));
      expect(notifier.verifyPin('1111'), isFalse);
      expect(notifier.verifyPin('2222'), isTrue);
    });

    test('clearPin turns the lock off and keeps other settings', () async {
      final c = await containerWith({});
      final notifier = c.read(settingsProvider.notifier);
      notifier.update((s) => s.copyWith(themeMode: AppThemeMode.dark));
      notifier.setPin('1234');
      notifier.clearPin();
      final s = c.read(settingsProvider);
      expect(s.appLockEnabled, isFalse);
      expect(s.pinHash, isNull);
      expect(s.pinSalt, isNull);
      expect(s.themeMode, AppThemeMode.dark);
      expect(notifier.verifyPin('1234'), isFalse);
    });

    test('setPin rejects invalid PINs', () async {
      final c = await containerWith({});
      final notifier = c.read(settingsProvider.notifier);
      for (final pin in ['123', '123456789', 'abcd', '12 4']) {
        expect(() => notifier.setPin(pin), throwsArgumentError, reason: pin);
      }
      expect(c.read(settingsProvider).appLockEnabled, isFalse);
    });
  });
}
