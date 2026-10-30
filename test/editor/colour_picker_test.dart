import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/tool_prefs.dart';
import 'package:neatink/features/editor/toolbar/color_picker_dialog.dart';
import 'package:neatink/features/settings/convert_style_prefs.dart';

import 'integrations/convert/harness.dart';
import 'integrations/erase_select/harness.dart';

// v1.13.0: "add a colour picker so she can choose any colour she wants":
// the highlighter and the typed text get the picker the pen had, and the
// picker starts with ready colours.

Finder key(String k) => find.byKey(ValueKey(k));

void main() {
  testWidgets('the highlighter takes any colour, kept with the recent colours', (tester) async {
    final h = await EraseSelectHarness.open(tester);
    h.controller.selectTool(EditorTool.highlighter);
    await tester.pump();
    expect(key('highlighter-colour-0'), findsOneWidget);
    await tester.tap(key('highlighter-colour-custom'));
    await tester.pumpAndSettle();
    expect(find.text('Highlighter colour'), findsOneWidget);
    await tester.tap(key('palette-8E24AA'));
    await tester.pump();
    await tester.tap(find.text('Use colour'));
    await tester.pumpAndSettle();
    expect(h.controller.toolPrefs.highlighter.color, 0xFF8E24AA);
    expect(h.controller.toolPrefs.recentColors.first, 0xFF8E24AA);

    // Cancel changes nothing.
    await tester.tap(key('highlighter-colour-custom'));
    await tester.pumpAndSettle();
    await tester.tap(key('palette-FFEB3B'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.controller.toolPrefs.highlighter.color, 0xFF8E24AA);

    // A preset again.
    await tester.tap(key('highlighter-colour-0'));
    await tester.pump();
    expect(h.controller.toolPrefs.highlighter.color, ToolPresets.highlighterColors.first);
    await h.close();
  });

  testWidgets('the pen: one of the ready colours, or one mixed by its code', (tester) async {
    final h = await EraseSelectHarness.open(tester);
    h.controller.selectTool(EditorTool.pen);
    await tester.pump();
    await tester.tap(key('pen-colour-custom'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('palette-000000')), findsOneWidget);
    expect(find.text('Or mix your own'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '12AB34');
    await tester.pump();
    await tester.tap(find.text('Use colour'));
    await tester.pumpAndSettle();
    expect(h.controller.toolPrefs.pen.color, 0xFF12AB34);
    await h.close();
  });

  test('the ready colours are forty different opaque colours', () {
    expect(pickerPalette, hasLength(40));
    expect(pickerPalette.toSet(), hasLength(40));
    expect(pickerPalette.every((c) => c >>> 24 == 0xFF), isTrue);
  });

  testWidgets('a narrow (portrait) screen gives the colours a row of their own, all in view', (tester) async {
    final h = await EraseSelectHarness.open(tester);
    tester.view.physicalSize = const Size(900, 1400);
    await tester.pumpAndSettle();
    h.controller.selectTool(EditorTool.pen);
    await tester.pump();
    final screen = tester.getRect(find.byType(Scaffold));
    for (final k in ['pen-colour-7', 'pen-colour-custom', 'pen-width-2']) {
      final r = tester.getRect(key(k));
      expect(r.right, lessThanOrEqualTo(screen.right), reason: '$k is on screen');
    }
    await h.close();
  });

  testWidgets('typed text can be any colour too', (tester) async {
    final h = await ConvertHarness.open(tester);
    await tester.tap(key('convert-settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(key('convert-colour-custom'));
    await tester.tap(key('convert-colour-custom'));
    await tester.pumpAndSettle();
    expect(find.text('Typed text colour'), findsOneWidget);
    await tester.tap(key('palette-0D47A1'));
    await tester.tap(find.text('Use colour'));
    await tester.pumpAndSettle();
    expect(h.container.read(convertStylePrefsProvider).colorOverride, 0xFF0D47A1);
  });
}
