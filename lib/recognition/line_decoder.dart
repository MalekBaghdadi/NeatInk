import 'dart:math' as math;

import 'ctc.dart';
import 'lexicon.dart';
import 'rescorer.dart' show RescoreConfig;
import 'user_lexicon.dart';

/// One word of a decoded line.
class DecodedWord {
  const DecodedWord({
    required this.text,
    required this.raw,
    required this.confidence,
    required this.startFrame,
    required this.endFrame,
    required this.known,
    this.alternatives = const [],
  });

  /// The chosen word with its capitalisation and punctuation.
  final String text;

  /// What the model alone (best path, no language layer) read in the frames
  /// of this word; empty when it read nothing there.
  final String raw;

  /// 0..1: how sure the decoder is of [text] (see [LineDecodeConfig]).
  final double confidence;

  /// Other readings of the word, best first (never [text] itself); the raw
  /// reading is among them when it was replaced.
  final List<String> alternatives;

  /// First frame of the word's range of the line's model output.
  final int startFrame;

  /// One past the last frame of the range. The ranges of consecutive words
  /// tile the line (the first starts at frame 0, the last ends at the last
  /// frame), the boundary between two words lying
  /// [LineDecodeConfig.gapSplit] of the way across the gap between them.
  final int endFrame;

  /// The word is in the word list, the personal dictionary or the contraction
  /// table.
  final bool known;

  /// The language layer changed the model's reading.
  bool get corrected => text != raw;
}

/// The decoded text of one line image.
class LineReading {
  const LineReading({
    required this.text,
    required this.raw,
    required this.confidence,
    required this.words,
    required this.timesteps,
  });

  static const LineReading empty = LineReading(text: '', raw: '', confidence: 0, words: [], timesteps: 0);

  /// The words joined by single spaces.
  final String text;

  /// The model's best-path reading of the whole line (spaces collapsed).
  final String raw;

  /// 0..1: a robust minimum of the word confidences (see
  /// [LineDecodeConfig.lineShrink]).
  final double confidence;
  final List<DecodedWord> words;

  /// Number of frames of the model output (frame `t` shows pixel
  /// `t * imageWidth / timesteps`).
  final int timesteps;
}

/// All tuning numbers of the line decoder in one place.
///
/// A candidate reading `s` of a stretch of the line is scored as
///
///     score(s) = ln P(image | s) + lambda * sum ln prior(word)
///                + wordBonus * words + bonus(words the model itself read)
///
/// `ln P(image | s)` is the CTC forward log-likelihood of the string WITH its
/// spaces (case insensitive, look-alike letters lend each other a little
/// probability, see [confusionMass]); `prior` comes from the word list, the
/// personal dictionary or the contraction table. This is "shallow fusion": the
/// recogniser already contains a language model of sorts, so the external one
/// only needs a moderate weight ([lambda]) to break ties between look-alikes
/// and to place spaces, never to overrule clear letters.
class LineDecodeConfig {
  const LineDecodeConfig({
    this.lambda = 0.55,
    this.oovRank = 30000,
    this.oovPenalty = 0.0,
    this.fallbackOovLogProb = -13.8,
    this.userLogProb = -7.0,
    this.knownBonus = 2.0,
    this.unknownBonus = 1.25,
    this.wordBonus = 0.0,
    this.splitBonus = 5.0,
    this.oovLetterLogProb = -3.0,
    this.oovFreeLetters = 8,
    this.confusionMass = 0.1,
    this.evidenceMass = 0.3,
    this.confusablePairs = RescoreConfig.defaultConfusablePairs,
    this.acronyms = RescoreConfig.defaultAcronyms,
    this.upperAcronyms = defaultUpperAcronyms,
    this.cutPeak = 0.6,
    this.cutRunProb = 0.3,
    this.maxStretchFrames = 56,
    this.minStretchFrames = 6,
    this.softCutProb = 0.15,
    this.maxSegmentPieces = 6,
    this.beamWidth = 16,
    this.beamPerFrame = 6,
    this.beamMinProb = 1e-3,
    this.maxCandidates = 40,
    this.doubtfulProb = 0.6,
    this.clearProb = 0.9,
    this.bonusFloor = 0.5,
    this.firmProb = 0.9,
    this.maxSweeps = 3,
    this.ascentStarts = 3,
    this.maxAlternatives = 4,
    this.alternativeGap = 6.0,
    this.confidenceLengthExponent = 0.5,
    this.taughtEvidenceExponent = 0.5,
    this.lineShrink = 1.0,
    this.gapSplit = 0.4,
  });

  /// Weight of the language prior against the image evidence (nats of image
  /// likelihood per nat of prior). The model is over-confident on handwriting
  /// (0.99 on a wrong letter is common), so the prior must be able to pay for
  /// a look-alike substitution, but a clear letter costs 4-5 nats and the
  /// whole prior range of the word list (the most frequent word to a rare one)
  /// is about 12 nats, so 0.55 lets a frequent word beat a doubtful letter and
  /// never a clear one.
  final double lambda;

  /// A string nobody knows (a name, a misspelling) gets the prior of the word
  /// at this rank of the word list: a rare but real word. It must not be far
  /// lower than that: a prior of "less likely than the rarest word" is what
  /// made the old rescorer replace clear unknown readings by frequent words.
  /// Rank 30000 of the bundled 50k list is about ln 1e-6 (see
  /// [fallbackOovLogProb]).
  final int oovRank;

  /// Extra nats below the rank prior (0 = none).
  final double oovPenalty;

  /// The unknown-string prior when there is no word list.
  final double fallbackOovLogProb;

  /// ln prior of a personal-dictionary word (about a top-150 word of the
  /// list; the list's top-2000 word is ln -9.8). The user taught it and writes
  /// it often (a name), and the look-alike substitutions this writer makes
  /// ('Malck' for 'Malek') must be repairable even when the model shows the
  /// wrong letter with 0.99: the prior gain 0.55 * (13.8 - 7.0) = 3.7 nats
  /// has to beat the 2.3 nats a look-alike costs.
  final double userLogProb;

  /// Added to the score of a word the model itself read when it is a known
  /// word: another word must beat it by this many nats. Correcting a right
  /// word is worse than leaving a wrong one.
  final double knownBonus;

  /// Same when the model's word is not a known word. Positive: a clear
  /// unknown reading (a name) is only replaced when the evidence for the
  /// replacement is nearly as good. (No head start for a reading that a
  /// look-alike slip away from a personal-dictionary word or a contraction: it
  /// is better explained as a misreading of that word.)
  final double unknownBonus;

  /// Added per word of a candidate. A unigram prior pays one (negative)
  /// log-probability per word, which taxes splitting a token in two; a small
  /// positive value compensates. 0 = neutral.
  final double wordBonus;

