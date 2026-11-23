import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/features/editor/tools/lasso.dart';
import 'package:neatink/features/editor/tools/pixel_eraser.dart';
import 'package:neatink/features/editor/tools/spatial_index.dart';
import 'package:neatink/features/editor/tools/stroke_eraser.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/line_style.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';

import 'tool_test_utils.dart';

/// A 2 pt pen line along y = 50 from x = 40 to x = 140 in [line].
Stroke lineIn(LineSettings line, {double concentration = 1, String id = 's'}) =>
    strokeOf(id, linePoints(40, 50, 140, 50, spacing: 5), size: 2)
        .copyWith(line: line, concentration: concentration);

/// A wave 4 pt high each side of the centre line (height slider 5 * 2 pt
/// pen * 0.4).
const wavy = LineSettings(style: LineStyle.wavy, waveHeight: 5);
const zigzag = LineSettings(style: LineStyle.zigzag, waveHeight: 5);
const double_ = LineSettings(style: LineStyle.parallel);
const dashed = LineSettings(style: LineStyle.dashed);
const dotted = LineSettings(style: LineStyle.dotted);

/// Interpolated cut points are quantized to 0.01 pt like captured ink.
const quantEps = 0.01;

String Function() idGen() {
  var n = 0;
  return () => 'piece${++n}';
}

