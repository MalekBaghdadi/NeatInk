import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../ink/ink_point.dart';
import '../ink/stroke.dart';
import '../render/stroke_outline.dart';
import 'stroke_grouping.dart';

/// Size of the recogniser's input image.
const int wordImageWidth = 128;
const int wordImageHeight = 32;

/// Tuning numbers for [renderWordImage].
class WordImageConfig {
  const WordImageConfig({
    this.margin = 2.0,
    this.strokeToXHeight = 0.2,
    this.minStrokePx = 1.6,
    this.maxStrokePx = 3.0,
    this.maxScale = 10.0,
  });

  /// White border kept around the ink, in pixels.
  final double margin;

  /// Pen width as a fraction of the (scaled) x-height. IAM word images have
  /// ink about 2 to 3 px wide at 32 px height.
  final double strokeToXHeight;
  final double minStrokePx;
  final double maxStrokePx;

  /// Largest enlargement in pixels per point. Even tiny writing (about 3 pt
  /// x-height) needs less, so a lone dot or dash is not blown up to fill the
  /// canvas.
  final double maxScale;
}

/// A word rendered for the recogniser.
class WordImage {
  const WordImage({required this.pixels, required this.scale, required this.strokeWidthPx});

  /// [wordImageWidth] x [wordImageHeight] bytes, row-major, 0 = ink and
  /// 255 = paper.
  final Uint8List pixels;

  /// Pixels per page point.
  final double scale;

  final double strokeWidthPx;
}

/// Draws strokes already placed in image pixel space (black ink, width
/// `Stroke.size` px) onto a white [wordImageWidth] x [wordImageHeight]
/// canvas and returns the grey pixels. Injectable because
/// `Picture.toImage` never completes under `flutter_tester`.
abstract class WordImageRenderer {
  Future<Uint8List> rasterize(List<Stroke> strokes);
}

/// Renders with `dart:ui`, using the same pen outlines as the screen.
class UiWordImageRenderer implements WordImageRenderer {
  const UiWordImageRenderer();

  @override
  Future<Uint8List> rasterize(List<Stroke> strokes) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, wordImageWidth.toDouble(), wordImageHeight.toDouble()),
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, wordImageWidth.toDouble(), wordImageHeight.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    final paint = ui.Paint()
      ..color = const ui.Color(0xFF000000)
      ..isAntiAlias = true;
    for (final s in strokes) {
      canvas.drawPath(cachedStrokePath(s), paint);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(wordImageWidth, wordImageHeight);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final out = Uint8List(wordImageWidth * wordImageHeight);
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
  Future<Uint8List> rasterize(List<Stroke> strokes) async {
    final coverage = Float64List(wordImageWidth * wordImageHeight);
    for (final s in strokes) {
      final pts = [
        for (final p in s.points)
          if (p.isFinite) p,
      ];
      if (pts.isEmpty) continue;
      final r = s.size / 2;
      if (pts.length == 1) {
        _capsule(coverage, pts[0].x, pts[0].y, pts[0].x, pts[0].y, r);
        continue;
      }
      for (var i = 1; i < pts.length; i++) {
        _capsule(coverage, pts[i - 1].x, pts[i - 1].y, pts[i].x, pts[i].y, r);
      }
    }
    final out = Uint8List(coverage.length);
    for (var i = 0; i < out.length; i++) {
      out[i] = (255 - 255 * coverage[i].clamp(0.0, 1.0)).round();
    }
    return out;
  }

  void _capsule(Float64List cov, double x0, double y0, double x1, double y1, double r) {
    final reach = r + 1;
    final minX = math.max(0, (math.min(x0, x1) - reach).floor());
    final maxX = math.min(wordImageWidth - 1, (math.max(x0, x1) + reach).ceil());
    final minY = math.max(0, (math.min(y0, y1) - reach).floor());
    final maxY = math.min(wordImageHeight - 1, (math.max(y0, y1) + reach).ceil());
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
        final i = py * wordImageWidth + px;
        if (c > cov[i]) cov[i] = c;
      }
    }
  }
}

/// Deskews [word] by its line's baseline slope, fits it into the recogniser's
/// 128x32 canvas keeping the aspect ratio (centred, small margin) and
/// rasterises it as dark ink on white.
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
    final blank = await renderer.rasterize(const []);
    return WordImage(pixels: blank, scale: 1, strokeWidthPx: 0);
  }

  final xh = word.xHeight ?? math.max(maxX - minX, maxY - minY).clamp(1.0, double.infinity) / 3;
  // A lone dot or dash must not be blown up to fill the canvas.
  final w = math.max(maxX - minX, 0.3 * xh);
  final h = math.max(maxY - minY, 0.3 * xh);

  double fit(double border) => math.min(
        config.maxScale,
        math.min(
          (wordImageWidth - 2 * border) / w,
          (wordImageHeight - 2 * border) / h,
        ),
      );
  final first = fit(config.margin);
  final width = (config.strokeToXHeight * xh * first).clamp(config.minStrokePx, config.maxStrokePx);
  final scale = fit(config.margin + width / 2);

  final midX = (minX + maxX) / 2, midY = (minY + maxY) / 2;
  final placed = <Stroke>[
    for (final st in word.strokes)
      () {
        final pts = [
          for (final p in st.points)
            if (p.isFinite)
              InkPoint(
                wordImageWidth / 2 + (lx(p) - midX) * scale,
                wordImageHeight / 2 + (ly(p) - midY) * scale,
                0.5,
                p.t,
              ),
        ];
        return Stroke(
          id: st.id,
          tool: StrokeTool.pen,
          color: 0xFF000000,
          size: width,
          raw: pts,
        );
      }(),
  ];
  return WordImage(
    pixels: await renderer.rasterize(placed),
    scale: scale,
    strokeWidthPx: width,
  );
}
