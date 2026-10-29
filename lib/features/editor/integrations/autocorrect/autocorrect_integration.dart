import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../document/commands.dart';
import '../../../../document/notebook_doc.dart';
import '../../../../document/page_items.dart';
import '../../../../ink/vec2.dart';
import '../../../../recognition/htr_channel.dart';
import '../../../../recognition/spell_check.dart';
import '../../../../render/text_style.dart';
import '../../editor_controller.dart';
import '../../editor_integrations.dart';
import '../convert/convert_config.dart';
import '../convert/convert_layout.dart';
import '../convert/convert_providers.dart';
import '../convert/user_lexicon.dart';
import '../text_images/text_layer.dart';

/// Autocorrect, iPad style: words autocorrect changed when handwriting
/// became text are underlined ([TextLayerPainter]); a tap on one (pen or
/// finger) shows a bubble with the word as it was written. Tapping the
/// bubble puts it back (one undo step; a spelling fix taken back is learned
/// in "My words" so it is not corrected again), the tick keeps the
/// correction and removes the mark.
///
/// Spell check (v1.8.0, setting "Check spelling"): words of typed text that
/// may be misspelt get a wavy underline ([SpellChecker]); a tap shows
/// spellings to choose from and "Add to My words" (or "Ignore" for a real
/// word that may be a slip).
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
  // The word list loads in the background; until then nothing is marked.
  unawaited(_loadChecker(ref.read(htrRecognizerProvider)).then((checker) {
    if (checker != null) bubble.useChecker(checker);
  }));
}

