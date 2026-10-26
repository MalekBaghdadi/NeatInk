import '../../document/notebook_meta.dart';
import 'folder_tree.dart' show naturalCompare;

/// Longest tag the UI accepts, in characters.
const int maxTagLength = 40;

/// Cleans up a tag typed by the user: trims it, drops leading `#`s,
/// collapses inner whitespace and caps the length. Returns null when
/// nothing is left.
String? normalizeTag(String input) {
  var t = input.trim();
  while (t.startsWith('#')) {
    t = t.substring(1).trimLeft();
  }
  t = t.replaceAll(RegExp(r'\s+'), ' ');
  if (t.length > maxTagLength) t = t.substring(0, maxTagLength).trimRight();
  return t.isEmpty ? null : t;
}

/// Normalizes every tag and removes duplicates case-insensitively, keeping
/// the first spelling and the original order.
List<String> normalizeTags(Iterable<String> tags) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in tags) {
    final t = normalizeTag(raw);
    if (t != null && seen.add(t.toLowerCase())) out.add(t);
  }
  return out;
}

/// Whether [notebook] carries [tag] (case-insensitive).
bool hasTag(NotebookMeta notebook, String tag) {
  final key = tag.toLowerCase();
  return notebook.tags.any((t) => t.toLowerCase() == key);
}

/// Every distinct tag used by [notebooks] (case-insensitive), in name order.
/// When spellings differ, the alphabetically first one is shown.
List<String> collectTags(Iterable<NotebookMeta> notebooks) {
  final byKey = <String, String>{};
  for (final n in notebooks) {
    for (final raw in n.tags) {
      final t = normalizeTag(raw);
      if (t == null) continue;
      final key = t.toLowerCase();
      final existing = byKey[key];
      if (existing == null || t.compareTo(existing) < 0) byKey[key] = t;
    }
  }
  return byKey.values.toList()..sort(naturalCompare);
}
