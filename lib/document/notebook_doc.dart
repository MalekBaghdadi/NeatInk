import 'notebook_meta.dart';
import 'page_content.dart';

/// What an edit touched, so listeners can repaint and autosave precisely.
class DocChange {
  const DocChange({this.pageIds = const {}, this.meta = false});

  static const DocChange none = DocChange();

  /// Pages whose [PageContent] changed.
  final Set<String> pageIds;

  /// True when [NotebookMeta] changed (page list, paper, title...).
  final bool meta;

  bool get isEmpty => pageIds.isEmpty && !meta;

  DocChange merge(DocChange o) =>
      DocChange(pageIds: {...pageIds, ...o.pageIds}, meta: meta || o.meta);

  @override
  String toString() => 'DocChange(pages: $pageIds, meta: $meta)';
}

typedef DocListener = void Function(DocChange change);

/// An open notebook in memory: metadata plus every page's content.
///
/// The editor loads all pages when the notebook opens. Mutations happen only
/// through `EditCommand`s on a `CommandStack`; after applying one, the stack
/// calls [notify] with the [DocChange] the command returned.
class NotebookDoc {
  NotebookDoc(this.meta, {Map<String, PageContent>? pages})
      : pages = pages ?? {};

  NotebookMeta meta;

  /// Page contents keyed by page id. Every id in `meta.pages` has an entry
  /// once loaded; [page] creates an empty one if missing.
  final Map<String, PageContent> pages;

  final List<DocListener> _listeners = [];

  PageContent page(String pageId) => pages.putIfAbsent(pageId, PageContent.new);

  PageMeta? pageMeta(String pageId) {
    for (final p in meta.pages) {
      if (p.id == pageId) return p;
    }
    return null;
  }

  void addListener(DocListener l) => _listeners.add(l);
  void removeListener(DocListener l) => _listeners.remove(l);

  void notify(DocChange change) {
    if (change.isEmpty) return;
    for (final l in List.of(_listeners)) {
      l(change);
    }
  }
}
