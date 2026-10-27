import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Longest side, in pixels, of a stored picture. Bigger photos are scaled
/// down: a page is at most A4-sized, so more pixels only cost memory and
/// PDF size.
const int maxStoredImageSide = 3000;

/// The user-facing reason a picture could not be added.
class ImageImportException implements Exception {
  const ImageImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A picture ready to be stored: upright, not too large.
class NormalizedImage {
  const NormalizedImage({
    required this.bytes,
    required this.extension,
    required this.width,
    required this.height,
  });

  /// Encoded file contents (what goes into the notebook's `assets/`). The
  /// PDF export embeds these bytes as they are, so they are already upright.
  final Uint8List bytes;

  /// File extension without the dot: `png` or `jpg`.
  final String extension;

  /// Pixel size of the upright picture.
  final int width;
  final int height;
}

/// Decodes [source] (any format the platform decodes) and returns bytes
/// that show the picture upright.
///
/// * `dart:ui` decodes with the EXIF orientation applied, so re-encoding the
///   decoded picture as PNG bakes the rotation in.
/// * A JPEG whose orientation tag is absent or 1, and that needs no
///   scaling, is kept byte for byte (no generation loss, small files).
/// * The longest side is limited to [maxSide] pixels.
///
/// Throws [ImageImportException] when the bytes are not a picture.
Future<NormalizedImage> normalizeImage(
  Uint8List source, {
  int maxSide = maxStoredImageSide,
}) async {
  ui.Codec? codec;
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Image? decoded;
  ui.Image? scaled;
  try {
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(source);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
    } catch (_) {
      throw const ImageImportException(
          "That file isn't a picture Mariam's Notes can open.");
    }
    final rawWidth = descriptor.width, rawHeight = descriptor.height;
    final tooBig = math.max(rawWidth, rawHeight) > maxSide;
    // Let the decoder scale while decoding: a huge photo is never held at
    // full size. The target applies to the longer raw side, whatever the
    // orientation turns out to be (checked again below).
    codec = await descriptor.instantiateCodec(
      targetWidth: tooBig && rawWidth >= rawHeight ? maxSide : null,
      targetHeight: tooBig && rawHeight > rawWidth ? maxSide : null,
    );
    decoded = (await codec.getNextFrame()).image;

    var image = decoded;
    var rescaled = tooBig;
    if (math.max(image.width, image.height) > maxSide) {
      scaled = await _scaleDown(image, maxSide);
      image = scaled;
      rescaled = true;
    }

    final orientation = isJpeg(source) ? jpegExifOrientation(source) : 0;
    if (orientation != 0 && (orientation == null || orientation == 1) &&
        !rescaled) {
      return NormalizedImage(
        bytes: source,
        extension: 'jpg',
        width: image.width,
        height: image.height,
      );
    }
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw const ImageImportException("That picture couldn't be converted.");
    }
    return NormalizedImage(
      bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      extension: 'png',
      width: image.width,
      height: image.height,
    );
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
    decoded?.dispose();
    scaled?.dispose();
  }
}

Future<ui.Image> _scaleDown(ui.Image image, int maxSide) {
  final factor = maxSide / math.max(image.width, image.height);
  final w = math.max(1, (image.width * factor).round());
  final h = math.max(1, (image.height * factor).round());
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final future = picture.toImage(w, h);
  picture.dispose();
  return future;
}

/// Whether [b] starts with the JPEG signature.
bool isJpeg(Uint8List b) => b.length > 3 && b[0] == 0xFF && b[1] == 0xD8;

/// The EXIF orientation (1-8) of a JPEG, or null when it has none or the
/// metadata is unreadable. 1 means upright.
int? jpegExifOrientation(Uint8List b) {
  if (!isJpeg(b)) return null;
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) return null;
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++; // fill byte
      continue;
    }
    // Standalone markers have no length; the scan data starts at SOS.
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    if (marker == 0xDA || marker == 0xD9) return null;
    final length = (b[i + 2] << 8) | b[i + 3];
    if (length < 2) return null;
    if (marker == 0xE1 && i + 4 + 6 <= b.length && _isExifHeader(b, i + 4)) {
      return _tiffOrientation(b, i + 10, math.min(b.length, i + 2 + length));
    }
    i += 2 + length;
  }
  return null;
}

bool _isExifHeader(Uint8List b, int at) =>
    b[at] == 0x45 && // E
    b[at + 1] == 0x78 && // x
    b[at + 2] == 0x69 && // i
    b[at + 3] == 0x66 && // f
    b[at + 4] == 0 &&
    b[at + 5] == 0;

int? _tiffOrientation(Uint8List b, int tiff, int end) {
  if (tiff + 8 > end) return null;
  final little = b[tiff] == 0x49 && b[tiff + 1] == 0x49; // "II"
  final big = b[tiff] == 0x4D && b[tiff + 1] == 0x4D; // "MM"
  if (!little && !big) return null;
  int u16(int at) =>
      little ? b[at] | (b[at + 1] << 8) : (b[at] << 8) | b[at + 1];
  int u32(int at) => little
      ? b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)
      : (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];
  final ifd = tiff + u32(tiff + 4);
  if (ifd + 2 > end) return null;
  final count = u16(ifd);
  for (var n = 0; n < count; n++) {
    final entry = ifd + 2 + n * 12;
    if (entry + 12 > end) return null;
    if (u16(entry) == 0x0112) {
      final value = u16(entry + 8);
      return value >= 1 && value <= 8 ? value : null;
    }
  }
  return null;
}
