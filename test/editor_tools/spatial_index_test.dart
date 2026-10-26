import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/features/editor/tools/spatial_index.dart';
import 'package:neatink/features/editor/tools/tool_config.dart';
import 'package:neatink/ink/affine2.dart';
import 'package:neatink/ink/ink_rect.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';

import 'tool_test_utils.dart';

/// A random scribble: a short random walk somewhere on an A4 page.
Stroke randomStroke(math.Random rnd, String id) {
  var p = Vec2(rnd.nextDouble() * 595, rnd.nextDouble() * 842);
  final n = 1 + rnd.nextInt(30);
  final step = rnd.nextBool() ? 2.0 : 12.0; // some long, sprawling strokes
  final pts = <Vec2>[p];
  for (var i = 1; i < n; i++) {
    p = p + Vec2(rnd.nextDouble() * 2 - 1, rnd.nextDouble() * 2 - 1) * step;
    pts.add(p);
  }
  return strokeOf(id, pts, size: 0.5 + rnd.nextDouble() * 12);
}

TextItem randomText(math.Random rnd, String id) => TextItem(
    id: id,
    x: rnd.nextDouble() * 550,
    y: rnd.nextDouble() * 800,
    width: 10 + rnd.nextDouble() * 200,
    height: 10 + rnd.nextDouble() * 60);

ImageItem randomImage(math.Random rnd, String id) => ImageItem(
    id: id,
    x: rnd.nextDouble() * 500,
    y: rnd.nextDouble() * 700,
    width: 5 + rnd.nextDouble() * 300,
    height: 5 + rnd.nextDouble() * 300,
    asset: '$id.png');

InkRect randomQuery(math.Random rnd) {
  final x = rnd.nextDouble() * 700 - 50, y = rnd.nextDouble() * 950 - 50;
  // Mostly eraser-sized queries, sometimes lasso-sized ones.
  final big = rnd.nextInt(5) == 0;
  final w = rnd.nextDouble() * (big ? 400 : 30);
  final h = rnd.nextDouble() * (big ? 400 : 30);
  return InkRect(x, y, x + w, y + h);
}

Set<String> bruteStrokes(PageContent page, InkRect q) => {
      for (final s in page.strokes)
        if (s.paintBounds.overlaps(q)) s.id,
    };

void expectMatchesBruteForce(SpatialIndex index, PageContent page, InkRect q) {
  expect(index.strokesIn(q).map((s) => s.id).toSet(), bruteStrokes(page, q),
      reason: 'strokes in $q');
  expect(index.textsIn(q).map((t) => t.id).toSet(), {
    for (final t in page.texts)
      if (t.frame.overlaps(q)) t.id,
  });
  expect(index.imagesIn(q).map((i) => i.id).toSet(), {
    for (final i in page.images)
      if (i.frame.overlaps(q)) i.id,
  });
  // No duplicates even for entries spanning many cells.
  final ids = index.strokesIn(q).map((s) => s.id).toList();
  expect(ids.length, ids.toSet().length);
}

