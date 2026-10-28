import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../document/commands.dart';
import '../../../../document/notebook_doc.dart';
import '../../../../document/page_items.dart';
import '../../../../ink/vec2.dart';
import '../../../../render/text_style.dart';
import '../../editor_controller.dart';
import '../../editor_integrations.dart';
import '../convert/convert_config.dart';
import '../convert/convert_layout.dart';
import '../convert/user_lexicon.dart';

/// Autocorrect, iPad style: words autocorrect changed when handwriting
/// became text are underlined ([TextLayerPainter]); a tap on one (pen or
/// finger) shows a bubble with the word as it was written. Tapping the
/// bubble puts it back (one undo step; a spelling fix taken back is learned
/// in "My words" so it is not corrected again), the tick keeps the
/// correction and removes the mark.
final EditorIntegration autocorrectIntegration = _install;

void _install(EditorController controller, WidgetRef ref) {
  final bubble = AutocorrectBubble(
    controller,
    learner: ref.read(userLexiconProvider),
  );
  controller.addDisposeCallback(bubble.dispose);
  controller.extensions
    ..pageTapHandlers.add(bubble.onTap)
    ..viewportOverlays.add((context, c) => AutocorrectBubbleView(bubble: bubble));
}

/// A corrected word on a page: the box it is in and where it is drawn.
class CorrectionHit {
  const CorrectionHit({
    required this.pageId,
    required this.itemId,
    required this.correction,
    required this.rect,
  });

  final String pageId;
  final String itemId;
  final TextCorrection correction;

  /// The word's box in page points (its first line when it wraps).
  final Rect rect;
}

/// The corrected word under [point] on [texts] (page points), if any. The
/// word's box is grown by [slop] points so a quick tap still finds it.
CorrectionHit? correctionAt(String pageId, Iterable<TextItem> texts, Vec2 point, {double slop = 4}) {
  final at = Offset(point.x, point.y);
  for (final item in texts) {
    if (item.liveCorrections.isEmpty) continue;
    if (!item.frame.inflate(slop).contains(point)) continue;
    for (final (c, boxes) in correctionBoxes(item)) {
      for (final b in boxes) {
        if (b.inflate(slop).contains(at)) {
          return CorrectionHit(pageId: pageId, itemId: item.id, correction: c, rect: boxes.first);
        }
      }
    }
  }
  return null;
}

/// What the bubble shows, and its two actions.
class AutocorrectBubble extends ChangeNotifier {
  AutocorrectBubble(this.controller, {this.learner, this.metrics = const FlutterTextMetrics()}) {
    controller.addListener(_onControllerChanged);
    // Writing closes it. (A finished stroke, not a started one: a tap that
    // closes the bubble starts like a stroke but never finishes as one.)
    _finished = controller.strokeEvents.finished.listen((_) => dismiss());
  }

  final EditorController controller;
  final WordLearner? learner;
  final ConvertTextMetrics metrics;

  /// How long the bubble stays when nothing is tapped.
  static const Duration visibleFor = Duration(seconds: 6);

  late final StreamSubscription<Object?> _finished;
  CorrectionHit? _hit;
  Timer? _timer;

  /// The word the bubble is open for (null: closed).
  CorrectionHit? get hit => _hit;

  /// Page tap handler: opens the bubble on a corrected word; a tap
  /// elsewhere while it is open only closes it (and leaves no dot).
  bool onTap(String pageId, Vec2 point) {
    if (!controller.isReady || !controller.settings.autocorrect) return false;
    final found = correctionAt(pageId, controller.doc.page(pageId).texts, point,
        slop: 4 / math.max(controller.viewport.scale, 0.25));
    if (found == null) {
      if (_hit == null) return false;
      dismiss();
      return true;
    }
    _hookDoc();
    _hit = found;
    _timer?.cancel();
    _timer = Timer(visibleFor, dismiss);
    notifyListeners();
    return true;
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (_hit == null) return;
    _hit = null;
    notifyListeners();
  }

  /// Puts the written word back.
  void restoreOriginal() {
    final hit = _hit;
    final item = hit == null ? null : _liveItem(hit);
    dismiss();
    if (hit == null || item == null || !hit.correction.holdsIn(item.text)) return;
    var after = item.withOriginal(hit.correction);
    // A one-line box grows to keep the word on its line (to the page margin).
    final page = controller.doc.pageMeta(hit.pageId);
    final wasOneLine = metrics.naturalWidth(item) <= item.width + 1e-6;
    if (page != null && wasOneLine) {
      final want = metrics.naturalWidth(after) + ConvertConfig.lineSlack;
      final room = page.width - ConvertConfig.rightMargin - item.x;
      if (want > item.width) after = after.copyWith(width: math.min(want, math.max(room, item.width)));
    }
    after = after.copyWith(height: metrics.heightOf(after));
    controller.execute(PageItemsCommand(hit.pageId, label: 'Undo autocorrect', textChanges: [(item, after)]));
    final c = hit.correction;
    if (_isSpellingFix(c)) learner?.learnWord(c.original);
  }

