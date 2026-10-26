import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'pdf_page_cache.dart';

/// Tuning for [PdfPageBackground].
abstract final class PdfBackgroundTuning {
  /// How long the zoom must stay still before a sharp render starts.
  static const Duration settleDelay = Duration(milliseconds: 250);

  /// Width of the quick first render of a page nobody has rendered yet.
  static const int previewWidthPx = 384;

  /// Render widths are rounded up to a multiple of this, so tiny zoom
  /// changes reuse the cached image instead of re-rendering.
  static const int widthStepPx = 128;

  /// Largest full-page image (pixels). Beyond this zoom the whole page stays
  /// at this resolution and a sharp patch is rendered for the visible part.
  static const int maxFullPagePixels = 12 * 1000 * 1000;

  /// Never render wider than this, even for the visible patch.
  static const int maxRenderWidthPx = 16384;

  /// Extra margin around the visible area included in the sharp patch (as a
  /// fraction of the visible size), so small pans stay sharp.
  static const double patchMargin = 0.15;

  /// How often the visible area is checked while zoomed past the full-page
  /// limit. Cheap: one transform lookup.
  static const Duration viewportCheckInterval = Duration(milliseconds: 300);

  /// A cached image counts as sharp enough down to this fraction of the
  /// wanted width.
  static const double sharpEnough = 0.95;

  /// A displayed image more than this many times the wanted width is
  /// replaced by a smaller render to free memory after zooming out.
  static const double tooLarge = 2.2;
}

/// The PDF page background of one notebook page.
///
/// Paints a white page immediately, a low-resolution render as soon as it
/// is ready, and a sharp render at device-pixel resolution for the current
/// [scale] once the zoom has settled for
/// [PdfBackgroundTuning.settleDelay]. Rendering happens off the UI thread
/// (PDFium) and never blocks a frame.
///
/// Sizing: fills tight constraints (the usual case: the editor sizes the
/// page), otherwise takes `pageWidthPt * scale` × `pageHeightPt * scale`
/// logical pixels.
class PdfPageBackground extends StatefulWidget {
  const PdfPageBackground({
    super.key,
    required this.pdfPath,
    required this.pageIndex,
    required this.pageWidthPt,
    required this.pageHeightPt,
    required this.scale,
    this.cache,
  });

  /// The notebook's `source.pdf`.
  final String pdfPath;

  /// 0-based page index in [pdfPath].
  final int pageIndex;

  /// The page size in points as displayed (from the page's metadata).
  final double pageWidthPt;
  final double pageHeightPt;

  /// Logical pixels per point on screen, zoom included.
  final double scale;

  /// Defaults to [PdfPageCache.shared].
  final PdfPageCache? cache;

  @override
  State<PdfPageBackground> createState() => _PdfPageBackgroundState();
}

class _PdfPageBackgroundState extends State<PdfPageBackground> {
  PdfPageImage? _base;
  PdfPageImage? _patch;

  PdfRenderTicket? _previewTicket;
  PdfRenderTicket? _sharpTicket;
  PdfRenderRegion? _sharpRegion;
  PdfRenderTicket? _patchTicket;
  PdfRenderRegion? _patchRegion;

  Timer? _settleTimer;
  Timer? _viewportTimer;
  Rect? _lastVisible;
  double _devicePixelRatio = 1;
  bool _started = false;

  PdfPageCache get _cache => widget.cache ?? PdfPageCache.shared;

  double get _aspect => widget.pageWidthPt > 0 && widget.pageHeightPt > 0
      ? widget.pageHeightPt / widget.pageWidthPt
      : 842 / 595;

  @override
  void initState() {
    super.initState();
    _cache.retainDocument(widget.pdfPath);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    if (!_started) {
      _started = true;
      _devicePixelRatio = dpr;
      _startPage();
    } else if (dpr != _devicePixelRatio) {
      _devicePixelRatio = dpr;
      _scheduleSettle();
    }
  }

