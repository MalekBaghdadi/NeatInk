import 'dart:math' as math;

import 'lexicon.dart';
import 'user_lexicon.dart';

/// What a [PolishSuggestion] is about.
enum PolishKind { spelling, contraction, capitalization, grammar }

/// One suggested change to a line of recognised text. Nothing is changed
/// until the user accepts it (or "Autocorrect" is on).
class PolishSuggestion {
  const PolishSuggestion({
    required this.original,
    required this.replacement,
    required this.kind,
    required this.reason,
    required this.start,
    required this.end,
    this.auto = true,
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

  /// Whether "Autocorrect" may apply it by itself. False for a spelling fix
  /// of a word the recogniser was unsure of (see
  /// [PolishConfig.sureWordConfidence]): it stays a suggestion.
  final bool auto;

  /// This suggestion, not to be applied by itself.
  PolishSuggestion get offered => PolishSuggestion(
      original: original, replacement: replacement, kind: kind, reason: reason, start: start, end: end, auto: false);

  @override
  bool operator ==(Object other) =>
      other is PolishSuggestion &&
      other.original == original &&
      other.replacement == replacement &&
      other.kind == kind &&
      other.reason == reason &&
      other.start == start &&
      other.end == end &&
      other.auto == auto;

  @override
  int get hashCode => Object.hash(original, replacement, kind, reason, start, end, auto);

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
    this.minWordLength = 4,
    this.channelWeight = 5.0,
    this.firstLetterPenalty = 0.25,
    this.closeMatchCost = 1.0,
    this.closeMatchMinRank = 45000,
    this.minLogProb = -12.5,
    this.ambiguityMargin = 1.0,
    this.splitCost = 0.3,
    this.splitMinRank = 25000,
    this.realWordMinRank = 15000,
    this.realWordMaxTargetRank = 3000,
    this.realWordMinRatio = 25,
    this.realWordMaxCost = 1.0,
    this.userWordRank = 5000,
    this.candidateLimit = 200,
    this.sureWordConfidence = 0.65,
    this.abbreviations = defaultAbbreviations,
    this.repeatableWords = defaultRepeatableWords,
  });

  /// Switch whole families of suggestions off.
  final bool spelling;
  final bool contractions;
  final bool capitalization;
  final bool grammar;

  /// Words shorter than this are never spell-checked: short words are too
  /// close to each other (`cot`/`cat`/`cut`) to tell a slip from a word. A
  /// word of this length only gets a look-alike letter fixed
  /// ([maxCostFor]).
  final int minWordLength;

  /// How much one unit of [handwritingDistance] counts against a
  /// correction, in ln-probability: each correction of an unknown word is
  /// scored `ln P(word) - channelWeight * distance` (a noisy channel), so a
  /// correction one plain edit further away must be e^5 ~ 150 times more
  /// frequent to win. Tuned on the owner's page and the word list: 3 let
  /// `numerous` beat `neurons` for `nuerons`.
  final double channelWeight;

  /// Added to the distance when the correction starts with another letter
  /// (first letters are written carefully, so they are rarely misread).
  final double firstLetterPenalty;

  /// A correction at most this far ([handwritingDistance]) may be any word
  /// of the list down to rank [closeMatchMinRank] (`hamberger` ->
  /// `hamburger`, rank 22784); a farther one must be as frequent as
  /// [minLogProb].
  final double closeMatchCost;
  final int closeMatchMinRank;

  /// ln of the share of the word list a far correction needs (-12.5 is about
  /// the 15000th word), so an obscure word is not offered as the fix of an
  /// unknown one.
  final double minLogProb;

  /// The best correction must score this much (ln) above the runner-up, or
  /// nothing is suggested: `onvert` is as close to `overt` as to `convert`.
  final double ambiguityMargin;

  /// What a missing space costs, in [handwritingDistance] units: `itworked`
  /// -> `it worked` when both words are at least as frequent as rank
  /// [splitMinRank] and the split scores better than any correction.
  final double splitCost;
  final int splitMinRank;

