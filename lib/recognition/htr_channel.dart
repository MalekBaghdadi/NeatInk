import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../beautify/resample.dart';
import '../ink/ink_rect.dart';
import '../ink/stroke.dart';
import 'ctc.dart';
import 'lexicon.dart';
import 'line_decoder.dart';
import 'rescorer.dart';
import 'stroke_grouping.dart';
import 'text_polish.dart';
import 'user_lexicon.dart';
import 'word_image.dart';

/// Asset with the model's class table (blank, characters, space).
const String htrCharsetAsset = 'assets/htr/charset.json';

/// Widest image the platform side accepts (pixels). Whole lines are up to
/// this wide; keep it equal to `MAX_WIDTH` in `HtrPlugin.kt` and to
/// [LineImageConfig.maxWidth].
const int htrMaxImageWidth = 2400;

/// How lines are drawn for the recogniser: THE one place to change it.
///
/// `snapDots` moves each i-dot over its stem in the picture only (never on
/// the page): this writer puts the dot 3 to 8 points left of the stem, which
/// made the model read "are in" as "aren". On the owner's sample page it
/// lowered the character error from 10.2% to 7.5% and was never worse.
const LineImageConfig recognitionLineImageConfig = LineImageConfig(snapDots: true);

/// A failed recognition call. [userMessage] is safe to show.
class HtrException implements Exception {
  const HtrException(this.code, this.message);

  /// The platform error code (`model_missing`, `out_of_memory`, `htr_failed`
  /// ...) or one of `unavailable`, `protocol`.
  final String code;
  final String message;

  String get userMessage => switch (code) {
        'model_missing' || 'model_unreadable' =>
          'The handwriting model could not be loaded.',
        'out_of_memory' => 'Not enough memory to read the handwriting.',
        'unavailable' => 'Handwriting recognition is not available on this device.',
        _ => 'Reading the handwriting failed.',
      };

  @override
  String toString() => 'HtrException($code): $message';
}

/// Model facts reported by the plugin's `info` call.
class HtrInfo {
  const HtrInfo({
    required this.classes,
    required this.blank,
    this.charsetSize = 0,
    this.inputHeight = wordImageHeight,
    this.minWidth = wordImageMinWidth,
    this.maxWidth = htrMaxImageWidth,
    this.timesteps = 0,
    this.charset = const [],
  });

  final int classes;
  final int blank;

  /// Number of entries of the plugin's character table (equals [classes]).
  final int charsetSize;
  final int inputHeight;
  final int minWidth;
  final int maxWidth;

  /// The number of timesteps depends on the image width, so the plugin no
  /// longer reports it (0).
  final int timesteps;

  /// Not reported any more (the Dart side loads `charset.json` itself).
  final List<String> charset;
}

/// One recognised word.
class WordResult {
  const WordResult({
    required this.group,
    required this.text,
    required this.confidence,
    required this.raw,
    required this.alternatives,
  });

  /// The strokes the text was read from.
  final WordGroup group;

  /// Final text (dictionary-corrected, with capitalisation and punctuation).
  final String text;

  /// 0..1; low values mean the reading is a guess.
  final double confidence;

  /// The model's own best-path output before the dictionary was applied.
  final String raw;

  /// Up to five other readings, best first (see [RescoredWord.alternatives]).
  final List<String> alternatives;
}

/// One recognised line of handwriting, read as a whole.
///
/// The model reads the whole line in one picture and the words come from its
/// own spaces ([LineDecoder]); [words] are those words with the strokes found
/// under each of them. EVERY stroke of the line is in some word's group, so
/// the layout and the removal of the ink can rely on [words].
class LineResult {
  const LineResult({
    required this.line,
    required this.words,
    required this.text,
    required this.raw,
    required this.confidence,
    this.suggestions = const [],
    this.images = const [],
  });

  /// The line with [words] as its word groups (`copyWith(words: ...)`); the
  /// ink, baseline and size are those of the line that was read.
  final RecognizedLine line;

