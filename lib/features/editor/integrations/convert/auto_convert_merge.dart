import 'dart:math' as math;

import '../../../../document/page_items.dart';
import '../text_images/text_editor.dart';
import 'convert_config.dart';
import 'convert_layout.dart';

/// One state of a text box auto-convert made: the box as it was, and where
/// the handwriting it replaced ended.
class AutoBoxVersion {
  const AutoBoxVersion(this.item, this.inkRight, this.inkBaseline);

  final TextItem item;

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
/// A box qualifies when the line sits on its baseline (within
/// [ConvertConfig.mergeBaselineTol] x-heights) and starts close to where its
/// typed text ends: from [ConvertConfig.mergeOverlap] x-heights over the
/// last letter to [ConvertConfig.mergeMaxGap] x-heights after it. That is
/// where the writer continues: the typed text is rarely as wide as the
/// handwriting it replaced. For the boxes auto-convert made ([boxes], with
/// the state it left them in), starting just after where the replaced
/// handwriting ended also counts (the pen may already have been down there).
///
/// Candidates are [boxes] and every other box of the page ([pageTexts]:
/// boxes typed earlier, by the Convert button or by hand); they must be one
/// line, left aligned, and the joined text must still fit on one line to the
/// right page margin. [liveItem] finds a box as it is now (null: it is
/// gone); boxes in [taken] already took a line this pass. The nearest wins.
/// The joined box keeps the autocorrect marks of both texts ([corrections]
/// are those of [text]).
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
}) {
  final xh = line.xHeight;
  if (!xh.isFinite || xh <= 0 || text.isEmpty) return null;
  final start = line.baselineAt(line.left);
  MergePlan? best;
  var bestGap = double.infinity;

  void consider(AutoBox box, TextItem live, AutoBoxVersion? base) {
    if (live.align != TextAlignKind.left) return;
    final typedEnd = live.x + metrics.naturalWidth(live);
    final typedBaseline = live.y + metrics.firstBaseline(live);
    double? gap;
    // After the typed text (the usual case) ...
    final g = line.left - typedEnd;
    if (g >= -ConvertConfig.mergeOverlap * xh &&
        g < ConvertConfig.mergeMaxGap * xh &&
        (start - typedBaseline).abs() < ConvertConfig.mergeBaselineTol * xh) {
      gap = g.abs();
    }
    // ... or after the handwriting the box replaced.
    if (base != null) {
      final h = line.left - base.inkRight;
      if (h >= 0 &&
          h < ConvertConfig.mergeMaxGap * xh &&
          (start - base.inkBaseline).abs() < ConvertConfig.mergeBaselineTol * xh) {
        gap = gap == null ? h : math.min(gap, h);
      }
    }
    if (gap == null || gap >= bestGap) return;

    // The old box must be a single line, and so must the joined text.
    const slack = ConvertConfig.lineSlack;
    if (metrics.naturalWidth(live) + slack > live.width + 1e-6) return;
    final head = '${live.text.trimRight()} ';
    final tail = text.trimLeft();
    final lead = text.length - tail.length;
    final grown = live.copyWith(text: head + tail);
    final joined = corrections.isEmpty
        ? grown
        : grown.copyWith(corrections: [
            ...grown.corrections,
            for (final c in corrections)
              if (c.start >= lead) c.shifted(head.length - lead),
          ]);
    final room = pageWidth - ConvertConfig.rightMargin - live.x;
    final natural = metrics.naturalWidth(joined);
    if (natural + slack > room) return;
    final wide = joined.copyWith(width: math.max(live.width, natural + slack));
    final after = wide.copyWith(height: metrics.heightOf(wide));
    best = MergePlan(box, live, after, base ?? AutoBoxVersion(live, typedEnd, typedBaseline));
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
  for (final t in pageTexts) {
    if (seen.contains(t.id) || taken.contains(t.id) || t.text.isEmpty) continue;
    final live = liveItem(t.id);
    if (live == null) continue;
    final typedEnd = live.x + metrics.naturalWidth(live);
    final typedBaseline = live.y + metrics.firstBaseline(live);
    consider(AutoBox(AutoBoxVersion(live, typedEnd, typedBaseline)), live, null);
  }
  return best;
}
