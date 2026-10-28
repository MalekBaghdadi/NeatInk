import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/commands.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/editor_controller.dart';
import 'package:neatink/features/editor/editor_integrations.dart';
import 'package:neatink/features/editor/editor_screen.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/stroke_events.dart';
import 'package:neatink/features/editor/integrations/convert/convert_integration.dart';
import 'package:neatink/features/editor/integrations/convert/convert_plan.dart';
import 'package:neatink/features/editor/integrations/erase_select/erase_select_integration.dart';
import 'package:neatink/features/editor/integrations/erase_select/lasso_handler.dart';
import 'package:neatink/features/editor/integrations/convert/sample_share.dart';
import 'package:neatink/features/editor/integrations/convert/user_lexicon.dart';
import 'package:neatink/features/editor/tools/selection.dart';
import 'package:neatink/features/settings/app_settings.dart';
import 'package:neatink/features/settings/settings_controller.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:neatink/recognition/htr_channel.dart';
import 'package:neatink/recognition/stroke_grouping.dart';
import 'package:neatink/recognition/text_polish.dart';
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

/// A recognised line the way the recogniser returns it: [readings] are the
/// (text, confidence) of each word group of [line], in order. The line's
/// confidence is that of its least sure word unless [confidence] says
/// otherwise; its text is the non-empty words joined by single spaces.
LineResult lineResultOf(
  RecognizedLine line,
  List<(String, double)> readings, {
  double? confidence,
  List<PolishSuggestion> suggestions = const [],
  List<List<String>>? alternatives,
  List<LineImage> images = const [],
}) {
  // No `expect` here: this runs inside the recogniser while a test pumps.
  if (readings.length != line.words.length) {
    throw ArgumentError('${readings.length} readings for ${line.words.length} words');
  }
  final words = [
    for (var i = 0; i < readings.length; i++)
      WordResult(
        group: line.words[i],
        text: readings[i].$1,
        confidence: readings[i].$2,
        raw: '${readings[i].$1}~',
        alternatives: alternatives?[i] ?? const [],
      ),
  ];
  final text = words.map((w) => w.text).where((t) => t.isNotEmpty).join(' ');
  return LineResult(
    line: line,
    words: words,
    text: text,
    raw: '$text~',
    confidence:
        confidence ?? words.fold<double>(1, (c, w) => math.min(c, w.confidence)),
    suggestions: suggestions,
    images: images,
  );
}

/// One line of handwriting with `readings.length` words, already recognised
/// (see [lineResultOf]) and planned the way `recognizePages` plans it.
PlannedLine plannedLineOf(
  List<(String, double)> readings, {
  String id = 'p/0',
  double? confidence,
  List<PolishSuggestion> suggestions = const [],
  List<List<String>>? alternatives,
  List<LineImage> images = const [],
  bool autoFix = false,
}) {
  final strokes = writeLine('a', [for (final _ in readings) 'hello'], y: 104);
  final line = groupStrokes(strokes).single;
  return plannedLineFrom(
    id: id,
    pageId: 'p',
    result: lineResultOf(line, readings,
        confidence: confidence,
        suggestions: suggestions,
        alternatives: alternatives,
        images: images),
    autoFix: autoFix,
  );
}

/// A recogniser that reads lines from a table keyed by the stroke id prefix
/// of each word (`l1w0` for the first word of the line written with id `l1`):
/// every word group of a line is looked up, the line's text is its words and
/// its confidence that of its least sure word.
class FakeRecognizer extends Fake implements HtrRecognizer {
  FakeRecognizer(this.readings, {this.defaultConfidence = 0.9});

  /// prefix -> (text, confidence)
  final Map<String, (String, double)> readings;
  final double defaultConfidence;

  /// prefix -> other readings of the word, best first.
  final Map<String, List<String>> alternatives = {};

  /// Prefix of the FIRST word of a line -> the fixes suggested for the line
  /// (their offsets refer to the text the line was read as).
  final Map<String, List<PolishSuggestion>> suggestions = {};

  /// Throws this instead of reading, when set.
  Object? error;

  /// When set, reading waits for it (to look at the progress state).
  Completer<void>? gate;

  /// Calls of [recognizeLines].
  int calls = 0;

  /// Words read, over all calls.
  int wordsRead = 0;

  /// The `previousLineText` of every call, in order.
  final List<String?> previousTexts = [];

  void Function(int done, int total)? lastProgress;

  static String keyOf(WordGroup w) => w.strokes.first.id.split('-').first;

