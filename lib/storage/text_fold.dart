/// Text normalization for search: case-insensitive, accent-insensitive for
/// Latin letters, and whitespace-insensitive, plus excerpt building that
/// maps a match in the normalized text back to the original text.
library;

/// Latin letters with diacritics (Latin-1 Supplement and Latin
/// Extended-A) grouped by the plain lowercase letters they fold to.
const Map<String, String> _latinGroups = {
  'a': 'ÀÁÂÃÄÅàáâãäåĀāĂăĄą',
  'c': 'ÇçĆćĈĉĊċČč',
  'd': 'ÐðĎďĐđ',
  'e': 'ÈÉÊËèéêëĒēĔĕĖėĘęĚě',
  'g': 'ĜĝĞğĠġĢģ',
  'h': 'ĤĥĦħ',
  'i': 'ÌÍÎÏìíîïĨĩĪīĬĭĮįİı',
  'j': 'Ĵĵ',
  'k': 'Ķķĸ',
  'l': 'ĹĺĻļĽľĿŀŁł',
  'n': 'ÑñŃńŅņŇňŉŊŋ',
  'o': 'ÒÓÔÕÖØòóôõöøŌōŎŏŐő',
  'r': 'ŔŕŖŗŘř',
  's': 'ŚśŜŝŞşŠšſ',
  't': 'ŢţŤťŦŧ',
  'u': 'ÙÚÛÜùúûüŨũŪūŬŭŮůŰűŲų',
  'w': 'Ŵŵ',
  'y': 'ÝýÿŶŷŸ',
  'z': 'ŹźŻżŽž',
  'ae': 'Ææ',
  'oe': 'Œœ',
  'ss': 'ß',
  'ij': 'Ĳĳ',
};

/// Code unit → folded replacement, built once from [_latinGroups].
final Map<int, String> _latinFolds = {
  for (final entry in _latinGroups.entries)
    for (final unit in entry.value.codeUnits) unit: entry.key,
};

/// Folds [text] for matching: lowercase, Latin accents removed (`é` → `e`,
/// `ß` → `ss`), combining accents dropped, and every run of whitespace
/// collapsed to one space. Fold the query and the searched text with the
/// same function and compare with `contains`.
String foldForSearch(String text) => _fold(text, null, -1);

/// Folds [text] like [foldForSearch] and records, for each folded code
/// unit, the index in [text] it came from. Stops once [limit] folded units
/// were produced (when [limit] >= 0).
String _fold(String text, List<int>? origins, int limit) {
  final out = <int>[];
  var inSpace = false;
  for (var i = 0; i < text.length; i++) {
    if (limit >= 0 && out.length >= limit) break;
    final c = text.codeUnitAt(i);
    if (_isSpace(c)) {
      if (!inSpace) {
        out.add(0x20);
        origins?.add(i);
        inSpace = true;
      }
      continue;
    }
    inSpace = false;
    if (_isCombiningMark(c)) continue;
    final folded = _foldUnit(c);
    if (folded is int) {
      out.add(folded);
      origins?.add(i);
    } else {
      for (final u in (folded as String).codeUnits) {
        out.add(u);
        origins?.add(i);
      }
    }
  }
  return String.fromCharCodes(out);
}

/// Folds one UTF-16 code unit; returns an `int` (one unit) or a `String`.
Object _foldUnit(int c) {
  if (c < 0x80) {
    return (c >= 0x41 && c <= 0x5A) ? c + 0x20 : c;
  }
  final latin = _latinFolds[c];
  if (latin != null) return latin;
  // Surrogate halves (emoji, rare scripts) are kept as they are.
  if (c >= 0xD800 && c <= 0xDFFF) return c;
  // Other scripts (Greek, Cyrillic...): plain lowercase when it stays one
  // code unit, so indices remain easy to map back.
  final lower = String.fromCharCode(c).toLowerCase();
  return lower.length == 1 ? lower.codeUnitAt(0) : c;
}

