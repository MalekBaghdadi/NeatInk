import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../document/notebook_meta.dart';
import '../document/pdf_margins.dart';
import '../storage/notebook_repository.dart';
import 'pdf_engine.dart';
import 'pdfrx_engine.dart';

/// Import failed. [message] is written for the user and can be shown as is.
class PdfImportException implements Exception {
  const PdfImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Title used when the file name gives nothing usable.
const String defaultPdfNotebookTitle = 'Imported PDF';

/// Creates a PDF-backed notebook from the PDF at [pdfPath].
///
/// * Reads every page's displayed size in points (after /Rotate, clipped to
///   the CropBox), so the app's page coordinates match the PDF exactly.
/// * [title] defaults to the file name without its extension.
/// * Copies the file into the notebook (via
///   [NotebookRepository.createPdfNotebook]) and then stores each page's
///   text for search. Text extraction is best effort: a page whose text
///   cannot be read is skipped and never fails the import.
/// * [onProgress] reports text extraction progress (pages done / total).
/// * [margins] adds lined writing space beside every page.
///
/// Throws [PdfImportException] with a user-facing message when the file is
/// missing, password-protected, damaged, empty, or cannot be stored.
Future<NotebookMeta> importPdfNotebook(
  NotebookRepository repo,
  String pdfPath, {
  String? title,
  String? folderId,
  PdfEngine engine = const PdfrxEngine(),
  void Function(int done, int total)? onProgress,
  PdfMargins margins = PdfMargins.none,
}) async {
  if (!File(pdfPath).existsSync()) {
    throw const PdfImportException(
        'The selected file could not be found. Please pick it again.');
  }

  final PdfEngineDocument doc;
  try {
    doc = await engine.open(pdfPath);
  } on PdfPasswordRequiredException {
    throw const PdfImportException(
        'This PDF is protected with a password. Remove the password (for '
        'example by printing it to a new PDF) and import it again.');
  } catch (e) {
    debugPrint('NeatInk: PDF open failed for $pdfPath: $e');
    throw const PdfImportException(
        'This file could not be opened. It may be damaged or not a PDF.');
  }

  try {
    final sizes = [for (final s in doc.pageSizes) sanitizePdfPageSize(s)];
    if (sizes.isEmpty) {
      throw const PdfImportException('This PDF has no pages.');
    }

    NotebookMeta meta;
    try {
      meta = await repo.createPdfNotebook(
        title: pdfNotebookTitle(pdfPath, title),
        sourcePdfPath: pdfPath,
        pageSizes: sizes,
        folderId: folderId,
      );
    } catch (e) {
      debugPrint('NeatInk: storing imported PDF failed: $e');
      throw const PdfImportException(
          'The PDF could not be copied into your library. Check that the '
          'device has enough free storage and try again.');
    }

    if (margins != PdfMargins.none) {
      final widened = meta.copyWith(
          pages: [for (final p in meta.pages) withPdfMargins(p, margins)]);
      try {
        await repo.saveMeta(widened);
        meta = widened;
      } catch (e) {
        // The notebook works without margins; they can be added later.
        debugPrint('NeatInk: saving PDF margins failed: $e');
      }
    }

    await _storePdfText(repo, meta, doc, onProgress);
    return meta;
  } finally {
    await doc.close();
  }
}

/// The notebook title for an imported file: [title] if it has content,
/// otherwise the file name without extension.
@visibleForTesting
String pdfNotebookTitle(String pdfPath, String? title) {
  final given = title?.trim() ?? '';
  if (given.isNotEmpty) return given;
  final name = p.basenameWithoutExtension(pdfPath).trim();
  return name.isEmpty ? defaultPdfNotebookTitle : name;
}

/// Replaces unusable page sizes (zero, negative, NaN) with A4 so a broken
/// page cannot break the editor's layout.
@visibleForTesting
PdfPageSize sanitizePdfPageSize(PdfPageSize s) {
  bool ok(double v) => v.isFinite && v >= 1;
  if (ok(s.width) && ok(s.height)) return s;
  return const PdfPageSize(a4WidthPt, a4HeightPt);
}

/// Extracts and saves the text of every page. Failures are logged and
/// skipped; the notebook is already created at this point.
Future<void> _storePdfText(
  NotebookRepository repo,
  NotebookMeta meta,
  PdfEngineDocument doc,
  void Function(int done, int total)? onProgress,
) async {
  final total = meta.pages.length;
  final textByPage = <String, String>{};
  onProgress?.call(0, total);
  for (var i = 0; i < total; i++) {
    final page = meta.pages[i];
    final index = page.pdfPageIndex ?? i;
    try {
      final text = normalizePdfText(await doc.extractText(index));
      if (text.isNotEmpty) textByPage[page.id] = text;
    } catch (e) {
      debugPrint('NeatInk: text extraction failed on page ${index + 1}: $e');
    }
    onProgress?.call(i + 1, total);
  }
  if (textByPage.isEmpty) return;
  try {
    await repo.savePdfText(meta.id, textByPage);
  } catch (e) {
    debugPrint('NeatInk: saving PDF text failed: $e');
  }
}

/// Cleans extracted text for search: unifies line breaks, drops control
/// characters PDFium emits for some fonts, collapses runs of spaces and
/// trims.
@visibleForTesting
String normalizePdfText(String text) {
  final unified = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final cleaned = String.fromCharCodes(unified.runes.where(_isTextRune));
  return cleaned
      .replaceAll(_horizontalSpaceRun, ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// False for code points that carry no text: C0 control characters other
/// than tab and line feed, and the noncharacters U+FFFE / U+FFFF that PDFium
/// emits for some broken font encodings.
bool _isTextRune(int rune) =>
    !((rune < 0x20 && rune != 0x09 && rune != 0x0A) ||
        rune == 0xFFFE ||
        rune == 0xFFFF);

/// Runs of spaces, tabs and no-break spaces (U+00A0).
final RegExp _horizontalSpaceRun = RegExp('[ \t${String.fromCharCode(0xA0)}]+');