  /// A listed word can be a misread one too: `wrong` read without its `r`
  /// is `wong`, a surname of the list (v1.8.0, the owner's paragraph); such
  /// words are only marked for the user, never changed ([suspectsFor]). A
  /// word below rank [realWordMinRank] (rarer than about the 15000th word),
  /// not in the study vocabulary or My words and not capitalised inside a
  /// sentence (a name), is changed to a word of rank [realWordMaxTargetRank]
  /// or better that is [realWordMinRatio] times more frequent and at most
  /// [realWordMaxCost] away ([handwritingDistance]). `lobe` (rank 9260)
  /// stays a lobe.
  final int realWordMinRank;
  final int realWordMaxTargetRank;
  final double realWordMinRatio;
  final double realWordMaxCost;

  /// The prior a word of My words gets as part of a split glued word, as if
  /// it were this frequent.
  final int userWordRank;

  /// The farthest correction ([handwritingDistance]) allowed for a word of
  /// [length] letters: one look-alike letter for 4, about one edit for 5-6,
  /// two for 7-9, a little more for longer words.
  double maxCostFor(int length) => length <= 3
      ? 0
      : length == 4
          ? 0.6
          : length <= 6
              ? 1.2
              : length <= 9
                  ? 2.0
                  : 2.6;

  /// Dictionary neighbours examined per word.
  final int candidateLimit;

