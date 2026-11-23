import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/app/theme.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/canvas/document_view.dart';
import 'package:neatink/features/editor/editor_controller.dart';
import 'package:neatink/features/editor/editor_integrations.dart';
import 'package:neatink/features/editor/editor_screen.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/ink/line_style.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../fakes/in_memory_repository.dart';
import 'toolbar_harness.dart';

/// The pen settings panel inside the real editor screen: what is chosen in it
/// is what the next stroke gets.
void main() {
  final pill = find.byKey(const ValueKey('ink-settings-pill'));
  final panel = find.byKey(const ValueKey('ink-settings-panel'));
  Finder chip(String style) => find.byKey(ValueKey('ink-settings-line-$style'));

  late EditorController controller;

  Future<void> openEditor(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = InMemoryNotebookRepository();
    final meta = await repo.createNotebook(
        title: 'Test', paper: const Paper(), pageCount: 1);
    useScreen(tester, const Size(1280, 1400));
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notebookRepositoryProvider.overrideWithValue(repo),
      editorIntegrationsProvider.overrideWithValue([
        (c, ref) => controller = c,
      ]),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: EditorScreen(notebookId: meta.id),
      ),
    ));
    await tester.pumpAndSettle();
    expect(controller.isReady, isTrue);
  }

  /// A short diagonal stroke with the stylus.
  Future<void> draw(WidgetTester tester) async {
    final start =
        tester.getCenter(find.byType(DocumentView)) - const Offset(100, 100);
    final g = await tester.startGesture(start, kind: PointerDeviceKind.stylus);
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(14, 9));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await g.up();
    await tester.pump();
  }

  Stroke lastStroke() =>
      controller.doc.page(controller.doc.meta.pages.first.id).strokes.last;

  testWidgets('the panel opens under the tool row, over the page',
      (tester) async {
    await openEditor(tester);
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    final row = tester.getRect(find.byKey(const ValueKey('tool-pen')));
    expect(tester.getTopLeft(panel).dy, greaterThan(row.bottom - 1));
    expect(tester.getRect(panel).right, 1280 - 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a line style chosen in the panel is on the next stroke',
      (tester) async {
    await openEditor(tester);
    await tester.tap(pill);
    await tester.pumpAndSettle();
    await tester.tap(chip('dashed'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 1300));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);

    await draw(tester);
    expect(lastStroke().line.style, LineStyle.dashed);
    expect(lastStroke().concentration, 1.0);
  });

  testWidgets('thickness, concentration and wave settings reach the stroke',
      (tester) async {
    await openEditor(tester);
    await tester.tap(find.byKey(const ValueKey('tool-pen')));
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget, reason: 'a tap on the selected pen');
    await tester.tap(chip('zigzag'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ink-settings-wave-height-plus')));
    await tester.tap(find.byKey(const ValueKey('ink-settings-thickness-plus')));
    await tester.pump();
    await tester.drag(
        find.byKey(const ValueKey('ink-settings-concentration')),
        const Offset(-120, 0));
    await tester.pumpAndSettle();
    final concentration = controller.toolPrefs.pen.concentration;
    expect(concentration, lessThan(1.0));
    await tester.tapAt(const Offset(20, 1300));
    await tester.pumpAndSettle();

    await draw(tester);
    final stroke = lastStroke();
    expect(stroke.line.style, LineStyle.zigzag);
    expect(stroke.line.waveHeight, 3.2);
    expect(stroke.size, 2.3);
    expect(stroke.concentration, concentration);
  });

  testWidgets('the highlighter panel styles the highlighter', (tester) async {
    await openEditor(tester);
    await tester.tap(find.byKey(const ValueKey('tool-highlighter')));
    await tester.pumpAndSettle();
    expect(controller.tool, EditorTool.highlighter);
    await tester.tap(pill);
    await tester.pumpAndSettle();
    await tester.tap(chip('wavy'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 1300));
    await tester.pumpAndSettle();

    await draw(tester);
    final stroke = lastStroke();
    expect(stroke.tool, StrokeTool.highlighter);
    expect(stroke.line.style, LineStyle.wavy);
    expect(controller.toolPrefs.pen.line, LineSettings.solid);
  });

  testWidgets('Reset in the panel gives plain strokes again', (tester) async {
    await openEditor(tester);
    await tester.tap(pill);
    await tester.pumpAndSettle();
    await tester.tap(chip('parallel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ink-settings-reset')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 1300));
    await tester.pumpAndSettle();

    await draw(tester);
    expect(lastStroke().line, LineSettings.solid);
  });
}
