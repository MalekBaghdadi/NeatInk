import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/canvas/document_view.dart';
import 'package:neatink/features/editor/editor_screen.dart';
import 'package:neatink/features/settings/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/in_memory_repository.dart';

/// Counts thumbnail writes and can be told to fail every page / meta save.
class _SpyRepository extends InMemoryNotebookRepository {
  int thumbnails = 0;
  bool failSaves = false;

  @override
  Future<void> saveThumbnail(String notebookId, Uint8List png) {
    thumbnails++;
    return super.saveThumbnail(notebookId, png);
  }

  @override
  Future<void> savePage(
      String notebookId, String pageId, PageContent content) {
    if (failSaves) throw StateError('disk full');
    return super.savePage(notebookId, pageId, content);
  }
}

void main() {
  late _SpyRepository repo;
  late SharedPreferences prefs;
  late NotebookMeta meta;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repo = _SpyRepository();
    meta = await repo.createNotebook(
      title: 'Physics',
      paper: const Paper(),
      pageCount: 2,
    );
  });

  /// Shows the editor inside a navigator so leaving can pop a route.
  Future<ProviderContainer> pumpEditor(
    WidgetTester tester, {
    String? notebookId,
    int? initialPageIndex,
  }) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notebookRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('open'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => EditorScreen(
                      notebookId: notebookId ?? meta.id,
                      initialPageIndex: initialPageIndex,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    return container;
  }

  /// Draws a diagonal line on the first page with a pointer of [kind].
  Future<void> drawLine(WidgetTester tester, PointerDeviceKind kind) async {
    final start =
        tester.getCenter(find.byType(DocumentView)) - const Offset(100, 100);
    final g = await tester.startGesture(start, kind: kind);
    for (var i = 1; i <= 8; i++) {
      await g.moveBy(const Offset(12, 10));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await g.up();
    await tester.pump();
  }

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<IconButton>(find.byKey(ValueKey(key))).onPressed != null;

  /// Flushes like the app going to the background does, including the
  /// thumbnail timeout.
  Future<void> pause(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    // A paused binding stops scheduling frames; resume so the UI keeps
    // updating like it does when the app comes back.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }

  Future<int> storedStrokes() async {
    final stored = (await repo.loadMeta(meta.id))!;
    final page = await repo.loadPage(meta.id, stored.pages.first.id);
    return page.strokes.length;
  }

  testWidgets('loads a notebook and shows its title and page count',
      (tester) async {
    await pumpEditor(tester);
    expect(find.text('Physics'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byType(DocumentView), findsOneWidget);
  });

  testWidgets('shows an error for a missing notebook', (tester) async {
    await pumpEditor(tester, notebookId: 'nope');
    expect(find.byKey(const ValueKey('editor-error')), findsOneWidget);
    expect(find.byType(DocumentView), findsNothing);
  });

  testWidgets('jumps to the initial page', (tester) async {
    await pumpEditor(tester, initialPageIndex: 1);
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('a stylus draws a stroke', (tester) async {
    await pumpEditor(tester);
    expect(enabled(tester, 'undo'), isFalse);
    await drawLine(tester, PointerDeviceKind.stylus);
    expect(enabled(tester, 'undo'), isTrue);
    await pause(tester);
    expect(await storedStrokes(), 1);
  });

  testWidgets('a finger does not draw unless finger drawing is on',
      (tester) async {
    final container = await pumpEditor(tester);
    await drawLine(tester, PointerDeviceKind.touch);
    expect(enabled(tester, 'undo'), isFalse);

    container
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(drawWithFinger: true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // palm window / fling
    await drawLine(tester, PointerDeviceKind.touch);
    expect(enabled(tester, 'undo'), isTrue);
  });

  testWidgets('undo and redo', (tester) async {
    await pumpEditor(tester);
    await drawLine(tester, PointerDeviceKind.stylus);
    expect(enabled(tester, 'redo'), isFalse);

    await tester.tap(find.byKey(const ValueKey('undo')));
    await tester.pump();
    expect(enabled(tester, 'undo'), isFalse);
    expect(enabled(tester, 'redo'), isTrue);
    await pause(tester);
    expect(await storedStrokes(), 0);

    await tester.tap(find.byKey(const ValueKey('redo')));
    await tester.pump();
    expect(enabled(tester, 'redo'), isFalse);
    expect(enabled(tester, 'undo'), isTrue);
    await pause(tester);
    expect(await storedStrokes(), 1);
  });

  testWidgets('adds a page at the end and deletes a page after confirming',
      (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byKey(const ValueKey('add-page')));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    await pause(tester);
    final added = (await repo.loadMeta(meta.id))!.pages;
    expect(added.length, 3);
    final newId = added.last.id;

    Future<void> openDelete() async {
      await tester.tap(find.byKey(const ValueKey('editor-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete page'));
      await tester.pumpAndSettle();
    }

    // Cancelling keeps the page.
    await openDelete();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining(' / 3'), findsOneWidget);

    // The current page (the new third one) is the one deleted.
    await openDelete();
    await tester.tap(find.byKey(const ValueKey('confirm-delete-page')));
    await tester.pumpAndSettle();
    expect(find.textContaining(' / 2'), findsOneWidget);
    await pause(tester);
    var pages = (await repo.loadMeta(meta.id))!.pages;
    expect(pages.length, 2);
    expect(pages.map((p) => p.id), isNot(contains(newId)));

    // Undo brings the page back.
    await tester.tap(find.byKey(const ValueKey('undo')));
    await tester.pumpAndSettle();
    expect(find.textContaining(' / 3'), findsOneWidget);
    await pause(tester);
    pages = (await repo.loadMeta(meta.id))!.pages;
    expect(pages.map((p) => p.id), contains(newId));
  });

  testWidgets('flushes ink when the app is paused, before the autosave delay',
      (tester) async {
    await pumpEditor(tester);
    await drawLine(tester, PointerDeviceKind.stylus);
    expect(await storedStrokes(), 0);
    await pause(tester);
    expect(await storedStrokes(), 1);
  });

  testWidgets('flushes ink when leaving the screen', (tester) async {
    await pumpEditor(tester);
    await drawLine(tester, PointerDeviceKind.stylus);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsNothing);
    expect(await storedStrokes(), 1);
  });

  testWidgets('refreshes the thumbnail when leaving', (tester) async {
    await pumpEditor(tester);
    await drawLine(tester, PointerDeviceKind.stylus);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    // Image rendering needs real time, not fake time.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsNothing);
    expect(repo.thumbnails, greaterThan(0));
  });

  testWidgets('asks to stay or leave when the final save fails',
      (tester) async {
    await pumpEditor(tester);
    await drawLine(tester, PointerDeviceKind.stylus);
    repo.failSaves = true;

    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't save"), findsOneWidget);

    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave anyway'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsNothing);
  });
}
