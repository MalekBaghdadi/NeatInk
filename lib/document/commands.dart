import '../ink/stroke.dart';
import 'notebook_doc.dart';
import 'notebook_meta.dart';
import 'page_content.dart';
import 'page_items.dart';

/// A reversible edit to a [NotebookDoc].
///
/// The UI never mutates strokes or items directly; it builds a command and
/// runs it through a [CommandStack]. Commands must be deterministic:
/// `apply` then `revert` restores the document exactly (including list order).
abstract class EditCommand {
  /// Short user-facing name ("Pen stroke", "Tidy", "Move selection").
  String get label;

  /// Performs the edit and returns what changed.
  DocChange apply(NotebookDoc doc);

  /// Undoes [apply] exactly and returns what changed.
  DocChange revert(NotebookDoc doc);
}

/// Undo/redo history for one notebook.
class CommandStack {
  CommandStack({this.capacity = 200});

  /// Maximum undo steps kept (the spec requires at least 100).
  final int capacity;

  final List<EditCommand> _undo = [];
  final List<EditCommand> _redo = [];

  /// Called after every execute/undo/redo (e.g. to refresh toolbar buttons).
  void Function()? onChanged;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.label;
  int get undoDepth => _undo.length;

  /// The most recent command, if any (e.g. to check what undo would revert).
  EditCommand? get lastCommand => _undo.isEmpty ? null : _undo.last;

  /// Applies [command], records it and notifies the document's listeners.
  DocChange execute(EditCommand command, NotebookDoc doc) {
    final change = command.apply(doc);
    _undo.add(command);
    if (_undo.length > capacity) _undo.removeAt(0);
    _redo.clear();
    doc.notify(change);
    onChanged?.call();
    return change;
  }

  DocChange undo(NotebookDoc doc) {
    if (_undo.isEmpty) return DocChange.none;
    final c = _undo.removeLast();
    final change = c.revert(doc);
    _redo.add(c);
    doc.notify(change);
    onChanged?.call();
    return change;
  }

  DocChange redo(NotebookDoc doc) {
    if (_redo.isEmpty) return DocChange.none;
    final c = _redo.removeLast();
    final change = c.apply(doc);
    _undo.add(c);
    doc.notify(change);
    onChanged?.call();
    return change;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
    onChanged?.call();
  }
}

/// Runs several commands as one undo step.
class CompositeCommand extends EditCommand {
  CompositeCommand(this.label, this.commands);

  @override
  final String label;
  final List<EditCommand> commands;

  @override
  DocChange apply(NotebookDoc doc) {
    var change = DocChange.none;
    for (final c in commands) {
      change = change.merge(c.apply(doc));
    }
    return change;
  }

  @override
  DocChange revert(NotebookDoc doc) {
    var change = DocChange.none;
    for (final c in commands.reversed) {
      change = change.merge(c.revert(doc));
    }
    return change;
  }
}

// ---------------------------------------------------------------------------
// Strokes

/// Appends strokes to a page (pen strokes, shapes, pasted strokes).
class AddStrokesCommand extends EditCommand {
  AddStrokesCommand(this.pageId, this.strokes, {this.label = 'Pen stroke'});

  final String pageId;
  final List<Stroke> strokes;
  @override
  final String label;

  @override
  DocChange apply(NotebookDoc doc) {
    final page = doc.page(pageId);
    page.strokes.addAll(strokes);
    page.touch();
    return DocChange(pageIds: {pageId});
  }

  @override
  DocChange revert(NotebookDoc doc) {
    final page = doc.page(pageId);
    final ids = {for (final s in strokes) s.id};
    page.strokes.removeWhere((s) => ids.contains(s.id));
    page.touch();
    return DocChange(pageIds: {pageId});
  }
}

/// Removes whole strokes (stroke eraser, delete selection). Remembers their
/// positions so undo puts them back in the same paint order.
class RemoveStrokesCommand extends EditCommand {
  RemoveStrokesCommand(this.pageId, Set<String> strokeIds,
      {this.label = 'Erase'})
      : strokeIds = Set.unmodifiable(strokeIds);

  final String pageId;
  final Set<String> strokeIds;
  @override
  final String label;

  /// (index, stroke) pairs in ascending index order, captured by [apply].
  final List<(int, Stroke)> _removed = [];

  @override
  DocChange apply(NotebookDoc doc) {
    final page = doc.page(pageId);
    _removed.clear();
    for (var i = 0; i < page.strokes.length; i++) {
      if (strokeIds.contains(page.strokes[i].id)) {
        _removed.add((i, page.strokes[i]));
      }
    }
    page.strokes.removeWhere((s) => strokeIds.contains(s.id));
    page.touch();
    return DocChange(pageIds: {pageId});
  }

