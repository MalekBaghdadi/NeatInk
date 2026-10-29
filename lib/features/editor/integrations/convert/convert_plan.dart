import '../../../../document/page_items.dart' show TextCorrection, TextItem;
import '../../../../ink/stroke.dart';
import '../../../../recognition/htr_channel.dart';
import '../../../../recognition/stroke_grouping.dart';
import '../../../../recognition/text_polish.dart';
import '../../../../recognition/word_image.dart';
import 'convert_config.dart';

/// Asked to stop: raised by [recognizePages] when its [ConvertCancelToken]
/// was cancelled.
class ConvertCancelled implements Exception {
  const ConvertCancelled();

  @override
  String toString() => 'ConvertCancelled';
}

/// Lets the Cancel button stop a recognition run between chunks.
class ConvertCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// One recognised line of handwriting, with what the review sheet edits
/// ([text], [include]) and what the layout and apply steps need.
class PlannedLine {
  PlannedLine({
    required this.id,
    required this.pageId,
    required this.line,
    required this.words,
    required this.text,
    required this.confidence,
    required this.dominantColor,
    required this.strokeIds,
    required this.lowConfidence,
    String? recognizedText,
    List<PolishSuggestion> suggestions = const [],
    List<PolishSuggestion> autoApplied = const [],
    this.images = const [],
  })  : recognizedText = recognizedText ?? text,
        suggestions = List.of(suggestions),
        autoApplied = List.of(autoApplied),
        include = !lowConfidence;

  /// Unique within the plan (`<pageId>/<index>`).
  final String id;
  final String pageId;

  /// The grouped strokes (geometry for the layout). Its [RecognizedLine.words]
  /// are the word groups the recogniser found; its
  /// [RecognizedLine.inkStrokes] hold every pen stroke of the line.
  final RecognizedLine line;

  /// What the recogniser read for each word, left to right (the groups of
  /// `line.words`).
  final List<WordResult> words;

  /// The text to type: the recogniser's reading, with the automatic fixes
  /// when "Autocorrect" is on, until the user edits it.
  String text;

  /// The text the recogniser read, before any polishing. The offsets of
  /// [suggestions] and [autoApplied] refer to it.
  final String recognizedText;

  /// Spelling and grammar fixes still offered for this line, in text order.
  /// Mutable: [acceptSuggestion] takes one out, [revertAutoFix] puts one back.
  final List<PolishSuggestion> suggestions;

  /// Fixes that were applied to [text] automatically (the setting "Fix
  /// spelling automatically"); each can be taken back with [revertAutoFix].
  final List<PolishSuggestion> autoApplied;

  /// The pictures the model was given for this line, exactly as sent.
  final List<LineImage> images;

  /// Confidence of the line (0..1): that of its least sure word.
  final double confidence;

  /// The most used stroke colour of the line (ARGB).
  final int dominantColor;

  /// Ids of every stroke of the line: removed when the line is converted.
  final Set<String> strokeIds;

  /// Below [ConvertConfig.lowConfidenceThreshold] (or nothing could be read):
  /// starts unchecked, shown with a "Not sure" badge.
  final bool lowConfidence;

  /// Whether the line will be converted. Starts as `!lowConfidence`.
  bool include;

  /// True when the line will actually be converted (ticked, has text).
  bool get willConvert => include && text.trim().isNotEmpty;

  // Fixes the user accepted (they are in [text] now). Not part of the
  // contract of [suggestions]: kept so offsets stay exact and so accepting a
  // fix is never mistaken for correcting the recogniser.
  final List<PolishSuggestion> _accepted = [];

  /// Fixes the user accepted with [acceptSuggestion] and did not take back.
  List<PolishSuggestion> get accepted => List.unmodifiable(_accepted);

  /// [recognizedText] with the fixes that are in [text] (accepted and
  /// automatic): what the line says when the user changed nothing else.
  /// Corrections to the recogniser are what differs from THIS, so taking a
  /// polish suggestion never teaches the personal dictionary.
  String get polishedText =>
      applyPolish(recognizedText, [...autoApplied, ..._accepted]);

