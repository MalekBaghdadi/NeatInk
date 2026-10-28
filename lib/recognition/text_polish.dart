import 'lexicon.dart';
import 'user_lexicon.dart';

/// What a [PolishSuggestion] is about.
enum PolishKind { spelling, contraction, capitalization, grammar }

/// One suggested change to a line of recognised text. Nothing is changed
/// until the user accepts it (or switches "Fix spelling automatically" on).
class PolishSuggestion {
  const PolishSuggestion({
    required this.original,
    required this.replacement,
    required this.kind,
    required this.reason,
    required this.start,
    required this.end,
  });

  /// The text to replace and what to put there.
  final String original;
  final String replacement;
  final PolishKind kind;

  /// Short, user-facing: "Spelling", "Contraction", "Capital letter" ...
  final String reason;

  /// Offsets `[start, end)` of [original] in the text the suggestion was
  /// computed on.
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is PolishSuggestion &&
      other.original == original &&
      other.replacement == replacement &&
      other.kind == kind &&
      other.reason == reason &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(original, replacement, kind, reason, start, end);

  @override
  String toString() => 'PolishSuggestion($original -> $replacement, ${kind.name}, [$start,$end))';
}

/// All tuning numbers and word lists of the [TextPolisher].
class PolishConfig {
  const PolishConfig({
    this.spelling = true,
    this.contractions = true,
    this.capitalization = true,
    this.grammar = true,
    this.minWordLength = 5,
    this.longWordLength = 7,
    this.minLogProb = -12.5,
    this.ambiguityRatio = 3.0,
    this.candidateLimit = 200,
    this.abbreviations = defaultAbbreviations,
    this.repeatableWords = defaultRepeatableWords,
  });

  /// Switch whole families of suggestions off.
  final bool spelling;
  final bool contractions;
  final bool capitalization;
  final bool grammar;

  /// Words shorter than this are never spell-checked: short words are too
  /// close to each other (`cot`/`cat`/`cut`) to tell a slip from a word, and
  /// short unlisted words are mostly jargon (`wifi` is one edit from `wife`,
  /// `todo` from `too`).
  final int minWordLength;

  /// A word of at least this many letters may be two edits away from its
  /// correction; shorter ones only one (a swap of two neighbouring letters
  /// counts as one edit).
  final int longWordLength;

  /// The correction must be at least this frequent (ln of its share of the
  /// word list; -12.5 is about the 15000th word), so an obscure word is not
  /// offered as the fix of an unknown one.
  final double minLogProb;

  /// When several corrections are equally close, the best must be this many
  /// times more frequent than the runner-up, or nothing is suggested.
  final double ambiguityRatio;

  /// Dictionary neighbours examined per word.
  final int candidateLimit;

  /// Lowercase words whose full stop does not end a sentence.
  final Set<String> abbreviations;

  static const Set<String> defaultAbbreviations = {
    'e.g', 'i.e', 'etc', 'vs', 'mr', 'mrs', 'ms', 'dr', 'prof', 'st', 'no', 'fig', 'eq', 'approx', 'cf', 'inc', 'ltd', 'jr', 'sr',
  };

  /// Function words that are never meant twice in a row (`that that` and
  /// `had had` are real English, so they are not here).
  final Set<String> repeatableWords;

  static const Set<String> defaultRepeatableWords = {
    'the', 'a', 'an', 'of', 'to', 'in', 'on', 'at', 'by', 'for', 'from', 'with', 'and', 'or', 'but', 'my', 'your', 'our', 'their',
  };
}

/// Suggests fixes for recognised text: spelling, missing apostrophes,
/// capital letters and a few safe grammar rules.
///
/// The rules are conservative on purpose: a wrong suggestion costs the user
/// attention, a wrong automatic fix costs trust. Never touched: words of the
/// personal dictionary, tokens with digits or odd punctuation (`c4t`,
/// `a@b.com`, `3.5`), and (for spelling) words in capitals and capitalised
/// words in the middle of a sentence, which are names more often than typos
/// (`Malek` is one edit from `Male`, a frequent word). A capitalised word at
/// the start of a sentence is capitalised because of the sentence, so it is
/// spell-checked, but only for a swap of two neighbouring letters
/// (`Nuerons` -> `Neurons`), the typo that cannot be a different name.
///
/// Spelling: an unknown word of 5+ letters whose best dictionary match within
/// one edit (two for 7+ letters; Damerau, a swap counts 1) starts with the
/// same letter, is frequent enough and is clearly better than the runner-up.
/// Inflected forms of listed words (`brainy`, `neuronal` are not checked
/// against `brain`, `neuron`; `walkings` is) are left alone.
class TextPolisher {
  TextPolisher(this.lexicon, {this.userLexicon, this.config = const PolishConfig()});

