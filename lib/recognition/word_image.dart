import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../beautify/resample.dart';
import '../ink/ink_point.dart';
import '../ink/ink_rect.dart';
import '../ink/stroke.dart';
import 'stroke_grouping.dart';

/// Height of the recogniser's input image in pixels (fixed by the model).
const int wordImageHeight = 48;

/// Narrowest and widest word image. The width follows the word's aspect
/// ratio; a word wider than [wordImageMaxWidth] is squeezed horizontally.
const int wordImageMinWidth = 16;
const int wordImageMaxWidth = 800;

/// The width of the ink in pixels at [wordImageHeight] pixels of image
/// height. THE tuning constant of the rendering: the model reads thin pen
/// strokes (about 1.5 to 2 px at this height) slightly better than thick
/// ones.
const double wordImageStrokePx = 1.8;

/// Width of the old fixed 128x32 input.
@Deprecated('Word images have a variable width: use WordImage.width.')
const int wordImageWidth = 128;

/// Tuning numbers for [renderWordImage].
class WordImageConfig {
  const WordImageConfig({
    this.strokePx = wordImageStrokePx,
    this.minWidth = wordImageMinWidth,
    this.maxWidth = wordImageMaxWidth,
    this.maxScale = 10.0,
    this.minExtentFactor = 0.3,
  });

  /// Pen width in image pixels (see [wordImageStrokePx]).
  final double strokePx;

  final int minWidth;
  final int maxWidth;

  /// Largest enlargement in pixels per point. A lone dot or dash is not
  /// blown up to fill the image; it stays small, centred on white.
  final double maxScale;

  /// A word is taken to be at least this many x-heights wide and high.
  final double minExtentFactor;
}

/// A word rendered for the recogniser.
class WordImage {
  WordImage({
    required this.pixels,
    required this.scale,
    required this.strokeWidthPx,
    int? width,
    this.height = wordImageHeight,
  }) : width = width ?? pixels.length ~/ height;

  /// [width] x [height] bytes, row-major, 0 = ink and 255 = paper.
  final Uint8List pixels;

  /// Image size in pixels; [height] is [wordImageHeight].
  final int width;
  final int height;

  /// Pixels per page point (vertically).
  final double scale;

  final double strokeWidthPx;
}

/// Draws strokes already placed in image pixel space (black ink, width
/// `Stroke.size` px) onto a white [width] x [height] canvas and returns the
/// grey pixels. Injectable because `Picture.toImage` never completes under
/// `flutter_tester`.
abstract class WordImageRenderer {
  Future<Uint8List> rasterize(List<Stroke> strokes, {required int width, int height = wordImageHeight});
}

/// Renders with `dart:ui`: every stroke is a round-capped polyline of its
/// width, anti-aliased.
class UiWordImageRenderer implements WordImageRenderer {
  const UiWordImageRenderer();

  @override
  Future<Uint8List> rasterize(List<Stroke> strokes, {required int width, int height = wordImageHeight}) async {
    final recorder = ui.PictureRecorder();
    final bounds = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final canvas = ui.Canvas(recorder, bounds);
    canvas.drawRect(bounds, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    for (final s in strokes) {
      final pts = [
        for (final p in s.points)
          if (p.isFinite) p,
      ];
      if (pts.isEmpty) continue;
      final line = ui.Paint()
        ..color = const ui.Color(0xFF000000)
        ..isAntiAlias = true
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = s.size
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round;
      final first = pts.first;
      final path = ui.Path()..moveTo(first.x, first.y);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].x, pts[i].y);
      }
      if (pts.length == 1) path.lineTo(first.x, first.y); // a dot
      canvas.drawPath(path, line);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final out = Uint8List(width * height);
      if (data != null) {
        for (var i = 0; i < out.length; i++) {
          out[i] = data.getUint8(i * 4);
        }
      } else {
        out.fillRange(0, out.length, 255);
      }
      return out;
    } finally {
      image.dispose();
      picture.dispose();
    }
  }
}

/// Pure-Dart rasteriser: every segment is a capsule of the stroke's width,
/// anti-aliased by distance. Used by tests (and usable in isolates).
class PolylineWordImageRenderer implements WordImageRenderer {
  const PolylineWordImageRenderer();

