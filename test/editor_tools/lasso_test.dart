import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/features/editor/tools/lasso.dart';
import 'package:neatink/features/editor/tools/spatial_index.dart';
import 'package:neatink/ink/ink_rect.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';

import 'tool_test_utils.dart';

const pageId = 'p';

/// A rectangular lasso path, drawn as a closed polyline.
List<Vec2> rectLasso(double l, double t, double r, double b) => joinPaths([
      linePoints(l, t, r, t),
      linePoints(r, t, r, b),
      linePoints(r, b, l, b),
      linePoints(l, b, l, t),
    ]);

/// A horizontal stroke from x0 to x1 at y with 11 evenly spaced points.
Stroke hStroke(String id, double x0, double x1, double y,
        {StrokeTool tool = StrokeTool.pen, double size = 2}) =>
    strokeOf(id, [for (var i = 0; i <= 10; i++) Vec2(x0 + (x1 - x0) * i / 10, y)],
        tool: tool, size: size);

void main() {
  group('lassoSelect', () {
    test('strokes need half their points inside', () {
      final page = PageContent(strokes: [
        hStroke('all', 10, 90, 20), // fully inside
        hStroke('sixty', 35, 135, 40), // 7 of 11 points inside (x < 100)
        hStroke('half', 45, 145, 60), // 6 of 11 inside: 54.5%
        hStroke('less', 55, 155, 70), // 5 of 11 inside, middle outside
        hStroke('out', 200, 300, 20),
        strokeOf('dot', [const Vec2(50, 80)]),
        strokeOf('dotOut', [const Vec2(150, 80)]),
      ]);
      final sel = lassoSelect(
          pageId: pageId, page: page, lasso: rectLasso(0, 0, 100, 100));
      expect(sel.strokeIds, {'all', 'sixty', 'half', 'dot'});
      expect(sel.pageId, pageId);
    });

    test('a letter the lasso cuts through counts when its middle is inside', () {
      // A tall letter: 4 of 11 points inside, but the middle of its bounds is.
      final page = PageContent(strokes: [
        strokeOf('l', [for (var i = 0; i <= 10; i++) Vec2(50, 30.0 + i * 10)]),
        strokeOf('far', [for (var i = 0; i <= 10; i++) Vec2(50, 70.0 + i * 10)]),
      ]);
      final sel = lassoSelect(pageId: pageId, page: page, lasso: rectLasso(0, 55, 100, 100));
      expect(sel.strokeIds, {'l'}, reason: 'far: 3 of 11 inside, middle outside');
    });

    test('a phrase in a wide text box selects the box', () {
      // A converted line: the box spans the page, the lasso goes around two
      // words in the middle (its centre and corners are all outside).
      const box = TextItem(id: 'para', x: 20, y: 200, width: 500, height: 40, text: 'one two three four');
      final page = PageContent(texts: const [box]);
      List<InkRect> words(TextItem t) => const [
            InkRect(20, 200, 60, 220),
            InkRect(70, 200, 110, 220),
            InkRect(120, 200, 170, 220),
            InkRect(180, 200, 220, 220),
          ];
      final around = rectLasso(110, 190, 230, 230);
      expect(lassoSelect(pageId: pageId, page: page, lasso: around).textIds, isEmpty, reason: 'no word boxes: the old rule');
      expect(lassoSelect(pageId: pageId, page: page, lasso: around, wordBoxesOf: words).textIds, {'para'});
      expect(lassoSelect(pageId: pageId, page: page, lasso: rectLasso(300, 190, 400, 230), wordBoxesOf: words).textIds,
          isEmpty, reason: 'empty part of the box');
    });

    test('exactly 60% counts', () {
      // 5 points, 3 inside.
      final page = PageContent(strokes: [
        strokeOf('s', [
          for (var i = 0; i < 5; i++) Vec2(80.0 + i * 10, 50),
        ]),
      ]);
      // Inside: x = 80, 90, 100 (< 105); outside 110, 120.
      final sel = lassoSelect(
          pageId: pageId, page: page, lasso: rectLasso(0, 0, 105, 100));
      expect(sel.strokeIds, {'s'});
    });

    test('items: centre inside, or at least half the corners', () {
      final page = PageContent(
        texts: [
          // Centre (50, 50) inside.
          const TextItem(id: 'centre', x: 20, y: 40, width: 60, height: 20),
          // Centre (110, 30) outside, left two corners inside.
          const TextItem(id: 'twoCorners', x: 90, y: 20, width: 40, height: 20),
          // Only one corner inside.
          const TextItem(id: 'oneCorner', x: 90, y: 90, width: 40, height: 40),
        ],
        images: [
          const ImageItem(
              id: 'img', x: 30, y: 70, width: 20, height: 20, asset: 'a.png'),
          const ImageItem(
              id: 'imgOut', x: 300, y: 70, width: 20, height: 20, asset: 'b.png'),
        ],
      );
      final sel = lassoSelect(
          pageId: pageId, page: page, lasso: rectLasso(0, 0, 100, 100));
      expect(sel.textIds, {'centre', 'twoCorners'});
      expect(sel.imageIds, {'img'});
      expect(sel.strokeIds, isEmpty);
    });

    test('self-crossing lassos use the even-odd rule', () {
      // A bow tie: two triangles meeting at (50, 50).
      final bowTie = joinPaths([
        linePoints(0, 0, 100, 100),
        linePoints(100, 100, 100, 0),
        linePoints(100, 0, 0, 100),
        linePoints(0, 100, 0, 0),
      ]);
      final page = PageContent(strokes: [
        strokeOf('left', [const Vec2(10, 45), const Vec2(12, 55)]),
        strokeOf('right', [const Vec2(90, 45), const Vec2(88, 55)]),
        strokeOf('top', [const Vec2(45, 10), const Vec2(55, 12)]),
      ]);
      final sel = lassoSelect(pageId: pageId, page: page, lasso: bowTie);
      expect(sel.strokeIds, {'left', 'right'});
    });

    test('bounds are the union of paint bounds and frames', () {
      final s = hStroke('s', 10, 50, 20, size: 4);
      const t = TextItem(id: 't', x: 30, y: 60, width: 50, height: 20);
      final page = PageContent(strokes: [s], texts: [t]);
      final sel = lassoSelect(
          pageId: pageId, page: page, lasso: rectLasso(0, 0, 100, 100));
      expect(sel.bounds, s.paintBounds.union(t.frame));
      expect(sel.length, 2);
      expect(sel.hasStrokes, isTrue);
      expect(sel.hasItems, isTrue);
    });

    test('using the index gives the same result as without', () {
      final rnd = math.Random(5);
      final strokes = [
        for (var i = 0; i < 800; i++)
          hStroke('s$i', rnd.nextDouble() * 500, rnd.nextDouble() * 500 + 20,
              rnd.nextDouble() * 800),
      ];
      final page = PageContent(strokes: strokes, texts: [
        for (var i = 0; i < 20; i++)
          TextItem(
              id: 't$i',
              x: rnd.nextDouble() * 500,
              y: rnd.nextDouble() * 800,
              width: 60,
              height: 20),
      ]);
      final index = SpatialIndex.forPage(page);
      for (var k = 0; k < 30; k++) {
        // Random star-shaped lassos.
        final c = Vec2(rnd.nextDouble() * 595, rnd.nextDouble() * 842);
        final lasso = [
          for (var a = 0; a < 40; a++)
            c +
                Vec2(math.cos(a * math.pi / 20), math.sin(a * math.pi / 20)) *
                    (60 + rnd.nextDouble() * 120),
        ];
        final plain = lassoSelect(pageId: pageId, page: page, lasso: lasso);
        final fast =
            lassoSelect(pageId: pageId, page: page, lasso: lasso, index: index);
        expect(fast.strokeIds, plain.strokeIds);
        expect(fast.textIds, plain.textIds);
        expect(fast.bounds, plain.bounds);
      }
    });

    test('an empty or non-finite lasso selects nothing', () {
      final page = PageContent(strokes: [hStroke('s', 0, 10, 10)]);
      expect(lassoSelect(pageId: pageId, page: page, lasso: const []).isEmpty,
          isTrue);
      expect(
          lassoSelect(
                  pageId: pageId,
                  page: page,
                  lasso: const [Vec2(double.nan, 0)])
              .isEmpty,
          isTrue);
    });
  });

  group('tiny lasso = tap', () {
    // Paint order bottom → top: image, highlighter, text, pen strokes.
    PageContent layeredPage() => PageContent(
          strokes: [
            hStroke('pen1', 0, 100, 50),
            hStroke('hl', 0, 100, 50, tool: StrokeTool.highlighter, size: 14),
            hStroke('pen2', 0, 100, 50), // painted after pen1: topmost
          ],
          texts: [const TextItem(id: 't', x: 0, y: 40, width: 100, height: 20)],
          images: [
            const ImageItem(
                id: 'i', x: 0, y: 0, width: 200, height: 200, asset: 'x.png'),
          ],
        );

    test('a tap selects the topmost stroke under the point', () {
      final page = layeredPage();
      final sel = lassoSelect(
          pageId: pageId, page: page, lasso: const [Vec2(50, 51)]);
      expect(sel.strokeIds, {'pen2'});
      expect(sel.textIds, isEmpty);
      expect(sel.imageIds, isEmpty);
      // A tiny scribble (area under the threshold) acts the same.
      final scribble = lassoSelect(pageId: pageId, page: page, lasso: const [
        Vec2(50, 51),
        Vec2(52, 52),
        Vec2(51, 54),
      ]);
      expect(scribble.strokeIds, {'pen2'});
    });

    test('below pen ink: text, then highlighter, then image', () {
      final page = layeredPage();
      // Off the pen line but inside the text box and highlighter band.
      expect(
          tapSelect(pageId: pageId, page: page, point: const Vec2(50, 58))
              .textIds,
          {'t'});
      page.texts.clear();
      expect(
          tapSelect(pageId: pageId, page: page, point: const Vec2(50, 58))
              .strokeIds,
          {'hl'});
      expect(
          tapSelect(pageId: pageId, page: page, point: const Vec2(150, 150))
              .imageIds,
          {'i'});
      expect(
          tapSelect(pageId: pageId, page: page, point: const Vec2(400, 400))
              .isEmpty,
          isTrue);
    });

    test('tap tolerance is the radius beyond the painted outline', () {
      final page = PageContent(strokes: [hStroke('s', 0, 100, 50, size: 2)]);
      // Outline reaches y = 51; default tap radius 5 → hits up to y = 56.
      expect(
          tapSelect(pageId: pageId, page: page, point: const Vec2(50, 55.9))
              .strokeIds,
          {'s'});
      expect(
          tapSelect(pageId: pageId, page: page, point: const Vec2(50, 56.1))
              .isEmpty,
          isTrue);
      expect(
          lassoSelect(
                  pageId: pageId,
                  page: page,
                  lasso: const [Vec2(50, 58)],
                  tapRadius: 8)
              .strokeIds,
          {'s'});
    });
  });

  group('Selection', () {
    test('refreshed drops ids that are gone and recomputes bounds', () {
      final a = hStroke('a', 0, 10, 10), b = hStroke('b', 100, 110, 10);
      final page = PageContent(strokes: [a, b]);
      final sel = Selection.fromPage(page,
          pageId: pageId, strokeIds: ['a', 'b', 'ghost']);
      expect(sel.strokeIds, {'a', 'b'});
      page.strokes.remove(b);
      final r = sel.refreshed(page);
      expect(r.strokeIds, {'a'});
      expect(r.bounds, a.paintBounds);
    });

    test('union merges ids and bounds', () {
      final a = hStroke('a', 0, 10, 10);
      const t = TextItem(id: 't', x: 50, y: 50, width: 10, height: 10);
      final page = PageContent(strokes: [a], texts: [t]);
      final s1 = Selection.fromPage(page, pageId: pageId, strokeIds: ['a']);
      final s2 = Selection.fromPage(page, pageId: pageId, textIds: ['t']);
      final u = s1.union(s2, page);
      expect(u.strokeIds, {'a'});
      expect(u.textIds, {'t'});
      expect(u.bounds, a.paintBounds.union(t.frame));
      expect(Selection.empty(pageId).isEmpty, isTrue);
      expect(Selection.empty(pageId).bounds, InkRect.empty);
      expect(u.strokesOn(page), [a]);
      expect(u.textsOn(page), [t]);
    });
  });
}
