import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../document/font_kind.dart';
import '../../../../recognition/htr_channel.dart';
import '../../../../recognition/text_polish.dart';
import '../../../../recognition/word_image.dart';
import '../../../settings/convert_style_prefs.dart';
import '../../editor_controller.dart';
import '../../tools/selection.dart';
import 'convert_apply.dart';
import 'convert_build.dart';
import 'convert_config.dart';
import 'convert_corrections.dart';
import 'convert_layout.dart';
import 'convert_plan.dart';
import 'sample_export.dart';
import 'user_lexicon.dart';

/// Where the convert sheet is.
enum ConvertPhase {
  /// Reading the handwriting (progress bar, Cancel).
  reading,

  /// Recognised lines to review.
  review,

  /// There is no handwriting in scope: "Nothing to convert here yet".
  empty,

  /// Recognition failed; [ConvertSession.errorMessage] says why.
  failed,
}

/// The state behind the convert sheet: which strokes are in scope, what was
/// read, the user's corrections and look, and the final apply.
///
/// Scope is the lasso [selection]'s pen strokes when there is one, else the
/// pen strokes of the page in view, or of every page once [allPages] is set.
/// Recognised pages are cached, so switching the scope only reads what is
/// new.
class ConvertSession extends ChangeNotifier {
  ConvertSession({
    required this.controller,
    required this.recognizer,
    this.selection,
    Uuid? uuid,
    this._metrics = const FlutterTextMetrics(),
    ConvertStylePrefs initialStyle = const ConvertStylePrefs(),
    this.learner,
    this.onStyleChosen,
    this.appVersion = 'unknown',
    this.autoFix = false,
    DateTime Function()? clock,
  })  : _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now {
    _load(initialStyle);
  }

  final EditorController controller;
  final HtrRecognizer recognizer;

  /// The lasso selection the sheet was opened for, or null.
  final Selection? selection;
  final Uuid _uuid;
  final ConvertTextMetrics _metrics;
  final DateTime Function() _clock;

  /// Told about the words the user corrected, when a conversion is applied
  /// (the personal dictionary). Null: nothing is learned.
  final WordLearner? learner;

  /// Called with the look used, when a conversion is applied, so it can be
  /// remembered (and used by auto-convert).
  final void Function(ConvertStylePrefs style)? onStyleChosen;

  /// Written into shared sample files.
  final String appVersion;

  /// The setting "Autocorrect": the spelling and grammar fixes
  /// the recogniser suggests are applied to the text as it is read (each can
  /// be taken back in the sheet). Off: they are only offered.
  final bool autoFix;

  ConvertPhase _phase = ConvertPhase.reading;
  double _progress = 0;
  String? _errorMessage;
  bool _allPages = false;
  bool _closed = false;
  int _run = 0;
  ConvertCancelToken? _token;
  final Map<String, PagePlan> _cache = {};

  FontKind _font = FontKind.sans;
  bool _bold = false;
  bool _italic = false;
  double? _fixedSize;
  int? _colorOverride;
  bool _evenSize = false;
  bool _joinLines = false;

  ConvertPhase get phase => _phase;

  /// 0..1 while [phase] is [ConvertPhase.reading].
  double get progress => _progress;

  /// A message safe to show when [phase] is [ConvertPhase.failed].
  String? get errorMessage => _errorMessage;

  /// True when the sheet may offer the "This page / All pages" switch.
  bool get canChooseScope => selection == null;
  bool get allPages => _allPages;

  FontKind get font => _font;
  bool get bold => _bold;
  bool get italic => _italic;

  /// Fixed size in points, or null for auto.
  double? get fixedSize => _fixedSize;
  bool get autoSize => !_evenSize && _fixedSize == null;
  bool get evenSize => _evenSize;
  bool get joinLines => _joinLines;

  /// Colour for every line, or null to keep the ink colour.
  int? get colorOverride => _colorOverride;

  ConvertStyle get style => ConvertStyle(
        font: _font,
        bold: _bold,
        italic: _italic,
        fixedSize: _fixedSize,
        colorOverride: _colorOverride,
        evenSize: _evenSize,
        joinLines: _joinLines,
      );

  // ---------------------------------------------------------------------------
  // Scope and reading

  /// The pages in scope as (id, index), in page order.
  List<(String, int)> _scopePages() {
    final pages = controller.doc.meta.pages;
    final sel = selection;
    if (sel != null) {
      final index = pages.indexWhere((p) => p.id == sel.pageId);
      return index < 0 ? const [] : [(sel.pageId, index)];
    }
    final indices = _allPages
        ? List.generate(pages.length, (i) => i)
        : [controller.currentPageIndex];
    return [
      for (final i in indices)
        if (i >= 0 && i < pages.length && controller.isPageEditable(pages[i].id))
          (pages[i].id, i),
    ];
  }

