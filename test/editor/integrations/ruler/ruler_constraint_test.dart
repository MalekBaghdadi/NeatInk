import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/editor_extensions.dart';
import 'package:neatink/features/editor/editor_integrations.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_edge_constraint.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_geometry.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_model.dart';
import 'package:neatink/features/editor/integrations/shapes/hold_snap_hook.dart';
import 'package:neatink/features/editor/integrations/shapes/shapes_integration.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';

import '../../canvas/canvas_harness.dart';
import 'ruler_harness.dart';
import 'ruler_test_utils.dart';

CanvasPointerEvent penAt(Offset local) => CanvasPointerEvent(
      event: PointerDownEvent(
          position: local, kind: PointerDeviceKind.stylus),
      localPosition: local,
      hit: null,
      pressure: 0.5,
    );

void main() {
  group('the constraint provider', () {
    late RulerModel model;
    late StrokeConstraintProvider provider;

    setUp(() {
      // Centre (500, 304), 920 x 96, flat: edges at y = 256 and y = 352.
      model = RulerModel()..show(const Size(1000, 800));
      provider = rulerConstraintProvider(model);
      addTearDown(model.dispose);
    });

    test('a hidden ruler constrains nothing', () {
      model.hide();
      expect(provider(penAt(const Offset(300, 256))), isNull);
    });

    test('a pen on or beside an edge is pulled onto it', () {
      for (final y in [256.0, 250.0, 240.0, 232.0, 270.0, 280.0]) {
        final c = provider(penAt(Offset(300, y)));
        expect(c, isA<RulerEdgeConstraint>(), reason: 'y = $y');
        expect((c! as RulerEdgeConstraint).edge, RulerEdge.top);
        // Anything projects onto that edge.
        expect(c.project(const Offset(420, 90)),
            offsetCloseTo(const Offset(420, 256)));
      }
      final bottom = provider(penAt(const Offset(300, 360)))!;
      expect((bottom as RulerEdgeConstraint).edge, RulerEdge.bottom);
      expect(bottom.project(const Offset(420, 90)),
          offsetCloseTo(const Offset(420, 352)));
    });

    test('24 px from an edge is the limit', () {
      expect(provider(penAt(Offset(300, 256 - rulerSnapDistance))), isNotNull);
      expect(provider(penAt(Offset(300, 256 - rulerSnapDistance - 0.5))), isNull);
      expect(provider(penAt(Offset(300, 256 + rulerSnapDistance))), isNotNull);
      expect(provider(penAt(Offset(300, 352 + rulerSnapDistance))), isNotNull);
      expect(provider(penAt(Offset(300, 352 + rulerSnapDistance + 0.5))), isNull);
    });

    test('the middle of the body and the page beyond it are free', () {
      expect(provider(penAt(const Offset(300, 304))), isNull);
      expect(provider(penAt(const Offset(300, 600))), isNull);
      expect(provider(penAt(const Offset(300, 100))), isNull);
    });

    test('the line stops at the ruler\'s ends', () {
      final c = provider(penAt(const Offset(300, 250)))!;
      expect(c.project(const Offset(-500, 250)),
          offsetCloseTo(const Offset(40, 256)));
      expect(c.project(const Offset(5000, 250)),
          offsetCloseTo(const Offset(960, 256)));
    });

    test('a pen just past the end of the ruler still draws along it', () {
      final c = provider(penAt(const Offset(40 - 10, 250)));
      expect(c, isNotNull);
      expect(c!.project(const Offset(30, 250)),
          offsetCloseTo(const Offset(40, 256)));
      expect(provider(penAt(const Offset(40 - 30, 250))), isNull);
    });

    test('the constraint is a snapshot: moving the ruler later does not '
        'move the line', () {
      final c = provider(penAt(const Offset(300, 250)))!;
      model.translate(const Offset(100, 200));
      model.rotateBy(rad(30));
      expect(c.project(const Offset(420, 90)),
          offsetCloseTo(const Offset(420, 256)));
    });

    test('works on a turned ruler', () {
      model.rotateBy(rad(90));
      final g = model.geometry;
      // The top edge is now on the right of the centre.
      final onEdge = g.edgePoint(RulerEdge.top, 100);
      final c = provider(penAt(onEdge + const Offset(8, 0)))!;
      expect(c.project(const Offset(900, 450)),
          offsetCloseTo(Offset(onEdge.dx, 450)));
    });
  });

  group('drawing along the ruler', () {
    /// Opens the editor with the ruler showing.
    Future<CanvasHarness> open(WidgetTester tester,
        {List<EditorIntegration> more = const []}) async {
      final h = await openWithRuler(tester, more: more);
      h.ruler.show(h.viewSize);
      await tester.pump();
      return h;
    }

    double topY(CanvasHarness h) {
      final g = h.ruler.geometry;
      return g.center.dy - g.thickness / 2;
    }

    double bottomY(CanvasHarness h) {
      final g = h.ruler.geometry;
      return g.center.dy + g.thickness / 2;
    }

    /// A pen path along y +- wobble, from x0 to x1 in steps of 20 px (the pen
    /// may go either way).
    List<Offset> wobbly(double y, double x0, double x1, {double wobble = 6}) {
      final step = x1 >= x0 ? 20.0 : -20.0;
      final n = ((x1 - x0) / step).floor();
      return [
        for (var i = 0; i <= n; i++)
          Offset(x0 + i * step, y + (i.isEven ? wobble : -wobble)),
      ];
    }

    double offEdge(CanvasHarness h, InkPoint p, RulerEdge edge) {
      final g = h.ruler.geometry;
      final l = h.local(p.pos);
      final edgeY = edge == RulerEdge.top ? topY(h) : bottomY(h);
      expect(g.angle, 0, reason: 'helper is for a flat ruler');
      return (l.dy - edgeY).abs();
    }

    testWidgets('a wobbly pen along the top edge gives a straight line',
        (tester) async {
      final h = await open(tester);
      final y = topY(h);
      final path = wobbly(y - 8, 100, 900);
      await h.drag(path);

      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      expect(s.points.length, greaterThan(50));
      for (final p in s.points) {
        expect(offEdge(h, p, RulerEdge.top), lessThan(0.05));
      }
      expect(h.local(s.points.first.pos).dx, closeTo(100, 0.05));
      expect(h.local(s.points.last.pos).dx, closeTo(900, 0.05));
      // The pen's own wobble is kept.
      expect(s.raw.length, path.length);
      final raws = s.raw.map((p) => h.local(p.pos).dy);
      expect(raws.reduce(math.max) - raws.reduce(math.min), greaterThan(8));
      expect(h.controller.undoLabel, 'Shape');
      await h.close();
    });

    testWidgets('and along the bottom edge', (tester) async {
      final h = await open(tester);
      final y = bottomY(h);
      await h.drag(wobbly(y + 10, 900, 200));
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      for (final p in s.points) {
        expect(offEdge(h, p, RulerEdge.bottom), lessThan(0.05));
      }
      // Drawn right to left.
      expect(s.points.first.x, greaterThan(s.points.last.x));
      await h.close();
    });

    testWidgets('a pen that starts inside the body draws along the edge too',
        (tester) async {
      final h = await open(tester);
      await h.drag(wobbly(topY(h) + 15, 100, 500));
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      for (final p in s.points) {
        expect(offEdge(h, p, RulerEdge.top), lessThan(0.05));
      }
      await h.close();
    });

    testWidgets('the line cannot run past the end of the ruler',
        (tester) async {
      final h = await open(tester);
      final g = h.ruler.geometry;
      final right = g.center.dx + g.length / 2;
      await h.drag(wobbly(topY(h) - 6, 600, right + 100));
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      expect(h.local(s.points.last.pos).dx, closeTo(right, 0.05));
      await h.close();
    });

    testWidgets('a pen that lands just before the end starts at the end',
        (tester) async {
      final h = await open(tester);
      final g = h.ruler.geometry;
      final left = g.center.dx - g.length / 2;
      await h.drag([
        Offset(left - 10, topY(h) - 5),
        Offset(left + 200, topY(h) - 5),
      ]);
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      expect(h.local(s.points.first.pos).dx, closeTo(left, 0.05));
      await h.close();
    });

    testWidgets('a pen away from the ruler draws freely', (tester) async {
      final h = await open(tester);
      final path = wobbly(topY(h) - 60, 100, 500);
      await h.drag(path);
      final s = h.strokes.single;
      expect(s.shape, isNull);
      expect(s.pointsAreRaw, isTrue);
      expect(s.raw.length, path.length);
      await h.close();
    });

    testWidgets('a pen in the middle of the body draws freely', (tester) async {
      final h = await open(tester);
      final y = h.ruler.geometry.center.dy;
      await h.drag(wobbly(y, 100, 500));
      expect(h.strokes.single.shape, isNull);
      await h.close();
    });

    testWidgets('a hidden ruler draws freely even at its place',
        (tester) async {
      final h = await open(tester);
      final y = topY(h);
      h.ruler.hide();
      await h.drag(wobbly(y - 8, 100, 500));
      expect(h.strokes.single.shape, isNull);
      await h.close();
    });

    testWidgets('a tap on an edge is a dot', (tester) async {
      final h = await open(tester);
      await h.drag([Offset(300, topY(h) - 5)]);
      final s = h.strokes.single;
      expect(s.shape, isNull);
      expect(s.raw.length, 1);
      await h.close();
    });

    testWidgets('a pen that only moves across the edge draws no line',
        (tester) async {
      final h = await open(tester);
      await h.drag([Offset(300, topY(h) - 5), Offset(300, topY(h) + 15)]);
      expect(h.strokes.single.shape, isNull);
      await h.close();
    });

    testWidgets('the live layer shows the straight line while drawing',
        (tester) async {
      final h = await open(tester);
      final y = topY(h);
      final path = wobbly(y - 8, 100, 700);
      final g = await h.down(path.first);
      for (var i = 1; i < 15; i++) {
        await h.moveTo(g, path[i]);
      }
      final active = h.controller.inkTool.active!;
      final preview = active.preview!;
      expect(preview.shape, ShapeKind.line);
      for (final p in preview.points) {
        expect(offEdge(h, p, RulerEdge.top), lessThan(0.05));
      }
      expect(h.strokes, isEmpty);
      await g.up();
      await tester.pump();
      await h.close();
    });

    testWidgets('a ruler turned by 30 degrees', (tester) async {
      final h = await open(tester);
      h.ruler.rotateBy(rad(30));
      await tester.pump();
      final g = h.ruler.geometry;
      expect(g.angle, closeTo(rad(30), 1e-12));

      final from = g.edgePoint(RulerEdge.top, -200) + g.normal * -9;
      final to = g.edgePoint(RulerEdge.top, 300) + g.normal * 12;
      final mid = Offset.lerp(from, to, 0.5)! + g.normal * 7;
      await h.drag([from, mid, to]);

      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      final start = g.edgePoint(RulerEdge.top, -200);
      final end = g.edgePoint(RulerEdge.top, 300);
      expect(h.local(s.points.first.pos), offsetCloseTo(start, 0.05));
      expect(h.local(s.points.last.pos), offsetCloseTo(end, 0.05));
      for (final p in s.points) {
        final l = h.local(p.pos) - start;
        final across = l.dx * g.normal.dx + l.dy * g.normal.dy;
        expect(across.abs(), lessThan(0.05));
      }
      await h.close();
    });

    testWidgets('a vertical ruler', (tester) async {
      final h = await open(tester);
      h.ruler.rotateBy(rad(90));
      await tester.pump();
      final g = h.ruler.geometry;
      final from = g.edgePoint(RulerEdge.bottom, -150) + g.normal * 8;
      final to = g.edgePoint(RulerEdge.bottom, 200) + g.normal * -5;
      await h.drag([from, to]);
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      final x = g.edgePoint(RulerEdge.bottom, 0).dx;
      for (final p in s.points) {
        expect(h.local(p.pos).dx, closeTo(x, 0.05));
      }
      await h.close();
    });

    testWidgets('the highlighter draws along the ruler too', (tester) async {
      final h = await open(tester);
      h.controller.selectTool(EditorTool.highlighter);
      await h.drag(wobbly(topY(h) - 5, 100, 600));
      final s = h.strokes.single;
      expect(s.tool, StrokeTool.highlighter);
      expect(s.shape, ShapeKind.line);
      await h.close();
    });

    testWidgets('keeps the pen\'s colour, size and line style', (tester) async {
      final h = await open(tester);
      h.controller.setPenColor(0xFFD93025);
      h.controller.setPenSize(3.6);
      await h.drag(wobbly(topY(h) - 5, 100, 600));
      final s = h.strokes.single;
      expect(s.color, 0xFFD93025);
      expect(s.size, 3.6);
      await h.close();
    });

    testWidgets('the ruler wins over horizontal drawing at its edge, and '
        'horizontal drawing applies elsewhere', (tester) async {
      final h = await open(tester);
      h.ruler.rotateBy(rad(30));
      h.controller.setPenHorizontal(true);
      await tester.pump();
      final g = h.ruler.geometry;

      final from = g.edgePoint(RulerEdge.top, -200) + g.normal * -5;
      final to = g.edgePoint(RulerEdge.top, 200) + g.normal * -5;
      await h.drag([from, to]);
      var s = h.strokes.last;
      // Slanted along the ruler, not level.
      expect((s.points.last.y - s.points.first.y).abs(), greaterThan(50));

      // Away from the ruler the switch gives a level line.
      await h.drag([const Offset(100, 1000), const Offset(500, 1100)]);
      s = h.strokes.last;
      expect(s.shape, ShapeKind.line);
      expect((s.points.last.y - s.points.first.y).abs(), lessThan(0.01));
      await h.close();
    });

    testWidgets('moving the ruler while the pen is down does not bend the line',
        (tester) async {
      final h = await open(tester);
      final y = topY(h);
      final g = await h.down(Offset(100, y - 5));
      await h.moveTo(g, Offset(300, y - 5));
      h.ruler.translate(const Offset(0, 120));
      h.ruler.rotateBy(rad(40));
      await h.moveTo(g, Offset(500, y - 5));
      await g.up();
      await tester.pump();
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      for (final p in s.points) {
        expect(h.local(p.pos).dy, closeTo(y, 0.05));
      }
      await h.close();
    });

    testWidgets('undo and redo treat it like any shape', (tester) async {
      final h = await open(tester);
      await h.drag(wobbly(topY(h) - 5, 100, 600));
      h.controller.undo();
      expect(h.strokes, isEmpty);
      h.controller.redo();
      expect(h.strokes.single.shape, ShapeKind.line);
      expect(h.strokes.single.raw.length, greaterThan(10));
      await h.close();
    });

    testWidgets('a finger that draws draws along an edge', (tester) async {
      final h = await open(tester);
      h.controller.applySettings(
          h.controller.settings.copyWith(drawWithFinger: true));
      await tester.pump(const Duration(seconds: 1));
      final before = h.ruler.geometry;
      await h.drag(wobbly(topY(h) - 6, 100, 500),
          kind: PointerDeviceKind.touch);
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      for (final p in s.points) {
        expect(offEdge(h, p, RulerEdge.top), lessThan(0.05));
      }
      expect(h.ruler.geometry, before, reason: 'the ruler did not move');
      await h.close();
    });

    testWidgets('holding the pen on a ruler line does not snap it to a shape',
        (tester) async {
      final h = await open(tester, more: [shapesIntegration]);
      final y = topY(h);
      final path = wobbly(y - 8, 100, 700);
      final g = await h.down(path.first);
      for (final p in path.skip(1)) {
        await h.moveTo(g, p);
      }
      await tester.pump(const Duration(milliseconds: 1200));
      expect(
          (h.controller.extensions.liveStrokeHook! as HoldSnapHook).hasSnapped,
          isFalse);
      await g.up();
      await tester.pump();
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      for (final p in s.points) {
        expect(offEdge(h, p, RulerEdge.top), lessThan(0.05));
      }
      await h.close();
    });
  });
}
