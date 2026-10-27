import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../../../recognition/word_image.dart';

/// Draws a recogniser input image ([width] x [height] grey bytes, 0 = ink,
/// 255 = paper) scaled by [scale], without decoding an image: runs of
/// similarly dark pixels become rectangles (three grey levels), so it also
/// works under `flutter_tester`, where decoding images from pixels is
/// unreliable.
class WordCropPainter extends CustomPainter {
  WordCropPainter(
    this.pixels, {
    required this.width,
    this.height = wordImageHeight,
    this.scale = 1.5,
  });

  /// Draws [image] (as made by `renderWordImage`).
  factory WordCropPainter.of(WordImage image, {double scale = 1.5}) =>
      WordCropPainter(image.pixels,
          width: image.width, height: image.height, scale: scale);

  final Uint8List pixels;
  final int width;
  final int height;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
    if (width <= 0 || height <= 0 || pixels.length < width * height) return;
    final levels = [
      Paint()..color = const Color(0x33000000),
      Paint()..color = const Color(0x99000000),
      Paint()..color = const Color(0xFF000000),
    ];
    int level(int v) => v < 85 ? 3 : (v < 170 ? 2 : (v < 235 ? 1 : 0));
    for (var y = 0; y < height; y++) {
      var x = 0;
      while (x < width) {
        final l = level(pixels[y * width + x]);
        if (l == 0) {
          x++;
          continue;
        }
        var end = x + 1;
        while (end < width && level(pixels[y * width + end]) == l) {
          end++;
        }
        canvas.drawRect(
          Rect.fromLTRB(x * scale, y * scale, end * scale, (y + 1) * scale),
          levels[l - 1],
        );
        x = end;
      }
    }
  }

  @override
  bool shouldRepaint(WordCropPainter old) =>
      !identical(old.pixels, pixels) ||
      old.scale != scale ||
      old.width != width ||
      old.height != height;
}
