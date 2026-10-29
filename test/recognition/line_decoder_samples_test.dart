// Decodes the model output of real handwritten lines.
//
// The samples are personal data and are NOT part of the repository: this
// test is skipped unless NEATINK_LINE_PROBS points to a JSON file
//
//     {id: {"truth": str, "width": W, "T": T, "C": 438, "probs": [T*C floats]}}
//
// (softmax probabilities of the bundled PP-OCRv5 model for a line image).
// It prints, per item, the greedy reading and the decoded reading with their
// character error rate against the truth, and a summary. There is no hard
// accuracy assertion beyond "the decoder is not worse than greedy on average".
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/recognition/ctc.dart';
import 'package:neatink/recognition/line_decoder.dart';
import 'package:neatink/recognition/lexicon.dart';
import 'package:neatink/recognition/user_lexicon.dart';

File? _asset(String name) {
  final candidates = [
    'assets/htr/$name',
    'C:/Users/Malek Baghdadi/Downloads/neatink/assets/htr/$name',
  ];
  return candidates.map(File.new).where((f) => f.existsSync()).firstOrNull;
}

double _cer(String truth, String got, {required bool ignoreCase}) {
  final t = (ignoreCase ? truth.toLowerCase() : truth).trim();
  final g = (ignoreCase ? got.toLowerCase() : got).trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return g.isEmpty ? 0 : 1;
  return levenshtein(t, g) / t.length;
}

void main() {
  final path = Platform.environment['NEATINK_LINE_PROBS'];
  final charsetFile = _asset('charset.json');
  final wordsFile = _asset('word_freq.txt');
  final skip = path == null || path.isEmpty || !File(path).existsSync() || charsetFile == null || wordsFile == null
      ? 'set NEATINK_LINE_PROBS to a line_probs.json to run this'
      : null;

  test('decoded lines are not worse than the greedy reading', () {
    final charset = CtcCharset.fromJson(charsetFile!.readAsStringSync());
    // The bundled lexicon: the general list and the study vocabulary.
    final subject = _asset('subject_words.txt');
    final lexicon = Lexicon.parse(wordsFile!.readAsStringSync(), studyText: subject?.readAsStringSync());
    final data = jsonDecode(File(path!).readAsStringSync()) as Map<String, dynamic>;

    final personal = UserLexicon()
      ..add('Malek')
      ..add('Baghdadi')
      ..add('Mariam');

    for (final withPersonal in [false, true]) {
      final decoder = LineDecoder(charset, lexicon, userLexicon: withPersonal ? personal : null);
      // Warm up (builds the word list's search tree).
      final first = data.values.first as Map<String, dynamic>;
      decoder.decode(_logProbs(first, charset));

      var greedyCer = 0.0, decodedCer = 0.0, greedyCerCase = 0.0, decodedCerCase = 0.0;
      var n = 0, micros = 0;
      stdout.writeln('\n=== personal dictionary: ${withPersonal ? "Malek, Baghdadi, Mariam" : "none"} ===');
      for (final entry in data.entries) {
        final item = entry.value as Map<String, dynamic>;
        final truth = (item['truth'] as String?) ?? '';
        final lp = _logProbs(item, charset);
        final greedy = greedyDecode(lp, charset).text;
        final sw = Stopwatch()..start();
        final reading = decoder.decode(lp);
        sw.stop();
        micros += sw.elapsedMicroseconds;
        final g = _cer(truth, greedy, ignoreCase: true);
        final d = _cer(truth, reading.text, ignoreCase: true);
        greedyCer += g;
        decodedCer += d;
        greedyCerCase += _cer(truth, greedy, ignoreCase: false);
        decodedCerCase += _cer(truth, reading.text, ignoreCase: false);
        n++;
        // The stretch-wise search must not lose to the model's own reading on
        // the whole-line objective.
        expect(decoder.scoreText(lp, reading.text), greaterThanOrEqualTo(decoder.scoreText(lp, greedy.trim().replaceAll(RegExp(r'\s+'), ' ')) - 1e-6),
            reason: entry.key);
        stdout.writeln('${entry.key.padRight(18)} truth=${truth.padRight(26)} '
            'greedy=${greedy.padRight(28)} (${g.toStringAsFixed(2)}) '
            'decoded=${reading.text.padRight(28)} (${d.toStringAsFixed(2)}) '
            'conf=${reading.confidence.toStringAsFixed(2)} ${(sw.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms');
        for (final w in reading.words) {
          stdout.writeln('      ${w.text.padRight(12)} raw=${w.raw.padRight(12)} '
              'frames ${w.startFrame}-${w.endFrame} conf=${w.confidence.toStringAsFixed(2)} '
              'known=${w.known} alt=${w.alternatives}');
        }
      }
      stdout.writeln('SUMMARY personal=$withPersonal items=$n '
          'CER(no case) greedy=${(greedyCer / n).toStringAsFixed(4)} decoded=${(decodedCer / n).toStringAsFixed(4)} | '
          'CER(case) greedy=${(greedyCerCase / n).toStringAsFixed(4)} decoded=${(decodedCerCase / n).toStringAsFixed(4)} | '
          'mean ${(micros / n / 1000).toStringAsFixed(1)} ms');
      expect(decodedCer, lessThanOrEqualTo(greedyCer + 1e-9), reason: 'personal=$withPersonal');
    }
  }, skip: skip);
}

CtcLogProbs _logProbs(Map<String, dynamic> item, CtcCharset charset) {
  final probs = [for (final v in item['probs'] as List<dynamic>) (v as num).toDouble()];
  return CtcLogProbs.fromProbabilities(probs, item['C'] as int, blank: charset.blank);
}
