import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../../../../document/commands.dart';
import '../../../../document/page_items.dart';
import '../../../../ink/ink_rect.dart';
import '../../../../ink/vec2.dart';
import '../../../../render/text_style.dart';
import '../../editor_controller.dart';
import '../../editor_extensions.dart';
import '../../editor_tool.dart';
import '../../tools/pixel_eraser.dart';
import '../../tools/scribble.dart' show withoutWords;
import '../../tools/spatial_index.dart';
import '../../tools/stroke_eraser.dart';
import '../../tools/text_eraser.dart';
import 'live_edit.dart';

/// Where the eraser circle is drawn: viewport-local pixels plus its radius
/// in page points.
class EraserCursor {
  const EraserCursor(this.position, this.radiusPt);

  final Offset position;
  final double radiusPt;
}

/// The eraser tool, also used by the pen's eraser end / barrel button.
///
/// One pointer erases at a time. Whole-stroke mode removes every stroke the
/// eraser circle touches; partial mode cuts them. Both also remove every
/// word of typed text they touch (v1.8.0; an emptied box goes). Both sweep
/// the segment between pointer samples, so a fast flick erases everything
/// it crossed.
/// The page shows the erasing live ([LiveEdit]) and the whole drag becomes a
/// single undo step on pen-up; a cancelled drag leaves the page untouched.
class EraserHandler extends CanvasToolHandler {
  EraserHandler(this.controller, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid(),
        _live = LiveEdit(controller);

  /// How long the hover cursor stays after the last pen event.
  static const Duration cursorLinger = Duration(milliseconds: 900);

  final EditorController controller;
  final Uuid _uuid;
  final LiveEdit _live;

  /// The eraser circle for the overlay; null hides it.
  final ValueNotifier<EraserCursor?> cursor = ValueNotifier(null);

  int? _pointer;
  String? _pageId;
  StrokeEraseSession? _strokes;
  PixelEraseSession? _pixels;
  Vec2 _last = Vec2.zero;
  Timer? _hideTimer;

  /// The page's text boxes when the drag started, their words (laid out
  /// once, when the eraser first comes near) and the words touched so far.
  Map<String, TextItem> _texts = const {};
  final Map<String, List<TextWord>> _words = {};
  final Map<String, Set<int>> _erasedWords = {};

  double get _radiusPt => controller.toolPrefs.eraser.size / 2;

  @override
  bool onPointerDown(CanvasPointerEvent e) {
    final hit = e.hit;
    if (_pointer != null || hit == null) return false;
    if (!controller.isPageEditable(hit.pageId)) return false;
    final content = controller.doc.page(hit.pageId);
    final index = SpatialIndex.forPage(content);
    _pointer = e.pointer;
    _pageId = hit.pageId;
    _last = hit.point;
    _texts = {for (final t in content.texts) t.id: t};
    _words.clear();
    _erasedWords.clear();
    if (controller.toolPrefs.eraser.mode == EraserMode.pixel) {
      _pixels = PixelEraseSession(index: index, newId: _uuid.v4);
    } else {
      _strokes = StrokeEraseSession(index);
    }
    _hideTimer?.cancel();
    _showCursor(e);
    _sweep(hit.point, hit.point);
    return true;
  }

  @override
  void onPointerMove(CanvasPointerEvent e) {
    if (e.pointer != _pointer) return;
    _showCursor(e);
    final p = _pagePoint(e);
    if (p == null) {
      _cancel();
      return;
    }
    _sweep(_last, p);
    _last = p;
  }

  @override
  void onPointerUp(CanvasPointerEvent e) {
    if (e.pointer != _pointer) return;
    final p = _pagePoint(e);
    if (p != null) _sweep(_last, p);
    _live.commit();
    _reset();
    _showCursor(e);
    _scheduleHide();
  }

  @override
  void onPointerCancel(CanvasPointerEvent e) {
    if (e.pointer != _pointer) return;
    _cancel();
  }

  @override
  void onHover(CanvasPointerEvent e) {
    if (_pointer != null) return;
    _showCursor(e);
    _scheduleHide();
  }

  @override
  void commitPending() {
    if (_pointer == null) return;
    _live.commit();
    _reset();
  }

  @override
  void onDeactivated() {
    commitPending();
    _hideCursor();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    if (_pointer != null) _cancel();
    cursor.dispose();
  }

  // ---------------------------------------------------------------------------

  /// The pointer in page points of the page the gesture started on.
  Vec2? _pagePoint(CanvasPointerEvent e) {
    final index = controller.viewport.layout.indexOfPage(_pageId!);
    if (index < 0) return null;
    return controller.viewport.localToPage(e.localPosition, index);
  }

  void _sweep(Vec2 from, Vec2 to) {
    final pageId = _pageId!;
    final radius = _radiusPt;
    final strokes = _strokes;
    final pixels = _pixels;
    var changed = false;
    if (strokes != null) {
      changed = strokes.sweep(from, to, radius).isNotEmpty;
    } else if (pixels != null) {
      changed = pixels.sweep(from, to, radius);
    }
    if (_sweepTexts(from, to, radius)) changed = true;
    if (!changed) return;
    final ink = strokes != null
        ? (strokes.erasedIds.isEmpty ? null : RemoveStrokesCommand(pageId, strokes.erasedIds, label: 'Erase'))
        : (pixels!.replacements.isEmpty ? null : SpliceStrokesCommand(pageId, pixels.replacements, label: 'Erase'));
    final texts = _textChanges();
    _live.show(
        pageId,
        texts.isEmpty
            ? ink
            : CompositeCommand('Erase', [
                ?ink,
                PageItemsCommand(pageId, label: 'Erase', textChanges: texts),
              ]));
  }

  /// Adds the typed words the sweep touches; true when there are new ones.
  bool _sweepTexts(Vec2 from, Vec2 to, double radius) {
    var any = false;
    final reach = InkRect.fromPoints([from, to]).inflate(radius);
    for (final t in _texts.values) {
      if (!t.frame.overlaps(reach)) continue;
      final words = _words[t.id] ??= textWordsOf(t);
      final erased = _erasedWords.putIfAbsent(t.id, () => <int>{});
      for (var i = 0; i < words.length; i++) {
        if (erased.contains(i)) continue;
        if (words[i].boxes.any((b) => sweepTouchesRect(from, to, radius, b))) {
          erased.add(i);
          any = true;
        }
      }
    }
    return any;
  }

  /// The boxes as they are without the touched words (null: emptied).
  List<(TextItem?, TextItem?)> _textChanges() => [
        for (final e in _erasedWords.entries)
          if (e.value.isNotEmpty) _withoutErased(_texts[e.key]!, _words[e.key]!, e.value),
      ];

  static (TextItem?, TextItem?) _withoutErased(TextItem t, List<TextWord> words, Set<int> erased) {
    final text = withoutWords(t.text, [for (final i in erased) (words[i].start, words[i].end)]);
    if (text.trim().isEmpty) return (t, null);
    final next = t.copyWith(text: text);
    final painter = layoutTextItem(next);
    try {
      return (t, next.copyWith(height: painter.height));
    } finally {
      painter.dispose();
    }
  }

  void _cancel() {
    _live.discard();
    _reset();
    _scheduleHide();
  }

  void _reset() {
    _pointer = null;
    _pageId = null;
    _strokes = null;
    _pixels = null;
  }

  void _showCursor(CanvasPointerEvent e) =>
      cursor.value = EraserCursor(e.localPosition, _radiusPt);

  void _hideCursor() {
    _hideTimer?.cancel();
    cursor.value = null;
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(cursorLinger, _hideCursor);
  }
}
