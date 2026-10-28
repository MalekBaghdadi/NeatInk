import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/recognition/ctc.dart';
import 'package:neatink/recognition/lexicon.dart';
import 'package:neatink/recognition/line_decoder.dart';
import 'package:neatink/recognition/user_lexicon.dart';

import 'ctc_fixtures.dart';

// Counts on the scale of the bundled list (total about 3.6e11; the filler
// carries the mass of the words not listed here; the rarest words have the
// count of the bundled list's 30000th word, which is the prior of an unknown
// string).
const _words = '''
filler 330000000000
the 10000000000
and 5000000000
i 3000000000
a 6000000000
in 7000000000
are 2000000000
is 5000000000
not 1500000000
note 30000000
notes 25000000
nose 6000000
node 4000000
make 400000000
male 90000000
mark 90000000
marion 3000000
marian 2500000
cat 50000000
cot 2000000
cut 80000000
car 300000000
brain 70000000
work 600000000
working 200000000
well 800000000
hello 30000000
help 200000000
world 400000000
word 300000000
nasa 5000000
neurons 3000000
today 90000000
to 9000000000
day 300000000
sun 390000
rare 390000
''';

void main() {
  final cs = testCharset();
  final lex = Lexicon.parse(_words);

  CtcLogProbs lpOf(List<Map<String, double>> frames) => framesOf(cs, frames);

  LineReading decode(
    List<Map<String, double>> frames, {
    Lexicon? lexicon,
    UserLexicon? user,
    LineDecodeConfig config = const LineDecodeConfig(),
  }) =>
      LineDecoder(cs, lexicon ?? lex, userLexicon: user, config: config).decode(lpOf(frames));

  UserLexicon personal(List<String> words) {
    final u = UserLexicon();
    words.forEach(u.add);
    return u;
  }

  /// A soft gap: the model hesitates between "space" and "no space".
  const softGap = {' ': 0.45, '_': 0.5};

  group('words and spaces', () {
    test('the model\'s spaces split the line into words', () {
      final r = decode(crisp('the cat and the world'));
      expect(r.text, 'the cat and the world');
      expect(r.words.map((w) => w.text), ['the', 'cat', 'and', 'the', 'world']);
      expect(r.raw, 'the cat and the world');
      expect(r.words.every((w) => w.known), isTrue);
    });

    test('empty and all-blank input read as nothing', () {
      expect(LineDecoder(cs, lex).decode(CtcLogProbs(const [], timesteps: 0, classes: cs.classes)).text, '');
      final r = decode([
        {'_': 0.99},
        {'_': 0.99},
      ]);
      expect(r.text, isEmpty);
      expect(r.words, isEmpty);
      expect(r.confidence, 0);
      expect(r.timesteps, 2);
    });

    test('leading and trailing spaces are dropped', () {
      final r = decode([...crisp(' the cat ')]);
      expect(r.text, 'the cat');
    });

    test('a missing space the model hesitates over is inserted when both parts are words', () {
      final frames = [...crisp('are'), softGap, ...crisp('in')];
      final r = decode(frames);
      expect(r.raw, 'arein'); // the best path has no space ...
      expect(r.words.map((w) => w.text), ['are', 'in']); // ... the language layer adds it
      expect(r.text, 'are in');
    });

    test('without the word list the hesitation is not resolved', () {
      final frames = [...crisp('are'), softGap, ...crisp('in')];
      final r = LineDecoder(cs, null).decode(lpOf(frames));
      expect(r.text, 'arein');
    });

    test('a space the model hesitates over is removed when the joined word is listed', () {
      final frames = [...crisp('to'), {' ': 0.3, '_': 0.65}, ...crisp('day')];
      expect(decode(frames).text, 'today');
      // a confident space is never removed
      final confident = [...crisp('to'), {' ': 0.97, '_': 0.02}, ...crisp('day')];
      expect(decode(confident).text, 'to day');
    });

    test('a line whose gaps are all hesitant is still split into words, and quickly', () {
      const sentence = ['the', 'cat', 'and', 'the', 'world', 'is', 'not', 'hello', 'work', 'help', 'car', 'word', 'and', 'the', 'brain'];
      final frames = <Map<String, double>>[];
      for (var i = 0; i < sentence.length; i++) {
        if (i > 0) frames.add({' ': 0.4, '_': 0.55});
        frames.addAll(crisp(sentence[i]));
      }
      final r = decode(frames);
      expect(r.raw.contains(' '), isFalse); // the model itself put no space anywhere
      expect(r.words.map((w) => w.text), sentence);
      final sw = Stopwatch()..start();
      decode(frames);
      expect(sw.elapsedMilliseconds, lessThan(500));
    });

    test('a long unknown token is not cut into small words', () {
      final r = decode(crisp('Baghdadi'));
      expect(r.text, 'Baghdadi');
    });
  });

  group('unknown readings and look-alikes', () {
    test('a clearly read name survives a frequent neighbour (Malek is not Male)', () {
      final r = decode(crisp('Malek'));
      expect(r.text, 'Malek');
      expect(r.words.single.known, isFalse);
      expect(r.words.single.corrected, isFalse);
    });

    test('a clearly read misspelling is not replaced by the right word', () {
      expect(decode(crisp('Nuerons')).text, 'Nuerons');
    });

    test('Malck becomes Malek only with Malek in the personal dictionary', () {
      final frames = crisp('Malck', maybe: {
        3: {'c': 0.55, 'e': 0.35},
      });
      expect(decode(frames).text, 'Malck');
      final withMalek = decode(frames, user: personal(['Malek']));
      expect(withMalek.text, 'Malek');
      expect(withMalek.words.single.raw, 'Malck');
      expect(withMalek.words.single.alternatives, contains('Malck'));
      expect(withMalek.words.single.known, isTrue);
    });

    test('a confidently read c is repaired to the personal e (this writer\'s e looks like a c)', () {
      final r = decode(crisp('Malck'), user: personal(['Malek']));
      expect(r.text, 'Malek');
      // ... but not a letter that does not look like e
      expect(decode(crisp('Malxk'), user: personal(['Malek'])).text, 'Malxk');
    });

    test('the personal dictionary is read live', () {
      final user = UserLexicon();
      final decoder = LineDecoder(cs, lex, userLexicon: user);
      final lp = lpOf(crisp('Malck'));
      expect(decoder.decode(lp).text, 'Malck');
      user.add('Malek');
      expect(decoder.decode(lp).text, 'Malek');
    });

    test('a doubtful letter is settled by the word list', () {
      final r = decode(crisp('cot', maybe: {
        1: {'a': 0.45, 'o': 0.5},
      }));
      expect(r.words.single.raw, 'cot');
      expect(r.text, 'cat'); // cat is 25x more frequent
      expect(r.words.single.corrected, isTrue);
      expect(r.words.single.alternatives, contains('cot'));
    });

    test('a clear letter is not overruled by a more frequent word', () {
      expect(decode(crisp('cot')).text, 'cot');
      expect(decode(crisp('cot', maybe: {
        1: {'a': 0.02, 'o': 0.95},
      })).text, 'cot');
    });

    test('an e written like a c: Notc becomes Note', () {
      final r = decode(crisp('Notc', maybe: {
        3: {'c': 0.55, 'e': 0.35},
      }));
      expect(r.text, 'Note');
      expect(r.words.single.raw, 'Notc');
    });

    test('an n written like a u: isut becomes isnt (a contraction without its apostrophe is a word)', () {
      final r = decode(crisp('isut', maybe: {
        2: {'u': 0.6, 'n': 0.35},
      }));
      expect(r.text, 'isnt');
      expect(r.words.single.known, isTrue);
      expect(r.words.single.raw, 'isut');
      // Even a clear u: "isut" is nothing, "isnt" is a very frequent word one
      // look-alike away (the same reasoning as Malck -> Malek) ...
      expect(decode(crisp('isut')).text, 'isnt');
      // ... but a letter that does not look like n is left alone
      expect(decode(crisp('isxt')).text, 'isxt');
    });

    test('apostrophe-less contractions are known words', () {
      final r = decode(crisp('i dont know'));
      expect(r.text, 'i dont know');
      expect(r.words[1].known, isTrue);
      expect(r.words[2].known, isFalse); // "know" is not in this small list
      expect(decode(crisp("don't")).text, "don't");
    });

    test('numbers and mixed tokens are never corrected', () {
      expect(decode(crisp('c4t')).text, 'c4t');
      expect(decode(crisp('27 Oct 2025')).text, '27 Oct 2025');
      expect(decode(crisp('well-known')).text, 'well-known');
    });

    test('punctuation stays on its word; a lone mark joins the word before', () {
      expect(decode(crisp('the brain, and')).text, 'the brain, and');
      expect(decode(crisp('hello .')).text, 'hello.');
      final r = decode(crisp('hello .'));
      expect(r.words, hasLength(1));
    });
  });

  // From Mariam's first sample page (v1.3.0, neuroscience notes).
  group('spaces between unknown words and after marks', () {
    test('two long unknown words keep the hesitant space the model reads between them', () {
      // One flat prior per unknown string made one long token cheaper than
      // two words, so the model's space was dropped.
      final frames = [...crisp('Kortalaxi'), softGap, ...crisp('Mendravol')];
      expect(decode(frames).text, 'Kortalaxi Mendravol');
    });

    test('a space the model reads with 0.7 is never removed', () {
      final frames = [...crisp('Nerous'), {' ': 0.7, '_': 0.25}, ...crisp('systen')];
      expect(decode(frames).words, hasLength(2));
    });

    test('a comma or full stop read without a space gets one', () {
      expect(decode(crisp('the brain,and')).text, 'the brain, and');
      final r = decode(crisp('cord.Seizure,'));
      expect(r.text, 'cord. Seizure,');
      expect(r.words.map((w) => w.text), ['cord.', 'Seizure,']);
      for (final w in r.words) {
        expect(w.alternatives.where((a) => a.contains('.') && a.contains('S')), isEmpty,
            reason: 'no reading of the whole token is offered for a half');
      }
      // the two words still tile the frames in order
      expect(r.words.first.startFrame, 0);
      expect(r.words.first.endFrame, r.words.last.startFrame);
      expect(r.words.last.endFrame, r.timesteps);
    });

    test('abbreviations, decimals and file names are not cut', () {
      expect(decode(crisp('e.g.')).text, 'e.g.');
      expect(decode(crisp('file.txt')).text, 'file.txt');
      expect(decode(crisp('3.5')).text, '3.5');
      expect(decode(crisp('cord.seizure')).text, 'cord.seizure'); // no capital after the stop
    });

    test('acronyms are written in capitals, plurals with a small s', () {
      expect(decode(crisp('dementia, ocd, depression')).text, 'dementia, OCD, depression');
      expect(decode(crisp('Adhd')).text, 'ADHD');
      expect(decode(crisp('ssris')).text, 'SSRIs');
    });
  });

  group('case', () {
    test('the model\'s case is kept for unknown words and known words', () {
      expect(decode(crisp('Hello World')).text, 'Hello World');
      expect(decode(crisp('hello world')).text, 'hello world');
      expect(decode(crisp('Xylo')).text, 'Xylo');
      expect(decode(crisp('xYlO')).text, 'xYlO');
    });

    test('shouting is tamed for listed words, kept for unknown ones', () {
      expect(decode(crisp('NOTE')).text, 'Note');
      expect(decode(crisp('NASA')).text, 'NASA');
      expect(decode(crisp('XQZ')).text, 'XQZ');
    });

    test('a replacement copies the raw case only when the first letters agree', () {
      // raw "Cat" (capital C ambiguous with e): the replacement "eat" starts
      // with another letter, so it does not inherit the capital.
      final lexicon = Lexicon.parse('$_words\neat 90000000\n');
      final r = decode(
          crisp('Cat', maybe: {
            0: {'C': 0.4, 'e': 0.5},
            1: {'a': 0.9},
          }),
          lexicon: lexicon);
      // either reading is acceptable; if the word list reading wins it must be
      // lowercase
      expect(r.text == 'Cat' || r.text == 'eat', isTrue, reason: r.text);
      // raw "Mark" corrected from a doubtful letter keeps its capital
      final q = decode(crisp('Marl', maybe: {
        3: {'l': 0.5, 'k': 0.45},
      }));
      expect(q.text, anyOf('Marl', 'Mark'));
    });

    test('personal words are written as the user typed them', () {
      final user = personal(['Malek', 'Baghdadi']);
      expect(decode(crisp('malek baghdadi'), user: user).text, 'Malek Baghdadi');
      expect(decode(crisp('MALEK'), user: user).text, 'Malek');
    });
  });

  group('frames', () {
    test('word ranges tile the line from the first to the last frame', () {
      final frames = crisp('the cat and the world');
      final r = decode(frames);
      expect(r.timesteps, frames.length);
      expect(r.words.first.startFrame, 0);
      expect(r.words.last.endFrame, frames.length);
      for (var i = 0; i + 1 < r.words.length; i++) {
        expect(r.words[i].endFrame, r.words[i + 1].startFrame);
        expect(r.words[i].endFrame, greaterThan(r.words[i].startFrame));
      }
    });

    test('each word\'s letters lie inside its range', () {
      // "the cat": t h e at frames 0,2,4, the space at 6, c a t at 8,10,12.
      final r = decode(crisp('the cat'));
      expect(r.words[0].startFrame, lessThanOrEqualTo(0));
      expect(r.words[0].endFrame, inInclusiveRange(5, 8));
      expect(r.words[1].startFrame, inInclusiveRange(5, 8));
      expect(r.words[1].endFrame, greaterThanOrEqualTo(13));
    });

    test('a word the language layer added a space to is cut at the gap', () {
      final frames = [...crisp('are'), softGap, ...crisp('in')];
      final r = decode(frames);
      final gap = 6; // the soft gap frame
      expect(r.words[0].endFrame, lessThanOrEqualTo(gap + 1));
      expect(r.words[1].startFrame, greaterThanOrEqualTo(gap - 1));
      expect(r.words[0].endFrame, r.words[1].startFrame);
    });

    test('raw gives the model\'s own letters per word', () {
      final r = decode(crisp('cot', maybe: {
        1: {'a': 0.45, 'o': 0.5},
      }));
      expect(r.words.single.raw, 'cot');
      final two = decode([
        ...crisp('the'),
        ...crisp(' '),
        ...crisp('cot', maybe: {
          1: {'a': 0.45, 'o': 0.5},
        }),
      ]);
      expect(two.words.map((w) => w.raw), ['the', 'cot']);
      expect(two.words.map((w) => w.text), ['the', 'cat']);
    });
  });

  group('confidence', () {
    test('a clear word is more confident than a doubtful one', () {
      final clear = decode(crisp('hello'));
      // weak letters: the model shows the e with 0.3 and nothing else
      final doubtful = decode(crisp('hello', maybe: {
        1: {'e': 0.3, 'x': 0.1},
      }));
      expect(doubtful.text, 'hello');
      expect(clear.confidence, greaterThan(doubtful.confidence + 0.15));
      expect(clear.confidence, greaterThan(0.7));
      expect(clear.confidence, inInclusiveRange(0.0, 1.0));
    });

    test('a coin flip the word list decides is reported with the odds the list gives', () {
      final r = decode(crisp('cot', maybe: {
        1: {'a': 0.45, 'o': 0.5},
      }));
      expect(r.text, 'cat');
      expect(r.words.single.confidence, inInclusiveRange(0.4, 0.9));
    });

    test('a repaired look-alike is less sure than a clear reading', () {
      final repaired = decode(crisp('Malck'), user: personal(['Malek']));
      final clear = decode(crisp('Malek'), user: personal(['Malek']));
      expect(repaired.confidence, lessThan(clear.confidence));
    });

    test('one doubtful word pulls the line down, short words count less', () {
      final good = decode(crisp('the cat and the world'));
      final oneBad = decode(crisp('the cot and the world', maybe: {
        5: {'a': 0.45, 'o': 0.5},
      }));
      expect(oneBad.confidence, lessThan(good.confidence));
      expect(oneBad.confidence, closeTo(oneBad.words.map((w) => w.confidence).reduce(min), 0.35));
      final badWord = oneBad.words.firstWhere((w) => w.raw == 'cot' || w.text == 'cat');
      expect(oneBad.confidence, lessThanOrEqualTo(badWord.confidence + 0.3));
    });

    test('an unknown but clearly read word keeps a good confidence', () {
      expect(decode(crisp('Kowalski')).confidence, greaterThan(0.7));
    });
  });

  group('robustness', () {
    test('no word list and no personal dictionary: the model\'s own reading', () {
      final r = LineDecoder(cs, null).decode(lpOf(crisp('the cat')));
      expect(r.text, 'the cat');
      expect(r.words.map((w) => w.known), [false, false]);
    });

    test('a space-less charset decodes one word', () {
      final noSpace = CtcCharset(['', 'a', 'b', 'c'], blank: 0);
      final frames = framesOf(noSpace, [
        {'a': 0.9, '_': 0.05},
        {'_': 0.9},
        {'b': 0.9, '_': 0.05},
      ]);
      expect(LineDecoder(noSpace, null).decode(frames).text, 'ab');
    });

    test('random peaky matrices keep the invariants of a reading', () {
      final rng = Random(77);
      final user = personal(['Malek', 'Mariam']);
      for (var n = 0; n < 60; n++) {
        final steps = 1 + rng.nextInt(70);
        final data = <double>[];
        for (var t = 0; t < steps; t++) {
          // a peaky random distribution over all classes
          final logits = List<double>.generate(cs.classes, (_) => rng.nextDouble() * 3);
          logits[rng.nextInt(cs.classes)] += 6 + rng.nextDouble() * 4;
          if (rng.nextInt(3) == 0) logits[cs.blank] += 8;
          if (rng.nextInt(9) == 0) logits[cs.space!] += 9;
          final exps = [for (final v in logits) exp(v)];
          final sum = exps.fold(0.0, (a, b) => a + b);
          data.addAll([for (final v in exps) max(v / sum, ctcProbFloor)]);
        }
        final lp = CtcLogProbs.fromProbabilities(data, cs.classes, blank: cs.blank);
        final r = LineDecoder(cs, lex, userLexicon: user).decode(lp);
        expect(r.timesteps, steps);
        expect(r.confidence, inInclusiveRange(0.0, 1.0));
        expect(r.text, r.words.map((w) => w.text).join(' '));
        var prevEnd = 0;
        for (final w in r.words) {
          expect(w.text, isNotEmpty);
          expect(w.confidence, inInclusiveRange(0.0, 1.0));
          expect(w.startFrame, greaterThanOrEqualTo(prevEnd == 0 ? 0 : prevEnd));
          expect(w.endFrame, greaterThanOrEqualTo(w.startFrame));
          expect(w.endFrame, lessThanOrEqualTo(steps));
          expect(w.alternatives, isNot(contains(w.text)));
          prevEnd = w.endFrame;
        }
        if (r.words.isNotEmpty) {
          expect(r.words.first.startFrame, 0);
          expect(r.words.last.endFrame, steps);
        }
      }
    });

    test('a single frame is read', () {
      expect(decode([
        {'a': 0.9, '_': 0.05},
      ]).text, 'a');
    });

    test('very noisy frames never throw', () {
      final rng = Random(5);
      for (var n = 0; n < 20; n++) {
        final frames = [
          for (var t = 0; t < 30; t++)
            {
              for (final ch in ['a', 'e', 'c', ' ', 't', 'n', 'u', '_']) ch: rng.nextDouble() / 8,
            },
        ];
        final r = decode(frames);
        expect(r.confidence, inInclusiveRange(0.0, 1.0));
        for (final w in r.words) {
          expect(w.endFrame, greaterThanOrEqualTo(w.startFrame));
        }
      }
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

    List<String> sample(int n, {int top = 50000, int minLen = 3}) {
      final lines = file!.readAsLinesSync();
      final rng = Random(3);
      final out = <String>[];
      while (out.length < n) {
        final w = lines[rng.nextInt(min(top, lines.length))].split(' ').first;
        if (w.length >= minLen && RegExp(r'^[a-z]+$').hasMatch(w)) out.add(w);
      }
      return out;
    }

    const lookAlike = {'e': 'c', 'c': 'e', 'a': 'o', 'o': 'a', 'r': 's', 's': 'r', 'n': 'u', 'u': 'n', 'i': 'l', 'l': 'i'};

    /// How often a word with one look-alike slip (the model reads [wrong] where
    /// the word has the letter it looks like, and the true letter gets
    /// [right]) is restored.
    ({int fixed, int other, int total}) slips(LineDecoder d, double wrong, double right) {
      var fixed = 0, other = 0, total = 0;
      for (final w in sample(300, top: 5000)) {
        final i = w.split('').indexWhere(lookAlike.containsKey);
        if (i < 0) continue;
        final bad = w.replaceRange(i, i + 1, lookAlike[w[i]]!);
        if (real!.contains(bad)) continue;
        total++;
        final text = d.decode(lpOf(crisp(bad, maybe: {i: {bad[i]: wrong, w[i]: right}}))).text;
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
      final d = LineDecoder(cs, real);
      final changed = [
        for (final w in sample(300))
          if (d.decode(lpOf(crisp(w))).text != w) w,
      ];
      expect(changed.length, lessThanOrEqualTo(2), reason: '$changed');
    });

    test('a clear line of listed words is read as it is', () {
      if (real == null) return;
      final d = LineDecoder(cs, real);
      final rng = Random(11);
      var changed = 0;
      const lines = 60;
      for (var n = 0; n < lines; n++) {
        final line = sample(5, top: 8000).join(' ');
        if (d.decode(lpOf(crisp(line))).text != line) changed++;
        rng.nextInt(2);
      }
      expect(changed, lessThanOrEqualTo(2));
    });

    test('clearly read unlisted names are not changed', () {
      if (real == null) return;
      final d = LineDecoder(cs, real);
      const names = ['Baghdadi', 'Malek', 'Mariam', 'Kowalski', 'Nguyen', 'Haddad', 'Zhang', 'Ibrahim', 'Layla', 'Yousef', 'Rania', 'Samir', 'Hadeel', 'Omar', 'Nuerons'];
      final changed = [
        for (final n in names)
          if (d.decode(lpOf(crisp(n))).text != n) n,
      ];
      expect(changed.length, lessThanOrEqualTo(1), reason: '$changed');
    });

    test('a look-alike slip with real doubt is mostly repaired', () {
      if (real == null) return;
      final result = slips(LineDecoder(cs, real), 0.75, 0.2);
      // ignore: avoid_print
      print('doubt: fixed ${result.fixed}/${result.total}, other ${result.other}');
      expect(result.fixed / result.total, greaterThan(0.5));
      expect(result.other / result.total, lessThan(0.05));
    });

    test('a look-alike slip read with great confidence is mostly left alone', () {
      if (real == null) return;
      final result = slips(LineDecoder(cs, real), 0.97, 0.005);
      // ignore: avoid_print
      print('sure: fixed ${result.fixed}/${result.total}, other ${result.other}');
      expect(result.fixed / result.total, lessThan(0.35));
      expect(result.other / result.total, lessThan(0.05));
    });

    test('the decoded line never scores below the models own reading (whole-line objective)', () {
      if (real == null) return;
      final user = personal(['Malek']);
      final d = LineDecoder(cs, real, userLexicon: user);
      final rng = Random(21);
      for (var n = 0; n < 40; n++) {
        final line = sample(4, top: 6000).join(' ');
        final maybe = <int, Map<String, double>>{};
        for (var k = 0; k < 3; k++) {
          final i = rng.nextInt(line.length);
          final ch = line[i];
          if (ch == ' ') continue;
          maybe[i] = {ch: 0.5, lookAlike[ch] ?? 'x': 0.4};
        }
        final lp = lpOf(crisp(line, maybe: maybe));
        final reading = d.decode(lp);
        final greedy = greedyDecode(lp, cs).text;
        expect(d.scoreText(lp, reading.text), greaterThanOrEqualTo(d.scoreText(lp, greedy) - 1e-6), reason: '$line -> ${reading.text}');
      }
    });

    test('a 40-character line decodes well under 50 ms', () {
      if (real == null) return;
      final user = personal(['Malek', 'Mariam', 'Baghdadi']);
      final d = LineDecoder(cs, real, userLexicon: user);
      // 40 characters with a few doubtful letters, like a real line.
      const text = 'noting that the brain cells are working';
      expect(text.length, 39);
      final lp = lpOf(crisp(text, maybe: {
        3: {'i': 0.5, 'e': 0.4},
        14: {'e': 0.45, 'c': 0.5},
        29: {'r': 0.5, 's': 0.45},
      }));
      d.decode(lp); // builds the word list's search tree
      final sw = Stopwatch()..start();
      const runs = 20;
      late LineReading r;
      for (var i = 0; i < runs; i++) {
        r = d.decode(lp);
      }
      final perLine = sw.elapsedMicroseconds / runs / 1000;
      // ignore: avoid_print
      print('40-character line: ${perLine.toStringAsFixed(1)} ms per decode (${r.text})');
      expect(perLine, lessThan(50));
    });
  });
}
