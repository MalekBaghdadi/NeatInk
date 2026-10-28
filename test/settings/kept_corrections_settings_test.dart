import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/app/theme.dart';
import 'package:neatink/features/editor/integrations/convert/kept_corrections.dart';
import 'package:neatink/features/editor/integrations/convert/sample_share.dart';
import 'package:neatink/features/settings/settings_controller.dart';
import 'package:neatink/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/in_memory_repository.dart';

class _Share implements SampleShareService {
  final List<({String fileName, String json})> shared = [];

  @override
  Future<bool> share({required String fileName, required String json}) async {
    shared.add((fileName: fileName, json: json));
    return true;
  }
}

void main() {
  final now = DateTime(2026, 11, 2, 9, 5);

  Future<ProviderContainer> pump(WidgetTester tester, InMemoryKeptCorrections kept, _Share share) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1200, 4600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notebookRepositoryProvider.overrideWithValue(InMemoryNotebookRepository()),
        keptCorrectionsProvider.overrideWithValue(kept),
        sampleShareServiceProvider.overrideWithValue(share),
        clockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  testWidgets('shows how many lines are kept and shares them as one file', (tester) async {
    final kept = InMemoryKeptCorrections()..lines.addAll([{'finalText': 'one'}, {'finalText': 'two'}]);
    final share = _Share();
    await pump(tester, kept, share);
    expect(find.textContaining('2 lines kept'), findsOneWidget);

    await tester.tap(key('settings-share-corrections'));
    await tester.pumpAndSettle();
    final file = share.shared.single;
    expect(file.fileName, 'mariams-notes-corrections-20261102-0905.json');
    final json = jsonDecode(file.json) as Map<String, dynamic>;
    expect(json['lineCount'], 2);
    expect(json['kind'], 'kept-corrections');
  });

  testWidgets('delete asks first, then empties the store', (tester) async {
    final kept = InMemoryKeptCorrections()..lines.add({'finalText': 'one'});
    await pump(tester, kept, _Share());
    await tester.tap(key('settings-delete-corrections'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(kept.lines, hasLength(1));

    await tester.tap(key('settings-delete-corrections'));
    await tester.pumpAndSettle();
    await tester.tap(key('kept-corrections-delete-confirm'));
    await tester.pumpAndSettle();
    expect(kept.lines, isEmpty);
    expect(find.text('Nothing kept yet.'), findsOneWidget);
  });

  testWidgets('nothing kept: sharing and deleting are off; the switch turns keeping off', (tester) async {
    final share = _Share();
    final container = await pump(tester, InMemoryKeptCorrections(), share);
    expect(tester.widget<ListTile>(key('settings-share-corrections')).enabled, isFalse);
    expect(tester.widget<IconButton>(key('settings-delete-corrections')).onPressed, isNull);

    expect(container.read(settingsProvider).keepCorrections, isTrue);
    await tester.tap(key('settings-keep-corrections'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).keepCorrections, isFalse);
  });
}