  /// Keeps the correction; the word is no longer marked.
  void keep() {
    final hit = _hit;
    final item = hit == null ? null : _liveItem(hit);
    dismiss();
    if (hit == null || item == null) return;
    controller.execute(PageItemsCommand(hit.pageId,
        label: 'Keep correction', textChanges: [(item, item.withoutCorrection(hit.correction))]));
  }

  /// A plain word swapped for another plain word (not an apostrophe, a
  /// capital or `a` -> `an`): the writer meant that word.
  static bool _isSpellingFix(TextCorrection c) {
    final word = RegExp(r'^[A-Za-z]{3,}$');
    return word.hasMatch(c.original) &&
        word.hasMatch(c.replacement) &&
        c.original.toLowerCase() != c.replacement.toLowerCase();
  }

  TextItem? _liveItem(CorrectionHit hit) => controller.doc.page(hit.pageId).textById(hit.itemId);

  NotebookDoc? _hookedDoc;

  /// Follows the open document's edits (it exists only once the notebook
  /// is open, so this is done on the first tap).
  void _hookDoc() {
    final doc = controller.doc;
    if (identical(doc, _hookedDoc)) return;
    _hookedDoc?.removeListener(_onDocChanged);
    _hookedDoc = doc..addListener(_onDocChanged);
  }

  void _onDocChanged(DocChange _) => _onControllerChanged();

  /// Closes the bubble when its word changed or went away (undo, an edit).
  void _onControllerChanged() {
    final hit = _hit;
    if (hit == null) return;
    if (!controller.isReady) return dismiss();
    final item = _liveItem(hit);
    if (item == null || !item.liveCorrections.contains(hit.correction)) dismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_finished.cancel());
    controller.removeListener(_onControllerChanged);
    _hookedDoc?.removeListener(_onDocChanged);
    super.dispose();
  }
}

/// The bubble above a tapped corrected word: the word as written (tap to
/// put it back) and a tick (keep the correction).
class AutocorrectBubbleView extends StatelessWidget {
  const AutocorrectBubbleView({super.key, required this.bubble});

  final AutocorrectBubble bubble;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([bubble, bubble.controller.viewport]),
        builder: (context, _) {
          final hit = bubble.hit;
          final c = bubble.controller;
          if (hit == null || !c.isReady) return const SizedBox.shrink();
          final index = c.viewport.layout.indexOfPage(hit.pageId);
          if (index < 0) return const SizedBox.shrink();
          final topLeft = c.viewport.pageToLocal(index, Vec2(hit.rect.left, hit.rect.top));
          final bottomRight = c.viewport.pageToLocal(index, Vec2(hit.rect.right, hit.rect.bottom));
          final word = Rect.fromPoints(topLeft, bottomRight);
          return CustomSingleChildLayout(
            delegate: _BubbleLayout(word),
            child: _Bubble(
              original: hit.correction.original,
              onRestore: bubble.restoreOriginal,
              onKeep: bubble.keep,
            ),
          );
        },
      );
}

/// Centres the bubble above the word (below it when there is no room),
/// inside the view.
class _BubbleLayout extends SingleChildLayoutDelegate {
  _BubbleLayout(this.word);

  final Rect word;
  static const double gap = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = (word.center.dx - child.width / 2).clamp(8.0, math.max(8.0, size.width - child.width - 8));
    var y = word.top - gap - child.height;
    if (y < 8) y = word.bottom + gap;
    return Offset(x.toDouble(), y.clamp(8.0, math.max(8.0, size.height - child.height - 8)).toDouble());
  }

  @override
  bool shouldRelayout(_BubbleLayout old) => old.word != word;
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.original, required this.onRestore, required this.onKeep});

  final String original;
  final VoidCallback onRestore;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('autocorrect-bubble'),
      elevation: 4,
      color: scheme.inverseSurface,
      borderRadius: BorderRadius.circular(20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const ValueKey('autocorrect-restore'),
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
            onTap: onRestore,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.undo, size: 18, color: scheme.onInverseSurface),
                  const SizedBox(width: 6),
                  Text(
                    original,
                    style: TextStyle(color: scheme.onInverseSurface, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 22, color: scheme.onInverseSurface.withValues(alpha: 0.3)),
          Tooltip(
            message: 'Keep the correction',
            child: InkWell(
              key: const ValueKey('autocorrect-keep'),
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
              onTap: onKeep,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
                child: Icon(Icons.check, size: 18, color: scheme.onInverseSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