  /// Autocorrect fixes the spelling of a recognised word by itself only when
  /// the recogniser read it with at least this confidence (the writer's own
  /// slip, written clearly: `nuerons`), or when the fix is one of the
  /// readings the decoder weighed against the picture. A word it was unsure
  /// of is a misreading more often than a misspelling, and the text-only
  /// guess turned Mariam's `systa` into `syria` and `visud` into `virus`; the
  /// fix stays a suggestion and the word gets the spelling underline.
  final double sureWordConfidence;

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
/// Spelling (v1.6.0, a noisy channel): an unknown word of 4+ letters gets
/// the dictionary word that best explains it, scored by how frequent the
/// word is minus how far it is in handwriting terms ([handwritingDistance]:
/// `joming` -> `joining` costs one look-alike `m` for `in`), or is split
/// into two words when a space was lost (`itworked` -> `it worked`). It
/// must be clearly the best explanation ([PolishConfig.ambiguityMargin]),
/// so `onvert` stays as it is rather than becoming `overt`. Inflected forms
/// of listed words (`brainy`, `neuronal` are not checked against `brain`,
/// `neuron`; `walkings` is) are left alone. `I a` becomes `I am`.
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
      if (config.grammar && _iA(tokens, k, cur)) {
        cur = 'am';
        kind ??= PolishKind.grammar;
        reasons.add("Use 'am' here");
      } else if (config.grammar && _wantsAn(tokens, k, cur)) {
        cur = cur == 'A' ? 'An' : 'an';
        kind ??= PolishKind.grammar;
        reasons.add("Use 'an' here");
      } else if (config.grammar && _wantsA(tokens, k, cur)) {
        cur = cur == 'An' ? 'A' : 'a';
        kind ??= PolishKind.grammar;
        reasons.add("Use 'a' here");
      } else if (config.grammar && kind == null) {
        final fix = _phraseFix(tokens, k, lower);
        if (fix != null) {
          cur = _caseLike(fix.$1, core);
          kind = fix.$2;
          reasons.add(fix.$3);
        }
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

  /// The suggested spelling of [core], or null: the best-scoring
  /// correction of an unknown word ([PolishConfig.channelWeight]) within
  /// [PolishConfig.maxCostFor] of it, or the word split in two
  /// (`itworked` -> `it worked`, `Whyisn't` -> `Why isn't`), when it is
  /// clearly better than the runner-up ([PolishConfig.ambiguityMargin]).
  String? _spelling(String core, String lower, bool startsSentence) {
    final lex = lexicon;
    if (lex == null) return null;
    if (core.length < config.minWordLength) return null;
    if (_known(lower)) return null;
    // A contraction glued to the word before it (`Baghdadidoesn't`): split
    // even when that word is a name the list does not know.
    final glued = _contractionTail(core, lower);
    if (glued != null) return glued;
    // Words in capitals and camel case are acronyms and brand names.
    if (core.length >= 2 && core == core.toUpperCase()) return null;
    if (core.substring(1) != core.substring(1).toLowerCase()) return null;
    final capitalised = core[0] != core[0].toLowerCase();
    // A capitalised word inside a sentence is a name.
    if (capitalised && !startsSentence) return null;
    if (_looksInflected(lower)) return null;

    // Text, score, and whether it may be chosen (a candidate that only came
    // close still makes the choice ambiguous: `onvert` could be `convert`,
    // so it does not become `overt`).
    final options = <(String, double, bool)>[];
    final split = _split(lower);
    if (split != null) options.add((split.$1, split.$2, true));
    // A word with an apostrophe is only ever split.
    if (!lower.contains("'") && !lower.contains('\u2019')) {
      final maxCost = config.maxCostFor(core.length);
      final closeFloor = lex.logProbAtRank(config.closeMatchMinRank);
      for (final c in lex.candidates(lower, maxEdits: 2, limit: config.candidateLimit)) {
        final w = c.word;
        if (w == lower || w.contains("'")) continue;
        final distance = handwritingDistance(lower, w);
        if (distance <= 0 || distance > maxCost + 1e-9) continue;
        final cost = distance + (w[0] != lower[0] ? config.firstLetterPenalty : 0);
        final lp = lex.logProb(w)!;
        if (lp < (distance <= config.closeMatchCost + 1e-9 ? closeFloor : config.minLogProb)) continue;
        // At the start of a sentence the capital may be a name's: only a
        // look-alike letter or a swap of two letters is fixed there.
        final eligible = cost <= maxCost + 1e-9 &&
            !(capitalised && cost > 0.6 + 1e-9 && !_isSwap(lower, w));
        options.add((w, lp - config.channelWeight * cost, eligible));
      }
    }
    if (options.isEmpty) return null;
    options.sort((a, b) => b.$2.compareTo(a.$2));
    if (!options.first.$3) return null;
    if (options.length > 1 && options[0].$2 - options[1].$2 < config.ambiguityMargin) return null;
    final best = options.first.$1;
    return capitalised ? best[0].toUpperCase() + best.substring(1) : best;
  }

  /// The far more frequent words [core] (a listed word) may have been
  /// meant to be (see [PolishConfig.realWordMinRank]), best first, at most
  /// three; empty when it looks fine. They keep its first letter (first
  /// letters are written carefully). Never applied by itself: on the whole
  /// word list the rule would change one rare word in 13, `testis` and
  /// `cations` among them, so the word is only marked in typed text for the
  /// user to check.
  List<String> suspectsFor(String core, {bool startsSentence = false}) {
    final lex = lexicon;
    if (lex == null || core.length < config.minWordLength) return const [];
    final lower = core.toLowerCase();
    if (_isUserWord(lower) || lex.studyWords.contains(lower) || lower.contains("'")) return const [];
    final rank = lex.rankOf(lower);
    if (rank == null || rank < config.realWordMinRank) return const [];
    if (core.substring(1) != lower.substring(1)) return const [];
    final capitalised = core[0] != lower[0];
    if (capitalised && !startsSentence) return const [];
    final minLp = lex.logProb(lower)! + math.log(config.realWordMinRatio);
    final options = <(String, double)>[];
    for (final c in lex.candidates(lower, maxEdits: 1, limit: config.candidateLimit)) {
      final w = c.word;
      if (w == lower || w.contains("'") || w[0] != lower[0]) continue;
      final r = lex.rankOf(w);
      if (r == null || r > config.realWordMaxTargetRank) continue;
      final lp = lex.logProb(w)!;
      if (lp < minLp) continue;
      final distance = handwritingDistance(lower, w);
      if (distance <= 0 || distance > config.realWordMaxCost + 1e-9) continue;
      if (!_isSkippedLetter(lower, w)) continue;
      options.add((w, lp - config.channelWeight * distance));
    }
    options.sort((a, b) => b.$2.compareTo(a.$2));
    return [
      for (final (w, _) in options.take(3)) capitalised ? w[0].toUpperCase() + w.substring(1) : w,
    ];
  }

  /// [a] and [b] differ by one letter left out or written twice inside the
  /// word (`wong` / `wrong`), not by an ending (`specific` / `specifics`,
  /// `raise` / `raised`): the slip a pen or the recogniser makes, while one
  /// letter swapped for another (`info` / `into`, `fake` / `face`) is far more
  /// often a word of its own, and so is a different ending.
  static bool _isSkippedLetter(String a, String b) {
    if ((a.length - b.length).abs() != 1) return false;
    final long = a.length > b.length ? a : b;
    final short = a.length > b.length ? b : a;
    var i = 0;
    while (i < short.length && long[i] == short[i]) {
      i++;
    }
    if (long.substring(i + 1) != short.substring(i)) return false;
    // The letter is inside the word, not its last one or a plural/past ending.
    if (i >= short.length) return false;
    for (final ending in const ['s', 'es', 'd', 'ed', 'r', 'er', 'n', 'y', 'ly', 'e']) {
      if (long.endsWith(ending) && long.substring(0, long.length - ending.length) == short) return false;
    }
    return true;
  }

  // ---- for the spelling underline --------------------------------------------

  /// Whether [word] (letters with apostrophes or hyphens inside) is spelt
  /// like a known word: the word list with the study words, the personal
  /// dictionary, a contraction, a possessive or another form of a listed word
  /// (`brainstorms`), or a hyphenated word whose every part is known. Without
  /// a word list every word counts as known.
  bool isKnownSpelling(String word) {
    if (lexicon == null) return true;
    final lower = word.toLowerCase().replaceAll('\u2019', "'");
    if (lower.isEmpty) return true;
    if (lower.contains('-')) return lower.split('-').every((p) => p.isEmpty || isKnownSpelling(p));
    if (_known(lower)) return true;
    if (lower.endsWith("'s") && _known(lower.substring(0, lower.length - 2))) return true;
    if (lower.endsWith("s'") && _known(lower.substring(0, lower.length - 1))) return true;
    return !lower.contains("'") && _looksInflected(lower);
  }

  /// Whether [word] is in the personal dictionary.
  bool isUserWord(String word) => _isUserWord(word.toLowerCase());

  /// Spellings [word] (an unknown word) may have been meant as, best first,
  /// at most [limit]: listed words within two edits (one for words of up to
  /// three letters), scored like autocorrect (frequency against handwriting
  /// distance), and the word split in two (`itworked` -> `it worked`). With
  /// the capital of [word]; empty when nothing is close.
  List<String> spellingSuggestions(String word, {int limit = 3}) {
    final lex = lexicon;
    if (lex == null || word.isEmpty) return const [];
    final lower = word.toLowerCase().replaceAll('\u2019', "'");
    final options = <(String, double)>[];
    final split = _split(lower);
    if (split != null) options.add(split);
    if (!lower.contains("'")) {
      for (final c in lex.candidates(lower, maxEdits: lower.length <= 3 ? 1 : 2, limit: config.candidateLimit)) {
        final w = c.word;
        if (w == lower || w.contains("'")) continue;
        final distance = handwritingDistance(lower, w);
        if (distance <= 0) continue;
        final cost = distance + (w[0] != lower[0] ? config.firstLetterPenalty : 0);
        options.add((w, lex.logProb(w)! - config.channelWeight * cost));
      }
    }
    options.sort((a, b) => b.$2.compareTo(a.$2));
    final shouting = word.length >= 2 && word == word.toUpperCase();
    final capital = word[0] != word[0].toLowerCase();
    final out = <String>[];
    for (final (w, _) in options) {
      final shown = shouting ? w.toUpperCase() : (capital ? w[0].toUpperCase() + w.substring(1) : w);
      if (!out.contains(shown)) out.add(shown);
      if (out.length == limit) break;
    }
    return out;
  }

  /// [core] with a space before the contraction it ends with
  /// (`Baghdadidoesn't` -> `Baghdadi doesn't`), or null.
  String? _contractionTail(String core, String lower) {
    final apostrophe = lower.indexOf("'");
    if (apostrophe < 0) return null;
    // The longest contraction that ends the word, at least `n't`/`'re` long
    // and with a word of 2+ letters before it.
    for (var k = 2; k < apostrophe; k++) {
      final tail = lower.substring(k);
      if (contractionLogProb(tail) == null) continue;
      final head = core.substring(0, k);
      if (!RegExp(r'^[A-Za-z]+$').hasMatch(head)) return null;
      return '$head ${core.substring(k)}';
    }
    return null;
  }

  /// [lower] as two words with the space put back, scored like a correction
  /// with [PolishConfig.splitCost] for the missing space and the prior of
  /// the two words together (`ham berger` is far less likely than
  /// `hamburger`); null when no split gives two words of the list (or
  /// contractions) at least as frequent as rank [PolishConfig.splitMinRank].
  (String, double)? _split(String lower) {
    final lex = lexicon!;
    final floor = lex.logProbAtRank(config.splitMinRank);
    (String, double)? best;
    for (var k = 1; k < lower.length; k++) {
      final a = lower.substring(0, k), b = lower.substring(k);
      final la = _partLogProb(a), lb = _partLogProb(b);
      if (la == null || lb == null || la < floor || lb < floor) continue;
      final score = la + lb - config.channelWeight * config.splitCost;
      if (best == null || score > best.$2) best = ('${_partText(a)} ${_partText(b)}', score);
    }
    return best;
  }

  /// ln probability of one part of a split word: a listed word of two or
  /// more letters, `a` or `i`, or a contraction (`isn't`, `isnt`).
  double? _partLogProb(String part) {
    if (part.contains("'") || part.contains('\u2019')) return contractionLogProb(part.replaceAll('\u2019', "'"));
    if (part.length == 1 && part != 'a' && part != 'i') return null;
    final listed = lexicon!.logProb(part) ?? contractionLogProb(part);
    if (listed != null) return listed;
    return _isUserWord(part) ? lexicon!.logProbAtRank(config.userWordRank) : null;
  }

  /// How a part of a split word is written: `i` -> `I`, `isnt` -> `isn't`.
  static String _partText(String part) => part == 'i' ? 'I' : contractionOf(part) ?? part;

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

  /// [word] (the current form of token [k]) is `a` right after `I` and
  /// before another word: `I a not` was `I am not` (`I a` is never English;
  /// the m was lost).
  bool _iA(List<_Token> tokens, int k, String word) {
    if (word != 'a' || k == 0 || k + 1 >= tokens.length) return false;
    final before = tokens[k - 1], t = tokens[k];
    if (before.core != 'I' && before.core != 'i') return false;
    return before.trail.isEmpty && t.lead.isEmpty && t.trail.isEmpty && tokens[k + 1].lead.isEmpty;
  }

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

  /// [word] is the article `an` and the next word starts with a consonant
  /// sound (`an book` -> `a book`, `an university` -> `a university`).
  /// Words starting with `x` (`an x-ray`) and capitals are left alone.
  bool _wantsA(List<_Token> tokens, int k, String word) {
    if (word != 'an' && word != 'An') return false;
    final t = tokens[k];
    if (t.trail.isNotEmpty || k + 1 >= tokens.length) return false;
    final next = tokens[k + 1].core;
    if (!_plainWord.hasMatch(next) || next.length < 2) return false;
    if (next == next.toUpperCase()) return false;
    final lower = next.toLowerCase();
    if (lower.startsWith('x') || lower.startsWith('h')) return false;
    return !_startsWithVowelSound(lower);
  }

  static const Set<String> _modals = {'could', 'should', 'would', 'must', 'might'};
  static const Set<String> _beForms = {'is', 'are', 'was', 'were'};

  /// Fixed slips of two words, judged by the word next to token [k]
  /// (`lower` is its lowercase form): `could of` -> `could have`, `their is`
  /// -> `there is`, and `alot` -> `a lot`. Returns the replacement (lower
  /// case), its kind and its reason.
  (String, PolishKind, String)? _phraseFix(List<_Token> tokens, int k, String lower) {
    final t = tokens[k];
    if (lower == 'alot') return ('a lot', PolishKind.spelling, 'Spelling');
    if (lower == 'of' && k > 0 && t.lead.isEmpty) {
      final before = tokens[k - 1];
      if (before.trail.isEmpty && _modals.contains(before.core.toLowerCase())) {
        return ('have', PolishKind.grammar, "Use 'have' here");
      }
    }
    if (lower == 'their' && t.trail.isEmpty && k + 1 < tokens.length) {
      final after = tokens[k + 1];
      if (after.lead.isEmpty && _beForms.contains(after.core.toLowerCase())) {
        return ('there', PolishKind.grammar, "Use 'there' here");
      }
    }
    return null;
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
