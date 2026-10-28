import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Probabilities below this are clamped before taking the logarithm, so a
/// single impossible frame costs a bounded number of nats (about 18) and the
/// likelihood of a wrong candidate stays finite and comparable.
const double ctcProbFloor = 1e-8;

/// Maps the recogniser's class indices to characters (`assets/htr/charset.json`).
///
/// The bundled PP-OCRv5 model has 438 classes: class 0 is the CTC blank,
/// classes 1..436 are the characters of the model's `character_dict` in file
/// order, and the last class (437) is the space. [symbols] holds the text of
/// every class (the empty string for the blank).
class CtcCharset {
  CtcCharset(List<String> symbols, {this.blank = 0, this.space})
      : assert(blank >= 0 && blank < symbols.length),
        symbols = List.unmodifiable(symbols) {
    for (var i = 0; i < this.symbols.length; i++) {
      if (i == blank) continue;
      _index.putIfAbsent(this.symbols[i], () => i);
    }
  }

  /// Parses `charset.json`: `{"blank": 0, "space": 437, "charset": [...]}`.
  /// `blank` defaults to 0 and `space` to the class whose text is `" "`.
  factory CtcCharset.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final symbols = [for (final c in map['charset'] as List<dynamic>) c as String];
    final blank = (map['blank'] as num?)?.toInt() ?? 0;
    final space = (map['space'] as num?)?.toInt() ?? (symbols.contains(' ') ? symbols.indexOf(' ') : null);
    return CtcCharset(symbols, blank: blank, space: space);
  }

  /// Old name of [CtcCharset.fromJson].
  factory CtcCharset.fromConfigJson(String json) => CtcCharset.fromJson(json);

  /// Text of each class, indexed by class; the blank is `''`.
  final List<String> symbols;
  final int blank;

  /// Class of the space character, if the model has one. Word images never
  /// contain spaces, so [CtcLogProbs.fromProbabilities] can fold it into the
  /// blank.
  final int? space;
  final Map<String, int> _index = {};

  int get classes => symbols.length;

  /// Class index of [ch], or null when the model cannot emit it.
  int? indexOf(String ch) => _index[ch];

  /// Character of class [i]; empty for the blank and for unknown indices.
  String charAt(int i) => i >= 0 && i < symbols.length && i != blank ? symbols[i] : '';

  /// Class indices of [text], or null when any character is not in the charset.
  List<int>? encode(String text) {
    final out = <int>[];
    for (final r in text.runes) {
      final i = _index[String.fromCharCode(r)];
      if (i == null) return null;
      out.add(i);
    }
    return out;
  }
}

/// Per-timestep log-probabilities of one image: row-major `[t][class]`.
class CtcLogProbs {
  CtcLogProbs(this.data, {required this.timesteps, required this.classes})
      : assert(data.length == timesteps * classes);

  /// Builds from a flat list of log-probabilities whose length is a multiple
  /// of [classes].
  factory CtcLogProbs.fromFlat(List<num> flat, int classes) {
    final values = flat is List<double> ? flat : [for (final v in flat) v.toDouble()];
    return CtcLogProbs(values, timesteps: values.length ~/ classes, classes: classes);
  }

  /// Builds from the model's softmax **probabilities** (flat, `[t][class]`).
  /// Values are clamped to [floor] before the logarithm. When [foldIntoBlank]
  /// is given (the space class), that class's probability is added to the
  /// blank's and the class itself is zeroed: a word image holds no spaces, so
  /// a "space" frame means "no letter here".
  factory CtcLogProbs.fromProbabilities(
    List<num> probs,
    int classes, {
    int blank = 0,
    int? foldIntoBlank,
    double floor = ctcProbFloor,
  }) {
    final steps = probs.length ~/ classes;
    final out = List<double>.filled(steps * classes, 0);
    final logFloor = math.log(floor);
    for (var t = 0; t < steps; t++) {
      final base = t * classes;
      for (var c = 0; c < classes; c++) {
        var p = probs[base + c].toDouble();
        if (c == blank && foldIntoBlank != null) p += probs[base + foldIntoBlank].toDouble();
        out[base + c] = c == foldIntoBlank ? logFloor : (p <= floor ? logFloor : math.log(p));
      }
    }
    return CtcLogProbs(out, timesteps: steps, classes: classes);
  }

  final List<double> data;
  final int timesteps;
  final int classes;

