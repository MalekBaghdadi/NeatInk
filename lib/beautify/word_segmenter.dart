import 'dart:math' as math;

import '../ink/ink_rect.dart';
import '../ink/stroke.dart';
import 'features.dart';
import 'line_context.dart';
import 'resample.dart';
import 'tidy_config.dart';

/// Spec step 1: deciding when a word is finished and which strokes belong
/// to it.
///
/// The segmenter is a small state machine the editor feeds with pen events
/// and a monotonic clock (milliseconds, any origin; tests drive it with made
/// up times). It never looks at the clock itself, so it is deterministic.
///
///     onPenDown(tool, now)      // may commit (tool change / idle)
///     onStrokeEnd(stroke, now)  // may commit (gap / new line) or attach
///     onTick(now)               // call at [idleDeadlineMs]; commits on idle
///     flush(reason)             // page change, tidy toggled off, …
///
/// Gap and new-line decisions use the finished stroke's bounding box, not
/// only its first point: an ascender can start well above the baseline, so
/// the first point is a poor guess of where a stroke lives.
enum CommitReason { idle, gap, newLine, toolChange, pageChange, tidyOff }

/// A pending word that is complete and should go to the tidy pipeline.
class CommittedWord {
  const CommittedWord(this.strokes, this.reason);
  final List<Stroke> strokes;
  final CommitReason reason;
}

/// What happened when a stroke ended.
class StrokeOutcome {
  const StrokeOutcome({this.committed, this.lateMarkWordId});

  /// The previous word, if this stroke finished it.
  final CommittedWord? committed;

  /// Set when the stroke is a late mark (i-dot, t-crossing, accent) of an
  /// already tidied word. The caller assigns the stroke that `wordId` and
  /// does not move it: it was drawn relative to the tidied word already.
  final String? lateMarkWordId;
}

class WordSegmenter {
  WordSegmenter({required this.page, this.config = const TidyConfig()});

  final PageContext page;
  final TidyConfig config;

  final List<Stroke> _pending = [];
  int? _lastUpMs;

  List<Stroke> get pending => List.unmodifiable(_pending);
  bool get hasPending => _pending.isNotEmpty;

  /// When the idle timer should fire (last pen-up + `wordIdleMs`), or null
  /// when nothing is pending.
  int? get idleDeadlineMs =>
      _pending.isEmpty || _lastUpMs == null ? null : _lastUpMs! + config.wordIdleMs;

  /// The x-height the thresholds are based on (spec step 1).
  double get xHeightEstimate => page.xHeightEstimate(page.lastLine);

  /// A pen touched down at [nowMs] with [tool]. Commits the pending word on
  /// a tool change (highlighter, eraser, lasso … anything but the pen) and
  /// when the idle time already ran out.
  CommittedWord? onPenDown({required StrokeTool? tool, required int nowMs}) {
    if (_pending.isEmpty) return null;
    if (tool != StrokeTool.pen) return flush(CommitReason.toolChange);
    return onTick(nowMs);
  }

  /// Advances the clock. Commits the pending word once no pen-down happened
  /// for `wordIdleMs` after the last pen-up.
  CommittedWord? onTick(int nowMs) {
    final deadline = idleDeadlineMs;
    if (deadline != null && nowMs >= deadline) {
      return flush(CommitReason.idle);
    }
    return null;
  }

  /// Commits whatever is pending (page change, tidy turned off, tool change).
  CommittedWord? flush(CommitReason reason) {
    if (_pending.isEmpty) return null;
    final word = CommittedWord(List.unmodifiable(_pending), reason);
    _pending.clear();
    _lastUpMs = null;
    return word;
  }

  /// Forgets the pending strokes without committing them.
  void reset() {
    _pending.clear();
    _lastUpMs = null;
  }

  /// [stroke] was lifted at [upMs]. Highlighter strokes and shapes never
  /// join a word (and end the pending one).
  StrokeOutcome onStrokeEnd(Stroke stroke, {required int upMs}) {
    if (stroke.isHighlighter || stroke.shape != null) {
      return StrokeOutcome(committed: flush(CommitReason.toolChange));
    }
    final box = finiteBounds(stroke.raw);
    if (box == null) return const StrokeOutcome();

    final late = _lateMarkTarget(stroke, box);
    if (late != null) return StrokeOutcome(lateMarkWordId: late);

    CommittedWord? committed;
    if (_pending.isNotEmpty) {
      final reason = _splitReason(box);
      if (reason != null) committed = flush(reason);
    }
    _pending.add(stroke);
    _lastUpMs = upMs;
    return StrokeOutcome(committed: committed);
  }

  /// Does a stroke with bounds [box] start a new word / line relative to the
  /// pending strokes? Null when it continues the pending word.
  CommitReason? _splitReason(InkRect box) {
    final x = xHeightEstimate;
    final scale = math.max(x, 1e-3);

    // New line: the stroke's centre is far above/below the pending baseline.
    final baseline = estimateBaselineY(
        [for (final s in _pending) s.raw],
        scaleHint: scale,
        config: config);
    if (baseline != null) {
      final lineHeight = page.lineHeight(page.lastLine);
      if ((box.center.y - baseline).abs() > config.newLineFactor * lineHeight) {
        return CommitReason.newLine;
      }
    }

    // Gap: its left edge is far right of the pending word's right edge.
    var right = double.negativeInfinity;
    for (final s in _pending) {
      final b = finiteBounds(s.raw);
      if (b != null && b.right > right) right = b.right;
    }
    if (box.left - right > config.wordGapFactor * scale) return CommitReason.gap;
    return null;
  }

  /// Late marks (spec step 1): a small stroke, or a short horizontal one,
  /// drawn after a word was tidied and landing inside that word's box
  /// (grown a little) belongs to that word.
  String? _lateMarkTarget(Stroke stroke, InkRect box) {
    String? best;
    var bestDist = double.infinity;
    final x = xHeightEstimate;
    for (final w in page.words) {
      if (!w.tidied) continue;
      final small = box.diagonal < config.smallMarkFactor * x;
      final shortBar = box.width < config.lateStrokeMaxWidthFactor * x &&
          box.height < config.lateStrokeMaxHeightFactor * x;
      if (!small && !shortBar) continue;
      final zone = w.bounds.inflate(config.lateMarkBoxPadFactor * x);
      if (!zone.contains(box.center)) continue;
      final d = box.center.distanceTo(w.bounds.center);
      if (d < bestDist) {
        bestDist = d;
        best = w.wordId;
      }
    }
    return best;
  }
}
