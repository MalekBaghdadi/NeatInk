import 'package:uuid/uuid.dart';

import '../../../../document/commands.dart';
import '../../../../document/notebook_meta.dart';
import '../../../../document/page_content.dart';
import '../../../../document/paper.dart';
import '../../editor_controller.dart';

/// Page-level edits of the page navigator. Every edit is one undoable
/// command on the editor's command stack, so nothing is ever lost: a deleted
/// page keeps its ink inside the command until the undo history drops it.
class PageOps {
  PageOps(this.controller, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final EditorController controller;
  final Uuid _uuid;

  int get pageCount => controller.pageCount;

  bool _valid(int i) => controller.isReady && i >= 0 && i < pageCount;

  /// A page whose file could not be read is shown empty; touching it could
  /// overwrite the real ink on disk, so it is left alone.
  bool isLocked(int index) =>
      !_valid(index) ||
      !controller.isPageEditable(controller.doc.meta.pages[index].id);

  bool canDelete(int index) =>
      controller.canDeletePage && _valid(index) && !isLocked(index);

  bool canChangePaper(int index) =>
      _valid(index) && !controller.doc.meta.pages[index].isPdf;

  /// Inserts an empty page after [index] (at the start for -1) with the
  /// same size and paper as the page at [index]; never a PDF background.
  PageMeta? insertBlankAfter(int index) {
    if (!controller.isReady) return null;
    final pages = controller.doc.meta.pages;
    final like = _valid(index) ? pages[index] : null;
    final page = PageMeta(
      id: _uuid.v4(),
      width: like?.width ?? a4WidthPt,
      height: like?.height ?? a4HeightPt,
      paper: (like != null && !like.isPdf)
          ? like.paper
          : controller.doc.meta.defaultPaper,
    );
    controller.execute(InsertPageCommand(
        (index + 1).clamp(0, pages.length), page, PageContent(),
        label: 'Insert page'));
    return page;
  }

  /// Copies the page at [index] (ink, text, images, paper) right after it.
  PageMeta? duplicate(int index) {
    if (!_valid(index) || isLocked(index)) return null;
    final source = controller.doc.meta.pages[index];
    final content = controller.doc.page(source.id);
    final copy = source.copyWith(id: _uuid.v4());
    // Items get fresh ids; point data is shared (strokes are immutable).
    final dup = PageContent(
      strokes: [for (final s in content.strokes) s.copyWith(id: _uuid.v4())],
      texts: [for (final t in content.texts) t.copyWith(id: _uuid.v4())],
      images: [for (final i in content.images) i.copyWith(id: _uuid.v4())],
    );
    controller.execute(
        InsertPageCommand(index + 1, copy, dup, label: 'Duplicate page'));
    return copy;
  }

  /// Moves the page at [from] so it ends up at index [to].
  bool move(int from, int to) {
    if (!_valid(from) || !_valid(to) || from == to) return false;
    controller.execute(MovePageCommand(from, to));
    return true;
  }

  /// Deletes the page at [index]; undo brings it back with all its content.
  bool delete(int index) {
    if (!canDelete(index)) return false;
    controller.execute(DeletePageCommand(index));
    return true;
  }

  /// Changes the paper of the page at [index].
  bool setPaper(int index, Paper paper) {
    if (!canChangePaper(index)) return false;
    final before = controller.doc.meta.pages[index];
    if (before.paper == paper) return false;
    controller.execute(
        UpdatePageMetaCommand(before, before.copyWith(paper: paper)));
    return true;
  }

  /// Changes the paper of every non-PDF page in one undo step.
  bool setPaperAll(Paper paper) {
    if (!controller.isReady) return false;
    final cmds = <EditCommand>[
      for (final p in controller.doc.meta.pages)
        if (!p.isPdf && p.paper != paper)
          UpdatePageMetaCommand(p, p.copyWith(paper: paper)),
    ];
    if (cmds.isEmpty) return false;
    controller.execute(CompositeCommand('Change paper', cmds));
    return true;
  }

  /// Scrolls to page [index] (clamped).
  void goTo(int index) {
    if (pageCount == 0) return;
    controller.scrollToPage(index.clamp(0, pageCount - 1));
  }

  void next() => goTo(controller.currentPageIndex + 1);
  void previous() => goTo(controller.currentPageIndex - 1);
}