  /// The recognised words, left to right. Never empty: a line the model
  /// read nothing from is one word with empty text and all the ink.
  final List<WordResult> words;

  /// The words' texts joined by single spaces; what the decoder read, before
  /// any polishing.
  final String text;

  /// The model's own best-path reading of the line (no language layer).
  final String raw;

  /// 0..1: how sure the reading of the line is ([LineReading.confidence],
  /// the least sure chunk for a line that was cut into several images).
  final double confidence;

  /// Spelling and grammar fixes suggested for [text]; offsets refer to it.
  final List<PolishSuggestion> suggestions;

  /// The pictures the model was given for the line (one, more only for very
  /// wide lines), exactly as sent.
  final List<LineImage> images;
}

/// Dart side of the Kotlin ONNX recogniser (`HtrPlugin.kt`).
///
/// Protocol on the `neatink/htr` channel:
///
/// | Dart -> Kotlin | arguments | reply |
/// |----------------|-----------|-------|
/// | `recognize`    | `{images: [{width, height, pixels}]}` | one `{timesteps, classes, probs}` map per image |
/// | `info`         | none      | `{classes, blank, charsetSize, inputHeight, minWidth, maxWidth, inputName}` |
///
/// An image is `height` = 48 rows of `width` (16..2400) grey bytes, row-major,
/// white paper = 255 (a [WordImage] or [LineImage]). `probs` is a
/// `Float32List` of `timesteps * classes` softmax **probabilities**,
/// row-major `[t][class]`; class 0 is the CTC blank. The plugin runs one image
/// per model call.
///
/// Whole lines are the normal input ([recognizeLines]): one picture per line,
/// read by the [LineDecoder], which needs the space class unfolded.
/// [recognizeWords] reads single words with the older [LexiconRescorer].
class HtrRecognizer {
  HtrRecognizer({
    MethodChannel? channel,
    this._renderer = const UiWordImageRenderer(),
    Future<Lexicon?> Function()? lexiconLoader,
    Future<CtcCharset> Function()? charsetLoader,
    this._rescoreConfig = const RescoreConfig(),
    this._lineImageConfig = recognitionLineImageConfig,
    this._lineDecodeConfig = const LineDecodeConfig(),
    this._polishConfig = const PolishConfig(),
    UserLexicon? userLexicon,
    this.batchSize = 8,
  })  : _channel = channel ?? const MethodChannel(channelName),
        _lexiconLoader = lexiconLoader ?? _loadBundledLexicon,
        _charsetLoader = charsetLoader ?? _loadBundledCharset,
        _userLexicon = userLexicon ?? UserLexicon();

  /// The app-wide recogniser, with the personal dictionary saved in the
  /// application documents directory.
  static final HtrRecognizer instance =
      HtrRecognizer(userLexicon: UserLexicon(store: JsonFileUserLexiconStore()));

  static const String channelName = 'neatink/htr';

  final MethodChannel _channel;
  final WordImageRenderer _renderer;
  final Future<Lexicon?> Function() _lexiconLoader;
  final Future<CtcCharset> Function() _charsetLoader;
  final RescoreConfig _rescoreConfig;
  final LineImageConfig _lineImageConfig;
  final LineDecodeConfig _lineDecodeConfig;
  final PolishConfig _polishConfig;
  final UserLexicon _userLexicon;

  /// Images sent per channel call (bounds the platform message size) and
  /// lines read between two reports of progress.
  final int batchSize;

  Future<LexiconRescorer>? _rescorer;
  Future<LineDecoder>? _decoder;
  Future<Lexicon?>? _lexiconLoading;
  TextPolisher? _polisher;
  Lexicon? _lexicon;

  /// The personal dictionary (names and words the user taught the app).
  UserLexicon get userLexicon => _userLexicon;

  static Future<Lexicon?> _loadBundledLexicon() => Lexicon.loadAsset();

  static Future<CtcCharset> _loadBundledCharset() async =>
      CtcCharset.fromJson(await rootBundle.loadString(htrCharsetAsset));

