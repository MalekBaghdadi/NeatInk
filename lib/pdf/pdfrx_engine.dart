import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../storage/notebook_repository.dart' show PdfPageSize;
import 'pdf_engine.dart';

/// [PdfEngine] backed by pdfrx (PDFium). This is the only file that uses
/// the pdfrx API; keep it small, because it cannot be unit-tested.
class PdfrxEngine implements PdfEngine {
  const PdfrxEngine();

  static Future<void>? _initialization;

  /// pdfrx needs a one-time asynchronous setup (cache directory, PDFium
  /// bindings) before documents are opened outside its viewer widgets.
  /// Concurrent callers share one setup; a failed setup is retried by the
  /// next call.
  static Future<void> ensureInitialized() {
    return _initialization ??=
        pdfrx.pdfrxFlutterInitialize().catchError((Object e) {
      _initialization = null;
      throw e;
    });
  }

  @override
  Future<PdfEngineDocument> open(String path) async {
    try {
      await ensureInitialized();
    } catch (e) {
      throw PdfOpenException(e);
    }
    try {
      // No password provider: an encrypted file fails with
      // PdfPasswordException instead of prompting.
      final doc = await pdfrx.PdfDocument.openFile(path);
      return _PdfrxDocument(doc);
    } on pdfrx.PdfPasswordException {
      throw const PdfPasswordRequiredException();
    } catch (e) {
      throw PdfOpenException(e);
    }
  }
}

class _PdfrxDocument implements PdfEngineDocument {
  _PdfrxDocument(this._doc);

  final pdfrx.PdfDocument _doc;
  bool _closed = false;

  @override
  int get pageCount => _doc.pages.length;

  /// pdfrx reports each page's size from PDFium's FPDF_GetPageWidthF /
  /// HeightF: the CropBox (clipped to the MediaBox), with width and height
  /// swapped for /Rotate 90 and 270, i.e. the displayed size.
  @override
  List<PdfPageSize> get pageSizes => [
        for (final page in _doc.pages) PdfPageSize(page.width, page.height),
      ];

  @override
  Future<String> extractText(int pageIndex) async {
    final text = await _doc.pages[pageIndex].loadText();
    return text?.fullText ?? '';
  }

  @override
  Future<ui.Image?> render(int pageIndex, PdfRenderRegion region,
      {PdfRenderCancelToken? cancel}) async {
    if (_closed || (cancel?.isCancelled ?? false)) return null;
    final page = _doc.pages[pageIndex];
    final token = page.createCancellationToken();
    cancel?.onCancel(token.cancel);
    final image = await page.render(
      x: region.x,
      y: region.y,
      width: region.width,
      height: region.height,
      fullWidth: region.fullWidth.toDouble(),
      fullHeight: region.fullHeight.toDouble(),
      backgroundColor: 0xFFFFFFFF,
      cancellationToken: token,
    );
    if (image == null) return null;
    try {
      if (cancel?.isCancelled ?? false) return null;
      return await image.createImage();
    } finally {
      image.dispose();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _doc.dispose();
    } catch (e) {
      debugPrint('NeatInk: closing PDF failed: $e');
    }
  }
}
