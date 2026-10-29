import '../ink/ink_rect.dart';
import '../ink/stroke.dart' show colorFromHex, colorToHex, enumByName;
import 'font_kind.dart';

// The font registry: `FontKind` (bundled families, `FontKind.sans`,
// `.values`, `.byName`), `FontCategory`, `FontFile`.
export 'font_kind.dart';

enum TextAlignKind { left, center, right }

/// A word autocorrect changed in a text box: [replacement] is in the text
/// at [start] and was [original] (what was written). Shown underlined on
/// screen; tapping it can put [original] back.
class TextCorrection {
  const TextCorrection({required this.start, required this.original, required this.replacement});

  factory TextCorrection.fromJson(Map<String, dynamic> j) => TextCorrection(
        start: (j['at'] as num).toInt(),
        original: j['from'] as String,
        replacement: j['to'] as String,
      );

  final int start;
  final String original;
  final String replacement;

  int get end => start + replacement.length;

  TextCorrection shifted(int by) =>
      TextCorrection(start: start + by, original: original, replacement: replacement);

  /// Whether [text] still has [replacement] at [start] as a whole word.
  bool holdsIn(String text) =>
      start >= 0 &&
      end <= text.length &&
      text.startsWith(replacement, start) &&
      (start == 0 || !_isWordChar(text.codeUnitAt(start - 1))) &&
      (end == text.length || !_isWordChar(text.codeUnitAt(end)));

  static bool _isWordChar(int c) =>
      (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x27 || c == 0x2019;

  Map<String, dynamic> toJson() => {'at': start, 'from': original, 'to': replacement};

  @override
  bool operator ==(Object other) =>
      other is TextCorrection &&
      other.start == start &&
      other.original == original &&
      other.replacement == replacement;

  @override
  int get hashCode => Object.hash(start, original, replacement);

  @override
  String toString() => 'TextCorrection($original -> $replacement @$start)';
}

/// [corrections] of [before] carried over to [after] (the same text edited
/// in one place): corrections before the edit stay, those after it move
/// with the text, and those the edit touched are dropped.
List<TextCorrection> remapCorrections(String before, String after, List<TextCorrection> corrections) {
  if (corrections.isEmpty || before == after) return corrections;
  final common = before.length < after.length ? before.length : after.length;
  var prefix = 0;
  while (prefix < common && before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < common - prefix &&
      before.codeUnitAt(before.length - 1 - suffix) == after.codeUnitAt(after.length - 1 - suffix)) {
    suffix++;
  }
  final editEnd = before.length - suffix;
  final delta = after.length - before.length;
  return [
    for (final c in corrections)
      if (c.end <= prefix && c.holdsIn(after))
        c
      else if (c.start >= editEnd && c.shifted(delta).holdsIn(after))
        c.shifted(delta),
  ];
}

/// When part of a text box was written (v1.12.0): the text from [start] on
/// (up to the next [TextTime] of the box) was converted from handwriting the
/// pen began at [writtenAt] (milliseconds since the epoch). A lecture
/// recording plays typed notes back line by line with it.
class TextTime {
  const TextTime(this.start, this.writtenAt);

  final int start;
  final int writtenAt;

  TextTime shifted(int by) => TextTime(start + by, writtenAt);

  List<int> toJson() => [start, writtenAt];

  @override
  bool operator ==(Object other) => other is TextTime && other.start == start && other.writtenAt == writtenAt;

  @override
  int get hashCode => Object.hash(start, writtenAt);

  @override
  String toString() => 'TextTime($start @$writtenAt)';
}

/// [times] of [before] carried over to [after] (the same text edited in one
/// place), like [remapCorrections]: marks before the edit stay, those after
/// it move with the text, those inside it are dropped (the edited words then
/// count as written with the text before them).
List<TextTime> remapTimes(String before, String after, List<TextTime> times) {
  if (times.isEmpty || before == after) return times;
  final common = before.length < after.length ? before.length : after.length;
  var prefix = 0;
  while (prefix < common && before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < common - prefix &&
      before.codeUnitAt(before.length - 1 - suffix) == after.codeUnitAt(after.length - 1 - suffix)) {
    suffix++;
  }
  final editEnd = before.length - suffix;
  final delta = after.length - before.length;
  return [
    for (final t in times)
      if (t.start <= prefix)
        t
      else if (t.start >= editEnd)
        t.shifted(delta),
  ];
}

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
    this.corrections = const [],
    this.lineSpacing,
    this.times = const [],
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
        corrections: [
          for (final c in (j['corrections'] as List<dynamic>? ?? const []))
            if (c is Map<String, dynamic> && c['at'] is num && c['from'] is String && c['to'] is String)
              TextCorrection.fromJson(c),
        ],
        lineSpacing: switch (j['lineSpacing']) {
          final num v when v.isFinite && v > 0 => v.toDouble(),
          _ => null,
        },
        times: [
          for (final t in (j['times'] as List<dynamic>? ?? const []))
            if (t is List && t.length >= 2 && t[0] is num && t[1] is num) TextTime((t[0] as num).toInt(), (t[1] as num).toInt()),
        ],
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

  /// Words autocorrect changed (see [TextCorrection]); use
  /// [liveCorrections], which skips any the text no longer holds.
  final List<TextCorrection> corrections;

  /// Distance between the baselines of wrapped lines, in points, or null for
  /// the font's own line height (v1.6.0). Handwriting converted on ruled
  /// paper uses the ruling, so every wrapped line sits on a ruled line.
  final double? lineSpacing;

  /// When its lines were written, for boxes converted from handwriting
  /// (see [TextTime]; empty for typed boxes and older ones), by `start`.
  final List<TextTime> times;

  /// The [corrections] still in [text].
  List<TextCorrection> get liveCorrections => [
        for (final c in corrections)
          if (c.holdsIn(text)) c,
      ];

  /// The box with [c]'s word put back as it was written.
  TextItem withOriginal(TextCorrection c) {
    if (!c.holdsIn(text)) return this;
    final delta = c.original.length - c.replacement.length;
    return copyWith(
      text: text.replaceRange(c.start, c.end, c.original),
      corrections: [
        for (final o in liveCorrections)
          if (o != c) o.start > c.start ? o.shifted(delta) : o,
      ],
    );
  }

  /// The box with [c] kept as corrected (no longer marked).
  TextItem withoutCorrection(TextCorrection c) =>
      copyWith(corrections: [for (final o in corrections) if (o != c) o]);

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
    List<TextCorrection>? corrections,
    double? lineSpacing,
    List<TextTime>? times,
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
        // A text change moves the marks with the words (or drops them).
        corrections: corrections ??
            (text == null || text == this.text
                ? this.corrections
                : remapCorrections(this.text, text, this.corrections)),
        lineSpacing: lineSpacing ?? this.lineSpacing,
        times: times ??
            (text == null || text == this.text ? this.times : remapTimes(this.text, text, this.times)),
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
        if (liveCorrections.isNotEmpty)
          'corrections': [for (final c in liveCorrections) c.toJson()],
        if (lineSpacing != null) 'lineSpacing': lineSpacing,
        if (times.isNotEmpty) 'times': [for (final t in times) t.toJson()],
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
