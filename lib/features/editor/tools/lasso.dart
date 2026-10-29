import '../../../document/page_content.dart';
import '../../../document/page_items.dart';
import '../../../ink/ink_rect.dart';
import '../../../ink/stroke.dart';
import '../../../ink/vec2.dart';
import 'geometry.dart';
import 'selection.dart';
import 'spatial_index.dart';
import 'tool_config.dart';

export 'selection.dart';

/// Freeform lasso selection.
///
/// [lasso] is the pen path in page points; it is closed implicitly and
/// tested with the even-odd rule, so self-crossing lassos behave like the
/// filled shape the user sees.
///
/// * A stroke is selected when at least
///   [ToolConfig.lassoStrokeInsideFraction] of its displayed points (or its
///   only point) are inside.
/// * A text box or image is selected when its centre is inside, or at least
///   [ToolConfig.lassoItemMinCornersInside] of its corners are. A text box
///   is also selected when the middle of any of its words is inside
///   ([wordBoxesOf] gives where its words are): converted text makes wide
///   boxes, and a lasso around a phrase in one never held its corners.
/// * A lasso enclosing less than [ToolConfig.lassoTapMaxAreaPt2] (a tap or
///   a tiny scribble) selects the topmost item under its first point
///   instead; see [tapSelect]. [tapRadius] overrides the tap tolerance (the
///   UI may scale it with zoom).
///
/// [index], when given, must be in sync with [page]; it only narrows the
/// candidates.
Selection lassoSelect({
  required String pageId,
  required PageContent page,
  required List<Vec2> lasso,
  SpatialIndex? index,
  double? tapRadius,
  List<InkRect> Function(TextItem item)? wordBoxesOf,
  ToolConfig config = ToolConfig.defaults,
}) {
  final path = [
    for (final p in lasso)
      if (p.isFinite) p,
  ];
  if (path.isEmpty) return Selection.empty(pageId);
  if (isTinyLasso(path, config.lassoTapMaxAreaPt2)) {
    return tapSelect(
      pageId: pageId,
      page: page,
      point: path.first,
      radius: tapRadius ?? config.tapHitRadiusPt,
    );
  }

  final area = InkRect.fromPoints(path);
  final strokes = index?.strokesIn(area) ?? page.strokes;
  final texts = index?.textsIn(area) ?? page.texts;
  final images = index?.imagesIn(area) ?? page.images;

  final strokeIds = <String>{
    for (final s in strokes)
      if (_strokeInLasso(s, path, area, config.lassoStrokeInsideFraction, config.lassoStrokeCenterFraction))
        s.id,
  };
  bool wordInside(TextItem t) {
    final words = wordBoxesOf?.call(t) ?? const <InkRect>[];
    return words.any((w) => pointInPolygon(w.center.x, w.center.y, path));
  }

  final textIds = <String>{
    for (final t in texts)
      if (_frameInLasso(t.frame, path, config.lassoItemMinCornersInside) || wordInside(t)) t.id,
  };
  final imageIds = <String>{
    for (final i in images)
      if (_frameInLasso(i.frame, path, config.lassoItemMinCornersInside)) i.id,
  };
  return Selection.fromPage(page,
      pageId: pageId,
      strokeIds: strokeIds,
      textIds: textIds,
      imageIds: imageIds);
}

/// True when the closed [lasso] encloses less than [maxArea] pt² (with the
/// even-odd rule), i.e. it is a tap or a tiny scribble rather than a loop.
///
/// The shoelace area is exact for simple loops, but the lobes of a
/// self-crossing lasso (a figure eight) cancel out in it. So when it is
/// small and the lasso's box could hold more than [maxArea], the even-odd
/// area is estimated by sampling a grid over the box.
bool isTinyLasso(List<Vec2> lasso, double maxArea) {
  if (lasso.length < 3) return true;
  if (signedPolygonArea(lasso).abs() >= maxArea) return false;
  final box = InkRect.fromPoints(lasso);
  if (box.area < maxArea) return true;
  const n = _areaSamplesPerSide;
  var inside = 0;
  for (var i = 0; i < n; i++) {
    final y = box.top + box.height * (i + 0.5) / n;
    for (var j = 0; j < n; j++) {
      final x = box.left + box.width * (j + 0.5) / n;
      if (pointInPolygon(x, y, lasso)) inside++;
    }
  }
  return box.area * inside / (n * n) < maxArea;
}

