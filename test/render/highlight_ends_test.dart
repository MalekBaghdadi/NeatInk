import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/tool_prefs.dart';
import 'package:neatink/features/editor/tools/highlight_tidy.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:neatink/render/stroke_outline.dart';

import '../editor/integrations/erase_select/harness.dart';

// v1.14.0: the owner asked for highlights with half-circle ends instead of
// square ones, "and some more options": square, round and slanted ends.

/// A straight highlighter swipe from (x0, y) to (x1, y), [size] wide.
Stroke band(double x0, double x1, {double y = 100, double size = 20, HighlightEnds ends = HighlightEnds.square}) {
  const n = 25;
  return Stroke(
    id: 'h',
    tool: StrokeTool.highlighter,
    highlightEnds: ends,
    color: 0xFFFFEB3B,
    size: size,
    raw: [for (var i = 0; i < n; i++) InkPoint(x0 + (x1 - x0) * i / (n - 1), y, 0.5, i * 10)],
  );
}

Rect boundsOf(List<Offset> pts) => Rect.fromLTRB(
      pts.map((p) => p.dx).reduce(math.min),
      pts.map((p) => p.dy).reduce(math.min),
      pts.map((p) => p.dx).reduce(math.max),
      pts.map((p) => p.dy).reduce(math.max),
    );

/// Shoelace area (absolute).
double areaOf(List<Offset> pts) {
  var a = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i], q = pts[(i + 1) % pts.length];
    a += p.dx * q.dy - q.dx * p.dy;
  }
  return a.abs() / 2;
}

/// The right-most x of the outline within [band] of height [y].
double rightAt(List<Offset> pts, double y, double band) =>
    pts.where((p) => (p.dy - y).abs() <= band).map((p) => p.dx).reduce(math.max);
double leftAt(List<Offset> pts, double y, double band) =>
    pts.where((p) => (p.dy - y).abs() <= band).map((p) => p.dx).reduce(math.min);

