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
import 'package:neatink/features/editor/integrations/convert/convert_providers.dart';
import 'package:neatink/features/editor/integrations/convert/user_lexicon.dart';
import 'package:neatink/features/editor/integrations/text_images/text_images_integration.dart';
import 'package:neatink/features/settings/app_settings.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:neatink/recognition/htr_channel.dart';
import 'package:neatink/recognition/lexicon.dart';
import 'package:neatink/recognition/text_polish.dart';
import 'package:neatink/render/text_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../fakes/in_memory_repository.dart';

// The test font draws every glyph as a square as wide as the font size.
const neurons = TextCorrection(start: 0, original: 'Nuerons', replacement: 'Neurons');
const box = TextItem(
    id: 't1', x: 100, y: 100, width: 600, height: 24, text: 'Neurons are in the brain', fontSize: 20,
    corrections: [neurons]);

/// A second box with a word the spell checker marks: "sensoy" is x 180-300.
const misspelt = TextItem(id: 't2', x: 100, y: 300, width: 600, height: 24, text: 'The sensoy info', fontSize: 20);

/// Reads nothing; its word list knows the words of [box] and [misspelt].
class _SpellRecognizer extends Fake implements HtrRecognizer {
  @override
  Future<TextPolisher> polisher() async => TextPolisher(Lexicon.parse(
      'filler 330000000000\nthe 9000000000\nare 2000000000\nin 9000000000\nbrain 50000000\n'
      'neurons 5000000\nsensory 20000000\nsensor 9000000\ninfo 5000000\n'));
}

class _Harness {
  _Harness(this.tester, this.controller, this.learner);

  final WidgetTester tester;
  final EditorController controller;
  final InMemoryWordLearner learner;

  static Future<_Harness> open(WidgetTester tester,
      {bool autocorrect = true, bool checkSpelling = true, List<TextItem> texts = const [box]}) async {
    SharedPreferences.setMockInitialValues({
      AppSettings.prefsKey: jsonEncode({'autocorrect': autocorrect, 'checkSpelling': checkSpelling}),
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = InMemoryNotebookRepository();
    final meta = await repo.createNotebook(title: 'Test', paper: const Paper(), pageCount: 1);
    await repo.savePage(meta.id, meta.pages.first.id, PageContent(texts: texts));
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final learner = InMemoryWordLearner();
    EditorController? captured;
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notebookRepositoryProvider.overrideWithValue(repo),
      userLexiconProvider.overrideWithValue(learner),
      htrRecognizerProvider.overrideWithValue(_SpellRecognizer()),
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
    final r = correctionBoxes(page.texts.first).single.$2.first;
    return at(Vec2(r.center.dx, r.center.dy));
  }

  /// The middle of "sensoy" on screen.
  Offset get sensoy => at(const Vec2(240, 310));

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

  group('spell check', () {
    testWidgets('a tap on a marked word offers spellings; picking one writes it', (tester) async {
      final h = await _Harness.open(tester, texts: [box, misspelt]);
      h.controller.selectTool(EditorTool.pen);
      await tester.pump();
      await h.tap(h.sensoy);
      expect(key('spelling-bubble'), findsOneWidget);
      expect(find.text('sensory'), findsOneWidget);
      expect(h.page.strokes, isEmpty, reason: 'the tap leaves no dot');

      await tester.tap(key('spelling-suggestion-0'));
      await tester.pumpAndSettle();
      expect(h.page.texts.last.text, 'The sensory info');
      expect(h.controller.undoLabel, 'Spelling');
      expect(key('spelling-bubble'), findsNothing);
      h.controller.undo();
      await tester.pump();
      expect(h.page.texts.last.text, 'The sensoy info');
    });

    testWidgets('Add to My words teaches the word and removes the mark', (tester) async {
      final h = await _Harness.open(tester, texts: [box, misspelt]);
      await h.tap(h.sensoy);
      await tester.tap(key('spelling-add'));
      await tester.pumpAndSettle();
      expect(h.learner.words, ['sensoy']);
      expect(h.page.texts.last.text, 'The sensoy info', reason: 'the text stays');
      await h.tap(h.sensoy, kind: PointerDeviceKind.touch);
      expect(key('spelling-bubble'), findsNothing, reason: 'no longer marked');
    });

    testWidgets('a corrected word keeps its own bubble', (tester) async {
      final h = await _Harness.open(tester, texts: [box, misspelt]);
      await h.tap(h.word);
      expect(key('autocorrect-bubble'), findsOneWidget);
      expect(key('spelling-bubble'), findsNothing);
    });

    testWidgets('with Check spelling off a tap on the word is just ink', (tester) async {
      final h = await _Harness.open(tester, checkSpelling: false, texts: [box, misspelt]);
      h.controller.selectTool(EditorTool.pen);
      await tester.pump();
      await h.tap(h.sensoy);
      expect(key('spelling-bubble'), findsNothing);
      expect(h.page.strokes, hasLength(1));
    });
  });
}
