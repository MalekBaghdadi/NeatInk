import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/storage/notebook_repository.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// A complete, in-memory [NotebookRepository] for tests.
///
/// It behaves like the file repository without touching the disk:
/// * Everything is stored as JSON text and decoded again on every read, so
///   callers never share objects with the store. A test that mutates a
///   [PageContent] after saving it, or forgets to save, sees the bug.
/// * Ids come from [Uuid] and timestamps from an injectable clock, so tests
///   can control ordering.
/// * Paths ([thumbnailPath], [sourcePdfPath], [assetPath]) point below
///   [rootPath], which does not exist on disk.
///
/// Extra inspection helpers (marked "Test helper") let tests check what was
/// written without going through the interface.
class InMemoryNotebookRepository implements NotebookRepository {
  InMemoryNotebookRepository({
    Uuid? uuid,
    DateTime Function()? clock,
    this.rootPath = '/in-memory-neatink',
  })  : _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now;

  final Uuid _uuid;
  final DateTime Function() _clock;

  /// Pretend root directory used to build file paths.
  final String rootPath;

  /// notebook id → `notebook.json` text. Insertion order is kept.
  final Map<String, String> _metas = {};

  /// notebook id → page id → page JSON text.
  final Map<String, Map<String, String>> _pages = {};

  /// notebook id → page id → typed text (refreshed by [savePage]).
  final Map<String, Map<String, String>> _typedText = {};

  /// notebook id → page id → PDF text (from [savePdfText]).
  final Map<String, Map<String, String>> _pdfText = {};

  /// notebook id → page id → (handwriting text, key) (from
  /// [saveHandwritingText]).
  final Map<String, Map<String, (String, String)>> _inkText = {};

  /// notebook id → asset file name → bytes.
  final Map<String, Map<String, Uint8List>> _assets = {};

  /// notebook id → thumbnail PNG bytes.
  final Map<String, Uint8List> _thumbnails = {};

  /// notebook id → path of the PDF the notebook was created from.
  final Map<String, String> _pdfSources = {};

  String? _libraryJson;

  // ---------------------------------------------------------------------
  // Test helpers
  // ---------------------------------------------------------------------

  /// Test helper: number of stored notebooks.
  int get notebookCount => _metas.length;

  /// Test helper: page ids that have a stored page file for [notebookId].
  Set<String> storedPageIds(String notebookId) =>
      Set.of(_pages[notebookId]?.keys ?? const <String>[]);

  /// Test helper: stored thumbnail bytes, or null.
  Uint8List? thumbnailBytes(String notebookId) => _thumbnails[notebookId];

  /// Test helper: stored asset bytes, or null.
  Uint8List? assetBytes(String notebookId, String asset) =>
      _assets[notebookId]?[asset];

  /// Test helper: the original path handed to [createPdfNotebook].
  String? importedPdfPath(String notebookId) => _pdfSources[notebookId];

  /// Test helper: whether [saveLibrary] was ever called.
  bool get hasSavedLibrary => _libraryJson != null;

  // ---------------------------------------------------------------------
  // Notebooks
  // ---------------------------------------------------------------------

  @override
  Future<List<NotebookMeta>> listNotebooks() async =>
      [for (final json in _metas.values) _decodeMeta(json)];

  @override
  Future<NotebookMeta?> loadMeta(String notebookId) async {
    final json = _metas[notebookId];
    return json == null ? null : _decodeMeta(json);
  }

  @override
  Future<NotebookMeta> createNotebook({
    required String title,
    required Paper paper,
    int pageCount = 1,
    String? folderId,
    int? coverColor,
  }) async {
    final now = _clock();
    final meta = NotebookMeta(
      id: _uuid.v4(),
      title: title,
      createdAt: now,
      updatedAt: now,
      defaultPaper: paper,
      pages: [
        for (var i = 0; i < math.max(1, pageCount); i++)
          PageMeta(id: _uuid.v4(), paper: paper),
      ],
      folderId: folderId,
      coverColor: coverColor ?? NotebookMeta.defaultCoverColor,
    );
    _metas[meta.id] = _encode(meta.toJson());
    return _decodeMeta(_metas[meta.id]!);
  }

