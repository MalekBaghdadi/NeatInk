import '../ink/stroke.dart' show colorFromHex, colorToHex, enumByName;
import 'cover_design.dart';
import 'paper.dart';

enum NotebookKind { blank, pdf }

/// A4 portrait in points.
const double a4WidthPt = 595;
const double a4HeightPt = 842;

/// One page entry in `notebook.json`. The page's ink lives in
/// `pages/<id>.json`.
class PageMeta {
  const PageMeta({
    required this.id,
    this.width = a4WidthPt,
    this.height = a4HeightPt,
    this.paper = const Paper(),
    this.pdfPageIndex,
    this.marginLeft = 0,
    this.marginRight = 0,
  });

  factory PageMeta.fromJson(Map<String, dynamic> j) => PageMeta(
        id: j['id'] as String,
        width: (j['width'] as num?)?.toDouble() ?? a4WidthPt,
        height: (j['height'] as num?)?.toDouble() ?? a4HeightPt,
        paper: Paper.fromJson(j['paper'] as Map<String, dynamic>?),
        pdfPageIndex: (j['pdfPageIndex'] as num?)?.toInt(),
        marginLeft: _margin(j['marginLeft']),
        marginRight: _margin(j['marginRight']),
      );

  static double _margin(Object? v) => v is num && v.isFinite && v > 0 ? v.toDouble() : 0;

  final String id;

  /// Page size in points as displayed (for PDF pages: after applying the
  /// page's /Rotate and CropBox, plus the margins).
  final double width;
  final double height;
  final Paper paper;

  /// 0-based index into `source.pdf`, or null for a plain page.
  final int? pdfPageIndex;

  /// Writing space beside a PDF page, in points: the PDF page lies between
  /// them ([contentLeft] to [contentRight]) and the margins show [paper]
  /// (lined by default). 0 for plain pages and PDF pages without margins.
  final double marginLeft;
  final double marginRight;

  bool get isPdf => pdfPageIndex != null;

  /// Where the PDF page (or, for a plain page, the whole page) lies, in page
  /// points.
  double get contentLeft => marginLeft;
  double get contentRight => width - marginRight;
  double get contentWidth => width - marginLeft - marginRight;
  bool get hasMargins => marginLeft > 0 || marginRight > 0;

  PageMeta copyWith({
    String? id,
    double? width,
    double? height,
    Paper? paper,
    int? pdfPageIndex,
    bool clearPdfPage = false,
    double? marginLeft,
    double? marginRight,
  }) =>
      PageMeta(
        id: id ?? this.id,
        width: width ?? this.width,
        height: height ?? this.height,
        paper: paper ?? this.paper,
        pdfPageIndex: clearPdfPage ? null : (pdfPageIndex ?? this.pdfPageIndex),
        marginLeft: marginLeft ?? this.marginLeft,
        marginRight: marginRight ?? this.marginRight,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'width': width,
        'height': height,
        'paper': paper.toJson(),
        'pdfPageIndex': pdfPageIndex,
        if (marginLeft > 0) 'marginLeft': marginLeft,
        if (marginRight > 0) 'marginRight': marginRight,
      };
}

/// `notebook.json`: everything about a notebook except page contents.
class NotebookMeta {
  const NotebookMeta({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.kind = NotebookKind.blank,
    this.defaultPaper = const Paper(),
    this.pages = const [],
    this.folderId,
    this.tags = const [],
    this.favorite = false,
    this.coverColor = defaultCoverColor,
    this.cover = const CoverDesign.preview(),
    this.lastPageIndex = 0,
  });

  factory NotebookMeta.fromJson(Map<String, dynamic> json) {
    final j = migrateNotebookJson(json);
    return NotebookMeta(
      id: j['id'] as String,
      title: j['title'] as String? ?? 'Untitled',
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt: DateTime.parse(j['updatedAt'] as String),
      kind: enumByName(NotebookKind.values, j['kind'], NotebookKind.blank),
      defaultPaper: Paper.fromJson(j['defaultPaper'] as Map<String, dynamic>?),
      pages: [
        for (final p in (j['pages'] as List<dynamic>? ?? const []))
          PageMeta.fromJson(p as Map<String, dynamic>),
      ],
      folderId: j['folderId'] as String?,
      tags: [for (final t in (j['tags'] as List<dynamic>? ?? const [])) '$t'],
      favorite: j['favorite'] as bool? ?? false,
      coverColor: j['coverColor'] == null
          ? defaultCoverColor
          : colorFromHex(j['coverColor'] as String),
      cover: CoverDesign.fromJson(j['cover']),
      lastPageIndex: (j['lastPageIndex'] as num?)?.toInt() ?? 0,
    );
  }

  static const int currentVersion = 1;
  static const int defaultCoverColor = 0xFF3F51B5;

