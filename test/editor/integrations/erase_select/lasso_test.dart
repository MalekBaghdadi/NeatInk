import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/integrations/erase_select/selection_geometry.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';

import '../../../editor_tools/tool_test_utils.dart';
import 'harness.dart';

void main() {
  /// A at y = 100 (x 100..200), B far below at y = 300.
  Stroke a() => strokeOf('a', linePoints(100, 100, 200, 100, spacing: 5));
  Stroke b() => strokeOf('b', linePoints(100, 300, 200, 300, spacing: 5));

  group('selecting', () {
    testWidgets('a lasso selects the strokes inside it', (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: [a(), b()]);
      await h.lassoRect(80, 70, 220, 130);
      expect(h.lasso.state.selection!.strokeIds, {'a'});
      expect(h.undoDepth, 0);
      await h.close();
    });

    testWidgets('a lasso selects text boxes and images by their bounds',
        (tester) async {
      final h = await EraseSelectHarness.open(tester, texts: [
        TextItem(id: 't', x: 100, y: 400, width: 100, height: 30, text: 'hi'),
      ], images: [
        ImageItem(
            id: 'i', x: 300, y: 400, width: 100, height: 80, asset: 'x.png'),
      ]);
      await h.lassoRect(80, 380, 430, 500);
      final sel = h.lasso.state.selection!;
      expect(sel.textIds, {'t'});
      expect(sel.imageIds, {'i'});
      await h.close();
    });

    testWidgets('a tap selects the stroke under the pen, a tap elsewhere '
        'clears', (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: [a(), b()]);
      h.controller.selectTool(EditorTool.lasso);
      await tester.pump();
      await h.drag([const Vec2(150, 100)]);
      expect(h.lasso.state.selection!.strokeIds, {'a'});
      await h.drag([const Vec2(400, 500)]);
      expect(h.lasso.state.selection, isNull);
      await h.close();
    });

    testWidgets('changing tool clears the selection', (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: [a()]);
      await h.lassoRect(80, 70, 220, 130);
      expect(h.lasso.state.selection, isNotNull);
      h.controller.selectTool(EditorTool.pen);
      expect(h.lasso.state.selection, isNull);
      await tester.pump();
      expect(find.byKey(const ValueKey('selection-delete')), findsNothing);
      await h.close();
    });
  });

  group('move and resize', () {
    testWidgets('moving updates raw and points together, in one undo step',
        (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: [a(), b()]);
      final before = h.strokes.first;
      await h.lassoRect(80, 70, 220, 130);

      await h.drag(const [Vec2(150, 100), Vec2(170, 120), Vec2(200, 150)]);

      final moved = h.strokes.first;
      expect(moved.id, 'a');
      expect(moved.raw.length, before.raw.length);
      for (var i = 0; i < before.raw.length; i++) {
        expect(moved.raw[i].x, closeTo(before.raw[i].x + 50, 1e-6));
        expect(moved.raw[i].y, closeTo(before.raw[i].y + 50, 1e-6));
        expect(moved.points[i].x, closeTo(moved.raw[i].x, 1e-9));
        expect(moved.points[i].y, closeTo(moved.raw[i].y, 1e-9));
      }
      expect(h.strokes.last.raw.first.x, 100, reason: 'b is untouched');
      expect(h.undoDepth, 1);
      expect(h.controller.undoLabel, 'Move selection');
      // The selection frame follows the moved ink.
      expect(h.lasso.state.selection!.bounds.left, closeTo(148.5, 1e-6));

      h.controller.undo();
      expect(h.strokes.first.raw.first.x, 100);
      expect(h.strokes.first.raw.first.y, 100);
      // Still selected after undo, with bounds back at the original spot.
      expect(h.lasso.state.selection!.strokeIds, {'a'});
      expect(h.lasso.state.selection!.bounds.left, closeTo(98.5, 1e-6));
      await h.close();
    });

    testWidgets('a tap inside the selection does not move it',
        (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: [a()]);
      await h.lassoRect(80, 70, 220, 130);
      await h.drag([const Vec2(150, 100), const Vec2(150.5, 100)]);
      expect(h.undoDepth, 0);
      expect(h.lasso.state.selection, isNotNull);
      await h.close();
    });

    testWidgets('dragging a corner handle resizes raw and points together',
        (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: [a()]);
      final before = h.strokes.single;
      await h.lassoRect(80, 70, 220, 130);
      final sel = h.lasso.state.selection!;
      final frame = selectionFrame(sel.bounds, h.controller.viewport.scale);

      await h.drag([
        frame.bottomRight,
        Vec2(frame.right + 20, frame.bottom + 1),
        Vec2(frame.right + 60, frame.bottom + 1),
      ]);

      final resized = h.strokes.single;
      expect(resized.id, 'a');
      expect(h.undoDepth, 1);
      expect(h.controller.undoLabel, 'Resize selection');
      final grow = resized.bounds.width / before.bounds.width;
      expect(grow, greaterThan(1.3));
      expect(resized.size, closeTo(before.size * grow, 0.05));
      // Anchored at the opposite (top-left) corner of the selection.
      for (var i = 0; i < resized.raw.length; i++) {
        expect(resized.points[i].x, closeTo(resized.raw[i].x, 1e-9));
        expect(resized.raw[i].x,
            closeTo(sel.bounds.left + (before.raw[i].x - sel.bounds.left) * grow, 0.01));
      }

      h.controller.undo();
      expect(h.strokes.single.raw.last.x, 200);
      await h.close();
    });

    testWidgets('moving and resizing carry text boxes and images',
        (tester) async {
      final h = await EraseSelectHarness.open(tester, texts: [
        TextItem(
            id: 't', x: 100, y: 400, width: 100, height: 30, fontSize: 12),
      ], images: [
        ImageItem(
            id: 'i', x: 300, y: 400, width: 100, height: 80, asset: 'x.png'),
      ]);
      await h.lassoRect(80, 380, 430, 500);

      await h.drag(const [Vec2(200, 440), Vec2(230, 470), Vec2(240, 480)]);
      expect(h.page.texts.single.x, closeTo(140, 1e-6));
      expect(h.page.texts.single.y, closeTo(440, 1e-6));
      expect(h.page.images.single.x, closeTo(340, 1e-6));
      expect(h.undoDepth, 1);

      h.controller.undo();
      expect(h.page.texts.single.x, 100);
      expect(h.page.images.single.y, 400);
      await h.close();
    });
  });

  group('menu actions', () {
    testWidgets('delete from the menu, then undo', (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: [a(), b()]);
      await h.lassoRect(80, 70, 220, 130);
      final delete = find.byKey(const ValueKey('selection-delete'));
      expect(delete, findsOneWidget);

      // A pen tap on a menu button must press it, not start a new lasso.
      await tester.tap(delete, kind: PointerDeviceKind.stylus);
      await tester.pump();

      expect(h.strokes.map((s) => s.id), ['b']);
      expect(h.lasso.state.selection, isNull);
      expect(h.undoDepth, 1);

      h.controller.undo();
      expect(h.strokes.map((s) => s.id), ['a', 'b']);
      await h.close();
    });

    testWidgets('colour: a preset from the menu recolours, one undo step',
        (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: [a(), b()]);
      await h.lassoRect(80, 70, 220, 130);

      await tester.tap(find.byKey(const ValueKey('selection-colour')),
          kind: PointerDeviceKind.stylus);
      await tester.pump();
      await tester.tap(find.byTooltip('Red'), kind: PointerDeviceKind.stylus);
      await tester.pump();

      expect(h.strokes.first.color, 0xFFD93025);
      expect(h.strokes.last.color, 0xFF1E1E1E);
      expect(h.undoDepth, 1);
      expect(h.strokes.first.raw.first.x, 100, reason: 'ink geometry kept');

      h.controller.undo();
      expect(h.strokes.first.color, 0xFF1E1E1E);
      await h.close();
    });

    testWidgets('recolouring a text box and leaving highlighters alone',
        (tester) async {
      final hl = strokeOf('h', linePoints(100, 200, 200, 200),
          tool: StrokeTool.highlighter, color: 0xFFFFE600, size: 14);
      final h = await EraseSelectHarness.open(tester, strokes: [a(), hl],
          texts: [
            TextItem(id: 't', x: 100, y: 120, width: 100, height: 20),
          ]);
      await h.lassoRect(80, 60, 220, 240);
      expect(h.lasso.state.selection!.length, 3);

      h.lasso.recolorSelected(0xFF188038);
      expect(h.strokes.firstWhere((s) => s.id == 'a').color, 0xFF188038);
      expect(h.strokes.firstWhere((s) => s.id == 'h').color, 0xFFFFE600);
      expect(h.page.texts.single.color, 0xFF188038);
      expect(h.undoDepth, 1);
      await h.close();
    });

    testWidgets('restore original: edited and shape strokes go back to raw',
        (tester) async {
      final raw = linePoints(100, 100, 200, 104, spacing: 5);
      final tidied = strokeOf('t', raw).copyWith(
        points: strokeOf('x', linePoints(100, 100, 200, 100, spacing: 5)).raw,
      );
      final snapped = strokeOf('s', linePoints(100, 150, 200, 153, spacing: 5))
          .copyWith(
        points: strokeOf('y', linePoints(100, 150, 200, 150, spacing: 5)).raw,
        shape: ShapeKind.line,
      );
      final plain = strokeOf('plain', linePoints(100, 200, 200, 200, spacing: 5));
      final h = await EraseSelectHarness.open(tester,
          strokes: [tidied, snapped, plain]);
      await h.lassoRect(80, 70, 220, 230);
      expect(h.lasso.state.selection!.strokeIds, {'t', 's', 'plain'});
      expect(h.lasso.canRestoreOriginal, isTrue);

      h.lasso.restoreOriginal();

      for (final id in ['t', 's']) {
        final s = h.strokes.firstWhere((s) => s.id == id);
        expect(s.pointsAreRaw, isTrue, reason: id);
        expect(s.shape, isNull, reason: id);
      }
      expect(h.strokes.firstWhere((s) => s.id == 't').points.last.y,
          closeTo(104, 1e-9));
      // The plain stroke is not touched.
      expect(h.strokes.firstWhere((s) => s.id == 'plain').pointsAreRaw, isTrue);
      expect(h.undoDepth, 1);
      expect(h.lasso.canRestoreOriginal, isFalse);

      h.controller.undo();
      final back = h.strokes.firstWhere((s) => s.id == 't');
      expect(back.pointsAreRaw, isFalse);
      expect(h.strokes.firstWhere((s) => s.id == 's').shape, ShapeKind.line);
      await h.close();
    });

    testWidgets('restore original is disabled when nothing is tidied',
        (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: [a()]);
      await h.lassoRect(80, 70, 220, 130);
      expect(h.lasso.canRestoreOriginal, isFalse);
      final button = tester.widget<IconButton>(find.descendant(
          of: find.byKey(const ValueKey('selection-restore')),
          matching: find.byType(IconButton)));
      expect(button.onPressed, isNull);
      await h.close();
    });

    testWidgets('duplicate adds copies and selects them; undo drops them '
        'from the selection', (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: [a()]);
      await h.lassoRect(80, 70, 220, 130);

      h.lasso.duplicateSelected();
      expect(h.strokes.length, 2);
      final copy = h.strokes.last;
      expect(copy.id, isNot('a'));
      expect(copy.raw.first.x, closeTo(116, 1e-6));
      expect(h.lasso.state.selection!.strokeIds, {copy.id});
      expect(h.undoDepth, 1);

      h.controller.undo();
      expect(h.strokes.length, 1);
      expect(h.lasso.state.selection, isNull);
      await h.close();
    });

    testWidgets('erasing a selected stroke drops it from the selection',
        (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: [a(), b()]);
      await h.lassoRect(80, 70, 220, 330);
      expect(h.lasso.state.selection!.length, 2);
      // The pen's eraser end removes one of the selected strokes.
      await h.drag(const [Vec2(150, 280), Vec2(150, 320)],
          kind: PointerDeviceKind.invertedStylus);
      expect(h.lasso.state.selection!.strokeIds, {'a'});
      await h.close();
    });
  });
}
