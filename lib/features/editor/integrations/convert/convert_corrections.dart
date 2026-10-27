import 'convert_layout.dart' show normalizeLineText;

// Pure helpers for the words the user types over in the review sheet: they
// feed the personal dictionary and the shared handwriting samples.

/// The words of [text]: line breaks and runs of spaces collapse, so a line
/// of text splits back into the words of the handwritten line.
List<String> splitWords(String text) {
  final t = normalizeLineText(text);
  return t.isEmpty ? <String>[] : t.split(' ');
}

/// Splits the corrected line [text] back into one entry per recognised word,
/// or returns null when the number of words changed (the user added or
/// removed a word, so words can't be matched up by position).
List<String>? alignWords(String text, int recognisedCount) {
  final words = splitWords(text);
  return words.length == recognisedCount ? words : null;
}

final RegExp _wordShape = RegExp(r"^[A-Za-z'-]{2,}$");
final RegExp _edgePunctuation = RegExp(r'''^[.,;:!?"()\[\]{}]+|[.,;:!?"()\[\]{}]+$''');

/// [word] without the punctuation around it (`"Hello,"` -> `Hello`).
String stripPunctuation(String word) => word.replaceAll(_edgePunctuation, '');

/// Whether [word] looks like a name or a word worth remembering: two or more
/// letters, apostrophes or hyphens (no digits, no spaces).
bool looksLikeWord(String word) => _wordShape.hasMatch(word);

/// The words of [finalText] the user changed: every word that differs from
/// the word [recognised] at the same position (punctuation around words
/// ignored) and looks like a name or word. Empty when the number of words
/// changed. Duplicates are dropped; order is kept.
List<String> correctedWords({
  required List<String> recognised,
  required String finalText,
}) {
  final aligned = alignWords(finalText, recognised.length);
  if (aligned == null) return const [];
  final out = <String>[];
  for (var i = 0; i < aligned.length; i++) {
    final now = stripPunctuation(aligned[i]);
    final was = stripPunctuation(recognised[i].trim());
    if (now == was || !looksLikeWord(now) || out.contains(now)) continue;
    out.add(now);
  }
  return out;
}
