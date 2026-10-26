import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'pdf_export_request.dart';

/// Dart side of the Kotlin PdfBox exporter (`PdfExportPlugin.kt`).
///
/// Protocol on the `neatink/pdf_export` channel. Pages are streamed one at
/// a time, so a long notebook never has to sit in memory (or in one
/// platform message) all at once:
///
/// | Dart → Kotlin | arguments                                      | reply      |
/// |---------------|------------------------------------------------|------------|
/// | `begin`       | outputPath, sourcePdfPath?, title?, pageCount  | session id |
/// | `addPage`     | session, index, page ([ExportPage.toMap])      | null       |
/// | `finish`      | session                                        | outputPath |
/// | `cancel`      | session                                        | null       |
///
/// Kotlin → Dart: `progress` {session, done, total} after each drawn page.
///
/// Kotlin runs every call on one background thread, in order, so the UI
/// never blocks; the output file is written atomically by `finish`.
class PdfExporter {
  /// Use [instance] in the app. Tests pass a channel whose platform side is
  /// mocked.
  PdfExporter({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onPlatformCall);
  }

  /// The app-wide exporter. Only one object may listen to the channel's
  /// `progress` calls, so always go through this instance.
  static final PdfExporter instance = PdfExporter();

  static const String channelName = 'neatink/pdf_export';

  final MethodChannel _channel;

  /// Progress listeners of running exports, by session id.
  final Map<int, void Function(int done, int total)> _progress = {};

  /// Exports [request] to `request.outputPath` and returns that path.
  ///
  /// [onProgress] reports pages drawn so far. Throws [PdfExportException]
  /// on failure and [PdfExportCancelledException] when [cancel] fires.
  Future<String> export(
    ExportRequest request, {
    void Function(int done, int total)? onProgress,
    PdfExportCancelToken? cancel,
  }) =>
      exportPages(
        outputPath: request.outputPath,
        sourcePdfPath: request.sourcePdfPath,
        title: request.title,
        pageCount: request.pages.length,
        pageAt: (i) async => request.pages[i],
        onProgress: onProgress,
        cancel: cancel,
      );

  /// Exports [pageCount] pages produced on demand by [pageAt] (see
  /// `ExportBuilder.buildPage`), and returns [outputPath].
  ///
  /// While Kotlin draws page i, page i + 1 is being built in Dart, so at
  /// most two pages are held in memory.
  Future<String> exportPages({
    required String outputPath,
    String? sourcePdfPath,
    String? title,
    required int pageCount,
    required Future<ExportPage> Function(int index) pageAt,
    void Function(int done, int total)? onProgress,
    PdfExportCancelToken? cancel,
  }) async {
    if (pageCount <= 0) {
      throw const PdfExportException('empty', 'There are no pages to export.');
    }
    cancel?._throwIfCancelled();

    final session = await _call<int>('begin', {
      'outputPath': outputPath,
      'sourcePdfPath': sourcePdfPath,
      'title': title,
      'pageCount': pageCount,
    });
    var reported = 0;
    void report(int done) {
      // Progress arrives both from Kotlin's `progress` calls and from
      // `addPage` replies; only ever move forward.
      if (done <= reported) return;
      reported = done;
      onProgress?.call(done, pageCount);
    }

    _progress[session] = (done, _) => report(done);
    var finished = false;
    try {
      onProgress?.call(0, pageCount);
      Future<void>? drawing;
      for (var i = 0; i < pageCount; i++) {
        final page = await pageAt(i);
        await drawing;
        cancel?._throwIfCancelled();
        final index = i;
        drawing = _call<void>('addPage', {
          'session': session,
          'index': index,
          'page': page.toMap(),
        }).then((_) => report(index + 1));
      }
      await drawing;
      cancel?._throwIfCancelled();
      final path = await _call<String>('finish', {'session': session});
      finished = true;
      return path;
    } finally {
      _progress.remove(session);
      if (!finished) {
        // Frees the native document and deletes the partial file. Errors
        // here would only hide the original failure.
        try {
          await _channel.invokeMethod<void>('cancel', {'session': session});
        } catch (e) {
          debugPrint('NeatInk: cancelling PDF export failed: $e');
        }
      }
    }
  }

  Future<T> _call<T>(String method, Map<String, Object?> args) async {
    try {
      final result = await _channel.invokeMethod<T>(method, args);
      if (result == null && null is! T) {
        throw PdfExportException(
            'protocol', 'The PDF exporter returned no result for $method.');
      }
      return result as T;
    } on PlatformException catch (e) {
      throw PdfExportException(e.code, e.message ?? e.code);
    } on MissingPluginException {
      throw const PdfExportException(
          'unavailable', 'PDF export is not available on this device.');
    }
  }

  Future<Object?> _onPlatformCall(MethodCall call) async {
    if (call.method != 'progress') return null;
    final args = call.arguments;
    if (args is! Map) return null;
    final session = args['session'];
    final done = args['done'];
    final total = args['total'];
    if (session is int && done is int && total is int) {
      _progress[session]?.call(done, total);
    }
    return null;
  }
}

