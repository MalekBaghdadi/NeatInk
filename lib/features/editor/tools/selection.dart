import '../../../document/page_content.dart';
import '../../../document/page_items.dart';
import '../../../ink/ink_rect.dart';
import '../../../ink/stroke.dart';

/// What the lasso selected on one page: stroke, text box and image ids, plus
/// the union of their painted bounds.
///
/// Immutable. Commands change the page, so after an edit (or undo) call
/// [refreshed] to drop ids that no longer exist and recompute [bounds].
class Selection {
  Selection({
    required this.pageId,
    Set<String> strokeIds = const {},
    Set<String> textIds = const {},
    Set<String> imageIds = const {},
    this.bounds = InkRect.empty,
  })  : strokeIds = Set.unmodifiable(strokeIds),
        textIds = Set.unmodifiable(textIds),
        imageIds = Set.unmodifiable(imageIds);

  /// A selection of the given ids with [bounds] computed from [page]. Ids
  /// not on the page are dropped.
  factory Selection.fromPage(
    PageContent page, {
    required String pageId,
    Iterable<String> strokeIds = const [],
    Iterable<String> textIds = const [],
    Iterable<String> imageIds = const [],
  }) {
    final sIds = strokeIds.toSet(), tIds = textIds.toSet();
    final iIds = imageIds.toSet();
    final strokes = {
      for (final s in page.strokes)
        if (sIds.contains(s.id)) s.id,
    };
    final texts = {
      for (final t in page.texts)
        if (tIds.contains(t.id)) t.id,
    };
    final images = {
      for (final i in page.images)
        if (iIds.contains(i.id)) i.id,
    };
    return Selection(
      pageId: pageId,
      strokeIds: strokes,
      textIds: texts,
      imageIds: images,
      bounds: boundsOf(page,
          strokeIds: strokes, textIds: texts, imageIds: images),
    );
  }

  /// Nothing selected on [pageId].
  factory Selection.empty(String pageId) => Selection(pageId: pageId);

  final String pageId;
  final Set<String> strokeIds;
  final Set<String> textIds;
  final Set<String> imageIds;

  /// Union of the selected strokes' paint bounds and items' frames;
  /// [InkRect.empty] when nothing is selected.
  final InkRect bounds;

  bool get isEmpty => strokeIds.isEmpty && textIds.isEmpty && imageIds.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// Number of selected strokes, text boxes and images.
  int get length => strokeIds.length + textIds.length + imageIds.length;

  bool get hasStrokes => strokeIds.isNotEmpty;
  bool get hasItems => textIds.isNotEmpty || imageIds.isNotEmpty;

  /// The selected strokes, in paint order.
  List<Stroke> strokesOn(PageContent page) => [
        for (final s in page.strokes)
          if (strokeIds.contains(s.id)) s,
      ];

  /// The selected text boxes, in paint order.
  List<TextItem> textsOn(PageContent page) => [
        for (final t in page.texts)
          if (textIds.contains(t.id)) t,
      ];

  /// The selected images, in paint order.
  List<ImageItem> imagesOn(PageContent page) => [
        for (final i in page.images)
          if (imageIds.contains(i.id)) i,
      ];

  /// This selection re-read from [page]: missing ids dropped, bounds
  /// recomputed. Use after any command that may have changed the page.
  Selection refreshed(PageContent page) => Selection.fromPage(page,
      pageId: pageId,
      strokeIds: strokeIds,
      textIds: textIds,
      imageIds: imageIds);

  /// Union of both selections (same page). Bounds are recomputed from
  /// [page].
  Selection union(Selection other, PageContent page) {
    assert(other.pageId == pageId, 'Selections are on different pages');
    return Selection.fromPage(page,
        pageId: pageId,
        strokeIds: {...strokeIds, ...other.strokeIds},
        textIds: {...textIds, ...other.textIds},
        imageIds: {...imageIds, ...other.imageIds});
  }

  /// Union of the paint bounds of the given strokes and frames of the given
  /// items on [page], or [InkRect.empty] when none of them is there.
  static InkRect boundsOf(
    PageContent page, {
    Set<String> strokeIds = const {},
    Set<String> textIds = const {},
    Set<String> imageIds = const {},
  }) {
    InkRect? box;
    void add(InkRect r) => box = box == null ? r : box!.union(r);
    if (strokeIds.isNotEmpty) {
      for (final s in page.strokes) {
        if (strokeIds.contains(s.id) && s.points.isNotEmpty) {
          add(s.paintBounds);
        }
      }
    }
    for (final t in page.texts) {
      if (textIds.contains(t.id)) add(t.frame);
    }
    for (final i in page.images) {
      if (imageIds.contains(i.id)) add(i.frame);
    }
    return box ?? InkRect.empty;
  }

  @override
  String toString() => 'Selection($pageId: ${strokeIds.length} strokes, '
      '${textIds.length} texts, ${imageIds.length} images, $bounds)';
}
