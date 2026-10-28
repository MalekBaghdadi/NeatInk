import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_items.dart';

const neurons = TextCorrection(start: 0, original: 'Nuerons', replacement: 'Neurons');
const isnt = TextCorrection(start: 23, original: 'isnt', replacement: "isn't");

// "Neurons are in the brain isn't it"
//  0       8   12 15  19    25
const text = "Neurons are in the brain isn't it";
const fixedIsnt = TextCorrection(start: 25, original: 'isnt', replacement: "isn't");

TextItem box(List<TextCorrection> corrections) =>
    TextItem(id: 't', x: 0, y: 0, width: 300, height: 20, text: text, corrections: corrections);

void main() {
  test('a correction holds only where its word still is, as a whole word', () {
    expect(neurons.holdsIn(text), isTrue);
    expect(fixedIsnt.holdsIn(text), isTrue);
    expect(isnt.holdsIn(text), isFalse, reason: 'wrong offset');
    expect(neurons.holdsIn('Neuronsx are'), isFalse, reason: 'part of a longer word');
    expect(box([neurons, isnt]).liveCorrections, [neurons]);
  });

  test('corrections survive notebook files; stale ones are not written', () {
    final item = box([neurons, fixedIsnt, isnt]);
    final json = item.toJson();
    expect(json['corrections'], [
      {'at': 0, 'from': 'Nuerons', 'to': 'Neurons'},
      {'at': 25, 'from': 'isnt', 'to': "isn't"},
    ]);
    expect(TextItem.fromJson(json).corrections, [neurons, fixedIsnt]);
    expect(box(const []).toJson().containsKey('corrections'), isFalse);
    // Old files and broken entries load without corrections.
    expect(TextItem.fromJson({...json}..remove('corrections')).corrections, isEmpty);
    expect(TextItem.fromJson({...json, 'corrections': [{'at': 'x'}, 3]}).corrections, isEmpty);
  });

  test('editing the text moves the marks with their words', () {
    final item = box([neurons, fixedIsnt]);
    // Typing before "isn't" moves it; "Neurons" stays.
    final edited = item.copyWith(text: "Neurons are in the big brain isn't it");
    expect(edited.corrections, [neurons, fixedIsnt.shifted(4)]);
    expect(edited.liveCorrections, hasLength(2));
    // Editing the corrected word itself drops its mark.
    final retyped = item.copyWith(text: "Neuron are in the brain isn't it");
    expect(retyped.corrections, [fixedIsnt.shifted(-1)]);
    // Typing right after a word makes it a different word: no mark.
    expect(item.copyWith(text: "Neuronsx are in the brain isn't it").liveCorrections, [fixedIsnt.shifted(1)]);
    // Other changes keep them as they are.
    expect(item.copyWith(x: 50).corrections, [neurons, fixedIsnt]);
  });

  test('putting the written word back, or keeping the correction', () {
    final item = box([neurons, fixedIsnt]);
    final back = item.withOriginal(neurons);
    expect(back.text, "Nuerons are in the brain isn't it");
    expect(back.corrections, [fixedIsnt]);
    final both = back.withOriginal(fixedIsnt);
    expect(both.text, 'Nuerons are in the brain isnt it');
    expect(both.corrections, isEmpty);
    // A later correction moves when an earlier word changes length.
    final first = box([const TextCorrection(start: 0, original: 'Neruonss', replacement: 'Neurons'), fixedIsnt])
        .withOriginal(const TextCorrection(start: 0, original: 'Neruonss', replacement: 'Neurons'));
    expect(first.corrections, [fixedIsnt.shifted(1)]);
    expect(first.liveCorrections, hasLength(1));

    final kept = item.withoutCorrection(neurons);
    expect(kept.text, text);
    expect(kept.corrections, [fixedIsnt]);
    expect(item.withOriginal(isnt), same(item), reason: 'a stale correction changes nothing');
  });

  test('remapCorrections with an edit at the very start or end', () {
    expect(remapCorrections(text, 'So $text', [neurons]), [neurons.shifted(3)]);
    expect(remapCorrections(text, 'X$text', [neurons]), isEmpty, reason: 'glued to the word');
    expect(remapCorrections(text, '$text?', [neurons, fixedIsnt]), [neurons, fixedIsnt]);
    expect(remapCorrections(text, text, [isnt]), [isnt], reason: 'unchanged text keeps the list as is');
  });
}
