import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../document/commands.dart';
import '../../../../document/page_items.dart';
import '../../../../ink/vec2.dart';
import '../../../../render/text_style.dart';
import '../../editor_controller.dart';
import 'frame_geometry.dart';

/// One text box being edited: the committed item it started from (null for a
/// new box), the draft with the live frame and formatting, and the text
/// field's controller and focus node.
class TextEditSession {
  TextEditSession({
    required this.pageId,
    required this.original,
    required this.draft,
    required this.wantFocus,
  }) : input = TextEditingController(text: draft.text);

  final String pageId;
  final TextItem? original;

  /// Frame and formatting as they are now; [TextItem.text] is only synced
  /// from [input] when the text changes or on commit.
  TextItem draft;
  final TextEditingController input;
  final FocusNode focus = FocusNode(debugLabel: 'text box');

  /// Focus the field (and so show the keyboard) when it appears.
  bool wantFocus;

  bool get isNew => original == null;

  void dispose() {
    input.dispose();
    focus.dispose();
  }
}

/// The text box state shared by the text tool, its page overlay and the
/// formatting bar. At most one box is edited at a time; it is committed as a
/// single undo step when editing ends.
class TextBoxEditor extends ChangeNotifier {
  TextBoxEditor(this.controller, {Uuid? uuid}) : _uuid = uuid ?? const Uuid() {
    controller.addListener(_onControllerChanged);
  }

  final EditorController controller;
  final Uuid _uuid;

  /// Formatting for new boxes (also updated by formatting changes made while
  /// editing). Only the style fields are used.
  TextItem format = const TextItem(
    id: '',
    x: 0,
    y: 0,
    width: 0,
    height: 0,
    fontSize: 16,
  );

  TextEditSession? _session;
  TextEditSession? get session => _session;

  static const double defaultBoxWidth = 220;
  static const double pageMargin = 24;

  /// The id of the box being edited on [pageId] (hidden from the text
  /// layer), if any.
  String? editingIdOn(String pageId) {
    final s = _session;
    return s != null && s.pageId == pageId ? s.draft.id : null;
  }

