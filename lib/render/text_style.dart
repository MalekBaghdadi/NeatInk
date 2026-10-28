import 'package:flutter/painting.dart';

import '../document/page_items.dart';

/// The single mapping from a [TextItem] to Flutter text styling. The editor
/// renders text boxes with it and the PDF exporter lays text out with it, so
/// a box wraps into exactly the same lines on screen and in the PDF.
///
/// Layout rules shared by both (use [layoutTextItem] to get them for free):
/// * the text starts at the box's top-left corner (`item.x`, `item.y`) with
///   no padding, and wraps at `item.width`;
/// * sizes are page points (the canvas is already in page coordinates), and
///   the system text scale factor is ignored ([TextScaler.noScaling]);
/// * left-to-right paragraphs.

/// Font family for [font]: the family name the bundled font files are
/// declared under in `pubspec.yaml`. Bold and italic pick the matching file
/// (Regular / Bold / Italic / Bold Italic) of that family; only if the family
/// lacks a file for the requested style does the engine fake it.
String fontFamilyFor(FontKind font) => font.family;

/// The text style of [item]: font size in points, colour, bold, italic and
/// underline.
///
/// [TextStyle.inherit] is false on purpose: the box must not pick up the
/// ambient `DefaultTextStyle` (Material's body style adds letter spacing and
/// line height), or the screen would wrap differently from the PDF.
TextStyle textStyleFor(TextItem item) {
  final color = Color(item.color);
  return TextStyle(
    inherit: false,
    color: color,
    fontFamily: fontFamilyFor(item.font),
    fontSize: item.fontSize,
    fontWeight: item.bold ? FontWeight.w700 : FontWeight.w400,
    fontStyle: item.italic ? FontStyle.italic : FontStyle.normal,
    letterSpacing: 0,
    wordSpacing: 0,
    textBaseline: TextBaseline.alphabetic,
    decoration:
        item.underline ? TextDecoration.underline : TextDecoration.none,
    decorationColor: color,
    decorationStyle: TextDecorationStyle.solid,
  );
}

/// The paragraph alignment for [align].
TextAlign textAlignFor(TextAlignKind align) => switch (align) {
      TextAlignKind.left => TextAlign.left,
      TextAlignKind.center => TextAlign.center,
      TextAlignKind.right => TextAlign.right,
    };

/// Text scaling used for text boxes: none, so the page looks the same on
/// every device and in the PDF regardless of the system font size setting.
const TextScaler textItemScaler = TextScaler.noScaling;

/// Lays out [item] exactly as the editor paints it: [textStyleFor],
/// [textAlignFor], wrapped (and aligned) within `item.width`.
///
/// Paint the result at `Offset(item.x, item.y)`. The caller owns the painter
/// and should [TextPainter.dispose] it when done.
TextPainter layoutTextItem(TextItem item) {
  final width = item.width.isFinite && item.width > 0 ? item.width : 1.0;
  return TextPainter(
    text: TextSpan(text: item.text, style: textStyleFor(item)),
    textAlign: textAlignFor(item.align),
    textDirection: TextDirection.ltr,
    textScaler: textItemScaler,
  )..layout(minWidth: width, maxWidth: width);
}

/// Where [item]'s autocorrected words ([TextItem.liveCorrections]) are on the
/// page: one or more rectangles per word (page points; a word broken over two
/// lines has two). [laidOut] is [item] laid out by [layoutTextItem], if the
/// caller has it already.
List<(TextCorrection, List<Rect>)> correctionBoxes(TextItem item,
    [TextPainter? laidOut]) {
  final corrections = item.liveCorrections;
  if (corrections.isEmpty) return const [];
  final painter = laidOut ?? layoutTextItem(item);
  try {
    return [
      for (final c in corrections)
        (
          c,
          [
            for (final b in painter.getBoxesForSelection(
                TextSelection(baseOffset: c.start, extentOffset: c.end)))
              b.toRect().shift(Offset(item.x, item.y)),
          ],
        ),
    ];
  } finally {
    if (laidOut == null) painter.dispose();
  }
}
