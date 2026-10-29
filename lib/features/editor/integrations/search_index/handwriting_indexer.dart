import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../ink/stroke.dart';
import '../../../../recognition/htr_channel.dart';
import '../../editor_controller.dart';
import '../convert/convert_plan.dart';

// Searching handwriting (v1.7.0): while the editor sits idle, the pages whose
// writing changed are read with the same reader as Convert, and what it read
// is stored in the notebook's `search.json` (`PageSearchText.ink`), so the
// library search finds handwritten words. Only the open notebook is read,
// one page at a time; any pen stroke, scroll or edit stops it until the
// editor is idle again. Nothing on the page changes.

/// Which pen strokes a page's handwriting text was read from: their count
/// and a hash of their ids (FNV-1a, 32 bits). Empty when the page has none.
String handwritingKeyOf(Iterable<Stroke> strokes) {
  final ids = [
    for (final s in strokes)
      if (s.tool == StrokeTool.pen && s.shape == null) s.id,
  ]..sort();
  if (ids.isEmpty) return '';
  var h = 0x811c9dc5;
  for (final id in ids) {
    for (final c in '$id,'.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
  }
  return '${ids.length}-${h.toRadixString(16)}';
}

/// Reads the handwriting of [controller]'s notebook in the background for
/// search (see the comment above).
class HandwritingIndexer {
  HandwritingIndexer({
    required this.controller,
    required this.recognizer,
    this.idle = const Duration(seconds: 8),
  }) {
    _started = controller.strokeEvents.started.listen((_) => _poke());
    controller.addListener(_poke);
    controller.viewport.addListener(_poke);
    _poke();
  }

  final EditorController controller;
  final HtrRecognizer recognizer;

  /// How long the editor must be left alone before reading starts.
  final Duration idle;

  late final StreamSubscription<Object?> _started;
  Timer? _timer;
  ConvertCancelToken? _token;
  Map<String, String>? _keys;
  bool _running = false;
  bool _disposed = false;

  /// True while a page is being read.
  @visibleForTesting
  bool get running => _running;

  /// Something happened: stop reading, and start again once it is quiet.
  void _poke() {
    if (_disposed) return;
    _token?.cancel();
    _timer?.cancel();
    _timer = Timer(idle, () => unawaited(_run()));
  }

  Future<void> _run() async {
    if (_disposed || _running || !controller.isReady || !controller.settings.searchHandwriting) return;
    _running = true;
    final token = _token = ConvertCancelToken();
    try {
      final keys = _keys ??= await controller.repository.handwritingKeys(controller.notebookId);
      // The page in view first, then the rest in order.
      final pages = controller.doc.meta.pages;
      final current = controller.currentPageIndex;
      final order = [
        if (current >= 0 && current < pages.length) current,
        for (var i = 0; i < pages.length; i++)
          if (i != current) i,
      ];
      for (final i in order) {
        if (token.isCancelled || _disposed || !controller.isReady) return;
        if (i >= controller.doc.meta.pages.length) return;
        final page = controller.doc.meta.pages[i];
        if (!controller.isPageEditable(page.id)) continue;
        final strokes = List.of(controller.doc.page(page.id).strokes);
        final key = handwritingKeyOf(strokes);
        if ((keys[page.id] ?? '') == key) continue;
        var text = '';
        if (key.isNotEmpty) {
          final plans = await recognizePages(
            [PageStrokes(pageId: page.id, pageIndex: i, strokes: strokes)],
            recognizer,
            cancel: token,
            autoFix: true,
          );
          text = [
            for (final plan in plans)
              for (final line in plan.lines)
                if (line.text.trim().isNotEmpty) line.text.trim(),
          ].join('\n');
        }
        if (token.isCancelled || _disposed) return;
        await controller.repository.saveHandwritingText(controller.notebookId, page.id, text: text, key: key);
        keys[page.id] = key;
      }
    } on ConvertCancelled {
      // Something happened meanwhile: the page is read again later.
    } catch (e) {
      debugPrint('NeatInk: reading handwriting for search failed: $e');
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    _token?.cancel();
    _timer?.cancel();
    unawaited(_started.cancel());
    controller.removeListener(_poke);
    controller.viewport.removeListener(_poke);
  }
}
