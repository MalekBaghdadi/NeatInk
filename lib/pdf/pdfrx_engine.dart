import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Rect;
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
  Future<List<PdfWordBox>> words(int pageIndex) async {
    final page = _doc.pages[pageIndex];
    final text = await page.loadText();
    if (text == null) return const [];
    final chars = text.fullText;
    final rects = text.charRects;
    final out = <PdfWordBox>[];
    Rect? word;
    void flush() {
      final w = word;
      if (w != null) out.add((left: w.left, top: w.top, right: w.right, bottom: w.bottom));
      word = null;
    }

    for (var i = 0; i < chars.length && i < rects.length; i++) {
      if (chars[i].trim().isEmpty) {
        flush();
        continue;
      }
      // pdfrx maps PDF space (bottom-left origin, unrotated) to the page as
      // displayed, the same frame its renderer and text selection use.
      final r = rects[i].toRect(page: page);
      if (!r.isFinite || r.width <= 0 || r.height <= 0) continue;
      final w = word;
      // A word also ends where the next character jumps a gap or a line.
      if (w != null && (r.left - w.right > r.height || (r.center.dy - w.center.dy).abs() > 0.6 * r.height)) {
        flush();
      }
      word = word == null ? r : word!.expandToInclude(r);
    }
    flush();
    return out;
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
