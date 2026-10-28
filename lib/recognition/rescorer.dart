import 'dart:math' as math;

import 'ctc.dart';
import 'lexicon.dart';
import 'user_lexicon.dart';

/// All tuning numbers of the language layer in one place.
///
/// A candidate word `w` for a word image is scored as
///
///     score(w) = ln P(image | w) + lambda * ln prior(w)
///
/// where `ln P(image | w)` is the CTC forward log-likelihood (case
/// insensitive) and `prior` is the word's share of the English word list, or
/// [userLogProb] for a word of the personal dictionary. The recogniser is
/// over-confident on handwriting (it often puts 0.9+ on a wrong letter), so
/// the prior must be allowed to overrule moderately confident letters:
/// [lambda] is the exchange rate between "nats of image evidence" and "nats
/// of language prior".
class RescoreConfig {
  const RescoreConfig({
    this.lambda = 0.6,
    this.oovRank = 30000,
    this.oovPenalty = 0.0,
    this.userLogProb = -7.0,
    this.userMinAdvantage = 3.0,
    this.knownBonus = 1.5,
    this.unknownBonus = 1.0,
    this.doubtfulProb = 0.6,
    this.clearProb = 0.9,
    this.maxCandidates = 150,
    this.beamWidth = 5,
    this.beamNeighbours = 2,
    this.maxAlternatives = 5,
    this.alternativeGap = 12.0,
    this.beamAlternativeGap = 1.5,
    this.confidenceLengthExponent = 0.5,
    this.confusionMass = 0.08,
    this.confusablePairs = defaultConfusablePairs,
    this.acronyms = defaultAcronyms,
  });

  /// Weight of the language prior against the image evidence.
  final double lambda;

  /// Words that are neither listed nor in the personal dictionary (a name, a
  /// misspelling) get the prior of the word at this rank of the list: a rare
  /// but real word. A prior below the rarest listed word (what this used to
  /// be) made the rescorer replace clear unknown readings by frequent words.
  final int oovRank;

  /// Extra nats below that prior (0 = none).
  final double oovPenalty;

  /// ln prior of a personal-dictionary word (roughly the frequency of a word
  /// in the top few thousand, so a name the user taught the app beats most
  /// look-alikes the word list has).
  final double userLogProb;

  /// Whatever the size of the word list, a personal word's prior is at least
  /// this many nats above that of a string nobody knows.
  final double userMinAdvantage;

  /// Added to the score of the model's own (greedy) reading when it is a
  /// known word: another candidate must beat it by this many nats to replace
  /// it. Correcting a right word is worse than leaving a wrong one.
  final double knownBonus;

  /// Same, when the greedy reading is not a known word. Positive: a clear
  /// unknown reading (a name) is replaced only when the evidence for the
  /// replacement is nearly as good (negative values make the app change
  /// unknown words more readily).
  final double unknownBonus;

  /// [unknownBonus] counts in full only for a CLEAR reading: one whose
  /// weakest letter has at least [clearProb]. It shrinks linearly to nothing
  /// at [doubtfulProb] and below, so a reading the model itself doubts is
  /// repaired as readily as before.
  final double doubtfulProb;
  final double clearProb;

  /// Dictionary words examined per recognised word.
  final int maxCandidates;

  /// Width of the CTC prefix beam search whose readings join the candidates
  /// (0 turns it off).
  final int beamWidth;

  /// For this many of the best other beam readings the dictionary neighbours
  /// (one edit) are examined too.
  final int beamNeighbours;

  /// Other readings returned besides the chosen one.
  final int maxAlternatives;

  /// Alternatives scoring more than this many nats below the chosen reading
  /// are not worth showing.
  final double alternativeGap;

  /// A reading that is no known word is only offered as an alternative when
  /// it is at most this many nats less likely than the best reading (as
  /// ranked by the beam search, or by the image evidence for a candidate).
  final double beamAlternativeGap;

  /// The word-level confidence is `exp(ln P / length^exponent)`: 0 gives the
  /// probability of the whole string, 1 the per-character geometric mean.
  final double confidenceLengthExponent;

