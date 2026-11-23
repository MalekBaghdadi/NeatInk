import 'dart:math' as math;
import 'dart:ui' show PathMetric, PointMode, Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_model.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_painter.dart';

import 'ruler_test_utils.dart';

void main() {
  const screen = Size(1000, 800);
  RulerModel shownModel([Size view = screen]) {
    final model = RulerModel()..show(view);
    addTearDown(model.dispose);
    return model;
  }

  TestRecordingCanvas paintOnce(RulerPainter painter, [Size size = screen]) {
    final canvas = TestRecordingCanvas();
    painter.paint(canvas, size);
    return canvas;
  }

  List<Invocation> calls(TestRecordingCanvas canvas, Symbol name) => [
        for (final r in canvas.invocations)
          if (r.invocation.memberName == name) r.invocation,
      ];

  /// The tick path the painter drew.
  Path ticksOf(TestRecordingCanvas canvas) {
    final paths = calls(canvas, #drawPath);
    expect(paths.length, 1, reason: 'the ticks are one path');
    return paths.single.positionalArguments[0] as Path;
  }

  group('what is drawn', () {
    test('nothing while the ruler is hidden', () {
      final model = RulerModel();
      addTearDown(model.dispose);
      final painter = RulerPainter(model: model);
      addTearDown(painter.dispose);
      expect(paintOnce(painter).invocations, isEmpty);
    });

    test('the body is a rounded band as long and wide as the ruler', () {
      final model = shownModel();
      final painter = RulerPainter(model: model);
      addTearDown(painter.dispose);
      final canvas = paintOnce(painter);
      final bodies = calls(canvas, #drawRRect);
      expect(bodies.length, 2, reason: 'a faint fill and a hairline outline');
      final rrect = bodies.first.positionalArguments[0] as RRect;
      expect(rrect.width, closeTo(920, 1e-9));
      expect(rrect.height, 96);
      expect(rrect.center, offsetCloseTo(Offset.zero));
      expect(rrect.tlRadius.x, 10);
    });

    test('it is drawn about the ruler\'s centre, turned by its angle', () {
      final model = shownModel()..rotateBy(rad(30));
      final painter = RulerPainter(model: model);
      addTearDown(painter.dispose);
      final canvas = paintOnce(painter);
      final translate = calls(canvas, #translate).first;
      expect(translate.positionalArguments,
          [model.geometry.center.dx, model.geometry.center.dy]);
      expect(calls(canvas, #rotate).first.positionalArguments.single,
          closeTo(rad(30), 1e-12));
      // Every save has its restore.
      expect(canvas.getSaveCount(), 0);
    });

    test('ticks every millimetre, longer every 5 mm, longest every cm', () {
      final model = shownModel();
      final painter = RulerPainter(model: model);
      addTearDown(painter.dispose);
      final metrics = ticksOf(paintOnce(painter)).computeMetrics().toList();
      // Half the ruler is 460 px: 73 mm, 6.2992 px each. Per side and edge:
      // 73 ticks, and one at the middle for each edge.
      expect(metrics.length, 2 + 4 * 73);
      int count(double length) =>
          metrics.where((m) => (m.length - length).abs() < 1e-9).length;
      // Centimetres: the middle (2 edges) and 7 per side and edge.
      expect(count(16), 2 + 7 * 4);
      // Half centimetres: 7 per side and edge.
      expect(count(10), 7 * 4);
      expect(count(6), metrics.length - 30 - 28);
    });

    test('a centimetre is 160 / 2.54 px apart, counted from the middle', () {
      final model = shownModel();
      final painter = RulerPainter(model: model);
      addTearDown(painter.dispose);
      final metrics = ticksOf(paintOnce(painter)).computeMetrics().toList();
      // The long ticks of the top edge (they start at y = -48).
      final xs = <double>[
        for (final PathMetric m in metrics)
          if ((m.length - 16).abs() < 1e-9 &&
              (m.getTangentForOffset(0)!.position.dy + 48).abs() < 1e-9)
            m.getTangentForOffset(0)!.position.dx,
      ]..sort();
      expect(xs.length, 15);
      // (The engine keeps paths in single precision.)
      for (var k = -7; k <= 7; k++) {
        expect(xs[k + 7], closeTo(k * rulerPxPerCm, 1e-3));
      }
      expect(rulerPxPerCm, closeTo(62.992, 1e-3));
    });

    test('the two scales hang from the two edges, mirrored', () {
      final model = shownModel();
      final painter = RulerPainter(model: model);
      addTearDown(painter.dispose);
      final bounds = ticksOf(paintOnce(painter)).getBounds();
      expect(bounds.top, -48);
      expect(bounds.bottom, 48);
      expect(bounds.left, closeTo(-73 * rulerPxPerCm / 10, 1e-3));
      expect(bounds.right, closeTo(73 * rulerPxPerCm / 10, 1e-3));
      final metrics = ticksOf(paintOnce(painter)).computeMetrics().toList();
      final fromTop = metrics.where(
          (m) => (m.getTangentForOffset(0)!.position.dy + 48).abs() < 1e-9);
      final fromBottom = metrics.where(
          (m) => (m.getTangentForOffset(0)!.position.dy - 48).abs() < 1e-9);
      expect(fromTop.length, fromBottom.length);
      expect(fromTop.length + fromBottom.length, metrics.length);
      // Ticks on the bottom edge point up.
      final up = fromBottom.first.getTangentForOffset(fromBottom.first.length)!;
      expect(up.position.dy, lessThan(48));
    });

    test('numbers count outward from the middle, 7 per side and edge', () {
      final model = shownModel();
      final painter = RulerPainter(model: model);
      addTearDown(painter.dispose);
      final canvas = paintOnce(painter);
      // 4 numbers' worth per centimetre (two sides, two edges) and the badge.
      expect(calls(canvas, #drawParagraph).length, 4 * 7 + 1);
      // The bottom scale is turned half a turn, about each number.
      final turns = [
        for (final c in calls(canvas, #rotate))
          if (((c.positionalArguments.single as double) - math.pi).abs() < 1e-12) c,
      ];
      expect(turns.length, 2 * 7);
    });

    test('a number that would not fit is left out', () {
      final model = RulerModel()..show(const Size(380, 800));
      addTearDown(model.dispose);
      // Length 360: half 180 px: 2 cm (126 px) fit, 3 cm (189 px) don't.
      final painter = RulerPainter(model: model);
      addTearDown(painter.dispose);
      expect(calls(paintOnce(painter), #drawParagraph).length, 4 * 2 + 1);
    });

    test('the longest ruler has 11 cm on each side', () {
      final model = RulerModel()..show(const Size(3000, 2000));
      addTearDown(model.dispose);
      final painter = RulerPainter(model: model);
      addTearDown(painter.dispose);
      final canvas = paintOnce(painter);
      expect(calls(canvas, #drawParagraph).length, 4 * 11 + 1);
      expect(ticksOf(canvas).computeMetrics().length, 2 + 4 * 119);
    });

    test('a ruler too short for numbers still draws ticks and the badge', () {
      final model = RulerModel()..show(const Size(30, 400));
      addTearDown(model.dispose);
      expect(model.geometry.length, 30);
      final painter = RulerPainter(model: model);
      addTearDown(painter.dispose);
      final canvas = paintOnce(painter);
      expect(calls(canvas, #drawParagraph).length, 1);
      expect(ticksOf(canvas).computeMetrics().length, 2 + 4 * 2);
    });

    test('the badge is a dotted circle that is not turned with the ruler', () {
      final model = shownModel()..rotateBy(rad(45));
      final painter = RulerPainter(model: model);
      addTearDown(painter.dispose);
      final canvas = paintOnce(painter);
      final dots = calls(canvas, #drawPoints).single;
      expect(dots.positionalArguments[0], PointMode.points);
      final points = dots.positionalArguments[1] as List<Offset>;
      expect(points.length, 24);
      for (final p in points) {
        expect((p - model.geometry.center).distance, closeTo(16, 1e-9));
      }
      // It is drawn after the turned ruler was restored.
      final firstDots = canvas.invocations
          .indexWhere((r) => r.invocation.memberName == #drawPoints);
      final lastRestore = canvas.invocations
          .lastIndexWhere((r) => r.invocation.memberName == #restore);
      expect(firstDots, greaterThan(lastRestore));
    });
  });

  group('colours', () {
    test('are the same on every paper and in every theme', () {
      final model = shownModel();
      final painter = RulerPainter(model: model);
      addTearDown(painter.dispose);
      final canvas = paintOnce(painter);
      final fill = calls(canvas, #drawRRect).first.positionalArguments[1] as Paint;
      // (A paint stores its colour as 8-bit channels.)
      expect(fill.color.toARGB32(), RulerPainter.bodyColor.toARGB32());
      final ticks = calls(canvas, #drawPath).single.positionalArguments[1] as Paint;
      expect(ticks.color.toARGB32(), RulerPainter.inkColor.toARGB32());
      expect(ticks.style, PaintingStyle.stroke);
    });
  });

  group('the badge text', () {
    test('has no decimals for a whole angle', () {
      expect(RulerPainter.angleLabel(0), '0°');
      expect(RulerPainter.angleLabel(15), '15°');
      expect(RulerPainter.angleLabel(90.0), '90°');
      expect(RulerPainter.angleLabel(150), '150°');
    });

    test('has one decimal otherwise', () {
      expect(RulerPainter.angleLabel(37.5), '37.5°');
      expect(RulerPainter.angleLabel(12.3), '12.3°');
      expect(RulerPainter.angleLabel(179.9), '179.9°');
      expect(RulerPainter.angleLabel(0.1), '0.1°');
    });
  });

  group('repainting', () {
    test('the painter repaints when the model changes', () {
      final model = shownModel();
      final painter = RulerPainter(model: model);
      addTearDown(painter.dispose);
      var repaints = 0;
      painter.addListener(() => repaints++);
      model.translate(const Offset(10, 0));
      model.rotateBy(rad(20));
      model.hide();
      expect(repaints, 3);
    });

    test('shouldRepaint compares the model', () {
      final model = shownModel();
      final other = shownModel();
      final a = RulerPainter(model: model);
      addTearDown(a.dispose);
      final same = RulerPainter(model: model);
      addTearDown(same.dispose);
      final elsewhere = RulerPainter(model: other);
      addTearDown(elsewhere.dispose);
      expect(a.shouldRepaint(same), isFalse);
      expect(a.shouldRepaint(elsewhere), isTrue);
    });

    test('painting again, and after dispose, works', () {
      final model = shownModel();
      final painter = RulerPainter(model: model);
      paintOnce(painter);
      model.rotateBy(rad(20));
      expect(calls(paintOnce(painter), #drawParagraph).length, 29);
      painter.dispose();
      painter.dispose();
      expect(calls(paintOnce(painter), #drawParagraph).length, 29);
      painter.dispose();
    });

    test('every angle paints without trouble', () {
      final model = shownModel();
      final painter = RulerPainter(model: model);
      addTearDown(painter.dispose);
      for (var deg = 0; deg < 720; deg += 7) {
        model.rotateBy(rad(7));
        model.translate(Offset(deg.isEven ? 3 : -3, 1));
        final canvas = paintOnce(painter);
        expect(calls(canvas, #drawParagraph), isNotEmpty);
        expect(canvas.getSaveCount(), 0);
      }
    });
  });

  group('the overlay', () {
    Widget host(RulerModel model, {ThemeData? theme, Size? size, Widget? below}) =>
        MaterialApp(
          theme: theme,
          home: Center(
            child: SizedBox.fromSize(
              size: size ?? screen,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ?below,
                  RulerOverlay(model: model),
                ],
              ),
            ),
          ),
        );

    RenderObject rulerPaint(WidgetTester tester) => tester.renderObject(find
        .descendant(
            of: find.byType(RulerOverlay), matching: find.byType(CustomPaint))
        .first);

    testWidgets('paints nothing while hidden and the ruler once shown',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final model = RulerModel();
      addTearDown(model.dispose);
      await tester.pumpWidget(host(model));
      expect(rulerPaint(tester), paintsNothing);

      model.show(screen);
      await tester.pump();
      expect(rulerPaint(tester), paints..rrect()..rrect()..path()..paragraph());

      model.hide();
      await tester.pump();
      expect(rulerPaint(tester), paintsNothing);
    });

    testWidgets('follows the ruler as it moves', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final model = shownModel();
      await tester.pumpWidget(host(model));
      final before = model.geometry.center;
      expect(rulerPaint(tester),
          paints..translate(x: before.dx, y: before.dy));
      model.translate(const Offset(30, 50));
      await tester.pump();
      expect(rulerPaint(tester),
          paints..translate(x: before.dx + 30, y: before.dy + 50));
    });

    testWidgets('does not take pointer events', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final model = shownModel();
      var taps = 0;
      await tester.pumpWidget(host(model,
          below: GestureDetector(
              behavior: HitTestBehavior.opaque, onTap: () => taps++)));
      final centre = tester.getTopLeft(find.byType(RulerOverlay)) +
          model.geometry.center;
      await tester.tapAt(centre);
      expect(taps, 1, reason: 'the tap went through the ruler');
    });

    testWidgets('fits the ruler to the size of the view', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final model = shownModel();
      final before = model.geometry.length;
      expect(before, closeTo(920, 1e-9));
      await tester.pumpWidget(host(model, size: const Size(500, 600)));
      await tester.pump();
      expect(model.viewport, const Size(500, 600));
      expect(model.geometry.length, 500);
      // The view grows again: the ruler is not stretched back.
      await tester.pumpWidget(host(model, size: const Size(900, 700)));
      await tester.pump();
      expect(model.viewport, const Size(900, 700));
      expect(model.geometry.length, 500);
    });

    testWidgets('builds in the light and the dark theme', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final model = shownModel();
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(host(model,
            theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.indigo, brightness: brightness))));
        await tester.pump();
        expect(rulerPaint(tester), paints..rrect());
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('can be removed while the ruler shows', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final model = shownModel();
      await tester.pumpWidget(host(model));
      await tester.pumpWidget(const SizedBox());
      // The model outlives the overlay and keeps working.
      model.translate(const Offset(5, 5));
      expect(tester.takeException(), isNull);
    });
  });
}