  /// Applies [s] to [text]: its [PolishSuggestion.original] is replaced by the
  /// replacement (at the position the suggestion was made for while the text
  /// is as polished so far, else at the first whole-word occurrence) and the
  /// suggestion moves out of [suggestions]. False, and nothing changes, when
  /// the word is no longer in [text].
  bool acceptSuggestion(PolishSuggestion s) {
    final at = _find(s.original, _currentStart(s));
    if (at == null) return false;
    text = text.replaceRange(at, at + s.original.length, s.replacement);
    suggestions.remove(s);
    _accepted.add(s);
    return true;
  }

  /// Takes back [s], a fix that was applied automatically (or accepted):
  /// its replacement in [text] goes back to the original and the suggestion
  /// returns to [suggestions]. False, and nothing changes, when the
  /// replacement is no longer in [text].
  bool revertAutoFix(PolishSuggestion s) {
    final at = _find(s.replacement, _currentStart(s));
    if (at == null) return false;
    text = text.replaceRange(at, at + s.replacement.length, s.original);
    autoApplied.remove(s);
    _accepted.remove(s);
    if (!suggestions.contains(s)) {
      final i = suggestions.indexWhere((o) => o.start > s.start);
      suggestions.insert(i < 0 ? suggestions.length : i, s);
    }
    return true;
  }

  /// Where [s] sits in [text] when only polish fixes changed it: its offset in
  /// [recognizedText] moved by the fixes applied before it.
  int _currentStart(PolishSuggestion s) {
    var at = s.start;
    for (final a in [...autoApplied, ..._accepted]) {
      if (a.start < s.start) at += a.replacement.length - a.original.length;
    }
    return at;
  }

  /// [needle] at [expected] when it is there as a whole word, else its first
  /// whole-word occurrence in [text], else null.
  int? _find(String needle, int expected) {
    if (needle.isEmpty) return null;
    if (expected >= 0 &&
        text.startsWith(needle, expected) &&
        _isWholeWord(text, expected, needle.length)) {
      return expected;
    }
    var from = 0;
    while (true) {
      final i = text.indexOf(needle, from);
      if (i < 0) return null;
      if (_isWholeWord(text, i, needle.length)) return i;
      from = i + 1;
    }
  }

  static final RegExp _wordChar = RegExp("[\\p{L}\\p{N}'’]", unicode: true);

  static bool _isWord(String char) => _wordChar.hasMatch(char);

  /// The [length] characters at [at] are not part of a longer word: a word
  /// character next to the match on a side where the match itself ends in a
  /// word character makes it part of one.
  static bool _isWholeWord(String t, int at, int length) {
    final first = t[at], last = t[at + length - 1];
    if (at > 0 && _isWord(first) && _isWord(t[at - 1])) return false;
    if (at + length < t.length && _isWord(last) && _isWord(t[at + length])) {
      return false;
    }
    return true;
  }
}

/// The recognised lines of one page, top to bottom.
class PagePlan {
  PagePlan({required this.pageId, required this.pageIndex, required this.lines});

  final String pageId;
  final int pageIndex;
  final List<PlannedLine> lines;

  bool get isEmpty => lines.isEmpty;
}

/// The pen strokes of one page to read.
class PageStrokes {
  const PageStrokes({
    required this.pageId,
    required this.pageIndex,
    required this.strokes,
    this.texts = const [],
  });

  final String pageId;
  final int pageIndex;
  final List<Stroke> strokes;

  /// Typed text already on the page: the box before the first line (in
  /// reading order) says whether that line starts a sentence.
  final List<TextItem> texts;
}