  /// The recogniser is sure of letters that look alike in handwriting (an
  /// `e` written like a `c` gets 0.99 for `c` and almost nothing for `e`).
  /// Before candidates are scored, every frame lends this fraction of the
  /// probability of one letter of a confusable pair to the other, so a
  /// look-alike substitution costs a couple of nats instead of ten. 0 turns
  /// it off. Only candidate scoring is affected; the raw reading is not.
  final double confusionMass;

  /// Letters (lowercase pairs) that look alike in handwriting.
  final List<String> confusablePairs;

  static const List<String> defaultConfusablePairs = [
    'ec', 'rs', 'ao', 'au', 'nu', 'nr', 'nm', 'mw', 'uv', 'vy', 'il', 'lt', 'it', 'ft', 'hb', 'hk',
    'gq', 'gy', 'pq', 'kx', 'sz', 'ij', 'do', 'cl', 'ck', 'eo', 'ae', 'nh', 'uo', 'rv',
  ];

  /// Lowercase acronyms that stay in capitals when the recogniser reads them
  /// in capitals.
  final Set<String> acronyms;

  static const Set<String> defaultAcronyms = {
    'usa', 'uk', 'eu', 'un', 'uae', 'nyc', 'pdf', 'html', 'css', 'api', 'url', 'sql', 'cpu', 'gpu',
    'ram', 'usb', 'gps', 'sms', 'dvd', 'cd', 'tv', 'pc', 'ai', 'id', 'ok', 'cv', 'faq', 'ceo', 'cto',
    'cfo', 'phd', 'mba', 'dna', 'rna', 'hiv', 'fbi', 'cia', 'nasa', 'nato', 'ibm', 'bbc', 'cnn', 'asap',
  };

  /// The largest number of dictionary edits tried for a word of [letters]
  /// letters.
  int maxEditsFor(int letters) => letters <= 2 ? 0 : (letters <= 4 ? 1 : 2);

  /// Same for personal-dictionary words, which are trusted more.
  int maxUserEditsFor(int letters) => letters <= 2 ? 0 : (letters == 3 ? 1 : (letters == 4 ? 2 : 3));
}

/// One recognised word.
class RescoredWord {
  const RescoredWord({
    required this.text,
    required this.raw,
    required this.confidence,
    required this.alternatives,
  });

  /// The chosen reading, with the capitalisation and punctuation of the raw
  /// output (see [LexiconRescorer] for the capitalisation rules).
  final String text;

  /// The plain best-path (greedy) CTC output.
  final String raw;

  /// 0..1: how likely the reading is right (see
  /// [RescoreConfig.confidenceLengthExponent]), lowered when other readings
  /// score nearly as well.
  final double confidence;

  /// Up to [RescoreConfig.maxAlternatives] other readings, best first, with
  /// the same capitalisation rules applied. Includes [raw] when it was
  /// replaced.
  final List<String> alternatives;

  /// The language layer changed the model's own reading.
  bool get corrected => text != raw;
}

/// Picks the final word from CTC probabilities.
///
/// Candidates: the model's greedy reading, the readings of a CTC prefix beam
/// search, dictionary words within a few edits of them, and personal
/// dictionary words within a few (more generous) edits. Each is scored with
/// [RescoreConfig]; the greedy reading keeps a head start when it is a known
/// word, so a clear image reading is never overruled by a language prior.
///
/// Capitalisation: matching is case insensitive. A personal-dictionary word
/// is written exactly as the user typed it (`Malek`). Any other word takes
/// the case of the raw reading's first letter (`Note`, `note`); a raw
/// reading in capitals (three or more letters) is not kept in capitals
/// unless the word is a known acronym, because the recogniser tends to
/// shout. Single letters keep the raw case. A reading that nothing explains
/// (an unknown word nobody replaced) is returned exactly as read.
///
/// Anything with digits or odd punctuation inside (`2025`, `well-known`,
/// `c4t`) is never corrected.
class LexiconRescorer {
  LexiconRescorer(
    this.charset,
    this.lexicon, {
    this.config = const RescoreConfig(),
    this.userLexicon,
  });

