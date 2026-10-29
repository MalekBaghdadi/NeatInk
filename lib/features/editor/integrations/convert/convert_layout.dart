import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:uuid/uuid.dart';

import '../../../../document/notebook_meta.dart';
import '../../../../document/page_items.dart';
import '../../../../document/paper.dart';
import '../../../../recognition/stroke_grouping.dart';
import '../../../../render/text_style.dart';
import '../../../settings/convert_style_prefs.dart';
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

/// Where converted text goes across a page: [left] is the first x a box may
/// start at, [right] the edge it wraps at, [ruling] the ruled lines it sits
/// on (null: none).
class TextColumn {
  const TextColumn({required this.left, required this.right, this.ruling});

  final double left;
  final double right;
  final PageRuling? ruling;

  double get width => right - left;

  /// Whether a box at [x] is in this column.
  bool holds(double x) => x >= left - 1 && x < right;
}

/// The column of [page] for writing that starts at [x], or null for a page
/// without PDF writing margins (the whole page, as always). On a PDF page
/// with margins (v1.9.0): the margin [x] is in, with the margin paper's
/// ruled lines, so typed notes wrap at the PDF's edge instead of running
/// over it and sit on the margin's lines; or the PDF page between them.
TextColumn? textColumnAt(PageMeta page, double x) {
  if (!page.isPdf || !page.hasMargins) return null;
  final ruling = PageRuling.of(page.paper, page.width, page.height);
  if (page.marginLeft > 0 && x < page.contentLeft) {
    return TextColumn(left: 0, right: page.contentLeft - ConvertConfig.pdfEdgeGap, ruling: ruling);
  }
  if (page.marginRight > 0 && x >= page.contentRight) {
    return TextColumn(
        left: page.contentRight + ConvertConfig.pdfEdgeGap,
        right: page.width - ConvertConfig.rightMargin,
        ruling: ruling);
  }
  return TextColumn(left: page.contentLeft, right: page.contentRight - ConvertConfig.pdfEdgeGap);
}

/// The look the user picked in the review sheet.
class ConvertStyle {
  const ConvertStyle({
    this.font = FontKind.sans,
    this.bold = false,
    this.italic = false,
    this.fixedSize,
    this.colorOverride,
    this.evenSize = false,
    this.joinLines = false,
  });

  /// The look remembered in the settings (see [ConvertStylePrefs]).
  factory ConvertStyle.fromPrefs(ConvertStylePrefs prefs) => ConvertStyle(
        font: prefs.font,
        bold: prefs.bold,
        italic: prefs.italic,
        fixedSize: prefs.sizeMode == ConvertSizeMode.custom
            ? prefs.fixedSize ?? ConvertConfig.defaultFixedSize
            : null,
        colorOverride: prefs.colorOverride,
        evenSize: prefs.sizeMode == ConvertSizeMode.even,
        joinLines: prefs.joinLines,
      );

  /// This look as something that can be remembered.
  ConvertStylePrefs toPrefs() => ConvertStylePrefs(
        fontId: font.name,
        bold: bold,
        italic: italic,
        sizeMode: evenSize
            ? ConvertSizeMode.even
            : fixedSize != null
                ? ConvertSizeMode.custom
                : ConvertSizeMode.handwriting,
        fixedSize: fixedSize,
        colorOverride: colorOverride,
        joinLines: joinLines,
      );

  final FontKind font;
  final bool bold;
  final bool italic;

  /// Font size in points, or null for "Auto (match my handwriting)".
  final double? fixedSize;

  /// ARGB colour for every line, or null for "Keep my ink colour".
  final int? colorOverride;

  /// One size for every line, from the page ([evenFontSize]); wins over
  /// [fixedSize].
  final bool evenSize;

  /// Lines of one sentence become one wrapping box ([continuesOnNextLine]).
  final bool joinLines;

  /// The size stays the same for every line: long text wraps instead of
  /// shrinking to fit.
  bool get keepsSize => evenSize || fixedSize != null;
}

/// The even size ([ConvertStyle.evenSize]) on a page: on ruled paper the
/// size that sits well on the ruling ([ConvertConfig.evenSizeOfRuling]),
/// otherwise [ConvertConfig.defaultFixedSize].
double evenFontSize(PageRuling? ruling) {
  final spacing = ruling?.spacing;
  if (spacing == null || !spacing.isFinite || spacing <= 0) {
    return ConvertConfig.defaultFixedSize;
  }
  return (spacing * ConvertConfig.evenSizeOfRuling)
      .roundToDouble()
      .clamp(ConvertConfig.minFixedSize, ConvertConfig.maxFixedSize)
      .toDouble();
}