  /// Added per extra word when an UNKNOWN token is split into known words
  /// (`arein` -> `are in`, `thecatandthe` -> `the cat and the`). The prior of an
  /// unknown string is a single rare-word figure (see [oovRank]; up to
  /// [oovFreeLetters] letters) that exists to protect clear names; if it were
  /// modelled letter by letter it would be far lower, and several known words,
  /// each paying its own (negative) log-probability, would not lose to it.
  /// This is the compensation. The image still has to show a gap there (the
  /// space class costs what the model gives it) and every piece must be a
  /// known word.
  final double splitBonus;

  /// An unknown string longer than [oovFreeLetters] letters (and digits) pays
  /// this many nats per extra letter on top of [oovRank]'s prior: about what
  /// a random letter costs (ln 1/26 = -3.3).
  ///
  /// With one flat figure for every unknown string, ONE long unknown token
  /// cost half of what the same letters cost as two unknown words, so the
  /// decoder dropped the model's own spaces between unknown words whenever
  /// they were not near certain (Mariam's `Nerous systen` -> `Neroussysten`,
  /// even `ocd, depression` -> `ocd,depression`). Now gluing words into one
  /// long token gains about nothing and the image decides. Words of up to 8
  /// letters (nearly every name) keep exactly the protection they had: an
  /// unknown string is never likelier than a rare real word.
  final double oovLetterLogProb;
  final int oovFreeLetters;

  /// Look-alike leniency: every frame lends this fraction of the probability
  /// of one letter of a pair (`e`/`c`, `n`/`u`, `n`/`h`, `u`/`o`, `r`/`v` ...)
  /// to the other, so a look-alike substitution costs about
  /// `-ln(confusionMass)` = 2.3 nats instead of the 9-18 a model that is sure
  /// of the wrong letter would charge. 0 turns it off.
  final double confusionMass;

  /// Same leniency, used only to judge how clearly the image shows the letters
  /// of the chosen words (the word confidence). Larger than [confusionMass]
  /// because choosing a word is a gamble the dictionary has to win, while
  /// reporting it as "not sure" for every letter that merely looks like its
  /// look-alike would flag every repaired name of this writer.
  final double evidenceMass;

  /// Lowercase letter pairs that look alike in handwriting.
  final List<String> confusablePairs;

  /// Lowercase acronyms that stay in capitals when read in capitals.
  final Set<String> acronyms;

  /// Lowercase acronyms that are written in capitals however they were
  /// written (`ocd` -> `OCD`, plural `ssris` -> `SSRIs`): they are never
  /// ordinary words. The same ones are known words through
  /// `assets/htr/subject_words.txt`.
  final Set<String> upperAcronyms;

  static const Set<String> defaultUpperAcronyms = {
    'adhd', 'ocd', 'ptsd', 'gaba', 'dna', 'rna', 'mrna', 'trna', 'atp', 'adp', 'eeg', 'ecg', 'ekg', 'emg', //
    'mri', 'fmri', 'cns', 'pns', 'iq', 'ssri', 'snri', 'maoi', 'dsm', 'icd', 'bmi', 'hiv', 'copd', 'cpr', //
    'icu', 'bpm', 'acth', 'tsh', 'lsd', 'mdma', 'nmda', 'ampa', 'ltp',
  };

  /// A run of frames where the space class is likely (at least
  /// [cutRunProb]) whose strongest frame reaches this probability is a
  /// confident word gap: the line is cut there into stretches that are
  /// decoded one by one. Weaker gaps (the model hesitates between "space" and
  /// "no space") stay inside a stretch where the decoder can insert or remove
  /// them.
  final double cutPeak;

  /// Probability of the space class from which a frame belongs to a gap run.
  final double cutRunProb;

  /// A stretch longer than this many frames (about 18 characters) is cut at its
  /// likeliest gap frame, which must have at least [softCutProb] and leave
  /// [minStretchFrames] on each side. Only a speed guard for lines whose gaps
  /// are all hesitant: it forbids merging the words on either side of the
  /// cut.
  final int maxStretchFrames;
  final int minStretchFrames;
  final double softCutProb;

  /// A token that is several words run together is split into at most this
  /// many.
  final int maxSegmentPieces;

  /// Readings kept by the CTC prefix beam search of each stretch.
  final int beamWidth;

  /// Classes extended per frame by the beam search.
  final int beamPerFrame;

  /// Classes below this probability are not extended.
  final double beamMinProb;

  /// Dictionary neighbours examined per word.
  final int maxCandidates;

  /// The head start of the model's own words ([knownBonus], [unknownBonus])
  /// counts in full for a word whose weakest letter has at least [clearProb]
  /// and shrinks linearly to nothing at [doubtfulProb] and below.
  final double doubtfulProb;
  final double clearProb;

  /// A reading the model doubts keeps at least this fraction of the head
  /// start: real handwriting gives 0.3-0.7 to many CORRECT letters, so a head
  /// start that vanished with them would let a frequent word replace every
  /// name with a weak letter (`Malek` -> `March`).
  final double bonusFloor;

  /// A word of the list whose every letter the model shows with at least this
  /// probability is not searched for neighbours (saves the dictionary
  /// lookups, and a clear reading must not be changed anyway).
  final double firmProb;

  /// Coordinate-ascent sweeps over the words of a stretch.
  final int maxSweeps;

  /// The coordinate ascent starts from up to this many beam readings, the
  /// best one of each word count, and keeps the best outcome. From the single
  /// best start, a reading that only wins after a substitution was out of
  /// reach: `Nerous systen` lost to the merged `Neroussysten` before
  /// `systen` could become `system`, and nothing splits two unknown words
  /// again.
  final int ascentStarts;

  /// Alternatives kept per word.
  final int maxAlternatives;

  /// Alternatives scoring more than this many nats below the chosen reading
  /// are not shown.
  final double alternativeGap;

  /// The evidence of a word is `exp(sum ln letterProb / length^exponent)`:
  /// 0 gives the probability of the whole word, 1 the geometric mean.
  final double confidenceLengthExponent;

  /// The evidence of a personal-dictionary word is raised to this power
  /// (below 1 softens it): the user typed the word, so a reading that matches
  /// it needs less support from the image than a word nobody vouches for; its
  /// name written with an unclear h/d should not be "not sure" on every page.
  final double taughtEvidenceExponent;

  /// The confidence of a word counts for the line as
  /// `(c * letters + s) / (letters + s)` with `s` = this many pseudo-letters
  /// of certainty, so a one-letter slip (an `a`, a stray mark) weighs less than
  /// a doubtful long word; the line confidence is the minimum of these.
  final double lineShrink;

