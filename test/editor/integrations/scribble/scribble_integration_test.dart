import 'dart:convert';
import 'dart:math' as math;

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
import 'package:neatink/features/editor/integrations/scribble/scribble_integration.dart';
import 'package:neatink/features/editor/integrations/shapes/shapes_integration.dart';
import 'package:neatink/features/settings/app_settings.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../fakes/in_memory_repository.dart';

// The test font draws every glyph as a square as wide as the font size:
// "hello world" at size 20 from x = 100 has "hello" at 100..200 and "world"
// at 220..320, on the line 100..120.
const text = TextItem(id: 't1', x: 100, y: 100, width: 400, height: 24, text: 'hello world', fontSize: 20);

/// A handwritten "word" at x 100..160 on baseline 200: four small loops.
final List<Stroke> ink = [
  for (var i = 0; i < 4; i++)
    Stroke(
      id: 'ink$i',
      tool: StrokeTool.pen,
      color: 0xFF000000,
      size: 2,
      raw: [
        for (var a = 0; a <= 16; a++)
          InkPoint(106 + 15.0 * i + 5 * math.cos(a * math.pi / 8), 194 + 5 * math.sin(a * math.pi / 8), 0.5, a * 8),
      ],
    ),
];

class _Harness {
  _Harness(this.tester, this.controller);

  final WidgetTester tester;
  final EditorController controller;

  static Future<_Harness> open(WidgetTester tester, {bool? scribble}) async {
    SharedPreferences.setMockInitialValues({
      if (scribble != null) AppSettings.prefsKey: jsonEncode({'scribbleToDelete': scribble}),
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = InMemoryNotebookRepository();
    final meta = await repo.createNotebook(title: 'Test', paper: const Paper(), pageCount: 1);
    await repo.savePage(meta.id, meta.pages.first.id, PageContent(strokes: [...ink], texts: [text]));
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
        scribbleIntegration,
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

  PageContent get page => controller.doc.page(controller.doc.meta.pages.first.id);

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

/// Back and forth between x0 and x1, drifting from y0 to y1, [turns] times,
/// a point every 4 points.
List<Vec2> scratch(double x0, double x1, double y0, double y1, {int turns = 6}) => [
      for (var k = 0; k < turns; k++)
        for (var x = 0.0; x < (x1 - x0); x += 4)
          Vec2(k.isEven ? x0 + x : x1 - x, y0 + (y1 - y0) * (k + x / (x1 - x0)) / turns),
      Vec2(turns.isEven ? x0 : x1, y1),
    ];

void main() {
  testWidgets('a scribble over handwriting deletes it, and undo brings it back', (tester) async {
    final h = await _Harness.open(tester);
    expect(h.page.strokes, hasLength(4));
    await h.drag(scratch(98, 164, 189, 199));

    expect(h.page.strokes, isEmpty, reason: 'the word and the scribble are gone');
    expect(h.page.texts.single.text, 'hello world', reason: 'the typed text was not under it');
    expect(h.controller.undoLabel, 'Scribble to delete');

    h.controller.undo();
    await tester.pump();
    expect([for (final s in h.page.strokes) s.id], [for (final s in ink) s.id]);
  });

  testWidgets('a scribble over typed text deletes the words under it', (tester) async {
    final h = await _Harness.open(tester);
    await h.drag(scratch(216, 324, 104, 116));

    expect(h.page.texts.single.text, 'hello');
    expect(h.page.strokes, hasLength(4), reason: 'the handwriting was not under it');
    h.controller.undo();
    await tester.pump();
    expect(h.page.texts.single.text, 'hello world');
  });

  testWidgets('scribbling out every word removes the box', (tester) async {
    final h = await _Harness.open(tester);
    await h.drag(scratch(96, 324, 104, 116));
    expect(h.page.texts, isEmpty);
  });

  testWidgets('a scribble on empty paper is ink', (tester) async {
    final h = await _Harness.open(tester);
    await h.drag(scratch(100, 164, 400, 410));
    expect(h.page.strokes, hasLength(5));
    expect(h.controller.undoLabel, 'Pen stroke');
  });

  testWidgets('with the setting off a scribble is ink', (tester) async {
    final h = await _Harness.open(tester, scribble: false);
    await h.drag(scratch(98, 164, 189, 199));
    expect(h.page.strokes, hasLength(5));
    expect(h.page.texts.single.text, 'hello world');
  });

  test('the setting is on by default', () {
    expect(const AppSettings().scribbleToDelete, isTrue);
    expect(AppSettings.fromJson(const {}).scribbleToDelete, isTrue);
    expect(AppSettings.fromJson(const {'scribbleToDelete': false}).scribbleToDelete, isFalse);
    expect(const AppSettings(scribbleToDelete: false).toJson()['scribbleToDelete'], isFalse);
  });
}