final RegExp _sentenceEnd = RegExp('[.!?:;…]["\'”’)\\]]*\$');

/// Whether [text] ends a sentence (`.`, `!`, `?`, `:` or `;`, maybe
/// followed by quotes or brackets).
bool endsSentence(String text) => _sentenceEnd.hasMatch(text.trimRight());

/// Whether [next], the line written below [line], carries on [line]'s
/// sentence. [text] and [nextText] are what the two lines say.
///
/// Never across a sentence end or into a list item, never when the next line
/// starts further right (an indent) or too far below ([maxLineDrop]: one
/// skipped ruled line is fine, many writers leave one). Then either the
/// words say the sentence goes on ([textCarriesOn]), or the writing ran out
/// of room on the line ([sentenceWraps]).
bool continuesOnNextLine({
  required LineGeometry line,
  required String text,
  required LineGeometry next,
  required String nextText,
  required double pageWidth,
  PageRuling? ruling,
  TextColumn? column,
}) {
  if (text.trim().isEmpty || endsSentence(text)) return false;
  if (nextText.trim().isEmpty || startsListItem(nextText)) return false;
  final xh = math.max(line.xHeight, next.xHeight);
  if (!xh.isFinite || xh <= 0) return false;
  if (next.left > line.left + ConvertConfig.joinIndentXHeights * xh) return false;
  final drop = next.baselineAt(next.left) - line.baselineAt(line.left);
  if (drop <= 0 || drop > maxLineDrop(xh, ruling)) return false;
  return textCarriesOn(text, nextText) ||
      sentenceWraps(
          right: line.right, next: next, nextText: nextText, xHeight: xh, pageWidth: pageWidth, column: column);
}

/// Whether a line of writing that ended at [right] broke there for want of
/// room: the first word of the next line ([next], saying [nextText]) would
/// not have fitted after it, a gap on, before the right margin (of
/// [column] if any). The word's width is its share of the next line's ink
/// by letters. A next line starting with a capital is a new thought, not
/// the rest of a sentence (`I` aside).
bool sentenceWraps({
  required double right,
  required LineGeometry next,
  required String nextText,
  required double xHeight,
  required double pageWidth,
  TextColumn? column,
}) {
  final words = nextText.trim().split(RegExp(r'\s+'));
  final first = words.first;
  if (RegExp('^[A-Z]').hasMatch(first) && first != 'I' && !first.startsWith("I'")) return false;
  final letters = nextText.trim().length;
  final inkWidth = next.right - next.left;
  final wordWidth = letters > 0 && inkWidth > 0 ? inkWidth * first.length / letters : first.length * xHeight;
  final edge = column?.right ?? pageWidth - ConvertConfig.rightMargin;
  return right + ConvertConfig.joinWordGapXHeights * xHeight + wordWidth > edge;
}

/// Words that do not end a sentence: after them the sentence goes on
/// (articles, prepositions, conjunctions, auxiliary verbs, possessives).
const Set<String> continuationWords = {
  'a', 'an', 'the', 'my', 'your', 'his', 'her', 'its', 'our', 'their', 'this', 'these', 'those', 'some', 'any', 'each',
  'every', 'of', 'to', 'in', 'on', 'at', 'for', 'with', 'from', 'by', 'into', 'onto', 'about', 'over', 'under', 'between',
  'through', 'during', 'after', 'before', 'without', 'within', 'among', 'against', 'towards', 'toward', 'upon', 'via', 'than',
  'as', 'like', 'and', 'or', 'but', 'nor', 'because', 'although', 'though', 'while', 'when', 'whereas', 'if', 'unless', 'until',
  'since', 'whether', 'where', 'which', 'who', 'whom', 'whose', 'that', 'is', 'are', 'was', 'were', 'be', 'been', 'being', 'am',
  'has', 'have', 'had', 'do', 'does', 'did', 'will', 'would', 'can', 'could', 'should', 'may', 'might', 'must', 'shall', 'not',
  'very', 'more', 'most', 'less', 'such', 'also', 'so', 'then', 'both', 'either', 'neither',
};

final RegExp _listMarker = RegExp(r'^\s*([-–—•·*+>]|\(?\d{1,3}[.)]|\(?[a-zA-Z][)])(\s|$)');

/// Whether [text] begins with a list marker: a dash or bullet, `1.`, `2)`,
/// `a)`.
bool startsListItem(String text) => _listMarker.hasMatch(text);

