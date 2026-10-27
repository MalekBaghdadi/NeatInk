import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../document/commands.dart';
import '../../../../document/page_items.dart';
import '../../../../ink/ink_rect.dart';
import '../../../../ink/vec2.dart';
import '../../editor_controller.dart';
import 'frame_geometry.dart';
import 'image_normalizer.dart';
import 'image_source.dart';

/// The picture selected with the image tool, and the frame it is being
/// dragged to.
class ImageSelection {
  ImageSelection(this.pageId, this.item) : frame = item.frame;

  final String pageId;

  /// The committed picture.
  final ImageItem item;

  /// Where the picture is now (differs from [item] while dragging).
  InkRect frame;

  bool get moved =>
      frame.left != item.x ||
      frame.top != item.y ||
      frame.width != item.width ||
      frame.height != item.height;
}

/// Inserting, selecting, moving, resizing and deleting pictures. One undo
/// step per action.
class ImageEditor extends ChangeNotifier {
  ImageEditor(this.controller, this.picker, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid() {
    controller.addListener(_onControllerChanged);
  }

  final EditorController controller;
  final ImagePicker picker;
  final Uuid _uuid;

  ImageSelection? _selection;
  ImageSelection? get selection => _selection;

  bool _busy = false;

  /// True while a picture is being picked / converted / stored.
  bool get busy => _busy;

  /// The picture hidden from the image layer on [pageId] because the overlay
  /// shows it at its dragged position.
  String? draggedIdOn(String pageId) {
    final s = _selection;
    return s != null && s.pageId == pageId && s.moved ? s.item.id : null;
  }

  // ---------------------------------------------------------------------------
  // Inserting

  /// Lets the user pick a picture and places it on the page in view.
  /// Returns null on success or cancel, else a message to show.
  Future<String?> insert() async {
    if (_busy || !controller.isReady) return null;
    final page = controller.currentPageMeta;
    if (page == null || !controller.isPageEditable(page.id)) {
      return "This page can't be edited.";
    }
    _busy = true;
    notifyListeners();
    try {
      final picked = await picker();
      if (picked == null) return null;
      final NormalizedImage image;
      try {
        image = await normalizeImage(picked.bytes);
      } on ImageImportException catch (e) {
        return e.message;
      }
      // The user may have left, or deleted the page, while picking.
      if (!controller.isReady || !controller.isPageEditable(page.id)) {
        return null;
      }
      final asset = await controller.repository
          .addAssetBytes(controller.notebookId, image.bytes, image.extension);
      if (!controller.isPageEditable(page.id)) return null;
      final frame = fitImageOnPage(
        pageWidth: page.width,
        pageHeight: page.height,
        pixelWidth: image.width,
        pixelHeight: image.height,
      );
      final item = ImageItem(
        id: _uuid.v4(),
        x: frame.left,
        y: frame.top,
        width: frame.width,
        height: frame.height,
        asset: asset,
        pixelWidth: image.width,
        pixelHeight: image.height,
      );
      controller.execute(PageItemsCommand(page.id,
          label: 'Add picture', imageChanges: [(null, item)]));
      _selection = ImageSelection(page.id, item);
      return null;
    } catch (e) {
      debugPrint('NeatInk: could not add picture: $e');
      return "The picture couldn't be added.";
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Selecting and editing

  /// A tap at [p]: selects the picture under it, or clears the selection.
  void tap(String pageId, Vec2 p, double scale) {
    if (!controller.isPageEditable(pageId)) return;
    final hit = hitImageItem(controller.doc.page(pageId).images, p,
        slop: 2 / scale);
    select(hit == null ? null : ImageSelection(pageId, hit));
  }

  void select(ImageSelection? selection) {
    final old = _selection;
    _selection = selection;
    if (old != null) controller.invalidatePageRender(old.pageId);
    notifyListeners();
  }

  /// Shows the picture at [frame] while it is dragged.
  void dragTo(InkRect frame) {
    final s = _selection;
    if (s == null) return;
    final wasMoved = s.moved;
    s.frame = frame;
    if (wasMoved != s.moved) controller.invalidatePageRender(s.pageId);
    notifyListeners();
  }

  /// Stores the dragged frame as one undo step.
  void commitDrag({required bool resized}) {
    final s = _selection;
    if (s == null) return;
    if (!s.moved || !controller.isPageEditable(s.pageId)) {
      cancelDrag();
      return;
    }
    final after = s.item.copyWith(
      x: s.frame.left,
      y: s.frame.top,
      width: s.frame.width,
      height: s.frame.height,
    );
    _selection = ImageSelection(s.pageId, after);
    controller.execute(PageItemsCommand(s.pageId,
        label: resized ? 'Resize picture' : 'Move picture',
        imageChanges: [(s.item, after)]));
    controller.invalidatePageRender(s.pageId);
    notifyListeners();
  }

  void cancelDrag() {
    final s = _selection;
    if (s == null || !s.moved) return;
    s.frame = s.item.frame;
    controller.invalidatePageRender(s.pageId);
    notifyListeners();
  }

  /// Deletes the selected picture (undoable). The asset file stays so undo
  /// can bring the picture back.
  void deleteSelected() {
    final s = _selection;
    if (s == null) return;
    _selection = null;
    if (controller.isPageEditable(s.pageId)) {
      controller.execute(PageItemsCommand(s.pageId,
          label: 'Delete picture', imageChanges: [(s.item, null)]));
    }
    controller.invalidatePageRender(s.pageId);
    notifyListeners();
  }

  void _onControllerChanged() {
    final s = _selection;
    if (s == null || !controller.isReady) return;
    final page = controller.doc.pageMeta(s.pageId);
    final current = page == null
        ? null
        : controller.doc.page(s.pageId).imageById(s.item.id);
    if (current == null || !identical(current, s.item)) {
      _selection = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    super.dispose();
  }
}
