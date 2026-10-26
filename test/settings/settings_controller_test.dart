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
    expect(s.tidyEnabled, isTrue);
    expect(s.tidyStrength, TidyStrength.medium);
    expect(s.slantMode, SlantMode.keep);
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
          tidyEnabled: false,
          tidyStrength: TidyStrength.strong,
          slantMode: SlantMode.upright,
          drawWithFinger: true,
          stylusButtonErases: false,
          shapeSnapEnabled: false,
          debugOverlay: true,
          exportPaperLines: false,
          defaultPaper: paper,
          librarySort: LibrarySort.title,
          lockAfterSeconds: 300,
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
    expect(reloaded.tidyEnabled, isFalse);
    expect(reloaded.tidyStrength, TidyStrength.strong);
    expect(reloaded.slantMode, SlantMode.upright);
    expect(reloaded.drawWithFinger, isTrue);
    expect(reloaded.stylusButtonErases, isFalse);
    expect(reloaded.shapeSnapEnabled, isFalse);
    expect(reloaded.debugOverlay, isTrue);
    expect(reloaded.exportPaperLines, isFalse);
    expect(reloaded.defaultPaper, paper);
    expect(reloaded.librarySort, LibrarySort.title);
    expect(reloaded.lockAfterSeconds, 300);
  });

  test('listeners see each update', () async {
    final c = await containerWith({});
    final seen = <bool>[];
    c.listen(settingsProvider.select((s) => s.tidyEnabled),
        (_, next) => seen.add(next));
    final notifier = c.read(settingsProvider.notifier);
    notifier.update((s) => s.copyWith(tidyEnabled: false));
    notifier.update((s) => s.copyWith(tidyEnabled: true));
    expect(seen, [false, true]);
  });

  group('corrupt or unexpected prefs fall back to defaults', () {
    for (final (name, stored) in [
      ('invalid JSON', '{"themeMode": "dark",'),
      ('a JSON array', '[1, 2, 3]'),
      ('a JSON string', '"dark"'),
      ('JSON null', 'null'),
      ('an empty string', ''),
      ('a wrong field type', '{"tidyEnabled": "yes"}'),
      ('a wrong nested type', '{"defaultPaper": "lined"}'),
      ('a bad paper colour', '{"defaultPaper": {"color": "#zz"}}'),
    ]) {
      test(name, () async {
        final c = await containerWith({AppSettings.prefsKey: stored});
        final s = c.read(settingsProvider);
        expect(s.themeMode, AppThemeMode.system);
        expect(s.tidyEnabled, isTrue);
        expect(s.appLockEnabled, isFalse);
      });
    }

    test('unknown enum names and missing fields fall back one by one',
        () async {
      final c = await containerWith({
        AppSettings.prefsKey: jsonEncode({
          'themeMode': 'sepia',
          'tidyStrength': 'strong',
          'futureSetting': 42,
        }),
      });
      final s = c.read(settingsProvider);
      expect(s.themeMode, AppThemeMode.system);
      expect(s.tidyStrength, TidyStrength.strong);
      expect(s.slantMode, SlantMode.keep);
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
