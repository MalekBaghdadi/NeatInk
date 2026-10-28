import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../pdf/export_builder.dart';
import '../../../../pdf/pdf_exporter.dart';
import '../../editor_controller.dart';
import 'export_service.dart';

/// The editor's "Export PDF" action: saves pending edits, builds the PDF
/// behind a progress dialog (with Cancel), then offers to save it to a
/// place the user picks or to share it.
Future<void> runPdfExportFlow(
  BuildContext context,
  EditorController controller,
  PdfExportService service,
) async {
  if (!controller.isReady) return;
  // Commit an unfinished stroke or text edit and write the notebook, so the
  // PDF matches what is on screen.
  await controller.close();
  if (!context.mounted) return;

  final doc = controller.doc;
  final builder = ExportBuilder(
    doc: doc,
    repo: controller.repository,
    exportPaperLines: controller.settings.exportPaperLines,
  );
  final fileName = safeFileName(doc.meta.title);
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.maybeOf(context);

  final cancel = PdfExportCancelToken();
  final progress =
      ValueNotifier<ExportProgress>(ExportProgress(0, builder.pageCount));
  final cancelling = ValueNotifier<bool>(false);
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => ExportProgressDialog(
      progress: progress,
      cancelling: cancelling,
      onCancel: () {
        cancelling.value = true;
        cancel.cancel();
      },
    ),
  ));

  String? exported;
  String? failure;
  try {
    final out = await service.prepareOutputPath(fileName);
    exported = await service.export(
      builder,
      outputPath: out,
      onProgress: (done, total) => progress.value = ExportProgress(done, total),
      cancel: cancel,
    );
  } on PdfExportCancelledException {
    exported = null;
  } on PdfExportException catch (e) {
    debugPrint('NeatInk: PDF export failed: ${e.code}: ${e.message}');
    failure = e.userMessage;
  } catch (e, st) {
    debugPrint('NeatInk: PDF export failed: $e\n$st');
    failure = 'The PDF could not be exported.';
  } finally {
    if (navigator.mounted) navigator.pop(); // The progress dialog.
    progress.dispose();
    cancelling.dispose();
  }

  if (failure != null) {
    messenger?.showSnackBar(SnackBar(content: Text(failure)));
    return;
  }
  final path = exported;
  if (path == null) return;
  if (!context.mounted) {
    await service.discard(path);
    return;
  }
  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (_) => ExportResultDialog(
      service: service,
      path: path,
      fileName: fileName,
      subject: doc.meta.title,
      pageCount: builder.pageCount,
    ),
  );
  await service.discard(path);
}

/// Pages drawn so far out of the total.
class ExportProgress {
  const ExportProgress(this.done, this.total);

  final int done;
  final int total;

  /// 0..1, or null when the total is unknown.
  double? get fraction => total <= 0 ? null : (done / total).clamp(0.0, 1.0);
}

class ExportProgressDialog extends StatelessWidget {
  const ExportProgressDialog({
    super.key,
    required this.progress,
    required this.cancelling,
    required this.onCancel,
  });

  final ValueListenable<ExportProgress> progress;
  final ValueListenable<bool> cancelling;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Exporting PDF'),
        content: ValueListenableBuilder<ExportProgress>(
          valueListenable: progress,
          builder: (context, p, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                  key: const ValueKey('export-progress'), value: p.fraction),
              const SizedBox(height: 12),
              Text(
                'Page ${p.done} of ${p.total} (${exportPercent(p.done, p.total)}%)',
                key: const ValueKey('export-progress-label'),
              ),
            ],
          ),
        ),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: cancelling,
            builder: (context, busy, _) => TextButton(
              key: const ValueKey('export-cancel'),
              onPressed: busy ? null : onCancel,
              child: Text(busy ? 'Cancelling…' : 'Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the PDF is ready: save it where the user wants, or share it.
class ExportResultDialog extends StatefulWidget {
  const ExportResultDialog({
    super.key,
    required this.service,
    required this.path,
    required this.fileName,
    required this.subject,
    required this.pageCount,
  });

  final PdfExportService service;
  final String path;
  final String fileName;
  final String subject;
  final int pageCount;

  @override
  State<ExportResultDialog> createState() => _ExportResultDialogState();
}

class _ExportResultDialogState extends State<ExportResultDialog> {
  bool _busy = false;
  String? _status;

  Future<void> _run(Future<bool> Function() action, String done) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    String? status;
    try {
      status = await action() ? done : null;
    } catch (_) {
      status = 'That did not work. Please try again.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages =
        widget.pageCount == 1 ? '1 page' : '${widget.pageCount} pages';
    return AlertDialog(
      title: const Text('PDF ready'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.fileName} ($pages)'),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(_status!, key: const ValueKey('export-status')),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('export-save'),
          onPressed: _busy
              ? null
              : () => _run(
                  () => widget.service.save(widget.path, widget.fileName),
                  'Saved.'),
          child: const Text('Save to device'),
        ),
        TextButton(
          key: const ValueKey('export-share'),
          onPressed: _busy
              ? null
              : () => _run(
                  () => widget.service.share(widget.path, widget.subject),
                  'Shared.'),
          child: const Text('Share'),
        ),
        FilledButton(
          key: const ValueKey('export-close'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