/// The text of the box in [texts] that comes right before a line of
/// handwriting starting at ([left], [baselineY]) with [xHeight] in reading
/// order: the nearest box ending above it, or one on the same line to its
/// left. Null when there is none (the line starts the page).
///
/// Auto-convert reads only the new writing, so without this every pass
/// started a sentence: autocorrect gave the first word a capital, and a
/// line carrying on the sentence above ("... so I can / test my app") no
/// longer looked like it, so it became a box of its own (v1.8.0).
String? textBeforeLine(Iterable<TextItem> texts, {required double left, required double baselineY, required double xHeight}) {
  TextItem? above, beside;
  for (final t in texts) {
    if (t.text.trim().isEmpty) continue;
    final bottom = t.y + t.height;
    if (bottom <= baselineY - 0.5 * xHeight) {
      if (above == null ||
          bottom > above.y + above.height + 0.5 * xHeight ||
          ((bottom - (above.y + above.height)).abs() <= 0.5 * xHeight && t.x > above.x)) {
        above = t;
      }
    } else if (t.y < baselineY && t.x < left) {
      // On this line and starting left of the writing: it comes first, even
      // when the box reaches past the pen (a typed box is often as wide as
      // the page; v1.9.0, the half sentence Mariam carried on got a capital).
      if (beside == null || t.x > beside.x) beside = t;
    }
  }
  return (beside ?? above)?.text;
}

/// Groups [strokes] (ignoring highlighter strokes and shapes) into lines,
/// without recognising anything yet. Every pen stroke ends up in a line's
/// [RecognizedLine.inkStrokes].
List<RecognizedLine> groupPageStrokes(List<Stroke> strokes) =>
    groupStrokes(strokes);

/// The most used colour among the strokes of [line], weighted by how many
/// points each stroke has; ties go to the colour met first.
int dominantColorOf(Iterable<Stroke> strokes) {
  final weight = <int, int>{};
  for (final s in strokes) {
    weight[s.color] = (weight[s.color] ?? 0) + s.points.length;
  }
  var best = 0xFF1E1E1E;
  var bestWeight = -1;
  weight.forEach((color, w) {
    if (w > bestWeight) {
      best = color;
      bestWeight = w;
    }
  });
  return best;
}

/// The suggestions of [all] that Autocorrect applies by itself to [text]:
/// those marked [PolishSuggestion.auto], by the rules of [applyPolish] (by
/// position, none overlapping an earlier one, each still matching the text),
/// in text order.
List<PolishSuggestion> applicableSuggestions(
    String text, Iterable<PolishSuggestion> all) {
  final sorted = all.toList()..sort((a, b) => a.start.compareTo(b.start));
  final out = <PolishSuggestion>[];
  var lastEnd = -1;
  for (final s in sorted) {
    if (!s.auto) continue;
    if (s.start < lastEnd || s.start < 0 || s.end > text.length || s.end < s.start) {
      continue;
    }
    if (text.substring(s.start, s.end) != s.original) continue;
    out.add(s);
    lastEnd = s.end;
  }
  return out;
}

/// Where the automatic fixes [applied] ended up in [text], the line's final
/// text (it may have been edited or tidied since): each replacement found as
/// a whole word, left to right, after the previous one. Fixes that are only
/// a capital letter are not marked (they are never worth taking back), and
/// fixes no longer in the text are skipped.
List<TextCorrection> locateCorrections(
    String text, Iterable<PolishSuggestion> applied) {
  final sorted = [
    for (final s in applied)
      if (s.kind != PolishKind.capitalization && s.replacement.isNotEmpty) s,
  ]..sort((a, b) => a.start.compareTo(b.start));
  final out = <TextCorrection>[];
  var from = 0;
  for (final s in sorted) {
    var i = text.indexOf(s.replacement, from);
    while (i >= 0) {
      final c = TextCorrection(
          start: i, original: s.original, replacement: s.replacement);
      if (c.holdsIn(text)) {
        out.add(c);
        from = c.end;
        break;
      }
      i = text.indexOf(s.replacement, i + 1);
    }
  }
  return out;
}

