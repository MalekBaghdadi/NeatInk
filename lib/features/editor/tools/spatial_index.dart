import '../../../document/page_content.dart';
import '../../../document/page_items.dart';
import '../../../ink/ink_rect.dart';
import '../../../ink/stroke.dart';
import 'tool_config.dart';

/// A uniform-grid spatial index over one page's strokes (by
/// [Stroke.paintBounds]) and text boxes / images (by their frames).
///
/// Hit tests (erasers, lasso, taps) query a rectangle and only look at the
/// few items whose cells it touches, so they stay fast on pages with
/// thousands of strokes.
///
/// The index stores the item instances themselves. Keep it in step with the
/// page either incrementally ([addStroke], [removeStroke], ...) or by calling
/// [sync] after every change, which diffs by identity and is cheap when
/// little changed.
///
/// Query results are in no particular order; callers that need paint order
/// must sort by the page lists.
class SpatialIndex {
  SpatialIndex({ToolConfig config = ToolConfig.defaults})
      : _strokes = _Grid<Stroke>(
            config.spatialCellSizePt, config.spatialMaxCellsPerEntry),
        _texts = _Grid<TextItem>(
            config.spatialCellSizePt, config.spatialMaxCellsPerEntry),
        _images = _Grid<ImageItem>(
            config.spatialCellSizePt, config.spatialMaxCellsPerEntry);

  /// An index already filled from [page].
  factory SpatialIndex.forPage(PageContent page,
      {ToolConfig config = ToolConfig.defaults}) {
    return SpatialIndex(config: config)..sync(page);
  }

  final _Grid<Stroke> _strokes;
  final _Grid<TextItem> _texts;
  final _Grid<ImageItem> _images;

  PageContent? _syncedPage;
  int _syncedRevision = -1;

  int get strokeCount => _strokes.entries.length;
  int get textCount => _texts.entries.length;
  int get imageCount => _images.entries.length;
  bool get isEmpty => strokeCount == 0 && textCount == 0 && imageCount == 0;

  // ------------------------------------------------------------- updates

  /// Adds [stroke], replacing any indexed stroke with the same id.
  void addStroke(Stroke stroke) {
    _strokes.put(stroke.id, stroke, stroke.paintBounds);
    _invalidateSync();
  }

  /// Same as [addStroke]; reads better at call sites that update.
  void replaceStroke(Stroke stroke) => addStroke(stroke);

  /// Removes the stroke with [id]. Returns false if it wasn't indexed.
  bool removeStroke(String id) {
    _invalidateSync();
    return _strokes.remove(id);
  }

  void addText(TextItem text) {
    _texts.put(text.id, text, text.frame);
    _invalidateSync();
  }

  bool removeText(String id) {
    _invalidateSync();
    return _texts.remove(id);
  }

  void addImage(ImageItem image) {
    _images.put(image.id, image, image.frame);
    _invalidateSync();
  }

  bool removeImage(String id) {
    _invalidateSync();
    return _images.remove(id);
  }

  void clear() {
    _strokes.clear();
    _texts.clear();
    _images.clear();
    _invalidateSync();
  }

  /// Brings the index in line with [page]: indexes new or replaced items (by
  /// identity, so strokes replaced by a command are re-indexed) and drops
  /// items no longer on the page. Returns false without doing anything when
  /// [page] is the page last synced and its revision hasn't changed.
  bool sync(PageContent page) {
    if (identical(page, _syncedPage) && page.revision == _syncedRevision) {
      return false;
    }
    _strokes.syncFrom(page.strokes, (s) => s.id, (s) => s.paintBounds);
    _texts.syncFrom(page.texts, (t) => t.id, (t) => t.frame);
    _images.syncFrom(page.images, (i) => i.id, (i) => i.frame);
    _syncedPage = page;
    _syncedRevision = page.revision;
    return true;
  }

  void _invalidateSync() {
    _syncedPage = null;
    _syncedRevision = -1;
  }

  // ------------------------------------------------------------- queries

  /// Strokes whose paint bounds overlap [area] (edges inclusive).
  List<Stroke> strokesIn(InkRect area) => _strokes.query(area);

  /// Text boxes whose frames overlap [area].
  List<TextItem> textsIn(InkRect area) => _texts.query(area);

  /// Images whose frames overlap [area].
  List<ImageItem> imagesIn(InkRect area) => _images.query(area);

  /// The indexed stroke with [id], or null.
  Stroke? stroke(String id) => _strokes.entries[id]?.value;

  TextItem? text(String id) => _texts.entries[id]?.value;

  ImageItem? image(String id) => _images.entries[id]?.value;
}

class _Entry<T> {
  _Entry(this.value, this.bounds);

  T value;
  InkRect bounds;

  /// Inclusive cell range; unused when [oversized].
  int x0 = 0, y0 = 0, x1 = -1, y1 = -1;
  bool oversized = false;

  /// Last query that reported this entry (dedupes entries spanning cells).
  int queryStamp = 0;

  /// Last sync generation that saw this entry on the page.
  int syncStamp = 0;
}

