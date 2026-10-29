import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/integrations/convert/convert_plan.dart';
import 'package:neatink/recognition/htr_channel.dart';
import 'package:neatink/recognition/text_polish.dart';

PolishSuggestion fix(String text, String from, String to, {PolishKind kind = PolishKind.spelling}) {
  final at = text.indexOf(from);
  return PolishSuggestion(original: from, replacement: to, kind: kind, reason: 'Spelling', start: at, end: at + from.length);
}

void main() {
  // Mariam's line: the recogniser was sure of "nuerons" (her slip), unsure of
  // "systa" (its misreading of "system") and of "nevrons".
  const text = 'nuerons in the central nerwos systa nevrons';
  final words = [
    (text: 'nuerons', confidence: 0.9, alternatives: <String>[]),
    (text: 'in', confidence: 0.95, alternatives: <String>[]),
    (text: 'the', confidence: 0.95, alternatives: <String>[]),
    (text: 'central', confidence: 0.78, alternatives: <String>['control']),
    (text: 'nerwos', confidence: 0.25, alternatives: <String>['nerus', 'nervous', 'nerves']),
    (text: 'systa', confidence: 0.61, alternatives: <String>[]),
    (text: 'nevrons', confidence: 0.43, alternatives: <String>['neurons.', 'herons.']),
  ];

  test('unsure words keep only the fixes the decoder weighed against the picture', () {
    final all = [
      fix(text, 'nuerons', 'neurons'),
      fix(text, 'nerwos', 'nerves'),
      fix(text, 'systa', 'syria'),
      fix(text, 'nevrons', 'neurons'),
    ];
    final weighed = weighSuggestions(all, words, 0.65);
    expect([for (final s in weighed) '${s.original}:${s.auto}'],
        ['nuerons:true', 'nerwos:true', 'systa:false', 'nevrons:true']);
    // Autocorrect applies the sure ones; the other stays a suggestion.
    expect(applyPolish(text, applicableSuggestions(text, weighed)),
        'neurons in the central nerves systa neurons');
  });

  test('capitals, contractions and grammar are applied whatever the confidence', () {
    final s = fix(text, 'systa', 'Systa', kind: PolishKind.capitalization);
    expect(weighSuggestions([s], words, 0.65).single.auto, isTrue);
  });

  test('a slip of the pen is fixed on a less sure word too, a misreading is not', () {
    // v1.11.0: with the 0.65 bar alone most of Mariam's misspellings stayed.
    const line = 'they recieve systa happend';
    final ws = [
      (text: 'they', confidence: 0.9, alternatives: <String>[]),
      (text: 'recieve', confidence: 0.5, alternatives: <String>[]),
      (text: 'systa', confidence: 0.5, alternatives: <String>[]),
      (text: 'happend', confidence: 0.2, alternatives: <String>[]),
    ];
    final weighed = weighSuggestions([
      fix(line, 'recieve', 'receive'),
      fix(line, 'systa', 'syria'),
      fix(line, 'happend', 'happened'),
    ], ws, 0.65, typoConfidence: 0.35);
    expect([for (final s in weighed) '${s.original}:${s.auto}'], ['recieve:true', 'systa:false', 'happend:false'],
        reason: 'below 0.35 even a slip is a guess');
  });
}