  /// Where the boundary between two words lies in the gap between their last
  /// and first letter frames: 0 = right after the previous word, 1 = right
  /// before the next. Below one half gives the following word more of the
  /// gap, because the dot of an `i` that starts a word sits to the left of its
  /// stem for this writer and must not drift to the previous word.
  final double gapSplit;

  /// Largest number of dictionary edits tried for a word of [letters] letters.
  /// Long words have few neighbours, so three edits are affordable from ten
  /// letters on (Mariam's `Neuraratony` is three from `neuroanatomy`).
  int maxEditsFor(int letters) => letters <= 5 ? 1 : (letters < 10 ? 2 : 3);

  /// Same for personal-dictionary words and contractions, which are trusted
  /// more.
  int maxUserEditsFor(int letters) => letters <= 2 ? 0 : (letters == 3 ? 1 : (letters == 4 ? 2 : 3));
}

/// Decodes the model output of a WHOLE LINE image into words.
///
/// The model is a line recogniser: it emits a space class between words, and
/// reading a line in one piece removes the word-grouping errors of cutting the
/// ink into word images first. The decoder keeps the model's visual evidence
/// and uses the language layer only where the evidence is open:
///
/// 1. Frames where the space class is confident (see
///    [LineDecodeConfig.cutPeak]) cut the line into stretches (usually one
///    word each).
/// 2. Each stretch gets a CTC prefix beam search WITH the space class, so
///    its readings contain their own spaces.
/// 3. The best reading is improved by coordinate ascent over its words:
///    each word may be replaced by a dictionary neighbour (edit distance
///    weighted for look-alike letters), a personal-dictionary word, or a
///    contraction written without its apostrophe; an unknown word may be
///    split into known words (`arein` -> `are in`), two words may be merged
///    into a known one (`to day` -> `today`). Every candidate stretch is
///    scored as a whole (string with spaces, see [LineDecodeConfig]).
/// 4. The winner is aligned to the frames, which gives each word its frame
///    range, and judged on its own for the confidence.
///
/// Scoring a stretch instead of the whole line is exact when the cuts are
/// real word gaps (the gap frames have the same cost for every candidate) and
/// is what keeps a 40-character line well below 50 ms ([scoreText] scores a
/// whole line for checking). Because each stretch has its own beam, every word
/// gets its alternatives, which one beam over the whole line could not give.
///
/// Confidence of a word: `evidence * sqrt(posterior)`. The evidence is the
/// CTC likelihood of the word alone on its frames, per letter
/// (`exp(ln P / letters^0.5)`, look-alike letters lend each other
/// [LineDecodeConfig.evidenceMass]); the posterior is the share of the chosen
/// reading among the readings scored at that position (substitutions, splits,
/// merges), without the head start. Of the line: the minimum over its words of
/// the word confidences shrunk towards 1 for short words
/// ([LineDecodeConfig.lineShrink]).
class LineDecoder {
  LineDecoder(
    this.charset,
    this.lexicon, {
    this.userLexicon,
    this.config = const LineDecodeConfig(),
  });

  final CtcCharset charset;

  /// Null disables dictionary correction.
  final Lexicon? lexicon;

  /// The personal dictionary, read live.
  final UserLexicon? userLexicon;
  final LineDecodeConfig config;

  /// Decodes [lp], the log-probabilities of one line image. Build them WITHOUT
  /// folding the space class into the blank:
  /// `CtcLogProbs.fromProbabilities(probs, classes, blank: charset.blank)`.
  LineReading decode(CtcLogProbs lp) {
    if (lp.timesteps == 0) return LineReading.empty;
    return _Decode(this, lp).run();
  }

  // Word-list neighbours of a reading, kept across lines and calls (the word
  // list never changes; auto-convert reads the same lines again and again).
  final Map<String, List<String>> _neighbourMemo = {};

  List<String> _lexiconNeighbours(String core, int maxEdits) {
    final lexicon = this.lexicon;
    if (lexicon == null) return const [];
    final hit = _neighbourMemo[core];
    if (hit != null) return hit;
    if (_neighbourMemo.length >= 20000) _neighbourMemo.clear();
    return _neighbourMemo[core] = [
      for (final c in lexicon.candidates(core, maxEdits: maxEdits, limit: config.maxCandidates)) c.word,
    ];
  }

  /// The objective [decode] maximises (without the head start of the model's
  /// own words), for [text] over the WHOLE of [lp]: the CTC log-likelihood of
  /// the string with its spaces plus the weighted word priors. A decoded line
  /// scores at least as high as the model's own best-path reading; tests
  /// and tuning use this to check the stretch-wise search against the full
  /// line. Negative infinity when [text] cannot be emitted.
  double scoreText(CtcLogProbs lp, String text) => _Decode(this, lp).scoreText(text);
}

// ---------------------------------------------------------------------------

/// One run of frames the best path spends on a character.
class _Glyph {
  _Glyph(this.cls, this.first, this.last, this.prob);

  final int cls;
  final int first;
  int last;
  double prob;
}

/// A word of a candidate stretch: [text] is lowercase (punctuation included),
/// [raw] the word as the model read it (the case rules look at it).
class _Tok {
  const _Tok(this.text, this.raw);

  final String text;
  final String raw;
}

/// What the scorer needs to know about a token, cached per decode.
class _Info {
  _Info({
    required this.lead,
    required this.core,
    required this.trail,
    required this.letters,
    required this.known,
    required this.prior,
    required this.sets,
  });

  final String lead;
  final String core;
  final String trail;

  /// The core is a plain word (letters, at most one apostrophe inside).
  final bool letters;
  final bool known;
  final double prior;

  /// Case-insensitive label sets of the whole token; null when the model
  /// cannot emit some character.
  final List<List<int>>? sets;
}

class _Variant {
  _Variant(this.tokens, {this.substitute, this.bonus = 0});

  final List<_Tok> tokens;

  /// Added to the score of [tokens] when the variant is compared with the
  /// current reading (see [LineDecodeConfig.splitBonus]).
  final double bonus;

  /// Set when the variant only replaces one word by another (not a split or a
  /// merge): that word's lowercase core, shown as an alternative.
  final String? substitute;
}

class _Decode {
  _Decode(this.d, this.lp) : cfg = d.config;

  final LineDecoder d;
  final CtcLogProbs lp;
  final LineDecodeConfig cfg;
  CtcCharset get cs => d.charset;
  Lexicon? get lex => d.lexicon;
  UserLexicon? get user => d.userLexicon;