  @override
  Future<NotebookMeta> createPdfNotebook({
    required String title,
    required String sourcePdfPath,
    required List<PdfPageSize> pageSizes,
    String? folderId,
  }) async {
    if (pageSizes.isEmpty) {
      throw ArgumentError.value(pageSizes, 'pageSizes', 'PDF has no pages');
    }
    final now = _clock();
    const pdfPaper = Paper(type: PaperType.blank);
    final meta = NotebookMeta(
      id: _uuid.v4(),
      title: title,
      createdAt: now,
      updatedAt: now,
      kind: NotebookKind.pdf,
      defaultPaper: pdfPaper,
      pages: [
        for (var i = 0; i < pageSizes.length; i++)
          PageMeta(
            id: _uuid.v4(),
            width: pageSizes[i].width,
            height: pageSizes[i].height,
            paper: pdfPaper,
            pdfPageIndex: i,
          ),
      ],
      folderId: folderId,
    );
    _metas[meta.id] = _encode(meta.toJson());
    _pdfSources[meta.id] = sourcePdfPath;
    return _decodeMeta(_metas[meta.id]!);
  }

  @override
  Future<void> saveMeta(NotebookMeta meta) async {
    _metas[meta.id] = _encode(meta.toJson());
    // Like the file repository: page files that left the page list go away.
    final keep = {for (final pg in meta.pages) pg.id};
    _pages[meta.id]?.removeWhere((id, _) => !keep.contains(id));
    _typedText[meta.id]?.removeWhere((id, _) => !keep.contains(id));
  }

  @override
  Future<PageContent> loadPage(String notebookId, String pageId) async {
    final json = _pages[notebookId]?[pageId];
    return json == null ? PageContent() : PageContent.fromJson(_decode(json));
  }

  @override
  Future<void> savePage(
      String notebookId, String pageId, PageContent content) async {
    _pages.putIfAbsent(notebookId, () => {})[pageId] =
        _encode(content.toJson());
    final text = [
      for (final t in content.texts)
        if (t.text.trim().isNotEmpty) t.text,
    ].join('\n');
    final byPage = _typedText.putIfAbsent(notebookId, () => {});
    if (text.isEmpty) {
      byPage.remove(pageId);
    } else {
      byPage[pageId] = text;
    }
  }

  @override
  Future<void> renameNotebook(String notebookId, String title) async {
    final meta = await _requireMeta(notebookId);
    _metas[notebookId] =
        _encode(meta.copyWith(title: title, updatedAt: _clock()).toJson());
  }

  @override
  Future<void> deleteNotebook(String notebookId) async {
    _metas.remove(notebookId);
    _pages.remove(notebookId);
    _typedText.remove(notebookId);
    _pdfText.remove(notebookId);
    _assets.remove(notebookId);
    _thumbnails.remove(notebookId);
    _pdfSources.remove(notebookId);
  }

  /// notebook id -> a notebook in the Trash.
  final Map<String, _Trashed> _trash = {};

  @override
  Future<void> trashNotebook(String notebookId) async {
    final meta = await _requireMeta(notebookId);
    _trash[notebookId] = _Trashed(
      deletedAt: _clock(),
      meta: _metas.remove(notebookId)!,
      pages: _pages.remove(notebookId),
      typedText: _typedText.remove(notebookId),
      pdfText: _pdfText.remove(notebookId),
      inkText: _inkText.remove(notebookId),
      assets: _assets.remove(notebookId),
      thumbnail: _thumbnails.remove(notebookId),
      pdfSource: _pdfSources.remove(notebookId),
    );
    assert(meta.id == notebookId);
  }

  @override
  Future<List<TrashedNotebook>> listTrash() async {
    final out = [
      for (final MapEntry(key: id, value: t) in _trash.entries)
        TrashedNotebook(
          meta: _decodeMeta(t.meta).copyWith(id: id),
          deletedAt: t.deletedAt,
          thumbnailPath: t.thumbnail == null ? null : p.join(rootPath, 'trash', id, 'thumb.png'),
        ),
    ];
    out.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return out;
  }

  @override
  Future<NotebookMeta> restoreFromTrash(String notebookId) async {
    final t = _trash.remove(notebookId);
    if (t == null) throw StateError('Not in the Trash: $notebookId');
    final id = _metas.containsKey(notebookId) ? _uuid.v4() : notebookId;
    var meta = _decodeMeta(t.meta).copyWith(id: id);
    if (meta.folderId != null && (await loadLibrary()).folderById(meta.folderId) == null) {
      meta = meta.copyWith(clearFolder: true);
    }
    _metas[id] = _encode(meta.toJson());
    if (t.pages != null) _pages[id] = t.pages!;
    if (t.typedText != null) _typedText[id] = t.typedText!;
    if (t.pdfText != null) _pdfText[id] = t.pdfText!;
    if (t.inkText != null) _inkText[id] = t.inkText!;
    if (t.assets != null) _assets[id] = t.assets!;
    if (t.thumbnail != null) _thumbnails[id] = t.thumbnail!;
    if (t.pdfSource != null) _pdfSources[id] = t.pdfSource!;
    return meta;
  }

