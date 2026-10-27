import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:uuid/uuid.dart';

import '../../../../document/page_items.dart';
import '../../../../document/paper.dart';
import '../../../../recognition/stroke_grouping.dart';
import '../../../../render/text_style.dart';
import '../text_images/text_editor.dart';
import 'convert_config.dart';

// Layout of converted handwriting: where each typed line goes and how big it
// is. Nothing here touches the document; the result is a list of text boxes.

/// The three measurements the layout needs from a text engine. The real one
/// ([FlutterTextMetrics]) uses the same layout code as the page painter and
/// the PDF exporter, so what is measured here is what is shown and exported;
/// unit tests can plug in a simple deterministic one.
abstract class ConvertTextMetrics {
  const ConvertTextMetrics();

  /// Distance from the top of the box to the baseline of its first line.
  double firstBaseline(TextItem item);

  /// Width of `item.text` laid out on one line, without wrapping.
  double naturalWidth(TextItem item);

  /// Height of the box when `item.text` wraps at `item.width`.
  double heightOf(TextItem item);
}

/// Measures with Flutter's text layout, exactly like the page painter and
/// `export_builder.dart`.
class FlutterTextMetrics extends ConvertTextMetrics {
  const FlutterTextMetrics();

  @override
  double firstBaseline(TextItem item) {
    final painter = layoutTextItem(
        item.copyWith(text: item.text.isEmpty ? ' ' : item.text));
    try {
      final lines = painter.computeLineMetrics();
      return lines.isEmpty ? painter.height * 0.8 : lines.first.baseline;
    } finally {
      painter.dispose();
    }
  }

  @override
  double naturalWidth(TextItem item) {
    final painter = TextPainter(
      text: TextSpan(text: item.text, style: textStyleFor(item)),
      textDirection: TextDirection.ltr,
      textScaler: textItemScaler,
    )..layout();
    try {
      return painter.width;
    } finally {
      painter.dispose();
    }
  }

  @override
  double heightOf(TextItem item) => TextBoxEditor.measureHeight(item);
}

/// The geometry of one handwritten line, as far as the layout cares.
class LineGeometry {
  const LineGeometry({
    required this.left,
    required this.right,
    required this.baselineY,
    required this.xHeight,
    required this.inkTop,
    this.baselineSlope = 0,
  });

  factory LineGeometry.of(RecognizedLine line) {
    var top = double.infinity;
    for (final w in line.words) {
      top = math.min(top, w.bounds.top);
    }
    final baseline = line.baselineAt(line.left);
    return LineGeometry(
      left: line.left,
      right: line.right,
      baselineY: baseline,
      baselineSlope: line.baselineSlope,
      xHeight: line.xHeight,
      inkTop: top.isFinite ? top : baseline - 2 * line.xHeight,
    );
  }

  /// Left edge of the ink and the baseline height there (page points).
  final double left;
  final double right;
  final double baselineY;
  final double baselineSlope;
  final double xHeight;

  /// Highest ink point of the line.
  final double inkTop;

  double baselineAt(double x) => baselineY + baselineSlope * (x - left);
}

/// The ruled lines of a page that typed lines can sit on.
class PageRuling {
  const PageRuling(this.baselines, this.spacing);

  /// Ruled line heights, top to bottom.
  final List<double> baselines;

  /// Distance between ruled lines.
  final double spacing;

  /// The ruling of a page, or null for blank / dotted / music paper and for
  /// PDF pages (which show the PDF instead of the paper).
  static PageRuling? of(Paper paper, double width, double height,
      {bool isPdf = false}) {
    if (isPdf || !paper.hasRuledLines) return null;
    final lines = PaperGeometry(paper, width, height).baselines;
    if (lines.isEmpty) return null;
    final spacing =
        paper.spacingPt <= 4 ? ConvertConfig.fallbackRuling : paper.spacingPt;
    return PageRuling(List.unmodifiable(lines), spacing);
  }
}

/// The look the user picked in the review sheet.
class ConvertStyle {
  const ConvertStyle({
    this.font = FontKind.sans,
    this.bold = false,
    this.italic = false,
    this.fixedSize,
    this.colorOverride,
  });

  final FontKind font;
  final bool bold;
  final bool italic;

  /// Font size in points, or null for "Auto (match my handwriting)".
  final double? fixedSize;

  /// ARGB colour for every line, or null for "Keep my ink colour".
  final int? colorOverride;
}

/// One recognised line to lay out.
class LayoutLineInput {
  const LayoutLineInput({
    required this.id,
    required this.text,
    required this.geometry,
    required this.color,
    this.include = true,
  });

  final String id;
  final String text;
  final LineGeometry geometry;

  /// The line's dominant ink colour (ARGB).
  final int color;

  /// False for lines that stay handwriting; they only bound the line above.
  final bool include;
}

