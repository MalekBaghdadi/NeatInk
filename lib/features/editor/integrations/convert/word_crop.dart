import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../../../recognition/word_image.dart';

/// Draws a recogniser input image (128x32 grey bytes, 0 = ink, 255 = paper)
/// scaled by [scale], without decoding an image: runs of similarly dark
/// pixels become rectangles (three grey levels), so it also works under
/// `flutter_tester`, where decoding images from pixels is unreliable.
class WordCropPainter extends CustomPainter {
  WordCropPainter(this.pixels, {this.scale = 1.5});

  final Uint8List pixels;
  final double scale;

  static const Size baseSize =
      Size(wordImageWidth * 1.0, wordImageHeight * 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
    if (pixels.length < wordImageWidth * wordImageHeight) return;
    final levels = [
      Paint()..color = const Color(0x33000000),
      Paint()..color = const Color(0x99000000),
      Paint()..color = const Color(0xFF000000),
    ];
    int level(int v) => v < 85 ? 3 : (v < 170 ? 2 : (v < 235 ? 1 : 0));
    for (var y = 0; y < wordImageHeight; y++) {
      var x = 0;
      while (x < wordImageWidth) {
        final l = level(pixels[y * wordImageWidth + x]);
        if (l == 0) {
          x++;
          continue;
        }
        var end = x + 1;
        while (end < wordImageWidth &&
            level(pixels[y * wordImageWidth + end]) == l) {
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
      !identical(old.pixels, pixels) || old.scale != scale;
}