void main() {
  group('SpatialIndex', () {
    test('queries equal brute force on random pages', () {
      final rnd = math.Random(42);
      final page = PageContent(
        strokes: [for (var i = 0; i < 3000; i++) randomStroke(rnd, 's$i')],
        texts: [for (var i = 0; i < 40; i++) randomText(rnd, 't$i')],
        images: [for (var i = 0; i < 15; i++) randomImage(rnd, 'i$i')],
      );
      final index = SpatialIndex.forPage(page);
      expect(index.strokeCount, 3000);
      expect(index.textCount, 40);
      expect(index.imageCount, 15);
      for (var k = 0; k < 400; k++) {
        expectMatchesBruteForce(index, page, randomQuery(rnd));
      }
      // The whole page and beyond.
      expectMatchesBruteForce(index, page, const InkRect(-1e4, -1e4, 1e4, 1e4));
    });

    test('incremental add / remove / replace stays equal to brute force', () {
      final rnd = math.Random(7);
      final page = PageContent();
      final index = SpatialIndex(config: const ToolConfig(spatialCellSizePt: 32));
      var next = 0;
      for (var round = 0; round < 1500; round++) {
        final op = rnd.nextInt(10);
        if (op < 5 || page.strokes.isEmpty) {
          final s = randomStroke(rnd, 's${next++}');
          page.strokes.add(s);
          index.addStroke(s);
        } else if (op < 8) {
          final i = rnd.nextInt(page.strokes.length);
          // Same id, new geometry (e.g. a lasso move).
          final moved = page.strokes[i].transformed(
              Affine2.translation(rnd.nextDouble() * 100 - 50, rnd.nextDouble() * 100 - 50));
          page.strokes[i] = moved;
          index.replaceStroke(moved);
        } else {
          final s = page.strokes.removeAt(rnd.nextInt(page.strokes.length));
          expect(index.removeStroke(s.id), isTrue);
        }
        if (round % 25 == 0) {
          expectMatchesBruteForce(index, page, randomQuery(rnd));
        }
      }
      expect(index.strokeCount, page.strokes.length);
      for (var k = 0; k < 200; k++) {
        expectMatchesBruteForce(index, page, randomQuery(rnd));
      }
      expect(index.removeStroke('missing'), isFalse);
    });

    test('sync follows page edits by identity and revision', () {
      final rnd = math.Random(3);
      final page = PageContent(
          strokes: [for (var i = 0; i < 200; i++) randomStroke(rnd, 's$i')],
          texts: [randomText(rnd, 't0')]);
      final index = SpatialIndex.forPage(page);
      expect(index.sync(page), isFalse, reason: 'nothing changed');

      // Simulate commands: remove some, replace some, add some.
      page.strokes.removeRange(0, 50);
      page.strokes[10] = page.strokes[10].transformed(Affine2.translation(300, 0));
      page.strokes.addAll([for (var i = 0; i < 30; i++) randomStroke(rnd, 'n$i')]);
      page.texts.clear();
      page.images.add(randomImage(rnd, 'i0'));
      page.touch();

      expect(index.sync(page), isTrue);
      expect(index.strokeCount, page.strokes.length);
      expect(index.textCount, 0);
      expect(index.imageCount, 1);
      expect(index.stroke('s0'), isNull);
      expect(index.stroke(page.strokes[10].id), same(page.strokes[10]));
      for (var k = 0; k < 200; k++) {
        expectMatchesBruteForce(index, page, randomQuery(rnd));
      }
    });

    test('huge and far-away entries go to the overflow list', () {
      final page = PageContent(strokes: [
        strokeOf('huge', [const Vec2(-5e5, -5e5), const Vec2(5e5, 5e5)]),
        strokeOf('far', [const Vec2(3e9, 3e9), const Vec2(3e9 + 5, 3e9)]),
        strokeOf('near', [const Vec2(10, 10), const Vec2(20, 10)]),
      ]);
      final index = SpatialIndex.forPage(page);
      expect(index.strokesIn(const InkRect(0, 0, 30, 30)).map((s) => s.id).toSet(),
          {'huge', 'near'});
      expect(
          index
              .strokesIn(const InkRect(3e9 - 1, 3e9 - 1, 3e9 + 1, 3e9 + 1))
              .map((s) => s.id),
          ['far']);
      index.removeStroke('huge');
      expect(index.strokesIn(const InkRect(0, 0, 30, 30)).map((s) => s.id),
          ['near']);
    });

    test('edges are inclusive and non-finite queries return nothing', () {
      final s = strokeOf('a', [const Vec2(10, 10), const Vec2(20, 10)], size: 1);
      final index = SpatialIndex()..addStroke(s);
      final pb = s.paintBounds;
      expect(index.strokesIn(InkRect(pb.right, pb.top, pb.right + 5, pb.top)),
          hasLength(1));
      expect(index.strokesIn(InkRect(pb.right + 0.01, 0, 100, 100)), isEmpty);
      expect(
          index.strokesIn(const InkRect(double.nan, 0, 100, 100)), isEmpty);
      index.clear();
      expect(index.isEmpty, isTrue);
    });

    test('items can be added, replaced and removed', () {
      final index = SpatialIndex();
      const t = TextItem(id: 't', x: 0, y: 0, width: 50, height: 20);
      index.addText(t);
      expect(index.textsIn(const InkRect(40, 10, 45, 15)), [t]);
      final moved = t.copyWith(x: 200);
      index.addText(moved);
      expect(index.textCount, 1);
      expect(index.textsIn(const InkRect(40, 10, 45, 15)), isEmpty);
      expect(index.text('t'), same(moved));
      expect(index.removeText('t'), isTrue);
      const img = ImageItem(
          id: 'i', x: 0, y: 0, width: 10, height: 10, asset: 'x.png');
      index.addImage(img);
      expect(index.imagesIn(const InkRect(5, 5, 6, 6)), [img]);
      expect(index.removeImage('i'), isTrue);
      expect(index.isEmpty, isTrue);
    });
  });
}