  final CtcCharset charset;

  /// Null disables dictionary correction.
  final Lexicon? lexicon;

  /// The personal dictionary, read live (words added later are used at once).
  final UserLexicon? userLexicon;
  final RescoreConfig config;

  static final RegExp _split = RegExp(r'^([^A-Za-z0-9]*)(.*?)([^A-Za-z0-9]*)$');
  static final RegExp _letters = RegExp(r"^[A-Za-z]+(?:'[A-Za-z]+)?$");

  bool _isKnown(String lower) =>
      (userLexicon?.contains(lower) ?? false) ||
      (lexicon?.contains(lower) ?? false) ||
      contractionLogProb(lower) != null;

  late final double _oovPrior =
      (lexicon?.logProbAtRank(config.oovRank) ?? math.log(1e-9)) - config.oovPenalty;

  double _priorOf(String lower) {
    final user = userLexicon?.contains(lower) ?? false;
    // Being listed never hurts: a word rarer than the unknown-string prior
    // is scored like an unknown string.
    var base = math.max(lexicon?.logProb(lower) ?? _oovPrior, _oovPrior);
    final contraction = contractionLogProb(lower);
    if (contraction != null) base = math.max(base, contraction);
    if (user) {
      final prior = math.max(config.userLogProb, _oovPrior + config.userMinAdvantage);
      return math.max(prior, base);
    }
    return base;
  }

  /// Class indices of each confusable pair: (letter a in both cases, letter
  /// b in both cases).
  late final List<(List<int>, List<int>)> _pairClasses = () {
    List<int> classesOf(String ch) => [
          for (final v in {ch, ch.toUpperCase()}) ?charset.indexOf(v),
        ];
    return [
      for (final p in config.confusablePairs)
        if (p.length == 2) (classesOf(p[0]), classesOf(p[1])),
    ].where((e) => e.$1.isNotEmpty && e.$2.isNotEmpty).toList();
  }();

  /// [lp] with every letter lending [RescoreConfig.confusionMass] of its
  /// probability to the letters it is confusable with (see there).
  CtcLogProbs _smoothed(CtcLogProbs lp) {
    final eps = config.confusionMass;
    if (eps <= 0 || _pairClasses.isEmpty) return lp;
    final classes = lp.classes;
    final data = List<double>.of(lp.data);
    final extra = List<double>.filled(classes, 0);
    for (var t = 0; t < lp.timesteps; t++) {
      final base = t * classes;
      for (final (a, b) in _pairClasses) {
        var fa = 0.0, fb = 0.0;
        for (final i in a) {
          fa += math.exp(data[base + i]);
        }
        for (final i in b) {
          fb += math.exp(data[base + i]);
        }
        // Spread over both cases so the case-insensitive sum is eps * f.
        for (final i in a) {
          extra[i] += eps * fb / a.length;
        }
        for (final i in b) {
          extra[i] += eps * fa / b.length;
        }
      }
      // A pseudo-likelihood: the frame is not renormalised, so a reading the
      // model already supports never loses probability.
      for (var c = 0; c < classes; c++) {
        final e = extra[c];
        if (e > 0) {
          data[base + c] = math.log(math.exp(data[base + c]) + e);
          extra[c] = 0;
        }
      }
    }
    return CtcLogProbs(data, timesteps: lp.timesteps, classes: classes);
  }

  List<List<int>>? _caseInsensitiveSets(String word) {
    final sets = <List<int>>[];
    for (final r in word.runes) {
      final ch = String.fromCharCode(r);
      final options = <int>{};
      for (final v in [ch.toLowerCase(), ch.toUpperCase()]) {
        final i = charset.indexOf(v);
        if (i != null) options.add(i);
      }
      if (options.isEmpty) return null;
      sets.add(options.toList());
    }
    return sets;
  }

