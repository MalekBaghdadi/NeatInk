import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/commands.dart';
import 'package:neatink/document/notebook_doc.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/features/editor/tools/selection.dart';
import 'package:neatink/features/editor/tools/selection_transform.dart';
import 'package:neatink/ink/affine2.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/ink_rect.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';

import 'tool_test_utils.dart';

const pageId = 'p1';

/// A tidied stroke: `points` differ from `raw` (shifted 1 pt down).
Stroke tidiedStroke(String id) {
  final raw = [
    for (var i = 0; i <= 10; i++) InkPoint(10.0 + i * 3, 20, 0.5, i * 8),
  ];
  return Stroke(
    id: id,
    tool: StrokeTool.pen,
    color: 0xFF000000,
    size: 2,
    raw: raw,
    points: [for (final p in raw) p.withPos(p.x, p.y + 1)],
  );
}

PageContent samplePage() => PageContent(
      strokes: [
        tidiedStroke('tidy'),
        strokeOf('plain', linePoints(10, 60, 60, 80)),
        strokeOf('hl', linePoints(10, 100, 80, 100),
            tool: StrokeTool.highlighter, size: 12, color: 0xFFFFEB3B),
      ],
      // Growable lists: commands mutate them.
      texts: [
        const TextItem(
            id: 't1', x: 100, y: 20, width: 80, height: 18, text: 'Hello'),
      ],
      images: [
        const ImageItem(
            id: 'i1', x: 100, y: 60, width: 40, height: 30, asset: 'a.png'),
      ],
    );

Selection selectAll(PageContent page) => Selection.fromPage(page,
    pageId: pageId,
    strokeIds: page.strokes.map((s) => s.id),
    textIds: page.texts.map((t) => t.id),
    imageIds: page.images.map((i) => i.id));

NotebookDoc docWith(PageContent page) => NotebookDoc(
      NotebookMeta(
        id: 'n',
        title: 'T',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        pages: const [PageMeta(id: pageId)],
      ),
      pages: {pageId: page},
    );

void expectPointsClose(List<InkPoint> a, List<InkPoint> b, [double eps = 1e-9]) {
  expect(a.length, b.length);
  for (var i = 0; i < a.length; i++) {
    expect((a[i].x - b[i].x).abs(), lessThanOrEqualTo(eps), reason: 'x[$i]');
    expect((a[i].y - b[i].y).abs(), lessThanOrEqualTo(eps), reason: 'y[$i]');
    expect(a[i].pressure, b[i].pressure);
    expect(a[i].t, b[i].t);
  }
}

