import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/recognition/stroke_grouping.dart';
import 'package:neatink/recognition/word_image.dart';

/// Dumps the line images of a real samples file (the JSON the Convert review
/// sheet's "Share samples" button writes) as PNGs, so the recogniser can be
/// run on them from outside (`dump_probs.py --pngs`).
///
/// The owner's samples are personal data: this test is skipped unless
/// `NEATINK_SAMPLES` (the JSON file) and `NEATINK_DUMP_DIR` (an existing or
/// creatable folder) are set, and it reads only from that path. Optional:
/// `NEATINK_PAGE` (default 1), `NEATINK_EXPECT_LINES` (fail unless the page
/// splits into exactly that many lines) and `NEATINK_DUMP_SWEEP=1` (also
/// dump every pen width x margin combination, to see how robust a reading
/// is).
///
/// Files: `line<i>_chunk<j>.png` (dots as written) and
/// `line<i>_chunk<j>_snap.png` (dots moved onto their stems); the sweep adds
/// `_px<pen>_m<margin>` before the suffix.
void main() {
  final samples = Platform.environment['NEATINK_SAMPLES'];
  final dumpDir = Platform.environment['NEATINK_DUMP_DIR'];
  final skip = samples == null || dumpDir == null
      ? 'set NEATINK_SAMPLES and NEATINK_DUMP_DIR to dump the line images of a samples file'
      : false;

  test('dump the line images of a samples file', () async {
    final json = jsonDecode(File(samples!).readAsStringSync()) as Map<String, dynamic>;
    final page = Platform.environment['NEATINK_PAGE'] ?? '1';
    final strokes = <Stroke>[];
    for (final w in json['words'] as List<dynamic>) {
      final word = w as Map<String, dynamic>;
      if ('${word['page']}' != page) continue;
      for (final s in word['strokes'] as List<dynamic>) {
        strokes.add(_strokeFromSample(s as Map<String, dynamic>));
      }
    }
    expect(strokes, isNotEmpty);

    final lines = groupStrokes(strokes);
    // ignore: avoid_print
    print('page $page: ${strokes.length} strokes -> ${lines.length} lines');
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final order = [for (final s in l.inkStrokes) strokes.indexOf(s)];
      // ignore: avoid_print
      print('line $i: ${l.inkStrokes.length} strokes, baseline y ${l.baselineY.toStringAsFixed(1)}, '
          'slope ${l.baselineSlope.toStringAsFixed(4)}, x-height ${l.xHeight.toStringAsFixed(2)}, '
          'x ${l.left.toStringAsFixed(0)}..${l.right.toStringAsFixed(0)}, '
          '${l.words.length} legacy words, strokes $order');
    }
    final seen = <Stroke>{for (final l in lines) ...l.inkStrokes};
    expect(seen.length, strokes.length, reason: 'every stroke must be in a line');
    final expected = int.tryParse(Platform.environment['NEATINK_EXPECT_LINES'] ?? '');
    if (expected != null) expect(lines, hasLength(expected));

    final dir = Directory(dumpDir!)..createSync(recursive: true);
    const renderer = PolylineWordImageRenderer();
    final sweep = Platform.environment['NEATINK_DUMP_SWEEP'] == '1';
    final variants = <({String tag, double px, double margin})>[
      (tag: '', px: const LineImageConfig().strokePx, margin: const LineImageConfig().marginFrac),
      if (sweep)
        for (final px in [1.6, 1.8, 2.0, 2.2, 2.4])
          for (final m in [0.10, 0.15, 0.20]) (tag: '_px${px}_m${m.toStringAsFixed(2)}', px: px, margin: m),
    ];
    for (final v in variants) {
      for (final snap in [false, true]) {
        for (var i = 0; i < lines.length; i++) {
          final images = await renderLineImages(
            lines[i],
            renderer: renderer,
            config: LineImageConfig(snapDots: snap, strokePx: v.px, marginFrac: v.margin),
          );
          for (var j = 0; j < images.length; j++) {
            final img = images[j];
            final name = 'line${i}_chunk$j${v.tag}${snap ? '_snap' : ''}.png';
            File('${dir.path}/$name').writeAsBytesSync(encodeGrayPng(img.pixels, img.width, img.height));
            if (v.tag.isEmpty) {
              // ignore: avoid_print
              print('$name: ${img.width}x${img.height}, scale ${img.scale.toStringAsFixed(3)}, '
                  '${img.strokes.length} strokes, moved dots ${img.shifts.where((s) => s != 0).length}');
            }
          }
        }
      }
    }
  }, skip: skip);
}

Stroke _strokeFromSample(Map<String, dynamic> s) => Stroke(
      id: s['id'] as String,
      tool: StrokeTool.pen,
      color: colorFromHex((s['color'] as String?) ?? '#FF1E1E1E'),
      size: (s['size'] as num?)?.toDouble() ?? 2.2,
      raw: [
        for (final p in s['points'] as List<dynamic>)
          InkPoint(
            ((p as List<dynamic>)[0] as num).toDouble(),
            (p[1] as num).toDouble(),
            p.length > 2 ? (p[2] as num).toDouble() : 0.5,
            p.length > 3 ? (p[3] as num).toInt() : 0,
          ),
      ],
    );

/// A minimal 8-bit greyscale PNG (zlib from dart:io, no packages).
Uint8List encodeGrayPng(Uint8List pixels, int width, int height) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // filter: none
    raw.add(Uint8List.sublistView(pixels, y * width, (y + 1) * width));
  }
  final out = BytesBuilder();
  out.add(const [137, 80, 78, 71, 13, 10, 26, 10]);
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 0) // greyscale
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  _chunk(out, 'IHDR', ihdr.buffer.asUint8List());
  _chunk(out, 'IDAT', Uint8List.fromList(zlib.encode(raw.toBytes())));
  _chunk(out, 'IEND', Uint8List(0));
  return out.toBytes();
}

void _chunk(BytesBuilder out, String type, Uint8List data) {
  final len = ByteData(4)..setUint32(0, data.length);
  out.add(len.buffer.asUint8List());
  final body = Uint8List.fromList([...type.codeUnits, ...data]);
  out.add(body);
  final crc = ByteData(4)..setUint32(0, _crc32(body));
  out.add(crc.buffer.asUint8List());
}

final List<int> _crcTable = () {
  final table = List<int>.filled(256, 0);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}();

int _crc32(Uint8List bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
