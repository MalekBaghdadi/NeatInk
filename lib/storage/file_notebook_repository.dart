import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../document/notebook_meta.dart';
import '../document/page_content.dart';
import '../document/paper.dart';
import 'atomic_file.dart';
import 'json_document_store.dart';
import 'keyed_mutex.dart';
import 'library_json.dart';
import 'notebook_repository.dart';
import 'page_codec.dart';
import 'search_data.dart';
import 'search_engine.dart';
import 'storage_errors.dart';
import 'storage_ids.dart';

/// [NotebookRepository] backed by JSON files under [root], in the layout
/// documented on [NotebookRepository].
///
/// Guarantees:
/// * every write is atomic, and JSON documents keep their previous good
///   version as `<name>.bak`, which reads fall back to;
/// * unreadable files are never deleted or overwritten in place (a save
///   keeps them as `<name>.corrupt`), and corrupt notebooks are skipped by
///   [listNotebooks], not removed;
/// * ids are validated before they become paths ([isValidStorageId]);
/// * writes to one notebook are serialized, so concurrent saves cannot
///   interleave their read-modify-write steps;
/// * big pages are encoded and decoded in a background isolate.
///
/// Errors: invalid ids throw [ArgumentError]; writes to a notebook that
/// does not exist throw [NotebookNotFoundException]; a page or notebook
/// file that cannot be parsed (nor its backup) throws
/// [CorruptFileException].
class FileNotebookRepository implements NotebookRepository {
  FileNotebookRepository(this.root, {Uuid? uuid, DateTime Function()? clock})
      : _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now,
        _store = JsonDocumentStore(
          backgroundThresholdBytes: PageCodec.backgroundByteThreshold,
          log: _log,
        );

  /// Folder that holds `library.json` and `notebooks/`.
  final Directory root;

  final Uuid _uuid;
  final DateTime Function() _clock;
  final JsonDocumentStore _store;
  final KeyedMutex _locks = KeyedMutex();

  static const String _metaFile = 'notebook.json';
  static const String _searchFile = 'search.json';
  static const String _sourcePdfFile = 'source.pdf';
  static const String _thumbFile = 'thumb.png';

  /// Prefix of a notebook folder that is being deleted. Not a valid id, so
  /// it is never listed; a leftover one (crash mid-delete) is removed by
  /// [listNotebooks].
  static const String _trashPrefix = '.deleted-';

  /// Lock key for `library.json` (not a valid notebook id, so no clash).
  static const String _libraryLock = ':library';

  // ---- In-memory caches (all writes go through this instance) ----------

  /// Last known metadata of every notebook, for search.
  final Map<String, NotebookMeta> _metas = {};

  /// Whether [_metas] holds every notebook (set by [listNotebooks]).
  bool _metasComplete = false;

  /// Bumped by every write that changes [_metas], so a listing that raced
  /// with a write does not overwrite newer cache entries.
  int _generation = 0;

  final Map<String, SearchData> _searchData = {};
  LibraryIndex? _library;

  /// Notebook id → page id → asset names referenced by that page, for
  /// pages read or written in this session.
  final Map<String, Map<String, Set<String>>> _assetRefs = {};

  /// Notebook id → assets added or seen referenced during this session.
  /// These are never cleaned up while the app runs: undo/redo history may
  /// still bring back an image that uses them.
  final Map<String, Set<String>> _sessionAssets = {};

  static void _log(String message) => debugPrint(message);

  // ---- Paths ------------------------------------------------------------

  String get _notebooksPath => p.join(root.path, 'notebooks');
  String get _libraryPath => p.join(root.path, 'library.json');

  String _dir(String notebookId) =>
      p.join(_notebooksPath, checkStorageId(notebookId, 'notebookId'));
  String _metaPath(String notebookId) => p.join(_dir(notebookId), _metaFile);
  String _pagesDir(String notebookId) => p.join(_dir(notebookId), 'pages');
  String _assetsDir(String notebookId) => p.join(_dir(notebookId), 'assets');
  String _searchPath(String notebookId) =>
      p.join(_dir(notebookId), _searchFile);
  String _pagePath(String notebookId, String pageId) => p.join(
      _pagesDir(notebookId), '${checkStorageId(pageId, 'pageId')}.json');

