import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/integrations/text_images/text_editor.dart';
import 'package:neatink/features/editor/integrations/text_images/text_images_integration.dart';
import 'package:neatink/features/editor/integrations/text_images/text_tool.dart';
import 'package:neatink/features/editor/integrations/text_images/text_write_bar.dart';
import 'package:neatink/ink/stroke.dart';

import '../erase_select/harness.dart';

// v1.13.0: Mariam could not add words in the middle of typed text; she had
// to delete the rest of the sentence and write it again.

Finder key(String k) => find.byKey(ValueKey(k));

TextEditingValue at(String text, int caret) =>
    TextEditingValue(text: text, selection: TextSelection.collapsed(offset: caret));

const box = TextItem(id: 't', x: 100, y: 100, width: 560, height: 20, text: 'The brain has neurons', fontSize: 20);

void main() {
  group('insertWritten', () {
    test('a word in the middle gets a space on each side', () {
      final r = insertWritten(at('The brain has neurons', 13), 'many');
      expect(r.value.text, 'The brain has many neurons');
      expect(r.value.selection, const TextSelection.collapsed(offset: 18), reason: 'after "many"');
    });

    test('after a space, before a space: no extra spaces', () {
      expect(insertWritten(at('The brain has neurons', 14), 'many').value.text, 'The brain has many neurons');
      expect(insertWritten(at('The brain has  neurons', 14), 'many').value.text, 'The brain has many neurons');
    });

    test('written over a selected word, it replaces it', () {
      const v = TextEditingValue(
        text: 'many nuerons here',
        selection: TextSelection(baseOffset: 5, extentOffset: 12),
      );
      expect(insertWritten(v, 'neurons').value.text, 'many neurons here');
    });

    test('punctuation sticks to the word before it', () {
      expect(insertWritten(at('neurons fire', 7), ',').value.text, 'neurons, fire');
      expect(insertWritten(at('neurons fire', 8), ',').value.text, 'neurons, fire', reason: 'the space before goes');
      expect(insertWritten(at('It ends', 7), '.').value.text, 'It ends.');
    });

    test('at the start, at the end, and with no cursor yet', () {
      expect(insertWritten(at('brain', 0), 'The').value.text, 'The brain');
      expect(insertWritten(at('The', 3), 'brain').value.text, 'The brain');
      expect(insertWritten(const TextEditingValue(text: 'The'), 'brain').value.text, 'The brain');
      expect(insertWritten(at('', 0), 'Hello').value.text, 'Hello');
      expect(insertWritten(at('(', 1), 'see').value.text, '(see');
    });

    test('nothing read changes nothing', () {
      final v = at('abc', 1);
      expect(insertWritten(v, '  ').value, v);
    });
  });

  testWidgets('select typed text, write a word with the pen, it goes in at the cursor', (tester) async {
    final reads = <String?>[];
    final answers = ['many', 'big', ''];
    final h = await EraseSelectHarness.open(tester, texts: const [box], extra: [
      textImagesIntegration,
      (controller, ref) => controller.extensions.readHandwriting = (List<Stroke> strokes, {String? before}) async {
            expect(strokes, isNotEmpty);
            reads.add(before);
            return answers.removeAt(0);
          },
    ]);
    final editor = (h.controller.extensions.toolHandlers[EditorTool.text]! as TextToolHandler).editor;
    TextField field() => tester.widget<TextField>(find.byType(TextField));

    await h.lassoRect(90, 92, 400, 130);
    await tester.tap(key('selection-edit'));
    await tester.pump();
    expect(h.controller.tool, EditorTool.text);
    expect(key('write-bar'), findsOneWidget);
    expect(key('write-pad'), findsOneWidget);
    expect(field().readOnly, isTrue, reason: 'no keyboard: the pen writes');
    expect(editor.session!.keyboard, isFalse);

    // The cursor after "has" (a tap in the text puts it there).
    editor.session!.input.selection = const TextSelection.collapsed(offset: 13);
    Future<void> writeOnPad({PointerDeviceKind kind = PointerDeviceKind.stylus}) async {
      final r = tester.getRect(key('write-pad'));
      final g = await tester.startGesture(r.centerLeft + const Offset(40, 0), kind: kind);
      for (var x = 50.0; x < 160; x += 10) {
        await g.moveTo(r.centerLeft + Offset(x, x % 20 == 0 ? 8 : -8));
        await tester.pump(const Duration(milliseconds: 10));
      }
      await g.up();
      await tester.pump();
    }

    await writeOnPad();
    expect(reads, isEmpty, reason: 'it waits for a pause');
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    expect(reads, ['The brain has']);
    expect(editor.session!.input.text, 'The brain has many neurons');
    expect(find.text('Added “many”'), findsOneWidget);

    // Take back, then a fresh word goes where the cursor is again.
    await tester.tap(key('write-undo'));
    await tester.pump();
    expect(editor.session!.input.text, 'The brain has neurons');
    editor.session!.input.selection = const TextSelection.collapsed(offset: 13);
    await writeOnPad();
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    expect(editor.session!.input.text, 'The brain has big neurons');

    // Nothing readable: says so, the text stays.
    await writeOnPad();
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    expect(key('write-problem'), findsOneWidget);
    expect(editor.session!.input.text, 'The brain has big neurons');

    // A finger (a resting hand) does not write in the strip.
    await writeOnPad(kind: PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(reads, hasLength(3));

    // Cursor keys, Space and Delete.
    editor.session!.input.selection = const TextSelection.collapsed(offset: 17);
    await tester.tap(key('write-backspace'));
    await tester.pump();
    expect(editor.session!.input.text, 'The brain has bi neurons');
    await tester.tap(key('write-left'));
    await tester.tap(key('write-space'));
    await tester.pump();
    expect(editor.session!.input.text, 'The brain has b i neurons');
    await tester.tap(key('write-right'));
    await tester.tap(key('write-backspace'));
    await tester.tap(key('write-backspace'));
    await tester.pump();
    expect(editor.session!.input.text, 'The brain has b neurons');

    // The keyboard, and back to the pen.
    await tester.tap(key('write-keyboard'));
    await tester.pump();
    expect(field().readOnly, isFalse);
    expect(key('write-pad'), findsNothing);
    await tester.tap(key('write-pen'));
    await tester.pump();
    expect(field().readOnly, isTrue);

    // Done: one undo step, back to the lasso.
    await tester.tap(key('write-done'));
    await tester.pump();
    expect(h.page.texts.single.text, 'The brain has b neurons');
    expect(h.controller.undoLabel, 'Edit text');
    expect(h.controller.tool, EditorTool.lasso);
    expect(key('write-bar'), findsNothing);
    await h.close();
  });

  testWidgets('Edit with the keyboard opens the keyboard; a new text box shows the bar too', (tester) async {
    final h = await EraseSelectHarness.open(tester, texts: const [box], extra: [textImagesIntegration]);
    await h.lassoRect(90, 92, 400, 130);
    await tester.tap(key('selection-edit-keyboard'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);
    expect(key('write-bar'), findsOneWidget);
    expect(key('write-pen'), findsNothing, reason: 'no handwriting reader in this editor');
    await tester.tap(key('write-done'));
    await tester.pump();
    expect(h.controller.tool, EditorTool.lasso);
    expect(TextBoxEditor.sameText(h.page.texts.single, box.copyWith(height: h.page.texts.single.height)), isTrue);
    await h.close();
  });
}
