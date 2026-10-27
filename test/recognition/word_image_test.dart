import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:neatink/recognition/stroke_grouping.dart';
import 'package:neatink/recognition/word_image.dart';

import '../beautify/synthetic_font.dart';

/// Bounding box of the dark pixels (< 128): left, top, right, bottom.
({int left, int top, int right, int bottom}) inkBox(Uint8List px) {
  var l = wordImageWidth, t = wordImageHeight, r = -1, b = -1;
  for (var y = 0; y < wordImageHeight; y++) {
    for (var x = 0; x < wordImageWidth; x++) {
      if (px[y * wordImageWidth + x] < 128) {
        if (x < l) l = x;
        if (x > r) r = x;
        if (y < t) t = y;
        if (y > b) b = y;
      }
    }
  }
  return (left: l, top: t, right: r, bottom: b);
}

WordGroup wordOf(String text, {double rotateDeg = 0}) {
  final lines = groupStrokes(makeWord(text, rotateDeg: rotateDeg));
  expect(lines.single.words, hasLength(1));
  return lines.single.words.single;
}

void main() {
  const renderer = PolylineWordImageRenderer();

  test('produces a 4096 byte image: dark ink on white', () async {
    final img = await renderWordImage(wordOf('hello'), renderer: renderer);
    expect(img.pixels.length, 4096);
    expect(img.pixels[0], 255);
    expect(img.pixels[4095], 255);
    expect(img.pixels.where((v) => v < 128).length, greaterThan(60));
    expect(img.pixels.where((v) => v > 0 && v < 255).length, greaterThan(20)); // anti-aliased
  });

  test('keeps the aspect ratio, centred, filling the height', () async {
    final img = await renderWordImage(wordOf('hello'), renderer: renderer);
    final box = inkBox(img.pixels);
    // The word is 39 x 19 pt: height limited.
    expect(box.top, inInclusiveRange(1, 4));
    expect(box.bottom, inInclusiveRange(27, 30));
    final inkW = box.right - box.left + 1, inkH = box.bottom - box.top + 1;
    expect(inkW / inkH, closeTo(39 / 19, 0.35));
    final leftMargin = box.left, rightMargin = wordImageWidth - 1 - box.right;
    expect((leftMargin - rightMargin).abs(), lessThanOrEqualTo(2));
  });

  test('a long word is width limited and still fits', () async {
    final img = await renderWordImage(wordOf('hellohellohello'), renderer: renderer);
    final box = inkBox(img.pixels);
    expect(box.left, inInclusiveRange(0, 4));
    expect(box.right, inInclusiveRange(123, 127));
    expect(box.bottom, lessThan(wordImageHeight));
  });

  test('pen width follows the x-height within IAM-like bounds', () async {
    final img = await renderWordImage(wordOf('hello'), renderer: renderer);
    expect(img.strokeWidthPx, inInclusiveRange(1.6, 3.0));
    // Pixels per point: 28 px for 19 pt of height.
    expect(img.scale, closeTo(1.4, 0.2));
  });

  test('a rotated word is levelled to match the unrotated rendering', () async {
    final flat = await renderWordImage(wordOf('hello'), renderer: renderer);
    final tilted = await renderWordImage(wordOf('hello', rotateDeg: 10), renderer: renderer);
    final a = inkBox(flat.pixels), b = inkBox(tilted.pixels);
    expect((a.top - b.top).abs(), lessThanOrEqualTo(2));
    expect((a.bottom - b.bottom).abs(), lessThanOrEqualTo(2));
    expect((a.left - b.left).abs(), lessThanOrEqualTo(3));
    expect((a.right - b.right).abs(), lessThanOrEqualTo(3));
    var diff = 0;
    for (var i = 0; i < 4096; i++) {
      if ((flat.pixels[i] - tilted.pixels[i]).abs() > 100) diff++;
    }
    final inkPixels = flat.pixels.where((v) => v < 128).length;
    expect(diff, lessThan(inkPixels ~/ 2));
  });

  test('a lone dot is not blown up to fill the canvas', () async {
    final dot = groupStrokes(toStrokes([
      densify(const [Vec2(0, 0), Vec2(0.4, 0)]),
    ])).single.words.single;
    final img = await renderWordImage(dot, renderer: renderer);
    final box = inkBox(img.pixels);
    expect(box.right - box.left, lessThan(40));
  });

  test('the same input gives the same pixels', () async {
    final a = await renderWordImage(wordOf('hello'), renderer: renderer);
    final b = await renderWordImage(wordOf('hello'), renderer: renderer);
    expect(a.pixels, b.pixels);
  });
}
