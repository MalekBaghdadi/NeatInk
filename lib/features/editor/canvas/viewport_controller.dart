import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../document/notebook_meta.dart';
import '../../../ink/vec2.dart';
import 'page_layout.dart';

/// Where a position falls on a page.
class PageHit {
  const PageHit({
    required this.pageIndex,
    required this.pageId,
    required this.point,
  });

  final int pageIndex;
  final String pageId;

  /// Position in page points (origin top-left, y down). It can lie slightly
  /// outside the page when a hit slop was used.
  final Vec2 point;

  @override
  String toString() => 'PageHit($pageIndex, $pageId, $point)';
}

/// A saved zoom and translation of a [ViewportController].
class ViewportSnapshot {
  const ViewportSnapshot(this.zoom, this.offset);
  final double zoom;
  final Offset offset;
}

/// The view onto the document: one zoom level for all pages plus a
/// translation, and the page layout they apply to.
///
/// Screen mapping (viewport-local logical pixels):
///
///     local = doc × scale + offset,   scale = fitScale × zoom
///
/// where `fitScale` makes the widest page fill the viewport width minus
/// [sideMargin] on each side, so `zoom == 1` is "fit width". All other
/// coordinate helpers derive from this one formula, and ink is stored in
/// page points obtained with its inverse.
///
/// The controller is plain Dart state (no ticker): gesture code calls
/// [panBy] / [zoomAt]; the document view renders [matrix] and rebuilds the
/// lazy page list when [visibleRange] changes.
class ViewportController extends ChangeNotifier {
  ViewportController({
    this.minZoom = 0.5,
    this.maxZoom = 4.0,
    this.pageGap = 12,
    this.sideMargin = 16,
    this.topMargin = 16,
    this.bottomMargin = 72,
    this.cacheExtent = 0.5,
    this.settleDelay = const Duration(milliseconds: 250),
  });

  /// Zoom limits relative to fit-width.
  final double minZoom;
  final double maxZoom;

  /// Gap between pages, in points (it scales with zoom like the pages).
  final double pageGap;

  /// Empty space around the document at fit width, in logical pixels.
  final double sideMargin;
  final double topMargin;
  final double bottomMargin;

  /// Pages within this many viewport heights above/below the visible area
  /// are built too, so scrolling doesn't reveal unbuilt pages.
  final double cacheExtent;

  /// How long the scale must stay unchanged before [settledScale] updates
  /// (PDF backgrounds re-render at the settled resolution).
  final Duration settleDelay;

  PageLayout _layout = PageLayout.empty;
  Size _viewportSize = Size.zero;
  double _zoom = 1;
  Offset _offset = Offset.zero;
  int? _pendingJump;
  bool _disposed = false;

  RenderBox? Function()? _box;
  Timer? _settleTimer;

  late final ValueNotifier<PageRange?> _visibleRange = ValueNotifier(null);
  late final ValueNotifier<int> _currentPage = ValueNotifier(0);
  late final ValueNotifier<double> _settledScale = ValueNotifier(1);

  // ---------------------------------------------------------------------------
  // State

  PageLayout get layout => _layout;
  Size get viewportSize => _viewportSize;
  bool get hasSize => _viewportSize.width > 0 && _viewportSize.height > 0;

  /// Zoom relative to fit-width (1 = the widest page fits the width).
  double get zoom => _zoom;

  /// Logical pixels per page point at zoom 1.
  double get fitScale {
    if (_layout.width <= 0 || _viewportSize.width <= 0) return 1;
    return math.max(0.01, (_viewportSize.width - 2 * sideMargin) / _layout.width);
  }

  /// Logical pixels per page point.
  double get scale => fitScale * _zoom;

  /// Translation of document space in viewport pixels.
  Offset get offset => _offset;

  /// Size the document's content is laid out at (document space).
  Size get documentSize => _layout.size;

  /// The document → viewport transform as a matrix for painting.
  Matrix4 get matrix {
    final s = scale;
    // Column-major: uniform scale s, then translate by offset.
    return Matrix4(s, 0, 0, 0, 0, s, 0, 0, 0, 0, 1, 0, _offset.dx, _offset.dy,
        0, 1);
  }

  /// Pages that are visible or within [cacheExtent] of the visible area.
  ValueListenable<PageRange?> get visibleRange => _visibleRange;

  /// The page at the vertical centre of the viewport.
  ValueListenable<int> get currentPage => _currentPage;

  /// [scale] once zooming has paused for [settleDelay].
  ValueListenable<double> get settledScale => _settledScale;

  // ---------------------------------------------------------------------------
  // Inputs

  /// Updates the pages (after open or any page-list change). Keeps the
  /// current zoom and translation, clamped to the new document.
  void setPages(List<PageMeta> pages) {
    _layout = PageLayout(pages, gap: pageGap);
    _offset = _clamp(_offset);
    _consumePendingJump();
    _publish();
  }

