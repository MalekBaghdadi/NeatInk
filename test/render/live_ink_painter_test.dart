import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/features/editor/canvas/live_ink.dart';
import 'package:neatink/features/editor/canvas/stroke_builder.dart';
import 'package:neatink/features/editor/canvas/stroke_constraint.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/line_style.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/render/stroke_outline.dart';

/// Records what [LiveInkPainter] fills.
class RecordingCanvas extends Fake implements Canvas {
  final List<(Path, Paint)> paths = [];
  int saves = 0, restores = 0;
  Rect? clip;

  @override
  void save() => saves++;

  @override
  void restore() => restores++;

  @override
  void clipRect(Rect rect, {ClipOp clipOp = ClipOp.intersect, bool doAntiAlias = true}) =>
      clip = rect;

  @override
  void drawPath(Path path, Paint paint) => paths.add((path, paint));
}

const Size pageSize = Size(595, 842);

/// A live pen stroke along y = 100 from x = 10 to [endX].
ActiveStroke activeStroke(
  LiveInk live, {
  LineStyle style = LineStyle.dashed,
  double endX = 110,
  StrokeTool tool = StrokeTool.pen,
  double concentration = 1,
  StrokeConstraint? constraint,
}) {
  final builder = StrokeBuilder(
      pageWidth: 595, pageHeight: 842, startTime: Duration.zero);
  for (var x = 10.0; x <= endX; x += 2) {
    builder.add(x, 100, 0.5, Duration(milliseconds: (x * 4).round()));
  }
  final active = ActiveStroke(
    pageId: 'p',
    page: const PageMeta(id: 'p'),
    tool: tool,
    penStyle: PenStyle.technical,
    color: 0xFF112233,
    size: 2,
    builder: builder,
    pointer: 1,
    live: live,
    line: LineSettings(style: style),
    concentration: concentration,
    constraint: constraint,
  );
  live.begin(active);
  return active;
}

/// The preview a ruler line (or a snapped shape) would show: a straight
/// 100 pt line from x = 10.
Stroke linePreview(ActiveStroke active) => active.current.copyWith(
      points: [
        for (var x = 10.0; x <= 110; x += 2) InkPoint(x, 100, 0.5, 0),
      ],
      shape: ShapeKind.line,
    );

List<Rect> contourBounds(Path path) => [
      for (final m in path.computeMetrics())
        m.extractPath(0, m.length).getBounds(),
    ];

