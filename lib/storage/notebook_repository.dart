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
enum SearchMatchKind { title, tag, folder, text, pdf }

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
/// ```
///
/// Every write is atomic (temp file + rename). Nothing ever leaves the
/// device.
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
  Future<void> deleteNotebook(String notebookId);

  /// Deep copy with new notebook/page ids and the title "<title> (copy)".
  Future<NotebookMeta> duplicateNotebook(String notebookId);

  /// Absolute path of the notebook's `source.pdf` (may not exist).
  String sourcePdfPath(String notebookId);

  /// Copies an image file into the notebook's `assets/` folder and returns
  /// the new asset file name.
  Future<String> addAsset(String notebookId, String sourceFilePath);

  /// Same as [addAsset] for in-memory bytes (e.g. a pasted image).
  Future<String> addAssetBytes(
      String notebookId, Uint8List bytes, String extension);

  /// Absolute path of an asset file.
  String assetPath(String notebookId, String asset);

  Future<void> saveThumbnail(String notebookId, Uint8List png);

  /// Absolute path of `thumb.png` (may not exist yet).
  String thumbnailPath(String notebookId);

  Future<LibraryIndex> loadLibrary();
  Future<void> saveLibrary(LibraryIndex library);

  /// Stores text extracted from the notebook's PDF (page id → text).
  Future<void> savePdfText(String notebookId, Map<String, String> textByPage);

  /// Case-insensitive search over titles, tags, folder names, text boxes and
  /// PDF text. Results are grouped by notebook in a stable order.
  Future<List<SearchHit>> search(String query);
}