/// Grid resolution of the even-odd area estimate in [isTinyLasso].
const int _areaSamplesPerSide = 24;

bool _strokeInLasso(Stroke s, List<Vec2> lasso, InkRect lassoBox, double fraction, double centerFraction) {
  final pts = s.points;
  if (pts.isEmpty || !s.bounds.overlaps(lassoBox)) return false;
  final n = pts.length;
  var inside = 0;
  for (final p in pts) {
    if (lassoBox.contains(p.pos) && pointInPolygon(p.x, p.y, lasso)) inside++;
  }
  // A little slack, so 3 of 5 counts as 60%.
  if (inside >= fraction * n - 1e-9) return true;
  final c = s.bounds.center;
  return inside >= centerFraction * n - 1e-9 && pointInPolygon(c.x, c.y, lasso);
}

bool _frameInLasso(InkRect frame, List<Vec2> lasso, int minCorners) {
  final c = frame.center;
  if (pointInPolygon(c.x, c.y, lasso)) return true;
  var corners = 0;
  for (final p in [
    Vec2(frame.left, frame.top),
    Vec2(frame.right, frame.top),
    Vec2(frame.right, frame.bottom),
    Vec2(frame.left, frame.bottom),
  ]) {
    if (pointInPolygon(p.x, p.y, lasso)) corners++;
  }
  return corners >= minCorners;
}

/// Selects the single topmost thing under [point]: pen strokes first (they
/// paint on top), then text boxes, then highlighter strokes, then images,
/// each from the last-painted down. A stroke is hit within [radius] of its
/// painted outline; an item within [radius] of its frame. Returns an empty
/// selection when nothing is there.
Selection tapSelect({
  required String pageId,
  required PageContent page,
  required Vec2 point,
  double radius = 5,
}) {
  Selection one({String? stroke, String? text, String? image}) =>
      Selection.fromPage(page,
          pageId: pageId,
          strokeIds: [?stroke],
          textIds: [?text],
          imageIds: [?image]);

  final pen = _topStroke(page.strokes, point, radius, highlighter: false);
  if (pen != null) return one(stroke: pen);
  final text = _topItem<TextItem>(page.texts, (t) => t.frame, point, radius);
  if (text != null) return one(text: text.id);
  final hl = _topStroke(page.strokes, point, radius, highlighter: true);
  if (hl != null) return one(stroke: hl);
  final image =
      _topItem<ImageItem>(page.images, (i) => i.frame, point, radius);
  if (image != null) return one(image: image.id);
  return Selection.empty(pageId);
}

String? _topStroke(List<Stroke> strokes, Vec2 p, double radius,
    {required bool highlighter}) {
  for (var i = strokes.length - 1; i >= 0; i--) {
    final s = strokes[i];
    if (s.isHighlighter != highlighter || s.points.isEmpty) continue;
    if (!s.paintBounds.inflate(radius).contains(p)) continue;
    if (strokeHitAt(s, p, radius)) return s.id;
  }
  return null;
}

T? _topItem<T>(
    List<T> items, InkRect Function(T) frameOf, Vec2 p, double radius) {
  for (var i = items.length - 1; i >= 0; i--) {
    if (frameOf(items[i]).inflate(radius).contains(p)) return items[i];
  }
  return null;
}

/// True when [p] is within [radius] of the painted outline of [s] (its
/// polyline inflated by half its width).
bool strokeHitAt(Stroke s, Vec2 p, double radius) {
  final pts = s.points;
  if (pts.isEmpty) return false;
  final reach = radius + s.size / 2;
  final reach2 = reach * reach;
  if (pts.length == 1) return pts.first.pos.distanceSquaredTo(p) <= reach2;
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    if (distanceSquaredToSegmentXY(p.x, p.y, a.x, a.y, b.x, b.y) <= reach2) {
      return true;
    }
  }
  return false;
}
