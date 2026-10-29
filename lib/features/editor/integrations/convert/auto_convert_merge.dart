import 'dart:math' as math;
import 'dart:ui' show Rect;

import '../../../../document/page_items.dart';
import '../text_images/text_editor.dart';
import 'convert_config.dart';
import 'convert_layout.dart';

/// One state of a text box auto-convert made: the box as it was, and where
/// the handwriting it replaced ended.
class AutoBoxVersion {
  const AutoBoxVersion(this.item, this.inkRight, this.inkBaseline, {this.inkXHeight});

  final TextItem item;

  /// x-height of the handwriting the box replaced (its last line), when
  /// known: how far above it an i-dot written later may land.
  final double? inkXHeight;

  /// Right edge of the handwriting the box replaced (page points) and the
  /// height of its baseline there. The next line is compared with these, not
  /// with the typed box: typed text is rarely as wide as the writing was.
  final double inkRight;
  final double inkBaseline;
}

/// A text box made by auto-convert, remembered in memory for the session so
/// later lines can be appended to it. Keeps every state the box had, so it
/// is still found after the user undoes a merge.
class AutoBox {
  AutoBox(AutoBoxVersion first) : versions = [first];

  final List<AutoBoxVersion> versions;

  String get id => versions.first.item.id;

  /// The remembered state that [live] is identical to, or null when the user
  /// moved, edited or restyled the box since.
  AutoBoxVersion? versionOf(TextItem live) {
    for (final v in versions.reversed) {
      if (TextBoxEditor.sameText(v.item, live)) return v;
    }
    return null;
  }
}

/// Appending a line to an existing box: the box [before] grows into [after].
class MergePlan {
  const MergePlan(this.box, this.before, this.after, this.base);

  final AutoBox box;
  final TextItem before;
  final TextItem after;

  /// The state of the box the line was compared with.
  final AutoBoxVersion base;
}