  List<PageStrokes> _pagesInScope() {
    final doc = controller.doc;
    final sel = selection;
    return [
      for (final (id, index) in _scopePages())
        PageStrokes(
          pageId: id,
          pageIndex: index,
          strokes: sel != null
              ? sel.strokesOn(doc.page(id))
              : List.of(doc.page(id).strokes),
        ),
    ];
  }

  /// Starts (or restarts) reading the handwriting in scope.
  Future<void> start() async {
    final run = ++_run;
    _token?.cancel();
    final token = _token = ConvertCancelToken();
    final scope = _pagesInScope();
    final missing = [
      for (final p in scope)
        if (!_cache.containsKey(p.pageId)) p,
    ];
    if (missing.isNotEmpty) {
      _phase = ConvertPhase.reading;
      _progress = 0;
      _errorMessage = null;
      _notify();
      try {
        final plans = await recognizePages(
          missing,
          recognizer,
          cancel: token,
          autoFix: autoFix,
          onProgress: (done, total) {
            if (run != _run || _closed) return;
            _progress = total == 0 ? 1 : (done / total).clamp(0.0, 1.0);
            _notify();
          },
        );
        for (final plan in plans) {
          _cache[plan.pageId] = plan;
        }
      } on ConvertCancelled {
        return;
      } on HtrException catch (e) {
        if (run != _run || _closed) return;
        _fail(e.userMessage);
        return;
      } catch (e) {
        debugPrint('NeatInk: convert failed: $e');
        if (run != _run || _closed) return;
        _fail('Reading the handwriting failed.');
        return;
      }
    }
    if (run != _run || _closed) return;
    _phase = plans.isEmpty ? ConvertPhase.empty : ConvertPhase.review;
    _notify();
  }

  void _fail(String message) {
    _phase = ConvertPhase.failed;
    _errorMessage = message;
    _notify();
  }

  /// Tries again after a failure.
  Future<void> retry() => start();

  /// Switches between the page in view and every page (only without a
  /// selection). Pages already read are not read again.
  Future<void> setAllPages(bool value) {
    if (!canChooseScope || value == _allPages) return Future.value();
    _allPages = value;
    return start();
  }

  /// Stops reading and ignores whatever is still in flight. The session
  /// stays usable for reading its state, but never notifies again.
  void cancel() {
    _closed = true;
    _run++;
    _token?.cancel();
  }

  /// The recognised pages in scope that have lines, in page order.
  List<PagePlan> get plans {
    final out = <PagePlan>[];
    for (final (id, _) in _scopePages()) {
      final plan = _cache[id];
      if (plan != null && !plan.isEmpty) out.add(plan);
    }
    return out;
  }

  Iterable<PlannedLine> get allLines => plans.expand((p) => p.lines);

  /// Lines that will be turned into text.
  int get includedCount => allLines.where((l) => l.willConvert).length;

  /// Lines that will stay handwriting.
  int get stayCount => allLines.length - includedCount;

  // ---------------------------------------------------------------------------
  // The user's choices

  void setInclude(PlannedLine line, bool value) {
    if (line.include == value) return;
    line.include = value;
    _notify();
  }

  void setText(PlannedLine line, String text) {
    if (line.text == text) return;
    line.text = text;
    _notify();
  }

  void setFont(FontKind value) {
    _font = value;
    _notify();
  }

  void setBold(bool value) {
    _bold = value;
    _notify();
  }

  void setItalic(bool value) {
    _italic = value;
    _notify();
  }

  /// A size in points, clamped to the slider range; null selects auto
  /// (match my handwriting).
  void setFixedSize(double? value) {
    _fixedSize = value?.clamp(
        ConvertConfig.minFixedSize, ConvertConfig.maxFixedSize).toDouble();
    _evenSize = false;
    _notify();
  }

  /// The whole look at once (the style controls).
  void setStyle(ConvertStylePrefs prefs) {
    _load(prefs);
    _notify();
  }

  void _load(ConvertStylePrefs prefs) {
    final style = ConvertStyle.fromPrefs(prefs);
    _font = style.font;
    _bold = style.bold;
    _italic = style.italic;
    _fixedSize = style.fixedSize?.clamp(
        ConvertConfig.minFixedSize, ConvertConfig.maxFixedSize).toDouble();
    _colorOverride = style.colorOverride;
    _evenSize = style.evenSize;
    _joinLines = style.joinLines;
  }