  static final RegExp _split = RegExp(r'^([^A-Za-z0-9]*)(.*?)([^A-Za-z0-9]*)$');
  static final RegExp _plainWord = RegExp(r"^[A-Za-z]+(?:'[A-Za-z]+)?$");
  static final RegExp _gluedWords = RegExp(r"^[A-Za-z]+(?:'[A-Za-z]+)?(?:[.,;:][A-Za-z]+(?:'[A-Za-z]+)?)+$");
  static final RegExp _closing = RegExp(r'''^[.,;:!?)\]}%"']+$''');

  late final CtcScorer _plain = CtcScorer.fromLogProbs(lp, blank: cs.blank);

  /// Scores candidates (look-alike leniency [LineDecodeConfig.confusionMass]).
  late final CtcScorer scorer = _plain.smoothed(_pairClasses, cfg.confusionMass);

  /// Judges one word on its own ([LineDecodeConfig.evidenceMass]; the space
  /// class counts as blank there).
  late final CtcScorer evidenceScorer = () {
    final smooth = _plain.smoothed(_pairClasses, cfg.evidenceMass);
    final sp = cs.space;
    return sp == null ? smooth : smooth.foldedIntoBlank(sp);
  }();

  late final List<(List<int>, List<int>)> _pairClasses = () {
    List<int> classesOf(String ch) => [
          for (final v in {ch, ch.toUpperCase()}) ?cs.indexOf(v),
        ];
    return [
      for (final p in cfg.confusablePairs)
        if (p.length == 2) (classesOf(p[0]), classesOf(p[1])),
    ].where((e) => e.$1.isNotEmpty && e.$2.isNotEmpty).toList();
  }();

  late final double oovPrior = (lex?.logProbAtRank(cfg.oovRank) ?? cfg.fallbackOovLogProb) - cfg.oovPenalty;

  /// The prior of an unknown string of [letters] letters and digits (see
  /// [LineDecodeConfig.oovLetterLogProb]).
  double oovPriorFor(int letters) => oovPrior + cfg.oovLetterLogProb * math.max(0, letters - cfg.oovFreeLetters);

  static final RegExp _letterOrDigit = RegExp(r'[A-Za-z0-9]');

  final Map<String, _Info> _infos = {};
  final Map<String, List<String>> _neighbourCache = {};

  // ---- token knowledge -----------------------------------------------------

  bool _known(String lower) =>
      (user?.contains(lower) ?? false) ||
      (lex?.contains(lower) ?? false) ||
      contractionLogProb(lower) != null;

  /// The prior of a token that is not a plain word: an unknown string, or
  /// the sum of its words' priors when it is words glued by a full stop or
  /// comma written without a space ("cord.Seizure"). As one unknown string
  /// it paid the per-letter cost of a long token, so a reading that dropped
  /// letters won ("cord.Seire"). Kept as one string: parts of one letter
  /// ("e.g") and unknown parts of up to three ("file.txt", where splitting
  /// would make dropping the dot cheaper than keeping it).
  double _tokenPrior(String text, String core) {
    if (_gluedWords.hasMatch(core)) {
      final parts = core.split(RegExp('[.,;:]'));
      if (parts.every((p) => p.length >= 2 && (p.length >= 4 || _known(p)))) {
        return parts.map(_priorOf).reduce((a, b) => a + b);
      }
    }
    return oovPriorFor(_letterOrDigit.allMatches(text).length);
  }

  double _priorOf(String lower) {
    var best = oovPriorFor(lower.replaceAll("'", '').length);
    final base = lex?.logProb(lower);
    if (base != null) best = math.max(best, base);
    final contraction = contractionLogProb(lower);
    if (contraction != null) best = math.max(best, contraction);
    if (user?.contains(lower) ?? false) best = math.max(best, cfg.userLogProb);
    return best;
  }

