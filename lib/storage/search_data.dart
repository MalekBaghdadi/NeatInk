import 'text_fold.dart';

/// Searchable text of one page: typed text boxes and PDF text.
class PageSearchText {
  PageSearchText({this.text = '', this.pdf = ''});

  factory PageSearchText.fromJson(Map<String, dynamic> j) => PageSearchText(
        text: j['text'] as String? ?? '',
        pdf: j['pdf'] as String? ?? '',
      );

  /// Text of the page's text boxes, one box per line.
  final String text;

  /// Text extracted from the page's PDF background.
  final String pdf;

  /// [text] folded for matching, computed on first search.
  late final String foldedText = foldForSearch(text);

  /// [pdf] folded for matching, computed on first search.
  late final String foldedPdf = foldForSearch(pdf);

  bool get isEmpty => text.isEmpty && pdf.isEmpty;

  PageSearchText copyWith({String? text, String? pdf}) =>
      PageSearchText(text: text ?? this.text, pdf: pdf ?? this.pdf);

  Map<String, dynamic> toJson() => {
        if (text.isNotEmpty) 'text': text,
        if (pdf.isNotEmpty) 'pdf': pdf,
      };
}

/// `search.json`: the extracted text of a notebook, used by search.
///
/// ```json
/// { "version": 1, "pages": { "<pageId>": { "text": "...", "pdf": "..." } } }
/// ```
///
/// Immutable: the `with…` methods return updated copies, so a cached copy
/// can be shared with a running search.
class SearchData {
  SearchData([Map<String, PageSearchText>? pages])
      : pages = Map.unmodifiable(pages ?? const <String, PageSearchText>{});

  factory SearchData.fromJson(Map<String, dynamic> json) {
    final j = migrateSearchJson(json);
    final raw = j['pages'] as Map<String, dynamic>? ?? const {};
    return SearchData({
      for (final e in raw.entries)
        e.key: PageSearchText.fromJson(e.value as Map<String, dynamic>),
    });
  }

  static const int currentVersion = 1;

  static final SearchData empty = SearchData();

  /// Page id → text. Pages without any text have no entry.
  final Map<String, PageSearchText> pages;

  bool get isEmpty => pages.isEmpty;

  /// Sets the text-box text of [pageId] (empty removes it).
  SearchData withPageText(String pageId, String text) =>
      _withPage(pageId, (old) => old.copyWith(text: text));

  /// Sets the PDF text of each page in [textByPage] (empty removes it).
  /// Pages not mentioned keep their PDF text.
  SearchData withPdfText(Map<String, String> textByPage) {
    final next = Map.of(pages);
    for (final e in textByPage.entries) {
      final page = (next[e.key] ?? PageSearchText()).copyWith(pdf: e.value);
      _put(next, e.key, page);
    }
    return SearchData(next);
  }

  /// Drops every page whose id is not in [pageIds].
  SearchData retainPages(Set<String> pageIds) => SearchData({
        for (final e in pages.entries)
          if (pageIds.contains(e.key)) e.key: e.value,
      });

  /// Renames page ids through [newIdByOldId] (pages without a new id are
  /// dropped). Used when duplicating a notebook.
  SearchData remapPages(Map<String, String> newIdByOldId) => SearchData({
        for (final e in pages.entries)
          ?newIdByOldId[e.key]: e.value,
      });

  SearchData _withPage(
    String pageId,
    PageSearchText Function(PageSearchText old) change,
  ) {
    final next = Map.of(pages);
    _put(next, pageId, change(next[pageId] ?? PageSearchText()));
    return SearchData(next);
  }

  static void _put(
    Map<String, PageSearchText> map,
    String pageId,
    PageSearchText page,
  ) {
    if (page.isEmpty) {
      map.remove(pageId);
    } else {
      map[pageId] = page;
    }
  }

  Map<String, dynamic> toJson() => {
        'version': currentVersion,
        'pages': {for (final e in pages.entries) e.key: e.value.toJson()},
      };
}

/// Upgrades a `search.json` map to [SearchData.currentVersion].
///
/// Version 1 is the first format; add a `case` per future version bump.
Map<String, dynamic> migrateSearchJson(Map<String, dynamic> j) {
  final version = (j['version'] as num?)?.toInt() ?? 1;
  if (version > SearchData.currentVersion) {
    throw FormatException(
        'Search file version $version is newer than this app supports');
  }
  return j;
}
