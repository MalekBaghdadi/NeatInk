import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/editor_controller.dart';
import 'package:neatink/features/editor/editor_integrations.dart';
import 'package:neatink/features/editor/editor_screen.dart';
import 'package:neatink/features/editor/integrations/pdf/margins_install.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/render/paper_painter.dart';
import 'package:neatink/storage/notebook_repository.dart' show PdfPageSize;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../fakes/in_memory_repository.dart';

void main() {
  late InMemoryNotebookRepository repo;
  late EditorController controller;

  Future<void> open(WidgetTester tester, {bool pdf = true}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = InMemoryNotebookRepository();
    final meta = pdf
        ? await repo.createPdfNotebook(
            title: 'Slides', sourcePdfPath: '/x.pdf', pageSizes: const [PdfPageSize(600, 800)])
        : await repo.createNotebook(title: 'Plain', paper: const Paper(), pageCount: 1);
    await repo.savePage(
        meta.id,
        meta.pages.first.id,
        PageContent(strokes: [
          Stroke(id: 's', tool: StrokeTool.pen, color: 0xFF000000, size: 2, raw: const [
            InkPoint(100, 100, 0.5, 0),
            InkPoint(200, 120, 0.5, 10),
          ]),
        ]));
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notebookRepositoryProvider.overrideWithValue(repo),
      editorIntegrationsProvider.overrideWithValue([
        (c, ref) {
          controller = c;
          installPdfMargins(c);
        },
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
      await tester.pump(const Duration(seconds: 6));
    });
  }

  Future<void> choose(WidgetTester tester, String margins) async {
    await tester.tap(find.byKey(const ValueKey('editor-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-pdf-margins')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('pdf-margins-$margins')));
    await tester.tap(find.byKey(const ValueKey('pdf-margins-ok')));
    await tester.pumpAndSettle();
  }

  testWidgets('the menu adds margins; the writing moves with its page; undo puts it back', (tester) async {
    await open(tester);
    await choose(tester, 'wide');
    final page = controller.doc.meta.pages.single;
    expect((page.width, page.marginLeft, page.marginRight), (1200.0, 300.0, 300.0));
    final s = controller.doc.page(page.id).strokes.single;
    expect(s.raw.first.x, 400);
    expect(controller.undoLabel, 'PDF margins');
    // The margins show paper beside the PDF page.
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is PdfPageFramePainter), findsWidgets);

    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.doc.meta.pages.single.width, 600);
    expect(controller.doc.page(page.id).strokes.single.raw.first.x, 100);
  });

  testWidgets('narrowing over notes in the margins asks first', (tester) async {
    await open(tester);
    await choose(tester, 'wide');
    // A note in the left margin, which "None" would cut off.
    final id = controller.doc.meta.pages.single.id;
    controller.doc.page(id).strokes.add(Stroke(
        id: 'm', tool: StrokeTool.pen, color: 0xFF000000, size: 2, raw: const [
      InkPoint(20, 50, 0.5, 0),
      InkPoint(120, 60, 0.5, 10),
    ]));
    await choose(tester, 'none');
    expect(find.text('Hide notes in the margins?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.doc.meta.pages.single.width, 1200, reason: 'unchanged');
  });

  testWidgets('plain notebooks have no PDF margins item', (tester) async {
    await open(tester, pdf: false);
    await tester.tap(find.byKey(const ValueKey('editor-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-pdf-margins')), findsNothing);
  });
}