  List<List<int>>? _setsOf(String s) {
    final sets = <List<int>>[];
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      final options = <int>{};
      for (final v in [ch.toLowerCase(), ch.toUpperCase()]) {
        final i = cs.indexOf(v);
        if (i != null) options.add(i);
      }
      if (options.isEmpty) return null;
      sets.add(options.toList());
    }
    return sets;
  }

  _Info info(String text) => _infos.putIfAbsent(text, () {
        final m = _split.firstMatch(text);
        final lead = m?.group(1) ?? '';
        final core = m?.group(2) ?? text;
        final trail = m?.group(3) ?? '';
        final letters = _plainWord.hasMatch(core) && (lex != null || !(user?.isEmpty ?? true));
        final known = letters && _known(core);
        return _Info(
          lead: lead,
          core: core,
          trail: trail,
          letters: letters,
          known: known,
          prior: letters ? _priorOf(core) : _tokenPrior(text, core),
          sets: _setsOf(text),
        );
      });

  double scoreText(String text) {
    final words = text.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return double.negativeInfinity;
    final space = cs.space;
    final positions = <List<int>>[];
    var prior = 0.0;
    for (var i = 0; i < words.length; i++) {
      final inf = info(words[i].toLowerCase());
      final sets = inf.sets;
      if (sets == null) return double.negativeInfinity;
      if (i > 0) {
        if (space == null) return double.negativeInfinity;
        positions.add([space]);
      }
      positions.addAll(sets);
      prior += inf.prior;
    }
    final ll = scorer.logLikelihood(positions);
    return ll == double.negativeInfinity ? ll : ll + cfg.lambda * prior + cfg.wordBonus * words.length;
  }

  // ---- the model's own reading ---------------------------------------------

  List<_Glyph> _greedy() {
    final out = <_Glyph>[];
    var prev = -1;
    for (var t = 0; t < lp.timesteps; t++) {
      var best = 0;
      var bestV = lp.at(t, 0);
      for (var c = 1; c < lp.classes; c++) {
        final v = lp.at(t, c);
        if (v > bestV) {
          bestV = v;
          best = c;
        }
      }
      final p = math.exp(bestV);
      if (best != cs.blank) {
        if (best == prev) {
          out.last
            ..last = t
            ..prob = math.max(out.last.prob, p);
        } else {
          out.add(_Glyph(best, t, t, p));
        }
      }
      prev = best;
    }
    return out;
  }

  /// Frame ranges `[start, end)` of the stretches between confident gaps.
  List<(int, int)> _stretches() {
    final steps = lp.timesteps;
    final sp = cs.space;
    if (sp == null) return [(0, steps)];
    final cuts = <(int, int)>[];
    var t = 0;
    while (t < steps) {
      if (math.exp(lp.at(t, sp)) >= cfg.cutRunProb) {
        var u = t;
        var peak = 0.0;
        while (u < steps && math.exp(lp.at(u, sp)) >= cfg.cutRunProb) {
          peak = math.max(peak, math.exp(lp.at(u, sp)));
          u++;
        }
        if (peak >= cfg.cutPeak) cuts.add((t, u - 1));
        t = u;
      } else {
        t++;
      }
    }
    final out = <(int, int)>[];
    var start = 0;
    for (final (a, b) in cuts) {
      if (a > start) _addStretch(out, start, a);
      start = b + 1;
    }
    if (steps > start) _addStretch(out, start, steps);
    return out;
  }

  /// Adds the frames [start, end) as a stretch; one that is longer than
  /// [LineDecodeConfig.maxStretchFrames] is cut at its likeliest gap frame
  /// first (the search cost grows with the square of a stretch, and a line
  /// whose gaps are all hesitant would otherwise be one stretch).
  void _addStretch(List<(int, int)> out, int start, int end) {
    final sp = cs.space;
    final minPiece = cfg.minStretchFrames;
    if (sp != null && end - start > cfg.maxStretchFrames && end - start >= 2 * minPiece + 1) {
      var best = -1;
      var bestP = cfg.softCutProb;
      final middle = (start + end) / 2;
      for (var t = start + minPiece; t < end - minPiece; t++) {
        final p = math.exp(lp.at(t, sp));
        if (p > bestP + 1e-9 || (best >= 0 && (p - bestP).abs() <= 1e-9 && (t - middle).abs() < (best - middle).abs())) {
          best = t;
          bestP = p;
        }
      }
      if (best >= 0) {
        _addStretch(out, start, best);
        _addStretch(out, best + 1, end);
        return;
      }
    }
    out.add((start, end));
  }

  // ---- the whole line --------------------------------------------------------

  LineReading run() {
    final glyphs = _greedy();
    final spaceCls = cs.space;
    final rawLine = [
      for (final g in glyphs) cs.charAt(g.cls),
    ].join().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (glyphs.every((g) => g.cls == spaceCls)) {
      return LineReading(text: '', raw: rawLine, confidence: 0, words: const [], timesteps: lp.timesteps);
    }

    // Words with tight frame ranges, in line order.
    final tight = <_Placed>[];
    for (final (a, b) in _stretches()) {
      tight.addAll(_Stretch(this, a, b).decode());
    }
    if (tight.isEmpty) {
      return LineReading(text: '', raw: rawLine, confidence: 0, words: const [], timesteps: lp.timesteps);
    }

    // A lone punctuation mark belongs to the word before it.
    final attached = <_Placed>[];
    for (final w in tight) {
      final core = info(w.tok.text);
      if (attached.isNotEmpty && !core.letters && _closing.hasMatch(w.tok.text)) {
        attached.last.attach(w);
      } else {
        attached.add(w);
      }
    }
    // The model often reads no space after a full stop or a comma
    // (`cord.Seizure,`); such a word is two words, cut after the mark.
    final merged = [for (final w in attached) ...w.splitAfterMarks(glyphs, cs)];

    // Tile the line: boundaries inside the gaps.
    final steps = lp.timesteps;
    final starts = List<int>.filled(merged.length, 0);
    final ends = List<int>.filled(merged.length, steps);
    for (var i = 0; i + 1 < merged.length; i++) {
      final gapStart = math.min(merged[i].last + 1, steps);
      final gapEnd = math.max(merged[i + 1].first, gapStart);
      final cut = (gapStart + cfg.gapSplit * (gapEnd - gapStart)).round().clamp(gapStart, gapEnd);
      ends[i] = cut;
      starts[i + 1] = cut;
    }

    final words = <DecodedWord>[];
    for (var i = 0; i < merged.length; i++) {
      final w = merged[i];
      final text = w.render(this);
      final raw = [
        for (final g in glyphs)
          if (g.cls != spaceCls && g.first >= starts[i] && g.first < ends[i]) cs.charAt(g.cls),
      ].join();
      words.add(DecodedWord(
        text: text,
        raw: raw,
        confidence: w.confidence,
        alternatives: w.alternativeTexts(this, text, raw),
        startFrame: starts[i],
        endFrame: ends[i],
        known: info(w.tok.text).known,
      ));
    }

    // Line confidence: the weakest word, short words counting less.
    var line = 1.0;
    for (final w in words) {
      final letters = w.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length;
      final c = (w.confidence * letters + cfg.lineShrink) / (letters + cfg.lineShrink);
      line = math.min(line, c);
    }
    return LineReading(
      text: words.map((w) => w.text).join(' '),
      raw: rawLine,
      confidence: line.clamp(0.0, 1.0).toDouble(),
      words: words,
      timesteps: lp.timesteps,
    );
  }

  // ---- case ----------------------------------------------------------------

  /// [lower] written with the capitalisation rules of the class comment of
  /// [LineDecoder]: personal words as typed; the model's own spelling is kept
  /// for strings nobody knows; a replacement copies the case pattern of the raw
  /// reading only when the first letters agree; capitals are not kept (the
  /// recogniser tends to shout) unless the word is a known acronym.
  String applyCase(String lower, String rawCore) {
    final form = user?.formOf(lower);
    if (form != null) return form;
    if (cfg.upperAcronyms.contains(lower)) return lower.toUpperCase();
    if (lower.length > 2 && lower.endsWith('s') && cfg.upperAcronyms.contains(lower.substring(0, lower.length - 1))) {
      return '${lower.substring(0, lower.length - 1).toUpperCase()}s';
    }
    if (lower.isEmpty || rawCore.isEmpty) return lower;
    final same = lower == rawCore.toLowerCase();
    if (same && !_known(lower)) return rawCore;
    if (!same && rawCore[0].toLowerCase() != lower[0]) return lower;
    final upperFirst = rawCore[0] != rawCore[0].toLowerCase();
    if (lower.length == 1) return upperFirst ? lower.toUpperCase() : lower;
    final shouting = rawCore.length >= 2 && rawCore == rawCore.toUpperCase();
    if (shouting && cfg.acronyms.contains(lower)) return lower.toUpperCase();
    return upperFirst ? lower[0].toUpperCase() + lower.substring(1) : lower;
  }
}

/// A decoded word with a tight frame range, before the line is tiled.
class _Placed {
  _Placed(this.tok, this.first, this.last, this.confidence, this.alternatives)
      : _suffix = '';

  final _Tok tok;

  /// Frames (of the line) of the first and last letter.
  int first;
  int last;
  final double confidence;
  final List<(String, double)> alternatives;
  String _suffix;

  void attach(_Placed punctuation) {
    _suffix += punctuation.tok.raw;
    last = punctuation.last;
  }

