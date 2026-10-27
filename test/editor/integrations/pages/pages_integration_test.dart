import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/editor_controller.dart';
import 'package:neatink/features/editor/editor_integrations.dart';
import 'package:neatink/features/editor/editor_screen.dart';
import 'package:neatink/features/editor/integrations/pages/page_navigator.dart';
import 'package:neatink/features/editor/integrations/pages/pages_integration.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../editor_tools/tool_test_utils.dart';
import '../../../fakes/in_memory_repository.dart';

Future<EditorController> openEditor(WidgetTester tester,
    {int pages = 3}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final repo = InMemoryNotebookRepository();
  final meta = await repo.createNotebook(
      title: 'Test', paper: const Paper(), pageCount: pages);
  for (final p in meta.pages) {
    await repo.savePage(meta.id, p.id, PageContent());
  }
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  EditorController? captured;
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    notebookRepositoryProvider.overrideWithValue(repo),
    editorIntegrationsProvider.overrideWithValue([
      (controller, ref) => captured = controller,
      pagesIntegration,
    ]),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: EditorScreen(notebookId: meta.id)),
  ));
  await tester.pumpAndSettle();
  expect(captured!.isReady, isTrue);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });
  return captured!;
}

void main() {
  testWidgets('delete is undoable and keeps the ink', (tester) async {
    final c = await openEditor(tester);
    final ops = PageOps(c);
    final id = c.doc.meta.pages[1].id;
    c.doc.page(id).strokes.add(
        strokeOf('s1', [const Vec2(10, 10), const Vec2(50, 50)]));
    expect(ops.delete(1), isTrue);
    expect(c.pageCount, 2);
    expect(c.doc.pages.containsKey(id), isFalse);
    c.undo();
    await tester.pump();
    expect(c.pageCount, 3);
    expect(c.doc.meta.pages[1].id, id);
    expect(c.doc.page(id).strokes.single.id, 's1');
  });

  testWidgets('last page cannot be deleted', (tester) async {
    final c = await openEditor(tester, pages: 1);
    expect(PageOps(c).delete(0), isFalse);
    expect(c.pageCount, 1);
  });

  testWidgets('duplicate copies content with new ids, undoable',
      (tester) async {
    final c = await openEditor(tester);
    final ops = PageOps(c);
    final id = c.doc.meta.pages[0].id;
    c.doc.page(id).strokes.add(
        strokeOf('s1', [const Vec2(10, 10), const Vec2(50, 50)]));
    final copy = ops.duplicate(0)!;
    expect(c.pageCount, 4);
    expect(c.doc.meta.pages[1].id, copy.id);
    final strokes = c.doc.page(copy.id).strokes;
    expect(strokes, hasLength(1));
    expect(strokes.single.id, isNot('s1'));
    expect(strokes.single.raw.length, 2);
    expect(c.doc.page(id).strokes.single.id, 's1');
    c.undo();
    expect(c.pageCount, 3);
  });

  testWidgets('insert blank after, move, undo', (tester) async {
    final c = await openEditor(tester);
    final ops = PageOps(c);
    final ids = [for (final p in c.doc.meta.pages) p.id];
    final blank = ops.insertBlankAfter(0)!;
    expect(c.doc.meta.pages[1].id, blank.id);
    expect(c.doc.page(blank.id).isEmpty, isTrue);
    expect(ops.move(0, 3), isTrue);
    expect(c.doc.meta.pages.last.id, ids[0]);
    expect(ops.move(2, 2), isFalse);
    c.undo();
    expect(c.doc.meta.pages.first.id, ids[0]);
  });

  testWidgets('change paper: one page, all pages, undo', (tester) async {
    final c = await openEditor(tester);
    final ops = PageOps(c);
    const dark = Paper(type: PaperType.dotted, color: Paper.dark);
    expect(ops.setPaper(1, dark), isTrue);
    expect(c.doc.meta.pages[1].paper, dark);
    expect(c.doc.meta.pages[0].paper, isNot(dark));
    expect(ops.setPaper(1, dark), isFalse);
    expect(ops.setPaperAll(const Paper(type: PaperType.cornell)), isTrue);
    expect(c.doc.meta.pages.every((p) => p.paper.type == PaperType.cornell),
        isTrue);
    c.undo();
    expect(c.doc.meta.pages[1].paper, dark);
    c.undo();
    expect(c.doc.meta.pages[1].paper, isNot(dark));
  });

  testWidgets('quick nav moves between pages and jumps', (tester) async {
    final c = await openEditor(tester);
    expect(c.extensions.openPageNavigator, isNotNull);
    expect(c.extensions.changePagePaper, isNotNull);
    expect(find.text('1 / 3'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('quick-next')));
    await tester.pumpAndSettle();
    expect(c.currentPageIndex, 1);
    await tester.tap(find.byKey(const ValueKey('quick-prev')));
    await tester.pumpAndSettle();
    expect(c.currentPageIndex, 0);
    await tester.tap(find.byKey(const ValueKey('quick-jump')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('jump-field')), '3');
    await tester.tap(find.byKey(const ValueKey('jump-go')));
    await tester.pumpAndSettle();
    expect(c.currentPageIndex, 2);
  });

  testWidgets('navigator grid: menu delete shows undo bar, undo restores',
      (tester) async {
    final c = await openEditor(tester);
    unawaited(showPageNavigator(
        tester.element(find.byType(EditorScreen)), c));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-open-2')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('page-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(c.pageCount, 4);
    await tester.tap(find.byKey(const ValueKey('page-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(c.pageCount, 3);
    expect(find.byKey(const ValueKey('nav-undo-bar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-undo')));
    await tester.pumpAndSettle();
    expect(c.pageCount, 4);
    await tester.tap(find.byKey(const ValueKey('page-open-3')));
    await tester.pumpAndSettle();
    expect(find.byType(PageNavigator), findsNothing);
  });

  testWidgets('navigator paper dialog changes the page paper',
      (tester) async {
    final c = await openEditor(tester);
    unawaited(showPageNavigator(
        tester.element(find.byType(EditorScreen)), c));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('page-menu-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Paper ('));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paper-type-music')));
    await tester.tap(find.byKey(const ValueKey('paper-color-dark')));
    await tester.tap(find.byKey(const ValueKey('paper-apply')));
    await tester.pumpAndSettle();
    final p = c.doc.meta.pages[0].paper;
    expect(p.type, PaperType.music);
    expect(p.color, Paper.dark);
  });
}
