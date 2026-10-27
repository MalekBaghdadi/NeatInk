import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

// A tiny pure-Dart PNG writer for 8-bit grey images, so the exact pixels the
// recogniser saw can travel inside a JSON file. No image package needed.

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    t[n] = c;
  }
  return t;
}();

/// CRC-32 (PNG / zlib flavour) of [bytes].
int crc32(List<int> bytes, [int crc = 0]) {
  var c = crc ^ 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Encodes [pixels] ([width] x [height] bytes, row-major, 0 = black,
/// 255 = white) as a grey 8-bit PNG file.
Uint8List encodeGrayPng(Uint8List pixels, int width, int height) {
  if (width <= 0 || height <= 0 || pixels.length != width * height) {
    throw ArgumentError('pixels must hold width * height bytes');
  }
  // Every row starts with filter type 0 (none).
  final raw = Uint8List((width + 1) * height);
  for (var y = 0; y < height; y++) {
    raw[y * (width + 1)] = 0;
    raw.setRange(y * (width + 1) + 1, (y + 1) * (width + 1),
        pixels, y * width);
  }
  final idat = Uint8List.fromList(ZLibEncoder(level: 6).convert(raw));

  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 0) // colour type: grey
    ..setUint8(10, 0) // compression
    ..setUint8(11, 0) // filter method
    ..setUint8(12, 0); // no interlace

  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final head = ByteData(4)..setUint32(0, data.length);
    final typeBytes = type.codeUnits;
    out
      ..add(head.buffer.asUint8List())
      ..add(typeBytes)
      ..add(data);
    final crc = crc32(data, crc32(typeBytes));
    out.add((ByteData(4)..setUint32(0, crc)).buffer.asUint8List());
  }

  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', idat);
  chunk('IEND', const []);
  return out.takeBytes();
}
