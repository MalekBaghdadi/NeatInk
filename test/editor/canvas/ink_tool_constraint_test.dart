import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/canvas/stroke_constraint.dart';
import 'package:neatink/features/editor/editor_extensions.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/stroke_events.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/line_style.dart';
import 'package:neatink/ink/stroke.dart';

import 'canvas_harness.dart';

/// Pulls positions onto the straight line through [a] and [b] (screen space).
Offset Function(Offset) alongLine(Offset a, Offset b) {
  final d = (b - a) / (b - a).distance;
  return (p) {
    final s = (p - a).dx * d.dx + (p - a).dy * d.dy;
    return a + d * s;
  };
}

/// A constraint that keeps the height of [y] (screen space).
FnConstraint levelAt(double y) => FnConstraint((p) => Offset(p.dx, y));

void main() {
  const lineA = Offset(100, 400);
  const lineB = Offset(900, 800);
  final diagonal = FnConstraint(alongLine(lineA, lineB));

  /// A hand-drawn wobbly path that follows [lineA]-[lineB] loosely.
  List<Offset> wobblyAlongDiagonal() => [
        for (var i = 0; i <= 60; i++)
          Offset(100 + i * 12.0, 400 + i * 6.0) +
              Offset(i.isEven ? 4 : -4, i.isEven ? -7 : 7),
      ];

  /// How far [p] (page points) is from the screen line a-b, in pixels.
  double offLine(CanvasHarness h, InkPoint p, Offset a, Offset b) {
    final l = h.local(p.pos);
    final d = (b - a) / (b - a).distance;
    final v = l - a;
    return (v.dx * d.dy - v.dy * d.dx).abs();
  }

  group('which constraint a stroke gets', () {
    testWidgets('none by default: the stroke is drawn as the pen moved',
        (tester) async {
      final h = await CanvasHarness.open(tester);
      final path = wobblyAlongDiagonal();
      final g = await h.down(path.first);
      expect(h.controller.inkTool.active!.constraint, isNull);
      await g.up();
      await tester.pump();
      h.controller.undo();

      await h.drag(path);
      final s = h.strokes.single;
      expect(s.shape, isNull);
      expect(s.pointsAreRaw, isTrue);
      expect(s.raw.length, path.length);
      await h.close();
    });

    testWidgets('the provider is asked at pen-down with the pen event',
        (tester) async {
      final seen = <CanvasPointerEvent>[];
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) {
          seen.add(e);
          return null;
        }),
      ]);
      final g = await h.down(const Offset(250, 330));
      expect(seen.length, 1);
      expect(seen.single.localPosition, const Offset(250, 330));
      expect(seen.single.kind, PointerDeviceKind.stylus);
      expect(seen.single.hit, isNotNull);
      await h.moveTo(g, const Offset(300, 340));
      await g.up();
      await tester.pump();
      // Asked once per stroke, not per sample.
      expect(seen.length, 1);
      await h.close();
    });

    testWidgets('the provider\'s constraint is used', (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => diagonal),
      ]);
      final g = await h.down(const Offset(120, 420));
      expect(h.controller.inkTool.active!.constraint, same(diagonal));
      await g.up();
      await tester.pump();
      await h.close();
    });

    testWidgets('"Horizontal drawing" keeps the pen-down height',
        (tester) async {
      final h = await CanvasHarness.open(tester);
      h.controller.setPenHorizontal(true);
      final g = await h.down(const Offset(250, 330));
      final c = h.controller.inkTool.active!.constraint;
      expect(c, isA<HorizontalConstraint>());
      expect((c! as HorizontalConstraint).y, 330);
      await g.up();
      await tester.pump();
      await h.close();
    });

    testWidgets('a constraint from the provider wins over horizontal drawing',
        (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => diagonal),
      ]);
      h.controller.setPenHorizontal(true);
      final g = await h.down(const Offset(120, 420));
      expect(h.controller.inkTool.active!.constraint, same(diagonal));
      await g.up();
      await tester.pump();
      await h.close();
    });

    testWidgets(
        'horizontal drawing applies when the provider has no constraint',
        (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => null),
      ]);
      h.controller.setPenHorizontal(true);
      final g = await h.down(const Offset(120, 420));
      expect(h.controller.inkTool.active!.constraint,
          isA<HorizontalConstraint>());
      await g.up();
      await tester.pump();
      await h.close();
    });

    testWidgets('each tool reads its own horizontal switch', (tester) async {
      final h = await CanvasHarness.open(tester);
      h.controller.setPenHorizontal(true);
      h.controller.selectTool(EditorTool.highlighter);
      var g = await h.down(const Offset(120, 420));
      expect(h.controller.inkTool.active!.constraint, isNull,
          reason: 'the highlighter has its own switch');
      await g.up();
      await tester.pump();

      h.controller.setHighlighterHorizontal(true);
      h.controller.setPenHorizontal(false);
      g = await h.down(const Offset(120, 420));
      expect(h.controller.inkTool.active!.constraint,
          isA<HorizontalConstraint>());
      await g.up();
      await tester.pump();

      h.controller.selectTool(EditorTool.pen);
      g = await h.down(const Offset(120, 420));
      expect(h.controller.inkTool.active!.constraint, isNull);
      await g.up();
      await tester.pump();
      await h.close();
    });
  });

  group('a constrained stroke', () {
    testWidgets(
        'a wobbly path along the line commits a straight line, raw kept',
        (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => diagonal),
      ]);
      final path = wobblyAlongDiagonal();
      await h.drag(path);

      expect(h.strokes.length, 1);
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      // raw is exactly what the pen drew...
      expect(s.raw.length, path.length);
      for (var i = 0; i < path.length; i++) {
        final expected = h.page(path[i]);
        expect(s.raw[i].x, closeTo(expected.x, 0.01), reason: 'raw $i');
        expect(s.raw[i].y, closeTo(expected.y, 0.01), reason: 'raw $i');
      }
      // ...it is not on the line, but points is.
      expect(s.raw.map((p) => offLine(h, p, lineA, lineB)).reduce(math.max),
          greaterThan(3));
      expect(s.points.length, greaterThan(50));
      for (final p in s.points) {
        expect(offLine(h, p, lineA, lineB), lessThan(0.05));
      }
      // The line runs from where the pen landed to where it lifted, both
      // pulled onto the line.
      final start = diagonal.project(path.first);
      final end = diagonal.project(path.last);
      expect(h.local(s.points.first.pos).dx, closeTo(start.dx, 0.05));
      expect(h.local(s.points.first.pos).dy, closeTo(start.dy, 0.05));
      expect(h.local(s.points.last.pos).dx, closeTo(end.dx, 0.05));
      expect(h.local(s.points.last.pos).dy, closeTo(end.dy, 0.05));
      await h.close();
    });

    testWidgets('is one undo step called Shape, and undo removes it',
        (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => diagonal),
      ]);
      await h.drag(wobblyAlongDiagonal());
      expect(h.undoDepth, 1);
      expect(h.controller.undoLabel, 'Shape');
      h.controller.undo();
      expect(h.strokes, isEmpty);
      h.controller.redo();
      expect(h.strokes.single.shape, ShapeKind.line);
      await h.close();
    });

    testWidgets('the live layer shows the straight line, not the wobble',
        (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => diagonal),
      ]);
      final path = wobblyAlongDiagonal();
      final g = await h.down(path.first);
      // A single point has no line yet.
      expect(h.controller.inkTool.active!.preview, isNull);
      for (var i = 1; i <= 20; i++) {
        await h.moveTo(g, path[i]);
      }
      final active = h.controller.inkTool.active!;
      final preview = active.preview!;
      expect(identical(active.displayed, preview), isTrue);
      expect(preview.shape, ShapeKind.line);
      for (final p in preview.points) {
        expect(offLine(h, p, lineA, lineB), lessThan(0.05));
      }
      final end = diagonal.project(path[20]);
      expect(h.local(preview.points.last.pos).dx, closeTo(end.dx, 0.05));
      // The pen's own path is kept underneath, and nothing is committed yet.
      expect(preview.raw.length, 21);
      expect(h.strokes, isEmpty);
      expect(h.undoDepth, 0);
      expect(h.controller.liveInkFor(h.pageId).active, same(active));

      // The line follows the pen as it goes on.
      await h.moveTo(g, path[40]);
      final longer = active.preview!;
      expect(h.local(longer.points.last.pos).dx,
          closeTo(diagonal.project(path[40]).dx, 0.05));
      await g.up();
      await tester.pump();
      await h.close();
    });

    testWidgets('the live layer repaints for every sample', (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => diagonal),
      ]);
      final path = wobblyAlongDiagonal();
      final g = await h.down(path.first);
      final layer = h.controller.liveInkFor(h.pageId).layer(StrokeTool.pen);
      var repaints = 0;
      void count() => repaints++;
      layer.addListener(count);
      for (var i = 1; i <= 10; i++) {
        await h.moveTo(g, path[i]);
      }
      layer.removeListener(count);
      expect(repaints, greaterThanOrEqualTo(10));
      await g.up();
      await tester.pump();
      await h.close();
    });

    testWidgets('a pen that wanders off the line does not bend it',
        (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => diagonal),
      ]);
      // Back and forth across the line, ending far from it.
      await h.drag([
        const Offset(100, 400),
        const Offset(300, 700),
        const Offset(500, 300),
        const Offset(700, 800),
        const Offset(900, 450),
      ]);
      final s = h.strokes.single;
      for (final p in s.points) {
        expect(offLine(h, p, lineA, lineB), lessThan(0.05));
      }
      await h.close();
    });

    testWidgets('the pen going back where it started gives a plain stroke',
        (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => diagonal),
      ]);
      // Out and back to the same spot: no line, so the pen's own ink stays.
      await h.drag([
        const Offset(300, 500),
        const Offset(400, 600),
        const Offset(300, 500),
      ]);
      final s = h.strokes.single;
      expect(s.shape, isNull);
      expect(s.pointsAreRaw, isTrue);
      await h.close();
    });

    testWidgets('a tap stays a dot', (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => diagonal),
      ]);
      await h.drag([const Offset(300, 500)]);
      final s = h.strokes.single;
      expect(s.shape, isNull);
      expect(s.pointsAreRaw, isTrue);
      expect(s.raw.length, 1);
      expect(h.controller.undoLabel, 'Pen stroke');
      await h.close();
    });

    testWidgets('a line shorter than a point is not a line', (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => levelAt(500)),
      ]);
      // 0.4 px is a quarter of a point on this screen.
      await h.drag([const Offset(300, 500), const Offset(300.4, 500)]);
      expect(h.strokes.single.shape, isNull);
      // A little longer than one point is a line.
      await h.drag([const Offset(300, 600), const Offset(303, 600)]);
      expect(h.strokes.last.shape, ShapeKind.line);
      await h.close();
    });

    testWidgets('keeps the line style, colour, size and concentration',
        (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => diagonal),
      ]);
      h.controller.setPenLine(const LineSettings(style: LineStyle.dashed));
      h.controller.setPenConcentration(0.5);
      h.controller.setPenColor(0xFF1E5BD8);
      h.controller.setPenSize(3.6);
      await h.drag(wobblyAlongDiagonal());
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      expect(s.line.style, LineStyle.dashed);
      expect(s.concentration, 0.5);
      expect(s.color, 0xFF1E5BD8);
      expect(s.size, 3.6);
      expect(s.tool, StrokeTool.pen);
      await h.close();
    });

    testWidgets('a highlighter stroke is constrained too', (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => diagonal),
      ]);
      h.controller.selectTool(EditorTool.highlighter);
      await h.drag(wobblyAlongDiagonal());
      final s = h.strokes.single;
      expect(s.tool, StrokeTool.highlighter);
      expect(s.shape, ShapeKind.line);
      expect(s.raw.length, 61);
      await h.close();
    });

    testWidgets('the line\'s times span the pen\'s time', (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => diagonal),
      ]);
      final path = wobblyAlongDiagonal();
      final g = await tester.startGesture(h.global(path.first),
          kind: PointerDeviceKind.stylus);
      for (var i = 1; i < path.length; i++) {
        await g.moveTo(h.global(path[i]),
            timeStamp: Duration(milliseconds: 20 * i));
      }
      await g.up(timeStamp: Duration(milliseconds: 20 * path.length));
      await tester.pump();
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      expect(s.raw.last.t, 20 * (path.length - 1));
      expect(s.points.first.t, 0);
      expect(s.points.last.t, s.raw.last.t);
      for (var i = 1; i < s.points.length; i++) {
        expect(s.points[i].t, greaterThanOrEqualTo(s.points[i - 1].t));
      }
      await h.close();
    });

    testWidgets('announces the finished stroke with the line', (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => diagonal),
      ]);
      final events = <FinishedStroke>[];
      final sub = h.controller.strokeEvents.finished.listen(events.add);
      addTearDown(sub.cancel);
      await h.drag(wobblyAlongDiagonal());
      await tester.pump();
      expect(events.length, 1);
      expect(events.single.stroke.shape, ShapeKind.line);
      expect(events.single.stroke.id, h.strokes.single.id);
      await h.close();
    });

    testWidgets('a second stroke starts afresh', (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => levelAt(450)),
      ]);
      await h.drag([const Offset(100, 450), const Offset(300, 460)]);
      await h.drag([const Offset(500, 450), const Offset(700, 440)]);
      expect(h.strokes.length, 2);
      expect(h.local(h.strokes[1].points.first.pos).dx, closeTo(500, 0.05));
      expect(h.local(h.strokes[1].points.last.pos).dx, closeTo(700, 0.05));
      await h.close();
    });
  });

  group('the line is cut to the page', () {
    // A 45 degree line through (900, 300).
    final slanted = FnConstraint(
        alongLine(const Offset(900, 300), const Offset(1000, 400)));

    testWidgets('a line running off the page edge stays straight',
        (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => slanted),
      ]);
      // The pen starts on the page and goes on well past its right edge
      // (984 px on this screen, 595 pt).
      await h.drag([
        const Offset(900, 300),
        const Offset(950, 300),
        const Offset(1000, 300),
        const Offset(1100, 300),
      ]);
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      final cut = h.page(const Offset(984, 384));
      expect(s.points.last.x, closeTo(595, 0.02));
      expect(s.points.last.x, closeTo(cut.x, 0.02));
      expect(s.points.last.y, closeTo(cut.y, 0.02));
      // Straight: 45 degrees all the way (a clamp on each axis would not be).
      final first = s.points.first;
      for (final p in s.points) {
        expect(p.y - first.y, closeTo(p.x - first.x, 0.03));
      }
      // The pen's own path was clamped to the page, as always.
      expect(s.raw.last.x, 595);
      await h.close();
    });

    testWidgets('a line that starts just off the page is cut at its edge',
        (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => levelAt(400)),
      ]);
      // Pen-down within the edge slop (6 px) left of the page; the page's
      // left edge is at x = 16.
      await h.drag([const Offset(12, 400), const Offset(300, 405)]);
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      expect(s.points.first.x, 0);
      expect(h.local(s.points.last.pos).dx, closeTo(300, 0.05));
      await h.close();
    });

    testWidgets('a line with nothing left on the page is the pen\'s ink',
        (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration(
            (e) => FnConstraint((p) => Offset(p.dx, p.dy - 5000))),
      ]);
      await h.drag([
        const Offset(200, 300),
        const Offset(300, 320),
        const Offset(500, 310),
      ]);
      final s = h.strokes.single;
      expect(s.shape, isNull);
      expect(s.pointsAreRaw, isTrue);
      expect(s.raw.length, 3);
      await h.close();
    });

    testWidgets('while nothing of the line is on the page the pen\'s ink shows',
        (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration(
            (e) => FnConstraint((p) => Offset(p.dx, p.dy - 5000))),
      ]);
      final g = await h.down(const Offset(200, 300));
      final layer = h.controller.liveInkFor(h.pageId).layer(StrokeTool.pen);
      var repaints = 0;
      void count() => repaints++;
      layer.addListener(count);
      await h.moveTo(g, const Offset(300, 320));
      await h.moveTo(g, const Offset(400, 330));
      layer.removeListener(count);
      final active = h.controller.inkTool.active!;
      expect(active.preview, isNull);
      expect(active.displayed.points.length, 3);
      expect(repaints, greaterThanOrEqualTo(2));
      await g.up();
      await tester.pump();
      await h.close();
    });

    testWidgets('the preview goes away when the line is gone again',
        (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => levelAt(500)),
      ]);
      final g = await h.down(const Offset(300, 500));
      await h.moveTo(g, const Offset(400, 500));
      expect(h.controller.inkTool.active!.preview, isNotNull);
      await h.moveTo(g, const Offset(300, 520));
      expect(h.controller.inkTool.active!.preview, isNull);
      await g.up();
      await tester.pump();
      expect(h.strokes.single.shape, isNull);
      await h.close();
    });
  });

  group('horizontal drawing', () {
    testWidgets('the pen draws a horizontal line from where it landed',
        (tester) async {
      final h = await CanvasHarness.open(tester);
      h.controller.setPenHorizontal(true);
      await h.drag([
        const Offset(200, 500),
        const Offset(300, 530),
        const Offset(400, 470),
        const Offset(600, 560),
      ]);
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      final y = h.page(const Offset(200, 500)).y;
      for (final p in s.points) {
        expect(p.y, closeTo(y, 0.01));
      }
      expect(s.points.first.x, closeTo(h.page(const Offset(200, 500)).x, 0.01));
      expect(s.points.last.x, closeTo(h.page(const Offset(600, 500)).x, 0.01));
      // The real path is kept.
      expect(s.raw.length, 4);
      expect(s.raw[1].y, isNot(closeTo(y, 1)));
      await h.close();
    });

    testWidgets('goes left as well as right', (tester) async {
      final h = await CanvasHarness.open(tester);
      h.controller.setPenHorizontal(true);
      await h.drag([const Offset(600, 500), const Offset(200, 540)]);
      final s = h.strokes.single;
      expect(s.points.first.x, greaterThan(s.points.last.x));
      await h.close();
    });

    testWidgets('works for the highlighter', (tester) async {
      final h = await CanvasHarness.open(tester);
      h.controller.selectTool(EditorTool.highlighter);
      h.controller.setHighlighterHorizontal(true);
      await h.drag([
        const Offset(200, 500),
        const Offset(300, 560),
        const Offset(500, 620),
      ]);
      final s = h.strokes.single;
      expect(s.tool, StrokeTool.highlighter);
      expect(s.shape, ShapeKind.line);
      final y = h.page(const Offset(200, 500)).y;
      for (final p in s.points) {
        expect(p.y, closeTo(y, 0.01));
      }
      expect(s.size, h.controller.toolPrefs.highlighter.size);
      await h.close();
    });

    testWidgets('does nothing while the switch is off', (tester) async {
      final h = await CanvasHarness.open(tester);
      await h.drag([const Offset(200, 500), const Offset(500, 620)]);
      expect(h.strokes.single.shape, isNull);
      await h.close();
    });

    testWidgets('a tap with the switch on is still a dot', (tester) async {
      final h = await CanvasHarness.open(tester);
      h.controller.setPenHorizontal(true);
      await h.drag([const Offset(200, 500)]);
      expect(h.strokes.single.shape, isNull);
      expect(h.strokes.single.raw.length, 1);
      await h.close();
    });

    for (final zoom in [0.5, 1.0, 2.5, 4.0]) {
      testWidgets('is exact at zoom $zoom', (tester) async {
        final h = await CanvasHarness.open(tester);
        h.controller.setPenHorizontal(true);
        h.controller.viewport.zoomAt(const Offset(500, 400), zoom);
        await tester.pump();
        final rect = h.controller.viewport.pageRectLocal(0);
        final y = math.max(rect.top, 0) + 200.0;
        final x0 = math.max(rect.left, 0) + 100.0;
        await h.drag([
          Offset(x0, y),
          Offset(x0 + 150, y + 40),
          Offset(x0 + 300, y - 30),
        ]);
        final s = h.strokes.single;
        expect(s.shape, ShapeKind.line);
        final py = h.page(Offset(x0, y)).y;
        for (final p in s.points) {
          expect(p.y, closeTo(py, 0.01));
        }
        expect(s.points.first.x, closeTo(h.page(Offset(x0, y)).x, 0.01));
        expect(s.points.last.x, closeTo(h.page(Offset(x0 + 300, y)).x, 0.01));
        await h.close();
      });
    }
  });

  group('ending a constrained stroke early', () {
    testWidgets('cancelling leaves nothing behind', (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => diagonal),
      ]);
      final path = wobblyAlongDiagonal();
      final g = await h.down(path.first);
      for (var i = 1; i <= 15; i++) {
        await h.moveTo(g, path[i]);
      }
      expect(h.controller.inkTool.active, isNotNull);
      expect(h.controller.inkTool.active!.preview, isNotNull);
      await g.cancel();
      await tester.pump();
      expect(h.controller.inkTool.active, isNull);
      expect(h.controller.liveInkFor(h.pageId).active, isNull);
      expect(h.strokes, isEmpty);
      expect(h.undoDepth, 0);
      await h.close();
    });

    testWidgets('a stroke after a cancelled one is not affected by it',
        (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => levelAt(450)),
      ]);
      final g = await h.down(const Offset(100, 450));
      await h.moveTo(g, const Offset(250, 460));
      await g.cancel();
      await tester.pump();
      await h.drag([const Offset(500, 450), const Offset(700, 455)]);
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      expect(h.local(s.points.first.pos).dx, closeTo(500, 0.05));
      expect(s.raw.length, 2);
      await h.close();
    });

    testWidgets('committing pending work saves the line so far',
        (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => diagonal),
      ]);
      final path = wobblyAlongDiagonal();
      final g = await h.down(path.first);
      for (var i = 1; i <= 20; i++) {
        await h.moveTo(g, path[i]);
      }
      h.controller.inkTool.commitPending();
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      expect(h.local(s.points.last.pos).dx,
          closeTo(diagonal.project(path[20]).dx, 0.05));
      expect(h.controller.liveInkFor(h.pageId).active, isNull);
      // The pen lifting afterwards adds nothing.
      await g.up();
      await tester.pump();
      expect(h.strokes.length, 1);
      await h.close();
    });

    testWidgets('the tool being deselected commits the line', (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => diagonal),
      ]);
      final path = wobblyAlongDiagonal();
      final g = await h.down(path.first);
      for (var i = 1; i <= 10; i++) {
        await h.moveTo(g, path[i]);
      }
      h.controller.inkTool.onDeactivated();
      expect(h.strokes.single.shape, ShapeKind.line);
      await g.up();
      await tester.pump();
      expect(h.strokes.length, 1);
      await h.close();
    });

    testWidgets('switching between pen and highlighter keeps the stroke',
        (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => diagonal),
      ]);
      final path = wobblyAlongDiagonal();
      final g = await h.down(path.first);
      for (var i = 1; i <= 10; i++) {
        await h.moveTo(g, path[i]);
      }
      // Both tools are the same handler: the stroke goes on as a pen stroke.
      h.controller.selectTool(EditorTool.highlighter);
      await h.moveTo(g, path[11]);
      await g.up();
      await tester.pump();
      final s = h.strokes.single;
      expect(s.tool, StrokeTool.pen);
      expect(s.shape, ShapeKind.line);
      expect(s.raw.length, 12);
      await h.close();
    });

    testWidgets('a pen that never moved and was cancelled is simply gone',
        (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration((e) => diagonal),
      ]);
      final g = await h.down(const Offset(300, 500));
      await g.cancel();
      await tester.pump();
      expect(h.strokes, isEmpty);
      expect(h.controller.inkTool.active, isNull);
      await h.close();
    });
  });

  group('constraints that misbehave never lose ink', () {
    testWidgets('positions that are not numbers keep the pen\'s ink',
        (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration(
            (e) => FnConstraint((p) => const Offset(double.nan, 5))),
      ]);
      await h.drag([const Offset(200, 300), const Offset(400, 350)]);
      final s = h.strokes.single;
      expect(s.shape, isNull);
      expect(s.raw.length, 2);
      await h.close();
    });

    testWidgets('infinite positions keep the pen\'s ink', (tester) async {
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration(
            (e) => FnConstraint((p) => Offset(double.infinity, p.dy))),
      ]);
      await h.drag([const Offset(200, 300), const Offset(400, 350)]);
      expect(h.strokes.single.shape, isNull);
      await h.close();
    });

    testWidgets('a huge but finite line is cut to the page', (tester) async {
      // x = 0 px at the pen-down, 10 million px at the pen-up: a little left
      // of the page on one side and far beyond it on the other.
      final h = await CanvasHarness.open(tester, integrations: [
        strokeConstraintIntegration(
            (e) => FnConstraint((p) => Offset(p.dx * 1e6 - 3e8, 400))),
      ]);
      await h.drag([const Offset(300, 400), const Offset(310, 400)]);
      final s = h.strokes.single;
      expect(s.shape, ShapeKind.line);
      expect(s.points.first.x, 0);
      expect(s.points.last.x, closeTo(595, 0.02));
      for (final p in s.points) {
        expect(p.x, inInclusiveRange(0, 595));
        expect(p.y, closeTo(h.page(const Offset(0, 400)).y, 0.01));
      }
      await h.close();
    });
  });
}