  /// A word, then `, ; : ! ?` or a full stop, then a word, all without a space
  /// (`cord.Seizure,`, `ocd,depression`): split after the mark. At least two
  /// letters must come before the mark, and after a full stop a capital, so
  /// `e.g.`, `U.S.`, `3.5` and `file.txt` stay whole. The frames are cut after
  /// the model's own glyph of the mark ([glyphs]); the word is left whole
  /// when that glyph is not found.
  List<_Placed> splitAfterMarks(List<_Glyph> glyphs, CtcCharset cs) {
    final raw = tok.raw;
    final text = tok.text;
    final m = _markInside.firstMatch(raw);
    if (m == null || text.length != raw.length || text.toLowerCase() != text) return [this];
    final mark = m.group(1)!;
    final at = m.end; // first letter of the second word
    if (mark == '.' && raw[at] == raw[at].toLowerCase()) return [this];
    if (text.substring(0, at).toLowerCase() != raw.substring(0, at).toLowerCase()) return [this];
    _Glyph? markGlyph;
    for (final g in glyphs) {
      if (g.first >= first && g.first <= last && cs.charAt(g.cls) == mark) {
        markGlyph = g;
        break;
      }
    }
    if (markGlyph == null || markGlyph.last >= last) return [this];
    var nextFirst = markGlyph.last + 1;
    for (final g in glyphs) {
      if (g.first > markGlyph.last && g.first <= last && cs.charAt(g.cls).trim().isNotEmpty) {
        nextFirst = g.first;
        break;
      }
    }
    final left = _Placed(_Tok(text.substring(0, at), raw.substring(0, at)), first, markGlyph.last, confidence, const []);
    // The alternatives were readings of the whole token: they fit neither half.
    final right = _Placed(_Tok(text.substring(at), raw.substring(at)), nextFirst, last, confidence, const [])
      .._suffix = _suffix;
    return [left, ...right.splitAfterMarks(glyphs, cs)];
  }

  static final RegExp _markInside = RegExp(r'[A-Za-z]{2}([.,;:!?])(?=[A-Za-z])');

  /// The word as shown: the raw text when nothing was replaced and it is not a
  /// plain word, else [dec]'s case rules.
  String render(_Decode dec) => '${_show(dec, tok.text)}$_suffix';

  String _show(_Decode dec, String text) {
    final i = dec.info(text);
    if (!i.letters) return text == tok.text && tok.raw.toLowerCase() == text ? tok.raw : text;
    return '${i.lead}${dec.applyCase(i.core, _rawCore(tok.raw))}${i.trail}';
  }

  static String _rawCore(String raw) => _Decode._split.firstMatch(raw)?.group(2) ?? raw;

  /// Other readings, best first; [raw] (the model's own reading of the word)
  /// is always worth showing next to a correction.
  List<String> alternativeTexts(_Decode dec, String chosen, String raw) {
    final out = <String>[];
    void offer(String t) {
      if (t.isNotEmpty && t != chosen && !out.contains(t) && out.length < dec.cfg.maxAlternatives) out.add(t);
    }

    final head = <String>[];
    if (raw != chosen && raw.isNotEmpty) head.add(raw);
    for (final (alt, _) in alternatives) {
      head.add('${_show(dec, alt)}$_suffix');
    }
    // The raw reading takes a place even when the list is full.
    for (final t in head) {
      offer(t);
    }
    if (raw != chosen && raw.isNotEmpty && !out.contains(raw)) {
      if (out.length >= dec.cfg.maxAlternatives) out.removeLast();
      out.add(raw);
    }
    return out;
  }
}

/// One stretch of the line between two confident gaps.
class _Stretch {
  _Stretch(this.dec, this.from, this.to);

  final _Decode dec;
  final int from;
  final int to;
  LineDecodeConfig get cfg => dec.cfg;
  CtcCharset get cs => dec.cs;

  late final CtcScorer sc = dec.scorer.slice(from, to);
  late final List<int>? spaceSet = cs.space == null ? null : [cs.space!];
  final Map<String, (double, double)> _memo = {};
  /// The words the model itself read here, with their head start (see
  /// [LineDecodeConfig.knownBonus]), scaled by how clearly it showed them.
  Map<String, double> _own = {};

  List<_Placed> decode() {
    final window = dec.lp.slice(from, to);
    final beams = ctcBeamSearch(
      window,
      cs,
      width: cfg.beamWidth,
      perFrame: cfg.beamPerFrame,
      minProb: cfg.beamMinProb,
    );
    // The readings as token lists (spaces trimmed and collapsed).
    final starts = <List<_Tok>>[];
    for (final b in beams) {
      final words = b.text.split(' ').where((w) => w.isNotEmpty).toList();
      if (words.isEmpty) continue;
      starts.add([for (final w in words) _Tok(w.toLowerCase(), w)]);
    }
    // The model's own best path too: the beam keeps the likeliest strings,
    // and a clear word can fall out of them next to punctuation (Mariam's
    // "cord.Seizure," came out as "cord. Seire,", which scores 2.9 nats
    // below "Seizure").
    final greedy = [
      for (final w in greedyDecode(window, cs).text.split(' '))
        if (w.isNotEmpty) _Tok(w.toLowerCase(), w),
    ];
    if (starts.isEmpty) return const [];
    _own = _headStarts(starts.first);

    // A few starts, each improved on its own; the best outcome wins. One
    // start per word count: readings that differ only in a letter are the
    // ascent's job, readings that differ in where the spaces are it cannot
    // reach from each other.
    final ranked = [for (final s in starts) (s, score(s))]..sort((a, b) => b.$2.compareTo(a.$2));
    final limit = math.max(1, cfg.ascentStarts);
    final seeds = <List<_Tok>>[];
    final counts = <int>{};
    for (final (s, v) in ranked) {
      if (seeds.length >= limit || (v == double.negativeInfinity && seeds.isNotEmpty)) break;
      if (counts.add(s.length)) seeds.add(s);
    }
    bool same(List<_Tok> a, List<_Tok> b) =>
        a.length == b.length && [for (var i = 0; i < a.length; i++) a[i].text == b[i].text].every((e) => e);
    if (greedy.isNotEmpty && score(greedy) > double.negativeInfinity && !seeds.any((s) => same(s, greedy))) {
      seeds.add(greedy);
    }
    if (ranked.first.$2 == double.negativeInfinity) {
      // The beam's reading does not even fit the frames (cannot happen for a
      // reading the search itself produced, but never throw on odd input).
      seeds
        ..clear()
        ..add(starts.first);
    }
    List<_Tok>? best;
    var bestScore = double.negativeInfinity;
    for (final seed in seeds) {
      final improved = _ascend(seed);
      final v = score(improved);
      if (best == null || v > bestScore) {
        best = improved;
        bestScore = v;
      }
    }
    final tokens = best!;
    return _finish(tokens, _firmness(tokens));
  }

