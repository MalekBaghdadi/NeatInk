import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/recognition/ctc.dart';

import 'ctc_fixtures.dart';

File? _bundled(String name) {
  final candidates = [
    'assets/htr/$name',
    'C:/Users/Malek Baghdadi/Downloads/neatink/assets/htr/$name',
  ];
  return candidates.map(File.new).where((f) => f.existsSync()).firstOrNull;
}

void main() {
  final cs = testCharset();

  group('CtcCharset', () {
    test('blank is class 0 and the space is the last class', () {
      expect(cs.classes, 95);
      expect(cs.blank, 0);
      expect(cs.space, 94);
      expect(cs.charAt(0), '');
      expect(cs.charAt(94), ' ');
      expect(cs.indexOf('0'), 1);
      expect(cs.indexOf('A'), 11);
      expect(cs.indexOf('z'), 62);
      expect(cs.indexOf('é'), isNull);
      expect(cs.indexOf(''), isNull); // the blank is not a character
    });

    test('parses charset.json and encodes text', () {
      final parsed = CtcCharset.fromJson(
          '{"blank": 0, "space": 4, "charset": ["", "a", "b", "c", " "]}');
      expect(parsed.classes, 5);
      expect(parsed.blank, 0);
      expect(parsed.space, 4);
      expect(parsed.encode('cab'), [3, 1, 2]);
      expect(parsed.encode('cad'), isNull);
      // blank defaults to 0 and the space is found by its text
      final plain = CtcCharset.fromConfigJson('{"charset": ["", "x", " "]}');
      expect(plain.blank, 0);
      expect(plain.space, 2);
    });

    test('the bundled charset.json matches the model (438 classes)', () {
      final file = _bundled('charset.json');
      if (file == null) return; // the mirror has no assets folder
      final real = CtcCharset.fromJson(file.readAsStringSync());
      expect(real.classes, 438);
      expect(real.blank, 0);
      expect(real.space, 437);
      expect(real.charAt(1), '0');
      expect(real.charAt(11), 'A');
      expect(real.charAt(37), 'a');
      expect(real.charAt(437), ' ');
      // The quote characters of the dictionary survive the round trip.
      expect(real.encode('"\''), isNotNull);
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect((json['charset'] as List).length, 438);
      expect((json['charset'] as List).first, '');
    });
  });

  group('CtcLogProbs.fromProbabilities', () {
    test('takes the logarithm with a floor', () {
      final lp = CtcLogProbs.fromProbabilities([0.5, 0.0, 1e-12, 0.5], 4);
      expect(lp.timesteps, 1);
      expect(lp.at(0, 0), closeTo(math.log(0.5), 1e-12));
      expect(lp.at(0, 1), closeTo(math.log(ctcProbFloor), 1e-12));
      expect(lp.at(0, 2), closeTo(math.log(ctcProbFloor), 1e-12));
    });

    test('folds the space class into the blank', () {
      // classes: blank, a, space
      final lp = CtcLogProbs.fromProbabilities([0.2, 0.5, 0.3, 0.1, 0.1, 0.8], 3,
          blank: 0, foldIntoBlank: 2);
      expect(lp.timesteps, 2);
      expect(lp.at(0, 0), closeTo(math.log(0.5), 1e-12));
      expect(lp.at(0, 2), closeTo(math.log(ctcProbFloor), 1e-12));
      expect(lp.at(1, 0), closeTo(math.log(0.9), 1e-12));
    });
  });

  group('greedyDecode', () {
    test('collapses repeats and removes blanks', () {
      final lp = framesOf(cs, [
        {'c': 0.9},
        {'c': 0.8},
        {'_': 0.9},
        {'a': 0.7},
        {'a': 0.95},
        {'_': 0.9},
        {'t': 0.6},
      ]);
      final g = greedyDecode(lp, cs);
      expect(g.text, 'cat');
      expect(g.charProbs[0], closeTo(0.9, 1e-9));
      expect(g.charProbs[1], closeTo(0.95, 1e-9)); // best frame of the run
      expect(g.charProbs[2], closeTo(0.6, 1e-9));
      expect(g.confidence, closeTo(math.pow(0.9 * 0.95 * 0.6, 1 / 3), 1e-9));
    });

    test('a doubled letter needs a blank between its frames', () {
      final merged = framesOf(cs, [
        {'l': 0.9},
        {'l': 0.9},
      ]);
      expect(greedyDecode(merged, cs).text, 'l');
      final split = framesOf(cs, [
        {'l': 0.9},
        {'_': 0.9},
        {'l': 0.9},
      ]);
      expect(greedyDecode(split, cs).text, 'll');
    });

    test('all blank decodes to nothing with zero confidence', () {
      final lp = framesOf(cs, [
        {'_': 0.99},
        {'_': 0.99},
      ]);
      final g = greedyDecode(lp, cs);
      expect(g.text, isEmpty);
      expect(g.confidence, 0);
    });
  });

  group('ctcLogLikelihood', () {
    test('matches the hand-computed sum over alignments', () {
      final lp = framesOf(cs, [
        {'a': 0.6, '_': 0.3},
        {'a': 0.5, '_': 0.4},
      ]);
      // Label "a" over two frames: aa, a_, _a.
      const a1 = 0.6, b1 = 0.3, a2 = 0.5, b2 = 0.4;
      final expected = math.log(a1 * a2 + a1 * b2 + b1 * a2);
      expect(ctcLogLikelihood(lp, [cs.indexOf('a')!], blank: cs.blank), closeTo(expected, 1e-9));
    });

    test('the empty label sequence is all blanks', () {
      final lp = framesOf(cs, [
        {'_': 0.5},
        {'_': 0.25},
      ]);
      expect(ctcLogLikelihood(lp, const [], blank: cs.blank), closeTo(math.log(0.125), 1e-9));
    });

    test('a repeated letter cannot fit without a separating blank', () {
      final two = framesOf(cs, [
        {'a': 0.9},
        {'a': 0.9},
      ]);
      final aa = cs.encode('aa')!;
      expect(ctcLogLikelihood(two, aa, blank: cs.blank), double.negativeInfinity);
      final three = framesOf(cs, [
        {'a': 0.9},
        {'_': 0.9},
        {'a': 0.9},
      ]);
      expect(ctcLogLikelihood(three, aa, blank: cs.blank), closeTo(math.log(0.9 * 0.9 * 0.9), 1e-9));
    });

    test('different letters may follow each other directly', () {
      final lp = framesOf(cs, [
        {'a': 0.9},
        {'b': 0.9},
      ]);
      expect(ctcLogLikelihood(lp, cs.encode('ab')!, blank: cs.blank), closeTo(math.log(0.81), 1e-9));
    });

    test('a spelled word scores higher than a near miss', () {
      final lp = framesOf(cs, spell('cat'));
      final cat = ctcLogLikelihood(lp, cs.encode('cat')!, blank: cs.blank);
      final cot = ctcLogLikelihood(lp, cs.encode('cot')!, blank: cs.blank);
      expect(cat, greaterThan(cot + 3));
    });

    test('case-insensitive sets add the probabilities of both cases', () {
      final lp = framesOf(cs, [
        {'a': 0.3, 'A': 0.4},
      ]);
      final sets = [
        [cs.indexOf('a')!, cs.indexOf('A')!],
      ];
      expect(ctcLogLikelihoodSets(lp, sets, blank: cs.blank), closeTo(math.log(0.7), 1e-9));
    });
  });

  group('ctcBeamSearch', () {
    // c, then a (0.55) or o (0.40), then t: three frames with blanks between.
    final lp = framesOf(cs, [
      {'c': 0.9, '_': 0.05},
      {'_': 0.9},
      {'a': 0.55, 'o': 0.40, '_': 0.03},
      {'_': 0.9},
      {'t': 0.9, '_': 0.05},
    ]);

    test('returns the best readings first, with their summed probability', () {
      final beams = ctcBeamSearch(lp, cs, width: 5);
      expect(beams.map((b) => b.text).take(2), ['cat', 'cot']);
      for (final b in beams.take(2)) {
        final exact = ctcLogLikelihood(lp, b.indices, blank: cs.blank);
        expect(b.logProb, closeTo(exact, 0.05), reason: b.text);
      }
      expect(beams.first.logProb, greaterThan(beams[1].logProb));
    });

    test('the best beam is the greedy reading on clear audio', () {
      final clear = framesOf(cs, spell('hello'));
      final beams = ctcBeamSearch(clear, cs);
      expect(beams.first.text, greedyDecode(clear, cs).text);
      expect(beams.first.text, 'hello');
    });

    test('width limits the number of readings; repeats need a blank', () {
      expect(ctcBeamSearch(lp, cs, width: 1), hasLength(1));
      final ll = framesOf(cs, [
        {'l': 0.9},
        {'l': 0.9},
      ]);
      expect(ctcBeamSearch(ll, cs).first.text, 'l');
    });

    test('an empty sequence has the empty reading', () {
      final empty = CtcLogProbs(const [], timesteps: 0, classes: cs.classes);
      expect(ctcBeamSearch(empty, cs).single.text, '');
    });
  });
}
