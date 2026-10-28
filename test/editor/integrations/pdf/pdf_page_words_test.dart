import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/features/editor/editor_controller.dart';
import 'package:neatink/features/editor/integrations/pdf/pdf_page_words.dart';
import 'package:neatink/features/editor/tool_prefs.dart';
import 'package:neatink/pdf/pdf_engine.dart' show PdfWordBox;
import 'package:neatink/storage/notebook_repository.dart' show PdfPageSize;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../fakes/in_memory_repository.dart';

void main() {
  late EditorController controller;
  late InMemoryNotebookRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = InMemoryNotebookRepository();
    final meta = await repo.createPdfNotebook(
        title: 'Slides', sourcePdfPath: '/x.pdf', pageSizes: const [PdfPageSize(600, 800), PdfPageSize(600, 800)]);
    controller = EditorController(repository: repo, notebookId: meta.id, toolPrefsStore: ToolPrefsStore(prefs));
    await controller.open();
  });

  tearDown(() => controller.dispose());

  test('words load once in the background, placed after the left margin', () async {
    final calls = <int>[];
    final gate = Completer<List<PdfWordBox>>();
    final words = PdfPageWords(controller, words: (notebookId, index) {
      calls.add(index);
      return gate.future;
    });
    final page = controller.doc.meta.pages[1];
    expect(words.wordsOn(page.id), isNull);
    words.prepare(page.id);
    words.prepare(page.id);
    expect(calls, [1], reason: 'one load per page');
    expect(words.wordsOn(page.id), isNull, reason: 'still loading');

    gate.complete(const [(left: 10, top: 20, right: 30, bottom: 32)]);
    await Future<void>.delayed(Duration.zero);
    expect(words.wordsOn(page.id), [(left: 10.0, top: 20.0, right: 30.0, bottom: 32.0)]);

    // With margins the PDF page moves right: the cached words are stale and
    // load again in the new place.
    final i = controller.doc.meta.pages.indexWhere((p) => p.id == page.id);
    final pages = [...controller.doc.meta.pages];
    pages[i] = page.copyWith(width: 800, marginLeft: 100, marginRight: 100);
    controller.doc.meta = controller.doc.meta.copyWith(pages: pages);
    expect(words.wordsOn(page.id), isNull);
    final again = PdfPageWords(controller, words: (_, _) async => const [(left: 10, top: 20, right: 30, bottom: 32)]);
    again.prepare(page.id);
    await Future<void>.delayed(Duration.zero);
    expect(again.wordsOn(page.id), [(left: 110.0, top: 20.0, right: 130.0, bottom: 32.0)]);
  });

  test('a plain page has no printed words', () async {
    final words = PdfPageWords(controller, words: (_, _) async => throw StateError('not a PDF page'));
    words.prepare('no-such-page');
    expect(words.wordsOn('no-such-page'), isNull);
    expect(controller.doc.meta.pages.first.isPdf, isTrue);
    expect(const PageMeta(id: 'p').contentWidth, a4WidthPt);
  });
}
