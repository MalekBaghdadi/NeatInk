import 'dart:ui';

import '../../../document/notebook_meta.dart';

/// An inclusive range of page indices.
class PageRange {
  const PageRange(this.first, this.last) : assert(first <= last);

  final int first;
  final int last;

  int get length => last - first + 1;

  bool contains(int index) => index >= first && index <= last;

  @override
  bool operator ==(Object other) =>
      other is PageRange && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);

  @override
  String toString() => 'PageRange($first..$last)';
}

/// Where each page sits in the document: pages are stacked top to bottom,
/// [gap] points apart, each centred horizontally in a column as wide as the
/// widest page.
///
/// "Document space" is measured in page points with the origin at the top
/// left of the column; the viewport maps it to the screen with one uniform
/// scale and a translation.
class PageLayout {
  factory PageLayout(List<PageMeta> pages, {double gap = 12}) {
    var width = 0.0;
    for (final p in pages) {
      if (p.width > width) width = p.width;
    }
    final rects = <Rect>[];
    var y = 0.0;
    for (var i = 0; i < pages.length; i++) {
      final p = pages[i];
      if (i > 0) y += gap;
      rects.add(Rect.fromLTWH((width - p.width) / 2, y, p.width, p.height));
      y += p.height;
    }
    return PageLayout._(
      List.unmodifiable(rects),
      List.unmodifiable([for (final p in pages) p.id]),
      width,
      y,
      gap,
    );
  }

  PageLayout._(this.rects, this.pageIds, this.width, this.height, this.gap);

  static final PageLayout empty = PageLayout(const []);

  /// Page rectangles in document space, in page order.
  final List<Rect> rects;

  /// Page ids, parallel to [rects].
  final List<String> pageIds;

  /// Document width (the widest page) and height (all pages plus gaps).
  final double width;
  final double height;
  final double gap;

  int get length => rects.length;
  bool get isEmpty => rects.isEmpty;
  Size get size => Size(width, height);

  int indexOfPage(String pageId) => pageIds.indexOf(pageId);

  /// The page "owning" document y: each page owns its own rectangle plus
  /// half of the gaps above and below it. Clamped to the first/last page.
  /// Returns -1 when there are no pages.
  int pageIndexAtY(double y) {
    if (rects.isEmpty) return -1;
    // Binary search for the first page whose lower boundary (bottom + half
    // gap) is at or below y.
    var lo = 0, hi = rects.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (rects[mid].bottom + gap / 2 < y) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// The pages whose rectangles intersect the vertical band
  /// [top, bottom] (document space), or null when none do.
  PageRange? rangeBetween(double top, double bottom) {
    if (rects.isEmpty || bottom < top) return null;
    // First page with bottom >= top.
    var lo = 0, hi = rects.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (rects[mid].bottom < top) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final first = lo;
    if (first >= rects.length || rects[first].top > bottom) return null;
    // Last page with top <= bottom.
    lo = first;
    hi = rects.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (rects[mid].top <= bottom) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return PageRange(first, lo - 1);
  }

  /// Index of the page containing the document point [p] (inclusive edges,
  /// grown by [slop] points), or -1.
  int pageIndexAt(Offset p, {double slop = 0}) {
    final i = pageIndexAtY(p.dy);
    if (i < 0) return -1;
    return _containsInclusive(rects[i].inflate(slop), p) ? i : -1;
  }

  // Rect.contains excludes the right and bottom edges; a pen resting exactly
  // on the page edge should still count as on the page.
  static bool _containsInclusive(Rect r, Offset p) =>
      p.dx >= r.left && p.dx <= r.right && p.dy >= r.top && p.dy <= r.bottom;
}
