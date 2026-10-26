import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../document/page_content.dart';
import '../../../ink/stroke.dart';
import '../../../render/stroke_outline.dart';
import '../editor_extensions.dart';

/// The two committed-content pictures of a page.
///
/// Paint order (CLAUDE.md, [PageContent]): background → images →
/// highlighter strokes → text boxes → pen strokes. The content is split in
/// two pictures so the live highlighter stroke can be painted between them,
/// i.e. exactly where it will sit once committed (under text and pen ink).
enum InkLayer {
  /// Images, then highlighter strokes.
  lower,

  /// Text boxes, then pen strokes.
  upper,
}

/// Paints a page's committed content in page coordinates, in the paint
/// order of [PageContent]: images → highlighter strokes → text boxes → pen
/// strokes. The thumbnail renderer uses this; the screen paints the same
/// thing as two pictures ([paintPageLayer]).
void paintPageContent(
  ui.Canvas canvas,
  PagePaintContext context, {
  PageLayerPainter? imageLayer,
  PageLayerPainter? textLayer,
}) {
  paintPageLayer(canvas, context, InkLayer.lower, imageLayer: imageLayer);
  paintPageLayer(canvas, context, InkLayer.upper, textLayer: textLayer);
}

/// Paints one [InkLayer] of a page's committed content in page coordinates.
void paintPageLayer(
  ui.Canvas canvas,
  PagePaintContext context,
  InkLayer layer, {
  PageLayerPainter? imageLayer,
  PageLayerPainter? textLayer,
}) {
  final paint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;
  final strokes = context.content.strokes;
  switch (layer) {
    case InkLayer.lower:
      imageLayer?.paint(canvas, context);
      for (final s in strokes) {
        if (s.isHighlighter) paintStroke(canvas, s, paint);
      }
    case InkLayer.upper:
      textLayer?.paint(canvas, context);
      for (final s in strokes) {
        if (!s.isHighlighter) paintStroke(canvas, s, paint);
      }
  }
}

/// Fills one stroke's cached outline. [paint] is reused across strokes to
/// avoid allocating per stroke.
void paintStroke(ui.Canvas canvas, Stroke s, Paint paint) {
  if (s.points.isEmpty) return;
  paint.color = strokeFillColor(s);
  canvas.drawPath(cachedStrokePath(s), paint);
}

/// Per-page cache of committed-content pictures (one per [InkLayer]).
///
/// A picture is recorded once per (content object, content revision,
/// render generation) and replayed on every paint, so scrolling, zooming
/// and rebuilding page widgets never re-walks the strokes. Pictures are
/// vector display lists, so they stay sharp at any zoom. The cache keeps
/// the most recently used [capacity] pictures.
///
/// Re-recording after an edit walks the page's strokes once; each stroke's
/// outline path is itself cached (`cachedStrokePath`), so this is a list of
/// `drawPath` calls, well under a frame even for thousands of strokes.
class PageRenderCache {
  PageRenderCache({this.capacity = 48});

  final int capacity;

  // LinkedHashMap keeps insertion order; re-inserting on use makes it LRU.
  final LinkedHashMap<(String, InkLayer), _CachedPicture> _entries =
      LinkedHashMap();

  int get length => _entries.length;

  /// The picture of [layer] for [pageId], re-recorded with [record] when
  /// [content], its revision or [generation] changed since the cached one.
  ui.Picture picture(
    String pageId,
    InkLayer layer, {
    required PageContent content,
    required int generation,
    required Rect bounds,
    required void Function(ui.Canvas canvas) record,
  }) {
    final key = (pageId, layer);
    final cached = _entries.remove(key);
    if (cached != null &&
        identical(cached.content, content) &&
        cached.revision == content.revision &&
        cached.generation == generation) {
      _entries[key] = cached;
      return cached.picture;
    }
    cached?.picture.dispose();
    final recorder = ui.PictureRecorder();
    record(ui.Canvas(recorder, bounds));
    final entry = _CachedPicture(
        recorder.endRecording(), content, content.revision, generation);
    _entries[key] = entry;
    _evictOverflow();
    return entry.picture;
  }

  /// Whether a picture of [layer] for [pageId] is cached (any revision).
  bool contains(String pageId, InkLayer layer) =>
      _entries.containsKey((pageId, layer));

  /// Drops the cached pictures of [pageId].
  void evict(String pageId) {
    for (final layer in InkLayer.values) {
      _entries.remove((pageId, layer))?.picture.dispose();
    }
  }

  /// Drops pictures of pages not in [keep] (e.g. deleted pages).
  void retainOnly(Set<String> keep) {
    final drop = [
      for (final key in _entries.keys)
        if (!keep.contains(key.$1)) key,
    ];
    for (final key in drop) {
      _entries.remove(key)?.picture.dispose();
    }
  }

  void clear() {
    for (final e in _entries.values) {
      e.picture.dispose();
    }
    _entries.clear();
  }

  void _evictOverflow() {
    while (_entries.length > capacity) {
      final oldest = _entries.keys.first;
      _entries.remove(oldest)?.picture.dispose();
    }
  }
}

class _CachedPicture {
  _CachedPicture(this.picture, this.content, this.revision, this.generation);
  final ui.Picture picture;
  final PageContent content;
  final int revision;
  final int generation;
}

/// Replays a page's cached committed-content picture. Repaints when
/// [version] (the page's render version) changes.
class CommittedInkPainter extends CustomPainter {
  CommittedInkPainter({
    required this.pictureFor,
    required this.version,
  }) : super(repaint: version);

  /// Returns the current picture, or null when there is nothing to draw.
  final ui.Picture? Function() pictureFor;
  final Listenable version;

  @override
  void paint(Canvas canvas, Size size) {
    final picture = pictureFor();
    if (picture == null) return;
    // Ink never shows outside its page (outlines bleed half a stroke width
    // past points clamped to the edge).
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawPicture(picture);
    canvas.restore();
  }

  @override
  bool shouldRepaint(CommittedInkPainter oldDelegate) =>
      !identical(oldDelegate.version, version);
}
