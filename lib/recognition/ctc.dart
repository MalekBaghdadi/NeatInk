import 'dart:convert';
import 'dart:math' as math;

/// Maps the recogniser's class indices to characters (`assets/htr/config.json`).
///
/// The model has `chars.length + 1` classes: one per charset entry, in order,
/// plus the CTC blank as the **last** class (verified in docs/htr-model-notes.md).
class CtcCharset {
  CtcCharset(List<String> chars) : chars = List.unmodifiable(chars) {
    for (var i = 0; i < this.chars.length; i++) {
      _index[this.chars[i]] = i;
    }
  }

  /// Parses the `charset` array of the model's `config.json`.
  factory CtcCharset.fromConfigJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final chars = [for (final c in map['charset'] as List<dynamic>) c as String];
    return CtcCharset(chars);
  }

  final List<String> chars;
  final Map<String, int> _index = {};

  int get blank => chars.length;
  int get classes => chars.length + 1;

  /// Class index of [ch], or null when the model cannot emit it.
  int? indexOf(String ch) => _index[ch];

  /// Character of class [i]; empty for the blank.
  String charAt(int i) => i >= 0 && i < chars.length ? chars[i] : '';

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

/// Per-timestep log-probabilities of one image: row-major `[t][class]`, as
/// returned by the plugin (`timesteps * classes` values).
class CtcLogProbs {
  CtcLogProbs(this.data, {required this.timesteps, required this.classes})
      : assert(data.length == timesteps * classes);

  /// Builds from a flat list whose length is a multiple of [classes].
  factory CtcLogProbs.fromFlat(List<num> flat, int classes) {
    final values = flat is List<double> ? flat : [for (final v in flat) v.toDouble()];
    return CtcLogProbs(values, timesteps: values.length ~/ classes, classes: classes);
  }

  final List<double> data;
  final int timesteps;
  final int classes;

  double at(int t, int c) => data[t * classes + c];
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
