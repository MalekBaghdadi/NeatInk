import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/canvas/document_view.dart';
import 'package:neatink/features/editor/editor_controller.dart';
import 'package:neatink/features/editor/editor_integrations.dart';
import 'package:neatink/features/editor/editor_screen.dart';
import 'package:neatink/features/editor/integrations/tidy/tidy_integration.dart';
import 'package:neatink/features/settings/settings_controller.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../beautify/synthetic_font.dart';
import '../../../fakes/in_memory_repository.dart';

void main() {
  late EditorController controller;
  late ProviderContainer container;

  Future<void> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = InMemoryNotebookRepository();
    final meta = await repo.createNotebook(
        title: 'Test', paper: const Paper(), pageCount: 1);
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notebookRepositoryProvider.overrideWithValue(repo),
      editorIntegrationsProvider.overrideWithValue([
        (c, ref) => controller = c,
        // The test clock is the fake one that `pump` advances, so the idle
        // timer and the segmenter's deadlines agree. No animation: the
        // tidy lands as soon as it is decided.
        createTidyIntegration(
          nowMs: () => tester.binding.clock.now().millisecondsSinceEpoch,
          reduceMotion: () => true,
        ),
      ]),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: EditorScreen(notebookId: meta.id)),
    ));
    await tester.pumpAndSettle();
    expect(controller.isReady, isTrue);
  }

  String pageId() => controller.doc.meta.pages.first.id;
  List<Stroke> strokes() => controller.doc.page(pageId()).strokes;

  Offset at(WidgetTester tester, Vec2 p) =>
      tester.getTopLeft(find.byType(DocumentView)) +
      controller.viewport.pageToLocal(0, p);

  /// Writes each stroke of [word] with the stylus, then lifts.
  Future<void> write(WidgetTester tester, List<Stroke> word) async {
    for (final s in word) {
      final pts = [for (var i = 0; i < s.raw.length; i += 4) s.raw[i]];
      final g = await tester.startGesture(at(tester, Vec2(pts.first.x, pts.first.y)),
          kind: PointerDeviceKind.stylus);
      await tester.pump(const Duration(milliseconds: 8));
      for (final p in pts.skip(1)) {
        await g.moveTo(at(tester, Vec2(p.x, p.y)));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  List<Stroke> slantedWord() =>
      makeWord('hello', rotateDeg: 8, scale: 2, x: 150, y: 300);

  /// Waits past the idle deadline so the word is committed.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  }

  bool movedFromRaw(Stroke s) {
    if (s.points.length != s.raw.length) return true;
    for (var i = 0; i < s.raw.length; i++) {
      if ((s.points[i].x - s.raw[i].x).abs() > 1e-6 ||
          (s.points[i].y - s.raw[i].y).abs() > 1e-6) {
        return true;
      }
    }
    return false;
  }

  testWidgets('a finished word is tidied after a pause, as one undo step',
      (tester) async {
    await open(tester);
    final before = controller.commands.undoDepth;
    await write(tester, slantedWord());
    expect(strokes(), isNotEmpty);
    expect(strokes().any((s) => s.tidy.applied), isFalse,
        reason: 'nothing is tidied while the word is still being written');

    await settle(tester);

    expect(strokes().every((s) => s.tidy.applied), isTrue);
    expect(strokes().every(movedFromRaw), isTrue);
    expect(strokes().map((s) => s.wordId).toSet().length, 1,
        reason: 'all strokes share one word id');
    expect(controller.undoLabel, 'Tidy');
    // One step per stroke plus exactly one for the tidy.
    expect(controller.commands.undoDepth, before + slantedWord().length + 1);
  });

  testWidgets('the handwriting as written is kept in raw', (tester) async {
    await open(tester);
    await write(tester, slantedWord());
    final written = [for (final s in strokes()) s.raw.length];
    await settle(tester);
    expect([for (final s in strokes()) s.raw.length], written);
    for (final s in strokes()) {
      expect(s.raw, isNot(equals(s.points)));
    }
  });

  testWidgets('undo restores the writing and does not tidy it again',
      (tester) async {
    await open(tester);
    await write(tester, slantedWord());
    await settle(tester);

    controller.undo();
    await tester.pump();
    await settle(tester);

    expect(strokes(), isNotEmpty);
    expect(strokes().any((s) => s.tidy.applied), isFalse);
    expect(strokes().any(movedFromRaw), isFalse);
    expect(strokes().every((s) => s.tidy.locked), isTrue,
        reason: 'an undone word is locked against automatic tidying');
    expect(controller.undoLabel, isNot('Tidy'));
  });

  testWidgets('redo brings the tidy back', (tester) async {
    await open(tester);
    await write(tester, slantedWord());
    await settle(tester);
    controller.undo();
    await tester.pump();
    controller.redo();
    await tester.pump();
    expect(strokes().every((s) => s.tidy.applied), isTrue);
  });

  testWidgets('tidy switched off leaves the writing alone', (tester) async {
    await open(tester);
    container
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(tidyEnabled: false));
    await tester.pump();
    await write(tester, slantedWord());
    await settle(tester);
    expect(strokes(), isNotEmpty);
    expect(strokes().any((s) => s.tidy.applied), isFalse);
    expect(strokes().any(movedFromRaw), isFalse);
  });

  testWidgets('closing the editor tidies a word that is still waiting',
      (tester) async {
    await open(tester);
    await write(tester, slantedWord());
    expect(strokes().any((s) => s.tidy.applied), isFalse);

    // close() runs the before-save hooks first; call them directly, because
    // the rest of close() renders a thumbnail, which needs a real raster.
    for (final hook in List.of(controller.extensions.beforeSaveHooks)) {
      hook();
    }
    await tester.pump();

    expect(strokes().every((s) => s.tidy.applied), isTrue);
  });
}
