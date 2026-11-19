import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/canvas/document_view.dart';
import 'package:neatink/features/editor/canvas/page_view.dart';
import 'package:neatink/features/editor/editor_controller.dart';
import 'package:neatink/features/editor/editor_integrations.dart';
import 'package:neatink/features/editor/editor_screen.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/integrations/text_images/text_editor.dart';
import 'package:neatink/features/editor/integrations/text_images/text_images_integration.dart';
import 'package:neatink/features/editor/integrations/text_images/text_tool.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../fakes/in_memory_repository.dart';

// v1.13.1: Mariam tapped a text box to type and the keyboard came up and
// went straight down again, every time. The keyboard makes the page area
// shorter, so fewer pages are in range; the pages kept their widgets by
// position, not by page, so the page with the box was built again and its
// text field (and the keyboard with it) was closed.

const box = TextItem(id: 't', x: 100, y: 300, width: 300, height: 20, text: 'Neurons', fontSize: 20);

void main() {
  late EditorController controller;

  Future<TextBoxEditor> open(WidgetTester tester, {int pages = 5, int boxPage = 2}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = InMemoryNotebookRepository();
    final meta = await repo.createNotebook(title: 'Notes', paper: const Paper(), pageCount: pages);
    await repo.savePage(meta.id, meta.pages[boxPage].id, PageContent(texts: const [box]));
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notebookRepositoryProvider.overrideWithValue(repo),
      editorIntegrationsProvider.overrideWithValue([
        (c, ref) {
          controller = c;
          textImagesIntegration(c, ref);
        },
      ]),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: EditorScreen(notebookId: meta.id, initialPageIndex: boxPage)),
    ));
    await tester.pumpAndSettle();
    controller.selectTool(EditorTool.text);
    await tester.pump();
    return (controller.extensions.toolHandlers[EditorTool.text]! as TextToolHandler).editor;
  }

  Set<int> builtPages(WidgetTester tester) =>
      {for (final p in tester.widgetList<EditorPageView>(find.byType(EditorPageView))) p.pageIndex};

  /// A finger tap on the box, the way Mariam opens it.
  Future<void> tapBox(WidgetTester tester, int pageIndex) async {
    final local = controller.viewport.pageToLocal(pageIndex, box.frame.center);
    await tester.tapAt(tester.getTopLeft(find.byType(DocumentView)) + local);
    await tester.pump();
  }

  testWidgets('the keyboard stays up when it makes the pages area shorter', (tester) async {
    final editor = await open(tester);
    await tapBox(tester, 2);
    expect(editor.session, isNotNull, reason: 'the box is being edited');
    await tester.pump();
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editor.session!.focus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue, reason: 'the keyboard comes up');
    final before = builtPages(tester);

    // The keyboard opens: the page area gets much shorter.
    tester.view.viewInsets = const FakeViewPadding(bottom: 420);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(builtPages(tester), isNot(before), reason: 'the test must change the range of built pages');

    expect(find.byType(EditableText), findsOneWidget);
    expect(identical(tester.state<EditableTextState>(find.byType(EditableText)), state), isTrue,
        reason: 'the text field is kept, not built again');
    expect(editor.session, isNotNull);
    expect(editor.session!.focus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue, reason: 'the keyboard stays up');

    // She can type.
    tester.testTextInput.enterText('Neurons fire');
    await tester.pump();
    expect(editor.session!.input.text, 'Neurons fire');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a box low on the screen is moved up above the keyboard', (tester) async {
    final editor = await open(tester);
    await tapBox(tester, 2);
    await tester.pumpAndSettle();
    expect(editor.session, isNotNull);
    final viewport = controller.viewport;

    Rect onScreen() {
      final r = editor.docRect()!;
      final s = viewport.scale;
      return Rect.fromLTRB(r.left * s, r.top * s, r.right * s, r.bottom * s).shift(viewport.offset);
    }

    // Scroll so the box is near the bottom of the pages area.
    viewport.panBy(Offset(0, viewport.viewportSize.height - 30 - onScreen().bottom));
    await tester.pump();
    expect(onScreen().bottom, closeTo(viewport.viewportSize.height - 30, 1));
    final heightBefore = viewport.viewportSize.height;

    tester.view.viewInsets = const FakeViewPadding(bottom: 420);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.pump();

    expect(viewport.viewportSize.height, lessThan(heightBefore - 300), reason: 'the keyboard took room');
    final box = onScreen();
    expect(box.top, greaterThanOrEqualTo(0));
    expect(box.bottom, lessThanOrEqualTo(viewport.viewportSize.height), reason: 'she sees what she types');
    expect(tester.testTextInput.isVisible, isTrue);
    expect(editor.session!.focus.hasFocus, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });
}
