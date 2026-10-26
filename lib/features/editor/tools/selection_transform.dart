import 'dart:math' as math;

import '../../../document/commands.dart';
import '../../../document/page_content.dart';
import '../../../document/page_items.dart';
import '../../../ink/affine2.dart';
import '../../../ink/ink_rect.dart';
import '../../../ink/stroke.dart';
import '../../../ink/vec2.dart';
import 'selection.dart';
import 'tool_config.dart';

/// Moving, resizing, recolouring and restoring a lasso selection.
///
/// Everything here is pure: functions take the page and the selection and
/// return [SelectionEdit]s (before/after lists). The editor turns an edit
/// into one undo step with [SelectionEdit.toCommand] and runs it through the
/// notebook's `CommandStack`.

/// One of the 8 resize handles around a selection's bounds.
enum ResizeHandle {
  topLeft(0, 0),
  top(0.5, 0),
  topRight(1, 0),
  right(1, 0.5),
  bottomRight(1, 1),
  bottom(0.5, 1),
  bottomLeft(0, 1),
  left(0, 0.5);

  const ResizeHandle(this.fx, this.fy);

  /// Position on the bounds as fractions of width and height (0, 0.5 or 1).
  final double fx, fy;

  /// Corner handles scale both axes uniformly (keeping the aspect ratio).
  bool get isCorner => fx != 0.5 && fy != 0.5;

  /// Edge handles scale one axis only.
  bool get isEdge => !isCorner;

  /// Whether dragging this handle changes the width / the height.
  bool get scalesX => fx != 0.5;
  bool get scalesY => fy != 0.5;

  /// The handle on the opposite side; it stays fixed while this one drags.
  ResizeHandle get opposite {
    for (final h in ResizeHandle.values) {
      if (h.fx == 1 - fx && h.fy == 1 - fy) return h;
    }
    throw StateError('unreachable');
  }

  /// Where this handle sits on [bounds].
  Vec2 positionOn(InkRect bounds) => Vec2(bounds.left + bounds.width * fx,
      bounds.top + bounds.height * fy);
}

/// The transform for moving a selection by ([dx], [dy]).
Affine2 moveTransform(double dx, double dy) => Affine2.translation(dx, dy);

/// The transform for dragging [handle] of a selection with [bounds] so that
/// the handle ends up at [handleTarget] (page coordinates).
///
/// The opposite handle is the fixed anchor. Corner handles keep the aspect
/// ratio, using the projection of the drag onto the anchor→handle diagonal,
/// so the corner follows the pen smoothly. Edge handles scale one axis.
///
/// Minimum size ([ToolConfig.minSelectionSizePt]): an edge drag never makes
/// its side shorter than the minimum, and a corner drag never makes the
/// longer side shorter than it (so thin selections such as a straight line
/// can still shrink proportionally). A side already below the minimum may
/// only grow. Dragging past the anchor does not mirror the selection.
Affine2 resizeTransform(
  InkRect bounds,
  ResizeHandle handle,
  Vec2 handleTarget, {
  ToolConfig config = ToolConfig.defaults,
}) {
  final anchor = handle.opposite.positionOn(bounds);
  final from = handle.positionOn(bounds);
  final w = bounds.width, h = bounds.height;
  final minSize = config.minSelectionSizePt;

  // Smallest allowed scale for a side of `length`.
  double minScale(double length) =>
      length >= minSize ? minSize / length : 1.0;

  // Degenerate sides can't be scaled meaningfully.
  final canX = handle.scalesX && w > 1e-6;
  final canY = handle.scalesY && h > 1e-6;
  if (!canX && !canY) return Affine2.identity;

  if (handle.isCorner) {
    final diag = from - anchor;
    var s = (handleTarget - anchor).dot(diag) / diag.lengthSquared;
    final lo = minScale(math.max(canX ? w : 0.0, canY ? h : 0.0));
    if (!s.isFinite || s < lo) s = lo;
    return Affine2.scaling(s, s, pivot: anchor);
  }
  if (canX) {
    var sx = (handleTarget.x - anchor.x) / (from.x - anchor.x);
    if (!sx.isFinite || sx < minScale(w)) sx = minScale(w);
    return Affine2.scaling(sx, 1, pivot: anchor);
  }
  var sy = (handleTarget.y - anchor.y) / (from.y - anchor.y);
  if (!sy.isFinite || sy < minScale(h)) sy = minScale(h);
  return Affine2.scaling(1, sy, pivot: anchor);
}

