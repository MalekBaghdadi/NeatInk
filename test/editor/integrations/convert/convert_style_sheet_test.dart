import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/settings/convert_style_prefs.dart';
import 'package:neatink/features/settings/settings_controller.dart';

import 'harness.dart';

Finder key(String k) => find.byKey(ValueKey(k));

void main() {
  testWidgets('the typed-text settings open from the editor with nothing to convert', (tester) async {
    final h = await ConvertHarness.open(tester, recognizer: FakeRecognizer(const {}));
    expect(h.page.strokes, isEmpty);
    await tester.tap(key('convert-settings'));
    await tester.pumpAndSettle();
    expect(find.text('Typed text'), findsOneWidget);
    expect(key('style-preview'), findsOneWidget);
    // The even size is chosen, and says what it is on this page.
    expect(tester.widget<ChoiceChip>(key('convert-size-even')).selected, isTrue);
    expect(find.text('Even size (16 pt)'), findsOneWidget);

    await tester.tap(key('convert-size-auto'));
    await tester.pump();
    await tester.ensureVisible(key('convert-join-lines'));
    await tester.tap(key('convert-join-lines'));
    await tester.pump();
    await tester.tap(key('convert-bold'));
    await tester.tap(key('convert-italic'));
    await tester.pump();
    final saved = h.container.read(convertStylePrefsProvider);
    expect(saved.sizeMode, ConvertSizeMode.handwriting);
    expect(saved.joinLines, isFalse);
    expect((saved.bold, saved.italic), (true, true), reason: 'two quick taps both count');

    // Auto-convert's own switches are here too.
    await tester.ensureVisible(key('style-auto-convert'));
    await tester.tap(key('style-auto-convert'));
    await tester.pump();
    expect(h.container.read(settingsProvider).autoConvert, isTrue);

    await tester.ensureVisible(key('style-done'));
    await tester.tap(key('style-done'));
    await tester.pumpAndSettle();
    expect(find.text('Typed text'), findsNothing);
  });

}
