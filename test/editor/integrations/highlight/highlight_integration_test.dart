import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/canvas/document_view.dart';
import 'package:neatink/features/editor/editor_controller.dart';
import 'package:neatink/features/editor/editor_integrations.dart';
import 'package:neatink/features/editor/editor_screen.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/integrations/highlight/highlight_integration.dart';
import 'package:neatink/features/editor/integrations/shapes/shapes_integration.dart';
import 'package:neatink/features/editor/tools/highlight_tidy.dart';
import 'package:neatink/features/settings/app_settings.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../fakes/in_memory_repository.dart';

// The test font draws every glyph as a square as wide as the font size:
// "hello world" at size 20 from x = 100 has "hello" at 100..200 and "world"
// at 220..320, on one line (ascent 16, descent 4: baseline at y + 16).
const text = TextItem(id: 't1', x: 100, y: 100, width: 400, height: 24, text: 'hello world', fontSize: 20);

class _Harness {
  _Harness(this.tester, this.controller);

  final WidgetTester tester;
  final EditorController controller;

  static Future<_Harness> open(WidgetTester tester, {bool? tidy}) async {
    SharedPreferences.setMockInitialValues({
      if (tidy != null) AppSettings.prefsKey: jsonEncode({'tidyHighlighter': tidy}),
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = InMemoryNotebookRepository();
    final meta = await repo.createNotebook(title: 'Test', paper: const Paper(), pageCount: 1);
    await repo.savePage(meta.id, meta.pages.first.id, PageContent(texts: [text]));
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    EditorController? captured;
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notebookRepositoryProvider.overrideWithValue(repo),
      editorIntegrationsProvider.overrideWithValue([
        (controller, ref) => captured = controller,
        shapesIntegration,
        highlightIntegration,
      ]),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: EditorScreen(notebookId: meta.id)),
    ));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });
    return _Harness(tester, captured!);
  }

  List<Stroke> get strokes => controller.doc.page(controller.doc.meta.pages.first.id).strokes;

  Offset at(Vec2 p) => tester.getTopLeft(find.byType(DocumentView)) + controller.viewport.pageToLocal(0, p);

  Future<void> drag(List<Vec2> points) async {
    final g = await tester.startGesture(at(points.first), kind: PointerDeviceKind.stylus);
    await tester.pump(const Duration(milliseconds: 8));
    for (final p in points.skip(1)) {
      await g.moveTo(at(p));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await g.up();
    await tester.pump();
  }
}

/// A wobbly swipe from x 95 to 300 around y 110: all of "hello", most of "world".
final wobbly = [for (var i = 0; i <= 20; i++) Vec2(95 + i * 10.25, 110 + (i.isEven ? 2.0 : -2.0))];

void main() {
  testWidgets('a highlight over typed text becomes a straight band over its line', (tester) async {
    final h = await _Harness.open(tester);
    h.controller.selectTool(EditorTool.highlighter);
    await tester.pump();
    await h.drag(wobbly);

    final s = h.strokes.single;
    expect(s.tool, StrokeTool.highlighter);
    expect(s.pointsAreRaw, isFalse, reason: 'tidied');
    expect(s.raw.length, greaterThan(5), reason: 'the drawn stroke is kept');
    final lines = textItemHighlightLines(text);
    final band = lines.single;
    expect(s.size, closeTo(band.thickness, 1e-6));
    expect(s.rawSize, isNotNull);
    expect(s.points.every((p) => (p.y - band.centerAt(p.x)).abs() < 0.02), isTrue);
    final pad = 0.12 * band.thickness;
    expect(s.points.first.x, closeTo(100 - pad, 0.05));
    expect(s.points.last.x, closeTo(320 + pad, 0.05));
    expect(h.controller.undoLabel, 'Highlighter');
  });

  testWidgets('with the setting off the highlight stays as drawn', (tester) async {
    final h = await _Harness.open(tester, tidy: false);
    h.controller.selectTool(EditorTool.highlighter);
    await tester.pump();
    await h.drag(wobbly);
    expect(h.strokes.single.pointsAreRaw, isTrue);
    expect(h.strokes.single.rawSize, isNull);
  });

  testWidgets('pen strokes are never tidied', (tester) async {
    final h = await _Harness.open(tester);
    h.controller.selectTool(EditorTool.pen);
    await tester.pump();
    await h.drag(wobbly);
    expect(h.strokes.single.pointsAreRaw, isTrue);
  });

  test('the setting is on by default', () {
    expect(const AppSettings().tidyHighlighter, isTrue);
    expect(AppSettings.fromJson(const {}).tidyHighlighter, isTrue);
    expect(AppSettings.fromJson(const {'tidyHighlighter': false}).tidyHighlighter, isFalse);
  });

  testWidgets('typed text: one band per laid-out line, words where they are drawn', (tester) async {
    final two = text.copyWith(text: 'hello world brain', width: 260);
    final lines = textItemHighlightLines(two);
    expect(lines, hasLength(2), reason: '"brain" wraps');
    expect(lines.first.words, [(left: 100.0, right: 200.0), (left: 220.0, right: 320.0)]);
    expect(lines.last.words, [(left: 100.0, right: 200.0)]);
    expect(lines.last.top, greaterThan(lines.first.bottom));
    expect(textItemHighlightLines(text.copyWith(text: '   ')), isEmpty);
  });

  test('printed words make lines by rows', () {
    final lines = wordBoxHighlightLines([
      (left: 50, top: 100, right: 80, bottom: 112),
      (left: 10, top: 101, right: 40, bottom: 112),
      (left: 10, top: 130, right: 60, bottom: 142),
    ]);
    expect(lines, hasLength(2));
    expect(lines.first.words, [(left: 10.0, right: 40.0), (left: 50.0, right: 80.0)]);
    expect(lines.first.top, 100);
    expect(lines.first.bottom, 112);
    expect(lines.last.left, 10);
    expect(wordBoxHighlightLines(const []), isEmpty);
    expect(lines.first, isA<HighlightLine>());
  });
}
