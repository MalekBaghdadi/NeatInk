import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/cover_design.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/render/cover_painter.dart';

/// Paints [design] at [size] and returns the RGBA pixels.
Future<(int, int, List<int>)> paint(CoverDesign design, Color color, Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  CoverPainter(design: design, color: color).paint(canvas, size);
  final image = await recorder.endRecording().toImage(size.width.ceil(), size.height.ceil());
  final data = await image.toByteData();
  image.dispose();
  return (size.width.ceil(), size.height.ceil(), data!.buffer.asUint8List().toList());
}

/// How many pixels differ clearly from the cover colour.
int inked(List<int> rgba, Color color) {
  final r = (color.r * 255).round(), g = (color.g * 255).round(), b = (color.b * 255).round();
  var n = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if ((rgba[i] - r).abs() + (rgba[i + 1] - g).abs() + (rgba[i + 2] - b).abs() > 60) n++;
  }
  return n;
}

void main() {
  const dark = Color(0xFF1A237E);
  const light = Color(0xFFFFF59D);

  test('ink is dark on light covers and light on dark ones', () {
    expect(coverInk(light).computeLuminance(), lessThan(0.2));
    expect(coverInk(dark).computeLuminance(), greaterThan(0.6));
  });

  test('every pattern and picture paints, at tile and grid sizes, on every colour', () async {
    final designs = [
      for (final p in CoverPattern.values) CoverDesign.pattern(p),
      for (final a in CoverArt.values) CoverDesign.art(a),
    ];
    for (final d in designs) {
      for (final size in const [Size(60, 80), Size(150, 200), Size(240, 180)]) {
        await paint(d, dark, size);
      }
    }
    for (final c in NotebookMeta.coverColors) {
      await paint(const CoverDesign.art(CoverArt.brain), Color(c), const Size(60, 80));
    }
  });

  test('a picture draws visibly more than a plain cover', () async {
    final (_, _, plain) = await paint(const CoverDesign.pattern(CoverPattern.plain), dark, const Size(150, 200));
    for (final a in CoverArt.values) {
      final (w, h, px) = await paint(CoverDesign.art(a), dark, const Size(150, 200));
      expect(inked(px, dark), greaterThan(inked(plain, dark) + w * h ~/ 50), reason: a.label);
    }
  });

  test('pictures keep their shape on a wide cover (centred, not stretched)', () async {
    final (w, h, px) = await paint(const CoverDesign.art(CoverArt.atom), dark, const Size(400, 200));
    // Nothing drawn in the outer side bands: the 3:4 picture is centred.
    var edge = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < 30; x++) {
        final i = (y * w + x) * 4;
        if ((px[i] - (dark.r * 255).round()).abs() > 120) edge++;
      }
    }
    expect(edge, lessThan(h * 30 ~/ 10));
  });
}
