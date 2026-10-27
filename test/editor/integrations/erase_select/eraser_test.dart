import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/integrations/erase_select/eraser_cursor.dart';
import 'package:neatink/ink/vec2.dart';

import '../../../editor_tools/tool_test_utils.dart';
import 'harness.dart';

void main() {
  /// Three horizontal lines at y = 100, 200 and 300.
  final lines = [
    for (final (i, y) in [100.0, 200.0, 300.0].indexed)
      strokeOf('s$i', linePoints(100, y, 300, y, spacing: 5)),
  ];

  group('whole-stroke eraser', () {
    testWidgets('erases every stroke touched, as one undo step',
        (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: lines);
      h.controller.selectTool(EditorTool.eraser);
      await tester.pump();

      final g = await h.beginDrag(const Vec2(200, 50));
      await g.moveTo(h.at(const Vec2(200, 150)));
      await tester.pump();
      // The erasing is shown while the pen is still down, but is not yet an
      // undo step.
      expect(h.strokes.map((s) => s.id), ['s1', 's2']);
      expect(h.undoDepth, 0);

      await g.moveTo(h.at(const Vec2(200, 250)));
      await tester.pump();
      await g.up();
      await tester.pump();

      expect(h.strokes.map((s) => s.id), ['s2']);
      expect(h.undoDepth, 1);

      h.controller.undo();
      expect(h.strokes.map((s) => s.id), ['s0', 's1', 's2']);
      h.controller.redo();
      expect(h.strokes.map((s) => s.id), ['s2']);
      await h.close();
    });

    testWidgets('a cancelled gesture leaves the page untouched',
        (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: lines);
      h.controller.selectTool(EditorTool.eraser);
      await tester.pump();

      final g = await h.beginDrag(const Vec2(200, 50));
      await g.moveTo(h.at(const Vec2(200, 250)));
      await tester.pump();
      expect(h.strokes.length, 1);
      await g.cancel();
      await tester.pump();

      expect(h.strokes.map((s) => s.id), ['s0', 's1', 's2']);
      expect(h.undoDepth, 0);
      await h.close();
    });

    testWidgets('the pen eraser end erases while the pen tool is selected',
        (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: lines);
      expect(h.controller.tool, EditorTool.pen);

      await h.drag(const [Vec2(200, 150), Vec2(200, 250)],
          kind: PointerDeviceKind.invertedStylus);

      expect(h.strokes.map((s) => s.id), ['s0', 's2']);
      expect(h.undoDepth, 1);
      expect(h.controller.tool, EditorTool.pen);
      await h.close();
    });

    testWidgets('a stylus barrel-button press erases too', (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: lines);
      final g = await tester.startGesture(h.at(const Vec2(200, 100)),
          kind: PointerDeviceKind.stylus, buttons: kPrimaryStylusButton);
      await g.moveTo(h.at(const Vec2(200, 120)));
      await g.up();
      await tester.pump();
      expect(h.strokes.map((s) => s.id), ['s1', 's2']);
      await h.close();
    });

    testWidgets('a fast flick still erases what it crossed', (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: lines);
      h.controller.selectTool(EditorTool.eraser);
      await tester.pump();
      // One huge jump across all three lines.
      await h.drag(const [Vec2(200, 20), Vec2(200, 400)]);
      expect(h.strokes, isEmpty);
      expect(h.undoDepth, 1);
      await h.close();
    });
  });

  group('partial eraser', () {
    final line = strokeOf('p', linePoints(50, 100, 350, 100, spacing: 5));

    testWidgets('cuts a stroke in two and undo restores it', (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: [line]);
      h.controller
        ..setEraserMode(EraserMode.pixel)
        ..setEraserSize(14)
        ..selectTool(EditorTool.eraser);
      await tester.pump();

      await h.drag(const [Vec2(200, 85), Vec2(200, 115)]);

      expect(h.strokes.length, 2);
      final left = h.strokes[0], right = h.strokes[1];
      expect(left.bounds.right, lessThan(200));
      expect(right.bounds.left, greaterThan(200));
      // The hand-drawn points are cut in step with the displayed ones.
      for (final s in h.strokes) {
        expect(s.pointsAreRaw, isTrue);
        expect(s.size, line.size);
        expect(s.color, line.color);
      }
      expect(h.undoDepth, 1);

      h.controller.undo();
      expect(h.strokes.length, 1);
      expect(h.strokes.single.id, 'p');
      expect(h.strokes.single.raw.length, line.raw.length);
      expect(h.strokes.single.raw.first.x, line.raw.first.x);
      await h.close();
    });

    testWidgets('one drag over several strokes is one undo step',
        (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: lines);
      h.controller
        ..setEraserMode(EraserMode.pixel)
        ..setEraserSize(14)
        ..selectTool(EditorTool.eraser);
      await tester.pump();

      await h.drag(const [Vec2(150, 50), Vec2(150, 150), Vec2(150, 250)]);

      // s0 and s1 are cut in two, s2 is untouched.
      expect(h.strokes.length, 5);
      expect(h.undoDepth, 1);
      h.controller.undo();
      expect(h.strokes.map((s) => s.id), ['s0', 's1', 's2']);
      await h.close();
    });

    testWidgets('the eraser size sets how much is cut', (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: [line]);
      h.controller
        ..setEraserMode(EraserMode.pixel)
        ..setEraserSize(30)
        ..selectTool(EditorTool.eraser);
      await tester.pump();
      await h.drag(const [Vec2(200, 85), Vec2(200, 115)]);
      final gap = h.strokes[1].bounds.left - h.strokes[0].bounds.right;
      expect(gap, greaterThan(28));
      await h.close();
    });
  });

  group('eraser cursor', () {
    testWidgets('shows under a hovering pen and fades away', (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: lines);
      h.controller.selectTool(EditorTool.eraser);
      await tester.pump();
      final cursor = find.descendant(
          of: find.byType(EraserCursorOverlay),
          matching: find.byType(CustomPaint));
      expect(cursor, findsNothing);

      final hover = await tester.createGesture(kind: PointerDeviceKind.stylus);
      await hover.addPointer(location: h.at(const Vec2(100, 400)));
      await hover.moveTo(h.at(const Vec2(120, 400)));
      await tester.pump();
      expect(cursor, findsOneWidget);

      await hover.removePointer();
      await tester.pump(const Duration(seconds: 2));
      expect(cursor, findsNothing);
      await h.close();
    });
  });
}
