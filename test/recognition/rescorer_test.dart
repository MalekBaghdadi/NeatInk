import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/recognition/lexicon.dart';
import 'package:neatink/recognition/rescorer.dart';
import 'package:neatink/recognition/user_lexicon.dart';

import 'ctc_fixtures.dart';

// Counts on the scale of the bundled list (total about 3.6e11; the last line
// is a filler that carries the mass of the thousands of words not listed
// here, so probabilities and the rank-30000 prior of unknown strings have
// realistic sizes).
const _words = '''
filler 330000000000
the 10000000000
and 5000000000
i 3000000000
not 1500000000
note 30000000
notes 25000000
nose 6000000
node 4000000
make 400000000
mark 90000000
marion 3000000
marian 2500000
cat 50000000
cot 2000000
cut 80000000
car 300000000
hello 30000000
help 200000000
world 400000000
word 300000000
nasa 5000000
don't 20000000
it's 25000000
sun 1000000
rare 1000000
''';

void main() {
  final cs = testCharset();
  final lex = Lexicon.parse(_words);
  final lexWithMariam = Lexicon.parse('$_words\nmariam 2000000\n');

  RescoredWord read(
    List<Map<String, double>> frames, {
    Lexicon? lexicon,
    UserLexicon? user,
    RescoreConfig config = const RescoreConfig(),
  }) =>
      LexiconRescorer(cs, lexicon ?? lex, userLexicon: user, config: config)
          .rescore(framesOf(cs, frames));

  UserLexicon personal(List<String> words) {
    final u = UserLexicon();
    words.forEach(u.add);
    return u;
  }

  // c, a/o, t with an ambiguous vowel.
  List<Map<String, double>> catOrCot(double pA, double pO) => spellWith('cot', {
        1: {'a': pA, 'o': pO},
      });

  group('dictionary correction', () {
    test('the lexicon decides between cat and cot when the image is unsure', () {
      final r = read(catOrCot(0.45, 0.5));
      expect(r.raw, 'cot'); // best path alone is wrong
      expect(r.text, 'cat'); // cat is 25x more frequent
      expect(r.alternatives, contains('cot'));
      expect(r.corrected, isTrue);
    });

    test('clear image evidence beats the language prior', () {
      final r = read(catOrCot(0.01, 0.95));
      expect(r.raw, 'cot');
      expect(r.text, 'cot');
      // (was 0.5 before an unknown string got the prior of a rare real word:
      // the rivals 'cut'/'car'/... now weigh a little more in the posterior)
      expect(r.confidence, greaterThan(0.4));
    });

    test('a known word is kept unless the language clearly prefers another', () {
      // o is likelier than a, but cat is 25x more common than cot: the
      // head start of a known greedy word holds against a moderate gap.
      expect(read(catOrCot(0.25, 0.7)).text, 'cot');
      expect(read(catOrCot(0.45, 0.5)).text, 'cat');
    });

    test('a one-letter slip in a listed word is repaired', () {
      // "hallo" read with a weak second letter: hello wins.
      final r = read(spellWith('hallo', {
        1: {'a': 0.55, 'e': 0.4},
      }));
      expect(r.raw, 'hallo');
      expect(r.text, 'hello');
    });

    test('Notc becomes Note when e and c are ambiguous', () {
      final r = read(spellWith('Notc', {
        3: {'c': 0.55, 'e': 0.35},
      }));
      expect(r.raw, 'Notc');
      expect(r.text, 'Note');
      expect(r.alternatives, contains('Notc'));
    });

    test('a clearly different letter is not overruled', () {
      // x is nothing like e: the unknown word stays as written.
      final r = read(spell('Notx'));
      expect(r.text, 'Notx');
      expect(r.raw, 'Notx');
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

    test('lambda 0 and no lexicon mean no correction', () {
      final frames = spellWith('Notc', {
        3: {'c': 0.55, 'e': 0.35},
      });
      expect(read(frames, config: const RescoreConfig(lambda: 0)).text, 'Notc');
      final bare = LexiconRescorer(cs, null).rescore(framesOf(cs, catOrCot(0.45, 0.5)));
      expect(bare.text, 'cot');
      expect(bare.raw, 'cot');
    });

    test('the beam search offers readings without any word list', () {
      final r = LexiconRescorer(cs, null).rescore(framesOf(cs, catOrCot(0.45, 0.5)));
      expect(r.alternatives, contains('cat'));
    });

    test('an empty reading has zero confidence', () {
      final r = read([
        {'_': 0.99},
        {'_': 0.99},
      ]);
      expect(r.text, isEmpty);
      expect(r.confidence, 0);
      expect(r.alternatives, isEmpty);
    });
  });

  group('look-alike letters', () {
    test('Masiam becomes Mariam when s and r are close and mariam is listed', () {
      final frames = spellWith('Masiam', {
        2: {'s': 0.5, 'r': 0.45},
      });
      final r = read(frames, lexicon: lexWithMariam);
      expect(r.raw, 'Masiam');
      expect(r.text, 'Mariam');
      expect(r.alternatives, contains('Masiam'));
    });

    test('clear evidence for s still wins over a listed mariam', () {
      final frames = spellWith('Masiam', {
        2: {'s': 0.97, 'r': 0.001},
      });
      final r = read(frames, lexicon: lexWithMariam);
      expect(r.text, 'Masiam');
    });

    test('without the word, Masiam stays', () {
      final frames = spellWith('Masiam', {
        2: {'s': 0.5, 'r': 0.45},
      });
      expect(read(frames).text, 'Masiam');
    });

    test('a personal word beats an unlisted look-alike', () {
      final frames = spellWith('Masiam', {
        2: {'s': 0.7, 'r': 0.25},
      });
      expect(read(frames, user: personal(['Mariam'])).text, 'Mariam');
      // ... but never a letter that does not look like the other
      expect(read(spell('Maxiam'), user: personal(['Mariam'])).text, 'Maxiam');
    });

    test('Malck becomes Malek only with Malek in the personal dictionary', () {
      final frames = spellWith('Malck', {
        3: {'c': 0.55, 'e': 0.35},
      });
      expect(read(frames).text, 'Malck');
      final withMalek = read(frames, user: personal(['Malek']));
      expect(withMalek.text, 'Malek');
      expect(withMalek.raw, 'Malck');
      expect(withMalek.alternatives, contains('Malck'));
    });

    test('the personal dictionary is read live', () {
      final user = UserLexicon();
      final rescorer = LexiconRescorer(cs, lex, userLexicon: user);
      final frames = framesOf(
          cs,
          spellWith('Malck', {
            3: {'c': 0.55, 'e': 0.35},
          }));
      expect(rescorer.rescore(frames).text, 'Malck');
      user.add('Malek');
      expect(rescorer.rescore(frames).text, 'Malek');
    });

    test('personal words are matched within more edits than listed ones', () {
      // Three letters differ, each only slightly unlikely.
      final frames = spellWith('Baghbadi', {
        4: {'b': 0.5, 'd': 0.4},
      });
      expect(read(frames, user: personal(['Baghdadi'])).text, 'Baghdadi');
      expect(read(frames).text, 'Baghbadi');
    });

    test('confusionMass 0 turns the look-alike leniency off', () {
      // A fairly confident s against a personal Mariam: the smoothing lets
      // the personal word win; without it the image evidence holds.
      final frames = spellWith('Masiam', {
        2: {'s': 0.85, 'r': 0.05},
      });
      final user = personal(['Mariam']);
      expect(read(frames, user: user).text, 'Mariam');
      expect(read(frames, user: user, config: const RescoreConfig(confusionMass: 0)).text, 'Masiam');
    });
  });

  group('capitalisation', () {
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

    test('capitals are not kept: NOTE becomes Note, HELLO becomes Hello', () {
      expect(read(spell('NOTE')).raw, 'NOTE');
      expect(read(spell('NOTE')).text, 'Note');
      expect(read(spell('HELLO')).text, 'Hello');
      expect(read(spell('hello')).text, 'hello');
      expect(read(spell('nOtE')).text, 'note');
    });

    test('acronyms stay in capitals', () {
      expect(read(spell('NASA')).text, 'NASA');
      expect(read(spell('USA'), user: personal(['USA'])).text, 'USA');
    });

    test('an unknown word in capitals is returned as read', () {
      expect(read(spell('XQZ')).text, 'XQZ');
    });

    test('single letters keep the case of the raw reading', () {
      expect(read(spell('I')).text, 'I');
      expect(read(spell('i')).text, 'i');
    });

    test('personal words keep the capitalisation the user typed', () {
      final user = personal(['Malek', 'Baghdadi']);
      expect(read(spell('Malek'), user: user).text, 'Malek');
      expect(read(spell('malek'), user: user).text, 'Malek');
      expect(read(spell('MALEK'), user: user).text, 'Malek');
      expect(read(spell('baghdadi'), user: user).text, 'Baghdadi');
    });
  });

  group('alternatives and confidence', () {
    test('up to five distinct readings, best first, casing applied', () {
      final r = read(spellWith('Notc', {
        3: {'c': 0.55, 'e': 0.35},
      }));
      expect(r.alternatives.length, lessThanOrEqualTo(5));
      expect(r.alternatives.toSet().length, r.alternatives.length);
      expect(r.alternatives, isNot(contains(r.text)));
      expect(r.alternatives, everyElement(startsWith('N')));
      // no two alternatives differ in case only
      final lower = r.alternatives.map((a) => a.toLowerCase()).toList();
      expect(lower.toSet().length, lower.length);
    });

    test('the raw reading is offered next to a correction', () {
      final r = read(catOrCot(0.45, 0.5));
      expect(r.alternatives, contains(r.raw));
    });

    test('readings that are not words get the beam readings as alternatives', () {
      final r = read(spellWith('27', {
        1: {'7': 0.5, '1': 0.4},
      }));
      expect(r.text, '27');
      expect(r.alternatives, contains('21'));
    });

    test('confidence is lower for a doubtful reading than a clear one', () {
      final clear = read(spell('hello'));
      final doubtful = read(catOrCot(0.45, 0.5));
      expect(clear.confidence, greaterThan(doubtful.confidence));
      expect(clear.confidence, inInclusiveRange(0.0, 1.0));
    });

    test('a correction that is a close call has a low confidence', () {
      final close = read(spellWith('Masiam', {
        2: {'s': 0.5, 'r': 0.45},
      }), lexicon: lexWithMariam);
      final sure = read(spell('Mariam'), lexicon: lexWithMariam);
      expect(close.confidence, lessThan(sure.confidence));
      expect(close.confidence, lessThan(0.5));
    });

    test('RescoredWord.corrected tells a change from a pass-through', () {
      expect(read(spell('hello')).corrected, isFalse);
      expect(read(catOrCot(0.45, 0.5)).corrected, isTrue);
    });
  });

  group('unknown strings and replacements (the v1.2.1 bugs)', () {
    final withMale = Lexicon.parse('$_words\nmale 90000000\n');

    test('a clearly read name is not replaced by a frequent word one edit away', () {
      // "Malek" read with confidence; "male" is listed and frequent.
      final r = read(spell('Malek'), lexicon: withMale);
      expect(r.text, 'Malek');
      expect(r.corrected, isFalse);
    });

    test('a name with a doubtful extra letter may lose it to a frequent word', () {
      // The head start of the model's own reading shrinks with doubt: an x the
      // model itself is unsure of does not protect "Malex" from "Male".
      final r = read(
          spellWith('Malex', {
            4: {'x': 0.4, 'e': 0.35},
          }),
          lexicon: withMale);
      expect(r.raw, 'Malex');
      expect(r.text, 'Male');
      expect(r.alternatives, contains('Malex'));
    });

    test('an unknown string gets the prior of a rare listed word, not of an impossible one', () {
      // A listed word nobody would expect must not beat a clear unknown reading
      // just because it is listed: "rare" is the rarest listed word.
      final lexicon = Lexicon.parse('$_words\nmarx 1000000\n');
      expect(read(spell('Marz'), lexicon: lexicon).text, 'Marz');
    });

    test('a replacement does not inherit a capital from a different first letter', () {
      // raw "Eat" (E and c look alike); the replacement "cat" starts with
      // another letter, so it is not capitalised (it used to become "Cat")
      final r = read(spellWith('Eat', {
        0: {'E': 0.5, 'c': 0.45},
      }));
      expect(r.raw, 'Eat');
      expect(r.text, 'cat');
    });

    test('a replacement with the same first letter keeps the capital', () {
      final r = read(spellWith('Cot', {
        1: {'o': 0.45, 'a': 0.5},
      }));
      expect(r.text, 'Cat');
    });

    test('contractions without the apostrophe are known words', () {
      final r = read(spellWith('isut', {
        2: {'u': 0.45, 'n': 0.5},
      }));
      expect(r.text, 'isnt');
      expect(read(spell('isnt')).text, 'isnt');
    });

    test('the head start of a clear unknown reading shrinks with doubt', () {
      // the same slip, once read with certainty and once with real doubt
      final user = personal(['Mariam']);
      final sure = read(spellWith('Masiam', {
        2: {'s': 0.97, 'r': 0.002},
      }), user: user);
      final doubtful = read(spellWith('Masiam', {
        2: {'s': 0.5, 'r': 0.45},
      }), user: user);
      expect(sure.text, 'Masiam');
      expect(doubtful.text, 'Mariam');
    });
  });

  group('on the bundled word list', () {
    const candidates = [
      'assets/htr/word_freq.txt',
      r'C:\Users\Malek Baghdadi\Downloads\neatink\assets\htr\word_freq.txt',
    ];
    final file = candidates.map(File.new).where((f) => f.existsSync()).firstOrNull;
    // The mirror has no assets folder: these tests then do nothing.
    final real = file == null ? null : Lexicon.parse(file.readAsStringSync());

    /// [n] words of the first [top] entries of the list (the list is sorted
    /// by frequency).
    List<String> sample(int n, {int top = 50000}) {
      final lines = file!.readAsLinesSync();
      final rng = Random(3);
      final out = <String>[];
      while (out.length < n) {
        final w = lines[rng.nextInt(min(top, lines.length))].split(' ').first;
        if (w.length >= 3 && RegExp(r'^[a-z]+$').hasMatch(w)) out.add(w);
      }
      return out;
    }

    const lookAlike = {'e': 'c', 'c': 'e', 'a': 'o', 'o': 'a', 'r': 's', 's': 'r', 'n': 'u', 'u': 'n', 'i': 'l', 'l': 'i'};

    /// For each sampled word with a look-alike letter that is not itself a
    /// word: how often the rescorer restores it when the model reads the
    /// wrong letter at [wrong] and the right one at [right].
    ({int fixed, int other, int total}) slips(LexiconRescorer r, double wrong, double right) {
      var fixed = 0, other = 0, total = 0;
      // Running text is made of frequent words: a uniform sample of the whole
      // list is mostly words from rank 10000 up, which a unigram prior (and the
      // sane prior of an unknown string) cannot rescue from a doubtful letter.
      for (final w in sample(300, top: 5000)) {
        final i = w.split('').indexWhere(lookAlike.containsKey);
        if (i < 0) continue;
        final bad = w.replaceRange(i, i + 1, lookAlike[w[i]]!);
        if (real!.contains(bad)) continue;
        total++;
        final text = r.rescore(framesOf(cs, crisp(bad, maybe: {i: {bad[i]: wrong, w[i]: right}}))).text;
        if (text == w) {
          fixed++;
        } else if (text != bad) {
          other++;
        }
      }
      return (fixed: fixed, other: other, total: total);
    }

    test('clear readings of listed words are not changed', () {
      if (real == null) return;
      final r = LexiconRescorer(cs, real);
      final changed = [
        for (final w in sample(300))
          if (r.rescore(framesOf(cs, crisp(w))).text != w) w,
      ];
      expect(changed.length, lessThanOrEqualTo(2), reason: '$changed');
    });

    test('clearly read unlisted names are not changed', () {
      if (real == null) return;
      final r = LexiconRescorer(cs, real);
      const names = ['Baghdadi', 'Malek', 'Mariam', 'Kowalski', 'Nguyen', 'Haddad', 'Zhang', 'Ibrahim', 'Layla', 'Yousef', 'Rania', 'Samir', 'Hadeel', 'Omar'];
      final changed = [
        for (final n in names)
          if (r.rescore(framesOf(cs, crisp(n))).text != n) n,
      ];
      expect(changed.length, lessThanOrEqualTo(2), reason: '$changed');
    });

    test('a look-alike slip with real doubt is mostly repaired', () {
      if (real == null) return;
      final result = slips(LexiconRescorer(cs, real), 0.75, 0.2);
      expect(result.fixed / result.total, greaterThan(0.6));
      expect(result.other / result.total, lessThan(0.05));
    });

    test('a look-alike slip read with great confidence is mostly left alone', () {
      if (real == null) return;
      final result = slips(LexiconRescorer(cs, real), 0.97, 0.005);
      expect(result.fixed / result.total, lessThan(0.35));
      expect(result.other / result.total, lessThan(0.05));
    });

    test('rescoring a 50k-word list stays fast enough', () {
      if (real == null) return;
      final rescorer = LexiconRescorer(cs, real, userLexicon: personal(['Malek', 'Mariam', 'Baghdadi']));
      final frames = framesOf(
          cs,
          spellWith('Notebook', {
            3: {'c': 0.55, 'e': 0.35},
          }));
      rescorer.rescore(frames); // builds the BK tree
      final sw = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        rescorer.rescore(frames);
      }
      expect(sw.elapsedMilliseconds / 10, lessThan(400));
      expect(rescorer.rescore(frames).text, 'Notebook');
    });
  });
}
