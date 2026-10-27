import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/features/editor/integrations/text_images/frame_geometry.dart';
import 'package:neatink/features/editor/integrations/text_images/image_normalizer.dart';
import 'package:neatink/features/editor/integrations/text_images/text_format_bar.dart';
import 'package:neatink/ink/ink_rect.dart';
import 'package:neatink/ink/vec2.dart';

/// A minimal JPEG header carrying an EXIF orientation tag (no image data:
/// only the metadata parser reads it).
Uint8List jpegWithOrientation(int orientation, {bool little = true}) {
  final tiff = <int>[
    if (little) ...[0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0] else ...[0x4D, 0x4D, 0x00, 0x2A, 0, 0, 0, 8],
    if (little) ...[1, 0] else ...[0, 1], // one entry
    if (little) ...[0x12, 0x01, 3, 0, 1, 0, 0, 0] else ...[0x01, 0x12, 0, 3, 0, 0, 0, 1],
    if (little) ...[orientation, 0, 0, 0] else ...[0, orientation, 0, 0],
    0, 0, 0, 0,
  ];
  final exif = [0x45, 0x78, 0x69, 0x66, 0, 0, ...tiff];
  final length = exif.length + 2;
  return Uint8List.fromList([
    0xFF, 0xD8, //
    0xFF, 0xE1, length >> 8, length & 0xFF, ...exif,
    0xFF, 0xDA, 0, 2,
  ]);
}

Future<Uint8List> solidPng(int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFCC0000),
  );
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  group('frame geometry', () {
    const frame = InkRect(100, 100, 300, 140);

    test('text zones: inside, band, handle, away', () {
      expect(textZone(frame, const Vec2(150, 120), 1), TextZone.inside);
      expect(textZone(frame, const Vec2(150, 95), 1), TextZone.move);
      expect(textZone(frame, const Vec2(300, 120), 1), TextZone.resize);
      expect(textZone(frame, const Vec2(150, 200), 1), TextZone.none);
    });

    test('the band stays the same size on screen when zoomed', () {
      // 14 px at scale 2 is 7 points.
      expect(textZone(frame, const Vec2(150, 90), 2), TextZone.none);
      expect(textZone(frame, const Vec2(150, 90), 1), TextZone.move);
    });

    test('hit testing prefers the topmost box', () {
      const a = TextItem(id: 'a', x: 0, y: 0, width: 100, height: 50);
      const b = TextItem(id: 'b', x: 50, y: 0, width: 100, height: 50);
      expect(hitTextItem([a, b], const Vec2(60, 10))!.id, 'b');
      expect(hitTextItem([a, b], const Vec2(10, 10))!.id, 'a');
      expect(hitTextItem([a, b], const Vec2(10, 80)), isNull);
      expect(hitTextItem([a, b], const Vec2(10, 54), slop: 5)!.id, 'a');
    });

    test('moving keeps part of the box on the page', () {
      final o = clampMovedOrigin(frame, const Vec2(-1000, 5000), 595, 842);
      expect(o.x, closeTo(24 - 200, 1e-9));
      expect(o.y, 842 - 24);
    });

    test('text width follows the pointer within limits', () {
      expect(resizedTextWidth(frame, 250, 595), 150);
      expect(resizedTextWidth(frame, 101, 595), minTextWidth);
      expect(resizedTextWidth(frame, 5000, 595), 595 - 100);
    });

    test('image resize keeps aspect ratio and the opposite corner', () {
      const img = InkRect(100, 100, 200, 150); // 100 x 50
      final r = resizedImageFrame(img, ImageCorner.bottomRight, const Vec2(300, 160));
      expect(r.left, 100);
      expect(r.top, 100);
      expect(r.width / r.height, closeTo(2, 1e-9));
      expect(r.width, 200);
      final tl = resizedImageFrame(img, ImageCorner.topLeft, const Vec2(150, 125));
      expect(tl.right, closeTo(200, 1e-9));
      expect(tl.bottom, closeTo(150, 1e-9));
      expect(tl.width, closeTo(50, 1e-9));
    });

    test('image resize has a minimum size', () {
      const img = InkRect(100, 100, 200, 150);
      final r = resizedImageFrame(img, ImageCorner.bottomRight, const Vec2(0, 0));
      expect(r.height, greaterThanOrEqualTo(minImageSide - 1e-9));
    });

    test('a new picture is 60% of the page width, centred, aspect kept', () {
      final r = fitImageOnPage(
          pageWidth: 595, pageHeight: 842, pixelWidth: 400, pixelHeight: 200);
      expect(r.width, closeTo(357, 1e-9));
      expect(r.height, closeTo(178.5, 1e-9));
      expect(r.center.x, closeTo(297.5, 1e-9));
      expect(r.center.y, closeTo(421, 1e-9));
    });

    test('a very tall picture is limited by the page height', () {
      final r = fitImageOnPage(
          pageWidth: 595, pageHeight: 842, pixelWidth: 100, pixelHeight: 1000);
      expect(r.height, closeTo(842 * 0.85, 1e-9));
      expect(r.width, closeTo(842 * 0.85 / 10, 1e-9));
    });

    test('font size stepper walks the list', () {
      expect(steppedFontSize(16, up: true), 18);
      expect(steppedFontSize(16, up: false), 14);
      expect(steppedFontSize(15, up: true), 16);
      expect(steppedFontSize(8, up: false), 8);
      expect(steppedFontSize(80, up: true), 80);
    });
  });

  group('EXIF orientation', () {
    test('reads little and big endian tags', () {
      for (final o in [1, 3, 6, 8]) {
        expect(jpegExifOrientation(jpegWithOrientation(o)), o);
        expect(jpegExifOrientation(jpegWithOrientation(o, little: false)), o);
      }
    });

    test('is null without EXIF, for junk and for non-JPEG bytes', () {
      expect(jpegExifOrientation(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xDA, 0, 2])), isNull);
      expect(jpegExifOrientation(Uint8List.fromList([1, 2, 3, 4, 5, 6])), isNull);
      expect(jpegExifOrientation(Uint8List(0)), isNull);
      expect(jpegExifOrientation(jpegWithOrientation(9)), isNull);
      // Truncated in the middle of the EXIF block.
      expect(jpegExifOrientation(jpegWithOrientation(6).sublist(0, 20)), isNull);
    });
  });

  group('normalizeImage', () {
    testWidgets('re-encodes a PNG as PNG with its pixel size', (tester) async {
      await tester.runAsync(() async {
        final source = await solidPng(8, 4);
        final n = await normalizeImage(source);
        expect(n.extension, 'png');
        expect((n.width, n.height), (8, 4));
        // PNG signature.
        expect(n.bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      });
    });

    testWidgets('downscales a picture whose longest side is too large',
        (tester) async {
      await tester.runAsync(() async {
        final source = await solidPng(200, 100);
        final n = await normalizeImage(source, maxSide: 50);
        expect(n.width, 50);
        expect(n.height, 25);
      });
    });

    testWidgets('rejects bytes that are not a picture', (tester) async {
      await tester.runAsync(() async {
        await expectLater(
          normalizeImage(Uint8List.fromList(List.filled(32, 7))),
          throwsA(isA<ImageImportException>()),
        );
      });
    });
  });
}