/// Whether the words of a line ([text]) and of the line below ([nextText])
/// read as one sentence broken over the two: the line ends with a comma,
/// hyphen or open bracket, or on a word a sentence cannot end on
/// ([continuationWords]).
bool textCarriesOn(String text, String nextText) {
  final a = text.trim(), b = nextText.trim();
  if (a.isEmpty || b.isEmpty) return false;
  if (RegExp(r'[,\-–—(]$').hasMatch(a)) return true;
  final last = a.split(RegExp(r'\s+')).last.replaceAll(RegExp(r"[^A-Za-z']"), '').toLowerCase();
  return continuationWords.contains(last);
}

/// How far below a line the next line of the same sentence may start.
double maxLineDrop(double xHeight, PageRuling? ruling) => ruling != null
    ? ruling.spacing * ConvertConfig.joinMaxRulings
    : xHeight * ConvertConfig.joinMaxXHeights;

/// [a] and [b] as one sentence: a space between them, or nothing after a
/// word broken with a hyphen (`neuro-` + `science`).
String joinSentence(String a, String b) {
  final head = a.trimRight(), tail = b.trimLeft();
  if (head.isEmpty) return tail;
  if (tail.isEmpty) return head;
  if (RegExp(r'[A-Za-z]-$').hasMatch(head) && RegExp('^[a-z]').hasMatch(tail)) {
    return head.substring(0, head.length - 1) + tail;
  }
  return '$head $tail';
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
    List<String>? lineIds,
  }) : lineIds = lineIds ?? const [];

  /// The id of the [LayoutLineInput] (the first one, for joined lines).
  final String id;

  /// With [ConvertStyle.joinLines], the ids of all the lines joined into
  /// this box, in order; empty for a box of one line ([members] has it).
  final List<String> lineIds;

  /// The ids of the lines in this box.
  List<String> get members => lineIds.isEmpty ? [id] : lineIds;
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

  LaidOutLine withItem(TextItem item) => LaidOutLine(
        id: id,
        item: item,
        baselineY: baselineY,
        snapped: snapped,
        fit: fit,
        collides: collides,
        lineIds: lineIds,
      );

  LaidOutLine withLines(List<String> ids) => LaidOutLine(
        id: id,
        item: item,
        baselineY: baselineY,
        snapped: snapped,
        fit: fit,
        collides: collides,
        lineIds: ids,
      );
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
///   reduced step by step until it clears it;
/// * with an even or fixed size ([ConvertStyle.keepsSize]) the size never
///   changes: a long line wraps at the right margin, and a box that would
///   run into the one above it is moved down to the next free (ruled) line
///   instead;
/// * on ruled paper every box gets the ruling as its line spacing
///   ([TextItem.lineSpacing]), so wrapped lines sit on the ruled lines;
/// * with [ConvertStyle.joinLines], consecutive lines of one sentence
///   ([continuesOnNextLine]) become one box that wraps at the right margin
///   ([LaidOutLine.members]).
///
/// The result has one entry per laid-out box, in input order.
List<LaidOutLine> layoutPage({
  required double pageWidth,
  required double pageHeight,
  required List<LayoutLineInput> lines,
  required ConvertStyle style,
  PageRuling? ruling,
  TextColumn? column,
  ConvertTextMetrics metrics = const FlutterTextMetrics(),
  Uuid? uuid,
}) {
  final joined = style.joinLines
      ? _joinParagraphs(lines, pageWidth, ruling, column)
      : (lines: lines, members: <List<String>>[for (final _ in lines) const []]);
  return _layoutLines(
    pageWidth: pageWidth,
    column: column,
    lines: joined.lines,
    members: joined.members,
    style: style,
    ruling: ruling,
    metrics: metrics,
    ids: uuid ?? const Uuid(),
  );
}

