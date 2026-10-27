import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/font_kind.dart';
import 'package:neatink/features/editor/integrations/convert/convert_layout.dart';
import 'package:neatink/features/settings/convert_style_prefs.dart';
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

  ProviderContainer restart(SharedPreferences prefs) {
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('the defaults are Roboto, auto size, keep the ink colour', () async {
    final c = await containerWith({});
    final p = c.read(convertStylePrefsProvider);
    expect(p.fontId, 'sans');
    expect(p.font, FontKind.sans);
    expect(p.bold, isFalse);
    expect(p.italic, isFalse);
    expect(p.fixedSize, isNull);
    expect(p.autoSize, isTrue);
    expect(p.colorOverride, isNull);
    expect(p, const ConvertStylePrefs());
  });

  test('saving persists every field and survives a restart', () async {
    final c = await containerWith({});
    const chosen = ConvertStylePrefs(
      fontId: 'lora',
      bold: true,
      italic: true,
      fixedSize: 18,
      colorOverride: 0xFF1A237E,
    );
    c.read(convertStylePrefsProvider.notifier).save(chosen);
    expect(c.read(convertStylePrefsProvider), chosen);

    final prefs = c.read(sharedPreferencesProvider);
    final stored = jsonDecode(prefs.getString(ConvertStylePrefs.prefsKey)!)
        as Map<String, dynamic>;
    expect(stored['font'], 'lora');
    expect(stored['sizeMode'], 'fixed');
    expect(stored['size'], 18);
    expect(stored['colourMode'], 'fixed');
    expect(stored['colour'], '#FF1A237E');

    expect(restart(prefs).read(convertStylePrefsProvider), chosen);
  });

  test('auto size and the ink colour are remembered as such', () async {
    final c = await containerWith({});
    final n = c.read(convertStylePrefsProvider.notifier);
    n.save(const ConvertStylePrefs(fixedSize: 14, colorOverride: 0xFF000000));
    n.save(const ConvertStylePrefs(fontId: 'lato'));
    final back = restart(c.read(sharedPreferencesProvider))
        .read(convertStylePrefsProvider);
    expect(back.fontId, 'lato');
    expect(back.fixedSize, isNull);
    expect(back.colorOverride, isNull);
  });

  test('copyWith can clear the size and the colour', () {
    const p = ConvertStylePrefs(fixedSize: 14, colorOverride: 0xFF000000);
    expect(p.copyWith(bold: true).fixedSize, 14);
    expect(p.copyWith(clearFixedSize: true).fixedSize, isNull);
    expect(p.copyWith(clearColorOverride: true).colorOverride, isNull);
    expect(p.copyWith(fontId: 'lato').colorOverride, 0xFF000000);
  });

  group('bad stored data gives the defaults', () {
    for (final (name, stored) in [
      ('invalid JSON', '{"font": "lora",'),
      ('a JSON array', '[1, 2]'),
      ('an empty string', ''),
      ('null', 'null'),
    ]) {
      test(name, () async {
        final c = await containerWith({ConvertStylePrefs.prefsKey: stored});
        expect(c.read(convertStylePrefsProvider), const ConvertStylePrefs());
      });
    }

    test('an unknown font id falls back to Roboto, the rest is kept', () async {
      final c = await containerWith({
        ConvertStylePrefs.prefsKey: jsonEncode({
          'font': 'comic_sans',
          'bold': true,
          'sizeMode': 'fixed',
          'size': 20,
        }),
      });
      final p = c.read(convertStylePrefsProvider);
      expect(p.font, FontKind.sans);
      expect(p.bold, isTrue);
      expect(p.fixedSize, 20);
    });

    test('wrong types and nonsense sizes are ignored one by one', () async {
      final c = await containerWith({
        ConvertStylePrefs.prefsKey: jsonEncode({
          'font': 7,
          'bold': 'yes',
          'sizeMode': 'fixed',
          'size': -3,
          'colourMode': 'fixed',
          'colour': 12,
        }),
      });
      expect(c.read(convertStylePrefsProvider), const ConvertStylePrefs());
    });
  });

  test('it converts to and from the look the layout uses', () {
    const prefs = ConvertStylePrefs(
        fontId: 'lora', bold: true, fixedSize: 18, colorOverride: 0xFF4E342E);
    final style = ConvertStyle.fromPrefs(prefs);
    expect(style.font, FontKind.lora);
    expect(style.bold, isTrue);
    expect(style.italic, isFalse);
    expect(style.fixedSize, 18);
    expect(style.colorOverride, 0xFF4E342E);
    expect(style.toPrefs(), prefs);

    final defaults = ConvertStyle.fromPrefs(const ConvertStylePrefs());
    expect(defaults.font, FontKind.sans);
    expect(defaults.fixedSize, isNull);
    expect(defaults.colorOverride, isNull);
  });
}