/// Decides whether a line of [text] (handwriting [line]) belongs at the end
/// of an existing text box instead of in a box of its own: the sentence goes
/// on beside the typed text, with one space, instead of starting a second
/// box with a gap.
///
/// On the same line a box qualifies when the line sits on its baseline
/// (within [ConvertConfig.mergeBaselineTol] x-heights, or on the same ruled
/// line) and starts after its typed text or after where the handwriting it
/// replaced ended (a little over either is fine), at most [ConvertConfig.mergeMaxGap]
/// x-heights after where the handwriting it replaced ended, with no other
/// box in between. The typed text is rarely as wide as that handwriting, so
/// anywhere over the space it left counts too. Where the handwriting ended is
/// known for the boxes auto-convert made ([boxes], with the state it left
/// them in); for other boxes it is estimated from the size of the writing.
///
/// Candidates are [boxes] and every other box of the page ([pageTexts]:
/// boxes typed earlier, by the Convert button or by hand); on the same line
/// they must be one line and left aligned, and the joined text must still
/// fit on one line to the right page margin (with [joinLines] it may wrap).
/// [liveItem] finds a box as it is now (null: it is gone); boxes in [taken]
/// already took a line this pass. The nearest wins. The joined box keeps the
/// autocorrect marks of both texts ([corrections] are those of [text]).
///
/// With [joinLines] a line also carries on a box on a line above when the
/// box's sentence goes on there ([continuesOnNextLine]'s rules: it ran to the
/// right edge, or the words carry on); the box then wraps at the right
/// margin.
MergePlan? planMerge({
  required Iterable<AutoBox> boxes,
  required TextItem? Function(String id) liveItem,
  required LineGeometry line,
  required String text,
  List<TextCorrection> corrections = const [],
  required double pageWidth,
  required ConvertTextMetrics metrics,
  Iterable<TextItem> pageTexts = const [],
  Set<String> taken = const {},
  bool joinLines = false,
  PageRuling? ruling,
  TextColumn? column,
}) {
  final xh = line.xHeight;
  if (!xh.isFinite || xh <= 0 || text.isEmpty) return null;
  final start = line.baselineAt(line.left);
  final others = pageTexts.toList();
  MergePlan? best;
  var bestGap = double.infinity;

  // The ruled line nearest to [y], when it is close enough to snap to.
  int? ruleOf(double y) {
    final r = ruling;
    if (r == null) return null;
    var bestIndex = -1;
    for (var i = 0; i < r.baselines.length; i++) {
      if (bestIndex < 0 || (r.baselines[i] - y).abs() < (r.baselines[bestIndex] - y).abs()) {
        bestIndex = i;
      }
    }
    if (bestIndex < 0) return null;
    return (r.baselines[bestIndex] - y).abs() <= ConvertConfig.snapReach * r.spacing ? bestIndex : null;
  }

  final myRule = ruleOf(start);
  bool sameLine(double baseline) =>
      (start - baseline).abs() < ConvertConfig.mergeBaselineTol * xh ||
      (myRule != null && ruleOf(baseline) == myRule);

  // Another box between the end of [live]'s text and the new writing.
  bool blocked(TextItem live, double from, double to) {
    if (to <= from) return false;
    final band = Rect.fromLTRB(from, start - 1.5 * xh, to, start);
    for (final o in others) {
      if (o.id == live.id || o.text.isEmpty) continue;
      if (Rect.fromLTWH(o.x, o.y, o.width, o.height).overlaps(band)) return true;
    }
    return false;
  }

  // Baseline of the last line of [live].
  double lastBaselineOf(TextItem live) {
    final one = metrics.heightOf(live.copyWith(text: 'x', width: 1e6));
    final lines = one > 0 ? (metrics.heightOf(live) / one).round().clamp(1, 1000) : 1;
    return live.y + metrics.firstBaseline(live) + (lines - 1) * one;
  }

  // Whether writing ending at [right] ran out of room (in [column], if any).
  bool atRightEdge(double right) =>
      column == null ? ranToRightEdge(right, xh, pageWidth) : ranToColumnEdge(right, xh, column);

  // How far below the box's last line [line] starts, when it carries on the
  // box's unfinished sentence; else null.
  double? dropBelow(TextItem live, AutoBoxVersion? base) {
    if (endsSentence(live.text) || startsListItem(text)) return null;
    if (line.left > live.x + ConvertConfig.joinIndentXHeights * xh) return null;
    final double lastBaseline;
    final bool atEdge;
    if (base != null) {
      atEdge = atRightEdge(base.inkRight);
      lastBaseline = base.inkBaseline;
    } else {
      // A typed box: its text wraps, or reaches the edge itself.
      atEdge = metrics.naturalWidth(live) > live.width + 1e-6 ||
          atRightEdge(live.x + live.width);
      lastBaseline = lastBaselineOf(live);
    }
    if (!atEdge && !textCarriesOn(live.text, text)) return null;
    final drop = start - lastBaseline;
    return drop > 0 && drop <= maxLineDrop(xh, ruling) ? drop : null;
  }

  void consider(AutoBox box, TextItem live, AutoBoxVersion? base) {
    if (live.align != TextAlignKind.left) return;
    // On a PDF page with writing margins, only text in the same margin.
    if (column != null && !column.holds(live.x)) return;
    final typedEnd = live.x + metrics.naturalWidth(live);
    final typedBaseline = live.y + metrics.firstBaseline(live);
    // Where the handwriting the box replaced ended: remembered, or estimated
    // from how much wider the writing is than the typed text.
    final inkEnd = base?.inkRight ?? estimatedInkRight(live, typedEnd - live.x, xh);
    double? gap;
    // On the same line, after the typed text (or over the space the
    // handwriting left) and not too far after where the handwriting ended.
    final onLine = sameLine(typedBaseline) || (base != null && sameLine(base.inkBaseline));
    // The writer goes on after the typed text or after where the writing
    // ended, whichever came first (the pen may land a little over either).
    final earliest = math.min(typedEnd - ConvertConfig.mergeOverlap * xh,
        inkEnd - ConvertConfig.mergeInkOverlap * xh);
    if (onLine &&
        line.left >= earliest &&
        line.left < math.max(typedEnd, inkEnd) + ConvertConfig.mergeMaxGap * xh &&
        !blocked(live, typedEnd, line.left)) {
      gap = math.max(0, line.left - math.max(typedEnd, inkEnd));
    }
    // ... or on a line below, carrying on the sentence (after any box on the
    // same line).
    var below = false;
    if (gap == null && joinLines) {
      final drop = dropBelow(live, base);
      if (drop != null) {
        gap = ConvertConfig.mergeMaxGap * xh + drop;
        below = true;
      }
    }
    if (gap == null || gap >= bestGap) return;

    // Beside the text, the old box must be a single line.
    const slack = ConvertConfig.lineSlack;
    if (!below && metrics.naturalWidth(live) + slack > live.width + 1e-6) return;
    final tail = text.trimLeft();
    final lead = text.length - tail.length;
    final joinedText = below
        ? joinSentence(live.text, tail)
        : '${live.text.trimRight()} $tail';
    final tailStart = joinedText.length - tail.length;
    final grown = live.copyWith(text: joinedText);
    final joined = corrections.isEmpty
        ? grown
        : grown.copyWith(corrections: [
            ...grown.corrections,
            for (final c in corrections)
              if (c.start >= lead) c.shifted(tailStart - lead),
          ]);
    final room = (column?.right ?? pageWidth - ConvertConfig.rightMargin) - live.x;
    final natural = metrics.naturalWidth(joined);
    // One line when it fits; else, joining sentences, it wraps at the margin.
    final double width;
    if (natural + slack <= room) {
      width = math.max(live.width, natural + slack);
    } else if (joinLines) {
      width = math.max(live.width, room);
    } else {
      return;
    }
    final wide = joined.copyWith(width: width);
    final after = wide.copyWith(height: metrics.heightOf(wide));
    best = MergePlan(box, live, after, base ?? AutoBoxVersion(live, inkEnd, typedBaseline));
    bestGap = gap;
  }

  final seen = <String>{};
  for (final box in boxes) {
    seen.add(box.id);
    if (taken.contains(box.id)) continue;
    final live = liveItem(box.id);
    if (live == null) continue;
    consider(box, live, box.versionOf(live));
  }
  for (final t in others) {
    if (seen.contains(t.id) || taken.contains(t.id) || t.text.isEmpty) continue;
    final live = liveItem(t.id);
    if (live == null) continue;
    consider(AutoBox(AutoBoxVersion(live, live.x + metrics.naturalWidth(live), live.y + metrics.firstBaseline(live))),
        live, null);
  }
  return best;
}

/// Where the handwriting a typed box replaced probably ended, when that was
/// not remembered (a box from an earlier session or the Convert button):
/// handwriting with x-height [inkXHeight] is about that many times wider
/// than the typed text ([typedWidth]) per typed x-height.
double estimatedInkRight(TextItem live, double typedWidth, double inkXHeight) {
  final ratio = ConvertConfig.fontXHeightRatio[live.font.category] ?? ConvertConfig.defaultXHeightRatio;
  final typedXHeight = live.fontSize * ratio;
  if (!(typedXHeight > 0) || !(inkXHeight > 0)) return live.x + typedWidth;
  final scale = (inkXHeight / typedXHeight).clamp(1.0, ConvertConfig.maxInkWidthScale);
  return live.x + typedWidth * scale;
}
