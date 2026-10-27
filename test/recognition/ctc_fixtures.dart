import 'dart:math' as math;

import 'package:neatink/recognition/ctc.dart';

/// The 78-character charset of the bundled model (assets/htr/config.json).
CtcCharset testCharset() => CtcCharset([
      ...'!"#&\'()*+,-./0123456789:;?'.split(''),
      for (var c = 65; c <= 90; c++) String.fromCharCode(c),
      for (var c = 97; c <= 122; c++) String.fromCharCode(c),
    ]);

/// Builds log-probabilities from per-frame probabilities. Each frame maps a
/// character (`_` is the blank) to its probability; the rest of the mass is
/// spread evenly over the remaining classes, so every frame sums to 1.
CtcLogProbs framesOf(CtcCharset cs, List<Map<String, double>> frames) {
  final data = <double>[];
  for (final f in frames) {
    final given = f.values.fold(0.0, (a, b) => a + b);
    assert(given <= 1.0 + 1e-9);
    final rest = (1 - given) / (cs.classes - f.length);
    for (var c = 0; c < cs.classes; c++) {
      final ch = c == cs.blank ? '_' : cs.charAt(c);
      data.add(math.log(f[ch] ?? rest));
    }
  }
  return CtcLogProbs(data, timesteps: frames.length, classes: cs.classes);
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