  void setColorOverride(int? value) {
    _colorOverride = value;
    _notify();
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Apply

  /// The changes the current choices would make, one per page.
  List<PageConversion> buildConversions() {
    final out = <PageConversion>[];
    for (final plan in plans) {
      final meta = controller.doc.pageMeta(plan.pageId);
      if (meta == null || !controller.isPageEditable(plan.pageId)) continue;
      final laid = layoutPlannedPage(
        plan: plan,
        meta: meta,
        style: style,
        metrics: _metrics,
        uuid: _uuid,
        convert: (l) => l.willConvert,
      );
      if (laid.isEmpty) continue;
      final converted = {for (final l in laid) ...l.members};
      out.add(PageConversion(
        pageId: plan.pageId,
        strokeIds: {
          for (final l in plan.lines)
            if (converted.contains(l.id)) ...l.strokeIds,
        },
        items: [for (final l in laid) l.item],
      ));
    }
    return out;
  }

  /// Replaces the ink of the ticked lines with typed text boxes, as one undo
  /// step. Returns null when nothing was converted.
  ConvertOutcome? apply() {
    if (_phase != ConvertPhase.review) return null;
    final toLearn = wordsToLearn();
    final outcome = applyConversion(controller, buildConversions());
    if (outcome != null) {
      for (final w in toLearn) {
        learner?.learnWord(w);
      }
      onStyleChosen?.call(style.toPrefs());
    }
    return outcome;
  }

  // ---------------------------------------------------------------------------
  // Corrections

  /// Replaces word [wordIndex] of [line] by [replacement] in the line's text
  /// (an alternative reading picked in "what the recognizer saw"). When the
  /// text no longer has one word per recognised word, the word is found by
  /// its recognised text instead; if it can't be found nothing changes.
  void replaceWord(PlannedLine line, int wordIndex, String replacement) {
    if (wordIndex < 0 || wordIndex >= line.words.length) return;
    final tokens = splitWords(line.text);
    int at;
    if (tokens.length == line.words.length) {
      at = wordIndex;
    } else {
      at = tokens.indexOf(line.words[wordIndex].text.trim());
      if (at < 0) return;
    }
    tokens[at] = replacement;
    setText(line, tokens.join(' '));
  }

  /// Words the user corrected in the lines that will be converted: what the
  /// personal dictionary should learn (see [correctedWords]).
  ///
  /// Corrections are measured against the recognised text WITH the polish
  /// fixes that are in it ([PlannedLine.polishedText]), and a word that is the
  /// replacement of a polish suggestion is never taught: taking a spelling
  /// fix is not a correction of what the recogniser read.
  List<String> wordsToLearn() {
    final out = <String>{};
    for (final line in allLines) {
      if (!line.willConvert) continue;
      final polish = {
        for (final s in [...line.suggestions, ...line.autoApplied, ...line.accepted])
          stripPunctuation(s.replacement),
      };
      for (final w in correctedWords(
        recognised: splitWords(line.polishedText),
        finalText: line.text,
      )) {
        if (!polish.contains(w)) out.add(w);
      }
    }
    return out.toList();
  }

  /// Applies the suggested fix [s] to the text of [line] (see
  /// [PlannedLine.acceptSuggestion]) and tells the sheet. False when the
  /// word is no longer in the text.
  bool acceptSuggestion(PlannedLine line, PolishSuggestion s) {
    final done = line.acceptSuggestion(s);
    if (done) _notify();
    return done;
  }

  /// Takes back the automatic fix [s] of [line] (see
  /// [PlannedLine.revertAutoFix]) and tells the sheet.
  bool revertAutoFix(PlannedLine line, PolishSuggestion s) {
    final done = line.revertAutoFix(s);
    if (done) _notify();
    return done;
  }

  // ---------------------------------------------------------------------------
  // Samples

  /// The JSON of every recognised line in scope with the text as it stands
  /// in the review sheet, for sharing handwriting samples (see
  /// [buildSamplesJson]). The pictures are the ones the recogniser was given
  /// ([PlannedLine.images]); a line without any is drawn with [renderer].
  Future<String> buildSamples([WordImageRenderer? renderer]) async {
    final lines = <SampleLineInput>[];
    for (final plan in plans) {
      for (final line in plan.lines) {
        var images = line.images;
        if (images.isEmpty && renderer != null) {
          images = await renderLineImages(line.line,
              renderer: renderer, config: recognitionLineImageConfig);
        }
        lines.add(SampleLineInput(
            line: line, pageIndex: plan.pageIndex, images: images));
      }
    }
    return encodeSamplesJson(buildSamplesJson(
      appVersion: appVersion,
      createdAt: _clock(),
      lines: lines,
    ));
  }

  /// The file name for samples made now.
  String get sampleFileName => samplesFileName(_clock());
}