  Future<LexiconRescorer> _loadRescorer() async {
    final pending = _rescorer ??= _buildRescorer();
    try {
      return await pending;
    } catch (_) {
      _rescorer = null;
      rethrow;
    }
  }

  /// The word list and the personal dictionary, loaded once. A missing word
  /// list is no error: the model's own reading is still useful.
  Future<Lexicon?> _loadLexicon() {
    return _lexiconLoading ??= () async {
      Lexicon? lexicon;
      try {
        lexicon = await _lexiconLoader();
      } catch (e) {
        debugPrint('NeatInk: word list unavailable: $e');
      }
      _lexicon = lexicon;
      await _userLexicon.load(); // never throws
      return lexicon;
    }();
  }

  Future<LexiconRescorer> _buildRescorer() async {
    final CtcCharset charset;
    try {
      charset = await _charsetLoader();
    } catch (e) {
      throw HtrException('model_unreadable', 'Cannot read the model configuration: $e');
    }
    final lexicon = await _loadLexicon();
    return LexiconRescorer(
      charset,
      lexicon,
      config: _rescoreConfig,
      userLexicon: _userLexicon,
    );
  }

  /// The line decoder, built once with the same character table, word list
  /// and personal dictionary as the rescorer.
  Future<LineDecoder> _loadDecoder() async {
    final pending = _decoder ??= _buildDecoder();
    try {
      return await pending;
    } catch (_) {
      _decoder = null;
      rethrow;
    }
  }

  Future<LineDecoder> _buildDecoder() async {
    final rescorer = await _loadRescorer();
    return LineDecoder(
      rescorer.charset,
      _lexicon,
      userLexicon: _userLexicon,
      config: _lineDecodeConfig,
    );
  }

  /// Suggests spelling and grammar fixes for recognised text (built once, with
  /// the word list and the personal dictionary; needs no model).
  Future<TextPolisher> polisher() async {
    final lexicon = await _loadLexicon();
    return _polisher ??= TextPolisher(
      lexicon,
      userLexicon: _userLexicon,
      config: _polishConfig,
    );
  }

  /// Teaches the recogniser the spelling of [correctedWord] (the text the
  /// user typed in place of a recognised word; several words are fine).
  /// Words the English list already knows are not stored. Returns how many
  /// entries were added or changed; the dictionary is saved before the
  /// future completes.
  Future<int> learn(String correctedWord) async {
    try {
      await _loadRescorer();
    } on HtrException {
      // No model: the personal dictionary still works on its own.
    }
    final lexicon = _lexicon;
    final added = _userLexicon.learn(
      correctedWord,
      isKnownWord: lexicon?.contains,
    );
    await _userLexicon.flush();
    return added;
  }

  /// Model facts (loads the model on first use).
  Future<HtrInfo> info() async {
    final raw = await _call<Map<Object?, Object?>>('info', null);
    int number(String key, int fallback) => (raw[key] as num?)?.toInt() ?? fallback;
    return HtrInfo(
      classes: number('classes', 0),
      blank: number('blank', 0),
      charsetSize: number('charsetSize', 0),
      inputHeight: number('inputHeight', wordImageHeight),
      minWidth: number('minWidth', wordImageMinWidth),
      maxWidth: number('maxWidth', htrMaxImageWidth),
    );
  }

