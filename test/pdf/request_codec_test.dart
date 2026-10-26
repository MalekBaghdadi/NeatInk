import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/pdf/pdf_export_request.dart';

/// Encodes with the codec the MethodChannel uses and decodes again, the way
/// the Kotlin side receives it.
Object? roundTrip(Object? value) {
  const codec = StandardMessageCodec();
  return codec.decodeMessage(codec.encodeMessage(value));
}

void main() {
  final page = ExportPage(
    width: 595,
    height: 842,
    pdfPageIndex: 2,
    background: 0xFFFAF5E8,
    lines: const [ExportLine(0, 10, 595, 10, 0.5, 0xFFC8D4E8)],
    dots: Float32List.fromList([10, 10, 20, 10]),
    dotRadius: 0.9,
    dotColor: 0xFFAAAAAA,
    images: const [ExportImage('/a/b.png', 1, 2, 3, 4)],
    highlighter: [
      ExportPolygon(Float32List.fromList([0, 0, 10, 0, 10, 10]), 0x59FFEE00),
    ],
    textRects: const [ExportRect(5, 6, 7, 8, 0xFFFFFF00)],
    textLines: const [
      ExportTextLine(
          text: 'héllo',
          x: 12,
          baselineY: 30,
          fontSize: 14,
          color: 0xFF000000,
          bold: true,
          underline: true,
          font: FontKind.mono,
          width: 40),
    ],
    ink: [
      ExportPolygon(
          Float32List.fromList([1, 1, 5, 1, 5, 5, 1, 5]), 0xFF1E1E1E),
    ],
  );

  test('a page survives the platform codec with the keys Kotlin reads', () {
    final map = roundTrip(page.toMap())! as Map<Object?, Object?>;
    expect(map['width'], 595.0);
    expect(map['height'], 842.0);
    expect(map['pdfPageIndex'], 2);
    // Colours above 2^31 arrive as 64-bit ints; Kotlin reads them as Number.
    expect(map['background'], 0xFFFAF5E8);
    expect(map['dotRadius'], 0.9);
    expect(map['dotColor'], 0xFFAAAAAA);
    expect(map['dots'], isA<Float32List>());
    expect(map['dots'], [10.0, 10.0, 20.0, 10.0]);

    final line = (map['lines']! as List).single as Map;
    expect(line.keys, containsAll(['x1', 'y1', 'x2', 'y2', 'width', 'color']));
    expect(line['color'], 0xFFC8D4E8);

    final image = (map['images']! as List).single as Map;
    expect(image['path'], '/a/b.png');
    expect(image.keys, containsAll(['x', 'y', 'width', 'height']));

    final highlighter = (map['highlighter']! as List).single as Map;
    expect(highlighter['xy'], isA<Float32List>());
    expect(highlighter['color'], 0x59FFEE00);

    final rect = (map['textRects']! as List).single as Map;
    expect(rect,
        {'x': 5.0, 'y': 6.0, 'width': 7.0, 'height': 8.0, 'color': 0xFFFFFF00});

    final text = (map['textLines']! as List).single as Map;
    expect(text['text'], 'héllo');
    expect(text['font'], 'mono');
    expect(text['bold'], true);
    expect(text['italic'], false);
    expect(text['underline'], true);
    expect(text['baselineY'], 30.0);
    expect(text['width'], 40.0);

    final ink = (map['ink']! as List).single as Map;
    expect((ink['xy'] as List).length, 8);
  });

  test('a blank page sends null for the PDF index and background', () {
    final map = roundTrip(const ExportPage(width: 10, height: 20).toMap())!
        as Map<Object?, Object?>;
    expect(map['pdfPageIndex'], isNull);
    expect(map['background'], isNull);
    expect(map['lines'], isEmpty);
    expect(map['ink'], isEmpty);
    expect(map['dots'], isEmpty);
  });

  test('a request survives the codec', () {
    final request = ExportRequest(
      outputPath: '/cache/out.pdf',
      sourcePdfPath: '/docs/source.pdf',
      title: 'Physics',
      pages: [page, const ExportPage(width: 1, height: 2)],
    );
    final map = roundTrip(request.toMap())! as Map<Object?, Object?>;
    expect(map['outputPath'], '/cache/out.pdf');
    expect(map['sourcePdfPath'], '/docs/source.pdf');
    expect(map['title'], 'Physics');
    expect(map['pages']! as List, hasLength(2));
  });

  test('polygons and images expose exactly the documented keys', () {
    expect(const ExportPolygon([1, 2, 3, 4, 5, 6], 7).toMap().keys,
        ['xy', 'color']);
    expect(const ExportImage('p', 1, 2, 3, 4).toMap().keys,
        ['path', 'x', 'y', 'width', 'height']);
  });
}