  double at(int t, int c) => data[t * classes + c];

  /// Timesteps [start, end) as a matrix of their own (a copy). Used to score
  /// one word of a line on the frames it occupies.
  CtcLogProbs slice(int start, int end) {
    final from = start.clamp(0, timesteps);
    final to = end.clamp(from, timesteps);
    return CtcLogProbs(
      data.sublist(from * classes, to * classes),
      timesteps: to - from,
      classes: classes,
    );
  }
}

/// Best-path (greedy) decoding of one image.
class CtcGreedy {
  const CtcGreedy({
    required this.text,
    required this.indices,
    required this.charProbs,
  });

  static const CtcGreedy empty = CtcGreedy(text: '', indices: [], charProbs: []);

  final String text;

  /// Class index of each decoded character.
  final List<int> indices;

  /// Probability (0..1) of each decoded character: the highest frame
  /// probability within the run of frames that produced it.
  final List<double> charProbs;

  /// Geometric mean of [charProbs], 0 for the empty string.
  double get confidence {
    if (charProbs.isEmpty) return 0;
    var sum = 0.0;
    for (final p in charProbs) {
      sum += math.log(math.max(p, 1e-12));
    }
    return math.exp(sum / charProbs.length);
  }
}

/// Collapses repeats and removes blanks from the per-frame argmax.
CtcGreedy greedyDecode(CtcLogProbs lp, CtcCharset charset) {
  final buf = StringBuffer();
  final indices = <int>[];
  final probs = <double>[];
  var prev = -1;
  var run = false; // inside a run that produced a character
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
    if (best == prev) {
      if (run && probs.isNotEmpty && p > probs.last) probs[probs.length - 1] = p;
    } else if (best != charset.blank) {
      buf.write(charset.charAt(best));
      indices.add(best);
      probs.add(p);
      run = true;
    } else {
      run = false;
    }
    prev = best;
  }
  return CtcGreedy(text: buf.toString(), indices: indices, charProbs: probs);
}

double _logSumExp2(double a, double b) {
  if (a == double.negativeInfinity) return b;
  if (b == double.negativeInfinity) return a;
  final m = math.max(a, b);
  return m + math.log(math.exp(a - m) + math.exp(b - m));
}

/// Log-likelihood `ln P(labels | image)` of a label sequence under the CTC
/// model: the log of the summed probability of every frame alignment that
/// collapses to [labels] (forward algorithm in log space).
///
/// Each position of [positions] is the set of classes accepted there (a
/// single class for exact matching; `{a, A}` makes the score case
/// insensitive). Two neighbouring positions that share a class must be
/// separated by a blank frame, as in the usual CTC rules. Returns negative
/// infinity when the sequence cannot fit in the available timesteps.
double ctcLogLikelihoodSets(
  CtcLogProbs lp,
  List<List<int>> positions, {
  required int blank,
}) {
  final n = positions.length;
  final steps = lp.timesteps;
  if (steps == 0) return n == 0 ? 0 : double.negativeInfinity;
  if (n == 0) {
    var sum = 0.0;
    for (var t = 0; t < steps; t++) {
      sum += lp.at(t, blank);
    }
    return sum;
  }
  final states = 2 * n + 1;

  // emit[t * n + i]: log probability that frame t shows label position i.
  final emit = List<double>.filled(steps * n, 0);
  for (var t = 0; t < steps; t++) {
    for (var i = 0; i < n; i++) {
      var v = double.negativeInfinity;
      for (final c in positions[i]) {
        v = _logSumExp2(v, lp.at(t, c));
      }
      emit[t * n + i] = v;
    }
  }

  // canSkip[i]: the transition from label i-1 straight to label i (without a
  // blank between) is allowed, i.e. they are different characters.
  final canSkip = List<bool>.filled(n, false);
  for (var i = 1; i < n; i++) {
    canSkip[i] = !positions[i].any(positions[i - 1].contains);
  }

  var prev = List<double>.filled(states, double.negativeInfinity);
  var cur = List<double>.filled(states, double.negativeInfinity);
  prev[0] = lp.at(0, blank);
  prev[1] = emit[0];
  for (var t = 1; t < steps; t++) {
    for (var s = 0; s < states; s++) {
      final isBlank = s.isEven;
      var a = prev[s];
      if (s >= 1) a = _logSumExp2(a, prev[s - 1]);
      if (!isBlank && s >= 3 && canSkip[s ~/ 2]) a = _logSumExp2(a, prev[s - 2]);
      if (a == double.negativeInfinity) {
        cur[s] = a;
      } else {
        cur[s] = a + (isBlank ? lp.at(t, blank) : emit[t * n + s ~/ 2]);
      }
    }
    final tmp = prev;
    prev = cur;
    cur = tmp;
  }
  return _logSumExp2(prev[states - 1], prev[states - 2]);
}