RecordingCanvas paint(LiveInk live, StrokeTool tool) {
  final canvas = RecordingCanvas();
  LiveInkPainter(live, tool).paint(canvas, pageSize);
  return canvas;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a solid stroke', () {
    test('is painted as the one outline it always was', () {
      final live = LiveInk();
      final active = activeStroke(live, style: LineStyle.solid);
      final canvas = paint(live, StrokeTool.pen);
      expect(canvas.paths, hasLength(1));
      final (path, _) = canvas.paths.single;
      expect(path.computeMetrics().length, 1);
      final expected = outlinePath(strokeOutline(active.current, isComplete: false));
      expect(path.getBounds(), expected.getBounds());
    });

    test('is clipped to the page and drawn in its own fill colour', () {
      final live = LiveInk();
      final active = activeStroke(live, style: LineStyle.solid, concentration: 0.5);
      final canvas = paint(live, StrokeTool.pen);
      expect(canvas.clip, Offset.zero & pageSize);
      expect(canvas.saves, 1);
      expect(canvas.restores, 1);
      expect(canvas.paths.single.$2.color.toARGB32(),
          strokeFillColor(active.current).toARGB32());
      expect(canvas.paths.single.$2.color.a, closeTo(0.5, 1e-9));
    });
  });

  group('a pattern while the stroke grows', () {
    test('is drawn dash by dash at its own pitch', () {
      final live = LiveInk();
      activeStroke(live);
      final canvas = paint(live, StrokeTool.pen);
      final dashes = contourBounds(canvas.paths.single.$1);
      // 100 pt from x = 10: dashes 6.8 pt long (8.8 with the caps) every
      // 12.6 pt. The eighth starts at 98.2 and ends at 105, short of the pen.
      expect(dashes, hasLength(8));
      expect(dashes[1].left - dashes[0].left, closeTo(12.6, 0.05));
      expect(dashes.first.left, closeTo(9, 0.05));
      expect(dashes.first.width, closeTo(8.8, 0.05));
      expect(dashes.last.right, closeTo(105 + 1, 0.05));
    });

    test('keeps the dashes already drawn where they are', () {
      final live = LiveInk();
      final active = activeStroke(live, endX: 60);
      final before = contourBounds(paint(live, StrokeTool.pen).paths.single.$1);
      for (var x = 62.0; x <= 140; x += 2) {
        active.builder.add(x, 100, 0.5, Duration(milliseconds: (x * 4).round()));
      }
      live.markChanged();
      final after = contourBounds(paint(live, StrokeTool.pen).paths.single.$1);
      expect(after.length, greaterThan(before.length));
      for (var i = 0; i < before.length - 1; i++) {
        expect(after[i], before[i], reason: 'dash $i');
      }
    });

    test('a ruler line (a constrained stroke) is not refitted either', () {
      final live = LiveInk();
      final active = activeStroke(live, constraint: const HorizontalConstraint(100));
      active.preview = linePreview(active);
      final dashes = contourBounds(paint(live, StrokeTool.pen).paths.single.$1);
      expect(dashes[1].left - dashes[0].left, closeTo(12.6, 0.05));
    });

    test('waves, dots and a double line are drawn too', () {
      for (final style in [
        LineStyle.dotted,
        LineStyle.wavy,
        LineStyle.zigzag,
        LineStyle.parallel,
      ]) {
        final live = LiveInk();
        activeStroke(live, style: style);
        final canvas = paint(live, StrokeTool.pen);
        expect(canvas.paths, hasLength(1), reason: style.name);
        expect(canvas.paths.single.$1.computeMetrics().length, greaterThan(0),
            reason: style.name);
      }
    });
  });

  group('a snapped shape', () {
    test('is final, so its pattern is fitted to it', () {
      final live = LiveInk();
      final active = activeStroke(live); // no constraint: hold-to-snap
      active.preview = linePreview(active);
      final dashes = contourBounds(paint(live, StrokeTool.pen).paths.single.$1);
      // Fitted: the first dash starts on the line's first point and the last
      // one ends on its last point.
      expect(dashes.first.left, closeTo(10 - 1, 0.05));
      expect(dashes.last.right, closeTo(110 + 1, 0.05));
      expect(dashes, hasLength(8)); // (100 + 5.8) / 12.6 rounds to 8
      // And the dashes are stretched to do it: 8 * 12.6 - 5.8 = 95 fits 100.
      const k = 100 / (8 * 12.6 - 5.8);
      expect(dashes.first.width, closeTo(6.8 * k + 2, 0.05));
    });
  });

  group('nothing to draw', () {
    test('another tool\'s stroke is not painted', () {
      final live = LiveInk();
      activeStroke(live);
      expect(paint(live, StrokeTool.highlighter).paths, isEmpty);
    });

    test('no active stroke, no points', () {
      expect(paint(LiveInk(), StrokeTool.pen).paths, isEmpty);
      final live = LiveInk();
      final builder = StrokeBuilder(
          pageWidth: 595, pageHeight: 842, startTime: Duration.zero);
      live.begin(ActiveStroke(
        pageId: 'p',
        page: const PageMeta(id: 'p'),
        tool: StrokeTool.pen,
        penStyle: PenStyle.ballpoint,
        color: 0xFF000000,
        size: 2,
        builder: builder,
        pointer: 1,
        live: live,
      ));
      expect(paint(live, StrokeTool.pen).paths, isEmpty);
    });

    test('a pen that can draw nothing paints nothing', () {
      final live = LiveInk();
      final builder = StrokeBuilder(
          pageWidth: 595, pageHeight: 842, startTime: Duration.zero)
        ..add(10, 10, 0.5, Duration.zero)
        ..add(50, 10, 0.5, const Duration(milliseconds: 10));
      live.begin(ActiveStroke(
        pageId: 'p',
        page: const PageMeta(id: 'p'),
        tool: StrokeTool.pen,
        penStyle: PenStyle.technical,
        color: 0xFF000000,
        size: 0,
        builder: builder,
        pointer: 1,
        live: live,
        line: const LineSettings(style: LineStyle.dashed),
      ));
      expect(paint(live, StrokeTool.pen).paths, isEmpty);
    });
  });
}
