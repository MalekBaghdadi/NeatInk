import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/editor_controller.dart';
import 'package:neatink/features/editor/editor_integrations.dart';
import 'package:neatink/features/editor/editor_screen.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/integrations/erase_select/clipboard.dart';
import 'package:neatink/features/editor/integrations/erase_select/erase_select_integration.dart';
import 'package:neatink/features/editor/integrations/erase_select/lasso_handler.dart';
import 'package:neatink/features/editor/tools/selection.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/ink_rect.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../fakes/in_memory_repository.dart';
import 'harness.dart';

Stroke line(String id, double x0, double y0, double x1, double y1) => Stroke(
      id: id,
      tool: StrokeTool.pen,
      color: 0xFF000000,
      size: 2,
      raw: [InkPoint(x0, y0, 0.5, 0), InkPoint((x0 + x1) / 2, (y0 + y1) / 2, 0.5, 8), InkPoint(x1, y1, 0.5, 16)],
    );

Finder key(String k) => find.byKey(ValueKey(k));

void main() {
  group('helpers', () {
    test('pasteOffset centres on the point and keeps things on the page', () {
      const b = InkRect(100, 100, 140, 120); // 40 x 20
      expect(pasteOffset(b, const Vec2(300, 300), pageWidth: 595, pageHeight: 842), const Vec2(180, 190));
      expect(pasteOffset(b, const Vec2(0, 0), pageWidth: 595, pageHeight: 842), const Vec2(-100, -100));
      expect(pasteOffset(b, const Vec2(595, 842), pageWidth: 595, pageHeight: 842), const Vec2(455, 722));
      const big = InkRect(10, 10, 1010, 30);
      expect(pasteOffset(big, const Vec2(300, 300), pageWidth: 595, pageHeight: 842).x, -10, reason: 'its left edge at 0');
    });

    test('plainTextOf: top to bottom, then left to right, empty boxes skipped', () {
      const a = TextItem(id: 'a', x: 300, y: 100, width: 100, height: 20, text: 'right');
      const b = TextItem(id: 'b', x: 50, y: 102, width: 100, height: 20, text: 'left');
      const c = TextItem(id: 'c', x: 50, y: 200, width: 100, height: 20, text: ' below ');
      const d = TextItem(id: 'd', x: 50, y: 300, width: 100, height: 20, text: '  ');
      expect(plainTextOf([c, a, d, b]), 'left\n\nright\n\nbelow');
    });

    test('content bounds cover strokes, boxes and pictures', () {
      final content = ClipContent(
        notebookId: 'n',
        strokes: [line('s', 100, 100, 150, 100)],
        texts: const [TextItem(id: 't', x: 50, y: 200, width: 60, height: 20, text: 'x')],
        images: [
          ClipImage(
            item: const ImageItem(id: 'i', x: 300, y: 50, width: 40, height: 40, asset: 'a.png'),
            extension: '.png',
            bytes: Future.value(null),
          ),
        ],
      );
      expect(content.bounds.left, 50);
      expect(content.bounds.top, 50);
      expect(content.bounds.right, 340);
      expect(content.bounds.bottom, 220);
      expect(content.isEmpty, isFalse);
    });
  });

  group('in the editor', () {
    testWidgets('Copy, then a lasso tap on an empty spot offers Paste there', (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: [line('s', 100, 100, 150, 100)]);
      await h.lassoRect(80, 80, 170, 120);
      await tester.tap(key('selection-copy'));
      await tester.pump();
      expect(h.strokes, hasLength(1), reason: 'copying changes nothing');

      await h.drag([const Vec2(300, 400)]);
      await tester.pump();
      expect(key('paste-bubble'), findsOneWidget);
      await tester.tap(key('paste-bubble'));
      await tester.pumpAndSettle();

      expect(h.strokes, hasLength(2));
      final pasted = h.strokes.last;
      expect(pasted.id, isNot('s'));
      expect(pasted.points.first.x, closeTo(275, 0.01), reason: 'its middle on the tapped spot');
      expect(pasted.points.first.y, closeTo(400, 0.01));
      expect(h.controller.undoLabel, 'Paste');
      expect(h.lasso.state.selection!.strokeIds, {pasted.id}, reason: 'ready to move');
      expect(key('paste-bubble'), findsNothing);

      h.controller.undo();
      await tester.pump();
      expect(h.strokes, hasLength(1));
    });

    testWidgets('Cut removes the selection; More > Paste puts it in the middle of the view', (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: [line('s', 100, 100, 150, 100)]);
      await h.lassoRect(80, 80, 170, 120);
      await tester.tap(key('selection-cut'));
      await tester.pump();
      expect(h.strokes, isEmpty);
      expect(h.controller.undoLabel, 'Cut');

      await tester.tap(key('editor-menu'));
      await tester.pumpAndSettle();
      await tester.tap(key('menu-paste'));
      await tester.pumpAndSettle();
      expect(h.strokes, hasLength(1));
      expect(h.strokes.single.id, isNot('s'));
      expect(h.controller.tool, EditorTool.lasso);
    });

    testWidgets('no Paste anywhere while the clipboard is empty', (tester) async {
      final h = await EraseSelectHarness.open(tester, strokes: [line('s', 100, 100, 150, 100)]);
      h.controller.selectTool(EditorTool.lasso);
      await tester.pump();
      await h.drag([const Vec2(300, 400)]);
      expect(key('paste-bubble'), findsNothing);
      await tester.tap(key('editor-menu'));
      await tester.pumpAndSettle();
      expect(key('menu-paste'), findsNothing);
    });

    testWidgets('copying typed text also gives it to other apps', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final h = await EraseSelectHarness.open(tester,
          texts: const [TextItem(id: 't', x: 100, y: 100, width: 200, height: 24, text: 'Neurons fire')]);
      await h.lassoRect(80, 80, 320, 140);
      await tester.tap(key('selection-copy'));
      await tester.pump();
      final set = calls.where((c) => c.method == 'Clipboard.setData').single;
      expect((set.arguments as Map)['text'], 'Neurons fire');
    });
  });

  testWidgets('a picture pasted into another notebook gets its own copy of the file', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = InMemoryNotebookRepository();
    final a = await repo.createNotebook(title: 'A', paper: const Paper(), pageCount: 1);
    final b = await repo.createNotebook(title: 'B', paper: const Paper(), pageCount: 1);
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final asset = await repo.addAssetBytes(a.id, bytes, '.png');
    await repo.savePage(a.id, a.pages.first.id, PageContent(images: [
      ImageItem(id: 'img', x: 100, y: 100, width: 80, height: 60, asset: asset),
    ]));
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    EditorController? captured;
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notebookRepositoryProvider.overrideWithValue(repo),
      editorIntegrationsProvider.overrideWithValue([
        (controller, ref) => captured = controller,
        eraseSelectIntegration,
      ]),
    ]);
    addTearDown(container.dispose);
    Future<EditorController> open(String id) async {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(key: ValueKey(id), home: EditorScreen(notebookId: id)),
      ));
      await tester.pumpAndSettle();
      return captured!;
    }

    final first = await open(a.id);
    final lasso = first.extensions.toolHandlers[EditorTool.lasso]! as LassoHandler;
    first.selectTool(EditorTool.lasso);
    lasso.state.setSelection(Selection.fromPage(first.doc.page(a.pages.first.id), pageId: a.pages.first.id, imageIds: ['img']));
    lasso.copySelected();
    await tester.pump();

    final second = await open(b.id);
    expect(identical(second, first), isFalse);
    final lassoB = second.extensions.toolHandlers[EditorTool.lasso]! as LassoHandler;
    expect(await tester.runAsync(() => lassoB.pasteAt(b.pages.first.id, const Vec2(300, 300))), isTrue);
    await tester.pump();
    final pasted = second.doc.page(b.pages.first.id).images.single;
    expect(pasted.asset, isNot(asset), reason: 'a file of notebook B');
    expect(repo.assetBytes(b.id, pasted.asset), bytes);
    expect(pasted.x, 260);
    expect(pasted.y, 270);
    await tester.pumpWidget(const SizedBox());
  });
}