/// [ctcLogLikelihoodSets] for an exact class sequence.
double ctcLogLikelihood(CtcLogProbs lp, List<int> labels, {required int blank}) =>
    ctcLogLikelihoodSets(lp, [for (final l in labels) [l]], blank: blank);

/// One reading found by [ctcBeamSearch].
class CtcBeamReading {
  const CtcBeamReading({required this.text, required this.indices, required this.logProb});

  final String text;
  final List<int> indices;

  /// `ln P(text | image)`: all alignments that collapse to [text], within
  /// the pruned search.
  final double logProb;
}

/// CTC prefix beam search: the [width] most probable distinct readings, best
/// first. Per frame only the [perFrame] likeliest classes (and none below
/// [minProb]) are extended, which keeps the search at a few thousand steps
/// for a word image.
List<CtcBeamReading> ctcBeamSearch(
  CtcLogProbs lp,
  CtcCharset charset, {
  int width = 5,
  int perFrame = 6,
  double minProb = 1e-3,
}) {
  final blank = charset.blank;
  final minLog = math.log(minProb);

  // Beams keyed by their class sequence (as a string of code units).
  var beams = <String, _Beam>{'': _Beam(const [], 0, double.negativeInfinity)};
  // For each beam: log P ending in blank (pb) and in a character (pnb).
  var order = <String>[''];
  final top = List<int>.filled(perFrame, 0);
  for (var t = 0; t < lp.timesteps; t++) {
    // The perFrame best classes of this frame, best first.
    var count = 0;
    for (var c = 0; c < lp.classes; c++) {
      final v = lp.at(t, c);
      if (count == perFrame && v <= lp.at(t, top[count - 1])) continue;
      var pos = count < perFrame ? count : perFrame - 1;
      if (count < perFrame) count++;
      while (pos > 0 && lp.at(t, top[pos - 1]) < v) {
        top[pos] = top[pos - 1];
        pos--;
      }
      top[pos] = c;
    }
    final next = <String, _Beam>{};
    _Beam entry(String key, List<int> seq) => next.putIfAbsent(key, () => _Beam(seq, double.negativeInfinity, double.negativeInfinity));
    for (final key in order) {
      final beam = beams[key]!;
      final total = _logSumExp2(beam.pb, beam.pnb);
      for (var k = 0; k < count; k++) {
        final c = top[k];
        final v = lp.at(t, c);
        if (v < minLog && k > 0) break;
        if (c == blank) {
          final e = entry(key, beam.seq);
          e.pb = _logSumExp2(e.pb, total + v);
          continue;
        }
        final last = beam.seq.isEmpty ? -1 : beam.seq.last;
        final extKey = '$key${String.fromCharCode(c)}';
        final ext = entry(extKey, [...beam.seq, c]);
        if (c == last) {
          // A repeated class starts a new character only after a blank; a
          // frame right after the same class stays in the same character.
          ext.pnb = _logSumExp2(ext.pnb, beam.pb + v);
          final same = entry(key, beam.seq);
          same.pnb = _logSumExp2(same.pnb, beam.pnb + v);
        } else {
          ext.pnb = _logSumExp2(ext.pnb, total + v);
        }
      }
    }
    final ranked = next.keys.toList()
      ..sort((a, b) => _logSumExp2(next[b]!.pb, next[b]!.pnb).compareTo(_logSumExp2(next[a]!.pb, next[a]!.pnb)));
    order = ranked.length > width ? ranked.sublist(0, width) : ranked;
    beams = {for (final k in order) k: next[k]!};
  }
  return [
    for (final k in order)
      CtcBeamReading(
        text: [for (final c in beams[k]!.seq) charset.charAt(c)].join(),
        indices: beams[k]!.seq,
        logProb: _logSumExp2(beams[k]!.pb, beams[k]!.pnb),
      ),
  ];
}

class _Beam {
  _Beam(this.seq, this.pb, this.pnb);

