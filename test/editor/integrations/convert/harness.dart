import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/editor_controller.dart';
import 'package:neatink/features/editor/editor_integrations.dart';
import 'package:neatink/features/editor/editor_screen.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/integrations/convert/convert_integration.dart';
import 'package:neatink/features/editor/integrations/erase_select/erase_select_integration.dart';
import 'package:neatink/features/editor/integrations/erase_select/lasso_handler.dart';
import 'package:neatink/features/editor/tools/selection.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:neatink/recognition/htr_channel.dart';
import 'package:neatink/recognition/stroke_grouping.dart';
import 'package:neatink/recognition/word_image.dart';
import 'package:neatink/storage/notebook_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../beautify/synthetic_font.dart';
import '../../../fakes/in_memory_repository.dart';

/// Handwriting of [words] on one line: the synthetic stroke font, words
/// [gap] points apart, starting at ([x], [y]) with y the baseline. Word i
/// has stroke ids `<id>w<i>-<k>`.
List<Stroke> writeLine(
  String id,
  List<String> words, {
  required double y,
  double x = 100,
  double gap = 28,
  int? color,
}) {
  final out = <Stroke>[];
  var cursor = 0.0;
  for (var i = 0; i < words.length; i++) {
    final polylines = wordPolylines(words[i]);
    var right = 0.0;
    for (final p in polylines) {
      for (final v in p) {
        if (v.x > right) right = v.x;
      }
    }
    final shifted = [
      for (final p in polylines) [for (final v in p) Vec2(v.x + cursor, v.y)],
    ];
    out.addAll(toStrokes(shifted,
        prefix: '${id}w$i', m: distortion(x: x, y: y)));
    cursor += right + gap;
  }
  if (color == null) return out;
  return [for (final s in out) s.copyWith(color: color)];
}

/// A recogniser that reads words from a table keyed by the stroke id prefix
/// (`l1w0` for the first word of the line written with id `l1`).
class FakeRecognizer extends Fake implements HtrRecognizer {
  FakeRecognizer(this.readings, {this.defaultConfidence = 0.9});

  /// prefix -> (text, confidence)
  final Map<String, (String, double)> readings;
  final double defaultConfidence;

  /// Throws this instead of reading, when set.
  Object? error;

  /// When set, reading waits for it (to look at the progress state).
  Completer<void>? gate;

  int calls = 0;
  int wordsRead = 0;
  void Function(int done, int total)? lastProgress;

  static String keyOf(WordGroup w) => w.strokes.first.id.split('-').first;

  @override
  Future<List<WordResult>> recognizeWords(
    List<WordGroup> words, {
    void Function(int done, int total)? onProgress,
  }) async {
    calls++;
    onProgress?.call(0, words.length);
    final g = gate;
    if (g != null) await g.future;
    final e = error;
    if (e != null) throw e;
    final out = <WordResult>[];
    for (final w in words) {
      final r = readings[keyOf(w)] ?? ('?', defaultConfidence);
      out.add(WordResult(
        group: w,
        text: r.$1,
        confidence: r.$2,
        raw: '${r.$1}~',
        alternatives: const [],
      ));
      onProgress?.call(out.length, words.length);
    }
    wordsRead += words.length;
    return out;
  }
}

class _FlakyRepository extends InMemoryNotebookRepository {
  final Set<String> broken = {};

  @override
  Future<PageContent> loadPage(String notebookId, String pageId) {
    if (broken.contains(pageId)) throw StateError('unreadable');
    return super.loadPage(notebookId, pageId);
  }
}

/// Opens the editor with the erase/select and convert integrations on a
/// notebook holding [pages] (strokes per page), with a fake recogniser and
/// the pure-Dart word renderer (`Picture.toImage` hangs under
/// `flutter_tester`).
class ConvertHarness {
  ConvertHarness._(this.tester, this.controller, this.recognizer);

  final WidgetTester tester;
  final EditorController controller;
  final FakeRecognizer recognizer;

  static Future<ConvertHarness> open(
    WidgetTester tester, {
    List<List<Stroke>> pages = const [[]],
    Paper paper = const Paper(),
    FakeRecognizer? recognizer,
    Set<int> unreadablePages = const {},
    bool pdf = false,
    Size size = const Size(1000, 1400),
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = _FlakyRepository();
    final NotebookMeta meta;
    if (pdf) {
      meta = await repo.createPdfNotebook(
        title: 'Pdf',
        sourcePdfPath: '/x.pdf',
        pageSizes: [for (final _ in pages) const PdfPageSize(595, 842)],
      );
    } else {
      meta = await repo.createNotebook(
          title: 'Test', paper: paper, pageCount: pages.length);
    }
    for (var i = 0; i < pages.length; i++) {
      await repo.savePage(meta.id, meta.pages[i].id,
          PageContent(strokes: List.of(pages[i])));
    }
    repo.broken.addAll([for (final i in unreadablePages) meta.pages[i].id]);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fake = recognizer ?? FakeRecognizer(const {});
    EditorController? captured;
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notebookRepositoryProvider.overrideWithValue(repo),
      htrRecognizerProvider.overrideWithValue(fake),
      wordImageRendererProvider
          .overrideWithValue(const PolylineWordImageRenderer()),
      editorIntegrationsProvider.overrideWithValue([
        (controller, ref) => captured = controller,
        eraseSelectIntegration,
        convertIntegration,
      ]),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: EditorScreen(notebookId: meta.id)),
    ));
    await tester.pumpAndSettle();
    final h = ConvertHarness._(tester, captured!, fake);
    expect(h.controller.isReady, isTrue);
    return h;
  }

  String pageIdAt(int index) => controller.doc.meta.pages[index].id;
  PageContent pageAt(int index) => controller.doc.page(pageIdAt(index));
  PageContent get page => pageAt(0);
  int get undoDepth => controller.commands.undoDepth;

  LassoHandler get lasso =>
      controller.extensions.toolHandlers[EditorTool.lasso]! as LassoHandler;

  /// Selects [strokeIds] of page [index] (as the lasso would).
  void select(Iterable<String> strokeIds, {int index = 0}) {
    controller.selectTool(EditorTool.lasso);
    lasso.state.setSelection(Selection.fromPage(pageAt(index),
        pageId: pageIdAt(index), strokeIds: strokeIds));
  }

  /// Taps the app bar Convert button and lets the reading finish.
  Future<void> tapConvert() async {
    await tester.tap(find.byKey(const ValueKey('convert-to-text')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}