Future<SpellChecker?> _loadChecker(HtrRecognizer recognizer) async {
  try {
    return SpellChecker(await recognizer.polisher());
  } catch (e) {
    debugPrint('NeatInk: spell check unavailable: $e');
    return null;
  }
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

/// A word of typed text marked as possibly misspelt, on a page.
class SpellingHit {
  const SpellingHit({
    required this.pageId,
    required this.itemId,
    required this.start,
    required this.word,
    required this.kind,
    required this.suggestions,
    required this.rect,
  });

  final String pageId;
  final String itemId;

  /// Where [word] starts in the box's text.
  final int start;
  final String word;
  final SpellMarkKind kind;

  /// Spellings to offer, best first (may be empty).
  final List<String> suggestions;

  /// The word's box in page points (its first line when it wraps).
  final Rect rect;
}

/// The words of [item] [checker] marks, without those autocorrect changed
/// (they have their own mark and bubble).
List<SpellMark> spellMarksOf(TextItem item, SpellChecker checker) {
  final marks = checker.marksFor(item.text);
  if (marks.isEmpty) return marks;
  final corrected = item.liveCorrections;
  return [
    for (final m in marks)
      if (!corrected.any((c) => c.start < m.end && m.start < c.end)) m,
  ];
}

/// The marked word under [point] on [texts] (page points), if any, with its
/// suggestions. The word's box is grown by [slop] points.
SpellingHit? spellingAt(String pageId, Iterable<TextItem> texts, Vec2 point, SpellChecker checker, {double slop = 4}) {
  final at = Offset(point.x, point.y);
  for (final item in texts) {
    if (!item.frame.inflate(slop).contains(point)) continue;
    final marks = spellMarksOf(item, checker);
    if (marks.isEmpty) continue;
    final painter = layoutTextItem(item);
    try {
      for (final m in marks) {
        final boxes = [
          for (final b in painter.getBoxesForSelection(TextSelection(baseOffset: m.start, extentOffset: m.end)))
            b.toRect().shift(Offset(item.x, item.y)),
        ];
        if (!boxes.any((b) => b.inflate(slop).contains(at))) continue;
        final word = item.text.substring(m.start, m.end);
        return SpellingHit(
          pageId: pageId,
          itemId: item.id,
          start: m.start,
          word: word,
          kind: m.kind,
          suggestions: checker.suggestionsFor(word, m.kind,
              startsSentence: SpellChecker.startsSentenceAt(item.text, m.start)),
          rect: boxes.first,
        );
      }
    } finally {
      painter.dispose();
    }
  }
  return null;
}

/// What the bubble shows, and its actions.
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
  SpellingHit? _spelling;
  Timer? _timer;
  bool _disposed = false;

  /// The corrected word the bubble is open for (null: closed or open for a
  /// misspelt word).
  CorrectionHit? get hit => _hit;

  /// The marked word the bubble is open for.
  SpellingHit? get spelling => _spelling;

  /// The spell checker, once the word list is loaded.
  SpellChecker? get checker => _checker;
  SpellChecker? _checker;

  /// Starts marking words with [checker] (the page text layer asks it on
  /// every paint while "Check spelling" is on).
  void useChecker(SpellChecker checker) {
    if (_disposed) return;
    _checker = checker;
    final layer = controller.extensions.textLayer;
    if (layer is TextLayerPainter) {
      layer.spellMarks = (item) => controller.settings.checkSpelling ? spellMarksOf(item, checker) : const [];
    }
    _repaintPages();
  }

  void _repaintPages() {
    if (!controller.isReady) return;
    for (final p in controller.doc.meta.pages) {
      controller.invalidatePageRender(p.id);
    }
  }

  /// Page tap handler: opens the bubble on a corrected or a marked word; a
  /// tap elsewhere while it is open only closes it (and leaves no dot).
  bool onTap(String pageId, Vec2 point) {
    if (!controller.isReady) return false;
    final settings = controller.settings;
    final slop = 4 / math.max(controller.viewport.scale, 0.25);
    final texts = controller.doc.page(pageId).texts;
    final found = settings.autocorrect ? correctionAt(pageId, texts, point, slop: slop) : null;
    final checker = _checker;
    final misspelt = found == null && settings.checkSpelling && checker != null
        ? spellingAt(pageId, texts, point, checker, slop: slop)
        : null;
    if (found == null && misspelt == null) {
      if (_hit == null && _spelling == null) return false;
      dismiss();
      return true;
    }
    _hookDoc();
    _hit = found;
    _spelling = misspelt;
    _timer?.cancel();
    _timer = Timer(visibleFor, dismiss);
    notifyListeners();
    return true;
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (_hit == null && _spelling == null) return;
    _hit = null;
    _spelling = null;
    notifyListeners();
  }

  /// Writes [replacement] in place of the marked word (one undo step).
  void applySpelling(String replacement) {
    final s = _spelling;
    final item = s == null ? null : controller.doc.page(s.pageId).textById(s.itemId);
    dismiss();
    if (s == null || item == null) return;
    final end = s.start + s.word.length;
    if (end > item.text.length || item.text.substring(s.start, end) != s.word) return;
    final after = _fitted(s.pageId, item, item.copyWith(text: item.text.replaceRange(s.start, end, replacement)));
    controller.execute(PageItemsCommand(s.pageId, label: 'Spelling', textChanges: [(item, after)]));
  }

  /// Adds the marked word to My words: it is no longer marked, here or
  /// anywhere, and the recogniser learns it.
  void addToMyWords() {
    final s = _spelling;
    dismiss();
    if (s == null) return;
    learner?.learnWord(s.word);
    _checker?.ignore(s.word);
    _repaintPages();
  }

  /// Leaves the marked word alone (until the notebook is closed).
  void ignoreSpelling() {
    final s = _spelling;
    dismiss();
    if (s == null) return;
    _checker?.ignore(s.word);
    _repaintPages();
  }

  /// [after] (an edit of [item]) re-measured; a one-line box grows to keep
  /// its text on one line (to the page margin).
  TextItem _fitted(String pageId, TextItem item, TextItem after) {
    final page = controller.doc.pageMeta(pageId);
    final wasOneLine = metrics.naturalWidth(item) <= item.width + 1e-6;
    if (page != null && wasOneLine) {
      final want = metrics.naturalWidth(after) + ConvertConfig.lineSlack;
      final room = page.width - ConvertConfig.rightMargin - item.x;
      if (want > item.width) after = after.copyWith(width: math.min(want, math.max(room, item.width)));
    }
    return after.copyWith(height: metrics.heightOf(after));
  }

  /// Puts the written word back.
  void restoreOriginal() {
    final hit = _hit;
    final item = hit == null ? null : _liveItem(hit);
    dismiss();
    if (hit == null || item == null || !hit.correction.holdsIn(item.text)) return;
    // A one-line box grows to keep the word on its line (to the page margin).
    final after = _fitted(hit.pageId, item, item.withOriginal(hit.correction));
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
    final s = _spelling;
    if (hit == null && s == null) return;
    if (!controller.isReady) return dismiss();
    if (hit != null) {
      final item = _liveItem(hit);
      if (item == null || !item.liveCorrections.contains(hit.correction)) dismiss();
    } else if (s != null) {
      final item = controller.doc.page(s.pageId).textById(s.itemId);
      final end = s.start + s.word.length;
      if (item == null || end > item.text.length || item.text.substring(s.start, end) != s.word) dismiss();
    }
  }

  @override
  void dispose() {
    _disposed = true;
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
          final spelling = bubble.spelling;
          final c = bubble.controller;
          final pageId = hit?.pageId ?? spelling?.pageId;
          final rect = hit?.rect ?? spelling?.rect;
          if (pageId == null || rect == null || !c.isReady) return const SizedBox.shrink();
          final index = c.viewport.layout.indexOfPage(pageId);
          if (index < 0) return const SizedBox.shrink();
          final topLeft = c.viewport.pageToLocal(index, Vec2(rect.left, rect.top));
          final bottomRight = c.viewport.pageToLocal(index, Vec2(rect.right, rect.bottom));
          final word = Rect.fromPoints(topLeft, bottomRight);
          return CustomSingleChildLayout(
            delegate: _BubbleLayout(word),
            child: hit != null
                ? _Bubble(
                    original: hit.correction.original,
                    onRestore: bubble.restoreOriginal,
                    onKeep: bubble.keep,
                  )
                : _SpellingBubble(
                    hit: spelling!,
                    onPick: bubble.applySpelling,
                    onAdd: bubble.addToMyWords,
                    onIgnore: bubble.ignoreSpelling,
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

/// The bubble above a marked word: the suggested spellings (tap one to use
/// it) and "Add to My words" for an unknown word or "Ignore" for a real word
/// that may be a slip.
class _SpellingBubble extends StatelessWidget {
  const _SpellingBubble({required this.hit, required this.onPick, required this.onAdd, required this.onIgnore});

  final SpellingHit hit;
  final ValueChanged<String> onPick;
  final VoidCallback onAdd;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onInverseSurface;
    final unknown = hit.kind == SpellMarkKind.unknown;
    Widget divider() => Container(width: 1, height: 22, color: fg.withValues(alpha: 0.3));
    return Material(
      key: const ValueKey('spelling-bubble'),
      elevation: 4,
      color: scheme.inverseSurface,
      borderRadius: BorderRadius.circular(20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hit.suggestions.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
              child: Text('No suggestions', style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 15)),
            ),
          for (var i = 0; i < hit.suggestions.length; i++) ...[
            if (i > 0) divider(),
            InkWell(
              key: ValueKey('spelling-suggestion-$i'),
              borderRadius: i == 0 ? const BorderRadius.horizontal(left: Radius.circular(20)) : null,
              onTap: () => onPick(hit.suggestions[i]),
              child: Padding(
                padding: EdgeInsets.fromLTRB(i == 0 ? 14 : 12, 10, 12, 10),
                child: Text(
                  hit.suggestions[i],
                  style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
          divider(),
          Tooltip(
            message: unknown ? 'Add to My words' : 'Ignore',
            child: InkWell(
              key: ValueKey(unknown ? 'spelling-add' : 'spelling-ignore'),
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
              onTap: unknown ? onAdd : onIgnore,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
                child: Icon(unknown ? Icons.bookmark_add_outlined : Icons.check, size: 18, color: fg),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
