import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/recognition/lexicon.dart';

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
}
