import '../document/notebook_meta.dart';
import 'notebook_repository.dart';
import 'search_data.dart';
import 'text_fold.dart';

/// One notebook as search sees it.
class SearchableNotebook {
  const SearchableNotebook(this.meta, this.data);

  final NotebookMeta meta;
  final SearchData data;
}

/// Default cap on text/PDF hits reported per notebook.
const int defaultMaxSnippetHits = 5;

/// Searches [notebooks] for [query] (pure, no I/O).
///
/// Matching is a case-, accent- and whitespace-insensitive substring test
/// (see [foldForSearch]) against the title, tags, the names of the
/// notebook's folder and its ancestors in [library], text boxes, handwriting
/// (as the reader read it) and PDF text. Those report one excerpt per page,
/// at most [maxSnippetHits] per notebook: text boxes first, then
/// handwriting, then PDF text.
///
/// Results are grouped by notebook. Groups are ordered by their best hit
/// (title, then tag/folder, then text, handwriting, PDF), then most
/// recently edited first, then title and id so the order is stable.
List<SearchHit> searchNotebooks(
  String query,
  Iterable<SearchableNotebook> notebooks,
  LibraryIndex library, {
  int maxSnippetHits = defaultMaxSnippetHits,
}) {
  final q = foldForSearch(query.trim());
  if (q.trim().isEmpty) return const [];

  final foldedFolderNames = {
    for (final f in library.folders) f.id: foldForSearch(f.name),
  };
  final groups = <_Group>[];
  for (final notebook in notebooks) {
    final hits = _hitsFor(
        notebook, q, library, foldedFolderNames, maxSnippetHits);
    if (hits.isNotEmpty) {
      groups.add(_Group(notebook.meta, foldForSearch(notebook.meta.title), hits));
    }
  }
  groups.sort(_compareGroups);
  return [for (final g in groups) ...g.hits];
}

/// Ranking tier of a hit kind; lower is better. Tags and folders share a
/// tier.
int rankOf(SearchMatchKind kind) => switch (kind) {
      SearchMatchKind.title => 0,
      SearchMatchKind.tag || SearchMatchKind.folder => 1,
      SearchMatchKind.text => 2,
      SearchMatchKind.handwriting => 3,
      SearchMatchKind.pdf => 4,
    };

List<SearchHit> _hitsFor(
  SearchableNotebook notebook,
  String q,
  LibraryIndex library,
  Map<String, String> foldedFolderNames,
  int maxSnippetHits,
) {
  final meta = notebook.meta;
  final hits = <SearchHit>[];
  SearchHit hit(SearchMatchKind kind,
          {String snippet = '', String? pageId, int? pageIndex}) =>
      SearchHit(
        notebookId: meta.id,
        notebookTitle: meta.title,
        kind: kind,
        pageId: pageId,
        pageIndex: pageIndex,
        snippet: snippet,
      );

  if (foldForSearch(meta.title).contains(q)) hits.add(hit(SearchMatchKind.title));

  for (final tag in meta.tags) {
    if (foldForSearch(tag).contains(q)) {
      hits.add(hit(SearchMatchKind.tag, snippet: tag));
    }
  }

  // The notebook's folder and its ancestors (guarding against cycles in a
  // hand-edited library.json).
  final visited = <String>{};
  var folder = library.folderById(meta.folderId);
  while (folder != null && visited.add(folder.id)) {
    if (foldedFolderNames[folder.id]?.contains(q) ?? false) {
      hits.add(hit(SearchMatchKind.folder, snippet: folder.name));
    }
    folder = library.folderById(folder.parentId);
  }

  var snippetHits = 0;
  for (final kind in const [SearchMatchKind.text, SearchMatchKind.handwriting, SearchMatchKind.pdf]) {
    for (var i = 0; i < meta.pages.length; i++) {
      if (snippetHits >= maxSnippetHits) break;
      final pageId = meta.pages[i].id;
      final page = notebook.data.pages[pageId];
      if (page == null) continue;
      final (folded, original) = switch (kind) {
        SearchMatchKind.pdf => (page.foldedPdf, page.pdf),
        SearchMatchKind.handwriting => (page.foldedInk, page.ink),
        _ => (page.foldedText, page.text),
      };
      final at = folded.indexOf(q);
      if (at < 0) continue;
      hits.add(hit(kind, pageId: pageId, pageIndex: i, snippet: buildSnippet(original, at, q.length)));
      snippetHits++;
    }
  }
  return hits;
}

class _Group {
  _Group(this.meta, this.foldedTitle, this.hits)
      : bestRank = hits.map((h) => rankOf(h.kind)).reduce((a, b) => a < b ? a : b);

  final NotebookMeta meta;
  final String foldedTitle;
  final List<SearchHit> hits;
  final int bestRank;
}

int _compareGroups(_Group a, _Group b) {
  var c = a.bestRank.compareTo(b.bestRank);
  if (c != 0) return c;
  c = b.meta.updatedAt.compareTo(a.meta.updatedAt);
  if (c != 0) return c;
  c = a.foldedTitle.compareTo(b.foldedTitle);
  if (c != 0) return c;
  return a.meta.id.compareTo(b.meta.id);
}
