import 'relative_time.dart';

/// Default title offered for a new notebook, e.g. "Notebook 25 Oct 2026".
String defaultNotebookTitle(DateTime now) => 'Notebook ${formatDate(now)}';

/// [base] if no name in [existing] matches it (case-insensitively),
/// otherwise "[base] 2", "[base] 3", ... whichever is free first.
String uniqueName(String base, Iterable<String> existing) {
  final taken = {for (final e in existing) e.trim().toLowerCase()};
  if (!taken.contains(base.toLowerCase())) return base;
  for (var i = 2;; i++) {
    final candidate = '$base $i';
    if (!taken.contains(candidate.toLowerCase())) return candidate;
  }
}

/// Trims a user-entered name and collapses whitespace. Returns null when
/// nothing is left, so callers can keep the old name.
String? cleanName(String input, {int maxLength = 120}) {
  var s = input.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (s.length > maxLength) s = s.substring(0, maxLength).trimRight();
  return s.isEmpty ? null : s;
}
