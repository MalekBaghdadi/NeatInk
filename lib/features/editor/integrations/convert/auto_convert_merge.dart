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
/// of one of the auto-made [boxes] instead of in a box of its own.
///
/// It does when the line sits on the same baseline (within
/// [ConvertConfig.mergeBaselineTol] x-heights) and starts after the end of
/// the handwriting that box replaced, no further than
/// [ConvertConfig.mergeMaxGap] x-heights away. The joined text must still
/// fit on one line to the right page margin. [liveItem] finds the box as it
/// is now (null: it is gone); boxes in [taken] already took a line this pass.
/// With several candidates the nearest wins.
MergePlan? planMerge({
  required Iterable<AutoBox> boxes,
  required TextItem? Function(String id) liveItem,
  required LineGeometry line,
  required String text,
  required double pageWidth,
  required ConvertTextMetrics metrics,
  Set<String> taken = const {},
}) {
  final xh = line.xHeight;
  if (!xh.isFinite || xh <= 0 || text.isEmpty) return null;
  MergePlan? best;
  var bestGap = double.infinity;
  for (final box in boxes) {
    if (taken.contains(box.id)) continue;
    final live = liveItem(box.id);
    if (live == null) continue;
    final base = box.versionOf(live);
    if (base == null) continue;
    final gap = line.left - base.inkRight;
    if (gap < 0 || gap >= ConvertConfig.mergeMaxGap * xh) continue;
    final drift = (line.baselineAt(line.left) - base.inkBaseline).abs();
    if (drift >= ConvertConfig.mergeBaselineTol * xh) continue;
    if (gap >= bestGap) continue;

    // The old box must be a single line, and so must the joined text.
    const slack = ConvertConfig.lineSlack;
    if (metrics.naturalWidth(live) + slack > live.width + 1e-6) continue;
    final joined = live.copyWith(text: '${live.text} $text');
    final room = pageWidth - ConvertConfig.rightMargin - live.x;
    final natural = metrics.naturalWidth(joined);
    if (natural + slack > room) continue;
    final wide = joined.copyWith(width: math.max(live.width, natural + slack));
    final after = wide.copyWith(height: metrics.heightOf(wide));
    best = MergePlan(box, live, after, base);
    bestGap = gap;
  }
  return best;
}
