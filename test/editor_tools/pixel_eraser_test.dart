import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/commands.dart';
import 'package:neatink/document/notebook_doc.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/features/editor/tools/pixel_eraser.dart';
import 'package:neatink/features/editor/tools/spatial_index.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';

import 'tool_test_utils.dart';

/// Sequential ids: piece1, piece2, ...
String Function() idGen() {
  var n = 0;
  return () => 'piece${++n}';
}

/// Interpolated cut points are quantized to 0.01 pt like captured ink.
const quantEps = 0.01;

void main() {
  group('cutStroke', () {
    // Horizontal pen line from x = 0 to 100, points 5 pt apart, width 2.
    final line = strokeOf('line', linePoints(0, 50, 100, 50, spacing: 5),
        size: 2, msPerPoint: 10);

    test('a sweep through the middle splits it into two pieces', () {
      // Vertical sweep at x = 52 with radius 3: reach 3 + 1 = 4.
      final pieces = cutStroke(line, const Vec2(52, 0), const Vec2(52, 100), 3,
          newId: idGen())!;
      expect(pieces, hasLength(2));
      final left = pieces[0], right = pieces[1];
      expect(left.points.first.pos, line.points.first.pos);
      expect(right.points.last.pos, line.points.last.pos);
      // Boundary points sit exactly on the reach circle around the sweep.
      expect(left.points.last.x, closeTo(48, quantEps));
      expect(right.points.first.x, closeTo(56, quantEps));
      for (final p in left.points) {
        expect(p.x, lessThanOrEqualTo(48 + quantEps));
      }
      for (final p in right.points) {
        expect(p.x, greaterThanOrEqualTo(56 - quantEps));
      }
      // The boundary point's time is interpolated between its neighbours
      // (points 45 and 50 at 90 ms and 100 ms).
      expect(left.points.last.t, 96);
      expect(left.points.last.pressure, 0.5);
    });

    test('boundary points lie on the circle for a slanted stroke', () {
      final slanted = strokeOf('s', linePoints(0, 0, 80, 60, spacing: 3));
      const c = Vec2(40, 30);
      const radius = 5.0, reach = radius + 1;
      final pieces = cutStroke(slanted, c, c, radius, newId: idGen())!;
      expect(pieces, hasLength(2));
      expect(pieces[0].points.last.pos.distanceTo(c), closeTo(reach, quantEps));
      expect(pieces[1].points.first.pos.distanceTo(c), closeTo(reach, quantEps));
    });

    test('pieces keep tool, style, colour and size', () {
      final styled = Stroke(
        id: 'styled',
        tool: StrokeTool.pen,
        penStyle: PenStyle.fountain,
        color: 0xFF1565C0,
        size: 3,
        raw: [
          for (var i = 0; i <= 20; i++) InkPoint(i * 5.0, 10, 0.3 + i * 0.01, i * 8),
        ],
      );
      final ids = idGen();
      final pieces =
          cutStroke(styled, const Vec2(50, 0), const Vec2(50, 20), 4, newId: ids)!;
      expect(pieces.map((p) => p.id), ['piece1', 'piece2']);
      for (final p in pieces) {
        expect(p.tool, StrokeTool.pen);
        expect(p.penStyle, PenStyle.fountain);
        expect(p.color, 0xFF1565C0);
        expect(p.size, 3);
        expect(p.shape, isNull);
        expect(p.pointsAreRaw, isTrue);
      }
    });

    test('edited strokes: raw and points are sliced at the same indices', () {
      // points = raw moved 2 pt down and 1 pt right (one-to-one).
      final raw = [
        for (var i = 0; i <= 25; i++) InkPoint(i * 4.0, 100 + (i % 3), 0.5, i * 10),
      ];
      final tidied = Stroke(
        id: 't',
        tool: StrokeTool.pen,
        color: 0xFF000000,
        size: 2,
        raw: raw,
        points: [for (final p in raw) p.withPos(p.x + 1, p.y + 2)],
      );
      final pieces = cutStroke(
          tidied, const Vec2(41.3, 90), const Vec2(41.3, 110), 3,
          newId: idGen())!;
      expect(pieces, hasLength(2));
      for (final piece in pieces) {
        expect(piece.pointsAreRaw, isFalse);
        expect(piece.raw.length, piece.points.length);
        for (var i = 0; i < piece.raw.length; i++) {
          // The offset between raw and points is preserved point by point,
          // including the interpolated boundary points.
          expect(piece.points[i].x - piece.raw[i].x, closeTo(1, 2 * quantEps));
          expect(piece.points[i].y - piece.raw[i].y, closeTo(2, 2 * quantEps));
          expect(piece.points[i].t, piece.raw[i].t);
        }
      }
    });

    test('shape strokes: pieces use the cut points as raw and drop shape', () {
      final rect = Stroke(
        id: 'rect',
        tool: StrokeTool.pen,
        color: 0xFF000000,
        size: 2,
        // Hand-drawn raw (few points) vs generated points (many).
        raw: [
          const InkPoint(0, 0, 0.5, 0),
          const InkPoint(98, 2, 0.5, 300),
          const InkPoint(100, 60, 0.5, 600),
        ],
        points: [
          for (final p in linePoints(0, 0, 100, 0)) InkPoint(p.x, p.y, 0.5, 0),
        ],
        shape: ShapeKind.rectangle,
      );
      final pieces =
          cutStroke(rect, const Vec2(50, -10), const Vec2(50, 10), 2, newId: idGen())!;
      expect(pieces, hasLength(2));
      for (final p in pieces) {
        expect(p.shape, isNull);
        expect(p.pointsAreRaw, isTrue);
        for (final q in p.points) {
          expect(q.y, 0);
        }
      }
    });

    test('dots are erased whole; untouched strokes return null', () {
      final dot = strokeOf('dot', [const Vec2(10, 10)], size: 2);
      expect(cutStroke(dot, const Vec2(12, 10), const Vec2(12, 10), 1.5,
          newId: idGen()), isEmpty);
      expect(cutStroke(dot, const Vec2(13, 10), const Vec2(13, 10), 1.5,
          newId: idGen()), isNull);
      expect(cutStroke(line, const Vec2(0, 0), const Vec2(100, 0), 3,
          newId: idGen()), isNull);
    });

    test('erasing an end leaves one piece; tiny leftovers are dropped', () {
      final end = cutStroke(line, const Vec2(100, 40), const Vec2(100, 60), 5,
          newId: idGen())!;
      expect(end, hasLength(1));
      expect(end.single.points.first.pos, line.points.first.pos);
      expect(end.single.points.last.x, closeTo(94, quantEps));

      // Cut 0.5 pt from the start: the 0.5 pt stub is dropped.
      final stub = cutStroke(line, const Vec2(4.5, 40), const Vec2(4.5, 60), 3,
          newId: idGen())!;
      expect(stub, hasLength(1));
      expect(stub.single.points.first.x, closeTo(8.5, quantEps));

      // Covering the whole stroke erases it.
      expect(cutStroke(line, const Vec2(0, 50), const Vec2(100, 50), 1,
          newId: idGen()), isEmpty);
    });

    test('a zigzag crossed once is cut on every segment the eraser covers', () {
      final zig = strokeOf('z', [
        const Vec2(0, 0),
        const Vec2(10, 40),
        const Vec2(20, 0),
        const Vec2(30, 40),
        const Vec2(40, 0),
      ]);
      // Horizontal sweep along y = 20 crosses all four segments.
      final pieces =
          cutStroke(zig, const Vec2(-10, 20), const Vec2(50, 20), 2, newId: idGen())!;
      expect(pieces, hasLength(5));
      for (final p in pieces) {
        for (final q in p.points) {
          expect((q.y - 20).abs(), greaterThanOrEqualTo(3 - quantEps));
        }
      }
    });
  });

  group('pixelErase and PixelEraseSession', () {
    test('pixelErase maps only touched strokes', () {
      final a = strokeOf('a', linePoints(0, 10, 100, 10));
      final b = strokeOf('b', linePoints(0, 80, 100, 80));
      final out = pixelErase(
          candidates: [a, b],
          from: const Vec2(50, 0),
          to: const Vec2(50, 20),
          radius: 3,
          newId: idGen());
      expect(out.keys, ['a']);
      expect(out['a'], hasLength(2));
    });

    test('a drag that cuts a stroke twice is one splice, undoable', () {
      final s = strokeOf('s', linePoints(0, 50, 120, 50));
      final other = strokeOf('o', linePoints(0, 200, 50, 200));
      final page = PageContent(strokes: [other, s]);
      final session =
          PixelEraseSession(index: SpatialIndex.forPage(page), newId: idGen());
      expect(session.sweep(const Vec2(40, 30), const Vec2(40, 70), 2), isTrue);
      expect(session.replacedIds, {'s'});
      expect(session.pieces, hasLength(2));
      // The second cut hits the right-hand piece, not the page stroke.
      expect(session.sweep(const Vec2(80, 30), const Vec2(80, 70), 2), isTrue);
      expect(session.replacedIds, {'s'});
      final pieces = session.replacements['s']!;
      expect(pieces, hasLength(3));
      // In polyline order.
      expect(pieces[0].points.first.x, 0);
      expect(pieces[1].points.first.x, closeTo(43, quantEps));
      expect(pieces[2].points.last.x, 120);
      expect(pieces.map((p) => p.id).toSet(), hasLength(3));
      // Nothing there: no change.
      expect(session.sweep(const Vec2(300, 300), const Vec2(301, 300), 2), isFalse);

      final doc = NotebookDoc(
        NotebookMeta(
            id: 'n',
            title: 'T',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            pages: const [PageMeta(id: 'p')]),
        pages: {'p': page},
      );
      final stack = CommandStack()
        ..execute(SpliceStrokesCommand('p', session.replacements), doc);
      expect(page.strokes.map((x) => x.id),
          ['o', pieces[0].id, pieces[1].id, pieces[2].id]);
      stack.undo(doc);
      expect(page.strokes.map((x) => x.id), ['o', 's']);
      expect(page.strokes[1], same(s));
    });

    test('erasing a piece completely leaves it out', () {
      final s = strokeOf('s', linePoints(0, 50, 100, 50));
      final page = PageContent(strokes: [s]);
      final session =
          PixelEraseSession(index: SpatialIndex.forPage(page), newId: idGen());
      session.sweep(const Vec2(50, 40), const Vec2(50, 60), 2);
      // Rub out the whole left piece (reach 4.5: up to x = 52.5, short of
      // the right piece, which starts at 53).
      session.sweep(const Vec2(-5, 50), const Vec2(48, 50), 3.5);
      final pieces = session.replacements['s']!;
      expect(pieces, hasLength(1));
      expect(pieces.single.points.first.x, closeTo(53, quantEps));
    });
  });
}