  /// Null disables spelling suggestions.
  final Lexicon? lexicon;

  /// Read live; its words are never touched.
  final UserLexicon? userLexicon;
  final PolishConfig config;

  static final RegExp _token = RegExp(r'\S+');
  static final RegExp _parts = RegExp(r'^([^A-Za-z0-9]*)(.*?)([^A-Za-z0-9]*)$');
  static final RegExp _plainWord = RegExp("^[A-Za-z]+(?:['\u2019][A-Za-z]+)?\$");

  /// A word that may carry a capital: letters, apostrophes and hyphens.
  static final RegExp _wordish = RegExp("^[A-Za-z][A-Za-z'\u2019-]*\$");

  /// Suggestions for [text], in text order. [sentenceStart] says the text
  /// begins a new sentence (so its first word wants a capital).
  List<PolishSuggestion> suggest(String text, {bool sentenceStart = false}) {
    final tokens = <_Token>[
      for (final m in _token.allMatches(text)) _Token.parse(m.group(0)!, m.start),
    ];
    final out = <PolishSuggestion>[];
    var startsSentence = sentenceStart;
    var skipNext = false;
    for (var k = 0; k < tokens.length; k++) {
      final t = tokens[k];
      final consumed = skipNext;
      skipNext = false;
      if (!consumed) {
        final repeat = config.grammar ? _repeat(text, tokens, k) : null;
        if (repeat != null) {
          out.add(repeat);
          skipNext = true;
        } else {
          final s = _word(tokens, k, startsSentence);
          if (s != null) out.add(s);
        }
      }
      startsSentence = _endsSentence(t);
    }
    return out;
  }

  // ---- sentences -----------------------------------------------------------

  bool _endsSentence(_Token t) {
    final trail = t.trail.replaceAll(RegExp('[)\\]}"\']+\$'), '');
    if (t.core.isEmpty && trail.isEmpty) return false;
    if (trail.endsWith('...')) return false;
    if (!trail.endsWith('.') && !trail.endsWith('!') && !trail.endsWith('?')) return false;
    if (trail.endsWith('.')) {
      final lower = t.core.toLowerCase();
      if (config.abbreviations.contains(lower)) return false;
      // An initial ("J. Smith") is no sentence end.
      if (t.core.length == 1 && RegExp('[A-Z]').hasMatch(t.core)) return false;
    }
    return true;
  }

  // ---- one word: spelling, contraction, capitals -----------------------------

  bool _isUserWord(String lower) => userLexicon?.contains(lower) ?? false;

  PolishSuggestion? _word(List<_Token> tokens, int k, bool startsSentence) {
    final t = tokens[k];
    final core = t.core;
    if (core.isEmpty || !_wordish.hasMatch(core)) return null;
    final lower = core.toLowerCase().replaceAll('\u2019', "'");
    if (_isUserWord(lower)) return null;
    final plain = _plainWord.hasMatch(core);
    var cur = core;
    PolishKind? kind;
    final reasons = <String>[];

    if (plain) {
      final contraction = config.contractions ? contractionOf(lower) : null;
      if (contraction != null) {
        cur = _caseLike(contraction, core);
        kind = PolishKind.contraction;
        reasons.add('Contraction');
      } else if (config.spelling) {
        final fix = _spelling(core, lower, startsSentence);
        if (fix != null) {
          cur = fix;
          kind = PolishKind.spelling;
          reasons.add('Spelling');
        }
      }
      if (config.grammar && _wantsAn(tokens, k, cur)) {
        cur = cur == 'A' ? 'An' : 'an';
        kind ??= PolishKind.grammar;
        reasons.add("Use 'an' here");
      }
    }

    if (config.capitalization) {
      final capitalised = _capitals(cur, t, startsSentence);
      if (capitalised != cur) {
        cur = capitalised;
        kind ??= PolishKind.capitalization;
        reasons.add(cur == 'I' || cur.startsWith("I'") ? 'Capital I' : 'Capital letter');
      }
    }
    if (cur == core || kind == null) return null;
    return PolishSuggestion(
      original: core,
      replacement: cur,
      kind: kind,
      reason: _joinReasons(reasons),
      start: t.coreStart,
      end: t.coreStart + core.length,
    );
  }

