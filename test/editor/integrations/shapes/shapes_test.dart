import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/integrations/shapes/hold_snap_hook.dart';
import 'package:neatink/features/editor/integrations/shapes/shape_prefs.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';

import 'harness.dart';

void main() {
  group('registration', () {
    testWidgets('registers the shape tool, its options and the snap hook',
        (tester) async {
      final h = await ShapesHarness.open(tester);
      final ext = h.controller.extensions;
      expect(ext.toolHandlers[EditorTool.shape], isNotNull);
      expect(ext.toolOptions[EditorTool.shape], isNotNull);
      expect(ext.liveStrokeHook, isA<HoldSnapHook>());
      expect(h.controller.isToolAvailable(EditorTool.shape), isTrue);
      await h.close();
    });
  });

  group('shape tool', () {
    testWidgets('a drag draws the selected shape as one undo step',
        (tester) async {
      final h = await ShapesHarness.open(tester);
      selectShapeKind(h.controller, ShapeKind.rectangle);
      h.controller.selectTool(EditorTool.shape);
      await tester.pump();

      final g = await h.beginDrag(const Vec2(100, 100));
      await g.moveTo(h.at(const Vec2(300, 250)));
      await tester.pump();
      // Previewed live, not yet committed.
      expect(h.strokes, isEmpty);
      expect(h.undoDepth, 0);
      await g.up();
      await tester.pump();

      expect(h.strokes.length, 1);
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.rectangle);
      expect(s.raw.length, greaterThanOrEqualTo(2));
      final xs = s.points.map((p) => p.x);
      final ys = s.points.map((p) => p.y);
      expect(xs.reduce(math.min), closeTo(100, 1));
      expect(xs.reduce(math.max), closeTo(300, 1));
      expect(ys.reduce(math.min), closeTo(100, 1));
      expect(ys.reduce(math.max), closeTo(250, 1));
      expect(h.undoDepth, 1);

      h.controller.undo();
      expect(h.strokes, isEmpty);
      h.controller.redo();
      expect(h.strokes.single.shape, ShapeKind.rectangle);
      await h.close();
    });

    for (final kind in ShapeKind.values) {
      testWidgets('draws a ${kind.name}', (tester) async {
        final h = await ShapesHarness.open(tester);
        selectShapeKind(h.controller, kind);
        h.controller.selectTool(EditorTool.shape);
        await tester.pump();
        await h.drag([const Vec2(120, 150), const Vec2(320, 300)]);
        expect(h.strokes.single.shape, kind);
        await h.close();
      });
    }

    testWidgets('a line goes from pen-down to pen-up', (tester) async {
      final h = await ShapesHarness.open(tester);
      selectShapeKind(h.controller, ShapeKind.line);
      h.controller.selectTool(EditorTool.shape);
      await tester.pump();
      await h.drag([const Vec2(100, 100), const Vec2(250, 180)]);
      final s = h.strokes.single;
      expect(s.points.first.x, closeTo(100, 0.5));
      expect(s.points.first.y, closeTo(100, 0.5));
      expect(s.points.last.x, closeTo(250, 0.5));
      expect(s.points.last.y, closeTo(180, 0.5));
      await h.close();
    });

    testWidgets('uses the pen colour and size', (tester) async {
      final h = await ShapesHarness.open(tester);
      selectShapeKind(h.controller, ShapeKind.line);
      h.controller.selectTool(EditorTool.shape);
      await tester.pump();
      await h.drag([const Vec2(100, 100), const Vec2(250, 180)]);
      final pen = h.controller.toolPrefs.pen;
      expect(h.strokes.single.color, pen.color);
      expect(h.strokes.single.size, pen.size);
      await h.close();
    });

    testWidgets('a cancelled drag adds nothing', (tester) async {
      final h = await ShapesHarness.open(tester);
      h.controller.selectTool(EditorTool.shape);
      await tester.pump();
      final g = await h.beginDrag(const Vec2(100, 100));
      await g.moveTo(h.at(const Vec2(300, 250)));
      await tester.pump();
      await g.cancel();
      await tester.pump();
      expect(h.strokes, isEmpty);
      expect(h.undoDepth, 0);
      await h.close();
    });

    testWidgets('a tap draws nothing', (tester) async {
      final h = await ShapesHarness.open(tester);
      h.controller.selectTool(EditorTool.shape);
      await tester.pump();
      await h.drag([const Vec2(100, 100)]);
      expect(h.strokes, isEmpty);
      expect(h.undoDepth, 0);
      await h.close();
    });

    testWidgets('committing pending work saves a drag in progress',
        (tester) async {
      final h = await ShapesHarness.open(tester);
      selectShapeKind(h.controller, ShapeKind.ellipse);
      h.controller.selectTool(EditorTool.shape);
      await tester.pump();
      final g = await h.beginDrag(const Vec2(100, 100));
      await g.moveTo(h.at(const Vec2(300, 250)));
      await tester.pump();
      h.controller.handlerFor(EditorTool.shape)!.commitPending();
      expect(h.strokes.single.shape, ShapeKind.ellipse);
      await g.up();
      await tester.pump();
      expect(h.strokes.length, 1);
      await h.close();
    });
  });

  group('hold to snap', () {
    List<Vec2> wobblyLine() => [
          for (var i = 0; i <= 30; i++)
            Vec2(100 + i * 8.0, 200 + (i.isEven ? 1.5 : -1.5)),
        ];

    Future<void> drawAndHold(ShapesHarness h, List<Vec2> pts) async {
      final g = await h.beginDrag(pts.first);
      for (final p in pts.skip(1)) {
        await g.moveTo(h.at(p));
        await h.tester.pump(const Duration(milliseconds: 8));
      }
      await h.tester.pump(const Duration(milliseconds: 1200));
      await g.up();
      await h.tester.pump();
    }

    testWidgets('holding the pen at the end snaps a drawn line',
        (tester) async {
      final h = await ShapesHarness.open(tester);
      await drawAndHold(h, wobblyLine());
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      // The hand-drawn ink is kept as raw.
      expect(s.raw.length, greaterThan(10));
      final ys = s.points.map((p) => p.y);
      expect(ys.reduce(math.max) - ys.reduce(math.min), lessThan(1));
      await h.close();
    });

    testWidgets('without holding the stroke stays as drawn', (tester) async {
      final h = await ShapesHarness.open(tester);
      await h.drag(wobblyLine());
      expect(h.strokes.single.shape, isNull);
      await h.close();
    });

    testWidgets('does nothing when snapping is switched off', (tester) async {
      final h = await ShapesHarness.open(tester);
      h.controller.applySettings(
          h.controller.settings.copyWith(shapeSnapEnabled: false));
      await drawAndHold(h, wobblyLine());
      expect(h.strokes.single.shape, isNull);
      await h.close();
    });

    // v1.11.0: an arrow drawn in one stroke, with a pause at the tip of its
    // shaft, lost its head: the pause snapped the shaft to a line and the
    // head then moved the line's end.
    Future<Stroke> pauseThen(ShapesHarness h, List<Vec2> after) async {
      final pts = wobblyLine();
      final g = await h.beginDrag(pts.first);
      for (final p in pts.skip(1)) {
        await g.moveTo(h.at(p));
        await h.tester.pump(const Duration(milliseconds: 8));
      }
      await h.tester.pump(const Duration(milliseconds: 1200));
      for (final p in after) {
        await g.moveTo(h.at(p));
        await h.tester.pump(const Duration(milliseconds: 8));
      }
      await g.up();
      await h.tester.pump();
      return h.strokes.single;
    }

    testWidgets("a pause at an arrow's tip, then its head: the ink stays as drawn", (tester) async {
      final h = await ShapesHarness.open(tester);
      // The shaft ends at (340, 200); the head goes back up, to the tip, back down.
      final s = await pauseThen(h, [
        for (var i = 1; i <= 6; i++) Vec2(340 - 2.0 * i, 200 - 2.0 * i),
        for (var i = 5; i >= 0; i--) Vec2(340 - 2.0 * i, 200 - 2.0 * i),
        for (var i = 1; i <= 6; i++) Vec2(340 - 2.0 * i, 200 + 2.0 * i),
      ]);
      expect(s.shape, isNull);
      expect(s.points.map((p) => p.y).reduce(math.min), lessThan(190), reason: 'the head is there');
      await h.close();
    });

    testWidgets('after the snap, moving on ahead or back along it still adjusts the line', (tester) async {
      for (final after in [
        [for (var i = 1; i <= 8; i++) Vec2(340 + 4.0 * i, 200 + 1.0 * i)],
        [for (var i = 1; i <= 8; i++) Vec2(340 - 4.0 * i, 200)],
      ]) {
        final h = await ShapesHarness.open(tester);
        final s = await pauseThen(h, after);
        expect(s.shape, ShapeKind.line);
        expect(s.points.last.x, closeTo(after.last.x, 1));
        await h.close();
      }
    });

    testWidgets('a held scribble is not snapped', (tester) async {
      final h = await ShapesHarness.open(tester);
      final rnd = math.Random(3);
      await drawAndHold(h, [
        for (var i = 0; i < 40; i++)
          Vec2(150 + rnd.nextDouble() * 80, 300 + rnd.nextDouble() * 80),
      ]);
      expect(h.strokes.single.shape, isNull);
      await h.close();
    });
  });
}