  @override
  Future<void> deleteFromTrash(String notebookId) async => _trash.remove(notebookId);

  @override
  Future<int> emptyTrash({DateTime? before}) async {
    final gone = [
      for (final MapEntry(key: id, value: t) in _trash.entries)
        if (before == null || t.deletedAt.isBefore(before)) id,
    ];
    gone.forEach(_trash.remove);
    return gone.length;
  }

  @override
  Future<NotebookMeta> duplicateNotebook(String notebookId) async {
    final source = await _requireMeta(notebookId);
    final now = _clock();
    final newId = _uuid.v4();
    final pageIdMap = {for (final pg in source.pages) pg.id: _uuid.v4()};
    final copy = source.copyWith(
      id: newId,
      title: '${source.title} (copy)',
      createdAt: now,
      updatedAt: now,
      pages: [
        for (final pg in source.pages) pg.copyWith(id: pageIdMap[pg.id]),
      ],
    );
    _metas[newId] = _encode(copy.toJson());

    Map<String, V> remapPages<V>(Map<String, V>? byPage) => {
          for (final e in (byPage ?? <String, V>{}).entries)
            if (pageIdMap.containsKey(e.key)) pageIdMap[e.key]!: e.value,
        };
    _pages[newId] = remapPages(_pages[notebookId]);
    _typedText[newId] = remapPages(_typedText[notebookId]);
    _pdfText[newId] = remapPages(_pdfText[notebookId]);
    _assets[newId] = {
      for (final e in (_assets[notebookId] ?? const {}).entries)
        e.key: Uint8List.fromList(e.value),
    };
    final thumb = _thumbnails[notebookId];
    if (thumb != null) _thumbnails[newId] = Uint8List.fromList(thumb);
    final pdf = _pdfSources[notebookId];
    if (pdf != null) _pdfSources[newId] = pdf;
    return _decodeMeta(_metas[newId]!);
  }

  @override
  String sourcePdfPath(String notebookId) =>
      p.join(_notebookDir(notebookId), 'source.pdf');

  // ---------------------------------------------------------------------
  // Assets and thumbnails
  // ---------------------------------------------------------------------

  /// Reads [sourceFilePath] synchronously (so it also works inside widget
  /// tests, where real async file IO never completes). Throws a
  /// [FileSystemException] when the file is missing, like a real copy.
  @override
  Future<String> addAsset(String notebookId, String sourceFilePath) async {
    final bytes = File(sourceFilePath).readAsBytesSync();
    return addAssetBytes(notebookId, bytes, p.extension(sourceFilePath));
  }

  @override
  Future<String> addAssetBytes(
      String notebookId, Uint8List bytes, String extension) async {
    final ext = extension.startsWith('.') ? extension.substring(1) : extension;
    final name = ext.isEmpty ? _uuid.v4() : '${_uuid.v4()}.${ext.toLowerCase()}';
    _assets.putIfAbsent(notebookId, () => {})[name] =
        Uint8List.fromList(bytes);
    return name;
  }

  @override
  Future<Uint8List> readAsset(String notebookId, String asset) async {
    final bytes = _assets[notebookId]?[asset];
    if (bytes == null) throw StateError('no asset $asset in $notebookId');
    return Uint8List.fromList(bytes);
  }

  @override
  String assetPath(String notebookId, String asset) =>
      p.join(_notebookDir(notebookId), 'assets', asset);

  @override
  Future<void> saveThumbnail(String notebookId, Uint8List png) async {
    _thumbnails[notebookId] = Uint8List.fromList(png);
  }

  @override
  String thumbnailPath(String notebookId) =>
      p.join(_notebookDir(notebookId), 'thumb.png');

  @override
  String recordingsFolder(String notebookId) => p.join(_notebookDir(notebookId), 'audio');

  // ---------------------------------------------------------------------
  // Library and search
  // ---------------------------------------------------------------------

  @override
  Future<LibraryIndex> loadLibrary() async {
    final json = _libraryJson;
    return json == null
        ? const LibraryIndex()
        : LibraryIndex.fromJson(_decode(json));
  }

  @override
  Future<void> saveLibrary(LibraryIndex library) async {
    _libraryJson = _encode(library.toJson());
  }

  @override
  Future<void> savePdfText(
      String notebookId, Map<String, String> textByPage) async {
    _pdfText[notebookId] = Map.of(textByPage);
  }

  @override
  Future<void> saveHandwritingText(String notebookId, String pageId, {required String text, required String key}) async {
    _inkText.putIfAbsent(notebookId, () => {})[pageId] = (text, key);
  }

