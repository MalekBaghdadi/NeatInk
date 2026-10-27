import 'dart:math' as math;

import 'package:neatink/recognition/ctc.dart';

/// A reduced copy of the bundled model's class table (assets/htr/charset.json):
/// same layout (blank first, digits, A-Z, a-z, punctuation, space last), fewer
/// symbols. 95 classes, blank 0, space 94. (No underscore: the fixtures use `_`
/// as the key of the blank.)
CtcCharset testCharset() => CtcCharset(
      [
        '',
        ...'0123456789'.split(''),
        for (var c = 65; c <= 90; c++) String.fromCharCode(c),
        for (var c = 97; c <= 122; c++) String.fromCharCode(c),
        ...'!"#\$%&\'()*+,-./:;<=>?@[\\]`{|}^~'.split(''),
        ' ',
      ],
      blank: 0,
      space: 94,
    );

/// Builds log-probabilities from per-frame probabilities. Each frame maps a
/// character (`_` is the blank) to its probability; the rest of the mass is
/// spread evenly over the remaining classes, so every frame sums to 1. Like
/// the real pipeline, values below [ctcProbFloor] are clamped.
CtcLogProbs framesOf(CtcCharset cs, List<Map<String, double>> frames) {
  final data = <double>[];
  for (final f in frames) {
    final given = f.values.fold(0.0, (a, b) => a + b);
    assert(given <= 1.0 + 1e-9);
    final rest = (1 - given) / (cs.classes - f.length);
    for (var c = 0; c < cs.classes; c++) {
      final ch = c == cs.blank ? '_' : cs.charAt(c);
      data.add(math.log(math.max(f[ch] ?? rest, ctcProbFloor)));
    }
  }
  return CtcLogProbs(data, timesteps: frames.length, classes: cs.classes);
}

/// The same frames as flat probabilities `[t][class]` (what the plugin
/// sends), for tests of the channel.
List<double> probabilitiesOf(CtcCharset cs, List<Map<String, double>> frames) {
  final lp = framesOf(cs, frames);
  return [for (final v in lp.data) math.exp(v)];
}

/// Frames that spell [text] confidently: each character for two frames,
/// separated by a blank frame.
List<Map<String, double>> spell(String text, {double p = 0.9}) {
  final out = <Map<String, double>>[];
  for (final ch in text.split('')) {
    out.add({ch: p, '_': 0.05});
    out.add({ch: p, '_': 0.05});
    out.add({'_': p});
  }
  return out;
}

/// Frames spelling [text] where selected positions are ambiguous: [maybe]
/// maps a position to the competing letters and their probabilities (e.g.
/// `{2: {'s': 0.5, 'r': 0.45}}`). Other positions are read with [p]. Like
/// the real model, each character takes one frame, followed by a blank.
List<Map<String, double>> spellWith(
  String text,
  Map<int, Map<String, double>> maybe, {
  double p = 0.9,
}) {
  final out = <Map<String, double>>[];
  final chars = text.split('');
  for (var i = 0; i < chars.length; i++) {
    final probs = maybe[i];
    final frame = probs == null ? {chars[i]: p, '_': 0.05} : {...probs, '_': 0.02};
    out
      ..add(frame)
      ..add({'_': 0.9});
  }
  return out;
}

/// Frames in the style of the real model's output for [text]: one frame per
/// character with the letter at [p] and almost no blank (as in the real
/// matrices, where the blank sits at 0.002 on a letter frame), a blank frame
/// between characters. [maybe] replaces the letters at some positions by
/// competing readings, like [spellWith].
List<Map<String, double>> crisp(
  String text, {
  Map<int, Map<String, double>> maybe = const {},
  double p = 0.97,
}) {
  final out = <Map<String, double>>[];
  for (var i = 0; i < text.length; i++) {
    out
      ..add(maybe[i] != null ? {...maybe[i]!, '_': 0.005} : {text[i]: p, '_': 0.005})
      ..add({'_': 0.99});
  }
  return out;
}