/// How much a line had to shrink to fit.
enum ConvertFit {
  /// Intended size, one line.
  natural,

  /// Shrunk, but to at least [ConvertConfig.softShrinkFactor] of the size.
  softShrink,

  /// Shrunk further, down to [ConvertConfig.floorSize].
  hardShrink,

  /// Smaller than the floor, as a last resort to stay clear of the next line.
  tinyShrink,

  /// Wrapped onto several lines inside the available width.
  wrapped,
}

/// A laid-out text box and how it came about.
class LaidOutLine {
  const LaidOutLine({
    required this.id,
    required this.item,
    required this.baselineY,
    required this.snapped,
    required this.fit,
    required this.collides,
  });

  /// The id of the [LayoutLineInput].
  final String id;
  final TextItem item;

  /// The page height the first line's baseline was put on.
  final double baselineY;

  /// True when [baselineY] is a ruled line rather than the handwriting's own
  /// baseline.
  final bool snapped;
  final ConvertFit fit;

  /// True only when even the smallest allowed text still runs into the next
  /// line (extremely tight handwriting).
  final bool collides;
}

/// The font size that makes [font] look as big as writing with the given
/// x-height: `xHeight / ratio`, within the auto limits, and on ruled paper
/// at most [ConvertConfig.maxSizeOfRuling] of the ruling.
double autoFontSize(FontKind font, double xHeight, {double? ruling}) {
  final ratio = ConvertConfig.fontXHeightRatio[font.category] ??
      ConvertConfig.defaultXHeightRatio;
  final raw = xHeight.isFinite && xHeight > 0
      ? xHeight / ratio
      : ConvertConfig.minAutoSize;
  var size =
      raw.clamp(ConvertConfig.minAutoSize, ConvertConfig.maxAutoSize).toDouble();
  if (ruling != null) {
    size = math.min(size, ConvertConfig.maxSizeOfRuling * ruling);
  }
  return size;
}

