import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/canvas/document_view.dart';
import 'package:neatink/features/editor/editor_controller.dart';
import 'package:neatink/features/editor/editor_integrations.dart';
import 'package:neatink/features/editor/editor_screen.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/integrations/erase_select/erase_select_integration.dart';
import 'package:neatink/features/editor/integrations/erase_select/lasso_handler.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../fakes/in_memory_repository.dart';

/// Opens the editor with [eraseSelectIntegration] on a one-page notebook
/// holding the given content, and drives it with synthetic pen events.
class EraseSelectHarness {
  EraseSelectHarness._(this.tester, this.controller);

  final WidgetTester tester;
  final EditorController controller;

  static Future<EraseSelectHarness> open(
    WidgetTester tester, {
    List<Stroke> strokes = const [],
    List<TextItem> texts = const [],
    List<ImageItem> images = const [],
    List<EditorIntegration> extra = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = InMemoryNotebookRepository();
    final meta = await repo.createNotebook(
        title: 'Test', paper: const Paper(), pageCount: 1);
    await repo.savePage(
      meta.id,
      meta.pages.first.id,
      PageContent(
          strokes: List.of(strokes),
          texts: List.of(texts),
          images: List.of(images)),
    );
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    EditorController? captured;
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notebookRepositoryProvider.overrideWithValue(repo),
      editorIntegrationsProvider.overrideWithValue([
        (controller, ref) => captured = controller,
        eraseSelectIntegration,
        ...extra,
      ]),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: EditorScreen(notebookId: meta.id)),
    ));
    await tester.pumpAndSettle();
    final h = EraseSelectHarness._(tester, captured!);
    expect(h.controller.isReady, isTrue);
    return h;
  }

  String get pageId => controller.doc.meta.pages.first.id;
  PageContent get page => controller.doc.page(pageId);
  List<Stroke> get strokes => page.strokes;
  int get undoDepth => controller.commands.undoDepth;

  LassoHandler get lasso =>
      controller.extensions.toolHandlers[EditorTool.lasso]! as LassoHandler;

  /// Screen position of a point of page 1.
  Offset at(Vec2 p) =>
      tester.getTopLeft(find.byType(DocumentView)) +
      controller.viewport.pageToLocal(0, p);

  /// Presses the pen at the first point, moves through the rest and lifts.
  Future<void> drag(
    List<Vec2> points, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) async {
    final g = await beginDrag(points.first, kind: kind);
    for (final p in points.skip(1)) {
      await g.moveTo(at(p));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await g.up();
    await tester.pump();
  }

  Future<TestGesture> beginDrag(
    Vec2 start, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) async {
    final g = await tester.startGesture(at(start), kind: kind);
    await tester.pump(const Duration(milliseconds: 8));
    return g;
  }

  /// Lassos the rectangle [x0, y0]-[x1, y1] of page 1 with the lasso tool.
  Future<void> lassoRect(double x0, double y0, double x1, double y1) async {
    controller.selectTool(EditorTool.lasso);
    await tester.pump();
    await drag([
      Vec2(x0, y0),
      Vec2(x1, y0),
      Vec2(x1, y1),
      Vec2(x0, y1),
      Vec2(x0, y0 + 1),
    ]);
  }

  /// Removes the editor so no timer outlives the test.
  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  }
}