  /// Probabilities of every character at every timestep for each of
  /// [images], turned into log-probabilities (the space class is folded into
  /// the blank, see [CtcLogProbs.fromProbabilities]). Used by the developer
  /// screen and tests; [recognizeWords] is the normal entry point.
  Future<List<CtcLogProbs>> recognizeImages(List<WordImage> images) async {
    final rescorer = await _loadRescorer();
    final out = <CtcLogProbs>[];
    for (var start = 0; start < images.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, images.length);
      out.addAll(await _recognizeBatch(images.sublist(start, end), rescorer.charset));
    }
    return out;
  }

  /// Sends [batch] to the platform and returns each image's log-probabilities.
  /// Word images fold the space class into the blank (a word holds no space);
  /// line images keep it ([foldSpace] false) because the spaces are what
  /// separates the words.
  Future<List<CtcLogProbs>> _recognizeBatch(
    List<WordImage> batch,
    CtcCharset charset, {
    bool foldSpace = true,
  }) async {
    final reply = await _call<List<Object?>>('recognize', {
      'images': [
        for (final img in batch)
          {'width': img.width, 'height': img.height, 'pixels': img.pixels},
      ],
    });
    if (reply.length != batch.length) {
      throw const HtrException('protocol', 'The recognizer returned the wrong number of results.');
    }
    final out = <CtcLogProbs>[];
    for (final item in reply) {
      if (item is! Map) {
        throw const HtrException('protocol', 'The recognizer returned a malformed result.');
      }
      final probs = item['probs'];
      final classes = (item['classes'] as num?)?.toInt();
      final steps = (item['timesteps'] as num?)?.toInt();
      if (probs is! List<num> ||
          classes != charset.classes ||
          steps == null ||
          steps <= 0 ||
          probs.length != steps * classes!) {
        throw const HtrException('protocol', 'The recognizer returned a malformed result.');
      }
      out.add(CtcLogProbs.fromProbabilities(
        probs,
        classes,
        blank: charset.blank,
        foldIntoBlank: foldSpace ? charset.space : null,
      ));
    }
    return out;
  }

  /// Renders, recognises and dictionary-corrects [words]; one result per
  /// word, in the same order. [onProgress] reports words finished so far.
  Future<List<WordResult>> recognizeWords(
    List<WordGroup> words, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (words.isEmpty) return const [];
    final rescorer = await _loadRescorer();
    final results = <WordResult>[];
    onProgress?.call(0, words.length);
    // The language layer runs on this isolate; give the UI a turn whenever
    // it has been busy for a frame or so.
    final slice = Stopwatch()..start();
    for (var start = 0; start < words.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, words.length);
      final images = <WordImage>[];
      for (var i = start; i < end; i++) {
        images.add(await renderWordImage(words[i], renderer: _renderer));
      }
      final logProbs = await _recognizeBatch(images, rescorer.charset);
      for (var i = 0; i < logProbs.length; i++) {
        final r = rescorer.rescore(logProbs[i]);
        results.add(WordResult(
          group: words[start + i],
          text: r.text,
          confidence: r.confidence,
          raw: r.raw,
          alternatives: r.alternatives,
        ));
        if (slice.elapsedMilliseconds > 12) {
          await Future<void>.delayed(Duration.zero);
          slice.reset();
        }
      }
      onProgress?.call(results.length, words.length);
    }
    return results;
  }

  /// Reads whole [lines]: one picture per line (several only for very wide
  /// ones), decoded by the [LineDecoder]; one result per line, in order.
  ///
  /// The words are the model's own (it emits a space class), and each word's
  /// strokes are found from the frames it spans, so the words of the result
  /// come with ink groups that together hold EVERY stroke of the line. A
  /// word whose frames hold no ink (a stray mark the model read in a gap) is
  /// merged into the word before it.
  ///
  /// [onProgress] reports lines finished so far. [previousLineText] is the
  /// text of the line above the first of [lines] on the same page, used to
  /// decide whether the first line starts a sentence for the suggestions;
  /// null means [lines] begin a page, so it does.
  Future<List<LineResult>> recognizeLines(
    List<RecognizedLine> lines, {
    void Function(int done, int total)? onProgress,
    String? previousLineText,
  }) async {
    if (lines.isEmpty) return const [];
    final decoder = await _loadDecoder();
    final textPolisher = await polisher();
    final results = <LineResult>[];
    onProgress?.call(0, lines.length);
    // Decoding and polishing run on this isolate; give the UI a turn whenever
    // it has been busy for a frame or so.
    final slice = Stopwatch()..start();
    var previous = previousLineText;
    for (var start = 0; start < lines.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, lines.length);
      final group = lines.sublist(start, end);
      final rendered = <List<LineImage>>[];
      for (final line in group) {
        rendered.add(await renderLineImages(line, renderer: _renderer, config: _lineImageConfig));
      }
      final flat = [for (final images in rendered) ...images];
      final logProbs = <CtcLogProbs>[];
      for (var s = 0; s < flat.length; s += batchSize) {
        final e = (s + batchSize).clamp(0, flat.length);
        logProbs.addAll(await _recognizeBatch(flat.sublist(s, e), decoder.charset, foldSpace: false));
      }
      var at = 0;
      for (var i = 0; i < group.length; i++) {
        final images = rendered[i];
        final readings = [
          for (var k = 0; k < images.length; k++) decoder.decode(logProbs[at + k]),
        ];
        at += images.length;
        final result = _lineResult(
          group[i],
          images,
          readings,
          textPolisher,
          sentenceStart: previous == null || _endsSentence(previous),
        );
        results.add(result);
        if (result.text.isNotEmpty) previous = result.text;
        if (slice.elapsedMilliseconds > 12) {
          await Future<void>.delayed(Duration.zero);
          slice.reset();
        }
      }
      onProgress?.call(results.length, lines.length);
    }
    return results;
  }

  /// Puts the readings of a line's [images] together: word groups from the
  /// frames of each word, ghosts merged, no stroke lost, suggestions made.
  LineResult _lineResult(
    RecognizedLine line,
    List<LineImage> images,
    List<LineReading> readings,
    TextPolisher textPolisher, {
    required bool sentenceStart,
  }) {
    final drafts = <_WordDraft>[];
    // Words without ink before the first word with ink.
    final leading = <DecodedWord>[];
    final raws = <String>[];
    var confidence = 1.0;
    for (var k = 0; k < images.length; k++) {
      final image = images[k];
      final reading = readings[k];
      if (reading.words.isEmpty) continue;
      confidence = math.min(confidence, reading.confidence);
      if (reading.raw.isNotEmpty) raws.add(reading.raw);
      // Frames are spread evenly over the picture.
      final steps = math.max(reading.timesteps, 1);
      final spans = [
        for (final w in reading.words)
          (start: w.startFrame * image.width / steps, end: w.endFrame * image.width / steps),
      ];
      final groups = assignStrokesToSpans(line, image, spans, config: _lineImageConfig);
      for (var j = 0; j < reading.words.length; j++) {
        final word = reading.words[j];
        final group = groups[j];
        if (group == null) {
          if (drafts.isNotEmpty) {
            drafts.last.append(word);
          } else {
            leading.add(word);
          }
        } else {
          final draft = _WordDraft(word, group);
          for (final ghost in leading.reversed) {
            draft.prepend(ghost);
          }
          leading.clear();
          drafts.add(draft);
        }
      }
    }

    if (drafts.isEmpty) {
      // Nothing was read (or nothing to attach it to): all the ink is one
      // unreadable word.
      final group = _groupOf(line, line.inkStrokes);
      return LineResult(
        line: line.copyWith(words: [group]),
        words: [
          WordResult(group: group, text: '', confidence: 0, raw: '', alternatives: const []),
        ],
        text: '',
        raw: raws.join(' '),
        confidence: 0,
        images: images,
      );
    }
    final groups = [for (final d in drafts) d.group];
    _attachMissingStrokes(line, groups);
    final words = [
      for (var i = 0; i < drafts.length; i++)
        WordResult(
          group: groups[i],
          text: drafts[i].text,
          confidence: drafts[i].confidence,
          raw: drafts[i].raw,
          alternatives: drafts[i].alternatives,
        ),
    ];
    final text = words.map((w) => w.text).join(' ');
    return LineResult(
      line: line.copyWith(words: groups),
      words: words,
      text: text,
      raw: raws.join(' '),
      confidence: confidence,
      suggestions: textPolisher.suggest(text, sentenceStart: sentenceStart),
      images: images,
    );
  }

  /// Gives every stroke of [line] that no word group has (a stroke the images
  /// did not carry) to the group nearest to it. [groups] is changed in place.
  static void _attachMissingStrokes(RecognizedLine line, List<WordGroup> groups) {
    final covered = <String>{
      for (final g in groups)
        for (final s in g.strokes) s.id,
    };
    for (final stroke in line.inkStrokes) {
      if (covered.contains(stroke.id)) continue;
      final box = finiteBounds(stroke.points);
      var best = 0;
      if (box != null) {
        var bestDistance = double.infinity;
        for (var i = 0; i < groups.length; i++) {
          final d = _distance(box, groups[i].bounds);
          if (d < bestDistance) {
            bestDistance = d;
            best = i;
          }
        }
      }
      final g = groups[best];
      groups[best] = WordGroup(
        strokes: [...g.strokes, stroke],
        bounds: box == null ? g.bounds : g.bounds.union(box),
        baselineSlope: g.baselineSlope,
        xHeight: g.xHeight,
      );
      covered.add(stroke.id);
    }
  }

  /// Squared distance between two boxes (0 when they overlap).
  static double _distance(InkRect a, InkRect b) {
    final dx = math.max(0.0, math.max(a.left - b.right, b.left - a.right));
    final dy = math.max(0.0, math.max(a.top - b.bottom, b.top - a.bottom));
    return dx * dx + dy * dy;
  }

  /// One word group holding [strokes] (the line's baseline and size).
  static WordGroup _groupOf(RecognizedLine line, List<Stroke> strokes) {
    InkRect? bounds;
    for (final s in strokes) {
      final b = finiteBounds(s.points);
      if (b != null) bounds = bounds == null ? b : bounds.union(b);
    }
    return WordGroup(
      strokes: List.of(strokes),
      bounds: bounds ?? InkRect(line.left, line.baselineY - line.xHeight, line.right, line.baselineY),
      baselineSlope: line.baselineSlope,
      xHeight: line.xHeight,
    );
  }

  static final RegExp _sentenceEnd = RegExp(r'''[.!?]['")\]}’”]*$''');

  /// Whether the next line starts a new sentence after [text].
  static bool _endsSentence(String text) {
    final t = text.trimRight();
    return _sentenceEnd.hasMatch(t) && !t.endsWith('...');
  }

  Future<T> _call<T>(String method, Object? args) async {
    try {
      final result = await _channel.invokeMethod<T>(method, args);
      if (result == null) {
        throw HtrException('protocol', 'The recognizer returned no result for $method.');
      }
      return result;
    } on PlatformException catch (e) {
      throw HtrException(e.code, e.message ?? e.code);
    } on MissingPluginException {
      throw const HtrException('unavailable', 'The handwriting recognizer is not installed.');
    }
  }
}