/// Collapses line breaks and runs of spaces: one handwritten line becomes
/// one line of text (it wraps only when it has to).
String normalizeLineText(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Lays out [lines] (top to bottom) on one page.
///
/// For every included line with text one box is made:
///
/// * `x` is the ink's left edge and the first text baseline sits on the
///   handwriting baseline there, snapped to the nearest ruled line when the
///   page is ruled ([ruling]); the top is `baseline - ascent` of the font,
///   found from the first line's metrics like the PDF exporter does;
/// * the size is the user's fixed size or [autoFontSize]. A line wider than
///   the room to the right margin first shrinks to fit (down to the floor),
///   and only then wraps inside the available width;
/// * a box never runs into the line below (included or not): the size is
///   reduced step by step until it clears it.
///
/// The result has one entry per laid-out line, in input order.
List<LaidOutLine> layoutPage({
  required double pageWidth,
  required double pageHeight,
  required List<LayoutLineInput> lines,
  required ConvertStyle style,
  PageRuling? ruling,
  ConvertTextMetrics metrics = const FlutterTextMetrics(),
  Uuid? uuid,
}) {
  final ids = uuid ?? const Uuid();
  final n = lines.length;
  final texts = [for (final l in lines) normalizeLineText(l.text)];
  bool active(int i) => lines[i].include && texts[i].isNotEmpty;

  // 1. Baselines, top to bottom: handwriting baseline, snapped to the
  //    nearest free ruled line.
  final baseline = List<double>.filled(n, 0);
  final snapped = List<bool>.filled(n, false);
  var previousRule = double.negativeInfinity;
  for (var i = 0; i < n; i++) {
    if (!active(i)) continue;
    final b = lines[i].geometry.baselineAt(lines[i].geometry.left);
    baseline[i] = b;
    if (ruling == null) continue;
    double? best;
    for (final r in ruling.baselines) {
      if (r <= previousRule + 1e-6) continue;
      if (best == null || (r - b).abs() < (best - b).abs()) best = r;
    }
    if (best != null &&
        (best - b).abs() <= ConvertConfig.snapReach * ruling.spacing) {
      baseline[i] = best;
      snapped[i] = true;
      previousRule = best;
    }
  }

  // 2. Boxes, bottom to top, so every line knows the top of the one below.
  //    Each line's size is also capped by the baseline distance to the line
  //    above, so tight lines get small text instead of a pile-up.
  final out = List<LaidOutLine?>.filled(n, null);
  var nextTop = double.infinity;
  for (var i = n - 1; i >= 0; i--) {
    if (!active(i)) {
      nextTop = lines[i].geometry.inkTop;
      continue;
    }
    final placed = _placeLine(
      id: ids.v4(),
      lineId: lines[i].id,
      text: texts[i],
      geometry: lines[i].geometry,
      color: style.colorOverride ?? lines[i].color,
      baseline: baseline[i],
      snapped: snapped[i],
      nextTop: nextTop,
      gapAbove: i == 0
          ? double.infinity
          : baseline[i] -
              (active(i - 1)
                  ? baseline[i - 1]
                  : lines[i - 1].geometry.baselineAt(lines[i - 1].geometry.left)),
      pageWidth: pageWidth,
      style: style,
      ruling: ruling,
      metrics: metrics,
    );
    out[i] = placed;
    nextTop = placed.item.y;
  }
  return [for (final o in out) ?o];
}

LaidOutLine _placeLine({
  required String id,
  required String lineId,
  required String text,
  required LineGeometry geometry,
  required int color,
  required double baseline,
  required bool snapped,
  required double nextTop,
  required double gapAbove,
  required double pageWidth,
  required ConvertStyle style,
  required PageRuling? ruling,
  required ConvertTextMetrics metrics,
}) {
  const slack = ConvertConfig.lineSlack;
  final rightEdge = pageWidth - ConvertConfig.rightMargin;
  var x = math.max(0.0, geometry.left);
  if (rightEdge - x < 60) x = math.max(0.0, rightEdge - 60);
  final avail = math.max(rightEdge - x, ConvertConfig.minBoxWidth);

  var base = style.fixedSize ??
      autoFontSize(style.font, geometry.xHeight, ruling: ruling?.spacing);

  TextItem build(double size, double width) => TextItem(
        id: id,
        x: x,
        y: 0,
        width: width,
        height: 0,
        text: text,
        fontSize: size,
        color: color,
        bold: style.bold,
        italic: style.italic,
        font: style.font,
      );

  // A line of text is about `lineHeightRatio` times the font size tall; two
  // lines of the same size need their baselines at least that far apart.
  if (gapAbove.isFinite && gapAbove > 0) {
    final lineHeightRatio = metrics.heightOf(build(100, 1e6)) / 100;
    if (lineHeightRatio > 0) {
      base = math.min(
          base, math.max(gapAbove / lineHeightRatio, ConvertConfig.floorSize));
    }
  }

  double natural(double size) => metrics.naturalWidth(build(size, avail));

  // The box for [size]: as wide as the text wants (at most the room), as tall
  // as the wrapped text, with its first baseline on [baseline].
  TextItem place(double size) {
    final nw = natural(size);
    final width = math.min(avail, math.max(nw + slack, ConvertConfig.minBoxWidth));
    final box = build(size, width);
    final ascent = metrics.firstBaseline(box);
    return box.copyWith(
      y: math.max(0.0, baseline - ascent),
      height: metrics.heightOf(box),
    );
  }

  bool fits(TextItem item) => item.y + item.height <= nextTop + 0.01;

  // Largest size (at most [from]) whose text fits on one line in the room.
  double widthFit(double from) {
    final nw = natural(from);
    if (nw <= avail - slack) return from;
    var s = from * (avail - slack) / nw;
    while (natural(s) > avail - slack && s > ConvertConfig.absoluteMinSize) {
      s *= 0.98;
    }
    return s;
  }

  // Shrinks [size] until the box clears the line below or [min] is reached.
  double clear(double size, double min) {
    var s = size;
    while (!fits(place(s)) && s > min) {
      s = math.max(min, s * ConvertConfig.shrinkStep);
    }
    return s;
  }

  var size = base;
  final single = widthFit(base);
  if (single >= ConvertConfig.floorSize || single >= base) {
    // One line: shrink to fit the width, then to clear the line below.
    size = clear(single, ConvertConfig.absoluteMinSize);
  } else {
    // Too long even at the floor size: wrap, as big as clears the next line.
    final wrapStart = math.max(
        ConvertConfig.floorSize, base * ConvertConfig.softShrinkFactor);
    size = clear(wrapStart, ConvertConfig.floorSize);
    if (!fits(place(size))) {
      // Still in the way: one line shrunk below the floor, if it can.
      final tiny = math.max(single, ConvertConfig.absoluteMinSize);
      size = clear(tiny, ConvertConfig.absoluteMinSize);
    }
  }

  final item = place(size);
  final wrapped = natural(size) + slack > avail + 1e-6;
  final ConvertFit fit;
  if (wrapped) {
    fit = ConvertFit.wrapped;
  } else if (size >= base - 1e-9) {
    fit = ConvertFit.natural;
  } else if (size >= base * ConvertConfig.softShrinkFactor - 1e-9) {
    fit = ConvertFit.softShrink;
  } else if (size >= ConvertConfig.floorSize - 1e-9) {
    fit = ConvertFit.hardShrink;
  } else {
    fit = ConvertFit.tinyShrink;
  }
  return LaidOutLine(
    id: lineId,
    item: item,
    baselineY: baseline,
    snapped: snapped,
    fit: fit,
    collides: !fits(item),
  );
}