bool _isSpace(int c) =>
    c == 0x20 ||
    (c >= 0x09 && c <= 0x0D) ||
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000 ||
    c == 0xFEFF;

bool _isCombiningMark(int c) => c >= 0x0300 && c <= 0x036F;

/// Builds an excerpt of about [maxLength] characters of [original] around
/// a match found at [foldedStart] (length [foldedLength]) in
/// `foldForSearch(original)`.
///
/// The excerpt is widened evenly on both sides of the match, snapped to
/// word boundaries when one is close, has its whitespace collapsed, and
/// gets a leading/trailing `…` when text was cut off on that side.
String buildSnippet(
  String original,
  int foldedStart,
  int foldedLength, {
  int maxLength = 60,
}) {
  if (original.isEmpty || foldedLength <= 0) return '';
  final origins = <int>[];
  _fold(original, origins, foldedStart + foldedLength);
  if (foldedStart >= origins.length) return '';
  final matchStart = origins[foldedStart];
  var matchEnd = origins[origins.length - 1] + 1;
  // Keep combining accents and surrogate pairs attached to the match.
  while (matchEnd < original.length &&
      (_isCombiningMark(original.codeUnitAt(matchEnd)) ||
          _isLowSurrogate(original.codeUnitAt(matchEnd)))) {
    matchEnd++;
  }

  final len = original.length;
  var from = matchStart;
  var to = matchEnd;
  final room = maxLength - (matchEnd - matchStart);
  if (room > 0) {
    final before = room ~/ 2;
    from = matchStart - before;
    to = matchEnd + (room - before);
    // Give unused room on one side to the other side.
    if (from < 0) {
      to = (to - from).clamp(0, len);
      from = 0;
    }
    if (to > len) {
      from = (from - (to - len)).clamp(0, len);
      to = len;
    }
  }

  // Snap to word boundaries when a space is close, so the excerpt does not
  // start or end in the middle of a word.
  const snapWindow = 12;
  if (from > 0 && !_isSpace(original.codeUnitAt(from - 1))) {
    for (var i = from; i < matchStart && i - from <= snapWindow; i++) {
      if (_isSpace(original.codeUnitAt(i))) {
        from = i + 1;
        break;
      }
    }
  }
  if (to < len && !_isSpace(original.codeUnitAt(to))) {
    for (var i = to - 1; i >= matchEnd && to - i <= snapWindow; i--) {
      if (_isSpace(original.codeUnitAt(i))) {
        to = i;
        break;
      }
    }
  }
  // Never split a surrogate pair.
  if (from > 0 && from < len && _isLowSurrogate(original.codeUnitAt(from))) {
    from--;
  }
  if (to > 0 && to < len && _isLowSurrogate(original.codeUnitAt(to))) {
    to++;
  }

  final body = _collapseSpaces(original.substring(from, to)).trim();
  final cutBefore = _hasTextBefore(original, from);
  final cutAfter = _hasTextAfter(original, to);
  return '${cutBefore ? '…' : ''}$body${cutAfter ? '…' : ''}';
}

bool _isLowSurrogate(int c) => c >= 0xDC00 && c <= 0xDFFF;

bool _hasTextBefore(String s, int index) {
  for (var i = index - 1; i >= 0; i--) {
    if (!_isSpace(s.codeUnitAt(i))) return true;
  }
  return false;
}

bool _hasTextAfter(String s, int index) {
  for (var i = index; i < s.length; i++) {
    if (!_isSpace(s.codeUnitAt(i))) return true;
  }
  return false;
}

String _collapseSpaces(String s) {
  final out = StringBuffer();
  var inSpace = false;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (_isSpace(c)) {
      if (!inSpace) out.write(' ');
      inSpace = true;
    } else {
      out.writeCharCode(c);
      inSpace = false;
    }
  }
  return out.toString();
}
