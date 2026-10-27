import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/commands.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/canvas/document_view.dart';
import 'package:neatink/features/editor/editor_controller.dart';
import 'package:neatink/features/editor/editor_extensions.dart';
import 'package:neatink/features/editor/editor_integrations.dart';
import 'package:neatink/features/editor/editor_screen.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/integrations/text_images/text_images_integration.dart';
import 'package:neatink/features/editor/integrations/text_images/image_layer.dart';
import 'package:neatink/features/editor/integrations/text_images/text_layer.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../fakes/in_memory_repository.dart';
import 'helpers_test.dart' show solidPng;

void main() {
  late InMemoryNotebookRepository repo;
  late SharedPreferences prefs;
  late NotebookMeta meta;
  late EditorController controller;
  Uint8List? pickedBytes;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repo = InMemoryNotebookRepository();
    meta = await repo.createNotebook(
        title: 'Notes', paper: const Paper(), pageCount: 2);
    pickedBytes = null;
  });

  String pageId() => meta.pages.first.id;
  PageContent content() => controller.doc.page(pageId());

  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notebookRepositoryProvider.overrideWithValue(repo),
      editorIntegrationsProvider.overrideWithValue([
        (c, ref) {
          controller = c;
          textImagesIntegration(c, ref);
        },
      ]),
      imagePickerProvider.overrideWithValue(() async =>
          pickedBytes == null ? null : PickedImage(pickedBytes!, name: 'p.png')),
      assetBytesLoaderProvider.overrideWithValue(
          (nb, asset) async => repo.assetBytes(nb, asset)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: EditorScreen(notebookId: meta.id)),
    ));
    await tester.pumpAndSettle();
  }

  /// Screen position of a point on the first page.
  Offset onPage(WidgetTester tester, double x, double y) {
    final origin = tester.getTopLeft(find.byType(DocumentView));
    return origin + controller.viewport.pageToLocal(0, Vec2(x, y));
  }

  Future<void> tapAt(WidgetTester tester, Offset at,
      {PointerDeviceKind kind = PointerDeviceKind.stylus}) async {
    final g = await tester.startGesture(at, kind: kind);
    await tester.pump(const Duration(milliseconds: 30));
    await g.up();
    await tester.pump();
  }

  Future<void> selectText(WidgetTester tester) async {
    controller.selectTool(EditorTool.text);
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
  }

  /// Ends editing the way a tool change does.
  Future<void> commit(WidgetTester tester) async {
    controller.selectTool(EditorTool.pen);
    await tester.pump();
  }

  const existing = TextItem(
      id: 't1', x: 100, y: 200, width: 200, height: 20, text: 'Hello', fontSize: 16);

  void addExisting() => controller.execute(PageItemsCommand(pageId(),
      label: 'Add text', textChanges: const [(null, existing)]));

  group('text tool', () {
    testWidgets('both tools are registered and enabled', (tester) async {
      await pumpEditor(tester);
      expect(controller.isToolAvailable(EditorTool.text), isTrue);
      expect(controller.isToolAvailable(EditorTool.image), isTrue);
      expect(controller.extensions.textLayer, isNotNull);
      expect(controller.extensions.imageLayer, isNotNull);
    });

    testWidgets('a pen tap creates a box; typing and committing is one undo step',
        (tester) async {
      await pumpEditor(tester);
      await selectText(tester);
      await tapAt(tester, onPage(tester, 150, 300));
      expect(find.byType(TextField), findsOneWidget);
      await type(tester, 'Hello world');
      await commit(tester);

      expect(find.byType(TextField), findsNothing);
      expect(content().texts, hasLength(1));
      final t = content().texts.single;
      expect(t.text, 'Hello world');
      expect(t.x, closeTo(150, 1));
      expect(t.height, greaterThan(10));
      expect(controller.undoLabel, 'Add text');

      controller.undo();
      expect(content().texts, isEmpty);
      controller.redo();
      expect(content().texts.single.text, 'Hello world');
    });

    testWidgets('a box left empty is not created', (tester) async {
      await pumpEditor(tester);
      await selectText(tester);
      await tapAt(tester, onPage(tester, 150, 300));
      await commit(tester);
      expect(content().texts, isEmpty);
      expect(controller.canUndo, isFalse);
    });

    testWidgets('tapping outside commits instead of creating another box',
        (tester) async {
      await pumpEditor(tester);
      await selectText(tester);
      await tapAt(tester, onPage(tester, 150, 300));
      await type(tester, 'one');
      await tapAt(tester, onPage(tester, 150, 600));
      expect(find.byType(TextField), findsNothing);
      expect(content().texts.single.text, 'one');
    });

    testWidgets('formatting while editing is stored with the box',
        (tester) async {
      await pumpEditor(tester);
      await selectText(tester);
      await tapAt(tester, onPage(tester, 150, 300));
      await type(tester, 'Styled');
      for (final key in ['text-bold', 'text-italic', 'text-underline', 'text-align-center']) {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pump();
      }
      await tester.ensureVisible(find.byKey(const ValueKey('text-size-up')));
      await tester.tap(find.byKey(const ValueKey('text-size-up')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('text-font')));
      await tester.tap(find.byKey(const ValueKey('text-font')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('text-font-serif')));
      await tester.pumpAndSettle();
      await commit(tester);

      final t = content().texts.single;
      expect(t.bold && t.italic && t.underline, isTrue);
      expect(t.align, TextAlignKind.center);
      expect(t.fontSize, 18);
      expect(t.font, FontKind.serif);
      // Style changes are part of the same single undo step.
      controller.undo();
      expect(content().texts, isEmpty);
    });

    testWidgets('the font picker lists every category and every font',
        (tester) async {
      await pumpEditor(tester);
      await selectText(tester);
      await tapAt(tester, onPage(tester, 150, 300));
      await type(tester, 'Fonts');
      await tester.ensureVisible(find.byKey(const ValueKey('text-font')));
      await tester.tap(find.byKey(const ValueKey('text-font')));
      await tester.pumpAndSettle();
      for (final c in FontCategory.values) {
        expect(find.byKey(ValueKey('text-font-heading-${c.name}')), findsOneWidget,
            reason: c.label);
        expect(find.text(c.label.toUpperCase()), findsOneWidget);
      }
      for (final f in FontKind.values) {
        expect(find.byKey(ValueKey('text-font-${f.name}')), findsOneWidget,
            reason: f.name);
      }
      // Each entry is drawn in its own font.
      final lato = tester.widget<Text>(
          find.descendant(
              of: find.byKey(const ValueKey('text-font-lato')),
              matching: find.byType(Text)));
      expect(lato.style?.fontFamily, FontKind.lato.family);
      await tester.ensureVisible(find.byKey(const ValueKey('text-font-caveat')));
      await tester.tap(find.byKey(const ValueKey('text-font-caveat')));
      await tester.pumpAndSettle();
      await commit(tester);
      expect(content().texts.single.font, FontKind.caveat);
    });

    testWidgets('a formatting change on an existing box is undoable',
        (tester) async {
      await pumpEditor(tester);
      addExisting();
      await selectText(tester);
      await tapAt(tester, onPage(tester, 150, 205));
      expect(find.byType(TextField), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('text-bold')));
      await tester.tap(find.byKey(const ValueKey('text-bold')));
      await tester.pump();
      await commit(tester);
      expect(content().texts.single.bold, isTrue);
      expect(controller.undoLabel, 'Format text');
      controller.undo();
      expect(content().texts.single.bold, isFalse);
      expect(content().texts.single.text, 'Hello');
    });

    testWidgets('emptying an existing box removes it, undo restores it',
        (tester) async {
      await pumpEditor(tester);
      addExisting();
      await selectText(tester);
      await tapAt(tester, onPage(tester, 150, 205));
      await type(tester, '');
      await commit(tester);
      expect(content().texts, isEmpty);
      expect(controller.undoLabel, 'Delete text');
      controller.undo();
      expect(content().texts.single.text, 'Hello');
    });

    testWidgets('the delete button removes the box being edited',
        (tester) async {
      await pumpEditor(tester);
      addExisting();
      await selectText(tester);
      await tapAt(tester, onPage(tester, 150, 205));
      await tester.ensureVisible(find.byKey(const ValueKey('text-delete')));
      await tester.tap(find.byKey(const ValueKey('text-delete')));
      await tester.pump();
      expect(content().texts, isEmpty);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('dragging a box moves it as one undo step', (tester) async {
      await pumpEditor(tester);
      addExisting();
      await selectText(tester);
      final g = await tester.startGesture(onPage(tester, 150, 205),
          kind: PointerDeviceKind.stylus);
      for (var i = 1; i <= 6; i++) {
        await g.moveBy(const Offset(10, 8));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await g.up();
      await tester.pump();
      await commit(tester);

      final t = content().texts.single;
      expect(t.x, greaterThan(100));
      expect(t.y, greaterThan(200));
      expect(t.width, 200);
      expect(controller.undoLabel, 'Move text');
      controller.undo();
      expect(content().texts.single.x, 100);
      expect(content().texts.single.y, 200);
    });

    testWidgets('dragging the width handle resizes the box', (tester) async {
      await pumpEditor(tester);
      addExisting();
      await selectText(tester);
      await tapAt(tester, onPage(tester, 150, 205)); // start editing
      final box = controller.extensions;
      expect(box.pageOverlays, isNotEmpty);
      final handleY = 200 + content().texts.single.height / 2;
      final g = await tester.startGesture(onPage(tester, 300, handleY),
          kind: PointerDeviceKind.stylus);
      for (var i = 1; i <= 5; i++) {
        await g.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await g.up();
      await tester.pump();
      await commit(tester);
      final t = content().texts.single;
      expect(t.width, greaterThan(250));
      expect(t.x, 100);
      expect(controller.undoLabel, 'Resize text');
    });

    testWidgets('a finger tap on a box edits it, a finger drag still scrolls',
        (tester) async {
      await pumpEditor(tester);
      addExisting();
      await selectText(tester);
      await tapAt(tester, onPage(tester, 150, 205), kind: PointerDeviceKind.touch);
      expect(find.byType(TextField), findsOneWidget);
      await commit(tester);

      await selectText(tester);
      final before = controller.viewport.offset;
      final g = await tester.startGesture(onPage(tester, 400, 600),
          kind: PointerDeviceKind.touch);
      for (var i = 1; i <= 6; i++) {
        await g.moveBy(const Offset(0, -30));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await g.up();
      await tester.pump();
      expect(controller.viewport.offset, isNot(before));
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('closing the editor commits the box being edited',
        (tester) async {
      await pumpEditor(tester);
      await selectText(tester);
      await tapAt(tester, onPage(tester, 150, 300));
      await type(tester, 'unsaved');
      // close() commits every tool handler first, then renders a thumbnail,
      // which needs a real raster; commit the handler directly.
      controller.extensions.toolHandlers[EditorTool.text]!.commitPending();
      await tester.pump();
      expect(content().texts.single.text, 'unsaved');
    });

    testWidgets('undo while editing drops the draft instead of corrupting it',
        (tester) async {
      await pumpEditor(tester);
      addExisting();
      await selectText(tester);
      await tapAt(tester, onPage(tester, 150, 205));
      controller.undo(); // removes the box that is being edited
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(content().texts, isEmpty);
    });
  });

  group('image tool', () {
    Future<void> insert(WidgetTester tester) async {
      controller.selectTool(EditorTool.image);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('image-insert')));
      for (var i = 0; i < 100 && content().images.isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    testWidgets('inserts a picked picture centred at 60% page width',
        (tester) async {
      await tester.runAsync(() async => pickedBytes = await solidPng(40, 20));
      await pumpEditor(tester);
      await insert(tester);

      expect(content().images, hasLength(1));
      final img = content().images.single;
      expect(img.width, closeTo(595 * 0.6, 0.01));
      expect(img.height, closeTo(595 * 0.3, 0.01));
      expect(img.x + img.width / 2, closeTo(297.5, 0.01));
      expect(img.pixelWidth, 40);
      expect(repo.assetBytes(meta.id, img.asset), isNotNull);
      expect(controller.undoLabel, 'Add picture');
      controller.undo();
      expect(content().images, isEmpty);
    });

    testWidgets('cancelling the picker adds nothing', (tester) async {
      await pumpEditor(tester);
      controller.selectTool(EditorTool.image);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('image-insert')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(content().images, isEmpty);
    });

    testWidgets('a bad file shows a message and adds nothing', (tester) async {
      pickedBytes = Uint8List.fromList(List.filled(40, 3));
      await pumpEditor(tester);
      controller.selectTool(EditorTool.image);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('image-insert')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(find.textContaining("isn't a picture"), findsOneWidget);
      expect(content().images, isEmpty);
    });

    testWidgets('drag moves, corner resizes, delete removes; each is one step',
        (tester) async {
      await tester.runAsync(() async => pickedBytes = await solidPng(40, 20));
      await pumpEditor(tester);
      await insert(tester);
      final start = content().images.single;

      // Move by dragging the body.
      var g = await tester.startGesture(onPage(tester, 297, 421),
          kind: PointerDeviceKind.stylus);
      for (var i = 1; i <= 5; i++) {
        await g.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await g.up();
      await tester.pump();
      var img = content().images.single;
      expect(img.y, greaterThan(start.y));
      expect(img.width, start.width);
      expect(controller.undoLabel, 'Move picture');

      // Resize from the bottom-right corner.
      g = await tester.startGesture(onPage(tester, img.x + img.width, img.y + img.height),
          kind: PointerDeviceKind.stylus);
      for (var i = 1; i <= 5; i++) {
        await g.moveBy(const Offset(-15, 0));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await g.up();
      await tester.pump();
      final resized = content().images.single;
      expect(resized.width, lessThan(img.width));
      expect(resized.width / resized.height, closeTo(2, 0.01));
      expect(resized.x, closeTo(img.x, 1e-6));
      expect(controller.undoLabel, 'Resize picture');
      img = resized;

      await tester.tap(find.byKey(const ValueKey('image-delete')));
      await tester.pump();
      expect(content().images, isEmpty);
      controller.undo();
      expect(content().images.single.id, img.id);
    });
  });

  group('layers', () {
    PagePaintContext contextFor(PageContent c, {bool thumb = false}) =>
        PagePaintContext(
          notebookId: 'nb',
          pageId: 'p',
          pageIndex: 0,
          page: PageMeta(id: 'p', width: 100, height: 100, paper: const Paper()),
          content: c,
          forThumbnail: thumb,
        );

    Future<ui.Image> render(void Function(ui.Canvas) paint) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 100, 100),
          ui.Paint()..color = const ui.Color(0xFFFFFFFF));
      paint(canvas);
      return recorder.endRecording().toImage(100, 100);
    }

    Future<bool> hasInk(ui.Image image) async {
      final data = (await image.toByteData())!.buffer.asUint8List();
      for (var i = 0; i < data.length; i += 4) {
        if (data[i] != 255 || data[i + 1] != 255 || data[i + 2] != 255) {
          return true;
        }
      }
      return false;
    }

    testWidgets('text layer paints text and backgrounds, skips the hidden one',
        (tester) async {
      await tester.runAsync(() async {
        final c = PageContent(texts: [
          const TextItem(
              id: 'a', x: 5, y: 5, width: 80, height: 30, text: 'Hi',
              fontSize: 20, color: 0xFF000000),
        ]);
        final shown = await render(
            (canvas) => TextLayerPainter().paint(canvas, contextFor(c)));
        expect(await hasInk(shown), isTrue);

        final hidden = await render((canvas) =>
            TextLayerPainter(hiddenId: (_) => 'a').paint(canvas, contextFor(c)));
        expect(await hasInk(hidden), isFalse);
        // Thumbnails always show the committed state.
        final thumb = await render((canvas) => TextLayerPainter(hiddenId: (_) => 'a')
            .paint(canvas, contextFor(c, thumb: true)));
        expect(await hasInk(thumb), isTrue);

        final bg = await render((canvas) => TextLayerPainter().paint(
            canvas,
            contextFor(PageContent(texts: [
              const TextItem(
                  id: 'b', x: 10, y: 10, width: 40, height: 20,
                  background: 0xFFFFF59D),
            ]))));
        expect(await hasInk(bg), isTrue);
      });
    });

    testWidgets('image layer decodes on prepare and paints the picture',
        (tester) async {
      await tester.runAsync(() async {
        final png = await solidPng(8, 8);
        final ready = <String>[];
        final layer = ImageLayerPainter(
          loadBytes: (nb, asset) async => asset == 'a.png' ? png : null,
          onReady: ready.add,
        );
        final c = PageContent(images: [
          const ImageItem(id: 'i', x: 10, y: 10, width: 50, height: 50, asset: 'a.png'),
        ]);
        final ctx = contextFor(c, thumb: true);
        await layer.prepare(ctx);
        final image = await render((canvas) => layer.paint(canvas, ctx));
        final data = (await image.toByteData())!.buffer.asUint8List();
        final at = (30 * 100 + 30) * 4; // inside the picture
        expect([data[at], data[at + 1], data[at + 2]], [0xCC, 0, 0]);
        layer.dispose();
      });
    });

    testWidgets('image layer asks for a repaint once a picture has decoded',
        (tester) async {
      await tester.runAsync(() async {
        final png = await solidPng(8, 8);
        final ready = <String>[];
        final layer = ImageLayerPainter(
          loadBytes: (nb, asset) async => png,
          onReady: ready.add,
        );
        final c = PageContent(images: [
          const ImageItem(id: 'i', x: 10, y: 10, width: 50, height: 50, asset: 'a.png'),
        ]);
        // Not decoded yet: a placeholder is drawn and a load is started.
        await render((canvas) => layer.paint(canvas, contextFor(c)));
        for (var i = 0; i < 50 && ready.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(ready, ['p']);
        layer.dispose();
      });
    });

    testWidgets('a missing picture file draws a placeholder, not a crash',
        (tester) async {
      await tester.runAsync(() async {
        final layer = ImageLayerPainter(
            loadBytes: (nb, asset) async => null, onReady: (_) {});
        final c = PageContent(images: [
          const ImageItem(id: 'i', x: 10, y: 10, width: 50, height: 50, asset: 'x.png'),
        ]);
        final ctx = contextFor(c, thumb: true);
        await layer.prepare(ctx);
        final image = await render((canvas) => layer.paint(canvas, ctx));
        expect(await hasInk(image), isTrue);
        layer.dispose();
      });
    });
  });
}