  @override
  Future<List<LineResult>> recognizeLines(
    List<RecognizedLine> lines, {
    void Function(int done, int total)? onProgress,
    String? previousLineText,
  }) async {
    calls++;
    previousTexts.add(previousLineText);
    onProgress?.call(0, lines.length);
    final g = gate;
    if (g != null) await g.future;
    final e = error;
    if (e != null) throw e;
    final out = <LineResult>[];
    for (final line in lines) {
      final keys = [for (final w in line.words) keyOf(w)];
      out.add(lineResultOf(
        line,
        [for (final k in keys) readings[k] ?? ('?', defaultConfidence)],
        alternatives: [for (final k in keys) alternatives[k] ?? const <String>[]],
        suggestions: suggestions[keys.first] ?? const [],
      ));
      onProgress?.call(out.length, lines.length);
    }
    wordsRead += out.fold<int>(0, (n, r) => n + r.words.length);
    return out;
  }
}

/// A share service that only records what it was asked to share.
class FakeShare implements SampleShareService {
  final List<({String fileName, String json})> shared = [];

  /// What `share` answers (false: the user dismissed the sheet).
  bool answer = true;

  /// Thrown instead of sharing, when set.
  Object? error;

  @override
  Future<bool> share({required String fileName, required String json}) async {
    final e = error;
    if (e != null) throw e;
    shared.add((fileName: fileName, json: json));
    return answer;
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
  ConvertHarness._(this.tester, this.controller, this.recognizer,
      this.container, this.share, this.learner);

  final WidgetTester tester;
  final EditorController controller;
  final FakeRecognizer recognizer;
  final ProviderContainer container;
  final FakeShare share;
  final InMemoryWordLearner learner;

  static Future<ConvertHarness> open(
    WidgetTester tester, {
    List<List<Stroke>> pages = const [[]],
    Paper paper = const Paper(),
    FakeRecognizer? recognizer,
    Set<int> unreadablePages = const {},
    bool pdf = false,
    Size size = const Size(1000, 1400),
    bool autoConvert = false,
    Map<String, Object> prefsValues = const {},
    int? autoConvertDelayMs = 1000,
  }) async {
    // Auto-convert waits 1 s in these tests unless a test asks otherwise
    // (null: the app's default); a settings JSON in [prefsValues] gets the
    // same delay unless it names one.
    final values = <String, Object>{
      if (autoConvert || autoConvertDelayMs != null)
        AppSettings.prefsKey: jsonEncode({if (autoConvert) 'autoConvert': true}),
      ...prefsValues,
    };
    // Autocorrect is on in the app; these tests start with it off (fixes
    // stay suggestions) unless a settings JSON in [prefsValues] names it.
    final map = values[AppSettings.prefsKey] is String
        ? jsonDecode(values[AppSettings.prefsKey]! as String) as Map<String, dynamic>
        : <String, dynamic>{};
    map.putIfAbsent('autocorrect', () => false);
    if (autoConvertDelayMs != null) {
      map.putIfAbsent('autoConvertDelayMs', () => autoConvertDelayMs);
    }
    values[AppSettings.prefsKey] = jsonEncode(map);
    SharedPreferences.setMockInitialValues(values);
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
    final share = FakeShare();
    final learner = InMemoryWordLearner();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      sampleShareServiceProvider.overrideWithValue(share),
      userLexiconProvider.overrideWithValue(learner),
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
    final h = ConvertHarness._(tester, captured!, fake, container, share, learner);
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

  /// Turns the auto-convert setting on or off, like the toggle does.
  void setAutoConvert(bool value) => container
      .read(settingsProvider.notifier)
      .update((s) => s.copyWith(autoConvert: value));

  /// Finishes one pen stroke the way the ink tool does: the stroke is added
  /// to the page in one undo step, with the started and finished events.
  Future<void> draw(Stroke stroke, {int pageIndex = 0}) async {
    final pageId = pageIdAt(pageIndex);
    controller.strokeEvents.emitStarted(StrokeStartedEvent(
        pageId: pageId, tool: stroke.tool, startMs: 0));
    await tester.pump();
    controller.execute(
        AddStrokesCommand(pageId, [stroke], label: 'Pen stroke'));
    controller.strokeEvents.emitFinished(FinishedStroke(
        pageId: pageId, stroke: stroke, startMs: 0, endMs: 10));
    await tester.pump();
  }

  /// [draw]s every stroke, [gapMs] apart (the last gap included).
  Future<void> write(List<Stroke> strokes,
      {int gapMs = 100, int pageIndex = 0}) async {
    for (final s in strokes) {
      await draw(s, pageIndex: pageIndex);
      await tester.pump(Duration(milliseconds: gapMs));
    }
  }

  /// Taps the app bar Convert button and lets the reading finish.
  Future<void> tapConvert() async {
    await tester.tap(find.byKey(const ValueKey('convert-to-text')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}
