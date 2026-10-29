import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/recognition/lexicon.dart';
import 'package:neatink/recognition/text_polish.dart';
import 'package:neatink/recognition/user_lexicon.dart';

// Counts on the scale of the bundled list (total about 3.6e11).
const _words = '''
filler 330000000000
the 10000000000
and 5000000000
a 6000000000
i 3000000000
it 4000000000
is 5000000000
my 1500000000
know 700000000
name 500000000
answer 300000000
apple 20000000
brain 70000000
neurons 3000000
receive 40000000
definitely 30000000
male 90000000
form 600000000
from 4000000000
storm 600000000
stork 8000000
work 600000000
word 300000000
world 400000000
hello 30000000
university 80000000
umbrella 9000000
hour 200000000
honest 70000000
user 300000000
european 100000000
orange 50000000
banana 9000000
walking 40000000
walks 30000000
stopped 60000000
cats 90000000
ice 100000000
also 900000000
bake 4000000
cake 20000000
bike 15000000
bite 15000000
bile 2000000
smith 50000000
mr 100000000
its 800000000
were 2000000000
well 800000000
tango 15000000
tangy 15000000
''';

void main() {
  final lex = Lexicon.parse(_words);

  UserLexicon personal(List<String> words) {
    final u = UserLexicon();
    words.forEach(u.add);
    return u;
  }

  TextPolisher polisher({UserLexicon? user, PolishConfig config = const PolishConfig(), Lexicon? lexicon}) =>
      TextPolisher(lexicon ?? lex, userLexicon: user, config: config);

  PolishSuggestion only(List<PolishSuggestion> s) {
    expect(s, hasLength(1), reason: '$s');
    return s.single;
  }

  group('spelling', () {
    test('a swap of two letters is fixed: Nuerons -> Neurons at the start of a sentence', () {
      final s = only(polisher().suggest('Nuerons are in the brain', sentenceStart: true));
      expect(s.original, 'Nuerons');
      expect(s.replacement, 'Neurons');
      expect(s.kind, PolishKind.spelling);
      expect(s.reason, 'Spelling');
      expect([s.start, s.end], [0, 7]);
    });

    test('a lowercase misspelling is fixed in the middle of a line', () {
      final s = only(polisher().suggest('please recieve the answer'));
      expect([s.original, s.replacement], ['recieve', 'receive']);
      expect(s.start, 7);
      expect(s.end, 14);
      final d = only(polisher().suggest('it is definately my name'));
      expect(d.replacement, 'definitely');
    });

    test('capitalised words in the middle of a sentence are names and are left alone', () {
      expect(polisher().suggest('the Nuerons are in the brain'), isEmpty);
      // Malek is one deletion from the frequent "male"
      expect(polisher().suggest('hello Malek'), isEmpty);
      expect(polisher().suggest('Malek is my name', sentenceStart: true), isEmpty);
    });

    test('at the start of a sentence only a swap of neighbouring letters is fixed', () {
      // "Wrold" is a swap of "World"; "Wold" is a deletion (also "Word"/"World")
      final swap = only(polisher().suggest('Wrold is big', sentenceStart: true).where((s) => s.kind == PolishKind.spelling).toList());
      expect(swap.replacement, 'World');
      expect(polisher().suggest('Hellp is big', sentenceStart: true).where((s) => s.kind == PolishKind.spelling), isEmpty);
    });

    test('words in capitals, with digits, odd capitals or an apostrophe are left alone', () {
      expect(polisher().suggest('NUERONS are in the brain'), isEmpty);
      expect(polisher().suggest('the nuerons2 are ok'), isEmpty);
      expect(polisher().suggest('the neUrons are ok'), isEmpty);
      expect(polisher().suggest("the neuron's brain"), isEmpty);
    });

    test('a three-letter word is only fixed by swapping two letters into a frequent word', () {
      // v1.11.0: "teh" and "adn" were left alone.
      expect(only(polisher().suggest('teh cta wifi')).replacement, 'the');
      expect(only(polisher().suggest('Teh brain', sentenceStart: true)).replacement, 'The');
      expect(polisher().suggest('the Teh brain'), isEmpty, reason: 'a capital inside a sentence: a name');
      final withWife = Lexicon.parse('filler 330000000000\nwife 100000000\n');
      expect(polisher(lexicon: withWife).suggest('the wifi here'), isEmpty);
    });

    test('listed words and their inflections are left alone', () {
      expect(polisher().suggest('walking walks stopped cats'), isEmpty);
      // not listed, but a form of a listed word
      expect(polisher().suggest('the brains were brainy and walked'), isEmpty);
    });

    test('the correction must start with the same letter', () {
      expect(polisher().suggest('the xrain is big'), isEmpty);
    });

    test('equally close, equally frequent candidates make no suggestion', () {
      // "tangq" is one edit from tango and tangy (both 15e6)
      final s = polisher().suggest('the tangq is here');
      expect(s.where((x) => x.kind == PolishKind.spelling), isEmpty);
    });

    test('a look-alike letter is a closer match than any other letter', () {
      // x and k look alike in handwriting, x and t do not
      final s = polisher().suggest('i bixe it').where((x) => x.kind == PolishKind.spelling).toList();
      expect(only(s).replacement, 'bike');
    });

    test('a clearly more frequent candidate wins over a rare one', () {
      // "stork" (8e6) and "storm" (600e6) are both one edit from "storn": 75x
      final s = polisher().suggest('the storn is big').where((x) => x.kind == PolishKind.spelling).toList();
      expect(only(s).replacement, 'storm');
    });

    test('a rare word is offered only as a close match', () {
      final tiny = Lexicon.parse('filler 330000000000\nzygote 1000000\nmicroscope 1000000\n');
      expect(only(polisher(lexicon: tiny).suggest('the zygotr is here')).replacement, 'zygote');
      expect(polisher(lexicon: tiny).suggest('a micrscopp here'), isEmpty, reason: 'two edits away');
    });

    test('long words may be two edits away', () {
      final lexicon = Lexicon.parse('filler 330000000000\nmicroscope 80000000\n');
      final s = polisher(lexicon: lexicon).suggest('a micrscopp here').where((x) => x.kind == PolishKind.spelling).toList();
      expect(only(s).replacement, 'microscope');
      final short = Lexicon.parse('filler 330000000000\nbrain 80000000\n');
      expect(polisher(lexicon: short).suggest('the brxxn is here'), isEmpty);
    });

    test('no word list, no spelling suggestions', () {
      expect(TextPolisher(null).suggest('please recieve the answer'), isEmpty);
    });

    test('the spelling rule can be switched off', () {
      expect(polisher(config: const PolishConfig(spelling: false)).suggest('please recieve the answer'), isEmpty);
    });
  });

  group('personal dictionary', () {
    test('personal words are never touched', () {
      final user = personal(['Nuerons', 'recieve', 'dont', 'iphone', 'Malek']);
      final p = polisher(user: user);
      expect(p.suggest('nuerons recieve dont iphone malek'), isEmpty);
      expect(p.suggest('iphone is it', sentenceStart: true), isEmpty);
      expect(p.suggest('dont know', sentenceStart: true), isEmpty);
    });

    test('words that are not personal still get suggestions', () {
      final p = polisher(user: personal(['Mariam']));
      expect(p.suggest('mariam dont know'), hasLength(1)); // dont only
    });
  });

  group('contractions', () {
    test('missing apostrophes are suggested', () {
      final cases = {
        'isnt': "isn't",
        'dont': "don't",
        'didnt': "didn't",
        'doesnt': "doesn't",
        'cant': "can't",
        'wont': "won't",
        'thats': "that's",
        'youre': "you're",
        'couldnt': "couldn't",
        'theyre': "they're",
      };
      cases.forEach((plain, full) {
        final s = only(polisher().suggest('it $plain here'));
        expect(s.original, plain);
        expect(s.replacement, full);
        expect(s.kind, PolishKind.contraction);
        expect(s.reason, 'Contraction');
      });
    });

    test('im and ive get a capital I', () {
      final a = only(polisher().suggest('so im here'));
      expect([a.original, a.replacement], ['im', "I'm"]);
      final b = only(polisher().suggest('and ive seen it'));
      expect([b.original, b.replacement], ['ive', "I've"]);
    });

    test('the case of the word is kept', () {
      expect(only(polisher().suggest('Dont go')).replacement, "Don't");
      expect(only(polisher().suggest('DONT go')).replacement, "DON'T");
    });

    test('words that are also real words are left alone (its, were, well, ill)', () {
      expect(polisher().suggest('its well, were ill'), isEmpty);
    });

    test('a contraction and a capital in one suggestion', () {
      final s = only(polisher().suggest('dont know', sentenceStart: true));
      expect(s.replacement, "Don't");
      expect(s.kind, PolishKind.contraction);
      expect(s.reason, 'Contraction and capital letter');
    });

    test('words with an apostrophe already are fine', () {
      expect(polisher().suggest("it isn't here and I'm fine"), isEmpty);
    });
  });

  group('capitalisation', () {
    test('a lone i becomes I', () {
      final s = only(polisher().suggest('so i know'));
      expect([s.original, s.replacement], ['i', 'I']);
      expect(s.kind, PolishKind.capitalization);
      expect(s.reason, 'Capital I');
      expect(s.start, 3);
    });

    test("i'm, i've, i'll and i'd get a capital I", () {
      for (final w in ["i'm", "i've", "i'll", "i'd"]) {
        final s = only(polisher().suggest('so $w here'));
        expect(s.replacement, 'I${w.substring(1)}');
      }
    });

    test('a roman numeral in a list marker is not touched', () {
      expect(polisher().suggest('i) the name'), isEmpty);
    });

    test('the first word after . ! ? gets a capital', () {
      final s = polisher().suggest('hello. my name is it! the answer? yes');
      expect(s.map((x) => x.replacement), ['My', 'The', 'Yes']);
      expect(s.every((x) => x.kind == PolishKind.capitalization), isTrue);
      expect(s.first.reason, 'Capital letter');
    });

    test('the first word gets a capital when the text starts a sentence', () {
      expect(only(polisher().suggest('the answer', sentenceStart: true)).replacement, 'The');
      expect(polisher().suggest('the answer'), isEmpty);
      expect(polisher().suggest('The answer', sentenceStart: true), isEmpty);
    });

    test('closing quotes and brackets do not hide a sentence end', () {
      expect(polisher().suggest('he said "hello." my name').map((x) => x.replacement), ['My']);
      expect(polisher().suggest('(it is.) the name').map((x) => x.replacement), ['The']);
    });

    test('abbreviations, initials and ellipses do not end a sentence', () {
      expect(polisher().suggest('mr. smith and e.g. the name'), isEmpty);
      expect(polisher().suggest('J. smith etc. and so'), isEmpty);
      expect(polisher().suggest('well... the name'), isEmpty);
    });

    test('a numbered list item starts a sentence', () {
      expect(polisher().suggest('2. the name').map((x) => x.replacement), ['The']);
    });

    test('tokens that are no plain words are not capitalised', () {
      expect(polisher().suggest('3rd place. 4x4 and a@b.com'), isEmpty);
    });

    test('the capital rule can be switched off', () {
      expect(polisher(config: const PolishConfig(capitalization: false)).suggest('so i know. my name'), isEmpty);
    });
  });

  group('grammar', () {
    test('a before a vowel sound becomes an', () {
      final s = only(polisher().suggest('it is a apple'));
      expect([s.original, s.replacement], ['a', 'an']);
      expect(s.kind, PolishKind.grammar);
      expect(s.start, 6);
      expect(s.end, 7);
      for (final w in ['umbrella', 'hour', 'honest', 'orange']) {
        expect(only(polisher().suggest('it is a $w')).replacement, 'an', reason: w);
      }
    });

    test('A at the start becomes An', () {
      expect(only(polisher().suggest('A apple is it')).replacement, 'An');
    });

    test('words that start with a vowel letter but a consonant sound are left alone', () {
      for (final w in ['university', 'user', 'european']) {
        expect(polisher().suggest('it is a $w'), isEmpty, reason: w);
      }
      expect(polisher().suggest('a one and a once'), isEmpty);
    });

    test('a before consonants, acronyms, punctuation and numbers is fine', () {
      expect(polisher().suggest('a banana, a FBI agent, a 8 and a'), isEmpty);
      expect(polisher().suggest('a, apple'), isEmpty);
    });

    test('a repeated function word is removed', () {
      final s = only(polisher().suggest('it is the the answer'));
      expect(s.original, 'the the');
      expect(s.replacement, 'the');
      expect(s.kind, PolishKind.grammar);
      expect(s.reason, 'Repeated word');
      expect(applyPolish('it is the the answer', [s]), 'it is the answer');
    });

    test('repeats of real doubles and across punctuation are left alone', () {
      expect(polisher().suggest('that that is it and it it'), isEmpty);
      expect(polisher().suggest('the, the answer'), isEmpty);
      expect(polisher().suggest('the. the answer').map((x) => x.replacement), ['The']);
    });

    test('an before a consonant sound becomes a', () {
      for (final w in ['banana', 'university', 'user']) {
        final s = only(polisher().suggest('it is an $w'));
        expect([s.original, s.replacement, s.reason], ['an', 'a', "Use 'a' here"], reason: w);
      }
      expect(only(polisher().suggest('An banana is it')).replacement, 'A');
      // Vowel sounds, silent h, h words in general, x and acronyms stay.
      expect(polisher().suggest('an apple, an hour, an hotel, an x-ray and an MRI'), isEmpty);
    });

    test('could of, their is and alot', () {
      final of = only(polisher().suggest('we could of know'));
      expect([of.original, of.replacement, of.kind], ['of', 'have', PolishKind.grammar]);
      expect(applyPolish('we should of gone', polisher().suggest('we should of gone')), 'we should have gone');
      final their = only(polisher().suggest('so their is a cell'));
      expect([their.original, their.replacement], ['their', 'there']);
      expect(only(polisher().suggest('Their are cells')).replacement, 'There');
      expect(only(polisher().suggest('it helps alot')).replacement, 'a lot');
      // Real uses stay: "their cells", "most of", "could, of course".
      expect(polisher().suggest('their cells are most of it, could, of course'), isEmpty);
    });

    test('the grammar rules can be switched off', () {
      final p = polisher(config: const PolishConfig(grammar: false));
      expect(p.suggest('it is a apple the the'), isEmpty);
      expect(p.suggest('we could of know their is an banana'), isEmpty);
    });
  });

  group('applyPolish', () {
    test('applies several suggestions by their offsets', () {
      const text = 'i dont know the the answer. it isnt a apple';
      final s = polisher().suggest(text, sentenceStart: true);
      expect(applyPolish(text, s), "I don't know the answer. It isn't an apple");
    });

    test('overlapping suggestions: the earlier one wins', () {
      const text = 'the the answer';
      final a = const PolishSuggestion(original: 'the the', replacement: 'the', kind: PolishKind.grammar, reason: 'x', start: 0, end: 7);
      final b = const PolishSuggestion(original: 'the', replacement: 'The', kind: PolishKind.capitalization, reason: 'x', start: 4, end: 7);
      expect(applyPolish(text, [b, a]), 'the answer');
    });

    test('a suggestion whose text is no longer there is skipped', () {
      const s = PolishSuggestion(original: 'dont', replacement: "don't", kind: PolishKind.contraction, reason: 'x', start: 2, end: 6);
      expect(applyPolish('so dont go', [s]), 'so dont go');
      expect(applyPolish('xxdont go', [s]), "xxdon't go");
      expect(applyPolish('x', [s]), 'x');
    });

    test('nothing to apply returns the text', () {
      expect(applyPolish('hello', const []), 'hello');
    });

    test('suggestions are in text order and equal by value', () {
      final s = polisher().suggest('so im here and i dont know');
      expect(s.map((x) => x.start).toList(), [...s.map((x) => x.start)]..sort());
      expect(s.first, polisher().suggest('so im here and i dont know').first);
    });
  });

  group('on the bundled word list', () {
    const candidates = [
      'assets/htr/word_freq.txt',
      r'C:\Users\Malek Baghdadi\Downloads\neatink\assets\htr\word_freq.txt',
    ];
    final file = candidates.map(File.new).where((f) => f.existsSync()).firstOrNull;
    final real = file == null ? null : Lexicon.parse(file.readAsStringSync());

    test('the example from the owner\'s notes', () {
      if (real == null) return;
      final p = TextPolisher(real);
      final s = p.suggest('Nuerons are in the brain', sentenceStart: true);
      expect(s.map((x) => '${x.original}>${x.replacement}'), ['Nuerons>Neurons']);
      expect(p.suggest('isnt working well').map((x) => '${x.original}>${x.replacement}'), ["isnt>isn't"]);
    });

    test('ordinary listed text gets no spelling suggestions', () {
      if (real == null) return;
      final p = TextPolisher(real);
      const sample = 'the quick brown fox jumps over the lazy dog while students study neurons in the brain and write notes about it';
      expect(p.suggest(sample).where((x) => x.kind == PolishKind.spelling), isEmpty);
    });

    test('names of people are not changed', () {
      if (real == null) return;
      final p = TextPolisher(real);
      expect(p.suggest('hello Malek and Baghdadi and Mariam and Kowalski'), isEmpty);
    });

    test('common misspellings are fixed', () {
      if (real == null) return;
      final p = TextPolisher(real);
      final fixed = <String, String>{};
      for (final pair in {
        'recieve': 'receive',
        'seperate': 'separate',
        'definately': 'definitely',
        'occured': 'occurred',
        'wich': 'which',
        'becuase': 'because',
        'freind': 'friend',
        'untill': 'until',
      }.entries) {
        final s = p.suggest('the ${pair.key} here').where((x) => x.kind == PolishKind.spelling).toList();
        if (s.length == 1) fixed[pair.key] = s.single.replacement;
      }
      // most of them (not every one is within the rules)
      var right = 0;
      fixed.forEach((k, v) {
        if (v == {'recieve': 'receive', 'seperate': 'separate', 'definately': 'definitely', 'occured': 'occurred', 'wich': 'which', 'becuase': 'because', 'freind': 'friend', 'untill': 'until'}[k]) right++;
      });
      expect(right, greaterThanOrEqualTo(5), reason: '$fixed');
    });

    // What autocorrect left alone, or got wrong, on the owner's page (v1.5.0).
    String fixed(TextPolisher p, String text, {bool sentenceStart = false}) =>
        applyPolish(text, p.suggest(text, sentenceStart: sentenceStart));

    test("the owner's page: look-alike letters, rarer words, glued words", () {
      if (real == null) return;
      final p = TextPolisher(real);
      expect(fixed(p, 'the lines are not auto joming'), 'the lines are not auto joining',
          reason: 'm read for in');
      expect(fixed(p, 'crazy hamberger'), 'crazy hamburger', reason: 'hamburger is word 22784');
      expect(fixed(p, 'okay this time itworked'), 'okay this time it worked');
      expect(fixed(p, "Whyisn't!", sentenceStart: true), "Why isn't!");
      expect(fixed(p, 'I a not in danger'), 'I am not in danger');
    });

    test("the owner's paragraph (v1.8.0): a name glued to a contraction, My words in splits", () {
      if (real == null) return;
      final p = TextPolisher(real);
      expect(fixed(p, "my name is Malek Baghdadidoesn't know"), "my name is Malek Baghdadi doesn't know",
          reason: 'a contraction glued to a name the list does not know');
      expect(fixed(p, "it isn't sodoesn't"), "it isn't so doesn't");
      final mine = UserLexicon()..add('Mariam');
      final withNames = TextPolisher(real, userLexicon: mine);
      expect(fixed(withNames, 'hello mariamwent home'), 'hello mariam went home', reason: 'My words split glued words');
      expect(fixed(p, "Mariam's notes"), "Mariam's notes", reason: 'a possessive is no contraction');
    });

    test('a rare listed word next to a common one is only a suspect, never changed', () {
      if (real == null) return;
      final study = File('assets/htr/subject_words.txt');
      final lex = study.existsSync()
          ? Lexicon.parse(file!.readAsStringSync(), studyText: study.readAsStringSync())
          : real;
      final p = TextPolisher(lex);
      expect(fixed(p, 'it went wong'), 'it went wong', reason: 'not changed by itself');
      expect(p.suspectsFor('wong'), contains('wrong'));
      expect(p.suspectsFor('wong').length, lessThanOrEqualTo(3));
      expect(p.suspectsFor('wong').every((w) => w.startsWith('w')), isTrue);
      expect(p.suspectsFor('Wong'), isEmpty, reason: 'a name inside a sentence');
      expect(p.suspectsFor('Wong', startsSentence: true), contains('Wrong'));
      expect(p.suspectsFor('lobe'), isEmpty, reason: 'lobe is common enough');
      expect(p.suspectsFor('wrong'), isEmpty);
      if (study.existsSync()) expect(p.suspectsFor('soma'), isEmpty, reason: 'study words are never suspects');
    });

    test('an unclear word is left alone rather than turned into another word', () {
      if (real == null) return;
      final p = TextPolisher(real);
      // "onvert" is as close to "overt" as to "convert": no guess.
      expect(fixed(p, 'why did that not onvert'), 'why did that not onvert');
      expect(fixed(p, 'hello Skyler'), 'hello Skyler', reason: 'a name');
    });

    test('suggesting for a page of text is fast', () {
      if (real == null) return;
      final p = TextPolisher(real);
      p.suggest('warm up recieve'); // builds the search tree
      final sw = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        p.suggest('nuerons are in the brain and i dont know why the freind recieve it', sentenceStart: true);
      }
      expect(sw.elapsedMilliseconds / 20, lessThan(100));
    });
  });

  // v1.11.0, Mariam: autocorrect "mostly doesn't recognise wrong words".
  // On a list of 126 common misspellings, 25 were not even underlined.
  group('slips of the pen', () {
    // Counts of the bundled list.
    final words = Lexicon.parse('''
filler 330000000000
the 26548583149
that 4000373255
with 2591390604
what 611266211
want 103845898
this 1913024043
final 48312451
finally 62381205
happen 19347696
happened 30889378
happens 14236413
begin 34655431
beginning 57165133
real 90782636
argue 11495418
argument 32182995
brain 29690816
receive 33869240
relieve 4682358
neurons 4414312
nervous 14672716
brainstorm 258924
''');
    TextPolisher p() => TextPolisher(words);
    String? fixOf(String word) =>
        p().suggest('the $word here').where((s) => s.original == word).firstOrNull?.replacement;

    test('a word that only looks like a form of a listed word is fixed and underlined', () {
      expect(fixOf('finaly'), 'finally');
      expect(fixOf('happend'), 'happened');
      expect(fixOf('begining'), 'beginning');
      expect(fixOf('arguement'), 'argument');
      for (final w in ['finaly', 'happend', 'begining']) {
        expect(p().isKnownSpelling(w), isFalse, reason: w);
      }
    });

    test('a real form the list lacks stays as written', () {
      expect(fixOf('brainstorms'), isNull);
      expect(p().isKnownSpelling('brainstorms'), isTrue);
      expect(fixOf('finals'), isNull);
    });

    test('two letters swapped cost as little as a look-alike letter', () {
      expect(fixOf('taht'), 'that');
      expect(fixOf('wiht'), 'with');
      expect(fixOf('waht'), 'what', reason: 'not "want": a swap, and far more frequent');
      expect(fixOf('recieve'), 'receive', reason: 'not "relieve"');
      expect(fixOf('neruons'), 'neurons', reason: 'not "nervous"');
    });

    test('a glued word is only split into real words', () {
      // The list has "ta", "ht", "wi" as abbreviations: "taht" was "ta ht".
      final withBits = Lexicon.parse('filler 330000000000\nta 90000000\nht 90000000\nwi 90000000\nself 90000000\nie 90000000\n');
      final q = TextPolisher(withBits);
      for (final w in ['taht', 'wiht', 'selfie']) {
        expect(q.suggest('the $w here'), isEmpty, reason: w);
      }
    });

    test('misspellings everybody makes are fixed even when they land on a name', () {
      expect(fixOf('brian'), 'brain');
      expect(fixOf('thier'), 'their');
      expect(p().suggest('the Brian here'), isEmpty, reason: 'a name inside a sentence');
      expect(p().isKnownSpelling('brian'), isFalse);
    });

    test('a slip of the pen is told from a misreading', () {
      for (final (a, b) in [('recieve', 'receive'), ('finaly', 'finally'), ('alot', 'a lot'), ('happend', 'happened')]) {
        expect(TextPolisher.isTypoShaped(a, b), isTrue, reason: '$a $b');
      }
      for (final (a, b) in [('systa', 'syria'), ('visud', 'virus'), ('nevrons', 'neurons'), ('cat', 'cat')]) {
        expect(TextPolisher.isTypoShaped(a, b), isFalse, reason: '$a $b');
      }
    });
  });

  test('British and American spellings are both right', () {
    final us = Lexicon.parse('filler 330000000000\nthe 26548583149\ndepolarized 100000\nbehavior 30000000\ncenter 60000000\netiology 300000\nlabeled 5000000\norganization 50000000\n');
    final uk = Lexicon.parse('filler 330000000000\nthe 26548583149\ndepolarised 100000\nbehaviour 30000000\ncentre 60000000\naetiology 300000\nlabelled 5000000\norganisation 50000000\n');
    for (final (lex, words) in [
      (us, ['depolarised', 'behaviour', 'centre', 'aetiology', 'labelled', 'organisation']),
      // (Not `e` -> `ae`: there is no telling where an `a` would go.)
      (uk, ['depolarized', 'behavior', 'center', 'labeled', 'organization']),
    ]) {
      final p = TextPolisher(lex);
      for (final w in words) {
        expect(p.suggest('the $w here'), isEmpty, reason: w);
        expect(p.isKnownSpelling(w), isTrue, reason: w);
      }
    }
  });
}
