import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ctc.dart';
import 'lexicon.dart';
import 'stroke_grouping.dart';
import 'word_image.dart';

/// Asset with the model's charset (`config.json` of the Hugging Face repo).
const String htrConfigAsset = 'assets/htr/config.json';

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
    required this.timesteps,
    required this.blank,
    required this.charset,
  });

  final int classes;
  final int timesteps;
  final int blank;
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

  final List<String> alternatives;
}

/// Dart side of the Kotlin ONNX recogniser (`HtrPlugin.kt`).
///
/// Protocol on the `neatink/htr` channel:
///
/// | Dart -> Kotlin | arguments                | reply |
/// |----------------|--------------------------|-------|
/// | `recognize`    | `{images: List<Uint8List>}` | `List<Float32List>`, one per image, each `timesteps * classes` log-probabilities row-major `[t][class]` |
/// | `info`         | none                     | `{classes, timesteps, blank, charset, width, height}` |
///
/// Each image is 4096 bytes (128x32 grey, row-major, white 255).
class HtrRecognizer {
  HtrRecognizer({
    MethodChannel? channel,
    this._renderer = const UiWordImageRenderer(),
    Future<Lexicon?> Function()? lexiconLoader,
    Future<CtcCharset> Function()? charsetLoader,
    this._rescoreConfig = const RescoreConfig(),
    this.batchSize = 32,
  })  : _channel = channel ?? const MethodChannel(channelName),
        _lexiconLoader = lexiconLoader ?? _loadBundledLexicon,
        _charsetLoader = charsetLoader ?? _loadBundledCharset;

  /// The app-wide recogniser.
  static final HtrRecognizer instance = HtrRecognizer();

  static const String channelName = 'neatink/htr';

  final MethodChannel _channel;
  final WordImageRenderer _renderer;
  final Future<Lexicon?> Function() _lexiconLoader;
  final Future<CtcCharset> Function() _charsetLoader;
  final RescoreConfig _rescoreConfig;

  /// Images sent per channel call (bounds the platform message size).
  final int batchSize;

  Future<LexiconRescorer>? _rescorer;

  static Future<Lexicon?> _loadBundledLexicon() => Lexicon.loadAsset();

  static Future<CtcCharset> _loadBundledCharset() async =>
      CtcCharset.fromConfigJson(await rootBundle.loadString(htrConfigAsset));

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
    return LexiconRescorer(charset, lexicon, config: _rescoreConfig);
  }

  /// Model facts (loads the model on first use).
  Future<HtrInfo> info() async {
    final raw = await _call<Map<Object?, Object?>>('info', null);
    return HtrInfo(
      classes: (raw['classes'] as num).toInt(),
      timesteps: (raw['timesteps'] as num).toInt(),
      blank: (raw['blank'] as num).toInt(),
      charset: [for (final c in raw['charset'] as List<Object?>) c as String],
    );
  }

  /// Raw log-probabilities for 4096-byte word images. Used by the developer
  /// screen and tests; [recognizeWords] is the normal entry point.
  Future<List<CtcLogProbs>> recognizeImages(List<Uint8List> images, {int classes = 79}) async {
    final out = <CtcLogProbs>[];
    for (var start = 0; start < images.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, images.length);
      final reply = await _call<List<Object?>>('recognize', {
        'images': images.sublist(start, end),
      });
      if (reply.length != end - start) {
        throw const HtrException('protocol', 'The recognizer returned the wrong number of results.');
      }
      for (final item in reply) {
        final flat = item as List<num>;
        if (flat.isEmpty || flat.length % classes != 0) {
          throw const HtrException('protocol', 'The recognizer returned a malformed result.');
        }
        out.add(CtcLogProbs.fromFlat(flat, classes));
      }
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
    final classes = rescorer.charset.classes;
    final results = <WordResult>[];
    onProgress?.call(0, words.length);
    for (var start = 0; start < words.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, words.length);
      final images = <Uint8List>[];
      for (var i = start; i < end; i++) {
        images.add((await renderWordImage(words[i], renderer: _renderer)).pixels);
      }
      final logProbs = await recognizeImages(images, classes: classes);
      for (var i = 0; i < logProbs.length; i++) {
        final r = rescorer.rescore(logProbs[i]);
        results.add(WordResult(
          group: words[start + i],
          text: r.text,
          confidence: r.confidence,
          raw: r.raw,
          alternatives: r.alternatives,
        ));
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