void main() {
  const r = 10.0; // half the width
  // How far the slanted corner reaches past the square end: the band's
  // width over tan(60°).
  final slantReach = 2 * r / math.tan(slantedEndAngleDeg * math.pi / 180);

  test('square ends: the band stops where the swipe stops (as before)', () {
    final o = strokeOutline(band(100, 300));
    final b = boundsOf(o);
    expect(b.left, closeTo(100, 0.5));
    expect(b.right, closeTo(300, 0.5));
    expect(b.top, closeTo(90, 0.5));
    expect(b.bottom, closeTo(110, 0.5));
    expect(areaOf(o), closeTo(200 * 2 * r, 30));
  });

  test('round ends: half circles past each end', () {
    final o = strokeOutline(band(100, 300, ends: HighlightEnds.round));
    final b = boundsOf(o);
    expect(b.left, closeTo(100 - r, 0.5));
    expect(b.right, closeTo(300 + r, 0.5));
    // The tips are half circles: every point past an end is r from it.
    expect(rightAt(o, 100, 1), closeTo(300 + r, 0.6));
    for (final p in o.where((p) => p.dx > 300.5)) {
      expect((p - const Offset(300, 100)).distance, closeTo(r, 0.3));
    }
    for (final p in o.where((p) => p.dx < 99.5)) {
      expect((p - const Offset(100, 100)).distance, closeTo(r, 0.3));
    }
    // (No area check: perfect_freehand's round end turns one and a half
    // times, which the shoelace sum counts twice; the fill is the same.)
  });

  for (final reversed in [false, true]) {
    test('slanted ends: "/" at both ends, drawn ${reversed ? 'right to left' : 'left to right'}', () {
      final s = reversed ? band(300, 100, ends: HighlightEnds.slanted) : band(100, 300, ends: HighlightEnds.slanted);
      final o = strokeOutline(s);
      // Top-right corner reaches out, bottom-right stays; the other way
      // round on the left.
      expect(rightAt(o, 90, 1), closeTo(300 + slantReach, 0.8));
      expect(rightAt(o, 110, 1), closeTo(300, 0.8));
      expect(leftAt(o, 110, 1), closeTo(100 - slantReach, 0.8));
      expect(leftAt(o, 90, 1), closeTo(100, 0.8));
      // Exactly the square band plus a triangle at each end: nothing is
      // cut away (the fill is non-zero, and no area cancels).
      final square = areaOf(strokeOutline(band(100, 300)));
      expect(areaOf(o), closeTo(square + 2 * (0.5 * 2 * r * slantReach), 30));
    });
  }

  test('slanted ends on a steep stroke reach out at most one band width', () {
    final o = strokeOutline(Stroke(
      id: 'v',
      tool: StrokeTool.highlighter,
      highlightEnds: HighlightEnds.slanted,
      color: 0xFFFFEB3B,
      size: 20,
      raw: [for (var i = 0; i < 25; i++) InkPoint(100 + i * 0.5, 100 + i * 8.0, 0.5, i * 10)],
    ));
    final b = boundsOf(o);
    expect(b.top, greaterThan(100 - 2 * r - 1));
    expect(b.bottom, lessThan(292 + 2 * r + 1));
  });

  test('a dot or a two-point swipe still draws', () {
    for (final ends in HighlightEnds.values) {
      final dot = Stroke(
        id: 'd',
        tool: StrokeTool.highlighter,
        highlightEnds: ends,
        color: 0xFFFFEB3B,
        size: 20,
        raw: const [InkPoint(50, 50, 0.5, 0)],
      );
      expect(strokeOutline(dot), isNotEmpty, reason: ends.name);
      expect(areaOf(strokeOutline(band(50, 52, ends: ends))), greaterThan(0), reason: ends.name);
    }
  });

  test('saved with the stroke; square (and pens) write nothing, as before', () {
    for (final ends in HighlightEnds.values) {
      final s = band(0, 50, ends: ends);
      final j = s.toJson();
      expect(j.containsKey('ends'), ends != HighlightEnds.square);
      expect(Stroke.fromJson(j).highlightEnds, ends);
    }
    expect(Stroke.fromJson(band(0, 50).toJson()..remove('ends')).highlightEnds, HighlightEnds.square);
    final pen = Stroke(id: 'p', tool: StrokeTool.pen, highlightEnds: HighlightEnds.round, color: 0xFF000000, size: 2, raw: const [InkPoint(0, 0, 0.5, 0)]);
    expect(pen.toJson().containsKey('ends'), isFalse);
    // Moving and copying keep them.
    final round = band(0, 50, ends: HighlightEnds.round);
    expect(round.copyWith(color: 0xFF00FF00).highlightEnds, HighlightEnds.round);
  });

  test('the highlighter remembers the last ends; old settings mean square', () {
    const prefs = HighlighterPrefs(ends: HighlightEnds.slanted);
    expect(HighlighterPrefs.fromJson(prefs.toJson()).ends, HighlightEnds.slanted);
    expect(HighlighterPrefs.fromJson(const {'color': 0xFFFFE600, 'size': 14}).ends, HighlightEnds.square);
  });

  test('over typed text, round ends are pulled in so the band hugs the words', () {
    final line = HighlightLine(left: 100, right: 300, top: 90, bottom: 110, words: const [(left: 100, right: 300)]);
    Stroke? tidy(HighlightEnds ends) => tidyHighlight(
          Stroke(
            id: 'h',
            tool: StrokeTool.highlighter,
            highlightEnds: ends,
            color: 0xFFFFEB3B,
            size: 14,
            raw: [for (var i = 0; i < 20; i++) InkPoint(100 + i * 10.5, 101 + (i.isEven ? 1 : -1), 0.5, i * 10)],
          ),
          [line],
        );
    final square = boundsOf(strokeOutline(tidy(HighlightEnds.square)!));
    final round = tidy(HighlightEnds.round)!;
    expect(round.highlightEnds, HighlightEnds.round);
    final pill = boundsOf(strokeOutline(round));
    // Height of the line either way; the pill reaches a little past the
    // square band (a quarter of its height), not half its height.
    expect(pill.height, closeTo(square.height, 0.5));
    expect(square.left - pill.left, closeTo(0.25 * 20, 0.6));
    expect(pill.right - square.right, closeTo(0.25 * 20, 0.6));
    expect(pill.contains(const Offset(100, 92)) || pill.left < 100, isTrue);
  });

  testWidgets('the highlighter menu sets the ends of the next highlight', (tester) async {
    final h = await EraseSelectHarness.open(tester);
    h.controller.selectTool(EditorTool.highlighter);
    await tester.pump();
    expect(find.byKey(const ValueKey('highlighter-ends')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('highlighter-ends')));
    await tester.pumpAndSettle();
    expect(find.text('Round ends'), findsOneWidget);
    expect(find.text('Slanted ends'), findsOneWidget);
    await tester.tap(find.text('Round ends'));
    await tester.pumpAndSettle();
    expect(h.controller.toolPrefs.highlighter.ends, HighlightEnds.round);

    await h.drag([for (var x = 100.0; x <= 300; x += 20) Vec2(x, 400)]);
    final drawn = h.strokes.where((s) => s.isHighlighter).single;
    expect(drawn.highlightEnds, HighlightEnds.round);
    await h.close();
  });
}