  final List<int> seq;
  double pb;
  double pnb;
}

/// Where one label of a sequence sits in the best alignment (see
/// [CtcScorer.align]).
class CtcLabelSpan {
  const CtcLabelSpan({required this.firstFrame, required this.lastFrame, required this.prob});

  /// First and last frame (inclusive) the best path spends on the label.
  final int firstFrame;
  final int lastFrame;

  /// The largest probability the label's accepted classes reach on those
  /// frames (0..1): how clearly the image shows this label.
  final double prob;
}

/// Fast repeated scoring of label sequences on ONE probability matrix.
///
/// [ctcLogLikelihoodSets] works in the log domain (an `exp` and a `log` per
/// lattice cell), which is fine for a handful of readings but too slow for
/// the hundreds of candidates a line decoder compares. This keeps the
/// probabilities themselves and runs the forward algorithm in the linear
/// domain with a per-frame rescaling, which gives the same numbers (see the
/// tests) several times faster.
class CtcScorer {
  CtcScorer._(this._p, this.timesteps, this.classes, this.blank);

  /// Linear-domain copy of [lp] (probabilities below [ctcProbFloor] are
  /// raised to it, like [CtcLogProbs.fromProbabilities] does).
  factory CtcScorer.fromLogProbs(CtcLogProbs lp, {required int blank}) {
    final p = Float64List(lp.data.length);
    for (var i = 0; i < p.length; i++) {
      p[i] = math.max(math.exp(lp.data[i]), ctcProbFloor);
    }
    return CtcScorer._(p, lp.timesteps, lp.classes, blank);
  }

  final Float64List _p;
  final int timesteps;
  final int classes;
  final int blank;

  /// Probability of class [c] at frame [t].
  double prob(int t, int c) => _p[t * classes + c];

  /// Timesteps [start, end) as a scorer of their own.
  CtcScorer slice(int start, int end) {
    final from = start.clamp(0, timesteps);
    final to = end.clamp(from, timesteps);
    return CtcScorer._(Float64List.sublistView(_p, from * classes, to * classes), to - from, classes, blank);
  }

  /// A copy in which every frame lends [mass] of the probability of one class
  /// of a pair to the other (a pseudo-likelihood: nothing is renormalised, so
  /// a reading the model already supports never loses probability). Each
  /// pair is `(classes of letter a, classes of letter b)`, one entry per
  /// case; the loan is spread over the entries so the case-insensitive sum of
  /// a letter grows by `mass * (sum of the other letter)`.
  CtcScorer smoothed(List<(List<int>, List<int>)> pairs, double mass) {
    if (mass <= 0 || pairs.isEmpty) return this;
    final out = Float64List.fromList(_p);
    for (var t = 0; t < timesteps; t++) {
      final base = t * classes;
      for (final (a, b) in pairs) {
        var fa = 0.0, fb = 0.0;
        for (final i in a) {
          fa += _p[base + i];
        }
        for (final i in b) {
          fb += _p[base + i];
        }
        if (fa < 1e-6 && fb < 1e-6) continue;
        for (final i in a) {
          out[base + i] += mass * fb / a.length;
        }
        for (final i in b) {
          out[base + i] += mass * fa / b.length;
        }
      }
    }
    return CtcScorer._(out, timesteps, classes, blank);
  }

  /// A copy in which class [cls] (the space) counts as "no letter here": its
  /// probability is added to the blank's and the class is floored. Used to
  /// judge one word on its own, where the neighbouring gaps are not part of
  /// the word.
  CtcScorer foldedIntoBlank(int cls) {
    final out = Float64List.fromList(_p);
    for (var t = 0; t < timesteps; t++) {
      final base = t * classes;
      out[base + blank] += _p[base + cls];
      out[base + cls] = ctcProbFloor;
    }
    return CtcScorer._(out, timesteps, classes, blank);
  }

  double _emit(int t, List<int> set) {
    final base = t * classes;
    if (set.length == 1) return _p[base + set[0]];
    var v = 0.0;
    for (final c in set) {
      v += _p[base + c];
    }
    return v;
  }

