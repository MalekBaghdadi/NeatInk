import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/recognition/lexicon.dart';
import 'package:neatink/recognition/spell_check.dart';
import 'package:neatink/recognition/text_polish.dart';
import 'package:neatink/recognition/user_lexicon.dart';

void main() {
  final words = File('assets/htr/word_freq.txt');
  final study = File('assets/htr/subject_words.txt');
  final lexicon = Lexicon.parse(words.readAsStringSync(), studyText: study.readAsStringSync());

  SpellChecker checker([UserLexicon? user]) => SpellChecker(TextPolisher(lexicon, userLexicon: user));

  String marked(SpellChecker c, String text) =>
      [for (final m in c.marksFor(text)) '${text.substring(m.start, m.end)}:${m.kind.name}'].join(' ');

  test('a correct sentence has no marks', () {
    expect(checker().marksFor('The hippocampus consolidates memories & communicates with other parts.'), isEmpty);
  });

  test('unknown words are marked, without their punctuation', () {
    final c = checker();
    const text = 'The thalamus is a relay station for sensoy info, (visud).';
    expect(marked(c, text), 'sensoy:unknown visud:unknown');
    final m = c.marksFor(text).first;
    expect(text.substring(m.start, m.end), 'sensoy');
  });

  test('a rare word with a letter left out of a frequent one is a suspect', () {
    expect(marked(checker(), 'Malek is wong about it'), 'wong:suspect');
    // ... but not one letter swapped for another, or another ending.
    expect(checker().marksFor('Sensory info and specifics'), isEmpty);
    expect(checker().suggestionsFor('wong', SpellMarkKind.suspect), contains('wrong'));
  });

  test('numbers, acronyms, possessives, forms and hyphenated words are left alone', () {
    expect(checker().marksFor("Mariam's 3 OCD notes: 12kg, brainstorms, well-known, x2, e.g."), isEmpty);
  });

  test('words of the personal dictionary are known, also after the first check', () {
    final user = UserLexicon();
    final c = checker(user);
    expect(marked(c, 'Ask Zorblat'), 'Zorblat:unknown');
    user.add('Zorblat');
    expect(c.marksFor('Ask Zorblat'), isEmpty);
  });

  test('an ignored word is no longer marked', () {
    final c = checker();
    expect(marked(c, 'sensoy Sensoy'), 'sensoy:unknown Sensoy:unknown');
    c.ignore('Sensoy');
    expect(c.marksFor('sensoy Sensoy'), isEmpty);
  });

  test('suggestions keep the capital and put the likeliest first', () {
    final c = checker();
    expect(c.suggestionsFor('sensoy', SpellMarkKind.unknown).first, 'sensory');
    expect(c.suggestionsFor('Procsing', SpellMarkKind.unknown), contains('Processing'));
    expect(c.suggestionsFor('itworked', SpellMarkKind.unknown), contains('it worked'));
    expect(c.suggestionsFor('qqqqqqqqqqqq', SpellMarkKind.unknown), isEmpty);
  });

  test('without a word list nothing is marked', () {
    expect(SpellChecker(TextPolisher(null)).marksFor('sensoy wong'), isEmpty);
  });

  test('sentence starts', () {
    expect(SpellChecker.startsSentenceAt('Hello there', 0), isTrue);
    expect(SpellChecker.startsSentenceAt('Hello there', 6), isFalse);
    expect(SpellChecker.startsSentenceAt('It ended. Then', 10), isTrue);
  });
}
