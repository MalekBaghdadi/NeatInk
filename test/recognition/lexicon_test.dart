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

  group('damerauLevenshtein', () {
    test('a swap of neighbouring letters costs 1', () {
      expect(damerauLevenshtein('nuerons', 'neurons'), 1);
      expect(levenshtein('nuerons', 'neurons'), 2);
      expect(damerauLevenshtein('recieve', 'receive'), 1);
      expect(damerauLevenshtein('ab', 'ba'), 1);
    });

    test('agrees with levenshtein otherwise', () {
      expect(damerauLevenshtein('cat', 'cat'), 0);
      expect(damerauLevenshtein('cat', 'cot'), 1);
      expect(damerauLevenshtein('kitten', 'sitting'), 3);
      expect(damerauLevenshtein('', 'abc'), 3);
      expect(damerauLevenshtein('abc', ''), 3);
      expect(damerauLevenshtein('abcd', 'acbd'), 1);
      // not two swaps in one place: the restricted form
      expect(damerauLevenshtein('ca', 'abc'), 3);
    });
  });

  group('look-alike letters', () {
    test('n/h and r/v are cheap substitutions', () {
      expect(weightedEditDistance('isnt', 'isht'), 0.6);
      expect(weightedEditDistance('are', 'ave'), 0.6);
      expect(weightedEditDistance('cat', 'cxt'), 1.0);
    });
  });

  group('contractions', () {
    test('a contraction written without its apostrophe is recognised', () {
      expect(contractionOf('isnt'), "isn't");
      expect(contractionOf('DONT'), "don't");
      expect(contractionOf('im'), "I'm");
      expect(contractionOf('ive'), "I've");
      expect(contractionOf('shouldve'), "should've");
    });

    test('ordinary words and forms that are also words are not contractions', () {
      for (final w in ['its', 'were', 'well', 'ill', 'id', 'hell', 'shell', 'lets', 'cat', 'isn', '']) {
        expect(contractionOf(w), isNull, reason: w);
      }
    });

    test('priors for both spellings, in the range of a frequent word', () {
      final plain = contractionLogProb('isnt');
      expect(plain, isNotNull);
      expect(contractionLogProb("isn't"), plain);
      expect(contractionLogProb("ISN'T"), plain);
      expect(plain, inInclusiveRange(-10.0, -7.0));
      expect(contractionLogProb('cat'), isNull);
      expect(contractionLogProb('dont')! > contractionLogProb('shouldnt')!, isTrue);
    });

    test('the plain forms list has no duplicates and no apostrophes', () {
      final forms = contractionPlainForms.toList();
      expect(forms.toSet().length, forms.length);
      expect(forms.any((f) => f.contains("'")), isFalse);
      expect(forms, containsAll(['isnt', 'dont', 'im', 'cant']));
    });
  });

  group('logProbAtRank', () {
    test('ranks words by count, clamps beyond the list', () {
      expect(lex.logProbAtRank(0), lex.logProb('the'));
      expect(lex.logProbAtRank(1), lex.logProb('world'));
      expect(lex.logProbAtRank(10000), lex.minLogProb);
      expect(lex.logProbAtRank(-3), lex.logProb('the'));
      expect(Lexicon.parse('').logProbAtRank(30000), lessThan(-10));
    });

    test('on the bundled list rank 30000 is a rare but real word', () {
      const candidates = [
        'assets/htr/word_freq.txt',
        r'C:\Users\Malek Baghdadi\Downloads\neatink\assets\htr\word_freq.txt',
      ];
      final file = candidates.map(File.new).where((f) => f.existsSync()).firstOrNull;
      if (file == null) return; // the mirror has no assets folder
      final real = Lexicon.parse(file.readAsStringSync());
      expect(real.logProbAtRank(30000), inInclusiveRange(-14.5, -13.0));
      expect(real.logProbAtRank(30000), greaterThan(real.minLogProb));
    });
  });
}
