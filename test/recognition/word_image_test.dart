import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:neatink/recognition/stroke_grouping.dart';
import 'package:neatink/recognition/word_image.dart';

import '../beautify/synthetic_font.dart';

/// Bounding box of the dark pixels (< 128): left, top, right, bottom.
({int left, int top, int right, int bottom}) inkBox(WordImage img) {
  var l = img.width, t = img.height, r = -1, b = -1;
  for (var y = 0; y < img.height; y++) {
    for (var x = 0; x < img.width; x++) {
      if (img.pixels[y * img.width + x] < 128) {
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

  test('is 48 pixels high, as wide as the aspect ratio asks, dark ink on white', () async {
    final img = await renderWordImage(wordOf('hello'), renderer: renderer);
    expect(img.height, wordImageHeight);
    expect(wordImageHeight, 48);
    expect(img.pixels.length, img.width * 48);
    // 'hello' is 39 x 19 pt, so about 48 * 39 / 19 = 98 px wide.
    expect(img.width, inInclusiveRange(94, 102));
    expect(img.pixels[img.width - 1], 255); // top right: above the o
    expect(img.pixels.where((v) => v < 128).length, greaterThan(60));
    expect(img.pixels.where((v) => v > 0 && v < 255).length, greaterThan(20)); // anti-aliased
  });

  test('the ink fills the image: no white padding', () async {
    final img = await renderWordImage(wordOf('hello'), renderer: renderer);
    final box = inkBox(img);
    expect(box.top, lessThanOrEqualTo(1));
    expect(box.bottom, greaterThanOrEqualTo(46));
    expect(box.left, lessThanOrEqualTo(1));
    expect(box.right, greaterThanOrEqualTo(img.width - 2));
  });

  test('keeps the aspect ratio', () async {
    final img = await renderWordImage(wordOf('hello'), renderer: renderer);
    final box = inkBox(img);
    final inkW = box.right - box.left + 1, inkH = box.bottom - box.top + 1;
    expect(inkW / inkH, closeTo(39 / 19, 0.2));
  });

  test('the width follows the word: a long word is wider, a short one narrower', () async {
    final short = await renderWordImage(wordOf('hen'), renderer: renderer);
    final long = await renderWordImage(wordOf('hellohellohello'), renderer: renderer);
    expect(short.width, lessThan(80));
    expect(long.width, greaterThan(250));
    expect(long.width, lessThanOrEqualTo(wordImageMaxWidth));
  });

  test('an extremely long word is squeezed into the widest image', () async {
    final img = await renderWordImage(wordOf('hellohellohellohellohellohellohellohellohellohello'),
        renderer: renderer);
    expect(img.width, wordImageMaxWidth);
    final box = inkBox(img);
    expect(box.left, lessThanOrEqualTo(2));
    expect(box.right, greaterThanOrEqualTo(wordImageMaxWidth - 3));
  });

  test('the pen is thin: wordImageStrokePx at 48 px height', () async {
    expect(wordImageStrokePx, inInclusiveRange(1.5, 2.0));
    final img = await renderWordImage(wordOf('hello'), renderer: renderer);
    expect(img.strokeWidthPx, wordImageStrokePx);
    // Near the top only the straight stems of the h and the two l exist;
    // each is about one stroke wide.
    const row = 8;
    var widest = 0, run = 0;
    for (var x = 0; x < img.width; x++) {
      if (img.pixels[row * img.width + x] < 160) {
        run++;
        if (run > widest) widest = run;
      } else {
        run = 0;
      }
    }
    expect(widest, lessThanOrEqualTo(3));
    // 48 px for 19 pt of height
    expect(img.scale, closeTo((48 - wordImageStrokePx) / 19, 0.1));
  });

  test('a custom stroke width is honoured', () async {
    final thin = await renderWordImage(wordOf('hello'), renderer: renderer);
    final thick = await renderWordImage(wordOf('hello'),
        renderer: renderer, config: const WordImageConfig(strokePx: 4));
    expect(thick.strokeWidthPx, 4);
    expect(thick.pixels.where((v) => v < 128).length,
        greaterThan(thin.pixels.where((v) => v < 128).length * 1.5));
  });

  test('a rotated word is levelled to match the unrotated rendering', () async {
    final flat = await renderWordImage(wordOf('hello'), renderer: renderer);
    final tilted = await renderWordImage(wordOf('hello', rotateDeg: 10), renderer: renderer);
    final a = inkBox(flat), b = inkBox(tilted);
    expect((flat.width - tilted.width).abs(), lessThanOrEqualTo(6));
    expect((a.top - b.top).abs(), lessThanOrEqualTo(2));
    expect((a.bottom - b.bottom).abs(), lessThanOrEqualTo(2));
    // Compare on the common width.
    final w = flat.width < tilted.width ? flat.width : tilted.width;
    var diff = 0;
    for (var y = 0; y < 48; y++) {
      for (var x = 0; x < w; x++) {
        if ((flat.pixels[y * flat.width + x] - tilted.pixels[y * tilted.width + x]).abs() > 100) {
          diff++;
        }
      }
    }
    final inkPixels = flat.pixels.where((v) => v < 128).length;
    expect(diff, lessThan(inkPixels));
  });

  test('a lone dot is not blown up to fill the image', () async {
    final dot = groupStrokes(toStrokes([
      densify(const [Vec2(0, 0), Vec2(0.4, 0)]),
    ])).single.words.single;
    final img = await renderWordImage(dot, renderer: renderer);
    expect(img.width, wordImageMinWidth);
    final box = inkBox(img);
    expect(box.right - box.left, lessThan(14));
    expect(box.bottom - box.top, lessThan(40));
  });

  test('a word with no points renders a blank minimum-width image', () async {
    final empty = WordGroup(strokes: const [], bounds: groupStrokes(makeWord('hello')).single.words.single.bounds);
    final img = await renderWordImage(empty, renderer: renderer);
    expect(img.width, wordImageMinWidth);
    expect(img.pixels.every((v) => v == 255), isTrue);
  });

  test('the same input gives the same pixels', () async {
    final a = await renderWordImage(wordOf('hello'), renderer: renderer);
    final b = await renderWordImage(wordOf('hello'), renderer: renderer);
    expect(a.pixels, b.pixels);
    expect(a.width, b.width);
  });

  test('WordImage derives its width from the pixel count when not given', () {
    final img = WordImage(pixels: Uint8List(48 * 70), scale: 1, strokeWidthPx: 1.8);
    expect(img.width, 70);
    expect(img.height, 48);
  });
}
