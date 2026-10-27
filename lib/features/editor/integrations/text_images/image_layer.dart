import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../editor_extensions.dart';
import 'image_source.dart';

/// Paints the pictures of a page, decoding them lazily.
///
/// Decoded images live in a small byte-budgeted LRU cache keyed by notebook
/// and asset. While a picture is still decoding, a grey placeholder is drawn
/// and [onReady] is called with each page that shows it once it is ready
/// (the editor then re-records that page). [prepare] awaits the decodes so
/// thumbnails are complete.
class ImageLayerPainter extends PageLayerPainter {
  ImageLayerPainter({
    required this.loadBytes,
    required this.onReady,
    this.hiddenId,
    this.maxDecodedSide = 2048,
    this.byteBudget = 96 * 1024 * 1024,
  });

  final AssetBytesLoader loadBytes;
  final void Function(String pageId) onReady;

  /// The picture being dragged on a page; drawn by the overlay instead.
  final String? Function(String pageId)? hiddenId;
  final int maxDecodedSide;
  final int byteBudget;

  final LinkedHashMap<String, ui.Image> _images = LinkedHashMap();
  final Map<String, Future<void>> _loading = {};
  final Set<String> _failed = {};
  final Map<String, Set<String>> _waitingPages = {};
  int _bytes = 0;
  bool _disposed = false;

  static String _key(String nb, String asset) => '$nb/$asset';

  /// The decoded picture, or null when not (yet) available.
  ui.Image? imageFor(String notebookId, String asset) {
    final key = _key(notebookId, asset);
    final image = _images.remove(key);
    if (image != null) _images[key] = image; // most recently used
    return image;
  }

  Future<void> _load(String notebookId, String asset) {
    final key = _key(notebookId, asset);
    return _loading[key] ??= _decode(notebookId, asset, key).whenComplete(() {
      _loading.remove(key);
    });
  }

  Future<void> _decode(String notebookId, String asset, String key) async {
    try {
      final bytes = await loadBytes(notebookId, asset);
      if (bytes == null || _disposed) {
        _failed.add(key);
        return;
      }
      final image = await _decodeBounded(bytes);
      if (_disposed) {
        image.dispose();
        return;
      }
      _images[key] = image;
      _bytes += image.width * image.height * 4;
      _evict();
    } catch (e) {
      debugPrint('NeatInk: picture $asset could not be shown: $e');
      _failed.add(key);
    }
    final pages = _waitingPages.remove(key);
    if (pages != null && !_disposed) pages.forEach(onReady);
  }

  Future<ui.Image> _decodeBounded(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width, h = descriptor.height;
    final big = math.max(w, h) > maxDecodedSide;
    final codec = await descriptor.instantiateCodec(
      targetWidth: big && w >= h ? maxDecodedSide : null,
      targetHeight: big && h > w ? maxDecodedSide : null,
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }

  void _evict() {
    while (_bytes > byteBudget && _images.length > 1) {
      final oldest = _images.keys.first;
      final image = _images.remove(oldest)!;
      _bytes -= image.width * image.height * 4;
      image.dispose();
    }
  }

  @override
  Future<void> prepare(PagePaintContext context) => Future.wait([
        for (final item in context.content.images.map((i) => i.asset).toSet())
          if (!_images.containsKey(_key(context.notebookId, item)))
            _load(context.notebookId, item),
      ]);

  @override
  void paint(ui.Canvas canvas, PagePaintContext context) {
    final hidden = context.forThumbnail ? null : hiddenId?.call(context.pageId);
    final paint = ui.Paint()
      ..isAntiAlias = true
      ..filterQuality = ui.FilterQuality.medium;
    for (final item in context.content.images) {
      if (item.id == hidden) continue;
      final dst = ui.Rect.fromLTWH(item.x, item.y, item.width, item.height);
      final key = _key(context.notebookId, item.asset);
      final image = imageFor(context.notebookId, item.asset);
      if (image != null) {
        canvas.drawImageRect(
          image,
          ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          dst,
          paint,
        );
        continue;
      }
      _placeholder(canvas, dst, failed: _failed.contains(key));
      if (!_failed.contains(key)) {
        _waitingPages.putIfAbsent(key, () => {}).add(context.pageId);
        _load(context.notebookId, item.asset);
      }
    }
  }

  void _placeholder(ui.Canvas canvas, ui.Rect r, {required bool failed}) {
    canvas.drawRect(r, ui.Paint()..color = const ui.Color(0x14000000));
    if (!failed) return;
    // A crossed box: the file is missing or unreadable.
    final line = ui.Paint()
      ..color = const ui.Color(0x66000000)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas
      ..drawRect(r, line)
      ..drawLine(r.topLeft, r.bottomRight, line)
      ..drawLine(r.topRight, r.bottomLeft, line);
  }

  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _bytes = 0;
  }
}
