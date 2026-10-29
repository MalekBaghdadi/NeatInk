import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/commands.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/editor_controller.dart';
import 'package:neatink/features/editor/editor_integrations.dart';
import 'package:neatink/features/editor/editor_screen.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/integrations/convert/convert_providers.dart';
import 'package:neatink/features/editor/integrations/search_index/handwriting_indexer.dart';
import 'package:neatink/features/editor/integrations/search_index/search_index_integration.dart';
import 'package:neatink/features/settings/app_settings.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/recognition/word_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../fakes/in_memory_repository.dart';
import '../convert/harness.dart' show FakeRecognizer, writeLine;

class OpenedNotebook {
  OpenedNotebook(this.controller, this.repo, this.notebookId, this.pageId);
  final EditorController controller;
  final InMemoryNotebookRepository repo;
  final String notebookId;
  final String pageId;

  String? get stored => repo.handwritingText(notebookId, pageId);
}

FakeRecognizer reader() => FakeRecognizer({
      'aw0': ('hello', 0.9),
      'aw1': ('online', 0.9),
      'bw0': ('second', 0.9),
    });

Future<OpenedNotebook> open(WidgetTester tester, FakeRecognizer recognizer, {bool enabled = true}) async {
  SharedPreferences.setMockInitialValues({
    if (!enabled) AppSettings.prefsKey: jsonEncode({'searchHandwriting': false}),
  });
  final prefs = await SharedPreferences.getInstance();
  final repo = InMemoryNotebookRepository();
  final meta = await repo.createNotebook(title: 'Bio', paper: const Paper(), pageCount: 1);
  await repo.savePage(meta.id, meta.pages.first.id,
      PageContent(strokes: writeLine('a', ['hello', 'online'], y: 104)));
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  EditorController? captured;
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    notebookRepositoryProvider.overrideWithValue(repo),
    htrRecognizerProvider.overrideWithValue(recognizer),
    wordImageRendererProvider.overrideWithValue(const PolylineWordImageRenderer()),
    editorIntegrationsProvider.overrideWithValue([
      (controller, ref) => captured = controller,
      searchIndexIntegration,
    ]),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: EditorScreen(notebookId: meta.id)),
  ));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
  return OpenedNotebook(captured!, repo, meta.id, meta.pages.first.id);
}

Future<void> idle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 9));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  test('the key follows the pen strokes, not their order, highlights or shapes', () {
    Stroke s(String id, {StrokeTool tool = StrokeTool.pen, ShapeKind? shape}) =>
        Stroke(id: id, tool: tool, color: 0, size: 1, raw: const [InkPoint(0, 0, 0.5, 0)], shape: shape);
    final key = handwritingKeyOf([s('a'), s('b')]);
    expect(key, startsWith('2-'));
    expect(handwritingKeyOf([s('b'), s('a')]), key);
    expect(handwritingKeyOf([s('a'), s('b'), s('h', tool: StrokeTool.highlighter), s('r', shape: ShapeKind.rectangle)]), key);
    expect(handwritingKeyOf([s('a'), s('c')]), isNot(key));
    expect(handwritingKeyOf(const []), '');
  });

  testWidgets('a moment after the editor is left alone, its handwriting is stored for search', (tester) async {
    final r = reader();
    final o = await open(tester, r);
    expect(o.stored, isNull, reason: 'nothing while it was just opened');
    await idle(tester);
    expect(o.stored, 'hello online');
    expect(r.calls, 1);
    expect((await o.repo.handwritingKeys(o.notebookId))[o.pageId], handwritingKeyOf(o.controller.doc.page(o.pageId).strokes));

    // Nothing changed: not read again.
    o.controller.selectTool(EditorTool.highlighter);
    await idle(tester);
    expect(r.calls, 1);

    // New writing: read again.
    o.controller.execute(AddStrokesCommand(o.pageId, writeLine('b', ['hello'], y: 156)));
    await idle(tester);
    expect(o.stored, 'hello online\nsecond');
    expect(r.calls, 2);
  });

  testWidgets('anything that happens while reading stops it; it is read again later', (tester) async {
    final r = reader()..gate = Completer<void>();
    final o = await open(tester, r);
    await tester.pump(const Duration(seconds: 9));
    expect(r.calls, 1);
    o.controller.selectTool(EditorTool.highlighter); // the user does something
    r.gate!.complete();
    r.gate = null;
    await tester.pump(const Duration(milliseconds: 100));
    expect(o.stored, isNull, reason: 'the reading was dropped');
    await idle(tester);
    expect(o.stored, 'hello online');
  });

  testWidgets('with the setting off nothing is read', (tester) async {
    final r = reader();
    final o = await open(tester, r, enabled: false);
    await idle(tester);
    expect(r.calls, 0);
    expect(o.stored, isNull);
  });

  test('the setting is on by default', () {
    expect(const AppSettings().searchHandwriting, isTrue);
    expect(AppSettings.fromJson(const {}).searchHandwriting, isTrue);
  });
}