void main() {
  group('stroke eraser reach', () {
    // A pen 2 pt wide has a half width of 1. The eraser here has radius 3.
    bool hit(Stroke s, double dy) => strokeTouchedBySweep(
        s, Vec2(60, 50 + dy), Vec2(120, 50 + dy), 3);

    test('a wave is hit at its crests, a plain line is not', () {
      // 3 + 1 = 4 for a solid line; 3 + 1 + 4 = 8 for the wave.
      expect(hit(lineIn(LineSettings.solid), 6), isFalse);
      expect(hit(lineIn(wavy), 6), isTrue);
      expect(hit(lineIn(zigzag), 6), isTrue);
      expect(hit(lineIn(wavy), 7.9), isTrue);
      expect(hit(lineIn(wavy), 8.1), isFalse);
      expect(hit(lineIn(zigzag), 8.1), isFalse);
    });

    test('a double line is hit at its second line', () {
      // 3 + 1 + 2.2 = 6.2
      expect(hit(lineIn(LineSettings.solid), 5), isFalse);
      expect(hit(lineIn(double_), 5), isTrue);
      expect(hit(lineIn(double_), 6.1), isTrue);
      expect(hit(lineIn(double_), 6.3), isFalse);
      expect(hit(lineIn(double_), -6.1), isTrue);
    });

    test('dashes and dots reach no further than the pen', () {
      for (final line in [dashed, dotted]) {
        expect(hit(lineIn(line), 3.9), isTrue, reason: line.style.name);
        expect(hit(lineIn(line), 4.1), isFalse, reason: line.style.name);
      }
    });

    test('a thicker pen scales the reach of the style', () {
      final fat = strokeOf('f', linePoints(40, 50, 140, 50, spacing: 5), size: 4)
          .copyWith(line: wavy);
      // half width 2 + amplitude 8, plus the eraser's 3.
      expect(strokeTouchedBySweep(fat, const Vec2(60, 62.9), const Vec2(120, 62.9), 3),
          isTrue);
      expect(strokeTouchedBySweep(fat, const Vec2(60, 63.1), const Vec2(120, 63.1), 3),
          isFalse);
    });

    test('a spatial index finds a styled stroke through its crests', () {
      final page = PageContent(strokes: [lineIn(wavy), lineIn(LineSettings.solid, id: 'plain')
          .copyWith(points: linePoints(40, 80, 140, 80, spacing: 5)
              .map((v) => InkPoint(v.x, v.y, 0.5, 0))
              .toList())]);
      final index = SpatialIndex.forPage(page);
      // Eraser band 7 pt above the wave's centre line.
      expect(eraseHits(index, const Vec2(60, 43), const Vec2(120, 43), 3), {'s'});
      final session = StrokeEraseSession(index);
      expect(session.sweep(const Vec2(60, 43), const Vec2(120, 43), 3), {'s'});
    });
  });

  group('lasso tap reach', () {
    test('tapping a crest selects the wave, tapping beside a plain line does not', () {
      final page = PageContent(strokes: [lineIn(wavy)]);
      // Tap radius 5: 5 + 1 + 4 = 10 from the centre line.
      expect(strokeHitAt(page.strokes.single, const Vec2(80, 59.5), 5), isTrue);
      expect(strokeHitAt(page.strokes.single, const Vec2(80, 60.5), 5), isFalse);
      expect(strokeHitAt(lineIn(LineSettings.solid), const Vec2(80, 55.5), 5),
          isTrue);
      expect(strokeHitAt(lineIn(LineSettings.solid), const Vec2(80, 56.5), 5),
          isFalse);
      expect(
          tapSelect(pageId: 'p', page: page, point: const Vec2(80, 58), radius: 5)
              .strokeIds,
          {'s'});
    });

    test('tapping beside the second line of a double line selects it', () {
      final page = PageContent(strokes: [lineIn(double_)]);
      // 5 + 1 + 2.2 = 8.2 from the centre line.
      expect(
          tapSelect(pageId: 'p', page: page, point: const Vec2(80, 58), radius: 5)
              .strokeIds,
          {'s'});
      expect(
          tapSelect(pageId: 'p', page: page, point: const Vec2(80, 58.5), radius: 5)
              .strokeIds,
          isEmpty);
    });

    test('a plain stroke keeps the old reach', () {
      final page = PageContent(strokes: [lineIn(LineSettings.solid)]);
      expect(
          tapSelect(pageId: 'p', page: page, point: const Vec2(80, 55.9), radius: 5)
              .strokeIds,
          {'s'});
      expect(
          tapSelect(pageId: 'p', page: page, point: const Vec2(80, 56.1), radius: 5)
              .strokeIds,
          isEmpty);
    });

    test('a lasso around a styled stroke still selects it', () {
      final page = PageContent(strokes: [lineIn(wavy), lineIn(dashed, id: 'd')]);
      final lasso = joinPaths([
        linePoints(0, 0, 200, 0),
        linePoints(200, 0, 200, 100),
        linePoints(200, 100, 0, 100),
        linePoints(0, 100, 0, 0),
      ]);
      expect(lassoSelect(pageId: 'p', page: page, lasso: lasso).strokeIds,
          {'s', 'd'});
    });
  });

  group('pixel eraser reach', () {
    // Sweep along y = 50 + dy, radius 3, in a vertical band so it cuts once.
    List<Stroke>? cutAt(Stroke s, double dy) =>
        cutStroke(s, Vec2(90, 50 + dy), Vec2(90, 50 + dy), 3, newId: idGen());

    test('the cut clears the wave crests', () {
      // 3 + 1 + 4 = 8 for the wave, 3 + 1 = 4 for a plain line.
      expect(cutAt(lineIn(LineSettings.solid), 6), isNull);
      expect(cutAt(lineIn(wavy), 6), isNotNull);
      expect(cutAt(lineIn(wavy), 8.1), isNull);
      // The piece boundaries sit 8 pt from the centre line's point under the
      // eraser: sqrt(8^2 - 6^2) = 5.29 each side of x = 90.
      final pieces = cutAt(lineIn(wavy), 6)!;
      expect(pieces, hasLength(2));
      expect(pieces[0].points.last.x, closeTo(90 - 5.2915, quantEps));
      expect(pieces[1].points.first.x, closeTo(90 + 5.2915, quantEps));
    });

    test('the cut reaches the second line of a double line', () {
      expect(cutAt(lineIn(LineSettings.solid), 5), isNull);
      expect(cutAt(lineIn(double_), 5), isNotNull);
      expect(cutAt(lineIn(double_), 6.3), isNull);
    });

    test('pixelErase looks at a styled stroke whose crests touch the sweep', () {
      final out = pixelErase(
        candidates: [lineIn(wavy), lineIn(LineSettings.solid, id: 'plain')],
        from: const Vec2(90, 40),
        to: const Vec2(90, 44),
        radius: 3,
        newId: idGen(),
      );
      // The eraser's box is 3 pt above y = 43..47: the wave's paint bounds
      // (46 .. 54 minus the half width) reach it, the plain line's do not.
      expect(out.keys, ['s']);
    });

    test('pieces keep the line style and the concentration', () {
      for (final line in [dashed, dotted, wavy, zigzag, double_]) {
        final s = lineIn(line, concentration: 0.4);
        final pieces = cutStroke(s, const Vec2(90, 40), const Vec2(90, 60), 3,
            newId: idGen())!;
        expect(pieces, hasLength(2), reason: line.style.name);
        for (final p in pieces) {
          expect(p.line, line, reason: line.style.name);
          expect(p.concentration, 0.4, reason: line.style.name);
          expect(p.tool, s.tool);
          expect(p.size, s.size);
        }
      }
    });

    test('pieces of a snapped shape keep the style too', () {
      final base = lineIn(dashed, concentration: 0.7);
      final shape = base.copyWith(
        raw: [const InkPoint(40, 50, 0.5, 0), const InkPoint(140, 52, 0.5, 90)],
        points: [for (final p in linePoints(40, 50, 140, 50)) InkPoint(p.x, p.y, 0.5, 0)],
        shape: ShapeKind.line,
      );
      final pieces = cutStroke(shape, const Vec2(90, 40), const Vec2(90, 60), 3,
          newId: idGen())!;
      expect(pieces, hasLength(2));
      for (final p in pieces) {
        expect(p.shape, isNull);
        expect(p.line, dashed);
        expect(p.concentration, 0.7);
      }
    });

    test('pieces with their own raw path keep the style', () {
      final raw = [for (var i = 0; i <= 20; i++) InkPoint(40.0 + i * 5, 50, 0.5, i * 8)];
      final edited = Stroke(
        id: 'e',
        tool: StrokeTool.pen,
        color: 0xFF000000,
        size: 2,
        raw: raw,
        points: [for (final p in raw) p.withPos(p.x, p.y + 1)],
        line: wavy,
        concentration: 0.5,
      );
      final pieces = cutStroke(edited, const Vec2(90, 30), const Vec2(90, 70), 3,
          newId: idGen())!;
      expect(pieces, hasLength(2));
      for (final p in pieces) {
        expect(p.pointsAreRaw, isFalse);
        expect(p.line, wavy);
        expect(p.concentration, 0.5);
      }
    });

    test('a piece cut again in one drag keeps the style', () {
      final s = lineIn(zigzag, concentration: 0.3);
      final page = PageContent(strokes: [s]);
      final session =
          PixelEraseSession(index: SpatialIndex.forPage(page), newId: idGen());
      expect(session.sweep(const Vec2(70, 30), const Vec2(70, 70), 2), isTrue);
      expect(session.sweep(const Vec2(110, 30), const Vec2(110, 70), 2), isTrue);
      final pieces = session.replacements['s']!;
      expect(pieces, hasLength(3));
      for (final p in pieces) {
        expect(p.line, zigzag);
        expect(p.concentration, 0.3);
      }
    });

    test('a plain stroke gives plain pieces, as before', () {
      final pieces = cutStroke(lineIn(LineSettings.solid), const Vec2(90, 40),
          const Vec2(90, 60), 3,
          newId: idGen())!;
      for (final p in pieces) {
        expect(p.line.isSolid, isTrue);
        expect(p.concentration, 1.0);
      }
    });

    test('a styled dot is erased whole when the eraser reaches it', () {
      final dot = strokeOf('dot', [const Vec2(10, 10)], size: 4)
          .copyWith(line: wavy);
      // Reach 2 + 2 + amplitude (5 * 4 * 0.4 = 8) = 12.
      expect(
          cutStroke(dot, const Vec2(21, 10), const Vec2(21, 10), 2, newId: idGen()),
          isEmpty);
      expect(
          cutStroke(dot, const Vec2(23, 10), const Vec2(23, 10), 2, newId: idGen()),
          isNull);
    });
  });
}
