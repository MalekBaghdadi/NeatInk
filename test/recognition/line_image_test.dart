import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:neatink/recognition/stroke_grouping.dart';
import 'package:neatink/recognition/word_image.dart';

import '../beautify/synthetic_font.dart';

/// Bounding box of the dark pixels (< 128): left, top, right, bottom.
({int left, int top, int right, int bottom}) inkBox(WordImage img,
    {int fromX = 0, int? toX, int fromY = 0, int? toY}) {
  var l = img.width, t = img.height, r = -1, b = -1;
  for (var y = fromY; y < (toY ?? img.height); y++) {
    for (var x = fromX; x < (toX ?? img.width); x++) {
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

/// Mean x of the dark pixels in the given window, or null when it is white.
double? inkCentre(WordImage img, {required int fromX, required int toX, required int fromY, required int toY}) {
  var sum = 0.0, n = 0;
  for (var y = fromY; y < toY; y++) {
    for (var x = fromX; x < toX; x++) {
      final v = img.pixels[y * img.width + x];
      if (v < 128) {
        sum += x + 0.5;
        n++;
      }
    }
  }
  return n == 0 ? null : sum / n;
}

/// Polylines of [text] (shared synthetic font, x-height 10, tall 19) with
/// the first letter at [x] and the baseline at y = 0.
List<List<Vec2>> textAt(String text, double x, {double gap = 4}) => [
      for (final p in wordPolylines(text, gap: gap)) [for (final v in p) Vec2(v.x + x, v.y)],
    ];

RecognizedLine lineFrom(List<List<Vec2>> polylines, {double rotateDeg = 0, double scale = 1}) {
  final lines = groupStrokes(toStrokes(polylines, m: distortion(rotateDeg: rotateDeg, scale: scale)));
  expect(lines, hasLength(1));
  return lines.single;
}

/// Words of the font side by side: word i starts at offsets[i].
RecognizedLine wordsLine(List<String> words, List<double> offsets, {double rotateDeg = 0, double scale = 1}) =>
    lineFrom([for (var i = 0; i < words.length; i++) ...textAt(words[i], offsets[i])],
        rotateDeg: rotateDeg, scale: scale);

/// Levelled x-range of [s] for a frame rotated by [angle].
({double left, double right}) levelledRange(Stroke s, double angle) {
  final c = math.cos(angle), sn = math.sin(angle);
  var l = double.infinity, r = double.negativeInfinity;
  for (final p in s.points) {
    final x = p.x * c + p.y * sn;
    if (x < l) l = x;
    if (x > r) r = x;
  }
  return (left: l, right: r);
}

void main() {
  const renderer = PolylineWordImageRenderer();
  final marginPx = const LineImageConfig().marginFrac * wordImageHeight; // 7.2

  group('renderLineImages geometry', () {
    test('config defaults match the contract', () {
      const c = LineImageConfig();
      expect(c.strokePx, 2.0);
      expect(c.marginFrac, 0.15);
      expect(c.minWidth, 16);
      expect(c.maxWidth, 2400);
      expect(c.maxScale, 10);
      expect(c.snapDots, isFalse);
    });

    test('a line is ONE image, 48 high, scaled so the ink fills 70 percent of it', () async {
      final line = wordsLine(['hello', 'online'], [0, 52]); // 102 x 19 pt
      final images = await renderLineImages(line, renderer: renderer);
      expect(images, hasLength(1));
      final img = images.single;
      expect(img, isA<WordImage>());
      expect(img.height, wordImageHeight);
      expect(img.pixels.length, img.width * 48);
      expect(img.scale, closeTo((48 - 2 * marginPx) / 19, 0.03));
      expect(img.width, closeTo(102 * img.scale + 2 * marginPx, 1.5));
      expect(img.strokeWidthPx, 2.0);
      expect(img.strokes, hasLength(line.inkStrokes.length));
      expect(img.pixels.where((v) => v < 128).length, greaterThan(150));
    });

    test('white margin of 15 percent of the height on every side', () async {
      final line = wordsLine(['hello', 'online'], [0, 52]);
      final img = (await renderLineImages(line, renderer: renderer)).single;
      final box = inkBox(img);
      // The pen centre line is marginPx from the edge; the 2 px pen reaches a
      // pixel further out.
      expect(box.top, inInclusiveRange(5, 7));
      expect(box.bottom, inInclusiveRange(40, 42));
      expect(box.left, inInclusiveRange(5, 7));
      expect(img.width - 1 - box.right, inInclusiveRange(5, 9));
      // ... and nothing else: rows and columns outside are pure white
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < img.width; x++) {
          expect(img.pixels[y * img.width + x], 255);
        }
      }
    });

    test('levelledX maps pixels back to the levelled frame', () async {
      final line = wordsLine(['hello', 'online'], [0, 52]);
      final img = (await renderLineImages(line, renderer: renderer)).single;
      final left = line.inkStrokes.map((s) => levelledRange(s, img.angle).left).reduce(math.min);
      final right = line.inkStrokes.map((s) => levelledRange(s, img.angle).right).reduce(math.max);
      expect(img.levelledX(marginPx), closeTo(left, 1.0));
      expect(img.levelledX(img.width - marginPx), closeTo(right, 1.5));
      expect(img.levelledX(0), closeTo(img.originX, 1e-9));
      expect(img.levelledX(img.scale * 10) - img.levelledX(0), closeTo(10, 1e-9));
      expect(img.pixelOf(img.levelledX(37.5)), closeTo(37.5, 1e-9));
      expect(img.angle, closeTo(0, 0.02));
    });

    test('a levelled line looks like the flat one', () async {
      final flat = (await renderLineImages(wordsLine(['hello', 'online'], [0, 52]), renderer: renderer)).single;
      final tilted = (await renderLineImages(wordsLine(['hello', 'online'], [0, 52], rotateDeg: 8),
              renderer: renderer))
          .single;
      expect(tilted.angle, closeTo(8 * math.pi / 180, 0.03));
      expect((flat.width - tilted.width).abs(), lessThanOrEqualTo(8));
      final a = inkBox(flat), b = inkBox(tilted);
      expect((a.top - b.top).abs(), lessThanOrEqualTo(2));
      expect((a.bottom - b.bottom).abs(), lessThanOrEqualTo(2));
    });

    test('every stroke of the line is drawn, the page strokes themselves are untouched', () async {
      final line = wordsLine(['hello', 'online'], [0, 52]);
      final before = [for (final s in line.inkStrokes) List.of(s.points)];
      final images = await renderLineImages(line,
          renderer: renderer, config: const LineImageConfig(snapDots: true));
      final drawn = [for (final img in images) ...img.strokes];
      expect(drawn, hasLength(line.inkStrokes.length));
      expect({...drawn}, {...line.inkStrokes});
      for (var i = 0; i < drawn.length; i++) {
        expect(drawn[i], same(line.inkStrokes[i]));
        expect(drawn[i].points, before[i]);
      }
    });

    test('the pen width and the margin are configurable', () async {
      final line = wordsLine(['hello', 'online'], [0, 52]);
      final thin = (await renderLineImages(line, renderer: renderer)).single;
      final thick = (await renderLineImages(line,
              renderer: renderer, config: const LineImageConfig(strokePx: 4)))
          .single;
      expect(thick.strokeWidthPx, 4);
      expect(thick.pixels.where((v) => v < 128).length,
          greaterThan(thin.pixels.where((v) => v < 128).length * 1.5));
      final roomy = (await renderLineImages(line,
              renderer: renderer, config: const LineImageConfig(marginFrac: 0.25)))
          .single;
      expect(roomy.scale, lessThan(thin.scale));
      expect(roomy.scale, closeTo((48 - 2 * 12) / 19, 0.03));
    });

    test('a lone dot is not blown up: it stays small, centred on white', () async {
      final line = lineFrom([
        densify(const [Vec2(0, 0), Vec2(0.4, 0)]),
      ]);
      final img = (await renderLineImages(line, renderer: renderer)).single;
      expect(img.scale, lessThanOrEqualTo(10));
      expect(img.width, inInclusiveRange(16, 20)); // the two margins alone are 14.4 px
      final box = inkBox(img);
      expect(box.right - box.left, lessThan(10));
      expect(box.bottom - box.top, lessThan(10));
      expect((box.left + box.right) / 2, closeTo(img.width / 2, 1));
      expect((box.top + box.bottom) / 2, closeTo(24, 1));
    });

    test('the minimum width pads a narrow line, ink centred', () async {
      final line = lineFrom([
        densify(const [Vec2(0, 0), Vec2(0.4, 0)]),
      ]);
      final img = (await renderLineImages(line,
              renderer: renderer, config: const LineImageConfig(minWidth: 60)))
          .single;
      expect(img.width, 60);
      final box = inkBox(img);
      expect((box.left + box.right) / 2, closeTo(30, 1));
    });

    test('maxScale caps the enlargement', () async {
      final line = wordsLine(['hello'], [0]);
      final img = (await renderLineImages(line,
              renderer: renderer, config: const LineImageConfig(maxScale: 0.5)))
          .single;
      expect(img.scale, 0.5);
    });

    test('a line without ink gives a blank minimum-width image', () async {
      final line = RecognizedLine(
        words: const [],
        baselineY: 0,
        baselineSlope: 0,
        left: 0,
        right: 0,
        xHeight: 10,
      );
      final images = await renderLineImages(line, renderer: renderer);
      expect(images, hasLength(1));
      expect(images.single.width, 16);
      expect(images.single.strokes, isEmpty);
      expect(images.single.pixels.every((v) => v == 255), isTrue);
    });

    test('the same input gives the same pixels', () async {
      final line = wordsLine(['hello', 'online'], [0, 52]);
      final a = (await renderLineImages(line, renderer: renderer)).single;
      final b = (await renderLineImages(line, renderer: renderer)).single;
      expect(a.pixels, b.pixels);
      expect(a.originX, b.originX);
    });
  });

  group('chunking of very wide lines', () {
    // hello 0..39, online 64..114 (gap 25), hen 159..189 (gap 45: the widest)
    RecognizedLine threeWords() => wordsLine(['hello', 'online', 'hen'], [0, 64, 159]);

    test('a line that fits stays whole whatever its length in points', () async {
      final images = await renderLineImages(threeWords(), renderer: renderer);
      expect(images, hasLength(1));
      expect(images.single.width, lessThanOrEqualTo(2400));
    });

    test('too wide: cut at the widest gap, each chunk within maxWidth, never squeezed', () async {
      final line = threeWords();
      final whole = (await renderLineImages(line, renderer: renderer)).single;
      expect(whole.width, greaterThan(300)); // so 300 forces a cut
      final images = await renderLineImages(line,
          renderer: renderer, config: const LineImageConfig(maxWidth: 300));
      expect(images, hasLength(2));
      expect([for (final i in images) i.strokes.length], [12, 3]); // hello+online | hen
      for (final img in images) {
        expect(img.width, lessThanOrEqualTo(300));
        expect(img.scale, closeTo(whole.scale, 1e-9));
        expect(img.height, 48);
      }
      // left to right, nothing shared, nothing lost
      expect(images[0].originX, lessThan(images[1].originX));
      expect(images[0].levelledX(images[0].width - marginPx), lessThan(images[1].levelledX(marginPx)));
      final drawn = [for (final i in images) ...i.strokes];
      expect({...drawn}, {...line.inkStrokes});
      expect(drawn, hasLength(line.inkStrokes.length));
      // the white gap between the chunks is real: the cut is at the 45 pt gap
      final gap = images[1].levelledX(marginPx) - images[0].levelledX(images[0].width - marginPx);
      expect(gap, closeTo(45, 2));
    });

    test('a narrower limit cuts a chunk again, at the next widest gap', () async {
      final line = threeWords();
      final images = await renderLineImages(line,
          renderer: renderer, config: const LineImageConfig(maxWidth: 150));
      expect(images, hasLength(3));
      expect([for (final i in images) i.strokes.length], [5, 7, 3]); // one word each
      for (final img in images) {
        expect(img.width, lessThanOrEqualTo(150));
      }
    });

    test('every chunk has the same height placement', () async {
      final images = await renderLineImages(threeWords(),
          renderer: renderer, config: const LineImageConfig(maxWidth: 150));
      final boxes = [for (final i in images) inkBox(i)];
      // hello, online and hen all stand between the baseline and the tall letters
      for (final b in boxes) {
        expect(b.top, inInclusiveRange(5, 7));
        expect(b.bottom, inInclusiveRange(40, 42));
      }
    });

    test('one unbroken stretch wider than the limit is cut through the middle', () async {
      final scribble = densify([for (var i = 0; i <= 100; i++) Vec2(i * 4.0, (i.isEven ? 0 : -10).toDouble())], 1);
      final line = lineFrom([scribble]);
      final images = await renderLineImages(line,
          renderer: renderer, config: const LineImageConfig(maxWidth: 800));
      expect(images.length, greaterThanOrEqualTo(2));
      for (final img in images) {
        expect(img.width, lessThanOrEqualTo(800));
        expect(img.strokes, [line.inkStrokes.single]);
      }
    });
  });

  group('snapDots', () {
    // hen 0..30, an i (stem at 42) whose dot is written 5 pt left of it, then
    // ne: the dot is nearer to its own stem than to the n before it.
    List<List<Vec2>> lineWithLeftDot({double dotX = 37, double stemX = 42}) => [
          ...textAt('hen', 0),
          densify([Vec2(stemX, -10), Vec2(stemX, 0)]),
          densify([Vec2(dotX - 0.3, -14), Vec2(dotX + 0.3, -14)]),
          ...textAt('ne', 49),
        ];

    test('off by default: the dot stays where it was written', () async {
      final line = lineFrom(lineWithLeftDot());
      final img = (await renderLineImages(line, renderer: renderer)).single;
      expect(img.shifts.every((s) => s == 0), isTrue);
    });

    test('a dot left of its stem is moved over the stem, in the image only', () async {
      final line = lineFrom(lineWithLeftDot());
      final plain = (await renderLineImages(line, renderer: renderer)).single;
      final snapped = (await renderLineImages(line,
              renderer: renderer, config: const LineImageConfig(snapDots: true)))
          .single;
      final moved = [for (var i = 0; i < snapped.shifts.length; i++) if (snapped.shifts[i] != 0) i];
      expect(moved, hasLength(1));
      expect(snapped.shifts[moved.single], closeTo(5, 0.7)); // 42 - 37
      expect(snapped.strokes[moved.single].bounds.center.x, closeTo(137, 0.5)); // page ink unchanged (x + 100)

      // Pixel check: the dot row sits near the stem column only when snapped.
      // (the page origin of the synthetic strokes is x = 100)
      final stemPlain = plain.pixelOf(142), stemSnap = snapped.pixelOf(142);
      int col(double px) => px.round();
      final dotRows = (14, 19);
      final dotPlain = inkCentre(plain,
          fromX: col(plain.pixelOf(133)), toX: col(plain.pixelOf(147)), fromY: dotRows.$1, toY: dotRows.$2);
      final dotSnap = inkCentre(snapped,
          fromX: col(snapped.pixelOf(133)), toX: col(snapped.pixelOf(147)), fromY: dotRows.$1, toY: dotRows.$2);
      expect(dotPlain, isNotNull);
      expect(dotSnap, isNotNull);
      expect((dotSnap! - stemSnap).abs(), lessThan(1.6));
      expect((dotPlain! - stemPlain).abs(), greaterThan(6));
    });

    test('snapping changes only the dots: same size, scale and alignment', () async {
      // The dot is the left-most ink of this line: moving it must not
      // shrink the image or shift the letters.
      final polylines = [
        densify([const Vec2(0, -14), const Vec2(0.6, -14)]), // dot, 6 pt left of the stem
        densify([const Vec2(6, -10), const Vec2(6, 0)]), // stem of the i
        ...textAt('ne', 14),
      ];
      final line = lineFrom(polylines);
      final plain = (await renderLineImages(line, renderer: renderer)).single;
      final snapped = (await renderLineImages(line,
              renderer: renderer, config: const LineImageConfig(snapDots: true)))
          .single;
      expect(snapped.shifts.where((s) => s != 0), hasLength(1));
      expect(snapped.width, plain.width);
      expect(snapped.scale, plain.scale);
      expect(snapped.originX, plain.originX);
      // rows below the dot (stem and letters) are identical
      for (var y = 22; y < 48; y++) {
        for (var x = 0; x < plain.width; x++) {
          expect(snapped.pixels[y * snapped.width + x], plain.pixels[y * plain.width + x]);
        }
      }
      expect(snapped.pixels, isNot(plain.pixels));
    });

    test('dots already over their stems barely move', () async {
      final line = wordsLine(['hello', 'online'], [0, 52]);
      final snapped = (await renderLineImages(line,
              renderer: renderer, config: const LineImageConfig(snapDots: true)))
          .single;
      expect(snapped.shifts.every((s) => s.abs() < 0.7), isTrue);
    });

    test('a full stop and a dot with no stem under it stay put', () async {
      final polylines = [
        ...textAt('hello', 0),
        densify(const [Vec2(42, -0.4), Vec2(42.5, 0)]), // a full stop after the word
        ...textAt('hen', 60),
        densify(const [Vec2(115, -16.3), Vec2(115.6, -16.3)]), // a stray high dot, no stroke near
      ];
      final line = lineFrom(polylines);
      final snapped = (await renderLineImages(line,
              renderer: renderer, config: const LineImageConfig(snapDots: true)))
          .single;
      expect(snapped.shifts.every((s) => s == 0), isTrue);
    });

    test('a dot with nothing within 1.2 x-heights is left alone', () async {
      final line = lineFrom(lineWithLeftDot(dotX: 95)); // ne ends at 71
      final snapped = (await renderLineImages(line,
              renderer: renderer, config: const LineImageConfig(snapDots: true)))
          .single;
      expect(snapped.shifts.every((s) => s == 0), isTrue);
    });

    test('works on a tilted line too', () async {
      final line = lineFrom(lineWithLeftDot(), rotateDeg: 6);
      final snapped = (await renderLineImages(line,
              renderer: renderer, config: const LineImageConfig(snapDots: true)))
          .single;
      final shifts = snapped.shifts.where((s) => s != 0).toList();
      expect(shifts, hasLength(1));
      expect(shifts.single, closeTo(5, 0.8));
    });
  });

  group('assignStrokesToSpans', () {
    ({double start, double end}) spanOf(LineImage img, Iterable<Stroke> strokes, {double pad = 2}) {
      var l = double.infinity, r = double.negativeInfinity;
      for (final s in strokes) {
        final range = levelledRange(s, img.angle);
        l = math.min(l, range.left);
        r = math.max(r, range.right);
      }
      return (start: img.pixelOf(l) - pad, end: img.pixelOf(r) + pad);
    }

    test('two words: every stroke goes to its word, left to right', () async {
      final line = wordsLine(['hello', 'online'], [0, 52]);
      final img = (await renderLineImages(line, renderer: renderer)).single;
      final first = line.inkStrokes.take(5).toList(); // hello
      final second = line.inkStrokes.skip(5).toList(); // online
      final groups = assignStrokesToSpans(line, img, [spanOf(img, first), spanOf(img, second)]);
      expect(groups, hasLength(2));
      expect(groups[0]!.strokes, hasLength(5));
      expect(groups[1]!.strokes, hasLength(7));
      expect({...groups[0]!.strokes}, {...first});
      expect({...groups[1]!.strokes}, {...second});
      for (final g in groups) {
        expect(g!.baselineSlope, line.baselineSlope);
        expect(g.xHeight, line.xHeight);
        for (var i = 1; i < g.strokes.length; i++) {
          expect(levelledRange(g.strokes[i], img.angle).left,
              greaterThanOrEqualTo(levelledRange(g.strokes[i - 1], img.angle).left));
        }
      }
      expect(groups[0]!.bounds.right, lessThan(groups[1]!.bounds.left));
    });

    test('every stroke is assigned to exactly one span, whatever the spans', () async {
      final line = wordsLine(['hello', 'online', 'hen'], [0, 64, 159]);
      final img = (await renderLineImages(line, renderer: renderer)).single;
      final rnd = math.Random(3);
      for (var trial = 0; trial < 25; trial++) {
        final n = 1 + rnd.nextInt(7);
        final cuts = [for (var i = 0; i < n - 1; i++) rnd.nextDouble() * img.width]..sort();
        final edges = [0.0, ...cuts, img.width.toDouble()];
        final spans = [
          for (var i = 0; i < n; i++)
            if (rnd.nextInt(5) > 0) (start: edges[i], end: edges[i + 1]) else (start: edges[i] + 1, end: edges[i] + 1.5),
        ];
        final groups = assignStrokesToSpans(line, img, spans);
        expect(groups, hasLength(spans.length));
        final all = [for (final g in groups) if (g != null) ...g.strokes];
        expect(all, hasLength(line.inkStrokes.length), reason: 'trial $trial');
        expect({...all}, {...line.inkStrokes});
      }
    });

    test('a stroke cut by two spans goes to the one it overlaps most', () async {
      final line = wordsLine(['hello'], [0]);
      final img = (await renderLineImages(line, renderer: renderer)).single;
      final o = line.inkStrokes.last; // the o: x 31..39
      final range = levelledRange(o, img.angle);
      // cut 25 percent into the o
      final cut = img.pixelOf(range.left + 0.25 * (range.right - range.left));
      final groups = assignStrokesToSpans(line, img, [
        (start: 0.0, end: cut),
        (start: cut, end: img.width.toDouble()),
      ]);
      expect(groups[1]!.strokes, contains(o));
      expect(groups[0]!.strokes, isNot(contains(o)));
    });

    test('a stroke in a gap goes to the nearest span', () async {
      final line = wordsLine(['hello', 'online'], [0, 52]);
      final img = (await renderLineImages(line, renderer: renderer)).single;
      final first = line.inkStrokes.take(5).toList();
      final second = line.inkStrokes.skip(5).toList();
      // Spans that leave the 'o' of hello (x 31..39) out, and the first
      // letters of online: the o is nearer to the first span.
      final firstSpan = spanOf(img, first.take(4), pad: 0);
      final secondSpan = spanOf(img, second, pad: 0);
      final groups = assignStrokesToSpans(line, img, [firstSpan, secondSpan]);
      expect(groups[0]!.strokes, contains(first.last));
    });

    test('spans nothing falls in give null; no spans give an empty list', () async {
      final line = wordsLine(['hello'], [0]);
      final img = (await renderLineImages(line, renderer: renderer)).single;
      final groups = assignStrokesToSpans(line, img, [
        (start: 0.0, end: img.width.toDouble()),
        (start: img.width + 100.0, end: img.width + 120.0),
      ]);
      expect(groups[0]!.strokes, hasLength(5));
      expect(groups[1], isNull);
      expect(assignStrokesToSpans(line, img, const []), isEmpty);
    });

    test('an i-dot inside the previous words span still joins the word of its stem', () async {
      // hen 0..30, the stem of an i at 42 and its dot at 37, then ne. The
      // model's span for hen reaches a little into the gap and covers the dot,
      // which is nearer to hen (6.7 pt) than to the i (4.7 pt) by the spans.
      final polylines = [
        ...textAt('hen', 0),
        densify([const Vec2(42, -10), const Vec2(42, 0)]),
        densify([const Vec2(36.7, -14), const Vec2(37.3, -14)]),
        ...textAt('ne', 50),
      ];
      final line = lineFrom(polylines);
      final n = line.inkStrokes.length;
      final dot = line.inkStrokes[n - 4];
      final stem = line.inkStrokes[n - 5];
      for (final snap in [false, true]) {
        final img = (await renderLineImages(line,
                renderer: renderer, config: LineImageConfig(snapDots: snap)))
            .single;
        final hen = line.inkStrokes.take(3).toList();
        final rest = [stem, ...line.inkStrokes.skip(n - 3)];
        final henSpan = spanOf(img, hen, pad: 0);
        // reaches 8 pt into the gap, over the dot
        final wide = (start: henSpan.start, end: henSpan.end + 8 * img.scale);
        final groups = assignStrokesToSpans(line, img, [wide, spanOf(img, rest)]);
        expect(groups[1]!.strokes, contains(dot), reason: 'snap $snap');
        expect(groups[0]!.strokes, isNot(contains(dot)), reason: 'snap $snap');
        expect(groups[0]!.strokes, hasLength(3), reason: 'snap $snap');
      }
    });

    test('a full stop after a word joins that word, not the next line below', () async {
      final polylines = [
        ...textAt('hello', 0),
        densify(const [Vec2(42, -0.4), Vec2(42.5, 0)]),
        ...textAt('hen', 62),
      ];
      final line = lineFrom(polylines);
      final img = (await renderLineImages(line, renderer: renderer)).single;
      final hello = line.inkStrokes.take(5).toList();
      final stop = line.inkStrokes[5];
      final hen = line.inkStrokes.skip(6).toList();
      final groups = assignStrokesToSpans(line, img, [spanOf(img, hello), spanOf(img, hen)]);
      expect(groups[0]!.strokes, contains(stop));
      expect(groups[1]!.strokes, hasLength(3));
    });
  });
}
