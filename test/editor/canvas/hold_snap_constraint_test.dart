import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/integrations/shapes/hold_snap_hook.dart';
import 'package:neatink/features/editor/integrations/shapes/shapes_integration.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';

import 'canvas_harness.dart';

void main() {
  // The hand-drawn line the shapes tests snap: wobbling about y = 200 pt.
  List<Offset> wobblyLine(CanvasHarness h) => [
        for (var i = 0; i <= 30; i++)
          h.local(Vec2(100 + i * 8.0, 200 + (i.isEven ? 1.5 : -1.5))),
      ];

  /// Draws [path], holds the pen still for 1.2 s and returns the gesture
  /// (still down).
  Future<TestGesture> drawAndHold(CanvasHarness h, List<Offset> path) async {
    final g = await h.down(path.first);
    for (final p in path.skip(1)) {
      await h.moveTo(g, p);
    }
    await h.tester.pump(const Duration(milliseconds: 1200));
    return g;
  }

  HoldSnapHook hookOf(CanvasHarness h) =>
      h.controller.extensions.liveStrokeHook! as HoldSnapHook;

  testWidgets('without a constraint the held line snaps (the control case)',
      (tester) async {
    final h = await CanvasHarness.open(tester, integrations: [shapesIntegration]);
    final g = await drawAndHold(h, wobblyLine(h));
    expect(hookOf(h).hasSnapped, isTrue);
    await g.up();
    await tester.pump();
    expect(h.strokes.single.shape, ShapeKind.line);
    await h.close();
  });

  testWidgets('a constrained stroke is not snapped by holding the pen',
      (tester) async {
    // Everything is pulled onto a diagonal, far from the hand-drawn line.
    final diagonal = FnConstraint((p) => Offset(p.dx, 100 + (p.dx - 100) * 0.5));
    final h = await CanvasHarness.open(tester, integrations: [
      shapesIntegration,
      strokeConstraintIntegration((e) => diagonal),
    ]);
    final path = wobblyLine(h);
    final g = await drawAndHold(h, path);
    expect(hookOf(h).hasSnapped, isFalse);
    // The preview is the constraint's line, not a snapped shape.
    final preview = h.controller.inkTool.active!.preview!;
    expect(preview.shape, ShapeKind.line);
    await g.up();
    await tester.pump();
    final s = h.strokes.single;
    expect(s.shape, ShapeKind.line);
    // Slanted like the constraint, not level like the hand-drawn line.
    final dy = s.points.last.y - s.points.first.y;
    final dx = s.points.last.x - s.points.first.x;
    expect(dy / dx, closeTo(0.5, 0.01));
    // And the real path is what raw keeps.
    expect(s.raw.length, path.length);
    await h.close();
  });

  testWidgets('holding with horizontal drawing on keeps the horizontal line',
      (tester) async {
    final h = await CanvasHarness.open(tester, integrations: [shapesIntegration]);
    h.controller.setPenHorizontal(true);
    // A diagonal the snap would also make a line of (a slanted one).
    final path = [
      for (var i = 0; i <= 30; i++) h.local(Vec2(100 + i * 8.0, 200 + i * 4.0)),
    ];
    final g = await drawAndHold(h, path);
    expect(hookOf(h).hasSnapped, isFalse);
    await g.up();
    await tester.pump();
    final s = h.strokes.single;
    expect(s.shape, ShapeKind.line);
    final ys = s.points.map((p) => p.y);
    expect(ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b),
        lessThan(0.01));
    await h.close();
  });

  testWidgets('an unconstrained stroke after a constrained one snaps again',
      (tester) async {
    var constrain = true;
    final h = await CanvasHarness.open(tester, integrations: [
      shapesIntegration,
      strokeConstraintIntegration(
          (e) => constrain ? FnConstraint((p) => Offset(p.dx, 600)) : null),
    ]);
    var g = await drawAndHold(h, wobblyLine(h));
    expect(hookOf(h).hasSnapped, isFalse);
    await g.up();
    await tester.pump();

    constrain = false;
    g = await drawAndHold(h, wobblyLine(h));
    expect(hookOf(h).hasSnapped, isTrue);
    await g.up();
    await tester.pump();
    expect(h.strokes.length, 2);
    expect(h.strokes.last.shape, ShapeKind.line);
    await h.close();
  });
}