  @override
  String sourcePdfPath(String notebookId) =>
      p.join(_dir(notebookId), _sourcePdfFile);

  @override
  String thumbnailPath(String notebookId) =>
      p.join(_dir(notebookId), _thumbFile);

  @override
  String assetPath(String notebookId, String asset) =>
      p.join(_assetsDir(notebookId), checkAssetName(asset));

  // ---- Notebooks ----------------------------------------------------------

  @override
  Future<List<NotebookMeta>> listNotebooks() async {
    final generation = _generation;
    final ids = await _notebookFolderIds();
    final loaded = await Future.wait(ids.map(_tryReadMeta));
    final metas = loaded.nonNulls.toList();
    if (generation == _generation) {
      _metas
        ..clear()
        ..addEntries(metas.map((m) => MapEntry(m.id, m)));
      _metasComplete = true;
    } else {
      // A write happened meanwhile; its cache entry is newer than our read.
      // The cache may now be stale (e.g. a notebook deleted mid-listing), so
      // the next search lists again.
      for (final m in metas) {
        _metas.putIfAbsent(m.id, () => m);
      }
      _metasComplete = false;
    }
    _searchData.removeWhere((id, _) => !_metas.containsKey(id));
    return metas;
  }

  /// Ids of all notebook folders. Also finishes interrupted deletes.
  Future<List<String>> _notebookFolderIds() async {
    final dir = Directory(_notebooksPath);
    if (!await dir.exists()) return const [];
    final ids = <String>[];
    final trash = <Directory>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (name.startsWith(_trashPrefix)) {
        trash.add(entity);
      } else if (isValidStorageId(name)) {
        ids.add(name);
      }
    }
    for (final t in trash) {
      await _deleteFolderQuietly(t);
    }
    return ids;
  }

  Future<NotebookMeta?> _tryReadMeta(String notebookId) async {
    try {
      final meta = await _readMeta(notebookId);
      if (meta == null) {
        _log('NeatInk storage: skipping notebook $notebookId '
            '(no $_metaFile)');
      }
      return meta;
    } catch (e) {
      _log('NeatInk storage: skipping unreadable notebook $notebookId: $e');
      return null;
    }
  }

  /// Reads `notebook.json` (or its backup); null when there is none.
  Future<NotebookMeta?> _readMeta(String notebookId) async {
    final meta = await _store.read(_metaPath(notebookId), parseNotebookMeta);
    if (meta == null) return null;
    // The folder name is what every path uses, so it wins over the file.
    return meta.id == notebookId ? meta : meta.copyWith(id: notebookId);
  }

  @override
  Future<NotebookMeta?> loadMeta(String notebookId) => _readMeta(notebookId);

  @override
  Future<NotebookMeta> createNotebook({
    required String title,
    required Paper paper,
    int pageCount = 1,
    String? folderId,
    int? coverColor,
  }) async {
    final now = _clock();
    final id = _uuid.v4();
    final meta = NotebookMeta(
      id: id,
      title: title,
      createdAt: now,
      updatedAt: now,
      defaultPaper: paper,
      // A notebook always has at least one page.
      pages: [
        for (var i = 0; i < math.max(1, pageCount); i++)
          PageMeta(id: _uuid.v4(), paper: paper),
      ],
      folderId: folderId,
      coverColor: coverColor ?? NotebookMeta.defaultCoverColor,
    );
    return _locks.run(id, () async {
      await Directory(_pagesDir(id)).create(recursive: true);
      await _writeMeta(meta);
      return meta;
    });
  }

  @override
  Future<NotebookMeta> createPdfNotebook({
    required String title,
    required String sourcePdfPath,
    required List<PdfPageSize> pageSizes,
    String? folderId,
  }) async {
    if (pageSizes.isEmpty) {
      throw ArgumentError.value(
          pageSizes, 'pageSizes', 'A PDF notebook needs at least one page');
    }
    final now = _clock();
    final id = _uuid.v4();
    const paper = Paper(type: PaperType.blank);
    final meta = NotebookMeta(
      id: id,
      title: title,
      createdAt: now,
      updatedAt: now,
      kind: NotebookKind.pdf,
      defaultPaper: paper,
      pages: [
        for (var i = 0; i < pageSizes.length; i++)
          PageMeta(
            id: _uuid.v4(),
            width: _validSize(pageSizes[i].width) ? pageSizes[i].width : a4WidthPt,
            height:
                _validSize(pageSizes[i].height) ? pageSizes[i].height : a4HeightPt,
            paper: paper,
            pdfPageIndex: i,
          ),
      ],
      folderId: folderId,
    );
    return _locks.run(id, () async {
      try {
        await Directory(_pagesDir(id)).create(recursive: true);
        await AtomicFile.copy(sourcePdfPath, this.sourcePdfPath(id));
        await _writeMeta(meta);
      } catch (_) {
        // Only our own half-made copy is removed; the user's PDF is untouched.
        await _deleteFolderQuietly(Directory(_dir(id)));
        _forgetNotebook(id);
        rethrow;
      }
      return meta;
    });
  }

  static bool _validSize(double v) => v.isFinite && v > 0;

  @override
  Future<void> saveMeta(NotebookMeta meta) async {
    final id = checkStorageId(meta.id, 'meta.id');
    for (final page in meta.pages) {
      checkStorageId(page.id, 'page id');
    }
    return _locks.run(id, () async {
      await _requireNotebook(id);
      await _writeMeta(meta);
      final pageIds = {for (final page in meta.pages) page.id};
      // Cleanup is best effort: the metadata is already safely written.
      await _bestEffort(() => _removeOrphanPages(id, pageIds));
      await _bestEffort(() => _pruneSearchData(id, pageIds));
      await _bestEffort(
          () => _removeUnusedAssets(id, meta.pages, cover: meta.cover.photo));
      await _bestEffort(() => AtomicFile.removeStrayTemps(Directory(_dir(id))));
    });
  }

  Future<void> _writeMeta(NotebookMeta meta) async {
    await _store.write(
        _metaPath(meta.id), encodeJsonBytes(meta.toJson(), pretty: true));
    _metas[meta.id] = meta;
    _generation++;
  }

  @override
  Future<void> renameNotebook(String notebookId, String title) async {
    checkStorageId(notebookId, 'notebookId');
    return _locks.run(notebookId, () async {
      final meta = await _readMeta(notebookId);
      if (meta == null) throw NotebookNotFoundException(notebookId);
      await _writeMeta(meta.copyWith(title: title, updatedAt: _clock()));
    });
  }

  @override
  Future<void> deleteNotebook(String notebookId) async {
    checkStorageId(notebookId, 'notebookId');
    return _locks.run(notebookId, () async {
      final dir = Directory(_dir(notebookId));
      if (await dir.exists()) {
        // Rename first (atomic) so a crash mid-delete never leaves a
        // half-deleted notebook that still shows up in the library.
        final token = _uuid.v4().substring(0, 8);
        final trash = await dir.rename(
            p.join(_notebooksPath, '$_trashPrefix$notebookId-$token'));
        await _deleteFolderQuietly(trash);
      }
      _forgetNotebook(notebookId);
      _metas.remove(notebookId);
      _generation++;
    });
  }

  @override
  Future<NotebookMeta> duplicateNotebook(String notebookId) async {
    checkStorageId(notebookId, 'notebookId');
    return _locks.run(notebookId, () async {
      final source = await _readMeta(notebookId);
      if (source == null) throw NotebookNotFoundException(notebookId);
      final newId = _uuid.v4();
      final newPageIds = {
        for (final page in source.pages) page.id: _uuid.v4(),
      };
      try {
        await Directory(_pagesDir(newId)).create(recursive: true);
        for (final page in source.pages) {
          final content = await _store.read(
              _pagePath(notebookId, page.id), PageCodec.decode);
          // A page that was never written stays empty in the copy too.
          if (content == null) continue;
          await _writePage(newId, newPageIds[page.id]!, content);
        }
        await _copyAssets(notebookId, newId);
        await _copyIfExists(sourcePdfPath(notebookId), sourcePdfPath(newId));
        await _copyIfExists(thumbnailPath(notebookId), thumbnailPath(newId));
        final search = await _loadSearchData(notebookId);
        await _writeSearchData(newId, search.remapPages(newPageIds));

        final now = _clock();
        final copy = source.copyWith(
          id: newId,
          title: '${source.title} (copy)',
          createdAt: now,
          updatedAt: now,
          pages: [
            for (final page in source.pages)
              page.copyWith(id: newPageIds[page.id]),
          ],
        );
        // Written last: until it exists the copy is not a notebook.
        await _writeMeta(copy);
        return copy;
      } catch (_) {
        await _deleteFolderQuietly(Directory(_dir(newId)));
        _forgetNotebook(newId);
        rethrow;
      }
    });
  }

  Future<void> _copyAssets(String fromId, String toId) async {
    final dir = Directory(_assetsDir(fromId));
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is! File || !isValidAssetName(name)) continue;
      await AtomicFile.copy(entity.path, assetPath(toId, name));
      _sessionAssetsOf(toId).add(name);
    }
  }

  static Future<void> _copyIfExists(String from, String to) async {
    if (await File(from).exists()) await AtomicFile.copy(from, to);
  }

  // ---- Pages ------------------------------------------------------------

  @override
  Future<PageContent> loadPage(String notebookId, String pageId) async {
    final content = await _readPage(notebookId, pageId);
    _rememberAssets(notebookId, pageId, content);
    return content;
  }

  /// Reads a page (or its backup); an empty page when it was never saved.
  Future<PageContent> _readPage(String notebookId, String pageId) async =>
      await _store.read(_pagePath(notebookId, pageId), PageCodec.decode) ??
      PageContent();

  @override
  Future<void> savePage(
    String notebookId,
    String pageId,
    PageContent content,
  ) async {
    _pagePath(notebookId, pageId); // Validates both ids now.
    // Snapshot now: the editor keeps changing `content` while this save
    // waits for earlier writes to the same notebook.
    final snapshot = content.copy();
    final text = _searchTextOf(snapshot);
    return _locks.run(notebookId, () async {
      await _requireNotebook(notebookId);
      await _writePage(notebookId, pageId, snapshot);
      final data = await _loadSearchData(notebookId);
      if ((data.pages[pageId]?.text ?? '') != text) {
        await _writeSearchData(notebookId, data.withPageText(pageId, text));
      }
    });
  }

  Future<void> _writePage(
    String notebookId,
    String pageId,
    PageContent content,
  ) async {
    final bytes = await PageCodec.encode(content);
    await _store.write(_pagePath(notebookId, pageId), bytes);
    _rememberAssets(notebookId, pageId, content);
  }

  /// Search text of a page: its non-empty text boxes, one per line.
  static String _searchTextOf(PageContent content) => [
        for (final t in content.texts)
          if (t.text.trim().isNotEmpty) t.text.trim(),
      ].join('\n');

  Future<void> _removeOrphanPages(
    String notebookId,
    Set<String> pageIds,
  ) async {
    final dir = Directory(_pagesDir(notebookId));
    if (!await dir.exists()) return;
    final refs = _assetRefs[notebookId];
    final orphans = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (AtomicFile.isTempName(name)) continue; // Handled below.
      final pageId = _pageIdOfFileName(name);
      if (pageId == null || pageIds.contains(pageId)) continue;
      orphans.add(entity);
      refs?.remove(pageId);
    }
    for (final file in orphans) {
      _store.forget(file.path);
      await _deleteQuietly(file);
    }
    await AtomicFile.removeStrayTemps(dir);
  }

  /// `<id>.json`, `<id>.json.bak` or `<id>.json.corrupt` → `<id>`; null for
  /// files this repository did not create (left alone).
  static String? _pageIdOfFileName(String name) {
    final dot = name.indexOf('.');
    if (dot <= 0) return null;
    final rest = name.substring(dot);
    if (rest != '.json' && rest != '.json.bak' && rest != '.json.corrupt') {
      return null;
    }
    final id = name.substring(0, dot);
    return isValidStorageId(id) ? id : null;
  }

  // ---- Assets & thumbnails ------------------------------------------------

  @override
  Future<String> addAsset(String notebookId, String sourceFilePath) async {
    final name = _newAssetName(p.extension(sourceFilePath));
    final target = assetPath(notebookId, name);
    return _locks.run(notebookId, () async {
      await _requireNotebook(notebookId);
      _sessionAssetsOf(notebookId).add(name);
      await AtomicFile.copy(sourceFilePath, target);
      return name;
    });
  }

  @override
  Future<String> addAssetBytes(
    String notebookId,
    Uint8List bytes,
    String extension,
  ) async {
    final name = _newAssetName(extension);
    final target = assetPath(notebookId, name);
    return _locks.run(notebookId, () async {
      await _requireNotebook(notebookId);
      _sessionAssetsOf(notebookId).add(name);
      await AtomicFile.writeBytes(target, bytes);
      return name;
    });
  }

  String _newAssetName(String extension) =>
      '${_uuid.v4()}.${sanitizeExtension(extension)}';

  @override
  Future<void> saveThumbnail(String notebookId, Uint8List png) async {
    final path = thumbnailPath(notebookId);
    return _locks.run(notebookId, () async {
      await _requireNotebook(notebookId);
      await AtomicFile.writeBytes(path, png);
    });
  }

  Set<String> _rememberAssets(
    String notebookId,
    String pageId,
    PageContent content,
  ) {
    final assets = {for (final image in content.images) image.asset};
    _assetRefs.putIfAbsent(notebookId, () => {})[pageId] = assets;
    _sessionAssetsOf(notebookId).addAll(assets);
    return assets;
  }

  Set<String> _sessionAssetsOf(String notebookId) =>
      _sessionAssets.putIfAbsent(notebookId, () => {});

  /// Deletes asset files that no page references, when that is provably
  /// safe: every page in [pages] must parse (otherwise an unreadable page
  /// might still reference them), and assets used during this session are
  /// kept for undo/redo. The [cover] photo is in use too.
  Future<void> _removeUnusedAssets(
    String notebookId,
    List<PageMeta> pages, {
    String? cover,
  }) async {
    final dir = Directory(_assetsDir(notebookId));
    if (!await dir.exists()) return;
    await AtomicFile.removeStrayTemps(dir);
    final session = _sessionAssets[notebookId] ?? const <String>{};
    final candidates = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is File && isValidAssetName(name) && !session.contains(name)) {
        candidates.add(entity);
      }
    }
    if (candidates.isEmpty) return;

    final refsByPage = _assetRefs.putIfAbsent(notebookId, () => {});
    final referenced = <String>{?cover};
    for (final page in pages) {
      var refs = refsByPage[page.id];
      if (refs == null) {
        final PageContent content;
        try {
          content = await _readPage(notebookId, page.id);
        } catch (e) {
          _log('NeatInk storage: keeping all assets of $notebookId, '
              'page ${page.id} is unreadable: $e');
          return;
        }
        refs = _rememberAssets(notebookId, page.id, content);
      }
      referenced.addAll(refs);
    }
    for (final file in candidates) {
      if (!referenced.contains(p.basename(file.path))) {
        await _deleteQuietly(file);
      }
    }
  }

  // ---- Library ------------------------------------------------------------

  @override
  Future<LibraryIndex> loadLibrary() async {
    await AtomicFile.removeStrayTemps(root);
    final library = await _readLibrary();
    _library = library;
    return library;
  }

  Future<LibraryIndex> _readLibrary() async {
    try {
      return await _store.read(_libraryPath, libraryFromJson) ??
          const LibraryIndex();
    } on CorruptFileException catch (e) {
      // Folders are lost from view but not from disk: the next save keeps
      // the unreadable file as library.json.corrupt.
      _log('NeatInk storage: library.json unreadable, showing no folders: '
          '${e.cause}');
      return const LibraryIndex();
    }
  }

  @override
  Future<void> saveLibrary(LibraryIndex library) async =>
      _locks.run(_libraryLock, () async {
        await _store.write(
            _libraryPath, encodeJsonBytes(library.toJson(), pretty: true));
        _library = library;
      });

  // ---- Search -------------------------------------------------------------

  @override
  Future<void> savePdfText(
    String notebookId,
    Map<String, String> textByPage,
  ) async {
    checkStorageId(notebookId, 'notebookId');
    for (final pageId in textByPage.keys) {
      checkStorageId(pageId, 'pageId');
    }
    final snapshot = Map.of(textByPage);
    return _locks.run(notebookId, () async {
      await _requireNotebook(notebookId);
      final data = await _loadSearchData(notebookId);
      await _writeSearchData(notebookId, data.withPdfText(snapshot));
    });
  }

  @override
  Future<List<SearchHit>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    if (!_metasComplete) await listNotebooks();
    final library = _library ??= await _readLibrary();
    final metas = _metas.values.toList();
    final data = await Future.wait(metas.map((m) => _searchDataOrEmpty(m.id)));
    return searchNotebooks(query, [
      for (var i = 0; i < metas.length; i++) SearchableNotebook(metas[i], data[i]),
    ], library);
  }

  /// The notebook's search data from the cache or disk. An unreadable
  /// `search.json` is rebuilt from the text boxes of the pages (PDF text
  /// cannot be recovered here and is dropped from search).
  Future<SearchData> _loadSearchData(String notebookId) async {
    final cached = _searchData[notebookId];
    if (cached != null) return cached;
    SearchData data;
    try {
      data = await _store.read(_searchPath(notebookId), SearchData.fromJson) ??
          SearchData.empty;
    } on CorruptFileException catch (e) {
      _log('NeatInk storage: rebuilding search text of $notebookId: '
          '${e.cause}');
      data = await _rebuildSearchData(notebookId);
    }
    // A write may have filled the cache while we were reading; it wins.
    return _searchData[notebookId] ??= data;
  }

  Future<SearchData> _searchDataOrEmpty(String notebookId) async {
    try {
      return await _loadSearchData(notebookId);
    } catch (e) {
      _log('NeatInk storage: no search data for $notebookId: $e');
      return SearchData.empty;
    }
  }

  Future<SearchData> _rebuildSearchData(String notebookId) async {
    final meta = await _readMeta(notebookId);
    var data = SearchData.empty;
    for (final page in meta?.pages ?? const <PageMeta>[]) {
      try {
        final text = _searchTextOf(await _readPage(notebookId, page.id));
        if (text.isNotEmpty) data = data.withPageText(page.id, text);
      } catch (_) {
        // An unreadable page simply has no searchable text.
      }
    }
    return data;
  }

  Future<void> _writeSearchData(String notebookId, SearchData data) async {
    final path = _searchPath(notebookId);
    if (data.isEmpty && !await _store.exists(path)) {
      _searchData[notebookId] = data;
      return;
    }
    await _store.write(path, encodeJsonBytes(data.toJson()));
    _searchData[notebookId] = data;
  }

  Future<void> _pruneSearchData(String notebookId, Set<String> pageIds) async {
    final data = await _loadSearchData(notebookId);
    if (data.pages.keys.every(pageIds.contains)) return;
    await _writeSearchData(notebookId, data.retainPages(pageIds));
  }

  // ---- Helpers ----------------------------------------------------------

  Future<void> _requireNotebook(String notebookId) async {
    if (!await Directory(_dir(notebookId)).exists()) {
      throw NotebookNotFoundException(notebookId);
    }
  }

  /// Drops every cache entry of a notebook whose folder is gone.
  void _forgetNotebook(String notebookId) {
    _searchData.remove(notebookId);
    _assetRefs.remove(notebookId);
    _sessionAssets.remove(notebookId);
    _store.forgetUnder(_dir(notebookId));
  }

  static Future<void> _bestEffort(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _log('NeatInk storage: cleanup skipped: $e');
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException catch (e) {
      _log('NeatInk storage: could not delete ${file.path}: $e');
    }
  }

  static Future<void> _deleteFolderQuietly(Directory dir) async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (e) {
      _log('NeatInk storage: could not delete ${dir.path}: $e');
    }
  }
}

/// Parses `notebook.json` and rejects page ids that are unsafe as file
/// names. Top-level so it can be sent to a background isolate.
NotebookMeta parseNotebookMeta(Map<String, dynamic> json) {
  final meta = NotebookMeta.fromJson(json);
  for (final page in meta.pages) {
    if (!isValidStorageId(page.id)) {
      throw FormatException('Invalid page id "${page.id}"');
    }
  }
  return meta;
}
