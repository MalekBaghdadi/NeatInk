import 'dart:convert';

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
import 'package:neatink/features/editor/integrations/autocorrect/autocorrect_integration.dart';
import 'package:neatink/features/editor/integrations/convert/user_lexicon.dart';
import 'package:neatink/features/editor/integrations/text_images/text_images_integration.dart';
import 'package:neatink/features/settings/app_settings.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:neatink/render/text_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../fakes/in_memory_repository.dart';

// The test font draws every glyph as a square as wide as the font size.
const neurons = TextCorrection(start: 0, original: 'Nuerons', replacement: 'Neurons');
const box = TextItem(
    id: 't1', x: 100, y: 100, width: 600, height: 24, text: 'Neurons are in the brain', fontSize: 20,
    corrections: [neurons]);

class _Harness {
  _Harness(this.tester, this.controller, this.learner);

  final WidgetTester tester;
  final EditorController controller;
  final InMemoryWordLearner learner;

  static Future<_Harness> open(WidgetTester tester, {bool autocorrect = true}) async {
    SharedPreferences.setMockInitialValues({
      AppSettings.prefsKey: jsonEncode({'autocorrect': autocorrect}),
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = InMemoryNotebookRepository();
    final meta = await repo.createNotebook(title: 'Test', paper: const Paper(), pageCount: 1);
    await repo.savePage(meta.id, meta.pages.first.id, PageContent(texts: [box]));
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final learner = InMemoryWordLearner();
    EditorController? captured;
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notebookRepositoryProvider.overrideWithValue(repo),
      userLexiconProvider.overrideWithValue(learner),
      editorIntegrationsProvider.overrideWithValue([
        (controller, ref) => captured = controller,
        textImagesIntegration,
        autocorrectIntegration,
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
      await tester.pump(const Duration(seconds: 7));
    });
    return _Harness(tester, captured!, learner);
  }

  PageContent get page => controller.doc.page(controller.doc.meta.pages.first.id);

  Offset at(Vec2 p) => tester.getTopLeft(find.byType(DocumentView)) + controller.viewport.pageToLocal(0, p);

  /// The middle of the corrected word on screen.
  Offset get word {
    final r = correctionBoxes(page.texts.single).single.$2.first;
    return at(Vec2(r.center.dx, r.center.dy));
  }

  Future<void> tap(Offset where, {PointerDeviceKind kind = PointerDeviceKind.stylus}) async {
    final g = await tester.startGesture(where, kind: kind);
    await tester.pump(const Duration(milliseconds: 60));
    await g.up();
    await tester.pumpAndSettle();
  }
}

Finder key(String k) => find.byKey(ValueKey(k));

void main() {
  test('the corrected word is where the text layout draws it', () {
    final (c, rects) = correctionBoxes(box).single;
    expect(c, neurons);
    expect(rects.single.left, 100);
    expect(rects.single.width, 7 * 20, reason: '"Neurons" is 7 glyphs');
    expect(correctionAt('p', [box], const Vec2(170, 110))?.correction, neurons);
    expect(correctionAt('p', [box], const Vec2(300, 110)), isNull, reason: 'another word');
  });

  testWidgets('a pen tap on a corrected word offers the written word; tapping it puts it back',
      (tester) async {
    final h = await _Harness.open(tester);
    h.controller.selectTool(EditorTool.pen);
    await tester.pump();
    await h.tap(h.word);
    expect(key('autocorrect-bubble'), findsOneWidget);
    expect(find.text('Nuerons'), findsOneWidget);
    expect(h.page.strokes, isEmpty, reason: 'the tap leaves no dot');

    await tester.tap(key('autocorrect-restore'));
    await tester.pumpAndSettle();
    expect(h.page.texts.single.text, 'Nuerons are in the brain');
    expect(h.page.texts.single.corrections, isEmpty);
    expect(key('autocorrect-bubble'), findsNothing);
    expect(h.controller.undoLabel, 'Undo autocorrect');
    expect(h.learner.words, ['Nuerons'], reason: 'not corrected again next time');

    h.controller.undo();
    await tester.pump();
    expect(h.page.texts.single.text, 'Neurons are in the brain');
    expect(h.page.texts.single.liveCorrections, [neurons]);
  });

  testWidgets('the tick keeps the correction and removes the mark', (tester) async {
    final h = await _Harness.open(tester);
    await h.tap(h.word);
    await tester.tap(key('autocorrect-keep'));
    await tester.pumpAndSettle();
    expect(h.page.texts.single.text, 'Neurons are in the brain');
    expect(h.page.texts.single.corrections, isEmpty);
    expect(h.controller.undoLabel, 'Keep correction');
    expect(h.learner.words, isEmpty);
  });

  testWidgets('a finger tap works too', (tester) async {
    final h = await _Harness.open(tester);
    await h.tap(h.word, kind: PointerDeviceKind.touch);
    expect(key('autocorrect-bubble'), findsOneWidget);
  });

  testWidgets('a tap elsewhere closes the bubble; with it closed, a pen tap is a dot',
      (tester) async {
    final h = await _Harness.open(tester);
    h.controller.selectTool(EditorTool.pen);
    await tester.pump();
    await h.tap(h.word);
    expect(key('autocorrect-bubble'), findsOneWidget);
    final empty = h.at(const Vec2(300, 400));
    await h.tap(empty);
    expect(key('autocorrect-bubble'), findsNothing);
    expect(h.page.strokes, isEmpty, reason: 'closing the bubble draws nothing');
    await h.tap(empty);
    expect(h.page.strokes, hasLength(1), reason: 'an ordinary pen tap is a dot');
  });

  testWidgets('the bubble closes by itself', (tester) async {
    final h = await _Harness.open(tester);
    await h.tap(h.word);
    expect(key('autocorrect-bubble'), findsOneWidget);
    await tester.pump(AutocorrectBubble.visibleFor + const Duration(milliseconds: 100));
    expect(key('autocorrect-bubble'), findsNothing);
  });

  testWidgets('with autocorrect off a tap on the word is just ink', (tester) async {
    final h = await _Harness.open(tester, autocorrect: false);
    h.controller.selectTool(EditorTool.pen);
    await tester.pump();
    await h.tap(h.word);
    expect(key('autocorrect-bubble'), findsNothing);
    expect(h.page.strokes, hasLength(1));
  });
}
