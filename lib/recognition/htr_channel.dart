import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ctc.dart';
import 'lexicon.dart';
import 'rescorer.dart';
import 'stroke_grouping.dart';
import 'user_lexicon.dart';
import 'word_image.dart';

/// Asset with the model's class table (blank, characters, space).
const String htrCharsetAsset = 'assets/htr/charset.json';

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
    this.maxWidth = wordImageMaxWidth,
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

/// Dart side of the Kotlin ONNX recogniser (`HtrPlugin.kt`).
///
/// Protocol on the `neatink/htr` channel:
///
/// | Dart -> Kotlin | arguments | reply |
/// |----------------|-----------|-------|
/// | `recognize`    | `{images: [{width, height, pixels}]}` | one `{timesteps, classes, probs}` map per image |
/// | `info`         | none      | `{classes, blank, charsetSize, inputHeight, minWidth, maxWidth, inputName}` |
///
/// An image is `height` = 48 rows of `width` (16..800) grey bytes, row-major,
/// white paper = 255 (a [WordImage]). `probs` is a `Float32List` of
/// `timesteps * classes` softmax **probabilities**, row-major `[t][class]`;
/// class 0 is the CTC blank. The plugin runs one image per model call.
class HtrRecognizer {
  HtrRecognizer({
    MethodChannel? channel,
    this._renderer = const UiWordImageRenderer(),
    Future<Lexicon?> Function()? lexiconLoader,
    Future<CtcCharset> Function()? charsetLoader,
    this._rescoreConfig = const RescoreConfig(),
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
  final UserLexicon _userLexicon;

  /// Images sent per channel call (bounds the platform message size and
  /// sets how often progress is reported).
  final int batchSize;

  Future<LexiconRescorer>? _rescorer;
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

  Future<LexiconRescorer> _buildRescorer() async {
    final CtcCharset charset;
    try {
      charset = await _charsetLoader();
    } catch (e) {
      throw HtrException('model_unreadable', 'Cannot read the model configuration: $e');
    }
    Lexicon? lexicon;
    try {
      lexicon = await _lexiconLoader();
    } catch (e) {
      // Without a word list the greedy reading is still useful.
      debugPrint('NeatInk: word list unavailable: $e');
    }
    _lexicon = lexicon;
    await _userLexicon.load(); // never throws
    return LexiconRescorer(
      charset,
      lexicon,
      config: _rescoreConfig,
      userLexicon: _userLexicon,
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
      maxWidth: number('maxWidth', wordImageMaxWidth),
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

  Future<List<CtcLogProbs>> _recognizeBatch(List<WordImage> batch, CtcCharset charset) async {
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
        foldIntoBlank: charset.space,
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