  @override
  Future<Uint8List> rasterize(List<Stroke> strokes, {required int width, int height = wordImageHeight}) async {
    final coverage = Float64List(width * height);
    for (final s in strokes) {
      final pts = [
        for (final p in s.points)
          if (p.isFinite) p,
      ];
      if (pts.isEmpty) continue;
      final r = s.size / 2;
      if (pts.length == 1) {
        _capsule(coverage, width, height, pts[0].x, pts[0].y, pts[0].x, pts[0].y, r);
        continue;
      }
      for (var i = 1; i < pts.length; i++) {
        _capsule(coverage, width, height, pts[i - 1].x, pts[i - 1].y, pts[i].x, pts[i].y, r);
      }
    }
    final out = Uint8List(coverage.length);
    for (var i = 0; i < out.length; i++) {
      out[i] = (255 - 255 * coverage[i].clamp(0.0, 1.0)).round();
    }
    return out;
  }

  void _capsule(Float64List cov, int width, int height, double x0, double y0, double x1, double y1, double r) {
    final reach = r + 1;
    final minX = math.max(0, (math.min(x0, x1) - reach).floor());
    final maxX = math.min(width - 1, (math.max(x0, x1) + reach).ceil());
    final minY = math.max(0, (math.min(y0, y1) - reach).floor());
    final maxY = math.min(height - 1, (math.max(y0, y1) + reach).ceil());
    final dx = x1 - x0, dy = y1 - y0;
    final len2 = dx * dx + dy * dy;
    for (var py = minY; py <= maxY; py++) {
      for (var px = minX; px <= maxX; px++) {
        final cx = px + 0.5, cy = py + 0.5;
        var t = len2 == 0 ? 0.0 : ((cx - x0) * dx + (cy - y0) * dy) / len2;
        t = t.clamp(0.0, 1.0);
        final ex = cx - (x0 + t * dx), ey = cy - (y0 + t * dy);
        final d = math.sqrt(ex * ex + ey * ey);
        // Full coverage inside the pen radius, a 1 px linear edge outside.
        final c = (r + 0.5 - d).clamp(0.0, 1.0);
        final i = py * width + px;
        if (c > cov[i]) cov[i] = c;
      }
    }
  }
}