/// Builds the plan line for a line the recogniser read.
///
/// With [autoFix] the polish suggestions that can be applied are applied to
/// the text right away and listed in [PlannedLine.autoApplied]; otherwise they
/// stay pending in [PlannedLine.suggestions] and the text is the reading as it
/// is.
PlannedLine plannedLineFrom({
  required String id,
  required String pageId,
  required LineResult result,
  bool autoFix = false,
  double threshold = ConvertConfig.lowConfidenceThreshold,
}) {
  final recognized = result.text;
  final applied = autoFix
      ? applicableSuggestions(recognized, result.suggestions)
      : const <PolishSuggestion>[];
  final pending = [
    for (final s in result.suggestions)
      if (!applied.contains(s)) s,
  ];
  final strokes = result.line.inkStrokes;
  final unreadable = recognized.trim().isEmpty ||
      result.words.any((w) => w.text.trim().isEmpty);
  final confidence = result.confidence.isNaN
      ? 0.0
      : result.confidence.clamp(0.0, 1.0).toDouble();
  return PlannedLine(
    id: id,
    pageId: pageId,
    line: result.line,
    words: result.words,
    text: applied.isEmpty ? recognized : applyPolish(recognized, applied),
    recognizedText: recognized,
    suggestions: pending,
    autoApplied: applied,
    images: result.images,
    confidence: confidence,
    dominantColor: dominantColorOf(strokes),
    strokeIds: {for (final s in strokes) s.id},
    lowConfidence: unreadable || confidence < threshold,
  );
}

/// Reads the handwriting of [pages] with [recognizer]: groups every page
/// into lines, recognises the lines in chunks of [ConvertConfig.chunkLines]
/// (so [cancel] is honoured between chunks) and returns one plan per page, in
/// input order.
///
/// [onProgress] reports `(linesDone, linesTotal)` over all pages. Pages
/// without pen strokes get an empty plan. With [autoFix] the spelling and
/// grammar fixes the recogniser suggests are applied to the text (and can be
/// taken back, see [PlannedLine.revertAutoFix]). Throws [HtrException] when
/// the recogniser fails and [ConvertCancelled] when cancelled.
Future<List<PagePlan>> recognizePages(
  List<PageStrokes> pages,
  HtrRecognizer recognizer, {
  void Function(int done, int total)? onProgress,
  ConvertCancelToken? cancel,
  bool autoFix = false,
}) async {
  final grouped = [for (final p in pages) groupPageStrokes(p.strokes)];
  final total = grouped.fold<int>(0, (n, lines) => n + lines.length);
  var done = 0;
  onProgress?.call(0, total);
  final plans = <PagePlan>[];
  for (var p = 0; p < pages.length; p++) {
    final lines = grouped[p];
    final planned = <PlannedLine>[];
    // The text of the line above the chunk, so the suggestions know whether
    // the chunk's first line starts a sentence (null: it starts the page).
    String? above = lines.isEmpty || pages[p].texts.isEmpty
        ? null
        : textBeforeLine(pages[p].texts,
            left: lines.first.left,
            baselineY: lines.first.baselineAt(lines.first.left),
            xHeight: lines.first.xHeight);
    for (var start = 0; start < lines.length; start += ConvertConfig.chunkLines) {
      if (cancel?.isCancelled ?? false) throw const ConvertCancelled();
      final end = (start + ConvertConfig.chunkLines).clamp(0, lines.length);
      final chunk = lines.sublist(start, end);
      final base = done;
      final read = await recognizer.recognizeLines(
        chunk,
        previousLineText: above,
        onProgress: (d, _) => onProgress?.call(base + d, total),
      );
      if (cancel?.isCancelled ?? false) throw const ConvertCancelled();
      if (read.length != chunk.length) {
        throw const HtrException('protocol', 'The recognizer returned the wrong number of results.');
      }
      for (var i = 0; i < read.length; i++) {
        planned.add(plannedLineFrom(
          id: '${pages[p].pageId}/${start + i}',
          pageId: pages[p].pageId,
          result: read[i],
          autoFix: autoFix,
        ));
        if (read[i].text.isNotEmpty) above = read[i].text;
      }
      done += read.length;
      onProgress?.call(done, total);
    }
    plans.add(PagePlan(
        pageId: pages[p].pageId, pageIndex: pages[p].pageIndex, lines: planned));
  }
  return plans;
}