  /// Coordinate ascent from [start]: each word in turn is replaced by its best
  /// variant (see [variantsAt]) while that raises the score.
  List<_Tok> _ascend(List<_Tok> start) {
    var tokens = start;
    var firm = _firmness(tokens);
    for (var sweep = 0; sweep < cfg.maxSweeps; sweep++) {
      var changed = false;
      var i = 0;
      while (i < tokens.length) {
        final cur = score(tokens);
        _Variant? win;
        var winScore = cur + 1e-9;
        for (final v in variantsAt(tokens, i, firm)) {
          final s = score(v.tokens) + v.bonus;
          if (s > winScore) {
            winScore = s;
            win = v;
          }
        }
        if (win != null) {
          changed = true;
          final grew = win.tokens.length - tokens.length;
          tokens = win.tokens;
          firm = _firmness(tokens);
          i += grew > 0 ? 1 + grew : 1;
        } else {
          i++;
        }
      }
      if (!changed) break;
    }
    return tokens;
  }

  // ---- scoring ---------------------------------------------------------------

  /// The head start of each word of the model's own reading: the bonus of the
  /// config times how clear the reading is (its weakest letter, from
  /// [LineDecodeConfig.doubtfulProb] = nothing to [LineDecodeConfig.clearProb]
  /// = all of it), so a reading the model doubts is repaired as readily as
  /// the language prior allows.
  Map<String, double> _headStarts(List<_Tok> own) {
    final out = <String, double>{};
    final positions = <List<int>>[];
    final ranges = <(int, int)>[];
    for (var i = 0; i < own.length; i++) {
      final sets = dec.info(own[i].text).sets;
      if (sets == null || (i > 0 && spaceSet == null)) return out;
      if (i > 0) positions.add(spaceSet!);
      ranges.add((positions.length, positions.length + sets.length));
      positions.addAll(sets);
    }
    final spans = dec._plain.slice(from, to).align(positions);
    for (var i = 0; i < own.length; i++) {
      final info = dec.info(own[i].text);
      var clarity = 1.0;
      if (spans != null) {
        final weakest = [for (var k = ranges[i].$1; k < ranges[i].$2; k++) spans[k].prob].reduce(math.min);
        clarity = ((weakest - cfg.doubtfulProb) / (cfg.clearProb - cfg.doubtfulProb)).clamp(cfg.bonusFloor, 1.0);
      }
      // The head start protects a reading nothing explains. A reading that is
      // a look-alike slip away from a word the user taught the app (or from a
      // contraction) is better explained as a misreading of that word.
      final explained = !info.known && info.letters && _explainedByTaughtWord(info.core);
      out[own[i].text] = explained ? 0 : (info.known ? cfg.knownBonus : cfg.unknownBonus) * clarity;
    }
    return out;
  }

  bool _explainedByTaughtWord(String core) {
    final letters = core.replaceAll("'", '').length;
    final edits = cfg.maxUserEditsFor(letters);
    if (edits == 0) return false;
    if (dec.user?.nearby(core, edits).isNotEmpty ?? false) return true;
    final contractionEdits = cfg.maxEditsFor(letters);
    for (final plain in contractionPlainForms) {
      if ((plain.length - core.length).abs() <= contractionEdits && levenshtein(core, plain) <= contractionEdits) return true;
    }
    return false;
  }

  double score(List<_Tok> tokens) => _scored(tokens).$1;

  /// [score] without the head start of the model's own words: the probability
  /// of a reading among its rivals must not depend on a tie-breaking
  /// heuristic.
  double scoreWithoutBonus(List<_Tok> tokens) {
    final v = _scored(tokens);
    return v.$1 - v.$2;
  }

  (double, double) _scored(List<_Tok> tokens) {
    final key = tokens.map((t) => t.text).join(' ');
    return _memo[key] ??= _score(tokens);
  }

  /// (score, the part of it that is the head start).
  (double, double) _score(List<_Tok> tokens) {
    final positions = <List<int>>[];
    var prior = 0.0;
    var bonus = 0.0;
    for (var i = 0; i < tokens.length; i++) {
      final info = dec.info(tokens[i].text);
      final sets = info.sets;
      if (sets == null) return (double.negativeInfinity, 0);
      if (i > 0) {
        if (spaceSet == null) return (double.negativeInfinity, 0);
        positions.add(spaceSet!);
      }
      positions.addAll(sets);
      prior += info.prior;
      bonus += _own[tokens[i].text] ?? 0;
    }
    final ll = sc.logLikelihood(positions);
    if (ll == double.negativeInfinity) return (ll, 0);
    return (ll + cfg.lambda * prior + cfg.wordBonus * tokens.length + bonus, bonus);
  }

  /// Per word: a known word every letter of which is clearly shown.
  List<bool> _firmness(List<_Tok> tokens) {
    final positions = <List<int>>[];
    final ranges = <(int, int)>[];
    for (var i = 0; i < tokens.length; i++) {
      final sets = dec.info(tokens[i].text).sets;
      if (sets == null || (i > 0 && spaceSet == null)) return List<bool>.filled(tokens.length, false);
      if (i > 0) positions.add(spaceSet!);
      ranges.add((positions.length, positions.length + sets.length));
      positions.addAll(sets);
    }
    final spans = sc.align(positions);
    if (spans == null) return List<bool>.filled(tokens.length, false);
    return [
      for (var i = 0; i < tokens.length; i++)
        dec.info(tokens[i].text).known &&
            [for (var k = ranges[i].$1; k < ranges[i].$2; k++) spans[k].prob].reduce(math.min) >= cfg.firmProb,
    ];
  }

  // ---- candidates --------------------------------------------------------------

  /// Lowercase words that may stand for the plain word [core].
  List<String> neighbours(String core) => dec._neighbourCache.putIfAbsent(core, () {
        final out = <String>{};
        final letters = core.replaceAll("'", '').length;
        out.addAll(dec.d._lexiconNeighbours(core, cfg.maxEditsFor(letters)));
        final user = dec.user;
        if (user != null) {
          for (final form in user.nearby(core, cfg.maxUserEditsFor(letters))) {
            out.add(form.toLowerCase());
          }
        }
        // contractions written without their apostrophe
        final contractionEdits = cfg.maxEditsFor(letters);
        for (final plain in contractionPlainForms) {
          if ((plain.length - core.length).abs() <= contractionEdits && levenshtein(core, plain) <= contractionEdits) out.add(plain);
        }
        out.remove(core);
        return out.toList();
      });

