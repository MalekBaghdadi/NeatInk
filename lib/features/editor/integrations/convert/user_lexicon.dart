import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../recognition/htr_channel.dart';
import 'convert_providers.dart';

/// Where words the user corrected in the review sheet go, so the recogniser
/// can read them next time (names, school words...).
///
/// A thin port so tests can use the in-memory learner below.
abstract interface class WordLearner {
  /// [word] was typed by the user over a recognised word. Called once per
  /// distinct word for each applied conversion; implementations should
  /// ignore words they already know.
  void learnWord(String word);
}

/// Keeps the learned words in memory for the running app (and so for tests).
class InMemoryWordLearner implements WordLearner {
  final List<String> _words = [];

  /// The words learned so far, in the order they were first learned.
  List<String> get words => List.unmodifiable(_words);

  @override
  void learnWord(String word) {
    if (!_words.contains(word)) _words.add(word);
  }
}

/// Feeds the recogniser's personal dictionary (saved in the app's documents
/// folder), so a name corrected once is read correctly from then on.
class RecognizerWordLearner implements WordLearner {
  RecognizerWordLearner(this.recognizer);

  final HtrRecognizer recognizer;

  @override
  void learnWord(String word) => unawaited(recognizer.learn(word));
}

/// The personal dictionary the review sheet feeds.
final userLexiconProvider = Provider<WordLearner>(
    (ref) => RecognizerWordLearner(ref.watch(htrRecognizerProvider)));