  /// `ln P(labels | image)` like [ctcLogLikelihoodSets] (same rules: each
  /// position is a set of accepted classes, neighbours that share a class
  /// need a blank between them). Negative infinity when the labels do not
  /// fit the frames.
  double logLikelihood(List<List<int>> positions) {
    final n = positions.length;
    if (timesteps == 0) return n == 0 ? 0 : double.negativeInfinity;
    if (n == 0) {
      var sum = 0.0;
      for (var t = 0; t < timesteps; t++) {
        sum += math.log(_p[t * classes + blank]);
      }
      return sum;
    }
    final states = 2 * n + 1;
    final canSkip = List<bool>.filled(n, false);
    for (var i = 1; i < n; i++) {
      canSkip[i] = !positions[i].any(positions[i - 1].contains);
    }
    var prev = Float64List(states);
    var cur = Float64List(states);
    var logScale = 0.0;
    prev[0] = _p[blank];
    prev[1] = _emit(0, positions[0]);
    final norm0 = prev[0] + prev[1];
    logScale += math.log(norm0);
    prev[0] /= norm0;
    prev[1] /= norm0;
    for (var t = 1; t < timesteps; t++) {
      final pb = _p[t * classes + blank];
      var sum = 0.0;
      for (var s = 0; s < states; s++) {
        double v;
        if (s.isEven) {
          v = (s >= 1 ? prev[s] + prev[s - 1] : prev[s]) * pb;
        } else {
          var a = prev[s] + prev[s - 1];
          if (s >= 3 && canSkip[s >> 1]) a += prev[s - 2];
          v = a == 0 ? 0 : a * _emit(t, positions[s >> 1]);
        }
        cur[s] = v;
        sum += v;
      }
      if (sum <= 0) return double.negativeInfinity;
      logScale += math.log(sum);
      final inv = 1 / sum;
      for (var s = 0; s < states; s++) {
        cur[s] *= inv;
      }
      final tmp = prev;
      prev = cur;
      cur = tmp;
    }
    final end = prev[states - 1] + prev[states - 2];
    if (end <= 0) return double.negativeInfinity;
    return logScale + math.log(end);
  }

  /// The best (Viterbi) alignment of [positions] to the frames: for each
  /// label the frames its state occupies and how clearly it shows there.
  /// Null when the labels do not fit.
  List<CtcLabelSpan>? align(List<List<int>> positions) {
    final n = positions.length;
    if (n == 0) return const [];
    if (timesteps == 0) return null;
    final states = 2 * n + 1;
    final canSkip = List<bool>.filled(n, false);
    for (var i = 1; i < n; i++) {
      canSkip[i] = !positions[i].any(positions[i - 1].contains);
    }
    const neg = double.negativeInfinity;
    // back[t * states + s]: how many states below s the best predecessor is.
    final back = Uint8List(timesteps * states);
    var prev = Float64List(states)..fillRange(0, states, neg);
    var cur = Float64List(states);
    prev[0] = math.log(_p[blank]);
    prev[1] = math.log(_emit(0, positions[0]));
    for (var t = 1; t < timesteps; t++) {
      for (var s = 0; s < states; s++) {
        var best = prev[s];
        var from = 0;
        if (s >= 1 && prev[s - 1] > best) {
          best = prev[s - 1];
          from = 1;
        }
        if (s.isOdd && s >= 3 && canSkip[s >> 1] && prev[s - 2] > best) {
          best = prev[s - 2];
          from = 2;
        }
        back[t * states + s] = from;
        if (best == neg) {
          cur[s] = neg;
        } else {
          final e = s.isEven ? _p[t * classes + blank] : _emit(t, positions[s >> 1]);
          cur[s] = best + math.log(e);
        }
      }
      final tmp = prev;
      prev = cur;
      cur = tmp;
    }
    var s = prev[states - 1] >= prev[states - 2] ? states - 1 : states - 2;
    if (prev[s] == neg) return null;
    final first = List<int>.filled(n, timesteps);
    final last = List<int>.filled(n, -1);
    for (var t = timesteps - 1; t >= 0; t--) {
      if (s.isOdd) {
        final i = s >> 1;
        if (t < first[i]) first[i] = t;
        if (t > last[i]) last[i] = t;
      }
      s -= back[t * states + s];
    }
    return [
      for (var i = 0; i < n; i++)
        if (last[i] < 0)
          const CtcLabelSpan(firstFrame: 0, lastFrame: 0, prob: 0)
        else
          CtcLabelSpan(
            firstFrame: first[i],
            lastFrame: last[i],
            prob: [for (var t = first[i]; t <= last[i]; t++) _emit(t, positions[i])].reduce(math.max),
          ),
    ];
  }
}