  RescoredWord rescore(CtcLogProbs lp) {
    final greedy = greedyDecode(lp, charset);
    final raw = greedy.text;
    if (raw.isEmpty) {
      return const RescoredWord(text: '', raw: '', confidence: 0, alternatives: []);
    }
    final beams = config.beamWidth > 0
        ? ctcBeamSearch(lp, charset, width: config.beamWidth)
        : const <CtcBeamReading>[];
    final m = _split.firstMatch(raw);
    final lead = m?.group(1) ?? '';
    final core = m?.group(2) ?? raw;
    final trail = m?.group(3) ?? '';
    final correctable = core.isNotEmpty &&
        _letters.hasMatch(core) &&
        (lexicon != null || (userLexicon?.isEmpty == false));
    if (!correctable) return _passThrough(lp, greedy, beams);

    final leadSets = [for (final i in charset.encode(lead) ?? const <int>[]) [i]];
    final trailSets = [for (final i in charset.encode(trail) ?? const <int>[]) [i]];
    final coreLower = core.toLowerCase();
    final cands = <String, _Candidate>{};
    final scoring = _smoothed(lp);

    void consider(String word) {
      if (cands.containsKey(word)) return;
      final cs = _caseInsensitiveSets(word);
      if (cs == null) return;
      final sets = [...leadSets, ...cs, ...trailSets];
      final ll = ctcLogLikelihoodSets(scoring, sets, blank: charset.blank);
      if (ll == double.negativeInfinity) return;
      final known = _isKnown(word);
      cands[word] = _Candidate(word, ll, _priorOf(word), known, sets.length, config.lambda);
    }

    final lex = lexicon;
    consider(coreLower);
    // Readings of the beam search whose punctuation matches the greedy one.
    final beamCores = <String>[];
    for (final b in beams) {
      final bm = _split.firstMatch(b.text);
      if (bm == null || bm.group(1) != lead || bm.group(3) != trail) continue;
      final bc = bm.group(2)!;
      if (!_letters.hasMatch(bc)) continue;
      final lower = bc.toLowerCase();
      if (lower == coreLower || beamCores.contains(lower)) continue;
      beamCores.add(lower);
      consider(lower);
    }
    final letters = coreLower.replaceAll("'", '').length;
    if (lex != null) {
      for (final c in lex.candidates(coreLower,
          maxEdits: config.maxEditsFor(letters), limit: config.maxCandidates)) {
        consider(c.word);
      }
      for (final lower in beamCores.take(config.beamNeighbours)) {
        final n = lower.replaceAll("'", '').length;
        if (n <= 2) continue;
        for (final c in lex.candidates(lower, maxEdits: 1, limit: 20)) {
          consider(c.word);
        }
      }
    }
    final user = userLexicon;
    if (user != null) {
      final edits = config.maxUserEditsFor(letters);
      for (final form in user.nearby(coreLower, edits)) {
        consider(form.toLowerCase());
      }
    }

    final greedyCand = cands[coreLower];
    if (greedyCand == null) return _passThrough(lp, greedy, beams);
    final ranked = cands.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    var best = ranked.first;
    final weakest = greedy.charProbs.isEmpty ? 0.0 : greedy.charProbs.reduce(math.min);
    final clarity = ((weakest - config.doubtfulProb) / (config.clearProb - config.doubtfulProb)).clamp(0.0, 1.0);
    final bonus = greedyCand.known ? config.knownBonus : config.unknownBonus * clarity;
    if (best.word == coreLower || best.score <= greedyCand.score + bonus) best = greedyCand;

    String render(_Candidate c) {
      if (c.word == coreLower && !c.known) return raw; // nothing explains it: as read
      return '$lead${_applyCase(c.word, core)}$trail';
    }

    final chosen = render(best);
    final alternatives = <String>[];
    void offer(String text) {
      if (text != chosen && !alternatives.contains(text) && alternatives.length < config.maxAlternatives) {
        alternatives.add(text);
      }
    }

    for (final c in ranked) {
      if (c == best) continue;
      if (c != greedyCand) {
        if (c.score < best.score - config.alternativeGap) continue;
        // A string that is no word must at least be a likely reading.
        if (!c.known && c.ll < greedyCand.ll - config.beamAlternativeGap) continue;
      }
      offer(render(c));
    }
    // The raw reading is always worth showing next to a correction.
    if (best != greedyCand && !alternatives.contains(raw) && raw != chosen) {
      if (alternatives.length >= config.maxAlternatives) alternatives.removeLast();
      alternatives.add(raw);
    }
    // Beam readings that differ from everything above in more than case.
    final shown = {chosen.toLowerCase(), for (final a in alternatives) a.toLowerCase()};
    for (final b in _plausible(beams)) {
      if (b.text.isNotEmpty && shown.add(b.text.toLowerCase())) offer(b.text);
    }

    // Posterior of the chosen reading among the candidates, from the scores.
    final top = ranked.first.score;
    var z = 0.0;
    for (final c in ranked) {
      z += math.exp(c.score - top);
    }
    final posterior = z > 0 ? math.exp(best.score - top) / z : 1.0;
    final base = math.exp(best.ll / math.pow(best.length, config.confidenceLengthExponent));
    final conf = (base * math.sqrt(posterior)).toDouble();
    return RescoredWord(
      text: chosen,
      raw: raw,
      confidence: conf.isNaN ? 0.0 : conf.clamp(0.0, 1.0),
      alternatives: alternatives,
    );
  }

