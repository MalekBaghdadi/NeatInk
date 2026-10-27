import '../../../../ink/stroke.dart';
import '../../../../recognition/htr_channel.dart';
import '../../../../recognition/stroke_grouping.dart';
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
  }) : include = !lowConfidence;

  /// Unique within the plan (`<pageId>/<index>`).
  final String id;
  final String pageId;

  /// The grouped strokes (geometry for the layout).
  final RecognizedLine line;

  /// What the recogniser read for each word (same order as `line.words`).
  final List<WordResult> words;

  /// The text to type: the recogniser's reading until the user edits it.
  String text;

  /// Mean confidence of the line's words (0..1).
  final double confidence;

  /// The most used stroke colour of the line (ARGB).
  final int dominantColor;

  /// Ids of every stroke of the line's words: removed when the line is
  /// converted.
  final Set<String> strokeIds;

  /// Below [ConvertConfig.lowConfidenceThreshold] (or a word could not be
  /// read at all): starts unchecked, shown with a "Not sure" badge.
  final bool lowConfidence;

  /// Whether the line will be converted. Starts as `!lowConfidence`.
  bool include;

  /// True when the line will actually be converted (ticked, has text).
  bool get willConvert => include && text.trim().isNotEmpty;
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
  });

  final String pageId;
  final int pageIndex;
  final List<Stroke> strokes;
}

/// Groups [strokes] (ignoring highlighter strokes and shapes) into lines and
/// words, without recognising anything yet.
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

/// Builds the plan line for [line] from the words the recogniser read.
PlannedLine plannedLineFrom({
  required String id,
  required String pageId,
  required RecognizedLine line,
  required List<WordResult> words,
  double threshold = ConvertConfig.lowConfidenceThreshold,
}) {
  final texts = <String>[];
  var sum = 0.0;
  var unreadable = false;
  for (final w in words) {
    final t = w.text.trim();
    if (t.isEmpty) {
      unreadable = true;
    } else {
      texts.add(t);
      sum += w.confidence.clamp(0.0, 1.0);
    }
  }
  final confidence = words.isEmpty ? 0.0 : sum / words.length;
  return PlannedLine(
    id: id,
    pageId: pageId,
    line: line,
    words: words,
    text: texts.join(' '),
    confidence: confidence,
    dominantColor: dominantColorOf(line.strokes),
    strokeIds: {for (final s in line.strokes) s.id},
    lowConfidence: unreadable || texts.isEmpty || confidence < threshold,
  );
}

/// Reads the handwriting of [pages] with [recognizer]: groups every page
/// into lines and words, recognises all words in chunks (so [cancel] is
/// honoured between chunks) and returns one plan per page, in input order.
///
/// [onProgress] reports `(wordsDone, wordsTotal)` over all pages. Pages
/// without pen strokes get an empty plan. Throws [HtrException] when the
/// recogniser fails and [ConvertCancelled] when cancelled.
Future<List<PagePlan>> recognizePages(
  List<PageStrokes> pages,
  HtrRecognizer recognizer, {
  void Function(int done, int total)? onProgress,
  ConvertCancelToken? cancel,
}) async {
  final grouped = [for (final p in pages) groupPageStrokes(p.strokes)];
  final allWords = <WordGroup>[
    for (final lines in grouped)
      for (final line in lines) ...line.words,
  ];
  final total = allWords.length;
  final results = <WordResult>[];
  onProgress?.call(0, total);
  for (var start = 0; start < total; start += ConvertConfig.chunkWords) {
    if (cancel?.isCancelled ?? false) throw const ConvertCancelled();
    final end = (start + ConvertConfig.chunkWords).clamp(0, total);
    final chunk = allWords.sublist(start, end);
    final read = await recognizer.recognizeWords(
      chunk,
      onProgress: (done, _) => onProgress?.call(start + done, total),
    );
    if (cancel?.isCancelled ?? false) throw const ConvertCancelled();
    if (read.length != chunk.length) {
      throw const HtrException('protocol', 'The recognizer returned the wrong number of results.');
    }
    results.addAll(read);
    onProgress?.call(results.length, total);
  }

  final plans = <PagePlan>[];
  var next = 0;
  for (var p = 0; p < pages.length; p++) {
    final lines = <PlannedLine>[];
    for (var i = 0; i < grouped[p].length; i++) {
      final line = grouped[p][i];
      final words = results.sublist(next, next + line.words.length);
      next += line.words.length;
      lines.add(plannedLineFrom(
        id: '${pages[p].pageId}/$i',
        pageId: pages[p].pageId,
        line: line,
        words: words,
      ));
    }
    plans.add(PagePlan(
        pageId: pages[p].pageId, pageIndex: pages[p].pageIndex, lines: lines));
  }
  return plans;
}
