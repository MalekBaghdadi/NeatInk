import 'dart:isolate';
import 'dart:typed_data';

import '../document/page_content.dart';
import 'json_document_store.dart';

/// Encodes pages to JSON bytes, moving the work to a background isolate
/// for big pages so autosave never drops frames while the user writes.
///
/// Decoding big pages off the UI isolate is handled by
/// [JsonDocumentStore], which switches by file size.
abstract final class PageCodec {
  /// Pages with more strokes than this are encoded in the background
  /// (the brief's "~2,000 strokes").
  static const int backgroundStrokeThreshold = 2000;

  /// Pages whose JSON is estimated above this many bytes are encoded in the
  /// background, and files this big are decoded in the background.
  static const int backgroundByteThreshold = 1 << 20;

  /// Rough bytes per serialized point: `[123.45,678.9,0.512,1234],`.
  static const int _bytesPerPoint = 28;

  /// Rough fixed bytes per stroke / item (ids, colour, style fields).
  static const int _bytesPerItem = 200;

  /// Whether [encode] will use a background isolate for [content].
  static bool encodesInBackground(PageContent content) =>
      content.strokes.length > backgroundStrokeThreshold ||
      estimateJsonBytes(content) > backgroundByteThreshold;

  /// Cheap upper-bound-ish estimate of the encoded size, without encoding.
  static int estimateJsonBytes(PageContent content) {
    var bytes = 64;
    for (final s in content.strokes) {
      // `raw` and `points` are both written, even when they are identical.
      bytes += (s.raw.length + s.points.length) * _bytesPerPoint + _bytesPerItem;
    }
    for (final t in content.texts) {
      bytes += t.text.length * 2 + _bytesPerItem;
    }
    bytes += content.images.length * _bytesPerItem;
    return bytes;
  }

  /// Encodes [content] on the calling isolate.
  static Uint8List encodeSync(PageContent content) =>
      encodeJsonBytes(content.toJson());

  /// Encodes [content], in a background isolate when it is large.
  ///
  /// The page is copied into the isolate when the call starts, so later
  /// edits to [content] do not affect the bytes produced.
  static Future<Uint8List> encode(PageContent content) async {
    if (!encodesInBackground(content)) return encodeSync(content);
    return _encodeInBackground(content);
  }

  /// Parses a page file's JSON (top-level function so it can be sent to a
  /// background isolate).
  static PageContent decode(Map<String, dynamic> json) =>
      PageContent.fromJson(json);
}

// Top-level so the isolate closure captures only the page.
Future<Uint8List> _encodeInBackground(PageContent content) =>
    Isolate.run(() => PageCodec.encodeSync(content));
