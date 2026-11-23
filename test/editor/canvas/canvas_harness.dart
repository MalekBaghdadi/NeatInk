import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/canvas/document_view.dart';
import 'package:neatink/features/editor/canvas/stroke_constraint.dart';
import 'package:neatink/features/editor/editor_controller.dart';
import 'package:neatink/features/editor/editor_extensions.dart';
import 'package:neatink/features/editor/editor_integrations.dart';
import 'package:neatink/features/editor/editor_screen.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../fakes/in_memory_repository.dart';

/// A [StrokeConstraint] that maps every position with [map].
class FnConstraint implements StrokeConstraint {
  FnConstraint(this.map);

  final Offset Function(Offset local) map;

  @override
  Offset project(Offset local) => map(local);
}

/// Opens the editor with the given integrations on a one-page A4 notebook and
/// drives it with synthetic pointer events.
///
/// Positions the helpers take are in the document view's local space (the
/// space pointer events and constraints work in) unless a method says page
/// points. With the 1000 x 1400 screen the view shows page 1 at scale 1.627
/// (968 px wide), starting at x = 16, y = 16.
class CanvasHarness {
  CanvasHarness._(this.tester, this.controller, this.container);

  final WidgetTester tester;
  final EditorController controller;
  final ProviderContainer container;

  static Future<CanvasHarness> open(
    WidgetTester tester, {
    List<EditorIntegration> integrations = const [],
    List<Stroke> strokes = const [],
    Size screen = const Size(1000, 1400),
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = InMemoryNotebookRepository();
    final meta = await repo.createNotebook(
        title: 'Test', paper: const Paper(), pageCount: 1);
    await repo.savePage(
        meta.id, meta.pages.first.id, PageContent(strokes: List.of(strokes)));
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    EditorController? captured;
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notebookRepositoryProvider.overrideWithValue(repo),
      editorIntegrationsProvider.overrideWithValue([
        (controller, ref) => captured = controller,
        ...integrations,
      ]),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: EditorScreen(notebookId: meta.id)),
    ));
    await tester.pumpAndSettle();
    final h = CanvasHarness._(tester, captured!, container);
    expect(h.controller.isReady, isTrue);
    return h;
  }

  String get pageId => controller.doc.meta.pages.first.id;
  List<Stroke> get strokes => controller.doc.page(pageId).strokes;
  int get undoDepth => controller.commands.undoDepth;

  /// The document view's top-left corner on screen.
  Offset get origin => tester.getTopLeft(find.byType(DocumentView));

  /// The document view's size.
  Size get viewSize => tester.getSize(find.byType(DocumentView));

  /// A local position on screen.
  Offset global(Offset local) => origin + local;

  /// The local position of a point of page 1.
  Offset local(Vec2 pagePoint) => controller.viewport.pageToLocal(0, pagePoint);

  /// The page point of a local position.
  Vec2 page(Offset local) => controller.viewport.localToPage(local, 0);

  /// Presses a pointer at local position [at].
  Future<TestGesture> down(
    Offset at, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) async {
    final g = await tester.startGesture(global(at), kind: kind);
    await tester.pump(const Duration(milliseconds: 8));
    return g;
  }

  Future<void> moveTo(TestGesture g, Offset at) async {
    await g.moveTo(global(at));
    await tester.pump(const Duration(milliseconds: 8));
  }

  /// Presses at the first position, moves through the rest and lifts.
  Future<void> drag(
    List<Offset> path, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) async {
    final g = await down(path.first, kind: kind);
    for (final p in path.skip(1)) {
      await moveTo(g, p);
    }
    await g.up();
    await tester.pump();
  }

  /// Removes the editor so no timer outlives the test.
  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  }
}

/// An integration that installs [provider] as the stroke constraint provider.
EditorIntegration strokeConstraintIntegration(
        StrokeConstraintProvider provider) =>
    (controller, ref) => controller.extensions.strokeConstraint = provider;