void main() {
  group('ResizeHandle', () {
    test('opposite pairs and positions', () {
      const r = InkRect(0, 0, 100, 50);
      expect(ResizeHandle.topLeft.opposite, ResizeHandle.bottomRight);
      expect(ResizeHandle.top.opposite, ResizeHandle.bottom);
      expect(ResizeHandle.right.opposite, ResizeHandle.left);
      expect(ResizeHandle.bottomLeft.opposite, ResizeHandle.topRight);
      for (final h in ResizeHandle.values) {
        expect(h.opposite.opposite, h);
      }
      expect(ResizeHandle.top.positionOn(r), vecCloseTo(50, 0));
      expect(ResizeHandle.bottomRight.positionOn(r), vecCloseTo(100, 50));
      expect(ResizeHandle.left.positionOn(r), vecCloseTo(0, 25));
      expect(ResizeHandle.values.where((h) => h.isCorner), hasLength(4));
      expect(ResizeHandle.top.scalesX, isFalse);
      expect(ResizeHandle.top.scalesY, isTrue);
    });
  });

  group('resizeTransform', () {
    const bounds = InkRect(100, 100, 200, 150); // 100 × 50

    test('the opposite handle is the fixed anchor for every handle', () {
      for (final h in ResizeHandle.values) {
        final from = h.positionOn(bounds);
        final target = from + const Vec2(13, 7);
        final m = resizeTransform(bounds, h, target);
        final anchor = h.opposite.positionOn(bounds);
        expect(m.apply(anchor), vecCloseTo(anchor.x, anchor.y, 1e-9),
            reason: '$h');
      }
    });

    test('edges scale one axis and follow the pen exactly', () {
      final right = resizeTransform(
          bounds, ResizeHandle.right, const Vec2(250, 999));
      expect(right.a, closeTo(1.5, 1e-12));
      expect(right.d, 1);
      expect(right.apply(const Vec2(200, 125)), vecCloseTo(250, 125));

      final top =
          resizeTransform(bounds, ResizeHandle.top, const Vec2(-5, 75));
      expect(top.a, 1);
      expect(top.d, closeTo(1.5, 1e-12));
      expect(top.apply(const Vec2(150, 100)), vecCloseTo(150, 75));
    });

    test('corners keep the aspect ratio', () {
      // Drag the bottom-right corner along its diagonal to double the size.
      final m = resizeTransform(
          bounds, ResizeHandle.bottomRight, const Vec2(300, 200));
      expect(m.a, closeTo(2, 1e-12));
      expect(m.d, closeTo(2, 1e-12));
      // Off the diagonal: still uniform (projection onto the diagonal).
      final m2 = resizeTransform(
          bounds, ResizeHandle.topLeft, const Vec2(80, 140));
      expect(m2.a, closeTo(m2.d, 1e-12));
      expect(m2.b, 0);
      expect(m2.c, 0);
    });

    test('enforces the minimum size and never mirrors', () {
      // Drag the right edge far past the left edge.
      final m =
          resizeTransform(bounds, ResizeHandle.right, const Vec2(-500, 0));
      final r = transformRect(bounds, m);
      expect(r.width, closeTo(8, 1e-9));
      expect(r.left, closeTo(100, 1e-9));
      expect(m.a, greaterThan(0));

      // Corner: the longer side stops at the minimum.
      final c = resizeTransform(
          bounds, ResizeHandle.bottomRight, const Vec2(0, 0));
      final rc = transformRect(bounds, c);
      expect(rc.width, closeTo(8, 1e-9));
      expect(rc.height, closeTo(4, 1e-9));
      expect(rc.topLeft, vecCloseTo(100, 100));
    });

    test('a side already below the minimum can only grow', () {
      const thin = InkRect(0, 0, 100, 3);
      final shrink =
          resizeTransform(thin, ResizeHandle.bottom, const Vec2(0, 1));
      expect(shrink.d, 1);
      final grow =
          resizeTransform(thin, ResizeHandle.bottom, const Vec2(0, 6));
      expect(grow.d, closeTo(2, 1e-12));
      // A corner on a thin selection still shrinks proportionally.
      final corner =
          resizeTransform(thin, ResizeHandle.bottomRight, const Vec2(50, 1.5));
      expect(corner.a, closeTo(0.5, 1e-9));
    });

    test('degenerate bounds give the identity', () {
      const flat = InkRect(0, 10, 100, 10);
      expect(
          resizeTransform(flat, ResizeHandle.bottom, const Vec2(0, 50))
              .isIdentity,
          isTrue);
    });
  });

  group('transformSelection', () {
    test('move: raw and points move together, items follow', () {
      final page = samplePage();
      final sel = selectAll(page);
      final edit = transformSelection(page, sel, moveTransform(5, -3));
      expect(edit.strokesBefore.map((s) => s.id), ['tidy', 'plain', 'hl']);
      expect(edit.strokesAfter.map((s) => s.id), ['tidy', 'plain', 'hl']);

      final before = edit.strokesBefore.first, after = edit.strokesAfter.first;
      for (var i = 0; i < before.raw.length; i++) {
        expect(after.raw[i].x, before.raw[i].x + 5);
        expect(after.raw[i].y, before.raw[i].y - 3);
        expect(after.points[i].x, before.points[i].x + 5);
        expect(after.points[i].y, before.points[i].y - 3);
        expect(after.points[i].t, before.points[i].t);
      }
      expect(after.size, before.size);
      // Untidied strokes keep sharing one list.
      expect(edit.strokesAfter[1].pointsAreRaw, isTrue);

      final (tBefore, tAfter) = edit.textChanges.single;
      expect(tBefore!.id, 't1');
      expect(tAfter!.x, 105);
      expect(tAfter.y, 17);
      expect(tAfter.fontSize, tBefore.fontSize);
      final (_, iAfter) = edit.imageChanges.single;
      expect(iAfter!.frame, const InkRect(105, 57, 145, 87));
    });

    test('inverse transform round trip restores the strokes', () {
      final page = samplePage();
      final sel = selectAll(page);
      final m = resizeTransform(
          sel.bounds, ResizeHandle.topLeft, sel.bounds.topLeft - const Vec2(20, 9));
      final there = transformSelection(page, sel, m);
      final back = [
        for (final s in there.strokesAfter) s.transformed(m.inverted()),
      ];
      for (var k = 0; k < back.length; k++) {
        expectPointsClose(back[k].raw, there.strokesBefore[k].raw, 1e-9);
        expectPointsClose(back[k].points, there.strokesBefore[k].points, 1e-9);
        expect(back[k].size, closeTo(there.strokesBefore[k].size, 1e-12));
      }
    });

    test('corner resize scales text font by the vertical scale', () {
      final page = samplePage();
      final sel = Selection.fromPage(page,
          pageId: pageId, textIds: ['t1'], imageIds: ['i1']);
      final m = Affine2.scaling(2, 2, pivot: sel.bounds.topLeft);
      final edit = transformSelection(page, sel, m);
      final (_, t) = edit.textChanges.single;
      expect(t!.fontSize, 28);
      expect(t.width, 160);
      expect(t.height, 36);
      final (_, i) = edit.imageChanges.single;
      expect(i!.width, 80);
      expect(i.height, 60);
    });

    test('edge resize changes text box width only, keeps the font', () {
      final page = samplePage();
      final sel = Selection.fromPage(page,
          pageId: pageId, textIds: ['t1'], imageIds: ['i1']);
      final wide = resizeTransform(sel.bounds, ResizeHandle.right,
          Vec2(sel.bounds.right + sel.bounds.width, 0));
      final edit = transformSelection(page, sel, wide);
      final (_, t) = edit.textChanges.single;
      expect(t!.fontSize, 14);
      expect(t.width, closeTo(160, 1e-9));
      expect(t.height, 18);
      expect(t.x, closeTo(100, 1e-9));
      // Images stretch.
      final (_, i) = edit.imageChanges.single;
      expect(i!.width, closeTo(80, 1e-9));
      expect(i.height, closeTo(30, 1e-9));

      final tall = resizeTransform(sel.bounds, ResizeHandle.bottom,
          Vec2(0, sel.bounds.bottom + sel.bounds.height));
      final (_, t2) = transformSelection(page, sel, tall).textChanges.single;
      expect(t2!.fontSize, 14);
      expect(t2.width, 80);
    });

    test('font never shrinks below the minimum', () {
      final page = samplePage();
      final sel = Selection.fromPage(page, pageId: pageId, textIds: ['t1']);
      final m = Affine2.scaling(0.1, 0.1, pivot: sel.bounds.topLeft);
      final (_, t) = transformSelection(page, sel, m).textChanges.single;
      expect(t!.fontSize, 4);
    });

    test('identity or empty selection is an empty edit', () {
      final page = samplePage();
      expect(
          transformSelection(page, selectAll(page), Affine2.identity).isEmpty,
          isTrue);
      expect(
          transformSelection(
                  page, Selection.empty(pageId), moveTransform(1, 1))
              .isEmpty,
          isTrue);
      expect(SelectionEdit().toCommand(pageId, label: 'x'), isNull);
    });

    test('toCommand applies and undoes as one step', () {
      final page = samplePage();
      final original = page.copy();
      final doc = docWith(page);
      final stack = CommandStack();
      final edit = transformSelection(page, selectAll(page), moveTransform(10, 0));
      stack.execute(edit.toCommand(pageId, label: 'Move selection')!, doc);
      expect(page.strokeById('plain')!.raw.first.x, 20);
      expect(page.textById('t1')!.x, 110);
      expect(page.imageById('i1')!.x, 110);
      expect(stack.undoDepth, 1);
      stack.undo(doc);
      expect(page.strokes, original.strokes);
      expect(page.texts, original.texts);
      expect(page.images, original.images);
    });
  });

  group('recolor / restore / delete', () {
    test('recolor changes pen strokes and text, not highlighters', () {
      final page = samplePage();
      final edit = recolorSelection(page, selectAll(page), 0xFFE53935);
      expect(edit.strokesBefore.map((s) => s.id), ['tidy', 'plain']);
      expect(edit.strokesAfter.every((s) => s.color == 0xFFE53935), isTrue);
      // Geometry untouched.
      expect(identical(edit.strokesAfter.first.raw, edit.strokesBefore.first.raw),
          isTrue);
      final (_, t) = edit.textChanges.single;
      expect(t!.color, 0xFFE53935);
      expect(edit.imageChanges, isEmpty);

      final withHl = recolorSelection(page, selectAll(page), 0xFFE53935,
          includeHighlighters: true);
      expect(withHl.strokesBefore.map((s) => s.id), contains('hl'));
    });

    test('recolor skips things that already have the colour', () {
      final page = samplePage();
      final edit = recolorSelection(page, selectAll(page), 0xFF1E1E1E);
      expect(edit.strokesBefore.map((s) => s.id), ['tidy']);
      expect(edit.textChanges, isEmpty);
    });

    test('restore original puts points back to raw and clears shapes', () {
      final shape = strokeOf('shape', linePoints(0, 0, 30, 2)).copyWith(
          points: [InkPoint(0, 0, 0.5, 0), InkPoint(30, 0, 0.5, 80)],
          shape: ShapeKind.line);
      final page = samplePage()..strokes.add(shape);
      final edit = restoreOriginalSelection(page, selectAll(page));
      final ids = edit.strokesBefore.map((s) => s.id).toList();
      // 'plain' and 'hl' already show their raw points: nothing to do.
      expect(ids, ['tidy', 'shape']);
      for (final s in edit.strokesAfter) {
        expect(s.pointsAreRaw, isTrue, reason: s.id);
        expect(s.shape, isNull);
      }
      final restored = edit.strokesAfter.first;
      expect(restored.points, same(restored.raw));
    });

    test('delete removes strokes and items; undo restores order', () {
      final page = samplePage();
      final original = page.copy();
      final doc = docWith(page);
      final stack = CommandStack();
      final sel = Selection.fromPage(page,
          pageId: pageId, strokeIds: ['tidy', 'hl'], textIds: ['t1']);
      final edit = deleteSelection(page, sel);
      stack.execute(edit.toCommand(pageId, label: 'Delete')!, doc);
      expect(page.strokes.map((s) => s.id), ['plain']);
      expect(page.texts, isEmpty);
      expect(page.images, hasLength(1));
      stack.undo(doc);
      expect(page.strokes, original.strokes);
      expect(page.texts, original.texts);
    });
  });
}