/// A recognised word being put together: the decoder's word with its ink,
/// plus the text of any ghost words (read in gaps with no ink) merged into it.
class _WordDraft {
  _WordDraft(DecodedWord word, this.group)
      : text = word.text,
        raw = word.raw,
        confidence = word.confidence,
        alternatives = word.alternatives;

  String text;
  String raw;
  double confidence;
  final List<String> alternatives;
  final WordGroup group;

  /// Punctuation that sticks to the word before it.
  static final RegExp _closing = RegExp(r'^[.,;:!?%)\]}"' "'" r'\u2019\u201D]+$');

  /// Punctuation that sticks to the word after it.
  static final RegExp _opening = RegExp(r'^[(\["' "'" r'\u2018\u201C]+$');

  void append(DecodedWord ghost) {
    text = _closing.hasMatch(ghost.text) ? '$text${ghost.text}' : '$text ${ghost.text}';
    raw = raw.isEmpty ? ghost.raw : (ghost.raw.isEmpty ? raw : '$raw ${ghost.raw}');
    confidence = math.min(confidence, ghost.confidence);
  }

  void prepend(DecodedWord ghost) {
    text = _opening.hasMatch(ghost.text) ? '${ghost.text}$text' : '${ghost.text} $text';
    raw = raw.isEmpty ? ghost.raw : (ghost.raw.isEmpty ? raw : '${ghost.raw} $raw');
    confidence = math.min(confidence, ghost.confidence);
  }
}
