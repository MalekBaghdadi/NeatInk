import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/render/paper_painter.dart';

/// A canvas that records the calls [paintPaper] makes.
class RecordingCanvas implements Canvas {
  final List<(Rect, Color)> rects = [];
  final List<(Path, Paint)> paths = [];
  final List<(List<Offset>, Paint)> points = [];

  @override
  void drawRect(Rect rect, Paint paint) => rects.add((rect, paint.color));

  @override
  void drawPath(Path path, Paint paint) => paths.add((path, paint));

  @override
  void drawPoints(ui.PointMode pointMode, List<Offset> pts, Paint paint) =>
      points.add((pts, paint));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  /// Line segments drawn with [color] (each moveTo/lineTo pair is one
  /// contour).
  int segmentsIn(int color) => [
        for (final (path, paint) in paths)
          if (paint.color.toARGB32() == color) path.computeMetrics().length,
      ].fold(0, (a, b) => a + b);

  Paint paintFor(int color) =>
      paths.firstWhere((e) => e.$2.color.toARGB32() == color).$2;
}

RecordingCanvas paint(Paper paper, Size size,
    {double w = a4WidthPt, double h = a4HeightPt}) {
  final canvas = RecordingCanvas();
  PaperPainter(paper, w, h).paint(canvas, size);
  return canvas;
}

void main() {
  const pageSize = Size(a4WidthPt, a4HeightPt);

  test('blank paper is only the background colour', () {
    final c = paint(const Paper(type: PaperType.blank, color: Paper.cream),
        const Size(100, 140));
    expect(c.rects, hasLength(1));
    expect(c.rects.single.$1, const Rect.fromLTWH(0, 0, 100, 140));
    expect(c.rects.single.$2.toARGB32(), Paper.cream);
    expect(c.paths, isEmpty);
    expect(c.points, isEmpty);
  });

  test('lined paper draws every PaperGeometry line at page scale', () {
    const paper = Paper(type: PaperType.lined, spacingPt: 26);
    final geometry = PaperGeometry(paper, a4WidthPt, a4HeightPt);
    final rules =
        geometry.lines.where((l) => l.role == PaperLineRole.rule).length;
    final accents =
        geometry.lines.where((l) => l.role == PaperLineRole.accent).length;

    final c = paint(paper, pageSize);
    expect(c.segmentsIn(paper.lineColor), rules);
    expect(c.segmentsIn(paper.accentColor), accents);
    expect(c.paintFor(paper.lineColor).strokeWidth,
        closeTo(PaperGeometry.strokeWidthFor(PaperLineRole.rule), 1e-5));
    expect(c.paintFor(paper.accentColor).strokeWidth,
        closeTo(PaperGeometry.strokeWidthFor(PaperLineRole.accent), 1e-5));

    // The first ruled line sits exactly where PaperGeometry put it.
    final firstRule = c.paths
        .firstWhere((e) => e.$2.color.toARGB32() == paper.lineColor)
        .$1
        .computeMetrics()
        .first
        .getTangentForOffset(0)!
        .position;
    expect(firstRule.dy, closeTo(geometry.baselines.first, 1e-6));
  });

  test('scales positions to the canvas and keeps hairlines visible', () {
    const paper = Paper(type: PaperType.grid, spacingPt: 20);
    // A 10% preview: 0.6 pt lines would be 0.06 px without the minimum.
    final c = paint(paper, const Size(59.5, 84.2));
    final rulePaint = c.paintFor(paper.lineColor);
    expect(rulePaint.strokeWidth, closeTo(minPaperLineWidth, 1e-5));
    for (final (path, _) in c.paths) {
      final b = path.getBounds();
      expect(b.left, greaterThanOrEqualTo(-0.01));
      expect(b.right, lessThanOrEqualTo(59.5 + 0.01));
      expect(b.bottom, lessThanOrEqualTo(84.2 + 0.01));
    }
  });

  test('zoomed in, line widths grow with the page', () {
    const paper = Paper(type: PaperType.lined);
    final c = paint(paper, pageSize * 3);
    expect(c.paintFor(paper.lineColor).strokeWidth, closeTo(0.6 * 3, 1e-5));
  });

  test('dotted paper draws all dots in one call with a minimum radius', () {
    const paper = Paper(type: PaperType.dotted, spacingPt: 26);
    final dots = PaperGeometry(paper, a4WidthPt, a4HeightPt).dots.length;
    final full = paint(paper, pageSize);
    expect(full.points, hasLength(1));
    expect(full.points.single.$1, hasLength(dots));
    expect(full.points.single.$2.strokeWidth,
        closeTo(PaperGeometry.dotRadius * 2, 1e-5));
    expect(full.points.single.$2.strokeCap, StrokeCap.round);

    final tiny = paint(paper, pageSize * 0.1);
    expect(tiny.points.single.$2.strokeWidth,
        closeTo(minPaperDotRadius * 2, 1e-5));
  });

  test('dark paper uses its light ruling colours', () {
    const paper = Paper(type: PaperType.cornell, color: Paper.dark);
    final c = paint(paper, pageSize);
    expect(c.rects.single.$2.toARGB32(), Paper.dark);
    expect(c.segmentsIn(0x40FFFFFF), greaterThan(0));
    expect(c.segmentsIn(paper.accentColor), 3);
  });

  test('every paper type paints without errors, including degenerate sizes',
      () {
    for (final type in PaperType.values) {
      for (final color in Paper.colors) {
        paint(Paper(type: type, color: color), const Size(120, 170));
      }
    }
    expect(paint(const Paper(), Size.zero).rects, isEmpty);
    // A zero page size fills the background but draws no ruling.
    final c = paint(const Paper(), const Size(10, 10), w: 0, h: 0);
    expect(c.rects, hasLength(1));
    expect(c.paths, isEmpty);
  });

  test('shouldRepaint only when the paper or page size changes', () {
    final a = PaperPainter(const Paper(), a4WidthPt, a4HeightPt);
    expect(a.shouldRepaint(PaperPainter(const Paper(), a4WidthPt, a4HeightPt)),
        isFalse);
    expect(
        a.shouldRepaint(PaperPainter(
            const Paper(type: PaperType.grid), a4WidthPt, a4HeightPt)),
        isTrue);
    expect(
        a.shouldRepaint(
            PaperPainter(const Paper(spacingPt: 32), a4WidthPt, a4HeightPt)),
        isTrue);
    expect(a.shouldRepaint(PaperPainter(const Paper(), 612, 792)), isTrue);
  });
}