  /// Cover colours offered in the UI.
  static const List<int> coverColors = [
    0xFF3F51B5, 0xFF1E88E5, 0xFF00897B, 0xFF43A047, 0xFFF9A825,
    0xFFEF6C00, 0xFFE53935, 0xFFD81B60, 0xFF8E24AA, 0xFF6D4C41,
    0xFF546E7A, 0xFF263238, 0xFF1A237E, 0xFF880E4F, 0xFF00695C,
    0xFF5E35B1,
  ];

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final NotebookKind kind;

  /// Paper used for new pages added to this notebook.
  final Paper defaultPaper;
  final List<PageMeta> pages;

  /// Containing folder, or null for the library root.
  final String? folderId;
  final List<String> tags;
  final bool favorite;
  final int coverColor;

  /// What the cover shows (see [CoverDesign]); [coverColor] is its colour.
  final CoverDesign cover;

  /// Page the editor reopens at.
  final int lastPageIndex;

  bool get isPdf => kind == NotebookKind.pdf;

  int indexOfPage(String pageId) => pages.indexWhere((p) => p.id == pageId);

  NotebookMeta copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    NotebookKind? kind,
    Paper? defaultPaper,
    List<PageMeta>? pages,
    String? folderId,
    bool clearFolder = false,
    List<String>? tags,
    bool? favorite,
    int? coverColor,
    CoverDesign? cover,
    int? lastPageIndex,
  }) =>
      NotebookMeta(
        id: id ?? this.id,
        title: title ?? this.title,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        kind: kind ?? this.kind,
        defaultPaper: defaultPaper ?? this.defaultPaper,
        pages: pages ?? this.pages,
        folderId: clearFolder ? null : (folderId ?? this.folderId),
        tags: tags ?? this.tags,
        favorite: favorite ?? this.favorite,
        coverColor: coverColor ?? this.coverColor,
        cover: cover ?? this.cover,
        lastPageIndex: lastPageIndex ?? this.lastPageIndex,
      );

  Map<String, dynamic> toJson() => {
        'version': currentVersion,
        'id': id,
        'title': title,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'kind': kind.name,
        'defaultPaper': defaultPaper.toJson(),
        'pages': [for (final p in pages) p.toJson()],
        'folderId': folderId,
        'tags': tags,
        'favorite': favorite,
        'coverColor': colorToHex(coverColor),
        if (cover.kind != CoverKind.preview) 'cover': cover.toJson(),
        'lastPageIndex': lastPageIndex,
      };
}

/// Upgrades a `notebook.json` map to [NotebookMeta.currentVersion].
/// Version 1 is the first format; add a `case` per future bump.
Map<String, dynamic> migrateNotebookJson(Map<String, dynamic> j) {
  final version = (j['version'] as num?)?.toInt() ?? 1;
  if (version > NotebookMeta.currentVersion) {
    throw FormatException(
        'Notebook version $version is newer than this app supports');
  }
  return j;
}

/// A library folder. Folders can nest through [parentId].
class Folder {
  const Folder({
    required this.id,
    required this.name,
    this.parentId,
    this.color = 0xFF90A4AE,
    required this.createdAt,
  });

  factory Folder.fromJson(Map<String, dynamic> j) => Folder(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Folder',
        parentId: j['parentId'] as String?,
        color: j['color'] == null
            ? 0xFF90A4AE
            : colorFromHex(j['color'] as String),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  final String id;
  final String name;

  /// Parent folder, or null when the folder sits at the library root.
  final String? parentId;
  final int color;
  final DateTime createdAt;

  Folder copyWith({
    String? name,
    String? parentId,
    bool clearParent = false,
    int? color,
  }) =>
      Folder(
        id: id,
        name: name ?? this.name,
        parentId: clearParent ? null : (parentId ?? this.parentId),
        color: color ?? this.color,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'parentId': parentId,
        'color': colorToHex(color),
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}

/// `library.json`: folder tree (notebooks point at folders by id).
class LibraryIndex {
  const LibraryIndex({this.folders = const []});

  factory LibraryIndex.fromJson(Map<String, dynamic> j) => LibraryIndex(
        folders: [
          for (final f in (j['folders'] as List<dynamic>? ?? const []))
            Folder.fromJson(f as Map<String, dynamic>),
        ],
      );

  static const int currentVersion = 1;

  final List<Folder> folders;

  Folder? folderById(String? id) {
    if (id == null) return null;
    for (final f in folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  List<Folder> childrenOf(String? parentId) =>
      [for (final f in folders) if (f.parentId == parentId) f];

  LibraryIndex copyWith({List<Folder>? folders}) =>
      LibraryIndex(folders: folders ?? this.folders);

  Map<String, dynamic> toJson() => {
        'version': currentVersion,
        'folders': [for (final f in folders) f.toJson()],
      };
}
