import 'text_polish.dart';

/// How a word of typed text is marked (v1.8.0, like a word processor).
enum SpellMarkKind {
  /// Not a known word: red wavy underline.
  unknown,

  /// A rare real word right next to a far more frequent one (`wong` for
  /// `wrong`, see [TextPolisher.suspectsFor]): amber wavy underline.
  suspect,
}

/// A marked word: its characters `text[start, end)`.
class SpellMark {
  const SpellMark(this.start, this.end, this.kind);

  final int start;
  final int end;
  final SpellMarkKind kind;

  @override
  bool operator ==(Object other) =>
      other is SpellMark && other.start == start && other.end == end && other.kind == kind;

  @override
  int get hashCode => Object.hash(start, end, kind);

  @override
  String toString() => 'SpellMark($start, $end, $kind)';
}

/// Finds the words of typed text that may be misspelt, for the underline in
/// the editor, with the word list of autocorrect ([TextPolisher]). Pure Dart
/// and synchronous, so the page painter can ask on every paint: results are
/// cached per word. Skipped: numbers and anything with a digit or symbol
/// inside, words in capitals (acronyms) and in camel case.
class SpellChecker {
  SpellChecker(this.polisher);

  final TextPolisher polisher;

  // Word (with whether it starts a sentence) -> its mark, without the
  // personal dictionary, which can grow while the checker lives and is
  // asked live.
  final Map<String, SpellMarkKind?> _cache = {};
  static const int _cacheLimit = 5000;

  // Words the user chose to leave alone (lowercase), for as long as the
  // checker lives.
  final Set<String> _ignored = {};

  /// Stops marking [word] (any capitalisation).
  void ignore(String word) => _ignored.add(word.toLowerCase());

  static final RegExp _token = RegExp(r'\S+');
  static final RegExp _parts = RegExp(r'^([^A-Za-z0-9]*)(.*?)([^A-Za-z0-9]*)$');
  static final RegExp _wordish = RegExp("^[A-Za-z]+(?:['\u2019-][A-Za-z]+)*\$");
  static final RegExp _sentenceEnd = RegExp('[.!?][)\\]}"\'\u201d\u2019]*\$');

  /// The marked words of [text], in text order.
  List<SpellMark> marksFor(String text) {
    final out = <SpellMark>[];
    var startsSentence = true;
    for (final m in _token.allMatches(text)) {
      final token = m.group(0)!;
      final parts = _parts.firstMatch(token)!;
      final lead = parts.group(1)!, core = parts.group(2)!, trail = parts.group(3)!;
      final kind = kindOf(core, startsSentence: startsSentence);
      if (kind != null) {
        final start = m.start + lead.length;
        out.add(SpellMark(start, start + core.length, kind));
      }
      if (core.isNotEmpty || trail.isNotEmpty) startsSentence = _sentenceEnd.hasMatch(trail);
    }
    return out;
  }

  /// How [word] (no surrounding punctuation) is marked, or null.
  SpellMarkKind? kindOf(String word, {bool startsSentence = false}) {
    if (!_wordish.hasMatch(word)) return null;
    if (word.length >= 2 && word == word.toUpperCase()) return null;
    if (word.substring(1) != word.substring(1).toLowerCase()) return null;
    final key = '${startsSentence ? '^' : ''}$word';
    final SpellMarkKind? kind;
    if (_cache.containsKey(key)) {
      kind = _cache[key];
    } else {
      if (_cache.length >= _cacheLimit) _cache.clear();
      kind = _cache[key] = _check(word, startsSentence);
    }
    if (kind != null && (polisher.isUserWord(word) || _ignored.contains(word.toLowerCase()))) return null;
    return kind;
  }

  SpellMarkKind? _check(String word, bool startsSentence) {
    if (!polisher.isKnownSpelling(word)) return SpellMarkKind.unknown;
    if (polisher.suspectsFor(word, startsSentence: startsSentence).isNotEmpty) return SpellMarkKind.suspect;
    return null;
  }

  /// What [word] may have been meant as, best first (at most three).
  List<String> suggestionsFor(String word, SpellMarkKind kind, {bool startsSentence = false}) =>
      kind == SpellMarkKind.unknown
          ? polisher.spellingSuggestions(word)
          : polisher.suspectsFor(word, startsSentence: startsSentence);

  /// Whether the word at [start] of [text] starts a sentence.
  static bool startsSentenceAt(String text, int start) {
    final before = text.substring(0, start).trimRight();
    if (before.isEmpty) return true;
    final last = _token.allMatches(before).lastOrNull?.group(0) ?? '';
    return _sentenceEnd.hasMatch(last);
  }
}