  @override
  void didUpdateWidget(PdfPageBackground old) {
    super.didUpdateWidget(old);
    final oldCache = old.cache ?? PdfPageCache.shared;
    if (old.pdfPath != widget.pdfPath ||
        old.pageIndex != widget.pageIndex ||
        !identical(oldCache, _cache)) {
      _cancelAll();
      oldCache.releaseDocument(old.pdfPath);
      _cache.retainDocument(widget.pdfPath);
      _patch?.dispose();
      _patch = null;
      _startPage();
    } else if (old.scale != widget.scale ||
        old.pageWidthPt != widget.pageWidthPt ||
        old.pageHeightPt != widget.pageHeightPt) {
      // The running sharp render is for the old zoom: drop it and wait for
      // the zoom to settle.
      _cancelSharp();
      _cancelPatch();
      _scheduleSettle();
    }
  }

  @override
  void dispose() {
    _cancelAll();
    _base?.dispose();
    _patch?.dispose();
    _base = null;
    _patch = null;
    _cache.releaseDocument(widget.pdfPath);
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------

  /// Shows whatever is cached, asks for a quick preview if nothing is, and
  /// schedules the sharp render.
  ///
  /// Called from didChangeDependencies / didUpdateWidget, which are always
  /// followed by a build, so state is assigned without setState.
  void _startPage() {
    _base?.dispose();
    _base = _cache.largestCached(widget.pdfPath, widget.pageIndex);
    if (_base == null) {
      final width =
          math.min(PdfBackgroundTuning.previewWidthPx, _fullPageWidthPx());
      final ticket = _cache.request(
          widget.pdfPath, widget.pageIndex, _fullRegion(width),
          priority: PdfRenderPriority.preview);
      _previewTicket = ticket;
      unawaited(ticket.result.then((img) {
        if (!identical(_previewTicket, ticket)) {
          img?.dispose();
          return;
        }
        _previewTicket = null;
        // A sharper image may have arrived first.
        if (img != null &&
            (_base == null ||
                _base!.region.fullWidth < img.region.fullWidth)) {
          _replaceBase(img);
        } else {
          img?.dispose();
        }
      }));
    }
    _scheduleSettle();
  }

  void _scheduleSettle() {
    _settleTimer?.cancel();
    _settleTimer = Timer(PdfBackgroundTuning.settleDelay, _onSettled);
  }

  /// The zoom is still: make the full-page image match it, and handle the
  /// sharp visible-area patch when zoomed past the full-page limit.
  void _onSettled() {
    if (!mounted) return;
    final wanted = _wantedWidthPx();
    final full = _fullPageWidthPx();
    final base = _base;
    final baseWidth = base?.region.fullWidth ?? 0;
    final sharpEnough = baseWidth >= full * PdfBackgroundTuning.sharpEnough;
    final tooLarge = baseWidth > full * PdfBackgroundTuning.tooLarge;
    if (!sharpEnough || tooLarge) {
      final cached = _cache.cachedFullPage(
        widget.pdfPath,
        widget.pageIndex,
        minWidth: (full * PdfBackgroundTuning.sharpEnough).floor(),
        maxWidth: (full * PdfBackgroundTuning.tooLarge).floor(),
      );
      if (cached != null) {
        _replaceBase(cached);
      } else {
        _requestSharp(_fullRegion(full));
      }
    }

    if (wanted > full * 1.05) {
      _viewportTimer ??= Timer.periodic(
          PdfBackgroundTuning.viewportCheckInterval, (_) => _checkViewport());
      _lastVisible = _visibleRect();
      _updatePatch(_lastVisible);
    } else {
      _viewportTimer?.cancel();
      _viewportTimer = null;
      _cancelPatch();
      _replacePatch(null);
    }
  }

  void _requestSharp(PdfRenderRegion region) {
    if (_sharpRegion == region && _sharpTicket != null) return;
    _cancelSharp();
    final ticket = _cache.request(widget.pdfPath, widget.pageIndex, region);
    _sharpTicket = ticket;
    _sharpRegion = region;
    unawaited(ticket.result.then((img) {
      if (!identical(_sharpTicket, ticket)) {
        img?.dispose();
        return;
      }
      _sharpTicket = null;
      _sharpRegion = null;
      if (img == null) return;
      _replaceBase(img);
      _previewTicket?.cancel();
      _previewTicket = null;
    }));
  }

  /// Runs while zoomed past the full-page limit: once the visible area has
  /// stopped moving and is not covered by the current patch, render a new
  /// one.
  void _checkViewport() {
    if (!mounted || _settleTimer?.isActive == true) return;
    final visible = _visibleRect();
    final last = _lastVisible;
    _lastVisible = visible;
    if (visible == null || last == null) return;
    final still = (visible.left - last.left).abs() < 1 &&
        (visible.top - last.top).abs() < 1 &&
        (visible.right - last.right).abs() < 1 &&
        (visible.bottom - last.bottom).abs() < 1;
    if (still) _updatePatch(visible);
  }

  void _updatePatch(Rect? visible) {
    final size = _layoutSize();
    if (visible == null || size == null) {
      _cancelPatch();
      return;
    }
    final wanted = _wantedWidthPx();
    if (_covers(_patch?.region, visible, size, wanted) ||
        _covers(_patchRegion, visible, size, wanted)) {
      return;
    }
    final region = _patchRegionFor(visible, size, wanted);
    if (region == null) return;
    _cancelPatch();
    final ticket = _cache.request(widget.pdfPath, widget.pageIndex, region);
    _patchTicket = ticket;
    _patchRegion = region;
    unawaited(ticket.result.then((img) {
      if (!identical(_patchTicket, ticket)) {
        img?.dispose();
        return;
      }
      _patchTicket = null;
      _patchRegion = null;
      if (img != null) _replacePatch(img);
    }));
  }

  /// Whether [region] (a patch at [wantedWidth]) contains [visible].
  bool _covers(
      PdfRenderRegion? region, Rect visible, Size size, int wantedWidth) {
    if (region == null || region.fullWidth != wantedWidth) return false;
    final rect = _regionToLocal(region, size);
    return rect.inflate(1).contains(visible.topLeft) &&
        rect.inflate(1).contains(visible.bottomRight);
  }

  /// A patch region at [wantedWidth] covering [visible] plus a margin, in
  /// full-page pixels, bounded to about the screen's pixel count.
  PdfRenderRegion? _patchRegionFor(Rect visible, Size size, int wantedWidth) {
    final fullW = wantedWidth;
    final fullH = math.max(1, (wantedWidth * _aspect).round());
    final kx = fullW / size.width, ky = fullH / size.height;
    final mx = visible.width * PdfBackgroundTuning.patchMargin;
    final my = visible.height * PdfBackgroundTuning.patchMargin;
    final withMargin = Rect.fromLTRB(visible.left - mx, visible.top - my,
            visible.right + mx, visible.bottom + my)
        .intersect(Offset.zero & size);
    final left = (withMargin.left * kx).floor().clamp(0, fullW - 1);
    final top = (withMargin.top * ky).floor().clamp(0, fullH - 1);
    final right = (withMargin.right * kx).ceil().clamp(left + 1, fullW);
    final bottom = (withMargin.bottom * ky).ceil().clamp(top + 1, fullH);
    final w = right - left, h = bottom - top;
    if (w <= 0 || h <= 0) return null;
    return PdfRenderRegion(
        fullWidth: fullW, fullHeight: fullH, x: left, y: top, width: w, height: h);
  }

  Rect _regionToLocal(PdfRenderRegion r, Size size) {
    final kx = size.width / r.fullWidth, ky = size.height / r.fullHeight;
    return Rect.fromLTWH(r.x * kx, r.y * ky, r.width * kx, r.height * ky);
  }

  // ---------------------------------------------------------------------
  // Geometry
  // ---------------------------------------------------------------------

  /// Device pixels across the page at the current zoom, rounded up to the
  /// width step.
  int _wantedWidthPx() {
    final px = widget.pageWidthPt * widget.scale * _devicePixelRatio;
    final step = PdfBackgroundTuning.widthStepPx;
    final rounded = px.isFinite ? ((px / step).ceil() * step) : step;
    return rounded.clamp(step, PdfBackgroundTuning.maxRenderWidthPx);
  }

  /// Width of the full-page render: [_wantedWidthPx] limited to
  /// [PdfBackgroundTuning.maxFullPagePixels].
  int _fullPageWidthPx() {
    final limit =
        math.sqrt(PdfBackgroundTuning.maxFullPagePixels / _aspect).floor();
    return math.max(1, math.min(_wantedWidthPx(), limit));
  }

  PdfRenderRegion _fullRegion(int width) => PdfRenderRegion(
      fullWidth: width, fullHeight: math.max(1, (width * _aspect).round()));

  Size? _layoutSize() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return null;
    return box.size;
  }

