import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/tools/text_eraser.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/ink_rect.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';

import 'harness.dart';

// Test font: squares as wide as the size. "hello world foo" at 20 pt from
// x = 100, line 100..120: hello 100..200, world 220..320, foo 340..400.
const box = TextItem(id: 't', x: 100, y: 100, width: 560, height: 20, text: 'hello world foo', fontSize: 20);

void main() {
  test('sweepTouchesRect', () {
    const r = InkRect(100, 100, 200, 120);
    expect(sweepTouchesRect(const Vec2(150, 50), const Vec2(150, 150), 2, r), isTrue, reason: 'crosses it');
    expect(sweepTouchesRect(const Vec2(150, 110), const Vec2(150, 110), 2, r), isTrue, reason: 'a tap inside');
    expect(sweepTouchesRect(const Vec2(90, 50), const Vec2(90, 150), 5, r), isFalse, reason: 'passes beside it');
    expect(sweepTouchesRect(const Vec2(90, 50), const Vec2(90, 150), 12, r), isTrue, reason: 'a wide eraser reaches it');
    expect(sweepTouchesRect(const Vec2(0, 300), const Vec2(300, 250), 1, r), isFalse, reason: 'a diagonal below it');
    expect(sweepTouchesRect(const Vec2(0, 0), const Vec2(300, 300), 1, r), isTrue, reason: 'a diagonal through it');
  });

  testWidgets('the eraser removes the typed words it touches; undo puts them back', (tester) async {
    final h = await EraseSelectHarness.open(tester, texts: const [box]);
    h.controller.selectTool(EditorTool.eraser);
    await tester.pump();
    await h.drag([const Vec2(270, 90), const Vec2(270, 130)]);
    expect(h.page.texts.single.text, 'hello foo');
    expect(h.controller.undoLabel, 'Erase');
    h.controller.undo();
    await tester.pump();
    expect(h.page.texts.single.text, 'hello world foo');
  });

  testWidgets('erasing every word removes the box, with ink in the same step', (tester) async {
    final ink = Stroke(id: 's', tool: StrokeTool.pen, color: 0xFF000000, size: 2, raw: const [
      InkPoint(150, 200, 0.5, 0),
      InkPoint(160, 200, 0.5, 8),
    ]);
    final h = await EraseSelectHarness.open(tester, texts: const [box], strokes: [ink]);
    h.controller.selectTool(EditorTool.eraser);
    await tester.pump();
    await h.drag([const Vec2(95, 110), const Vec2(405, 110), const Vec2(155, 200)]);
    expect(h.page.texts, isEmpty);
    expect(h.page.strokes, isEmpty);
    h.controller.undo();
    await tester.pump();
    expect(h.page.texts.single.text, 'hello world foo');
    expect(h.page.strokes, hasLength(1));
  });

  testWidgets('the partial eraser removes typed words too', (tester) async {
    final h = await EraseSelectHarness.open(tester, texts: const [box]);
    h.controller
      ..setEraserMode(EraserMode.pixel)
      ..selectTool(EditorTool.eraser);
    await tester.pump();
    await h.drag([const Vec2(150, 90), const Vec2(150, 130)]);
    expect(h.page.texts.single.text, 'world foo');
  });
}
