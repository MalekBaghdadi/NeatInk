import '../document/page_items.dart' show FontFile, FontKind;

/// Data sent from Dart to the Kotlin PdfBox exporter over the
/// `neatink/pdf_export` MethodChannel. All coordinates are page points with
/// the origin at the top-left and y pointing down (the app's coordinate
/// system); the Kotlin side flips y and handles /Rotate and the CropBox.
///
/// Everything is plain lists/maps/numbers so it encodes with the standard
/// message codec. Polygons are flat `[x0, y0, x1, y1, ...]` lists.

/// A filled polygon: one stroke outline as displayed on screen.
class ExportPolygon {
  const ExportPolygon(this.xy, this.color);

  /// Flat list of outline vertices.
  final List<double> xy;

  /// ARGB. The alpha channel becomes the fill alpha (highlighter ≈ 0.35,
  /// pencil ≈ 0.85, everything else opaque).
  final int color;

  Map<String, Object> toMap() => {'xy': xy, 'color': color};
}

/// A line segment of the paper pattern (ruled lines, grid, staff lines).
class ExportLine {
  const ExportLine(this.x1, this.y1, this.x2, this.y2, this.width, this.color);
  final double x1, y1, x2, y2;
  final double width;
  final int color;

  Map<String, Object> toMap() =>
      {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2, 'width': width, 'color': color};
}

/// One laid-out line of a text box, positioned by the Dart text layout so
/// the PDF wraps exactly like the screen.
class ExportTextLine {
  const ExportTextLine({
    required this.text,
    required this.x,
    required this.baselineY,
    required this.fontSize,
    required this.color,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.font = FontKind.sans,
    this.width = 0,
  });

  final String text;

  /// Left edge of the line's first glyph.
  final double x;
  final double baselineY;
  final double fontSize;
  final int color;
  final bool bold;
  final bool italic;
  final bool underline;
  final FontKind font;

  /// Measured line width (used for underline and alignment checks).
  final double width;

  /// The registry file the exporter should embed for this line's weight and
  /// slant (the closest the family has; see [FontKind.resolveFile]).
  FontFile get fontFile => font.resolveFile(bold: bold, italic: italic);

  Map<String, Object> toMap() => {
        'text': text,
        'x': x,
        'baselineY': baselineY,
        'fontSize': fontSize,
        'color': color,
        'bold': bold,
        'italic': italic,
        'underline': underline,
        'font': font.name,
        // Additive font info for the exporter: the Flutter asset path of the
        // resolved TTF and which styles that file really has, so the
        // exporter can fake only what is missing (e.g. bold for a family
        // without a Bold file).
        'fontAsset': fontFile.asset,
        'fontAssetBold': fontFile.bold,
        'fontAssetItalic': fontFile.italic,
        'width': width,
      };
}

/// A filled rectangle (text box background).
class ExportRect {
  const ExportRect(this.x, this.y, this.width, this.height, this.color);
  final double x, y, width, height;
  final int color;

  Map<String, Object> toMap() =>
      {'x': x, 'y': y, 'width': width, 'height': height, 'color': color};
}

/// An image file drawn into a rectangle.
class ExportImage {
  const ExportImage(this.path, this.x, this.y, this.width, this.height);

  /// Absolute path of a PNG/JPEG/WebP file on the device.
  final String path;
  final double x, y, width, height;

  Map<String, Object> toMap() =>
      {'path': path, 'x': x, 'y': y, 'width': width, 'height': height};
}

/// One output page. Layers are painted in this order (matching the screen):
/// background → paper lines/dots → images → highlighter → text → ink.
class ExportPage {
  const ExportPage({
    required this.width,
    required this.height,
    this.pdfPageIndex,
    this.marginLeft = 0,
    this.marginRight = 0,
    this.background,
    this.lines = const [],
    this.dots = const [],
    this.dotRadius = 0.9,
    this.dotColor = 0,
    this.images = const [],
    this.highlighter = const [],
    this.textRects = const [],
    this.textLines = const [],
    this.ink = const [],
  });

  /// Page size in points as displayed in the app.
  final double width;
  final double height;

  /// When set, this page is a copy of `sourcePdfPath`'s page at this index
  /// and the ink is appended on top of the original content (which stays
  /// selectable). When null, a new blank page is created.
  final int? pdfPageIndex;

  /// Writing space beside a PDF page, in points: the output page is
  /// [width] wide with the PDF page between the margins (its content
  /// unchanged and still selectable). Zero for plain pages.
  final double marginLeft;
  final double marginRight;

  /// Fill colour (ARGB) for blank pages, or for the margins of a PDF page;
  /// null leaves the page unfilled.
  final int? background;
  final List<ExportLine> lines;

  /// Flat `[x0, y0, x1, y1, ...]` dot centres for dotted paper.
  final List<double> dots;
  final double dotRadius;
  final int dotColor;
  final List<ExportImage> images;
  final List<ExportPolygon> highlighter;
  final List<ExportRect> textRects;
  final List<ExportTextLine> textLines;
  final List<ExportPolygon> ink;

  Map<String, Object?> toMap() => {
        'width': width,
        'height': height,
        'pdfPageIndex': pdfPageIndex,
        'marginLeft': marginLeft,
        'marginRight': marginRight,
        'background': background,
        'lines': [for (final l in lines) l.toMap()],
        'dots': dots,
        'dotRadius': dotRadius,
        'dotColor': dotColor,
        'images': [for (final i in images) i.toMap()],
        'highlighter': [for (final p in highlighter) p.toMap()],
        'textRects': [for (final r in textRects) r.toMap()],
        'textLines': [for (final t in textLines) t.toMap()],
        'ink': [for (final p in ink) p.toMap()],
      };
}

/// A whole export job. Pages appear in the output in list order; PDF pages
/// may be reordered, repeated or interleaved with blank pages.
class ExportRequest {
  const ExportRequest({
    required this.outputPath,
    required this.pages,
    this.sourcePdfPath,
    this.title,
  });

  /// Where the Kotlin side writes the finished PDF (a temp file the Dart
  /// side then hands to the save/share dialog).
  final String outputPath;
  final String? sourcePdfPath;
  final String? title;
  final List<ExportPage> pages;

  Map<String, Object?> toMap() => {
        'outputPath': outputPath,
        'sourcePdfPath': sourcePdfPath,
        'title': title,
        'pages': [for (final p in pages) p.toMap()],
      };
}
