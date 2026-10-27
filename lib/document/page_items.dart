import '../ink/ink_rect.dart';
import '../ink/stroke.dart' show colorFromHex, colorToHex, enumByName;
import 'font_kind.dart';

// The font registry: `FontKind` (bundled families, `FontKind.sans`,
// `.values`, `.byName`), `FontCategory`, `FontFile`.
export 'font_kind.dart';

enum TextAlignKind { left, center, right }

/// A typed text box placed on a page. Position and size are in page points.
class TextItem {
  const TextItem({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.text = '',
    this.fontSize = 14,
    this.color = 0xFF1E1E1E,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.align = TextAlignKind.left,
    this.font = FontKind.sans,
    this.background = 0x00000000,
  });

  factory TextItem.fromJson(Map<String, dynamic> j) => TextItem(
        id: j['id'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        width: (j['width'] as num).toDouble(),
        height: (j['height'] as num?)?.toDouble() ?? 20,
        text: j['text'] as String? ?? '',
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 14,
        color: colorFromHex(j['color'] as String? ?? '#FF1E1E1E'),
        bold: j['bold'] as bool? ?? false,
        italic: j['italic'] as bool? ?? false,
        underline: j['underline'] as bool? ?? false,
        align: enumByName(TextAlignKind.values, j['align'], TextAlignKind.left),
        font: FontKind.byName(j['font'] is String ? j['font'] as String : null),
        background: colorFromHex(j['background'] as String? ?? '#00000000'),
      );

  final String id;
  final double x;
  final double y;

  /// Box width; text wraps inside it.
  final double width;

  /// Laid-out height of the text (kept up to date by the editor so hit
  /// testing, selection and export don't need a text layout engine).
  final double height;
  final String text;

  /// Font size in points.
  final double fontSize;
  final int color;
  final bool bold;
  final bool italic;
  final bool underline;
  final TextAlignKind align;
  final FontKind font;

  /// Fill behind the text (ARGB). Fully transparent means none.
  final int background;

  InkRect get frame => InkRect.fromLTWH(x, y, width, height);

  TextItem copyWith({
    String? id,
    double? x,
    double? y,
    double? width,
    double? height,
    String? text,
    double? fontSize,
    int? color,
    bool? bold,
    bool? italic,
    bool? underline,
    TextAlignKind? align,
    FontKind? font,
    int? background,
  }) =>
      TextItem(
        id: id ?? this.id,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        text: text ?? this.text,
        fontSize: fontSize ?? this.fontSize,
        color: color ?? this.color,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        align: align ?? this.align,
        font: font ?? this.font,
        background: background ?? this.background,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'text': text,
        'fontSize': fontSize,
        'color': colorToHex(color),
        'bold': bold,
        'italic': italic,
        'underline': underline,
        'align': align.name,
        'font': font.name,
        'background': colorToHex(background),
      };
}

/// A picture placed on a page. The image file lives in the notebook's
/// `assets/` folder; [asset] is its file name there.
class ImageItem {
  const ImageItem({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.asset,
    this.pixelWidth = 0,
    this.pixelHeight = 0,
  });

  factory ImageItem.fromJson(Map<String, dynamic> j) => ImageItem(
        id: j['id'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        width: (j['width'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
        asset: j['asset'] as String,
        pixelWidth: (j['pixelWidth'] as num?)?.toInt() ?? 0,
        pixelHeight: (j['pixelHeight'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final double x;
  final double y;
  final double width;
  final double height;

  /// File name inside `<notebook>/assets/`.
  final String asset;

  /// Intrinsic size of the image file (0 if unknown).
  final int pixelWidth;
  final int pixelHeight;

  InkRect get frame => InkRect.fromLTWH(x, y, width, height);

  ImageItem copyWith({
    String? id,
    double? x,
    double? y,
    double? width,
    double? height,
    String? asset,
    int? pixelWidth,
    int? pixelHeight,
  }) =>
      ImageItem(
        id: id ?? this.id,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        asset: asset ?? this.asset,
        pixelWidth: pixelWidth ?? this.pixelWidth,
        pixelHeight: pixelHeight ?? this.pixelHeight,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'asset': asset,
        'pixelWidth': pixelWidth,
        'pixelHeight': pixelHeight,
      };
}
