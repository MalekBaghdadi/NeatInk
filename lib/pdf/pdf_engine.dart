import 'dart:ui' as ui;

import '../storage/notebook_repository.dart' show PdfPageSize;

/// The small surface of a PDF engine the app needs: open a file, read page
/// sizes and text, render pages to images.
///
/// The app uses pdfrx (PDFium) through [PdfrxEngine] in `pdfrx_engine.dart`;
/// that is the only file that talks to pdfrx. Everything else depends on
/// this interface, so it can be tested with fakes (PDFium is a native
/// library that unit tests cannot load).
abstract interface class PdfEngine {
  /// Opens the PDF at [path].
  ///
  /// Throws [PdfPasswordRequiredException] when the file needs a password
  /// and [PdfOpenException] when it cannot be read as a PDF.
  Future<PdfEngineDocument> open(String path);
}

/// An open PDF. Call [close] when done; it releases native memory.
abstract interface class PdfEngineDocument {
  /// Page count.
  int get pageCount;

  /// Each page's size in points as displayed: after /Rotate, clipped to the
  /// CropBox.
  List<PdfPageSize> get pageSizes;

  /// Plain text of the page at [pageIndex] (0-based) in reading order.
  Future<String> extractText(int pageIndex);

  /// Renders [region] of the page at [pageIndex] on a white background.
  /// Returns null when [cancel] fired before the render finished.
  Future<ui.Image?> render(int pageIndex, PdfRenderRegion region,
      {PdfRenderCancelToken? cancel});

  Future<void> close();
}

/// What part of a page to render, in pixels.
///
/// The whole page is rendered at [fullWidth] × [fullHeight] pixels, and the
/// output image is the [width] × [height] window of it whose top-left corner
/// is at ([x], [y]). A full-page render has x = y = 0 and width/height equal
/// to the full size.
class PdfRenderRegion {
  const PdfRenderRegion({
    required this.fullWidth,
    required this.fullHeight,
    this.x = 0,
    this.y = 0,
    int? width,
    int? height,
  })  : width = width ?? fullWidth,
        height = height ?? fullHeight;

  final int fullWidth;
  final int fullHeight;
  final int x;
  final int y;
  final int width;
  final int height;

  bool get isFullPage =>
      x == 0 && y == 0 && width == fullWidth && height == fullHeight;

  /// Bytes of the decoded RGBA image.
  int get byteSize => width * height * 4;

  @override
  bool operator ==(Object other) =>
      other is PdfRenderRegion &&
      other.fullWidth == fullWidth &&
      other.fullHeight == fullHeight &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(fullWidth, fullHeight, x, y, width, height);

  @override
  String toString() =>
      'PdfRenderRegion(${fullWidth}x$fullHeight @ $x,$y ${width}x$height)';
}

/// Lets the caller abandon a render that is no longer needed.
class PdfRenderCancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
    _listeners.clear();
  }

  /// Runs [listener] when [cancel] is called (immediately if it already
  /// was).
  void onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }
}

/// The PDF is encrypted with a user password.
class PdfPasswordRequiredException implements Exception {
  const PdfPasswordRequiredException();

  @override
  String toString() => 'PdfPasswordRequiredException';
}

/// The file is missing, unreadable, or not a valid PDF.
class PdfOpenException implements Exception {
  const PdfOpenException(this.cause);

  final Object? cause;

  @override
  String toString() => 'PdfOpenException: $cause';
}