  /// A reading that is not a plain word: kept as read, with the beam
  /// search's other readings as alternatives.
  RescoredWord _passThrough(CtcLogProbs lp, CtcGreedy greedy, List<CtcBeamReading> beams) {
    final raw = greedy.text;
    final ll = ctcLogLikelihoodSets(
      lp,
      [for (final i in greedy.indices) [i]],
      blank: charset.blank,
    );
    final n = math.max(greedy.indices.length, 1);
    final double conf = ll == double.negativeInfinity
        ? greedy.confidence
        : math.exp(ll / math.pow(n, config.confidenceLengthExponent)).clamp(0.0, 1.0).toDouble();
    final alternatives = <String>[];
    for (final b in _plausible(beams)) {
      if (b.text.isEmpty || b.text == raw || alternatives.contains(b.text)) continue;
      if (alternatives.length >= config.maxAlternatives) break;
      alternatives.add(b.text);
    }
    return RescoredWord(text: raw, raw: raw, confidence: conf, alternatives: alternatives);
  }

  /// The beam readings close enough to the best one to be worth offering.
  Iterable<CtcBeamReading> _plausible(List<CtcBeamReading> beams) {
    if (beams.isEmpty) return beams;
    final floor = beams.first.logProb - config.beamAlternativeGap;
    return beams.where((b) => b.logProb >= floor);
  }

  /// [lower] written with the capitalisation rules of the class comment. A
  /// replacement (a word different from the raw reading) copies the case
  /// pattern of the raw reading only when the first letters agree: a raw
  /// `Isut` that the language layer turns into `Sat` is no sentence start, so
  /// the replacement stays lowercase.
  String _applyCase(String lower, String rawCore) {
    final user = userLexicon?.formOf(lower);
    if (user != null) return user;
    if (lower.isEmpty || rawCore.isEmpty) return lower;
    if (lower != rawCore.toLowerCase() && rawCore[0].toLowerCase() != lower[0]) return lower;
    final upperFirst = rawCore[0] != rawCore[0].toLowerCase();
    if (lower.length == 1) return upperFirst ? lower.toUpperCase() : lower;
    final shouting = rawCore.length >= 2 && rawCore == rawCore.toUpperCase();
    if (shouting && config.acronyms.contains(lower)) return lower.toUpperCase();
    return upperFirst ? lower[0].toUpperCase() + lower.substring(1) : lower;
  }
}

class _Candidate {
  _Candidate(this.word, this.ll, this.prior, this.known, this.length, double lambda)
      : score = ll + lambda * prior;

  /// Lowercase word.
  final String word;

  /// `ln P(image | word)`.
  final double ll;

  /// ln prior of the word.
  final double prior;
  final bool known;

  /// Number of label positions (including punctuation).
  final int length;
  final double score;
}