/// Deskews [word] by its line's baseline slope and renders it as thin dark
/// ink on white, [wordImageHeight] pixels high and as wide as its aspect
/// ratio asks (at least [WordImageConfig.minWidth], at most
/// [WordImageConfig.maxWidth]).
///
/// The ink's bounding box fills the image: no white border (the model reads
/// padded handwriting worse and answers in capitals). Only half a pen width
/// is kept free on every side so the outermost strokes are not clipped, and
/// tiny marks (dots, commas) stay small and centred.
Future<WordImage> renderWordImage(
  WordGroup word, {
  WordImageRenderer renderer = const UiWordImageRenderer(),
  WordImageConfig config = const WordImageConfig(),
}) async {
  final phi = math.atan(word.baselineSlope);
  final c = math.cos(phi), s = math.sin(phi);
  final cx = word.bounds.center.x, cy = word.bounds.center.y;

  // Levelled coordinates (rotation by -phi about the word centre).
  double lx(InkPoint p) => (p.x - cx) * c + (p.y - cy) * s;
  double ly(InkPoint p) => -(p.x - cx) * s + (p.y - cy) * c;

  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  for (final st in word.strokes) {
    for (final p in st.points) {
      if (!p.isFinite) continue;
      final x = lx(p), y = ly(p);
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (minX == double.infinity) {
    final blank = await renderer.rasterize(const [], width: config.minWidth);
    return WordImage(pixels: blank, width: config.minWidth, scale: 1, strokeWidthPx: 0);
  }

  final xh = word.xHeight ?? math.max(maxX - minX, maxY - minY).clamp(1.0, double.infinity) / 3;
  final w = math.max(maxX - minX, config.minExtentFactor * xh);
  final h = math.max(maxY - minY, config.minExtentFactor * xh);

  final stroke = config.strokePx;
  const height = wordImageHeight;
  // Pixels per point: the ink (plus half a pen width on each side) fills the
  // image height.
  final sy = math.min(config.maxScale, (height - stroke) / h);
  var sx = sy;
  var width = (w * sx + stroke).round();
  if (width > config.maxWidth) {
    // Very long word: squeeze it horizontally into the widest image.
    width = config.maxWidth;
    sx = (width - stroke) / w;
  }
  if (width < config.minWidth) width = config.minWidth;

  final midX = (minX + maxX) / 2, midY = (minY + maxY) / 2;
  final placed = <Stroke>[
    for (final st in word.strokes)
      () {
        final pts = [
          for (final p in st.points)
            if (p.isFinite)
              InkPoint(
                width / 2 + (lx(p) - midX) * sx,
                height / 2 + (ly(p) - midY) * sy,
                0.5,
                p.t,
              ),
        ];
        return Stroke(
          id: st.id,
          tool: StrokeTool.pen,
          color: 0xFF000000,
          size: stroke,
          raw: pts,
        );
      }(),
  ];
  return WordImage(
    pixels: await renderer.rasterize(placed, width: width, height: height),
    width: width,
    scale: sy,
    strokeWidthPx: stroke,
  );
}

// ---------------------------------------------------------------------------
// Whole lines
// ---------------------------------------------------------------------------

/// Tuning numbers for [renderLineImages].
class LineImageConfig {
  const LineImageConfig({
    this.strokePx = 2.0,
    this.marginFrac = 0.15,
    this.minWidth = 16,
    this.maxWidth = 2400,
    this.maxScale = 10.0,
    this.snapDots = false,
    this.minExtentFactor = 0.3,
    this.dotMaxFactor = 0.6,
    this.dotFloatFactor = 0.7,
    this.barMinWidthFactor = 0.35,
    this.barFlatness = 0.35,
    this.stemMinFactor = 0.25,
    this.stemMaxWidthFactor = 1.2,
    this.stemMaxAspect = 0.6,
    this.stemTopFraction = 0.2,
    this.markFactor = 0.6,
    this.reachX = 1.2,
    this.reachY = 2.0,
    this.snapReachY = 3.0,
    this.stretchX = 1.0,
    this.xHeightWidthPx = 0,
    this.maxStretchX = 1.0,
  });

  /// Pen width in image pixels (at 48 px of image height).
  final double strokePx;

  /// Horizontal stretch: the image is drawn this many times wider than its
  /// vertical scale asks for. The model emits one output frame per 8 px of
  /// width and needs at least one frame per letter; a compact hand with tall
  /// ascenders and descenders gets so small a scale (fitting the line's
  /// height into 48 px) that whole words fell through (see
  /// [xHeightWidthPx]).
  final double stretchX;

  /// Adaptive stretch: when the line's x-height is fewer than this many
  /// pixels at the vertical scale, the image is stretched horizontally until
  /// one x-height spans this many pixels, at most [maxStretchX] times (and
  /// never less than [stretchX]). 0 switches it off.
  final double xHeightWidthPx;

  /// Upper limit of the adaptive stretch.
  final double maxStretchX;

  /// White margin on every side of the ink, as a fraction of the image
  /// height. The recogniser reads a line with some air around it better
  /// than one that touches the edges.
  final double marginFrac;

  final int minWidth;

  /// A line wider than this (in pixels, at the scale that fits its height)
  /// is cut at its widest gaps into several images. Lines are never
  /// squeezed.
  final int maxWidth;

  /// Largest enlargement in pixels per point. A lone dot or dash is not
  /// blown up to fill the image; it stays small, centred on white.
  final double maxScale;

  /// For images made only for recognition: move every i-dot sideways so it
  /// sits over the stem under it. This writer puts the dot 3 to 8 points
  /// left of the stem, which makes the model miss the 'i'. Ink on the page
  /// is never moved; only the rendering is, and the image is laid out as if
  /// nothing had moved (same size, scale and alignment).
  final bool snapDots;

  /// The ink is taken to be at least this many x-heights high when the
  /// scale is chosen, so a flat scribble is not enlarged to fill the image.
  final double minExtentFactor;

  /// A stroke whose box diagonal is at most this many x-heights is a dot
  /// candidate for [snapDots] ...
  final double dotMaxFactor;

  /// ... when it also floats: its lower edge is at least this many x-heights
  /// above the baseline (an i-dot is above the x-height, inside the letters
  /// there is no room for one).
  final double dotFloatFactor;

  /// A mark at least this many x-heights wide ...
  final double barMinWidthFactor;

  /// ... and at most this many times as high as it is wide is a bar (the
  /// cross stroke of a `t`), not a dot: snapping moved Mariam's high t-bars
  /// onto the i next to them.
  final double barFlatness;

  /// A stem under a dot is at least this many x-heights tall (some writers
  /// make the i a short tick: Mariam's are about a third of an x-height) ...
  final double stemMinFactor;

  /// ... at most this many x-heights wide (not a whole letter blob) ...
  final double stemMaxWidthFactor;

  /// ... and upright: at most this wide for its height. Without it a round
  /// letter next to a short i (the `o` of "depression") passed for the stem
  /// and took the i's dot, which the model then read as a full stop.
  final double stemMaxAspect;

  /// The stem's x is the mean x of the samples in this top fraction of its
  /// height (the top of an i, whatever its tail does).
  final double stemTopFraction;

  /// In [assignStrokesToSpans]: strokes whose box diagonal is at most this
  /// many x-heights are marks (dots, commas) that follow the stroke they
  /// belong to instead of being placed by their own overlap.
  final double markFactor;

  /// How far a dot may be from the stem or stroke it belongs to: this many
  /// x-heights sideways and [reachY] vertically (see [nearestSupport]).
  final double reachX;
  final double reachY;

  /// The vertical reach of [snapDots] (the sideways one is [reachX]). Longer
  /// than [reachY]: a short i-stem can sit well over an x-height under its
  /// dot, and the dot must still go to it rather than to a stem beside it.
  final double snapReachY;
}

/// A line rendered for the recogniser: the whole line (or, for very wide
/// ones, a chunk of it) in one image.
///
/// All the geometry needed to map the model's output back onto the ink is
/// kept: a pixel column [px] corresponds to the levelled x [levelledX], and
/// the strokes drawn in the image are listed in [strokes].
///
/// The levelled frame is the page frame rotated by [angle] about the page
/// origin: `x' = x cos a + y sin a`, `y' = y cos a - x sin a`, so a line of
/// slope `tan a` runs horizontally in it.
class LineImage extends WordImage {
  LineImage({
    required super.pixels,
    required super.scale,
    required super.strokeWidthPx,
    super.width,
    super.height,
    required this.strokes,
    required this.angle,
    required this.originX,
    double? scaleX,
    List<double>? shifts,
  })  : scaleX = scaleX ?? scale,
        shifts = shifts ?? List.filled(strokes.length, 0.0);

  /// Pixels per levelled point horizontally: [scale] times the stretch of
  /// [LineImageConfig.stretchX] / [LineImageConfig.xHeightWidthPx].
  final double scaleX;

  /// The strokes drawn in this image (the original page strokes), in input
  /// order. A stroke cut by a forced chunk boundary is in both chunks.
  final List<Stroke> strokes;

  /// Levelling rotation in radians (`atan` of the line's baseline slope).
  final double angle;

  /// Levelled x, in page points, at pixel column 0.
  final double originX;

  /// Per stroke of [strokes]: how far (levelled points, along the line) it
  /// was moved in this image by `LineImageConfig.snapDots`; mostly zero.
  final List<double> shifts;

  /// Levelled x (page points) at pixel column [px].
  double levelledX(double px) => originX + px / scaleX;

  /// Pixel column of levelled x [x]; the inverse of [levelledX].
  double pixelOf(double x) => (x - originX) * scaleX;
}

/// A stroke in the levelled frame.
class _Levelled {
  _Levelled(this.stroke, this.xs, this.ys)
      : left = xs.reduce(math.min),
        right = xs.reduce(math.max),
        top = ys.reduce(math.min),
        bottom = ys.reduce(math.max);

  final Stroke stroke;
  final List<double> xs;
  final List<double> ys;
  final double left, right, top, bottom;

  /// Sideways shift applied in the rendering (levelled points).
  double shift = 0;

  double get shiftedLeft => left + shift;
  double get shiftedRight => right + shift;

  /// Extent used to lay the image out: the stroke where it was written and
  /// where it was drawn, so a moved dot never changes the size or the
  /// alignment of the image (a rendering with and without
  /// `LineImageConfig.snapDots` then differs only in the dots).
  double get layoutLeft => math.min(left, shiftedLeft);
  double get layoutRight => math.max(right, shiftedRight);
  double get diagonal => math.sqrt((right - left) * (right - left) + (bottom - top) * (bottom - top));
  double get height => bottom - top;
  double get width => right - left;

  LevelBox get box => (left: shiftedLeft, top: top, right: shiftedRight, bottom: bottom);
}

List<_Levelled> _levelStrokes(Iterable<Stroke> strokes, double angle) {
  final c = math.cos(angle), s = math.sin(angle);
  final out = <_Levelled>[];
  for (final st in strokes) {
    final xs = <double>[], ys = <double>[];
    for (final p in st.points) {
      if (!p.isFinite) continue;
      xs.add(p.x * c + p.y * s);
      ys.add(p.y * c - p.x * s);
    }
    if (xs.isEmpty) continue;
    out.add(_Levelled(st, xs, ys));
  }
  return out;
}

/// Renders [line] as ONE image (several only for very wide lines): levelled
/// by the line's baseline slope, thin dark ink on white, [wordImageHeight]
/// pixels high.
///
/// The ink's bounding box is scaled to fill `1 - 2 * marginFrac` of the
/// height (at most [LineImageConfig.maxScale] pixels per point) and sits in
/// the middle of the image, so there is a white margin of
/// `marginFrac * 48` pixels on every side. The width follows the aspect
/// ratio, stretched by [lineStretchX] for small x-heights. A line wider than
/// [LineImageConfig.maxWidth] is cut into chunks at
/// its widest horizontal gaps (between words, as a rule), left to right,
/// each at the same scale and height: the letters are never squeezed.
///
/// Every pen stroke of the line ([RecognizedLine.inkStrokes]) is drawn.
Future<List<LineImage>> renderLineImages(
  RecognizedLine line, {
  WordImageRenderer renderer = const UiWordImageRenderer(),
  LineImageConfig config = const LineImageConfig(),
}) async {
  final angle = math.atan(line.baselineSlope);
  final pieces = _levelStrokes(line.inkStrokes, angle);
  const height = wordImageHeight;
  if (pieces.isEmpty) {
    final blank = await renderer.rasterize(const [], width: config.minWidth);
    return [
      LineImage(
        pixels: blank,
        width: config.minWidth,
        scale: 1,
        strokeWidthPx: 0,
        strokes: const [],
        angle: angle,
        originX: 0,
      ),
    ];
  }
  if (config.snapDots) _snapDots(line, pieces, angle, config);

  var minX = double.infinity, maxX = double.negativeInfinity;
  var minY = double.infinity, maxY = double.negativeInfinity;
  for (final p in pieces) {
    if (p.layoutLeft < minX) minX = p.layoutLeft;
    if (p.layoutRight > maxX) maxX = p.layoutRight;
    if (p.top < minY) minY = p.top;
    if (p.bottom > maxY) maxY = p.bottom;
  }
  final inkHeight = math.max(maxY - minY, config.minExtentFactor * line.xHeight);
  final margin = config.marginFrac * height;
  final scale = math.min(config.maxScale, (height - 2 * margin) / inkHeight);
  final scaleX = scale * lineStretchX(line.xHeight * scale, config);
  final midY = (minY + maxY) / 2;

  // Merge the horizontal extents of the strokes; the gaps between them are
  // where a too wide line may be cut.
  final extents = [
    for (final p in pieces) (start: p.layoutLeft, end: p.layoutRight),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final merged = <({double start, double end})>[];
  for (final e in extents) {
    if (merged.isNotEmpty && e.start <= merged.last.end) {
      if (e.end > merged.last.end) merged[merged.length - 1] = (start: merged.last.start, end: e.end);
    } else {
      merged.add(e);
    }
  }
  final ranges = _chunkRanges(merged, scaleX, margin, config.maxWidth);

  final images = <LineImage>[];
  for (final range in ranges) {
    final inside = [
      for (final p in pieces)
        if (p.shiftedRight >= range.start - 1e-9 && p.shiftedLeft <= range.end + 1e-9) p,
    ];
    final inkWidthPx = (range.end - range.start) * scaleX;
    final width = (inkWidthPx + 2 * margin).round().clamp(config.minWidth, config.maxWidth);
    // Ink centred horizontally (matters when the minimum width pads it).
    final originX = (range.start + range.end) / 2 - width / (2 * scaleX);
    final placed = <Stroke>[
      for (final p in inside)
        Stroke(
          id: p.stroke.id,
          tool: StrokeTool.pen,
          color: 0xFF000000,
          size: config.strokePx,
          raw: [
            for (var i = 0; i < p.xs.length; i++)
              InkPoint(
                (p.xs[i] + p.shift - originX) * scaleX,
                height / 2 + (p.ys[i] - midY) * scale,
                0.5,
                0,
              ),
          ],
        ),
    ];
    images.add(
      LineImage(
        pixels: await renderer.rasterize(placed, width: width, height: height),
        width: width,
        scale: scale,
        scaleX: scaleX,
        strokeWidthPx: config.strokePx,
        strokes: [for (final p in inside) p.stroke],
        angle: angle,
        originX: originX,
        shifts: [for (final p in inside) p.shift],
      ),
    );
  }
  return images;
}

/// How many times wider than tall a line image is drawn, for a line whose
/// x-height is [xHeightPx] pixels at the vertical scale (see
/// [LineImageConfig.stretchX] and [LineImageConfig.xHeightWidthPx]).
double lineStretchX(double xHeightPx, LineImageConfig config) {
  var f = config.stretchX;
  if (config.xHeightWidthPx > 0 && xHeightPx > 0) {
    final adaptive = math.min(config.maxStretchX, config.xHeightWidthPx / xHeightPx);
    if (adaptive > f) f = adaptive;
  }
  return f;
}

/// Cuts the merged ink [extents] (sorted, with gaps between them) into
/// ranges that fit [maxWidth] pixels at [scale] plus two [margin]s: always at
/// the widest gap of a range that is still too wide. A single extent that is
/// too wide on its own has no gap; it is cut in the middle (such writing is
/// larger than any page).
List<({double start, double end})> _chunkRanges(
  List<({double start, double end})> extents,
  double scale,
  double margin,
  int maxWidth,
) {
  if (extents.isEmpty) return const [];
  final lo = extents.first.start, hi = extents.last.end;
  if ((hi - lo) * scale + 2 * margin <= maxWidth) return [(start: lo, end: hi)];
  if (extents.length == 1) {
    final mid = (lo + hi) / 2;
    return [
      ..._chunkRanges([(start: lo, end: mid)], scale, margin, maxWidth),
      ..._chunkRanges([(start: mid, end: hi)], scale, margin, maxWidth),
    ];
  }
  var cut = 0;
  var widest = -1.0;
  for (var i = 0; i + 1 < extents.length; i++) {
    final gap = extents[i + 1].start - extents[i].end;
    if (gap > widest) {
      widest = gap;
      cut = i;
    }
  }
  return [
    ..._chunkRanges(extents.sublist(0, cut + 1), scale, margin, maxWidth),
    ..._chunkRanges(extents.sublist(cut + 1), scale, margin, maxWidth),
  ];
}

/// Moves every i-dot sideways onto the stem under it (see
/// [LineImageConfig.snapDots]). Only [_Levelled.shift] changes.
void _snapDots(RecognizedLine line, List<_Levelled> pieces, double angle, LineImageConfig config) {
  final xh = line.xHeight;
  // Baseline in the levelled frame (a level line after the rotation).
  final c = math.cos(angle), s = math.sin(angle);
  final bx = line.left, by = line.baselineY;
  final baseline = by * c - bx * s;
  final stems = <_Levelled>[];
  final dots = <_Levelled>[];
  for (final p in pieces) {
    final bar = p.width >= config.barMinWidthFactor * xh && p.height <= config.barFlatness * p.width;
    if (p.diagonal <= config.dotMaxFactor * xh && p.bottom <= baseline - config.dotFloatFactor * xh) {
      if (!bar) dots.add(p);
    } else if (p.height >= config.stemMinFactor * xh &&
        p.width <= config.stemMaxWidthFactor * xh &&
        p.width <= config.stemMaxAspect * p.height) {
      stems.add(p);
    }
  }
  if (dots.isEmpty || stems.isEmpty) return;
  final boxes = [for (final st in stems) st.box];
  for (final d in dots) {
    final k = nearestSupport(d.box, boxes, u: xh, reachX: config.reachX, reachY: config.snapReachY, underOnly: true);
    if (k == null) continue;
    final stem = stems[k];
    // x of the stem's top: where the i's dot belongs.
    final topLimit = stem.top + config.stemTopFraction * stem.height;
    var sum = 0.0, n = 0;
    for (var i = 0; i < stem.xs.length; i++) {
      if (stem.ys[i] <= topLimit) {
        sum += stem.xs[i];
        n++;
      }
    }
    final stemX = n == 0 ? (stem.left + stem.right) / 2 : sum / n;
    d.shift = stemX - (d.left + d.right) / 2;
  }
}

/// Distributes the strokes drawn in [image] over the horizontal [pixelSpans]
/// (for example the words the recogniser found, as pixel column ranges of
/// the image). Returns one entry per span: the strokes that belong to it as
/// a [WordGroup] (strokes left to right, with the line's baseline slope and
/// x-height), or null when no stroke falls in it.
///
/// Every stroke of `image.strokes` goes to exactly one span. A stroke goes to
/// the span its levelled x-range overlaps most, or to the nearest span when
/// it overlaps none. Marks (dots, commas: see [LineImageConfig.markFactor])
/// follow the stroke they belong to ([nearestSupport]) instead, so a dot
/// written beside its stem still joins the stem's word.
List<WordGroup?> assignStrokesToSpans(
  RecognizedLine line,
  LineImage image,
  List<({double start, double end})> pixelSpans, {
  LineImageConfig config = const LineImageConfig(),
}) {
  final n = pixelSpans.length;
  final out = List<WordGroup?>.filled(n, null);
  if (n == 0) return out;

  final pieces = _levelStrokes(image.strokes, image.angle);
  // _levelStrokes drops strokes without finite points; keep the pairing with
  // image.shifts by matching on identity.
  final shiftOf = <Stroke, double>{
    for (var i = 0; i < image.strokes.length; i++) image.strokes[i]: image.shifts[i],
  };
  for (final p in pieces) {
    p.shift = shiftOf[p.stroke] ?? 0;
  }

  final xh = line.xHeight;
  final spanOf = <_Levelled, int>{};

  int bySpan(_Levelled p) {
    final a = image.pixelOf(p.shiftedLeft), b = image.pixelOf(p.shiftedRight);
    var best = 0;
    var bestOverlap = -1.0;
    var bestGap = double.infinity;
    for (var i = 0; i < n; i++) {
      final sp = pixelSpans[i];
      final overlap = math.min(b, sp.end) - math.max(a, sp.start);
      if (overlap > 0) {
        if (overlap > bestOverlap) {
          bestOverlap = overlap;
          best = i;
        }
      } else if (bestOverlap <= 0) {
        final gap = math.max(sp.start - b, a - sp.end);
        if (gap < bestGap) {
          bestGap = gap;
          best = i;
        }
      }
    }
    return best;
  }

  final bigs = [
    for (final p in pieces)
      if (p.diagonal > config.markFactor * xh) p,
  ];
  for (final p in bigs) {
    spanOf[p] = bySpan(p);
  }
  final boxes = [for (final p in bigs) p.box];
  for (final p in pieces) {
    if (spanOf.containsKey(p)) continue;
    final k = bigs.isEmpty ? null : nearestSupport(p.box, boxes, u: xh, reachX: config.reachX, reachY: config.reachY);
    spanOf[p] = k != null ? spanOf[bigs[k]]! : bySpan(p);
  }

  final groups = List.generate(n, (_) => <_Levelled>[]);
  for (final p in pieces) {
    groups[spanOf[p]!].add(p);
  }
  for (var i = 0; i < n; i++) {
    final g = groups[i];
    if (g.isEmpty) continue;
    g.sort((a, b) => a.shiftedLeft.compareTo(b.shiftedLeft));
    InkRect? bounds;
    for (final p in g) {
      final b = finiteBounds(p.stroke.points);
      if (b == null) continue;
      bounds = bounds == null ? b : bounds.union(b);
    }
    out[i] = WordGroup(
      strokes: [for (final p in g) p.stroke],
      bounds: bounds!,
      baselineSlope: line.baselineSlope,
      xHeight: line.xHeight,
    );
  }
  return out;
}
