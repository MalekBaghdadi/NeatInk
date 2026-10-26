import '../../storage/notebook_repository.dart';

/// The search hits of one notebook, in the order the repository returned
/// them.
class SearchGroup {
  const SearchGroup({
    required this.notebookId,
    required this.notebookTitle,
    required this.hits,
  });

  final String notebookId;
  final String notebookTitle;
  final List<SearchHit> hits;

  /// Page to open when the notebook itself (not a hit) is tapped: the first
  /// page-specific hit's page, or null to let the editor reopen where the
  /// user left off.
  int? get firstPageIndex {
    for (final h in hits) {
      if (h.pageIndex != null) return h.pageIndex;
    }
    return null;
  }
}

/// Groups [hits] by notebook. Groups keep the order in which each notebook
/// first appears, and hits keep their order inside a group, so the
/// repository's ranking is preserved even if its hits are interleaved.
List<SearchGroup> groupSearchHits(Iterable<SearchHit> hits) {
  final byNotebook = <String, List<SearchHit>>{};
  final titles = <String, String>{};
  for (final h in hits) {
    byNotebook.putIfAbsent(h.notebookId, () => []).add(h);
    titles.putIfAbsent(h.notebookId, () => h.notebookTitle);
  }
  return [
    for (final e in byNotebook.entries)
      SearchGroup(
        notebookId: e.key,
        notebookTitle: titles[e.key]!,
        hits: List.unmodifiable(e.value),
      ),
  ];
}

/// A `[start, end)` character range of a match inside a text.
typedef MatchRange = ({int start, int end});

/// Every non-overlapping, case-insensitive occurrence of [query] in [text],
/// left to right. The query is trimmed; an empty query matches nothing.
///
/// Matching uses `toLowerCase` on both sides only when that keeps the
/// string length, so the ranges always index into the original [text].
List<MatchRange> findMatches(String text, String query) {
  final q = query.trim();
  if (q.isEmpty || text.isEmpty) return const [];
  final lowerText = text.toLowerCase();
  final lowerQuery = q.toLowerCase();
  // A few characters (e.g. 'İ') change length when lower-cased; fall back to
  // an exact-case search rather than return ranges that are off by one.
  final haystack = lowerText.length == text.length ? lowerText : text;
  final needle = lowerText.length == text.length ? lowerQuery : q;

  final ranges = <MatchRange>[];
  var from = 0;
  while (from <= haystack.length - needle.length) {
    final at = haystack.indexOf(needle, from);
    if (at < 0) break;
    ranges.add((start: at, end: at + needle.length));
    from = at + needle.length;
  }
  return ranges;
}

/// Short user-facing name of what a hit matched.
String searchMatchKindLabel(SearchMatchKind kind) => switch (kind) {
      SearchMatchKind.title => 'Title',
      SearchMatchKind.tag => 'Tag',
      SearchMatchKind.folder => 'Folder',
      SearchMatchKind.text => 'Typed text',
      SearchMatchKind.pdf => 'PDF text',
    };

/// The text a result row shows: the snippet, or for title matches (which
/// have no snippet) the notebook title itself.
String searchHitDisplayText(SearchHit hit) =>
    hit.snippet.isNotEmpty ? hit.snippet : hit.notebookTitle;