  @override
  DocChange revert(NotebookDoc doc) {
    final page = doc.page(pageId);
    for (final (index, stroke) in _removed) {
      page.strokes.insert(index.clamp(0, page.strokes.length), stroke);
    }
    page.touch();
    return DocChange(pageIds: {pageId});
  }
}

/// Replaces strokes in place, matched by id (tidy, recolor, lasso transform,
/// restore original, shape snap). [before] and [after] must contain the same
/// ids.
class ReplaceStrokesCommand extends EditCommand {
  ReplaceStrokesCommand(this.pageId, this.before, this.after,
      {required this.label})
      : assert(before.length == after.length);

  final String pageId;
  final List<Stroke> before;
  final List<Stroke> after;
  @override
  final String label;

  @override
  DocChange apply(NotebookDoc doc) => _swap(doc, after);

  @override
  DocChange revert(NotebookDoc doc) => _swap(doc, before);

  DocChange _swap(NotebookDoc doc, List<Stroke> replacements) {
    final page = doc.page(pageId);
    final byId = {for (final s in replacements) s.id: s};
    for (var i = 0; i < page.strokes.length; i++) {
      final r = byId[page.strokes[i].id];
      if (r != null) page.strokes[i] = r;
    }
    page.touch();
    return DocChange(pageIds: {pageId});
  }
}

/// Replaces some strokes with a different set of strokes at the same paint
/// position (pixel eraser splitting a stroke into pieces).
class SpliceStrokesCommand extends EditCommand {
  SpliceStrokesCommand(this.pageId, this.replacements, {this.label = 'Erase'});

  final String pageId;

  /// Original stroke id → the pieces that replace it (may be empty).
  final Map<String, List<Stroke>> replacements;
  @override
  final String label;

  final List<(int, Stroke)> _originals = [];

  @override
  DocChange apply(NotebookDoc doc) {
    final page = doc.page(pageId);
    _originals.clear();
    final out = <Stroke>[];
    for (var i = 0; i < page.strokes.length; i++) {
      final s = page.strokes[i];
      final pieces = replacements[s.id];
      if (pieces == null) {
        out.add(s);
      } else {
        _originals.add((i, s));
        out.addAll(pieces);
      }
    }
    page.strokes
      ..clear()
      ..addAll(out);
    page.touch();
    return DocChange(pageIds: {pageId});
  }

  @override
  DocChange revert(NotebookDoc doc) {
    final page = doc.page(pageId);
    final pieceIds = {
      for (final pieces in replacements.values)
        for (final p in pieces) p.id,
    };
    page.strokes.removeWhere((s) => pieceIds.contains(s.id));
    for (final (index, stroke) in _originals) {
      page.strokes.insert(index.clamp(0, page.strokes.length), stroke);
    }
    page.touch();
    return DocChange(pageIds: {pageId});
  }
}

// ---------------------------------------------------------------------------
// Text boxes and images

/// Adds, updates or removes text boxes and images on one page. Use
/// `before == null` to add and `after == null` to remove.
class PageItemsCommand extends EditCommand {
  PageItemsCommand(
    this.pageId, {
    required this.label,
    this.textChanges = const [],
    this.imageChanges = const [],
  });

  final String pageId;
  @override
  final String label;
  final List<(TextItem?, TextItem?)> textChanges;
  final List<(ImageItem?, ImageItem?)> imageChanges;

  final Map<String, int> _textIndex = {};
  final Map<String, int> _imageIndex = {};

  @override
  DocChange apply(NotebookDoc doc) {
    final page = doc.page(pageId);
    for (final (before, after) in textChanges) {
      _applyOne<TextItem>(page.texts, before, after, (t) => t.id, _textIndex);
    }
    for (final (before, after) in imageChanges) {
      _applyOne<ImageItem>(
          page.images, before, after, (i) => i.id, _imageIndex);
    }
    page.touch();
    return DocChange(pageIds: {pageId});
  }

  @override
  DocChange revert(NotebookDoc doc) {
    final page = doc.page(pageId);
    for (final (before, after) in imageChanges.reversed) {
      _applyOne<ImageItem>(
          page.images, after, before, (i) => i.id, _imageIndex);
    }
    for (final (before, after) in textChanges.reversed) {
      _applyOne<TextItem>(page.texts, after, before, (t) => t.id, _textIndex);
    }
    page.touch();
    return DocChange(pageIds: {pageId});
  }

  static void _applyOne<T>(List<T> list, T? from, T? to, String Function(T) id,
      Map<String, int> indexMemo) {
    if (from == null && to != null) {
      // Add (or re-add on revert of a removal) at the remembered position.
      final at = indexMemo[id(to)] ?? list.length;
      list.insert(at.clamp(0, list.length), to);
    } else if (from != null && to == null) {
      final i = list.indexWhere((e) => id(e) == id(from));
      if (i >= 0) {
        indexMemo[id(from)] = i;
        list.removeAt(i);
      }
    } else if (from != null && to != null) {
      final i = list.indexWhere((e) => id(e) == id(from));
      if (i >= 0) list[i] = to;
    }
  }
}

