import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../ink/ink_point.dart';
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