  static String _joinReasons(List<String> reasons) {
    final unique = <String>[];
    for (final r in reasons) {
      if (!unique.contains(r)) unique.add(r);
    }
    if (unique.length == 1) return unique.first;
    return '${unique.first} and ${unique.skip(1).map((r) => r.toLowerCase()).join(', ')}';
  }

  /// [word] (lowercase letters) in the case pattern of [like]: all capitals,
  /// capitalised, or lowercase. `I'm`-style words keep their capital I.
  static String _caseLike(String word, String like) {
    if (like.length >= 2 && like == like.toUpperCase()) return word.toUpperCase();
    if (word.startsWith("I'")) return word;
    if (like[0] != like[0].toLowerCase()) return word[0].toUpperCase() + word.substring(1);
    return word;
  }

  /// The capital rules applied to [word] (a plain word, possibly just
  /// corrected): a lone `i`, `i'm` & co., the first word of a sentence.
  String _capitals(String word, _Token t, bool startsSentence) {
    final w = word.replaceAll('\u2019', "'");
    if (w == 'i' && !t.trail.startsWith(')')) return 'I';
    if (RegExp(r"^i'(m|ve|ll|d)$").hasMatch(w)) return 'I${w.substring(1)}';
    if (startsSentence && word[0] != word[0].toUpperCase() && !_isUserWord(w.toLowerCase())) {
      return word[0].toUpperCase() + word.substring(1);
    }
    return word;
  }

  // ---- spelling ---------------------------------------------------------------

  bool _known(String lower) =>
      (lexicon?.contains(lower) ?? false) || _isUserWord(lower) || contractionLogProb(lower) != null;

  /// The suggested spelling of [core], or null.
  String? _spelling(String core, String lower, bool startsSentence) {
    final lex = lexicon;
    if (lex == null) return null;
    if (core.length < config.minWordLength || core.contains("'") || core.contains('\u2019')) return null;
    if (_known(lower)) return null;
    // Words in capitals and camel case are acronyms and brand names.
    if (core.length >= 2 && core == core.toUpperCase()) return null;
    if (core.substring(1) != core.substring(1).toLowerCase()) return null;
    final capitalised = core[0] != core[0].toLowerCase();
    // A capitalised word inside a sentence is a name.
    if (capitalised && !startsSentence) return null;
    if (_looksInflected(lower)) return null;

    final maxEdits = core.length >= config.longWordLength ? 2 : 1;
    final found = <(String, int, int)>[]; // word, distance, count
    for (final c in lex.candidates(lower, maxEdits: 2, limit: config.candidateLimit)) {
      if (c.word == lower || c.word[0] != lower[0] || c.word.contains("'")) continue;
      final d = damerauLevenshtein(lower, c.word);
      if (d == 0 || d > maxEdits) continue;
      if (capitalised && !(d == 1 && _isSwap(lower, c.word))) continue;
      if (lex.logProb(c.word)! < config.minLogProb) continue;
      found.add((c.word, d, c.count));
    }
    if (found.isEmpty) return null;
    found.sort((a, b) {
      final byDistance = a.$2.compareTo(b.$2);
      return byDistance != 0 ? byDistance : b.$3.compareTo(a.$3);
    });
    final best = found.first;
    if (found.length > 1) {
      final next = found[1];
      if (next.$2 == best.$2 && best.$3 < config.ambiguityRatio * next.$3) return null;
    }
    return capitalised ? best.$1[0].toUpperCase() + best.$1.substring(1) : best.$1;
  }

  /// [b] is [a] with two neighbouring letters swapped.
  static bool _isSwap(String a, String b) {
    if (a.length != b.length) return false;
    var i = 0;
    while (i < a.length && a[i] == b[i]) {
      i++;
    }
    return i + 1 < a.length && a[i] == b[i + 1] && a[i + 1] == b[i] && a.substring(i + 2) == b.substring(i + 2);
  }

  static const List<String> _suffixes = ['s', 'es', 'd', 'ed', 'ing', 'ly', 'er', 'ers', 'est', 'ness', 'ment', 'ments', 'ful', 'less', 'ion', 'ions', 'al', 'ish', 'y'];

