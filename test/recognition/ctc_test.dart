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

  group('CtcLogProbs.slice', () {
    test('cuts timesteps [start, end) and clamps', () {
      final lp = framesOf(cs, [
        {'a': 0.9},
        {'b': 0.9},
        {'c': 0.9},
        {'d': 0.9},
      ]);
      final mid = lp.slice(1, 3);
      expect(mid.timesteps, 2);
      expect(mid.classes, lp.classes);
      expect(mid.at(0, cs.indexOf('b')!), lp.at(1, cs.indexOf('b')!));
      expect(mid.at(1, cs.indexOf('c')!), lp.at(2, cs.indexOf('c')!));
      expect(lp.slice(-5, 99).timesteps, 4);
      expect(lp.slice(3, 1).timesteps, 0);
    });
  });

  group('CtcScorer', () {
    CtcLogProbs randomFrames(math.Random rng, int steps) {
      final letters = ['a', 'b', 'c', 'e', ' ', '_'];
      return framesOf(cs, [
        for (var t = 0; t < steps; t++) _randomFrame(rng, letters),
      ]);
    }

    test('matches the log-domain forward algorithm', () {
      final rng = math.Random(4);
      for (var n = 0; n < 40; n++) {
        final lp = randomFrames(rng, 3 + rng.nextInt(12));
        final scorer = CtcScorer.fromLogProbs(lp, blank: cs.blank);
        final text = String.fromCharCodes(List.generate(rng.nextInt(5), (_) => 97 + rng.nextInt(5)));
        final labels = cs.encode(text.replaceAll('d', ' '))!;
        final sets = [
          for (final l in labels) [l],
        ];
        final exact = ctcLogLikelihoodSets(lp, sets, blank: cs.blank);
        final fast = scorer.logLikelihood(sets);
        if (exact == double.negativeInfinity) {
          expect(fast, double.negativeInfinity, reason: text);
        } else {
          expect(fast, closeTo(exact, 1e-9), reason: text);
        }
      }
    });

    test('case-insensitive sets add the probabilities of both cases', () {
      final lp = framesOf(cs, [
        {'a': 0.3, 'A': 0.4},
      ]);
      final scorer = CtcScorer.fromLogProbs(lp, blank: cs.blank);
      final sets = [
        [cs.indexOf('a')!, cs.indexOf('A')!],
      ];
      expect(scorer.logLikelihood(sets), closeTo(math.log(0.7), 1e-9));
    });

    test('empty labels and empty input', () {
      final lp = framesOf(cs, [
        {'_': 0.5},
        {'_': 0.25},
      ]);
      final scorer = CtcScorer.fromLogProbs(lp, blank: cs.blank);
      expect(scorer.logLikelihood(const []), closeTo(math.log(0.125), 1e-9));
      final none = CtcScorer.fromLogProbs(CtcLogProbs(const [], timesteps: 0, classes: cs.classes), blank: cs.blank);
      expect(none.logLikelihood(const []), 0);
      expect(none.logLikelihood([
        [1],
      ]), double.negativeInfinity);
    });

    test('a repeated letter needs a blank between its frames', () {
      final two = CtcScorer.fromLogProbs(
          framesOf(cs, [
            {'a': 0.9},
            {'a': 0.9},
          ]),
          blank: cs.blank);
      final aa = [
        [cs.indexOf('a')!],
        [cs.indexOf('a')!],
      ];
      expect(two.logLikelihood(aa), double.negativeInfinity);
    });

    test('slice scores a part of the frames', () {
      final lp = framesOf(cs, spell('cat'));
      final scorer = CtcScorer.fromLogProbs(lp, blank: cs.blank);
      final whole = scorer.logLikelihood([for (final l in cs.encode('cat')!) [l]]);
      final firstLetter = scorer.slice(0, 3).logLikelihood([
        [cs.indexOf('c')!],
      ]);
      expect(firstLetter, greaterThan(whole));
      expect(scorer.slice(0, 3).timesteps, 3);
      expect(scorer.slice(2, 99).timesteps, lp.timesteps - 2);
    });

    test('smoothing lends probability to the look-alike letter and leaves the rest', () {
      final lp = framesOf(cs, [
        {'c': 0.9, '_': 0.05},
      ]);
      final scorer = CtcScorer.fromLogProbs(lp, blank: cs.blank);
      final pairs = [
        ([cs.indexOf('e')!], [cs.indexOf('c')!]),
      ];
      final smooth = scorer.smoothed(pairs, 0.1);
      expect(smooth.prob(0, cs.indexOf('e')!), closeTo(scorer.prob(0, cs.indexOf('e')!) + 0.09, 1e-9));
      expect(smooth.prob(0, cs.indexOf('c')!), closeTo(scorer.prob(0, cs.indexOf('c')!) + 0.1 * scorer.prob(0, cs.indexOf('e')!), 1e-9));
      expect(smooth.prob(0, cs.indexOf('t')!), scorer.prob(0, cs.indexOf('t')!));
      expect(identical(scorer.smoothed(pairs, 0), scorer), isTrue);
      final e = smooth.logLikelihood([
        [cs.indexOf('e')!],
      ]);
      final plain = scorer.logLikelihood([
        [cs.indexOf('e')!],
      ]);
      expect(e, greaterThan(plain + 3));
    });

    test('folding the space into the blank turns gap frames into "no letter"', () {
      final lp = framesOf(cs, [
        {'a': 0.9, '_': 0.05},
        {' ': 0.9, '_': 0.05},
      ]);
      final scorer = CtcScorer.fromLogProbs(lp, blank: cs.blank);
      final a = [
        [cs.indexOf('a')!],
      ];
      final folded = scorer.foldedIntoBlank(cs.space!);
      expect(folded.logLikelihood(a), greaterThan(scorer.logLikelihood(a) + 2));
      expect(folded.prob(1, cs.blank), closeTo(0.95, 1e-9));
      expect(folded.prob(1, cs.space!), closeTo(ctcProbFloor, 1e-12));
    });

    test('align finds the frames and the probability of each label', () {
      final lp = framesOf(cs, [
        {'_': 0.9},
        {'c': 0.9, '_': 0.05},
        {'_': 0.9},
        {'a': 0.6, 'o': 0.3, '_': 0.05},
        {'a': 0.7, '_': 0.05},
        {'_': 0.9},
        {'t': 0.8, '_': 0.1},
      ]);
      final scorer = CtcScorer.fromLogProbs(lp, blank: cs.blank);
      final spans = scorer.align([for (final l in cs.encode('cat')!) [l]])!;
      expect(spans, hasLength(3));
      expect([spans[0].firstFrame, spans[0].lastFrame], [1, 1]);
      expect([spans[1].firstFrame, spans[1].lastFrame], [3, 4]);
      expect([spans[2].firstFrame, spans[2].lastFrame], [6, 6]);
      expect(spans[0].prob, closeTo(0.9, 1e-9));
      expect(spans[1].prob, closeTo(0.7, 1e-9));
      expect(spans[2].prob, closeTo(0.8, 1e-9));
      expect(scorer.align(const []), isEmpty);
    });

    test('align returns null when the labels do not fit', () {
      final lp = framesOf(cs, [
        {'a': 0.9},
        {'a': 0.9},
      ]);
      final scorer = CtcScorer.fromLogProbs(lp, blank: cs.blank);
      expect(scorer.align([for (final l in cs.encode('aa')!) [l]]), isNull);
    });

    test('is faster than the log-domain forward algorithm', () {
      final rng = math.Random(9);
      final lp = randomFrames(rng, 80);
      final scorer = CtcScorer.fromLogProbs(lp, blank: cs.blank);
      final sets = [for (final l in cs.encode('abcabceabcabceabcab')!) [l]];
      var sink = 0.0;
      final slow = Stopwatch()..start();
      for (var i = 0; i < 40; i++) {
        sink += ctcLogLikelihoodSets(lp, sets, blank: cs.blank);
      }
      final slowMs = slow.elapsedMicroseconds;
      final fast = Stopwatch()..start();
      for (var i = 0; i < 40; i++) {
        sink += scorer.logLikelihood(sets);
      }
      final fastMs = fast.elapsedMicroseconds;
      expect(sink.isNaN, isFalse);
      expect(fastMs, lessThan(slowMs));
    });
  });
}

/// One frame of random probabilities over [letters] (`_` is the blank, a
/// space is the space class), summing to a little less than 1.
Map<String, double> _randomFrame(math.Random rng, List<String> letters) {
  final weights = [for (final _ in letters) rng.nextDouble()];
  final total = weights.fold(0.0, (a, b) => a + b) * 1.05;
  return {
    for (var i = 0; i < letters.length; i++) letters[i]: weights[i] / total,
  };
}