/// Export failed. [code] identifies the cause (set by the Kotlin side, see
/// `PdfExportPlugin.kt`); [userMessage] can be shown as is.
class PdfExportException implements Exception {
  const PdfExportException(this.code, this.message);

  final String code;

  /// Technical detail, for logs.
  final String message;

  /// A short explanation for the user.
  String get userMessage => switch (code) {
        'source_missing' =>
          "This notebook's original PDF file is missing, so it can't be "
              'exported.',
        'source_unreadable' =>
          "This notebook's original PDF could not be read. It may be "
              'damaged.',
        'out_of_memory' =>
          'The device ran out of memory while exporting. Close other apps '
              'and try again.',
        'write_failed' =>
          'The PDF could not be written. Check that the device has enough '
              'free storage.',
        'unavailable' => 'PDF export is not available on this device.',
        'empty' => 'There are no pages to export.',
        _ => 'The PDF could not be exported.',
      };

  @override
  String toString() => 'PdfExportException($code): $message';
}

/// The export was cancelled through its [PdfExportCancelToken].
class PdfExportCancelledException implements Exception {
  const PdfExportCancelledException();

  @override
  String toString() => 'PdfExportCancelledException';
}

/// Lets the UI stop a running export (e.g. a Cancel button next to the
/// progress bar). The export stops after the page being drawn and throws
/// [PdfExportCancelledException]; no file is left behind.
class PdfExportCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void _throwIfCancelled() {
    if (_cancelled) throw const PdfExportCancelledException();
  }
}

// ---------------------------------------------------------------------------
// Delivery
// ---------------------------------------------------------------------------

/// Longest file name (without extension) [safeFileName] produces.
const int maxExportFileNameLength = 80;

/// A file name for [title] that every file system and share target accepts:
/// characters that are reserved on common file systems (`\ / : * ? " < > |`)
/// and control characters become spaces, whitespace is collapsed, leading
/// and trailing dots/spaces are removed and the result is shortened to
/// [maxExportFileNameLength] characters. Falls back to "Notebook".
///
/// [extension] (with or without the dot) is appended; pass '' for none.
String safeFileName(String title, {String extension = 'pdf'}) {
  final cleaned = String.fromCharCodes(title.runes.map(
          (r) => r < 0x20 || r == 0x7F || _reservedFileNameRunes.contains(r)
              ? 0x20
              : r))
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[ .]+|[ .]+$'), '');
  var base = cleaned.isEmpty ? 'Notebook' : cleaned;
  if (base.runes.length > maxExportFileNameLength) {
    base = String.fromCharCodes(base.runes.take(maxExportFileNameLength))
        .replaceAll(RegExp(r'[ .]+$'), '');
  }
  final ext = extension.startsWith('.') ? extension.substring(1) : extension;
  return ext.isEmpty ? base : '$base.$ext';
}

const Set<int> _reservedFileNameRunes = {
  0x5C, // \
  0x2F, // /
  0x3A, // :
  0x2A, // *
  0x3F, // ?
  0x22, // "
  0x3C, // <
  0x3E, // >
  0x7C, // |
};

/// Lets the user pick where to save the exported PDF at [pdfPath], with
/// Android's system "Save to" dialog (Storage Access Framework, so no
/// storage permission is needed). Returns true when it was saved, false
/// when the user cancelled.
///
/// The dialog sends the app to the background: callers that use the app
/// lock should suspend it around this call.
Future<bool> savePdfToUserLocation(
    String pdfPath, String suggestedFileName) async {
  final bytes = await File(pdfPath).readAsBytes();
  final uri = await FilePicker.saveFile(
    fileName: suggestedFileName,
    bytes: bytes,
    mimeType: 'application/pdf',
    dialogTitle: 'Save PDF',
  );
  return uri != null;
}

/// Opens the system share sheet for the exported PDF at [pdfPath].
/// Returns false only when the user dismissed the sheet.
///
/// Like [savePdfToUserLocation], this leaves the app while the sheet is
/// open.
Future<bool> sharePdf(String pdfPath, String subject,
    {Rect? sharePositionOrigin}) async {
  final result = await SharePlus.instance.share(ShareParams(
    files: [XFile(pdfPath, mimeType: 'application/pdf')],
    subject: subject,
    title: subject,
    sharePositionOrigin: sharePositionOrigin,
  ));
  return result.status != ShareResultStatus.dismissed;
}

/// Deletes files in [dir] last modified more than [maxAge] ago, so old
/// exports do not pile up in the cache. Never throws.
Future<void> deleteStaleExports(Directory dir,
    {Duration maxAge = const Duration(hours: 1)}) async {
  try {
    if (!dir.existsSync()) return;
    final cutoff = DateTime.now().subtract(maxAge);
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      if (entity.lastModifiedSync().isBefore(cutoff)) {
        entity.deleteSync();
      }
    }
  } catch (e) {
    debugPrint('NeatInk: cleaning old exports failed: $e');
  }
}

/// Percentage for a progress label, e.g. "Exporting… 40%".
int exportPercent(int done, int total) =>
    total <= 0 ? 0 : (100 * math.min(done, total) / total).round();