  /// A form of a listed word (`neuronal` is not, `brainstorms` is): left alone,
  /// because the word list is far from complete in inflections and a "fix"
  /// would replace a real word.
  bool _looksInflected(String lower) {
    for (final suffix in _suffixes) {
      if (lower.length <= suffix.length + 2 || !lower.endsWith(suffix)) continue;
      final stem = lower.substring(0, lower.length - suffix.length);
      if (_known(stem) || _known('${stem}e')) return true;
      // doubled final consonant: stopped -> stop, running -> run
      if (stem.length > 2 && stem[stem.length - 1] == stem[stem.length - 2] && _known(stem.substring(0, stem.length - 1))) return true;
      // happier -> happy
      if (stem.endsWith('i') && _known('${stem.substring(0, stem.length - 1)}y')) return true;
    }
    return false;
  }

  // ---- grammar ------------------------------------------------------------------

  /// [word] (the current form of token [k]) is the article `a` and the next
  /// word starts with a vowel sound.
  bool _wantsAn(List<_Token> tokens, int k, String word) {
    if (word != 'a' && word != 'A') return false;
    final t = tokens[k];
    if (t.trail.isNotEmpty || k + 1 >= tokens.length) return false;
    final next = tokens[k + 1].core;
    if (!_plainWord.hasMatch(next) || next.length < 2) return false;
    // acronyms and initialisms ("a FBI" vs "an FBI") depend on how they are said
    if (next == next.toUpperCase()) return false;
    return _startsWithVowelSound(next.toLowerCase());
  }

  static final RegExp _silentH = RegExp(r'^(hour|honest|honor|honour|heir)');

  /// Words that start with a vowel LETTER but a consonant sound (`a university`,
  /// `a one-way`, `a European`, `a user`).
  static final RegExp _consonantSound = RegExp(r'^(one(?!r)|once|uni[tvoqfcsl]|us[eu]|uti|uten|uter|euro|eu[lpg]|ewe|ubiq|ukul|uran)');

  static bool _startsWithVowelSound(String w) {
    if (_silentH.hasMatch(w)) return true;
    if ('aeiou'.contains(w[0])) return !_consonantSound.hasMatch(w);
    return false;
  }

  /// `the the` -> `the`.
  PolishSuggestion? _repeat(String text, List<_Token> tokens, int k) {
    if (k + 1 >= tokens.length) return null;
    final a = tokens[k];
    final b = tokens[k + 1];
    if (a.core.isEmpty || a.trail.isNotEmpty || b.lead.isNotEmpty || a.lead.isNotEmpty) return null;
    final lower = a.core.toLowerCase();
    if (lower != b.core.toLowerCase() || !config.repeatableWords.contains(lower)) return null;
    if (_isUserWord(lower)) return null;
    final start = a.coreStart;
    final end = b.coreStart + b.core.length;
    return PolishSuggestion(
      original: text.substring(start, end),
      replacement: a.core,
      kind: PolishKind.grammar,
      reason: 'Repeated word',
      start: start,
      end: end,
    );
  }
}

class _Token {
  _Token(this.lead, this.core, this.trail, this.coreStart);

  factory _Token.parse(String s, int offset) {
    final m = TextPolisher._parts.firstMatch(s)!;
    final lead = m.group(1)!;
    return _Token(lead, m.group(2)!, m.group(3)!, offset + lead.length);
  }

  final String lead;
  final String core;
  final String trail;

  /// Offset of [core] in the text.
  final int coreStart;
}

/// Applies [suggestions] to [text] by their offsets, right to left, so earlier
/// offsets stay valid. Suggestions that overlap an earlier one (by start) or
/// whose [PolishSuggestion.original] is no longer at its offsets (the text
/// changed since) are skipped.
String applyPolish(String text, Iterable<PolishSuggestion> suggestions) {
  final sorted = suggestions.toList()..sort((a, b) => a.start.compareTo(b.start));
  final chosen = <PolishSuggestion>[];
  var lastEnd = -1;
  for (final s in sorted) {
    if (s.start < lastEnd || s.start < 0 || s.end > text.length || s.end < s.start) continue;
    if (text.substring(s.start, s.end) != s.original) continue;
    chosen.add(s);
    lastEnd = s.end;
  }
  var out = text;
  for (final s in chosen.reversed) {
    out = out.replaceRange(s.start, s.end, s.replacement);
  }
  return out;
}
