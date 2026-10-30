import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/ink/vec2.dart';

import 'harness.dart';

// The test font draws every glyph as a square as wide as the font size:
// "hello world foo" at 20 pt from x = 100 has "world" at 220..320. The box
// is as wide as a converted line (560 pt), so its centre (380, 112) and
// corners are outside a lasso around "world".
const box = TextItem(id: 't', x: 100, y: 100, width: 560, height: 20, text: 'hello world foo', fontSize: 20);

Finder key(String k) => find.byKey(ValueKey(k));

void main() {
  testWidgets('a lasso around a word of a converted line selects its box', (tester) async {
    final h = await EraseSelectHarness.open(tester, texts: const [box]);
    await h.lassoRect(210, 92, 330, 130);
    expect(h.lasso.state.selection?.textIds, {'t'});
  });

  testWidgets('Text style: size, bold, underline and font, each one undo step', (tester) async {
    final h = await EraseSelectHarness.open(tester, texts: const [box]);
    await h.lassoRect(210, 92, 330, 130);
    await tester.tap(key('selection-text-style'));
    await tester.pump();
    expect(key('selection-size'), findsOneWidget);
    expect(tester.widget<Text>(key('selection-size')).data, '20');

    await tester.tap(key('selection-size-up'));
    await tester.pump();
    expect(h.page.texts.single.fontSize, 24);
    expect(h.page.texts.single.height, 24, reason: 'measured again (the test font is as tall as its size)');
    expect(h.page.texts.single.width, 560, reason: 'same place and width');
    expect(h.controller.undoLabel, 'Text style');

    await tester.tap(key('selection-bold'));
    await tester.pump();
    await tester.tap(key('selection-underline'));
    await tester.pump();
    expect(h.page.texts.single.bold, isTrue);
    expect(h.page.texts.single.underline, isTrue);

    await tester.tap(key('selection-font'));
    await tester.pumpAndSettle();
    final serif = FontKind.values.firstWhere((f) => f != box.font);
    await tester.tap(find.byKey(ValueKey('text-font-${serif.name}')).last);
    await tester.pumpAndSettle();
    expect(h.page.texts.single.font, serif);

    for (var i = 0; i < 4; i++) {
      h.controller.undo();
    }
    await tester.pump();
    expect(h.page.texts.single.fontSize, 20);
    expect(h.page.texts.single.bold, isFalse);
    expect(h.page.texts.single.font, box.font);
    expect(h.lasso.state.selection, isNotNull);
  });

  testWidgets('Edit text opens the selected box, with the pen or the keyboard', (tester) async {
    final h = await EraseSelectHarness.open(tester, texts: const [box]);
    TextItem? edited;
    bool? withKeyboard;
    h.controller.extensions.editText = (pageId, item, {bool keyboard = false}) {
      edited = item;
      withKeyboard = keyboard;
    };
    await h.lassoRect(210, 92, 330, 130);
    await tester.tap(key('selection-edit'));
    await tester.pump();
    expect(edited?.id, 't');
    expect(withKeyboard, isFalse);
    await h.lassoRect(210, 92, 330, 130);
    await tester.tap(key('selection-edit-keyboard'));
    await tester.pump();
    expect(withKeyboard, isTrue);
  });

  testWidgets('no Text style for a selection of handwriting only', (tester) async {
    final h = await EraseSelectHarness.open(tester, texts: const [box]);
    await h.lassoRect(600, 600, 700, 700);
    expect(key('selection-text-style'), findsNothing);
    expect(key('selection-edit'), findsNothing);
    expect(Vec2.zero, isNotNull);
  });
}
