import 'dart:typed_data';

import '../document/notebook_meta.dart';
import '../document/page_content.dart';
import '../document/paper.dart';

/// Size of one PDF page as displayed (after /Rotate and CropBox), in points.
class PdfPageSize {
  const PdfPageSize(this.width, this.height);
  final double width;
  final double height;
}

/// What a search result matched.
enum SearchMatchKind { title, tag, folder, text, handwriting, pdf }

class SearchHit {
  const SearchHit({
    required this.notebookId,
    required this.notebookTitle,
    required this.kind,
    this.pageId,
    this.pageIndex,
    this.snippet = '',
  });

  final String notebookId;
  final String notebookTitle;
  final SearchMatchKind kind;

  /// Set for text / pdf matches.
  final String? pageId;
  final int? pageIndex;

  /// A short excerpt around the match (empty for title matches).
  final String snippet;
}

/// Local, file-based storage for notebooks. Layout:
///
/// ```
/// <root>/library.json                       folder tree
/// <root>/notebooks/<id>/notebook.json       NotebookMeta
/// <root>/notebooks/<id>/source.pdf          PDF-backed notebooks only
/// <root>/notebooks/<id>/pages/<pageId>.json PageContent
/// <root>/notebooks/<id>/assets/<file>       images placed on pages
/// <root>/notebooks/<id>/thumb.png           cover thumbnail
/// <root>/notebooks/<id>/search.json         extracted text for search
/// <root>/trash/<id>/...                      a deleted notebook (same
///                                            files) + trashed.json
/// ```
///
/// Every write is atomic (temp file + rename). Nothing ever leaves the
/// device.
/// A notebook in the Trash.
class TrashedNotebook {
  const TrashedNotebook({required this.meta, required this.deletedAt, this.thumbnailPath});

  final NotebookMeta meta;
  final DateTime deletedAt;

  /// Its cover thumbnail, when it has one.
  final String? thumbnailPath;
}

abstract class NotebookRepository {
  /// All notebooks, unsorted. Corrupt notebooks are skipped (and logged),
  /// never deleted.
  Future<List<NotebookMeta>> listNotebooks();

  Future<NotebookMeta?> loadMeta(String notebookId);

  /// Creates a blank notebook with [pageCount] pages of [paper].
  Future<NotebookMeta> createNotebook({
    required String title,
    required Paper paper,
    int pageCount = 1,
    String? folderId,
    int? coverColor,
  });

  /// Creates a PDF-backed notebook: copies [sourcePdfPath] to `source.pdf`
  /// and makes one page per entry in [pageSizes] (with `pdfPageIndex` set).
  Future<NotebookMeta> createPdfNotebook({
    required String title,
    required String sourcePdfPath,
    required List<PdfPageSize> pageSizes,
    String? folderId,
  });

  /// Writes `notebook.json` (atomically). Also deletes page files whose ids
  /// are no longer in [meta]'s page list.
  Future<void> saveMeta(NotebookMeta meta);

  /// Loads a page. A missing file yields an empty page.
  Future<PageContent> loadPage(String notebookId, String pageId);

  /// Writes a page (atomically) and refreshes the notebook's search text for
  /// that page from its text boxes.
  Future<void> savePage(String notebookId, String pageId, PageContent content);

  Future<void> renameNotebook(String notebookId, String title);

  /// Deletes a notebook for good (not through the Trash).
  Future<void> deleteNotebook(String notebookId);

  /// Moves a notebook to the Trash (v1.8.0): it leaves the library and
  /// search with all its files, until [restoreFromTrash] brings it back or
  /// [deleteFromTrash] / [emptyTrash] delete it.
  Future<void> trashNotebook(String notebookId);

  /// The notebooks in the Trash, most recently deleted first.
  Future<List<TrashedNotebook>> listTrash();

  /// Puts a notebook from the Trash back in the library and returns it (with
  /// a new id when a notebook with its id came back meanwhile, at the top of
  /// the library when its folder is gone).
  Future<NotebookMeta> restoreFromTrash(String notebookId);

  /// Deletes a notebook in the Trash for good.
  Future<void> deleteFromTrash(String notebookId);

  /// Deletes the notebooks that went to the Trash before [before] (all of
  /// them when null) for good; returns how many.
  Future<int> emptyTrash({DateTime? before});

  /// Deep copy with new notebook/page ids and the title "<title> (copy)".
  Future<NotebookMeta> duplicateNotebook(String notebookId);

  /// Absolute path of the notebook's `source.pdf` (may not exist).
  String sourcePdfPath(String notebookId);

  /// Absolute path of the notebook's `audio/` folder (lecture recordings,
  /// v1.12.0; may not exist). It moves with the notebook (Trash, backups).
  String recordingsFolder(String notebookId);

  /// Copies an image file into the notebook's `assets/` folder and returns
  /// the new asset file name.
  Future<String> addAsset(String notebookId, String sourceFilePath);

  /// Same as [addAsset] for in-memory bytes (e.g. a pasted image).
  Future<String> addAssetBytes(
      String notebookId, Uint8List bytes, String extension);

  /// Absolute path of an asset file.
  String assetPath(String notebookId, String asset);

  /// The bytes of an asset file (copying a picture to another notebook).
  /// Throws when it can't be read.
  Future<Uint8List> readAsset(String notebookId, String asset);

  Future<void> saveThumbnail(String notebookId, Uint8List png);

  /// Absolute path of `thumb.png` (may not exist yet).
  String thumbnailPath(String notebookId);

  Future<LibraryIndex> loadLibrary();
  Future<void> saveLibrary(LibraryIndex library);

  /// Stores text extracted from the notebook's PDF (page id → text).
  Future<void> savePdfText(String notebookId, Map<String, String> textByPage);

  /// Stores what the handwriting reader read on a page, with the [key] of
  /// the strokes it read (see `HandwritingIndexer`).
  Future<void> saveHandwritingText(String notebookId, String pageId, {required String text, required String key});

  /// The handwriting keys stored so far, page id → key.
  Future<Map<String, String>> handwritingKeys(String notebookId);

  /// Case-insensitive search over titles, tags, folder names, text boxes,
  /// handwriting and PDF text. Results are grouped by notebook in a stable
  /// order.
  Future<List<SearchHit>> search(String query);
}