/// Bounding box of [r] after the affine transform [m].
InkRect transformRect(InkRect r, Affine2 m) => InkRect.fromPoints([
      m.apply(Vec2(r.left, r.top)),
      m.apply(Vec2(r.right, r.top)),
      m.apply(Vec2(r.right, r.bottom)),
      m.apply(Vec2(r.left, r.bottom)),
    ]);

/// A selection edit as before/after lists.
///
/// [strokesBefore] / [strokesAfter] pair up by index and id (for
/// `ReplaceStrokesCommand`); [textChanges] and [imageChanges] are
/// (before, after) pairs for `PageItemsCommand`. Unchanged things are left
/// out, so an edit that changes nothing [isEmpty].
class SelectionEdit {
  SelectionEdit({
    List<Stroke> strokesBefore = const [],
    List<Stroke> strokesAfter = const [],
    List<(TextItem?, TextItem?)> textChanges = const [],
    List<(ImageItem?, ImageItem?)> imageChanges = const [],
    this.removedStrokeIds = const {},
  })  : assert(strokesBefore.length == strokesAfter.length),
        strokesBefore = List.unmodifiable(strokesBefore),
        strokesAfter = List.unmodifiable(strokesAfter),
        textChanges = List.unmodifiable(textChanges),
        imageChanges = List.unmodifiable(imageChanges);

  final List<Stroke> strokesBefore;
  final List<Stroke> strokesAfter;
  final List<(TextItem?, TextItem?)> textChanges;
  final List<(ImageItem?, ImageItem?)> imageChanges;

  /// Strokes deleted by the edit (for `RemoveStrokesCommand`).
  final Set<String> removedStrokeIds;

  bool get isEmpty =>
      strokesBefore.isEmpty &&
      textChanges.isEmpty &&
      imageChanges.isEmpty &&
      removedStrokeIds.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// The edit as one undoable command on [pageId], or null when [isEmpty].
  EditCommand? toCommand(String pageId, {required String label}) {
    final commands = <EditCommand>[
      if (strokesBefore.isNotEmpty)
        ReplaceStrokesCommand(pageId, strokesBefore, strokesAfter,
            label: label),
      if (removedStrokeIds.isNotEmpty)
        RemoveStrokesCommand(pageId, removedStrokeIds, label: label),
      if (textChanges.isNotEmpty || imageChanges.isNotEmpty)
        PageItemsCommand(pageId,
            label: label, textChanges: textChanges, imageChanges: imageChanges),
    ];
    if (commands.isEmpty) return null;
    return commands.length == 1 ? commands.single : CompositeCommand(label, commands);
  }
}

/// Applies the move/resize transform [m] to everything in [selection].
///
/// * Strokes: [Stroke.transformed], so `raw` and `points` move together and
///   the width scales with the transform's mean scale.
/// * Text boxes: the top-left corner follows [m]. A uniform scale (corner
///   resize) scales the box and the font size by the vertical scale; a
///   one-axis scale (edge drag) only changes the box width and keeps the
///   font size, so the text re-wraps instead of stretching. The editor
///   re-measures `height` after a width change.
/// * Images: the frame follows [m] (images may stretch on edge drags).
///
/// [m] must be a translation and/or axis-aligned scale, as built by
/// [moveTransform] and [resizeTransform].
SelectionEdit transformSelection(
  PageContent page,
  Selection selection,
  Affine2 m, {
  ToolConfig config = ToolConfig.defaults,
}) {
  if (m.isIdentity || selection.isEmpty) return SelectionEdit();
  final before = selection.strokesOn(page);
  return SelectionEdit(
    strokesBefore: before,
    strokesAfter: [for (final s in before) s.transformed(m)],
    textChanges: [
      for (final t in selection.textsOn(page))
        (t, transformTextItem(t, m, config: config)),
    ],
    imageChanges: [
      for (final i in selection.imagesOn(page)) (i, transformImageItem(i, m)),
    ],
  );
}

