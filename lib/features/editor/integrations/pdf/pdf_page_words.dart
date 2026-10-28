import 'dart:async';

import '../../../../pdf/pdf_engine.dart' show PdfWordBox;
import '../../editor_controller.dart';
import '../../editor_extensions.dart';

/// The printed words of the open notebook's PDF pages, in page points (the
/// PDF page sits between the page's margins). Loaded once per page in the
/// background; [wordsOn] is null until then.
class PdfPageWords implements PageTextWords {
  PdfPageWords(this.controller, {required this.words});

  final EditorController controller;
  final Future<List<PdfWordBox>> Function(String notebookId, int pageIndex) words;

  // Per page: the left margin the words were placed with, and the words.
  final Map<String, (double, List<PdfWordBox>)> _ready = {};
  final Set<String> _loading = {};

  double? _offsetOf(String pageId) {
    if (!controller.isReady) return null;
    final page = controller.doc.pageMeta(pageId);
    return page == null || page.pdfPageIndex == null ? null : page.contentLeft;
  }

  @override
  List<PdfWordBox>? wordsOn(String pageId) {
    final hit = _ready[pageId];
    // Stale after the margins changed.
    return hit == null || hit.$1 != _offsetOf(pageId) ? null : hit.$2;
  }

  @override
  void prepare(String pageId) {
    if (wordsOn(pageId) != null || !_loading.add(pageId)) return;
    final dx = _offsetOf(pageId);
    final index = controller.isReady ? controller.doc.pageMeta(pageId)?.pdfPageIndex : null;
    if (dx == null || index == null) {
      _loading.remove(pageId);
      return;
    }
    unawaited(words(controller.notebookId, index).then((list) {
      _ready[pageId] = (dx, [
        for (final w in list) (left: w.left + dx, top: w.top, right: w.right + dx, bottom: w.bottom),
      ]);
    }).whenComplete(() => _loading.remove(pageId)));
  }
}