  /// Records the viewport size WITHOUT notifying listeners, so it can be
  /// called during layout. Returns true when the size changed; the caller
  /// must then call [publish] after the frame.
  ///
  /// On a resize (e.g. rotation) the document point under the viewport
  /// centre stays under the centre, and the zoom (relative to fit-width)
  /// is kept.
  bool applyViewportSize(Size size) {
    if (size == _viewportSize || size.isEmpty) return false;
    if (!hasSize) {
      _viewportSize = size;
      _offset = _clamp(Offset(0, topMargin));
      _consumePendingJump();
      return true;
    }
    final anchor = localToDoc(_viewportSize.center(Offset.zero));
    _viewportSize = size;
    _offset = _clamp(size.center(Offset.zero) - anchor * scale);
    return true;
  }

  /// Notifies listeners and refreshes [visibleRange] / [currentPage] after a
  /// silent update such as [applyViewportSize].
  void publish() => _publish();

  /// Lets [globalToPage] and friends convert global positions. The document
  /// view registers a lookup of its render box.
  void attachViewportBox(RenderBox? Function()? lookup) => _box = lookup;

  // ---------------------------------------------------------------------------
  // Navigation

  /// Moves the document by [delta] viewport pixels (content follows the
  /// finger). Returns the delta actually applied after clamping.
  Offset panBy(Offset delta) {
    final before = _offset;
    _offset = _clamp(_offset + delta);
    if (_offset != before) _publish();
    return _offset - before;
  }

  /// Sets the zoom to [newZoom] (clamped) keeping the document point under
  /// the viewport-local [focal] point fixed.
  void zoomAt(Offset focal, double newZoom) {
    final z = newZoom.clamp(minZoom, maxZoom).toDouble();
    if (z == _zoom || !z.isFinite) return;
    final doc = localToDoc(focal);
    _zoom = z;
    _offset = _clamp(focal - doc * scale);
    _publish();
  }

  /// Zooms around the viewport centre.
  void setZoom(double newZoom) =>
      zoomAt(_viewportSize.center(Offset.zero), newZoom);

  /// One step of a pan / pinch gesture: the document point that was under
  /// the viewport-local [from] moves under [to], and the zoom becomes
  /// [newZoom] (clamped to [minZoom]..[maxZoom]).
  ///
  /// Doing both in one step keeps the content under the fingers while they
  /// pinch and move at the same time.
  void moveFocal(Offset from, Offset to, double newZoom) {
    final doc = localToDoc(from);
    final z = newZoom.isFinite
        ? newZoom.clamp(minZoom, maxZoom).toDouble()
        : _zoom;
    final oldZoom = _zoom, oldOffset = _offset;
    _zoom = z;
    _offset = _clamp(to - doc * scale);
    if (_zoom != oldZoom || _offset != oldOffset) _publish();
  }

  /// Scrolls so that the top of page [index] is at the top of the viewport
  /// (below [topMargin]) and the page is horizontally centred where
  /// possible. Before the viewport has a size, the jump is deferred until
  /// it does.
  void jumpToPage(int index) {
    if (_layout.isEmpty) {
      _pendingJump = index;
      return;
    }
    final i = index.clamp(0, _layout.length - 1);
    if (!hasSize) {
      _pendingJump = i;
      return;
    }
    _offset = _offsetShowingPage(i);
    _publish();
  }

  /// Scrolls the minimum amount so that [docRect] (document space) is
  /// visible, e.g. to reveal a search hit or a selection.
  void ensureVisible(Rect docRect) {
    if (!hasSize) return;
    final s = scale;
    final local = Rect.fromLTRB(docRect.left * s + _offset.dx,
        docRect.top * s + _offset.dy, docRect.right * s + _offset.dx,
        docRect.bottom * s + _offset.dy);
    var dx = 0.0, dy = 0.0;
    if (local.top < 0) {
      dy = -local.top + topMargin;
    } else if (local.bottom > _viewportSize.height) {
      dy = _viewportSize.height - local.bottom - topMargin;
    }
    if (local.left < 0) {
      dx = -local.left + sideMargin;
    } else if (local.right > _viewportSize.width) {
      dx = _viewportSize.width - local.right - sideMargin;
    }
    panBy(Offset(dx, dy));
  }

  /// The current zoom and translation (see [restore]).
  ViewportSnapshot get snapshot => ViewportSnapshot(_zoom, _offset);

  /// Returns to a [snapshot] (clamped to the current document and size),
  /// e.g. to undo the pan a resting palm caused before the pen landed.
  void restore(ViewportSnapshot snapshot) {
    final z = snapshot.zoom.clamp(minZoom, maxZoom).toDouble();
    final oldZoom = _zoom, oldOffset = _offset;
    _zoom = z;
    _offset = _clamp(snapshot.offset);
    if (_zoom != oldZoom || _offset != oldOffset) _publish();
  }

  // ---------------------------------------------------------------------------
  // Coordinate conversion

  /// Viewport-local pixels → document space.
  Offset localToDoc(Offset local) => (local - _offset) / scale;

  /// Document space → viewport-local pixels.
  Offset docToLocal(Offset doc) => doc * scale + _offset;

  /// Viewport-local pixels → page points of page [pageIndex] (not clamped).
  Vec2 localToPage(Offset local, int pageIndex) {
    final d = localToDoc(local);
    final r = _layout.rects[pageIndex];
    return Vec2(d.dx - r.left, d.dy - r.top);
  }