/// [text] after the move/resize transform [m] (see [transformSelection]).
TextItem transformTextItem(TextItem text, Affine2 m,
    {ToolConfig config = ToolConfig.defaults}) {
  final sx = m.a.abs(), sy = m.d.abs();
  final origin = m.apply(Vec2(text.x, text.y));
  final uniform = (sx - sy).abs() <= 1e-9 * math.max(sx, sy);
  if (uniform) {
    final fontSize = text.fontSize * sy;
    return text.copyWith(
      x: origin.x,
      y: origin.y,
      width: text.width * sx,
      height: text.height * sy,
      // Never shrink below the minimum, but don't enlarge an already tiny
      // font either.
      fontSize: math.max(fontSize, math.min(config.minFontSizePt, text.fontSize)),
    );
  }
  return text.copyWith(x: origin.x, y: origin.y, width: text.width * sx);
}

/// [image] after the move/resize transform [m] (see [transformSelection]).
ImageItem transformImageItem(ImageItem image, Affine2 m) {
  final r = transformRect(image.frame, m);
  return image.copyWith(x: r.left, y: r.top, width: r.width, height: r.height);
}

/// Sets the colour of the selected pen strokes and text boxes to [color]
/// (ARGB). Highlighter strokes keep their colour unless
/// [includeHighlighters] is set. Things that already have [color] are left
/// out.
SelectionEdit recolorSelection(
  PageContent page,
  Selection selection,
  int color, {
  bool includeHighlighters = false,
}) {
  final before = [
    for (final s in selection.strokesOn(page))
      if ((includeHighlighters || !s.isHighlighter) && s.color != color) s,
  ];
  return SelectionEdit(
    strokesBefore: before,
    strokesAfter: [for (final s in before) s.copyWith(color: color)],
    textChanges: [
      for (final t in selection.textsOn(page))
        if (t.color != color) (t, t.copyWith(color: color)),
    ],
  );
}

/// "Restore original": every selected stroke goes back to its hand-drawn
/// `raw` points. Tidy is marked not applied and locked (so it is never
/// tidied again automatically) and any snapped shape is cleared. Strokes
/// already in that state are left out.
SelectionEdit restoreOriginalSelection(PageContent page, Selection selection) {
  final before = <Stroke>[];
  final after = <Stroke>[];
  for (final s in selection.strokesOn(page)) {
    final r = restoreOriginalStroke(s);
    if (!identical(r, s)) {
      before.add(s);
      after.add(r);
    }
  }
  return SelectionEdit(strokesBefore: before, strokesAfter: after);
}

/// [s] with `points = raw`, tidy not applied + locked, and no shape. Returns
/// [s] itself when it is already like that.
Stroke restoreOriginalStroke(Stroke s) {
  final tidy = s.tidy.copyWith(applied: false, locked: true);
  if (s.pointsAreRaw && s.shape == null && s.tidy == tidy) return s;
  return s.copyWith(points: s.raw, tidy: tidy, clearShape: true);
}

/// Deletes everything in [selection]: strokes via `RemoveStrokesCommand`
/// and items via `PageItemsCommand` (both restore paint order on undo).
SelectionEdit deleteSelection(PageContent page, Selection selection) =>
    SelectionEdit(
      removedStrokeIds: {
        for (final s in selection.strokesOn(page)) s.id,
      },
      textChanges: [for (final t in selection.textsOn(page)) (t, null)],
      imageChanges: [for (final i in selection.imagesOn(page)) (i, null)],
    );