  /// Height of [item]'s text laid out like on the page; one line at least.
  static double measureHeight(TextItem item) {
    final painter = layoutTextItem(
        item.copyWith(text: item.text.isEmpty ? ' ' : item.text));
    try {
      return painter.height;
    } finally {
      painter.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // Starting and ending an edit

  /// Starts editing [item] (an existing box, or a new one when [isNew]),
  /// committing any other box first.
  void begin(String pageId, TextItem item,
      {bool isNew = false, bool focus = true}) {
    commit();
    final fixed = item.copyWith(height: measureHeight(item));
    _session = TextEditSession(
      pageId: pageId,
      original: isNew ? null : item,
      draft: fixed,
      wantFocus: focus,
    );
    controller.invalidatePageRender(pageId);
    notifyListeners();
  }

  /// A new empty box at [p] on [pageId] with the current formatting.
  void createAt(String pageId, Vec2 p) {
    final page = controller.doc.pageMeta(pageId);
    if (page == null || !controller.isPageEditable(pageId)) return;
    final width = math.min(defaultBoxWidth, page.width - 2 * pageMargin);
    final x = p.x
        .clamp(pageMargin, math.max(pageMargin, page.width - pageMargin - width))
        .toDouble();
    final y = (p.y - format.fontSize * 0.6)
        .clamp(0.0, math.max(0.0, page.height - pageMargin))
        .toDouble();
    begin(
      pageId,
      format.copyWith(
          id: _uuid.v4(), x: x, y: y, width: width, text: '', height: 0),
      isNew: true,
    );
  }

  /// A new box in the upper part of the visible part of the page in view.
  void createInView() {
    final index = controller.currentPageIndex;
    final page = controller.currentPageMeta;
    if (page == null) return;
    var y = page.height * 0.2;
    if (controller.viewport.hasSize) {
      // Page y at the top edge of the view, plus a little way down.
      final pageTop = controller.viewport.localToPage(Offset.zero, index).y;
      y = (pageTop + 80 / controller.viewport.scale)
          .clamp(0.0, page.height - pageMargin);
    }
    createAt(page.id, Vec2((page.width - defaultBoxWidth) / 2, y));
  }

  /// A tap (pen, mouse or finger) at [p] on [pageId] with the text tool:
  /// edits the box under it, or ends the current edit, or starts a new box.
  void tap(String pageId, Vec2 p, double scale) {
    if (!controller.isPageEditable(pageId)) return;
    final s = _session;
    if (s != null &&
        s.pageId == pageId &&
        textZone(s.draft.frame, p, scale) != TextZone.none) {
      return;
    }
    final target =
        hitTextItem(controller.doc.page(pageId).texts, p, slop: 4 / scale);
    if (target != null) {
      begin(pageId, target);
    } else if (s != null) {
      commit();
    } else {
      createAt(pageId, p);
    }
  }

  /// Ends the edit and stores the result as one undo step: new box added,
  /// changed box replaced, emptied box removed. Returns true when the
  /// document changed.
  bool commit() {
    final s = _session;
    if (s == null) return false;
    _session = null;
    final result = _finish(s);
    _release(s);
    return result;
  }

  bool _finish(TextEditSession s) {
    final original = s.original;
    final text = s.input.text;
    final withText = s.draft.copyWith(text: text);
    final item = withText.copyWith(height: measureHeight(withText));
    if (!controller.isPageEditable(s.pageId)) return false;
    final empty = text.trim().isEmpty;
    PageItemsCommand? command;
    if (original == null) {
      if (!empty) {
        command = PageItemsCommand(s.pageId,
            label: 'Add text', textChanges: [(null, item)]);
      }
    } else if (empty) {
      command = PageItemsCommand(s.pageId,
          label: 'Delete text', textChanges: [(original, null)]);
    } else if (!sameText(original, item)) {
      command = PageItemsCommand(s.pageId,
          label: _labelFor(original, item), textChanges: [(original, item)]);
    }
    if (command == null) return false;
    controller.execute(command);
    return true;
  }

  /// Deletes the box being edited (an existing one is removed undoably).
  void deleteSession() {
    final s = _session;
    if (s == null) return;
    _session = null;
    final original = s.original;
    if (original != null && controller.isPageEditable(s.pageId)) {
      controller.execute(PageItemsCommand(s.pageId,
          label: 'Delete text', textChanges: [(original, null)]));
    }
    _release(s);
  }

  /// Drops the edit without storing it (the box was changed elsewhere, e.g.
  /// by undo).
  void cancel() {
    final s = _session;
    if (s == null) return;
    _session = null;
    _release(s);
  }

  void _release(TextEditSession s) {
    controller.invalidatePageRender(s.pageId);
    notifyListeners();
    // The text field may still be in the tree for this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => s.dispose());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  static String _labelFor(TextItem a, TextItem b) {
    if (a.text != b.text) return 'Edit text';
    final moved = a.x != b.x || a.y != b.y;
    final resized = a.width != b.width;
    if (moved && !resized && _sameStyle(a, b)) return 'Move text';
    if (resized && !moved && _sameStyle(a, b)) return 'Resize text';
    return 'Format text';
  }

  static bool _sameStyle(TextItem a, TextItem b) =>
      a.fontSize == b.fontSize &&
      a.color == b.color &&
      a.bold == b.bold &&
      a.italic == b.italic &&
      a.underline == b.underline &&
      a.align == b.align &&
      a.font == b.font &&
      a.background == b.background &&
      a.lineSpacing == b.lineSpacing;

  /// Whether two text items are identical in every field.
  static bool sameText(TextItem a, TextItem b) =>
      a.id == b.id &&
      a.x == b.x &&
      a.y == b.y &&
      a.width == b.width &&
      a.height == b.height &&
      a.text == b.text &&
      _sameStyle(a, b);

  // ---------------------------------------------------------------------------
  // Live changes

  /// The field's text changed.
  void textChanged() {
    final s = _session;
    if (s == null) return;
    final withText = s.draft.copyWith(text: s.input.text);
    s.draft = withText.copyWith(height: measureHeight(withText));
    notifyListeners();
  }

  /// Moves / resizes the box being edited (dragging).
  void setFrame({double? x, double? y, double? width}) {
    final s = _session;
    if (s == null) return;
    final moved = s.draft.copyWith(x: x, y: y, width: width);
    s.draft = moved.copyWith(height: measureHeight(moved));
    notifyListeners();
  }

  /// Applies a formatting change to the box being edited and to the
  /// formatting of new boxes.
  void applyFormat(TextItem Function(TextItem) change) {
    format = change(format);
    final s = _session;
    if (s != null) {
      final hadFocus = s.focus.hasFocus;
      final changed = change(s.draft);
      s.draft = changed.copyWith(height: measureHeight(changed));
      if (hadFocus) s.focus.requestFocus();
    }
    notifyListeners();
  }

  void _onControllerChanged() {
    final s = _session;
    if (s == null || !controller.isReady) return;
    final page = controller.doc.pageMeta(s.pageId);
    final original = s.original;
    final stale = page == null ||
        (original != null &&
            !identical(controller.doc.page(s.pageId).textById(original.id),
                original));
    if (stale) cancel();
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    final s = _session;
    _session = null;
    s?.dispose();
    super.dispose();
  }
}