  /// Page points of page [pageIndex] → viewport-local pixels.
  Offset pageToLocal(int pageIndex, Vec2 p) {
    final r = _layout.rects[pageIndex];
    return docToLocal(Offset(r.left + p.x, r.top + p.y));
  }

  /// The page under the viewport-local position, or null over gaps and
  /// margins. [slopPx] grows each page by that many pixels.
  PageHit? hitTestLocal(Offset local, {double slopPx = 0}) {
    if (_layout.isEmpty) return null;
    final d = localToDoc(local);
    final i = _layout.pageIndexAt(d, slop: slopPx / scale);
    if (i < 0) return null;
    final r = _layout.rects[i];
    return PageHit(
      pageIndex: i,
      pageId: _layout.pageIds[i],
      point: Vec2(d.dx - r.left, d.dy - r.top),
    );
  }

  /// Global position → the page under it (see [hitTestLocal]). Null when
  /// the document view isn't laid out or the position isn't on a page.
  PageHit? globalToPage(Offset global, {double slopPx = 0}) {
    final box = _box?.call();
    if (box == null || !box.hasSize) return null;
    return hitTestLocal(box.globalToLocal(global), slopPx: slopPx);
  }

  /// Page point → global position, or null when not laid out.
  Offset? pageToGlobal(int pageIndex, Vec2 p) {
    final box = _box?.call();
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(pageToLocal(pageIndex, p));
  }

  /// Rectangle of page [index] in viewport-local pixels.
  Rect pageRectLocal(int index) {
    final r = _layout.rects[index];
    final s = scale;
    return Rect.fromLTWH(
        r.left * s + _offset.dx, r.top * s + _offset.dy, r.width * s, r.height * s);
  }

  /// The visible part of the document, in document space.
  Rect get visibleDocRect {
    if (!hasSize) return Rect.zero;
    final tl = localToDoc(Offset.zero);
    return Rect.fromLTWH(tl.dx, tl.dy, _viewportSize.width / scale,
        _viewportSize.height / scale);
  }

  /// Pages intersecting the visible area grown by [cacheExtent] viewport
  /// heights above and below.
  PageRange? computeVisibleRange() {
    if (!hasSize) return null;
    final v = visibleDocRect;
    final extra = v.height * cacheExtent;
    return _layout.rangeBetween(v.top - extra, v.bottom + extra);
  }

  /// The page owning the document y at the viewport's vertical centre.
  int computeCurrentPage() {
    if (_layout.isEmpty) return 0;
    if (!hasSize) return _pendingJump?.clamp(0, _layout.length - 1) ?? 0;
    final y = localToDoc(Offset(0, _viewportSize.height / 2)).dy;
    return _layout.pageIndexAtY(y);
  }

  // ---------------------------------------------------------------------------
  // Internals

  /// Keeps the document inside the viewport: centred horizontally when it
  /// is narrower than the viewport, otherwise its edges may not pass the
  /// side margins; vertically it starts at [topMargin] and can scroll until
  /// its end is [bottomMargin] above the viewport bottom.
  Offset _clamp(Offset o) {
    if (!hasSize) return o;
    final s = scale;
    final vw = _viewportSize.width, vh = _viewportSize.height;
    final cw = _layout.width * s, ch = _layout.height * s;
    final double x;
    if (cw + 2 * sideMargin <= vw + 0.01) {
      x = (vw - cw) / 2;
    } else {
      x = o.dx.clamp(vw - sideMargin - cw, sideMargin).toDouble();
    }
    final minY = vh - bottomMargin - ch;
    final y = minY >= topMargin
        ? topMargin
        : o.dy.clamp(minY, topMargin).toDouble();
    return Offset(x, y);
  }

  void _consumePendingJump() {
    final j = _pendingJump;
    if (j == null || _layout.isEmpty || !hasSize) return;
    _pendingJump = null;
    _offset = _offsetShowingPage(j.clamp(0, _layout.length - 1));
  }

  /// Offset that puts the top of page [i] at [topMargin], centred
  /// horizontally (clamped).
  Offset _offsetShowingPage(int i) {
    final r = _layout.rects[i];
    final s = scale;
    return _clamp(Offset(
      (_viewportSize.width - r.width * s) / 2 - r.left * s,
      topMargin - r.top * s,
    ));
  }

  void _publish() {
    if (_disposed) return;
    notifyListeners();
    _visibleRange.value = computeVisibleRange();
    _currentPage.value = computeCurrentPage();
    _scheduleSettle();
  }

  void _scheduleSettle() {
    if (scale == _settledScale.value) {
      _settleTimer?.cancel();
      _settleTimer = null;
      return;
    }
    _settleTimer?.cancel();
    _settleTimer = Timer(settleDelay, () {
      _settleTimer = null;
      if (!_disposed) _settledScale.value = scale;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _settleTimer?.cancel();
    _visibleRange.dispose();
    _currentPage.dispose();
    _settledScale.dispose();
    super.dispose();
  }
}