  @override
  Future<Map<String, String>> handwritingKeys(String notebookId) async => {
        for (final e in (_inkText[notebookId] ?? const <String, (String, String)>{}).entries) e.key: e.value.$2,
      };

  /// Test helper: the handwriting text stored for a page, or null.
  String? handwritingText(String notebookId, String pageId) => _inkText[notebookId]?[pageId]?.$1;

  /// Notebooks are visited most recently edited first (ties by id), and each
  /// notebook's hits come in this order: title, tags, folders (its folder
  /// and the folders above it), then typed text and PDF text page by page.
  @override
  Future<List<SearchHit>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final library = await loadLibrary();
    final metas = await listNotebooks()
      ..sort((a, b) {
        final c = b.updatedAt.compareTo(a.updatedAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });

    final hits = <SearchHit>[];
    for (final m in metas) {
      SearchHit hit(SearchMatchKind kind,
              {String snippet = '', String? pageId, int? pageIndex}) =>
          SearchHit(
            notebookId: m.id,
            notebookTitle: m.title,
            kind: kind,
            snippet: snippet,
            pageId: pageId,
            pageIndex: pageIndex,
          );

      if (m.title.toLowerCase().contains(q)) hits.add(hit(SearchMatchKind.title));
      for (final t in m.tags) {
        if (t.toLowerCase().contains(q)) {
          hits.add(hit(SearchMatchKind.tag, snippet: t));
        }
      }
      for (final f in _folderChain(library, m.folderId)) {
        if (f.name.toLowerCase().contains(q)) {
          hits.add(hit(SearchMatchKind.folder, snippet: f.name));
        }
      }
      for (var i = 0; i < m.pages.length; i++) {
        final pageId = m.pages[i].id;
        for (final (kind, source) in [
          (SearchMatchKind.text, _typedText[m.id]),
          (SearchMatchKind.handwriting, {for (final e in (_inkText[m.id] ?? const <String, (String, String)>{}).entries) e.key: e.value.$1}),
          (SearchMatchKind.pdf, _pdfText[m.id]),
        ]) {
          final text = source?[pageId];
          if (text == null) continue;
          final at = text.toLowerCase().indexOf(q);
          if (at < 0) continue;
          hits.add(hit(kind,
              snippet: snippetAround(text, at, q.length),
              pageId: pageId,
              pageIndex: i));
        }
      }
    }
    return hits;
  }

  /// A one-line excerpt of [text] around the match at [start]: up to 30
  /// characters before and 60 after, whitespace collapsed, with "…" where
  /// the text was cut.
  static String snippetAround(String text, int start, int length) {
    final from = math.max(0, start - 30);
    final to = math.min(text.length, start + length + 60);
    final body = text.substring(from, to).replaceAll(RegExp(r'\s+'), ' ').trim();
    return '${from > 0 ? '…' : ''}$body${to < text.length ? '…' : ''}';
  }

  // ---------------------------------------------------------------------

  String _notebookDir(String id) => p.join(rootPath, 'notebooks', id);

  Future<NotebookMeta> _requireMeta(String id) async {
    final meta = await loadMeta(id);
    if (meta == null) throw StateError('No notebook with id $id');
    return meta;
  }

  /// [folderId] and its ancestors, innermost first. Stops on unknown ids
  /// and on cycles.
  static List<Folder> _folderChain(LibraryIndex library, String? folderId) {
    final chain = <Folder>[];
    final seen = <String>{};
    var cur = folderId;
    while (cur != null && seen.add(cur)) {
      final f = library.folderById(cur);
      if (f == null) break;
      chain.add(f);
      cur = f.parentId;
    }
    return chain;
  }

  static String _encode(Map<String, dynamic> json) => jsonEncode(json);

  static Map<String, dynamic> _decode(String json) =>
      jsonDecode(json) as Map<String, dynamic>;

  static NotebookMeta _decodeMeta(String json) =>
      NotebookMeta.fromJson(_decode(json));
}

/// A notebook in the Trash of [InMemoryNotebookRepository]: everything it
/// had, as stored.
class _Trashed {
  _Trashed({
    required this.deletedAt,
    required this.meta,
    this.pages,
    this.typedText,
    this.pdfText,
    this.inkText,
    this.assets,
    this.thumbnail,
    this.pdfSource,
  });

  final DateTime deletedAt;
  final String meta;
  final Map<String, String>? pages;
  final Map<String, String>? typedText;
  final Map<String, String>? pdfText;
  final Map<String, (String, String)>? inkText;
  final Map<String, Uint8List>? assets;
  final Uint8List? thumbnail;
  final String? pdfSource;
}