/// Replaces everything on one page with [after] (e.g. all of it moved);
/// undo puts [before] back. The page object stays the same, so views and
/// caches keep following it.
class ReplacePageContentCommand extends EditCommand {
  ReplacePageContentCommand(this.pageId, PageContent before, PageContent after,
      {required this.label})
      : _before = _snapshot(before),
        _after = _snapshot(after);

  final String pageId;
  @override
  final String label;
  final PageContent _before;
  final PageContent _after;

  static PageContent _snapshot(PageContent c) => PageContent(
      strokes: List.of(c.strokes), texts: List.of(c.texts), images: List.of(c.images));

  @override
  DocChange apply(NotebookDoc doc) => _set(doc, _after);

  @override
  DocChange revert(NotebookDoc doc) => _set(doc, _before);

  DocChange _set(NotebookDoc doc, PageContent from) {
    final page = doc.page(pageId);
    page.strokes
      ..clear()
      ..addAll(from.strokes);
    page.texts
      ..clear()
      ..addAll(from.texts);
    page.images
      ..clear()
      ..addAll(from.images);
    page.touch();
    return DocChange(pageIds: {pageId});
  }
}

// ---------------------------------------------------------------------------
// Pages

/// Inserts a page (new, duplicated or restored) at [index].
class InsertPageCommand extends EditCommand {
  InsertPageCommand(this.index, this.page, this.content,
      {this.label = 'Add page'});

  final int index;
  final PageMeta page;
  final PageContent content;
  @override
  final String label;

  @override
  DocChange apply(NotebookDoc doc) {
    final pages = List.of(doc.meta.pages)
      ..insert(index.clamp(0, doc.meta.pages.length), page);
    doc.meta = doc.meta.copyWith(pages: pages);
    doc.pages[page.id] = content;
    content.touch();
    return DocChange(pageIds: {page.id}, meta: true);
  }

  @override
  DocChange revert(NotebookDoc doc) {
    doc.meta = doc.meta.copyWith(
        pages: [for (final p in doc.meta.pages) if (p.id != page.id) p]);
    doc.pages.remove(page.id);
    return const DocChange(meta: true);
  }
}

/// Deletes the page at [index]. Its content stays in memory for undo; the
/// page file is removed from disk on the next save.
class DeletePageCommand extends EditCommand {
  DeletePageCommand(this.index, {this.label = 'Delete page'});

  final int index;
  @override
  final String label;

  PageMeta? _page;
  PageContent? _content;

  @override
  DocChange apply(NotebookDoc doc) {
    final pages = List.of(doc.meta.pages);
    _page = pages.removeAt(index);
    _content = doc.pages.remove(_page!.id);
    doc.meta = doc.meta.copyWith(pages: pages);
    return const DocChange(meta: true);
  }

  @override
  DocChange revert(NotebookDoc doc) {
    final pages = List.of(doc.meta.pages)..insert(index, _page!);
    doc.meta = doc.meta.copyWith(pages: pages);
    final content = _content ?? PageContent();
    doc.pages[_page!.id] = content;
    content.touch();
    return DocChange(pageIds: {_page!.id}, meta: true);
  }
}

/// Moves a page from [from] to [to] (indices in the list before the move).
class MovePageCommand extends EditCommand {
  MovePageCommand(this.from, this.to, {this.label = 'Move page'});

  final int from;
  final int to;
  @override
  final String label;

  @override
  DocChange apply(NotebookDoc doc) => _move(doc, from, to);

  @override
  DocChange revert(NotebookDoc doc) => _move(doc, to, from);

  static DocChange _move(NotebookDoc doc, int a, int b) {
    final pages = List.of(doc.meta.pages);
    final p = pages.removeAt(a);
    pages.insert(b.clamp(0, pages.length), p);
    doc.meta = doc.meta.copyWith(pages: pages);
    return const DocChange(meta: true);
  }
}

/// Replaces one page's metadata (e.g. change its paper).
class UpdatePageMetaCommand extends EditCommand {
  UpdatePageMetaCommand(this.before, this.after, {this.label = 'Change paper'})
      : assert(before.id == after.id);

  final PageMeta before;
  final PageMeta after;
  @override
  final String label;

  @override
  DocChange apply(NotebookDoc doc) => _set(doc, after);

  @override
  DocChange revert(NotebookDoc doc) => _set(doc, before);

  DocChange _set(NotebookDoc doc, PageMeta m) {
    doc.meta = doc.meta.copyWith(
        pages: [for (final p in doc.meta.pages) p.id == m.id ? m : p]);
    // The page content is unchanged, but its background must repaint.
    return DocChange(pageIds: {m.id}, meta: true);
  }
}
