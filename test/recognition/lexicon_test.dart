import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/recognition/lexicon.dart';

import 'ctc_fixtures.dart';

const _words = '''
the 1000000
cat 50000
cot 2000
cut 40000
car 60000
hello 30000
help 40000
world 90000
word 80000
don't 20000
it's 25000
bad line
''';

void main() {
  final cs = testCharset();
  final lex = Lexicon.parse(_words);

  group('edit distance', () {
    test('levenshtein', () {
      expect(levenshtein('cat', 'cat'), 0);
      expect(levenshtein('cat', 'cot'), 1);
      expect(levenshtein('kitten', 'sitting'), 3);
      expect(levenshtein('', 'abc'), 3);
    });

    test('confusable letters and narrow letters are cheaper', () {
      expect(weightedEditDistance('cat', 'cot'), 0.6);
      expect(weightedEditDistance('cat', 'cxt'), 1.0);
      expect(weightedEditDistance('hello', 'helo'), 0.8); // dropped narrow l
      expect(weightedEditDistance('hello', 'helxo'), 1.0);
    });
  });

  group('Lexicon', () {
    test('parses words, skips bad lines, ranks by frequency', () {
      expect(lex.length, 11);
      expect(lex.contains('HELLO'), isTrue);
      expect(lex.countOf('cat'), 50000);
      expect(lex.logProb('the')! > lex.logProb('cot')!, isTrue);
      expect(lex.logProb('zzz'), isNull);
      expect(lex.minLogProb, lex.logProb('cot'));
    });

    test('candidates equal a brute-force search', () {
      for (final q in ['cat', 'hel', 'wrld', 'cxt', 'zzzzzz']) {
        final expected = {
          for (final w in ['the', 'cat', 'cot', 'cut', 'car', 'hello', 'help', 'world', 'word', "don't", "it's"])
            if (levenshtein(q, w) <= 2) w,
        };
        final got = {for (final c in lex.candidates(q, maxEdits: 2)) c.word};
        expect(got, expected, reason: q);
      }
    });

    test('limit keeps the closest, most frequent', () {
      final c = lex.candidates('cat', maxEdits: 2, limit: 2);
      expect(c.map((e) => e.word), ['cat', 'cot']);
    });

    test('is fast enough for a 50k word list', () {
      final rng = Random(7);
      String randomWord() => String.fromCharCodes(
          List.generate(4 + rng.nextInt(6), (_) => 97 + rng.nextInt(26)));
      final seen = <String>{};
      final big = StringBuffer();
      while (seen.length < 50000) {
        final w = randomWord();
        if (seen.add(w)) big.writeln('$w ${100000 - seen.length}');
      }
      final queries = seen.take(20).toList();
      final sw = Stopwatch()..start();
      final bigLex = Lexicon.parse(big.toString());
      final first = bigLex.candidates('abcdef', maxEdits: 2); // builds the tree
      final build = sw.elapsedMilliseconds;
      sw
        ..reset()
        ..start();
      for (var i = 0; i < 20; i++) {
        bigLex.candidates(queries[i], maxEdits: 2);
      }
      final perQuery = sw.elapsedMilliseconds / 20;
      expect(first, isA<List<LexiconCandidate>>());
      expect(build, lessThan(8000));
      expect(perQuery, lessThan(150));
    });

    test('the bundled list parses', () {
      const candidates = [
        'assets/htr/word_freq.txt',
        r'C:\Users\Malek Baghdadi\Downloads\neatink\assets\htr\word_freq.txt',
      ];
      final file = candidates.map(File.new).where((f) => f.existsSync()).firstOrNull;
      if (file == null) return; // the mirror has no assets folder
      final real = Lexicon.parse(file.readAsStringSync());
      expect(real.length, 50000);
      expect(real.contains('hello'), isTrue);
      expect(real.candidates('cot', maxEdits: 1).map((c) => c.word), contains('cat'));
    });
  });

  group('LexiconRescorer', () {
    // Frames spelling c, a/o, t where the vowel is ambiguous.
    List<Map<String, double>> catOrCot(double pA, double pO) => [
          {'c': 0.9, '_': 0.05},
          {'c': 0.9, '_': 0.05},
          {'_': 0.9},
          {'a': pA, 'o': pO, '_': 0.02},
          {'a': pA, 'o': pO, '_': 0.02},
          {'_': 0.9},
          {'t': 0.9, '_': 0.05},
          {'t': 0.9, '_': 0.05},
        ];

    RescoredWord read(List<Map<String, double>> frames, {Lexicon? lexicon}) =>
        LexiconRescorer(cs, lexicon ?? lex).rescore(framesOf(cs, frames));

    test('the lexicon decides between cat and cot when the image is unsure', () {
      final r = read(catOrCot(0.45, 0.5));
      expect(r.raw, 'cot'); // best path alone is wrong
      expect(r.text, 'cat'); // cat is 25x more frequent
      expect(r.alternatives, contains('cot'));
    });

    test('clear image evidence beats the language prior', () {
      final r = read(catOrCot(0.01, 0.95));
      expect(r.raw, 'cot');
      expect(r.text, 'cot');
      expect(r.confidence, greaterThan(0.6));
    });

    test('capitalisation and punctuation are restored from the raw output', () {
      final upper = read([
        {'C': 0.9, '_': 0.05},
        {'C': 0.9, '_': 0.05},
        {'_': 0.9},
        {'a': 0.45, 'o': 0.5, '_': 0.02},
        {'a': 0.45, 'o': 0.5, '_': 0.02},
        {'_': 0.9},
        {'t': 0.9, '_': 0.05},
        {'t': 0.9, '_': 0.05},
        {'_': 0.9},
        {'.': 0.9, '_': 0.05},
        {'.': 0.9, '_': 0.05},
      ]);
      expect(upper.raw, 'Cot.');
      expect(upper.text, 'Cat.');
    });

    test('all capitals stay all capitals', () {
      final r = read([
        {'C': 0.9, '_': 0.05},
        {'_': 0.9},
        {'A': 0.45, 'O': 0.5, '_': 0.02},
        {'_': 0.9},
        {'T': 0.9, '_': 0.05},
        {'_': 0.9},
      ]);
      expect(r.raw, 'COT');
      expect(r.text, 'CAT');
    });

    test('unlisted words keep the raw reading', () {
      final r = read(spell('Mariam'));
      expect(r.text, 'Mariam');
      expect(r.raw, 'Mariam');
      expect(r.alternatives.length, lessThanOrEqualTo(3));
    });

    test('numbers and mixed tokens are never corrected', () {
      expect(read(spell('c4t')).text, 'c4t');
      expect(read(spell('2025')).text, '2025');
      expect(read(spell('well-known')).text, 'well-known');
    });

    test('apostrophes inside words are kept and listed words pass through', () {
      expect(read(spell("don't")).text, "don't");
      expect(read(spell('hello')).text, 'hello');
    });

    test('a one-letter slip in a listed word is repaired', () {
      // "hallo" read with a weak second letter: hello wins.
      final r = read([
        {'h': 0.9, '_': 0.05},
        {'h': 0.9, '_': 0.05},
        {'_': 0.9},
        {'a': 0.4, 'e': 0.55, '_': 0.02},
        {'a': 0.4, 'e': 0.55, '_': 0.02},
        {'_': 0.9},
        {'l': 0.9, '_': 0.05},
        {'_': 0.9},
        {'l': 0.9, '_': 0.05},
        {'_': 0.9},
        {'o': 0.9, '_': 0.05},
      ]);
      expect(r.text, 'hello');
    });

    test('no lexicon means greedy output', () {
      final r = LexiconRescorer(cs, null).rescore(framesOf(cs, catOrCot(0.45, 0.5)));
      expect(r.text, 'cot');
      expect(r.alternatives, isEmpty);
    });

    test('an empty reading has zero confidence', () {
      final r = read([
        {'_': 0.99},
        {'_': 0.99},
      ]);
      expect(r.text, isEmpty);
      expect(r.confidence, 0);
    });

    test('confidence is lower for a doubtful reading than a clear one', () {
      final clear = read(spell('hello'));
      final doubtful = read(catOrCot(0.45, 0.5));
      expect(clear.confidence, greaterThan(doubtful.confidence));
      expect(clear.confidence, inInclusiveRange(0.0, 1.0));
    });
  });
}
