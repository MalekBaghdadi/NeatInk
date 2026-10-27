import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/editor_integrations.dart';
import 'package:neatink/features/editor/editor_screen.dart';
import 'package:neatink/features/editor/integrations/pdf/export_flow.dart';
import 'package:neatink/features/editor/integrations/pdf/export_install.dart';
import 'package:neatink/features/editor/integrations/pdf/export_service.dart';
import 'package:neatink/pdf/export_builder.dart';
import 'package:neatink/pdf/pdf_exporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../fakes/in_memory_repository.dart';

class FakeExportService implements PdfExportService {
  final calls = <String>[];
  Completer<void>? gate;
  Object? exportError;
  bool saveResult = true;
  ExportBuilder? lastBuilder;

  @override
  Future<String> prepareOutputPath(String fileName) async {
    calls.add('prepare:$fileName');
    return '/tmp/$fileName';
  }

  @override
  Future<String> export(
    ExportBuilder builder, {
    required String outputPath,
    required void Function(int done, int total) onProgress,
    required PdfExportCancelToken cancel,
  }) async {
    lastBuilder = builder;
    calls.add('export');
    onProgress(0, builder.pageCount);
    onProgress(1, builder.pageCount);
    if (gate != null) {
      await gate!.future;
      if (cancel.isCancelled) throw const PdfExportCancelledException();
    }
    final e = exportError;
    if (e != null) throw e;
    onProgress(builder.pageCount, builder.pageCount);
    return outputPath;
  }

  @override
  Future<bool> save(String path, String suggestedFileName) async {
    calls.add('save:$suggestedFileName');
    return saveResult;
  }

  @override
  Future<bool> share(String path, String subject, {Rect? origin}) async {
    calls.add('share:$subject');
    return true;
  }

  @override
  Future<void> discard(String path) async => calls.add('discard');
}

void main() {
  late FakeExportService service;

  Future<void> openEditor(WidgetTester tester, {String title = 'My: notes'}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = InMemoryNotebookRepository();
    final meta = await repo.createNotebook(
        title: title, paper: const Paper(), pageCount: 3);
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notebookRepositoryProvider.overrideWithValue(repo),
      pdfExportServiceProvider.overrideWithValue(service),
      editorIntegrationsProvider.overrideWithValue([installPdfExport]),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: EditorScreen(notebookId: meta.id)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapExport(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('editor-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export PDF'));
    await tester.pump();
  }

  setUp(() => service = FakeExportService());

  testWidgets('menu offers Export PDF and the flow ends in a result dialog',
      (tester) async {
    await openEditor(tester);
    await tapExport(tester);
    await tester.pumpAndSettle();

    expect(find.text('PDF ready'), findsOneWidget);
    expect(find.textContaining('My notes.pdf (3 pages)'), findsOneWidget);
    expect(service.calls.take(2), ['prepare:My notes.pdf', 'export']);
    expect(service.lastBuilder!.pageCount, 3);
    expect(service.lastBuilder!.exportPaperLines, isTrue);
  });

  testWidgets('save and share go through the service; Done discards the file',
      (tester) async {
    await openEditor(tester);
    await tapExport(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('export-save')));
    await tester.pumpAndSettle();
    expect(find.text('Saved.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('export-share')));
    await tester.pumpAndSettle();
    expect(service.calls, contains('share:My: notes'));

    service.saveResult = false;
    await tester.tap(find.byKey(const ValueKey('export-save')));
    await tester.pumpAndSettle();
    expect(find.text('Saved.'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('export-close')));
    await tester.pumpAndSettle();
    expect(find.text('PDF ready'), findsNothing);
    expect(service.calls.last, 'discard');
  });

  testWidgets('shows progress while exporting and Cancel stops it',
      (tester) async {
    service.gate = Completer<void>();
    await openEditor(tester);
    await tapExport(tester);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Exporting PDF'), findsOneWidget);
    expect(find.textContaining('Page 1 of 3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('export-cancel')));
    await tester.pump();
    expect(find.text('Cancelling…'), findsOneWidget);
    service.gate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Exporting PDF'), findsNothing);
    expect(find.text('PDF ready'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a failed export shows the user message', (tester) async {
    service.exportError = const PdfExportException('write_failed', 'disk');
    await openEditor(tester);
    await tapExport(tester);
    await tester.pumpAndSettle();

    expect(find.text('Exporting PDF'), findsNothing);
    expect(find.text('PDF ready'), findsNothing);
    expect(find.textContaining('free storage'), findsOneWidget);
  });

  testWidgets('an unexpected error shows a generic message', (tester) async {
    service.exportError = StateError('boom');
    await openEditor(tester);
    await tapExport(tester);
    await tester.pumpAndSettle();

    expect(find.text('The PDF could not be exported.'), findsOneWidget);
  });

  test('ExportProgress fraction', () {
    expect(const ExportProgress(1, 4).fraction, 0.25);
    expect(const ExportProgress(0, 0).fraction, isNull);
    expect(const ExportProgress(9, 4).fraction, 1.0);
  });
}