/// [lines] with each run of lines of one sentence merged into one input
/// (the first line's place and colour, the texts joined), and for each
/// input the ids of the lines it holds (empty when just itself).
({List<LayoutLineInput> lines, List<List<String>> members}) _joinParagraphs(
    List<LayoutLineInput> lines, double pageWidth, PageRuling? ruling, TextColumn? column) {
  final out = <LayoutLineInput>[];
  final members = <List<String>>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final text = normalizeLineText(l.text);
    final prev = i > 0 ? lines[i - 1] : null;
    if (prev != null &&
        out.last.include &&
        l.include &&
        text.isNotEmpty &&
        continuesOnNextLine(
            line: prev.geometry,
            text: normalizeLineText(prev.text),
            next: l.geometry,
            nextText: text,
            pageWidth: pageWidth,
            ruling: ruling,
            column: column)) {
      final last = out.last;
      out[out.length - 1] = LayoutLineInput(
        id: last.id,
        text: joinSentence(normalizeLineText(last.text), text),
        geometry: last.geometry,
        color: last.color,
      );
      final ids = members.last;
      members[members.length - 1] = [...(ids.isEmpty ? [last.id] : ids), l.id];
      continue;
    }
    out.add(l);
    members.add(const []);
  }
  return (lines: out, members: members);
}

List<LaidOutLine> _layoutLines({
  required double pageWidth,
  TextColumn? column,
  required List<LayoutLineInput> lines,
  required List<List<String>> members,
  required ConvertStyle style,
  required PageRuling? ruling,
  required ConvertTextMetrics metrics,
  required Uuid ids,
}) {
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
      column: column,
      style: style,
      ruling: ruling,
      metrics: metrics,
      paragraph: members[i].isNotEmpty,
    );
    out[i] = members[i].isEmpty ? placed : placed.withLines(members[i]);
    nextTop = placed.item.y;
  }
  if (style.keepsSize) _pushDown(out, ruling, metrics);
  return [for (final o in out) ?o];
}

/// With a size that never shrinks, a box that reaches into the one above it
/// (a joined sentence that wraps onto more lines than the writing took) is
/// moved down, top to bottom, to the first (ruled) line where it clears.
void _pushDown(List<LaidOutLine?> boxes, PageRuling? ruling, ConvertTextMetrics metrics) {
  var bottom = double.negativeInfinity;
  for (var i = 0; i < boxes.length; i++) {
    final o = boxes[i];
    if (o == null) continue;
    var item = o.item;
    if (item.y < bottom - 0.5) {
      final ascent = metrics.firstBaseline(item);
      var baseline = bottom + ascent;
      var snapped = false;
      for (final r in ruling?.baselines ?? const <double>[]) {
        if (r >= baseline - 0.01) {
          baseline = r;
          snapped = true;
          break;
        }
      }
      item = item.copyWith(y: baseline - ascent);
      boxes[i] = LaidOutLine(
        id: o.id,
        item: item,
        baselineY: baseline,
        snapped: snapped,
        fit: o.fit,
        collides: false,
        lineIds: o.lineIds,
      );
    }
    bottom = item.y + item.height;
  }
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
  TextColumn? column,
  required ConvertStyle style,
  required PageRuling? ruling,
  required ConvertTextMetrics metrics,
  bool paragraph = false,
}) {
  const slack = ConvertConfig.lineSlack;
  final rightEdge = column?.right ?? pageWidth - ConvertConfig.rightMargin;
  final leftEdge = column?.left ?? 0.0;
  var x = math.max(leftEdge, geometry.left);
  if (rightEdge - x < 60) x = math.max(leftEdge, rightEdge - 60);
  final avail = math.max(rightEdge - x, ConvertConfig.minBoxWidth);

  var base = style.evenSize
      ? evenFontSize(ruling)
      : style.fixedSize ??
          autoFontSize(style.font, geometry.xHeight, ruling: ruling?.spacing);
  // Even and fixed sizes, and joined sentences, wrap rather than shrink.
  final keepSize = style.keepsSize || paragraph;

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
        lineSpacing: ruling?.spacing,
      );

  // A line of text is about `lineHeightRatio` times the font size tall; two
  // lines of the same size need their baselines at least that far apart.
  // (Not for even and fixed sizes: they are the size the user chose.)
  if (!style.keepsSize && gapAbove.isFinite && gapAbove > 0) {
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
  final single = keepSize ? base : widthFit(base);
  if (style.keepsSize) {
    // Even and fixed sizes never change: long text wraps, and a box in the
    // way of the next one is moved instead ([_pushDown]). Text that shrank
    // to stay clear of handwriting below looked like a mistake (v1.6.0).
    size = base;
  } else if (keepSize) {
    // The chosen size, wrapping when long; a little smaller if it would run
    // into the line below, and only as a last resort more than that.
    size = clear(base, base * ConvertConfig.softShrinkFactor);
    if (!fits(place(size))) size = clear(size, ConvertConfig.absoluteMinSize);
  } else if (single >= ConvertConfig.floorSize || single >= base) {
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
    collides: !style.keepsSize && !fits(item),
  );
}
