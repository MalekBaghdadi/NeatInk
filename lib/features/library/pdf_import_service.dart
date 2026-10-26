import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../document/notebook_meta.dart';
import '../../pdf/pdf_import.dart';
import '../../storage/notebook_repository.dart';
import '../lock/auto_lock_suspension.dart';
import 'library_naming.dart';

/// A PDF the user picked, as a readable local file.
class PickedPdf {
  const PickedPdf({
    required this.path,
    required this.name,
    this.isTemporaryCopy = false,
  });

  /// Local path of the file (on Android, the picker's cached copy).
  final String path;

  /// File name as shown in the picker, e.g. "Lecture 3.pdf".
  final String name;

  /// True when [path] is a copy this service made in the system temp
  /// folder; it is deleted once the import finishes.
  final bool isTemporaryCopy;

  /// Notebook title derived from the file name ("Lecture 3").
  String get suggestedTitle =>
      cleanName(p.basenameWithoutExtension(name)) ?? 'PDF';
}

/// Picks a PDF with the system file picker and turns it into a notebook.
///
/// Behind [pdfImportServiceProvider] so widget tests can replace the
/// platform picker and the PDF parser.
class PdfImportService {
  const PdfImportService();

  /// Shows the system picker filtered to PDFs. Returns null when the user
  /// cancels. The app lock is relaxed while the picker is open.
  ///
  /// The Android picker normally hands back a local copy in its cache. When
  /// it only gives a content URI, the bytes are streamed into a temporary
  /// file so the importer always gets a real path.
  Future<PickedPdf?> pickPdf() async {
    final file = await AutoLockSuspension.during<PlatformFile?>(
      () => FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      ),
    );
    if (file == null) return null;
    final path = file.path;
    if (path != null) return PickedPdf(path: path, name: file.name);
    return PickedPdf(
      path: await _copyToTemp(file),
      name: file.name,
      isTemporaryCopy: true,
    );
  }

  /// Creates a PDF-backed notebook from [pdf] in [folderId].
  /// Throws [PdfImportException] with a user-facing message on failure.
  Future<NotebookMeta> importPdf(NotebookRepository repo, PickedPdf pdf,
      {String? folderId}) async {
    try {
      return await importPdfNotebook(repo, pdf.path,
          title: pdf.suggestedTitle, folderId: folderId);
    } finally {
      await _cleanUp(pdf);
    }
  }

  /// Streams [file] into a fresh temp folder (never into memory as a whole:
  /// PDFs can be large) and returns the new file's path.
  Future<String> _copyToTemp(PlatformFile file) async {
    final dir = await Directory.systemTemp.createTemp('neatink_import_');
    final base = p.basename(file.name).trim();
    final target = File(p.join(dir.path, base.isEmpty ? 'import.pdf' : base));
    final sink = target.openWrite();
    try {
      await sink.addStream(file.readAsByteStream());
    } finally {
      await sink.close();
    }
    return target.path;
  }

  /// The notebook keeps its own copy of the PDF, so the picker's cached copy
  /// (and any temp copy of ours) can go. Failing to clean up is harmless:
  /// Android clears app caches on its own.
  Future<void> _cleanUp(PickedPdf pdf) async {
    try {
      if (pdf.isTemporaryCopy) {
        await File(pdf.path).parent.delete(recursive: true);
      }
      await FilePicker.clearTemporaryFiles();
    } catch (e) {
      debugPrint('NeatInk: could not clear picker cache: $e');
    }
  }
}

final pdfImportServiceProvider =
    Provider<PdfImportService>((ref) => const PdfImportService());
