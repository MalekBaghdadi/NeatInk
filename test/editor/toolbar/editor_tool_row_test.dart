import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/editor_controller.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/tool_prefs.dart';
import 'package:neatink/features/editor/toolbar/color_picker_dialog.dart' show hexOf;
import 'package:neatink/features/editor/toolbar/editor_tool_row.dart';
import 'package:neatink/features/editor/toolbar/line_style_widgets.dart';
import 'package:neatink/features/editor/toolbar/tool_options.dart';
import 'package:neatink/features/editor/toolbar/toolbar_widgets.dart';
import 'package:neatink/ink/line_style.dart';
import 'package:neatink/ink/stroke.dart';

import 'toolbar_harness.dart';

void main() {
  final pill = find.byKey(const ValueKey('ink-settings-pill'));
  final panel = find.byKey(const ValueKey('ink-settings-panel'));
  Finder chip(String style) => find.byKey(ValueKey('ink-settings-line-$style'));
  Finder tool(EditorTool t) => find.byKey(ValueKey('tool-${t.name}'));

  /// Shows the tool row of a fresh controller, like the editor does.
  Future<EditorController> pumpRow(
    WidgetTester tester, {
    Size screen = const Size(1280, 800),
    Brightness brightness = Brightness.light,
    void Function(EditorController controller)? setup,
  }) async {
    final controller = await toolbarController();
    setup?.call(controller);
    useScreen(tester, screen);
    await tester.pumpWidget(themedApp(
      Column(children: [
        EditorToolRow(controller: controller),
        const Expanded(child: SizedBox.expand()),
      ]),
      brightness: brightness,
    ));
    await tester.pumpAndSettle();
    return controller;
  }

  group('the pill', () {
    testWidgets('ends the pen options, after the width dots', (tester) async {
      await pumpRow(tester);
      expect(pill, findsOneWidget);
      expect(find.byTooltip('Pen settings'), findsOneWidget);
      expect(tester.getTopLeft(pill).dx,
          greaterThan(tester.getTopRight(find.byType(WidthDotButton).last).dx));
      expect(tester.getSize(find.descendant(of: pill, matching: find.byType(InkWell))),
          const Size(64, 32));
    });

    testWidgets('shows the current line style of the pen', (tester) async {
      final c = await pumpRow(tester);
      expect(tester.widget<LineStylePill>(pill).line, LineSettings.solid);
      c.setPenLine(const LineSettings(style: LineStyle.zigzag));
      await tester.pump();
      expect(tester.widget<LineStylePill>(pill).line.style, LineStyle.zigzag);
    });

    testWidgets('has the pen colour, or the text colour when that is invisible',
        (tester) async {
      final c = await pumpRow(tester);
      c.setPenColor(0xFFD93025);
      await tester.pump();
      expect(tester.widget<LineStylePill>(pill).color, 0xFFD93025);
      // A white pen on the light toolbar would vanish.
      c.setPenColor(0xFFFFFFFF);
      await tester.pump();
      expect(tester.widget<LineStylePill>(pill).color,
          isNot(0xFFFFFFFF));
    });

    testWidgets('opens the pen settings panel under the tool row, at the right',
        (tester) async {
      await pumpRow(tester);
      await tester.tap(pill);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      expect(find.text('Ballpoint'), findsOneWidget);
      final row = tester.getRect(find.byType(EditorToolRow));
      final card = tester.getRect(panel);
      expect(card.top, greaterThanOrEqualTo(row.bottom));
      expect(card.top, lessThan(row.bottom + 16));
      expect(card.right, 1280 - 8);
      expect(card.width, 340);
    });

    testWidgets('the panel changes the pen at once, and the pill follows',
        (tester) async {
      final c = await pumpRow(tester);
      await tester.tap(pill);
      await tester.pumpAndSettle();
      await tester.tap(chip('dashed'));
      await tester.pumpAndSettle();
      expect(c.toolPrefs.pen.line.style, LineStyle.dashed);
      expect(tester.widget<LineStylePill>(pill).line.style, LineStyle.dashed);
      // Reset is live too.
      await tester.tap(find.byKey(const ValueKey('ink-settings-reset')));
      await tester.pumpAndSettle();
      expect(c.toolPrefs.pen.line, LineSettings.solid);
    });

    testWidgets('a tap outside closes the panel', (tester) async {
      await pumpRow(tester);
      await tester.tap(pill);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      await tester.tapAt(const Offset(40, 600));
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
    });

    testWidgets('back closes the panel', (tester) async {
      await pumpRow(tester);
      await tester.tap(pill);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
    });

    testWidgets('the highlighter has its own pill and panel', (tester) async {
      final c = await pumpRow(tester,
          setup: (c) => c.selectTool(EditorTool.highlighter));
      expect(find.byTooltip('Highlighter settings'), findsOneWidget);
      expect(find.byTooltip('Pen settings'), findsNothing);
      await tester.tap(pill);
      await tester.pumpAndSettle();
      expect(find.text('Highlighter'), findsWidgets);
      expect(
          find.descendant(of: panel, matching: find.text('Highlighter')), findsOneWidget);
      await tester.tap(chip('wavy'));
      await tester.pumpAndSettle();
      expect(c.toolPrefs.highlighter.line.style, LineStyle.wavy);
      expect(c.toolPrefs.pen.line, LineSettings.solid);
    });
  });

  group('custom colours', () {
    final add = find.byKey(const ValueKey('ink-settings-color-add'));

    testWidgets('the toolbar colour button still opens the pen picker',
        (tester) async {
      final c = await pumpRow(tester);
      await tester.tap(find.byType(CustomColorButton));
      await tester.pumpAndSettle();
      expect(find.text('Pen colour'), findsOneWidget);
      await tester.tap(find.text('Use colour'));
      await tester.pumpAndSettle();
      expect(ToolPresets.penColors, isNot(contains(c.toolPrefs.pen.color)));
      expect(c.toolPrefs.recentColors, [c.toolPrefs.pen.color]);
    });

    testWidgets('the panel plus does the same for the pen', (tester) async {
      final c = await pumpRow(tester);
      await tester.tap(pill);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('Pen colour'), findsOneWidget);
      await tester.tap(find.text('Use colour'));
      await tester.pumpAndSettle();
      final picked = c.toolPrefs.pen.color;
      expect(ToolPresets.penColors, isNot(contains(picked)));
      expect(c.toolPrefs.recentColors, [picked]);
      // The new colour joins the grid, selected.
      final swatch = find.byKey(ValueKey('ink-settings-color-$picked'));
      expect(tester.widget<ColorSwatchButton>(swatch).selected, isTrue);
    });

    testWidgets('the panel plus works for the highlighter, too',
        (tester) async {
      final c = await pumpRow(tester,
          setup: (c) => c.selectTool(EditorTool.highlighter));
      await tester.tap(pill);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('Highlighter colour'), findsOneWidget);
      // The picker starts from the current colour: take a ready colour that
      // is not one of the six presets.
      const picked = 0xFF90CAF9;
      expect(ToolPresets.highlighterColors, isNot(contains(picked)));
      final dot = find.byKey(ValueKey('palette-${hexOf(picked)}'));
      await tester.ensureVisible(dot);
      await tester.tap(dot);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use colour'));
      await tester.pumpAndSettle();
      expect(c.toolPrefs.highlighter.color, picked);
      expect(c.toolPrefs.recentColors, [picked]);
      expect(c.toolPrefs.pen.color, const PenPrefs().color,
          reason: 'the pen keeps its own colour');
    });

    testWidgets('cancelling the picker changes no colour', (tester) async {
      final c = await pumpRow(tester);
      await tester.tap(pill);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.toolPrefs.pen.color, const PenPrefs().color);
      expect(c.toolPrefs.recentColors, isEmpty);
    });
  });

  group('tapping the selected tool', () {
    testWidgets('the selected pen opens its settings', (tester) async {
      final c = await pumpRow(tester);
      expect(c.tool, EditorTool.pen);
      await tester.tap(tool(EditorTool.pen));
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text('Ballpoint')),
          findsOneWidget);
    });

    testWidgets('the pen settings show the pen that is selected',
        (tester) async {
      await pumpRow(tester, setup: (c) => c.setPenStyle(PenStyle.technical));
      await tester.tap(tool(EditorTool.pen));
      await tester.pumpAndSettle();
      expect(find.descendant(of: panel, matching: find.text('Technical pen')),
          findsOneWidget);
    });

    testWidgets('a tool that is not selected is only selected',
        (tester) async {
      final c = await pumpRow(tester);
      await tester.tap(tool(EditorTool.highlighter));
      await tester.pumpAndSettle();
      expect(c.tool, EditorTool.highlighter);
      expect(panel, findsNothing);
      // The next tap on it is the second one.
      await tester.tap(tool(EditorTool.highlighter));
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text('Highlighter')),
          findsOneWidget);
    });

    testWidgets('going back to the pen selects it without a panel',
        (tester) async {
      final c = await pumpRow(tester,
          setup: (c) => c.selectTool(EditorTool.highlighter));
      await tester.tap(tool(EditorTool.pen));
      await tester.pumpAndSettle();
      expect(c.tool, EditorTool.pen);
      expect(panel, findsNothing);
    });
  });

  group('extra tool row buttons', () {
    const action = ValueKey('test-action');

    testWidgets('are drawn after the tool buttons, behind a divider',
        (tester) async {
      EditorController? seen;
      final withoutDivider = <int>[];
      await pumpRow(tester, setup: (c) {
        c.extensions.toolRowActions.add((context, controller) {
          seen = controller;
          return const SizedBox(key: action, width: 44, height: 44);
        });
      });
      expect(find.byKey(action), findsOneWidget);
      expect(seen, isNotNull);
      final shape = tester.getRect(tool(EditorTool.shape));
      final extra = tester.getRect(find.byKey(action));
      expect(extra.left, greaterThan(shape.right));
      expect(extra.center.dy, shape.center.dy);
      withoutDivider.add(find.byType(ToolbarDivider).evaluate().length);

      // Without the action there is one divider less.
      await pumpRow(tester);
      expect(find.byKey(action), findsNothing);
      expect(find.byType(ToolbarDivider).evaluate().length,
          withoutDivider.single - 1);
    });

    testWidgets('keep their order', (tester) async {
      await pumpRow(tester, setup: (c) {
        c.extensions.toolRowActions
          ..add((_, _) => const SizedBox(key: ValueKey('a'), width: 44, height: 44))
          ..add((_, _) => const SizedBox(key: ValueKey('b'), width: 44, height: 44));
      });
      expect(tester.getTopLeft(find.byKey(const ValueKey('a'))).dx,
          lessThan(tester.getTopLeft(find.byKey(const ValueKey('b'))).dx));
    });

    testWidgets('appear when an integration registers one later',
        (tester) async {
      final c = await pumpRow(tester);
      expect(find.byKey(action), findsNothing);
      c.extensions.toolRowActions
          .add((_, _) => const SizedBox(key: action, width: 44, height: 44));
      c.extensionsChanged();
      await tester.pump();
      expect(find.byKey(action), findsOneWidget);
    });
  });

  group('on a phone', () {
    for (final brightness in Brightness.values) {
      testWidgets('opens the panel from the pill, ${brightness.name} theme',
          (tester) async {
        final c = await pumpRow(tester,
            screen: const Size(360, 800), brightness: brightness);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(pill);
        await tester.pumpAndSettle();
        await tester.tap(pill);
        await tester.pumpAndSettle();
        expect(panel, findsOneWidget);
        final row = tester.getRect(find.byType(EditorToolRow));
        final card = tester.getRect(panel);
        expect(card.top, greaterThanOrEqualTo(row.bottom),
            reason: 'under both rows of the tool row');
        expect(card.right, lessThanOrEqualTo(360));
        expect(card.width, 340);
        await tester.tap(chip('wavy'));
        await tester.pumpAndSettle();
        expect(c.toolPrefs.pen.line.style, LineStyle.wavy);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('tapping the selected pen opens the panel too',
        (tester) async {
      await pumpRow(tester, screen: const Size(360, 800));
      await tester.tap(tool(EditorTool.pen));
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the technical pen', () {
    testWidgets('is one of the pens in the pen menu', (tester) async {
      final c = await pumpRow(tester);
      await tester.tap(find.byType(PenStyleMenu));
      await tester.pumpAndSettle();
      for (final name in ['Ballpoint', 'Fountain pen', 'Pencil', 'Technical pen']) {
        expect(find.text(name), findsWidgets, reason: name);
      }
      await tester.tap(find.text('Technical pen').last);
      await tester.pumpAndSettle();
      expect(c.toolPrefs.pen.style, PenStyle.technical);
    });

    for (final style in PenStyle.values) {
      testWidgets('${style.name} has a sample stroke', (tester) async {
        await tester.pumpWidget(themedApp(Center(
          child: PenStylePreview(style: style, color: 0xFF1E5BD8),
        )));
        expect(tester.takeException(), isNull);
        final paint = find.descendant(
            of: find.byType(PenStylePreview), matching: find.byType(CustomPaint));
        // The pencil is translucent, so the colour is not checked.
        expect(tester.renderObject(paint.first), paints..path());
      });
    }
  });
}
