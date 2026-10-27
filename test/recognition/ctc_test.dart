import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/recognition/ctc.dart';

import 'ctc_fixtures.dart';

void main() {
  final cs = testCharset();

  group('CtcCharset', () {
    test('blank is the last class', () {
      expect(cs.chars.length, 78);
      expect(cs.classes, 79);
      expect(cs.blank, 78);
      expect(cs.charAt(78), '');
      expect(cs.indexOf('A'), 26);
      expect(cs.indexOf('z'), 77);
      expect(cs.indexOf('é'), isNull);
    });

    test('parses config.json and encodes text', () {
      final parsed = CtcCharset.fromConfigJson('{"charset": ["a", "b", "c"], "num_classes": 4}');
      expect(parsed.classes, 4);
      expect(parsed.encode('cab'), [2, 0, 1]);
      expect(parsed.encode('cad'), isNull);
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
}