  /// The part of this page on screen, in local logical pixels, or null when
  /// the page is off screen.
  Rect? _visibleRect() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final screen = MediaQuery.maybeSizeOf(context);
    if (screen == null || screen.isEmpty) return null;
    final toScreen = box.getTransformTo(null);
    final toLocal = Matrix4.tryInvert(toScreen);
    if (toLocal == null) return null;
    final local = MatrixUtils.transformRect(toLocal, Offset.zero & screen);
    final visible = local.intersect(Offset.zero & box.size);
    if (visible.width <= 0 || visible.height <= 0) return null;
    return visible;
  }

  // ---------------------------------------------------------------------
  // State helpers
  // ---------------------------------------------------------------------

  void _replaceBase(PdfPageImage? img) {
    final old = _base;
    if (identical(old, img)) return;
    if (mounted) {
      setState(() => _base = img);
    } else {
      _base = img;
    }
    old?.dispose();
  }

  void _replacePatch(PdfPageImage? img) {
    final old = _patch;
    if (identical(old, img)) return;
    if (mounted) {
      setState(() => _patch = img);
    } else {
      _patch = img;
    }
    old?.dispose();
  }

  void _cancelSharp() {
    _sharpTicket?.cancel();
    _sharpTicket = null;
    _sharpRegion = null;
  }

  void _cancelPatch() {
    _patchTicket?.cancel();
    _patchTicket = null;
    _patchRegion = null;
  }

  void _cancelAll() {
    _settleTimer?.cancel();
    _settleTimer = null;
    _viewportTimer?.cancel();
    _viewportTimer = null;
    _previewTicket?.cancel();
    _previewTicket = null;
    _cancelSharp();
    _cancelPatch();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(widget.pageWidthPt * widget.scale,
            widget.pageHeightPt * widget.scale),
        painter: _PdfPagePainter(_base, _patch),
      ),
    );
  }
}

class _PdfPagePainter extends CustomPainter {
  _PdfPagePainter(this.base, this.patch);

  final PdfPageImage? base;
  final PdfPageImage? patch;

  static final Paint _white = Paint()..color = const Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final page = Offset.zero & size;
    canvas.drawRect(page, _white);
    final b = base;
    if (b != null) {
      _drawImage(canvas, b.image, page);
    }
    final p = patch;
    if (p != null) {
      final r = p.region;
      final kx = size.width / r.fullWidth, ky = size.height / r.fullHeight;
      _drawImage(canvas, p.image,
          Rect.fromLTWH(r.x * kx, r.y * ky, r.width * kx, r.height * ky));
    }
  }

  void _drawImage(Canvas canvas, ui.Image image, Rect dst) {
    final src = Rect.fromLTWH(
        0, 0, image.width.toDouble(), image.height.toDouble());
    // Medium uses mipmaps, which keeps downscaled pages crisp instead of
    // aliased.
    canvas.drawImageRect(
        image, src, dst, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_PdfPagePainter old) =>
      !identical(old.base?.image, base?.image) ||
      !identical(old.patch?.image, patch?.image);
}