  /// The best way to write [core] as known words (word-break dynamic
  /// programme over the sum of the word priors), at most
  /// [LineDecodeConfig.maxSegmentPieces] of them; null when there is none.
  List<String>? _segmentation(String core) {
    final n = core.length;
    final best = List<double>.filled(n + 1, double.negativeInfinity);
    final from = List<int>.filled(n + 1, -1);
    final count = List<int>.filled(n + 1, 0);
    best[0] = 0;
    for (var i = 1; i <= n; i++) {
      for (var j = i - 1; j >= 0; j--) {
        if (best[j] == double.negativeInfinity || count[j] >= cfg.maxSegmentPieces) continue;
        final piece = core.substring(j, i);
        if (!_splitHalfOk(piece)) continue;
        final v = best[j] + dec._priorOf(piece);
        if (v > best[i]) {
          best[i] = v;
          from[i] = j;
          count[i] = count[j] + 1;
        }
      }
    }
    if (best[n] == double.negativeInfinity) return null;
    final out = <String>[];
    for (var i = n; i > 0; i = from[i]) {
      out.add(core.substring(from[i], i));
    }
    return out.reversed.toList();
  }

  bool _splitHalfOk(String half) {
    if (half.length == 1) return half == 'a' || half == 'i';
    return dec._known(half);
  }

  Iterable<_Variant> variantsAt(List<_Tok> tokens, int i, List<bool> firm) sync* {
    final tok = tokens[i];
    final info = dec.info(tok.text);
    if (info.letters && !firm[i]) {
      for (final cand in neighbours(info.core)) {
        final text = '${info.lead}$cand${info.trail}';
        yield _Variant(_replaced(tokens, i, 1, [_Tok(text, tok.raw)]), substitute: text);
      }
      if (spaceSet != null && !info.known && !info.core.contains("'")) {
        for (var p = 1; p < info.core.length; p++) {
          final a = info.core.substring(0, p);
          final b = info.core.substring(p);
          if (!_splitHalfOk(a) || !_splitHalfOk(b)) continue;
          yield _Variant(
            _replaced(tokens, i, 1, [
              _Tok('${info.lead}$a', tok.raw),
              _Tok('$b${info.trail}', b),
            ]),
            bonus: cfg.splitBonus,
          );
        }
        // Several words run together ("thecatandthe"): the likeliest way to
        // write the token as three or more known words.
        final pieces = info.core.length >= 6 ? _segmentation(info.core) : null;
        if (pieces != null && pieces.length >= 3) {
          yield _Variant(
            _replaced(tokens, i, 1, [
              for (var k = 0; k < pieces.length; k++)
                _Tok(
                  '${k == 0 ? info.lead : ''}${pieces[k]}${k == pieces.length - 1 ? info.trail : ''}',
                  k == 0 ? tok.raw : pieces[k],
                ),
            ]),
            bonus: cfg.splitBonus * (pieces.length - 1),
          );
        }
      }
    }
    if (spaceSet != null && i + 1 < tokens.length && !(firm[i] && firm[i + 1])) {
      final next = tokens[i + 1];
      final ni = dec.info(next.text);
      if (info.letters && ni.letters && info.trail.isEmpty && ni.lead.isEmpty) {
        final joined = info.core + ni.core;
        if (dec._known(joined)) {
          yield _Variant(_replaced(tokens, i, 2, [_Tok('${info.lead}$joined${ni.trail}', tok.raw)]));
        }
      }
    }
  }

  static List<_Tok> _replaced(List<_Tok> tokens, int at, int count, List<_Tok> with_) =>
      [...tokens.sublist(0, at), ...with_, ...tokens.sublist(at + count)];

  // ---- the outcome ------------------------------------------------------------

  List<_Placed> _finish(List<_Tok> tokens, List<bool> firm) {
    final positions = <List<int>>[];
    final ranges = <(int, int)>[];
    for (var i = 0; i < tokens.length; i++) {
      final sets = dec.info(tokens[i].text).sets!;
      if (i > 0) positions.add(spaceSet!);
      ranges.add((positions.length, positions.length + sets.length));
      positions.addAll(sets);
    }
    final evidenceSc = dec.evidenceScorer.slice(from, to);
    final spans = evidenceSc.align(positions);
    final cur = scoreWithoutBonus(tokens);
    final out = <_Placed>[];
    for (var i = 0; i < tokens.length; i++) {
      // Alternatives and the posterior of this word among them.
      final scored = <String, double>{};
      var z = 1.0; // the chosen reading itself, relative to cur
      final seen = <String>{tokens.map((t) => t.text).join(' ')};
      for (final v in variantsAt(tokens, i, firm)) {
        final key = v.tokens.map((t) => t.text).join(' ');
        if (!seen.add(key)) continue;
        final s = scoreWithoutBonus(v.tokens) + v.bonus;
        if (s == double.negativeInfinity) continue;
        z += math.exp(s - cur);
        final sub = v.substitute;
        if (sub != null) scored[sub] = s;
      }
      final posterior = 1 / z;
      final alts = scored.entries.where((e) => e.value >= cur - cfg.alternativeGap).toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // Evidence: the CTC likelihood of the word alone on the frames around
      // it, per letter (see LineDecodeConfig.confidenceLengthExponent).
      var first = 0;
      var last = to - from - 1;
      var evidence = 0.0;
      final (a, b) = ranges[i];
      if (spans != null) {
        first = spans[a].firstFrame;
        last = spans[b - 1].lastFrame;
        final winStart = i == 0 ? 0 : (spans[ranges[i - 1].$2 - 1].lastFrame + 1 + first) ~/ 2;
        final winEnd = i + 1 == tokens.length ? to - from : (last + 1 + spans[ranges[i + 1].$1].firstFrame) ~/ 2;
        final sets = positions.sublist(a, b);
        var ll = evidenceSc.slice(winStart, math.max(winEnd, last + 1)).logLikelihood(sets);
        if (ll == double.negativeInfinity) {
          ll = 0;
          for (var k = a; k < b; k++) {
            ll += math.log(math.max(spans[k].prob, 1e-6));
          }
        }
        evidence = math.exp(ll / math.pow(b - a, cfg.confidenceLengthExponent));
        final taught = dec.info(tokens[i].text);
        if (taught.letters && (dec.user?.contains(taught.core) ?? false)) {
          evidence = math.pow(evidence, cfg.taughtEvidenceExponent).toDouble();
        }
      }
      final conf = (evidence * math.sqrt(posterior)).clamp(0.0, 1.0).toDouble();
      out.add(_Placed(
        tokens[i],
        from + first,
        from + last,
        conf.isNaN ? 0.0 : conf,
        [for (final e in alts.take(cfg.maxAlternatives)) (e.key, e.value)],
      ));
    }
    return out;
  }
}
