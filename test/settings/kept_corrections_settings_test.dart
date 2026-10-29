import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/diagnostics.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/app/theme.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/document/paper.dart';
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

  Future<ProviderContainer> pump(WidgetTester tester, InMemoryKeptCorrections kept, _Share share,
      {InMemoryNotebookRepository? repository, DiagnosticsLog? log}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1200, 4600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notebookRepositoryProvider.overrideWithValue(repository ?? InMemoryNotebookRepository()),
        keptCorrectionsProvider.overrideWithValue(kept),
        sampleShareServiceProvider.overrideWithValue(share),
        clockProvider.overrideWithValue(() => now),
        diagnosticsLogProvider.overrideWithValue(log ?? InMemoryDiagnosticsLog()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  testWidgets('one tap sends every kept line, with what its text is now, as one file', (tester) async {
    // v1.11.0: "make it one click" for Mariam.
    final repository = InMemoryNotebookRepository();
    final meta = await tester.runAsync(() => repository.createNotebook(title: 'Bio', paper: const Paper(), pageCount: 1));
    final pageId = meta!.pages.first.id;
    await tester.runAsync(() => repository.savePage(meta.id, pageId, PageContent(texts: const [
          TextItem(id: 'box', x: 10, y: 10, width: 200, height: 20, text: 'Neurons fire fast', fontSize: 16),
        ])));
    final kept = InMemoryKeptCorrections()
      ..lines.addAll([
        {'finalText': 'one', 'source': 'sheet'},
        {'finalText': 'Nuerons fire', 'source': 'auto', 'notebookId': meta.id, 'pageId': pageId, 'boxId': 'box'},
        {'finalText': 'undone', 'source': 'auto', 'notebookId': meta.id, 'pageId': pageId, 'boxId': 'gone'},
      ]);
    final log = InMemoryDiagnosticsLog()..record('Convert failed: test');
    final share = _Share();
    await pump(tester, kept, share, repository: repository, log: log);
    expect(find.textContaining('3 lines of your writing'), findsOneWidget);

    await tester.tap(key('settings-share-corrections'));
    await tester.pumpAndSettle();
    final file = share.shared.single;
    expect(file.fileName, 'mariams-notes-writing-20261102-0905.json');
    final json = jsonDecode(file.json) as Map<String, dynamic>;
    expect(json['kind'], 'writing-samples');
    expect(json['lineCount'], 3);
    final lines = (json['lines'] as List).cast<Map<String, dynamic>>();
    expect(lines[0].containsKey('boxTextNow'), isFalse, reason: 'a sheet line has no box to look at');
    expect([lines[1]['boxTextNow'], lines[1]['boxGone']], ['Neurons fire fast', false]);
    expect([lines[2]['boxTextNow'], lines[2]['boxGone']], [null, true], reason: 'the conversion was undone');
    expect((json['settings'] as Map)['autoConvert'], isA<bool>());
    expect(((json['problems'] as List).single as Map)['m'], 'Convert failed: test');
    expect(find.textContaining('Thank you! 3 lines'), findsOneWidget);
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