/// One grid for one kind of item.
class _Grid<T> {
  _Grid(this.cellSize, this.maxCellsPerEntry);

  final double cellSize;
  final int maxCellsPerEntry;

  final Map<String, _Entry<T>> entries = {};
  final Map<int, List<_Entry<T>>> _cells = {};
  final List<_Entry<T>> _oversized = [];
  int _queryStamp = 0;
  int _syncStamp = 0;

  /// Coordinates beyond this are not gridded (keeps cell ids in 32 bits).
  static const double _maxCoordinate = 1e9;

  _Entry<T> put(String id, T value, InkRect bounds) {
    final existing = entries[id];
    if (existing == null) {
      final e = _Entry<T>(value, bounds);
      entries[id] = e;
      _link(e);
      return e;
    }
    existing.value = value;
    if (existing.bounds != bounds) {
      _unlink(existing);
      existing.bounds = bounds;
      _link(existing);
    }
    return existing;
  }

  bool remove(String id) {
    final e = entries.remove(id);
    if (e == null) return false;
    _unlink(e);
    return true;
  }

  void clear() {
    entries.clear();
    _cells.clear();
    _oversized.clear();
  }

  void syncFrom(List<T> items, String Function(T) idOf,
      InkRect Function(T) boundsOf) {
    final stamp = ++_syncStamp;
    var seen = 0;
    for (final item in items) {
      final id = idOf(item);
      var e = entries[id];
      if (e == null || !identical(e.value, item)) {
        e = put(id, item, boundsOf(item));
      }
      if (e.syncStamp != stamp) {
        e.syncStamp = stamp;
        seen++;
      }
    }
    if (entries.length > seen) {
      final stale = [
        for (final MapEntry(:key, :value) in entries.entries)
          if (value.syncStamp != stamp) key,
      ];
      stale.forEach(remove);
    }
  }

  List<T> query(InkRect area) {
    final out = <T>[];
    if (entries.isEmpty || !_isFinite(area)) return out;
    final stamp = ++_queryStamp;
    final range = _cellRange(area);
    if (range == null ||
        (range.$3 - range.$1 + 1) * (range.$4 - range.$2 + 1) >
            entries.length) {
      // Visiting the cells would cost more than checking every entry.
      for (final e in entries.values) {
        if (e.bounds.overlaps(area)) out.add(e.value);
      }
      return out;
    }
    final (x0, y0, x1, y1) = range;
    for (var cx = x0; cx <= x1; cx++) {
      for (var cy = y0; cy <= y1; cy++) {
        final cell = _cells[_key(cx, cy)];
        if (cell == null) continue;
        for (final e in cell) {
          if (e.queryStamp == stamp) continue;
          e.queryStamp = stamp;
          if (e.bounds.overlaps(area)) out.add(e.value);
        }
      }
    }
    for (final e in _oversized) {
      if (e.bounds.overlaps(area)) out.add(e.value);
    }
    return out;
  }

  void _link(_Entry<T> e) {
    final range = _isFinite(e.bounds) ? _cellRange(e.bounds) : null;
    if (range == null ||
        (range.$3 - range.$1 + 1) * (range.$4 - range.$2 + 1) >
            maxCellsPerEntry) {
      e.oversized = true;
      _oversized.add(e);
      return;
    }
    e
      ..oversized = false
      ..x0 = range.$1
      ..y0 = range.$2
      ..x1 = range.$3
      ..y1 = range.$4;
    for (var cx = e.x0; cx <= e.x1; cx++) {
      for (var cy = e.y0; cy <= e.y1; cy++) {
        (_cells[_key(cx, cy)] ??= <_Entry<T>>[]).add(e);
      }
    }
  }

  void _unlink(_Entry<T> e) {
    if (e.oversized) {
      _oversized.remove(e);
      return;
    }
    for (var cx = e.x0; cx <= e.x1; cx++) {
      for (var cy = e.y0; cy <= e.y1; cy++) {
        final key = _key(cx, cy);
        final cell = _cells[key];
        if (cell == null) continue;
        cell.remove(e);
        if (cell.isEmpty) _cells.remove(key);
      }
    }
  }

  /// Inclusive cell range covering [r], or null when it is too far out to
  /// grid (those entries live in the overflow list).
  (int, int, int, int)? _cellRange(InkRect r) {
    if (r.left < -_maxCoordinate ||
        r.top < -_maxCoordinate ||
        r.right > _maxCoordinate ||
        r.bottom > _maxCoordinate) {
      return null;
    }
    return (
      (r.left / cellSize).floor(),
      (r.top / cellSize).floor(),
      (r.right / cellSize).floor(),
      (r.bottom / cellSize).floor(),
    );
  }

  static bool _isFinite(InkRect r) =>
      r.left.isFinite && r.top.isFinite && r.right.isFinite && r.bottom.isFinite;

  /// Packs a cell coordinate pair into one int (both fit in 32 bits because
  /// coordinates are bounded by [_maxCoordinate]).
  static int _key(int cx, int cy) => ((cx & 0xFFFFFFFF) << 32) | (cy & 0xFFFFFFFF);
}
