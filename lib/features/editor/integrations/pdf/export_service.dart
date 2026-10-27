import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../pdf/export_builder.dart';
import '../../../../pdf/pdf_exporter.dart';
import '../../../lock/auto_lock_suspension.dart';

/// Everything the export UI needs from the outside world (the Kotlin
/// exporter, the system "Save to" dialog, the share sheet, the cache
/// folder), behind one interface so the flow can be tested with a fake.
abstract interface class PdfExportService {
  /// A fresh path for an export called [fileName] in the cache folder
  /// (old exports are cleaned up). The file is not created yet.
  Future<String> prepareOutputPath(String fileName);

  /// Builds and writes the PDF for [builder] to [outputPath], reporting
  /// progress as pages are done. Returns the written path. Throws
  /// [PdfExportException], or [PdfExportCancelledException] after [cancel].
  Future<String> export(
    ExportBuilder builder, {
    required String outputPath,
    required void Function(int done, int total) onProgress,
    required PdfExportCancelToken cancel,
  });

  /// Lets the user choose where to save [path]. False when cancelled.
  Future<bool> save(String path, String suggestedFileName);

  /// Opens the share sheet for [path]. False when dismissed.
  Future<bool> share(String path, String subject, {Rect? origin});

  /// Removes the temporary export. Never throws.
  Future<void> discard(String path);
}

/// The real service: PdfBox export through the `neatink/pdf_export`
/// channel, Storage Access Framework saving and the Android share sheet.
/// No storage or network permission is involved.
class DefaultPdfExportService implements PdfExportService {
  const DefaultPdfExportService();

  @override
  Future<String> prepareOutputPath(String fileName) async {
    final dir =
        Directory(p.join((await getTemporaryDirectory()).path, 'exports'));
    await dir.create(recursive: true);
    await deleteStaleExports(dir);
    return p.join(dir.path, fileName);
  }

  @override
  Future<String> export(
    ExportBuilder builder, {
    required String outputPath,
    required void Function(int done, int total) onProgress,
    required PdfExportCancelToken cancel,
  }) =>
      // Pages are built one at a time while the previous one is drawn, so
      // memory stays small even for long notebooks.
      PdfExporter.instance.exportPages(
        outputPath: outputPath,
        sourcePdfPath: builder.sourcePdfPath,
        title: builder.meta.title,
        pageCount: builder.pageCount,
        pageAt: builder.buildPage,
        onProgress: onProgress,
        cancel: cancel,
      );

  // The system dialogs send NeatInk to the background; keep the app lock
  // from engaging while the user is in them.
  @override
  Future<bool> save(String path, String suggestedFileName) =>
      AutoLockSuspension.during(
          () => savePdfToUserLocation(path, suggestedFileName));

  @override
  Future<bool> share(String path, String subject, {Rect? origin}) =>
      AutoLockSuspension.during(
          () => sharePdf(path, subject, sharePositionOrigin: origin));

  @override
  Future<void> discard(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// The service used by the editor's Export PDF action. Tests override it.
final pdfExportServiceProvider =
    Provider<PdfExportService>((ref) => const DefaultPdfExportService());
