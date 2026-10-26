import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/tools/shape_fitting.dart';
import 'package:neatink/features/editor/tools/shape_geometry.dart';
import 'package:neatink/features/editor/tools/tool_config.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';

import 'tool_test_utils.dart';

List<Vec2> _pos(ShapeResult r) => [for (final p in r.points) p.pos];

void main() {
  group('buildShape', () {
    test('line goes from start to end with even spacing', () {
      final r = buildShape(ShapeKind.line, const Vec2(10, 10), const Vec2(110, 10),
          t0: 0, t1: 1000)!;
      expect(r.kind, ShapeKind.line);
      expect(r.points.first.pos, vecCloseTo(10, 10));
      expect(r.points.last.pos, vecCloseTo(110, 10));
      expect(r.points.first.t, 0);
      expect(r.points.last.t, 1000);
      for (var i = 1; i < r.points.length; i++) {
        expect(r.points[i].pos.distanceTo(r.points[i - 1].pos),
            lessThanOrEqualTo(2.0 + 1e-6));
        expect(r.points[i].t, greaterThanOrEqualTo(r.points[i - 1].t));
        expect(r.points[i].pressure, closeTo(0.5, 1e-6));
      }
    });

    test('too-short or non-finite drags build nothing', () {
      expect(buildShape(ShapeKind.line, const Vec2(0, 0), const Vec2(0.5, 0)),
          isNull);
      expect(
          buildShape(ShapeKind.rectangle, const Vec2(0, 0),
              const Vec2(double.nan, 5)),
          isNull);
      // A flat box has no rectangle, ellipse or triangle.
      for (final k in [
        ShapeKind.rectangle,
        ShapeKind.ellipse,
        ShapeKind.triangle
      ]) {
        expect(buildShape(k, const Vec2(0, 0), const Vec2(50, 0.2)), isNull);
      }
    });

    test('arrow: shaft then two barbs of the configured geometry', () {
      const cfg = ToolConfig.defaults;
      final r = buildShape(ShapeKind.arrow, const Vec2(0, 0), const Vec2(100, 0))!;
      final pts = _pos(r);
      expect(pts.first, vecCloseTo(0, 0));
      // The tip is visited twice (shaft end, between barbs).
      final tipVisits = pts.where((p) => p.distanceTo(const Vec2(100, 0)) < 1e-6);
      expect(tipVisits.length, 2);
      // Barb ends are barbLength from the tip, angle from the shaft.
      final barb = (100 * cfg.arrowBuildBarbFraction)
          .clamp(cfg.arrowBuildMinBarbPt, cfg.arrowBuildMaxBarbPt);
      final far = pts
          .where((p) => p.x < 100 && p.y.abs() > 1e-6)
          .reduce((a, b) => a.y.abs() > b.y.abs() ? a : b);
      expect(far.distanceTo(const Vec2(100, 0)), closeTo(barb, 0.5));
      final ang = math.atan2(far.y.abs(), 100 - far.x) * 180 / math.pi;
      expect(ang, closeTo(cfg.arrowBuildBarbAngleDeg, 1));
      // Barbs lie on both sides of the shaft.
      expect(pts.any((p) => p.y > 1), isTrue);
      expect(pts.any((p) => p.y < -1), isTrue);
    });

    test('arrow barbs are clamped for tiny and huge arrows', () {
      const cfg = ToolConfig.defaults;
      double longestBarb(double len) {
        final r = buildShape(
            ShapeKind.arrow, const Vec2(0, 0), Vec2(len, 0))!;
        return _pos(r)
            .where((p) => p.y.abs() > 1e-6)
            .map((p) => p.distanceTo(Vec2(len, 0)))
            .reduce(math.max);
      }

      // Short shaft: barb is the minimum (but never longer than needed).
      expect(longestBarb(20), closeTo(cfg.arrowBuildMinBarbPt, 0.5));
      expect(longestBarb(2000), closeTo(cfg.arrowBuildMaxBarbPt, 0.5));
    });

    test('rectangle fills the drag box and starts at the drag start', () {
      final r = buildShape(
          ShapeKind.rectangle, const Vec2(200, 150), const Vec2(100, 50))!;
      final pts = _pos(r);
      expect(pts.first, vecCloseTo(200, 150));
      expect(pts.last, vecCloseTo(200, 150));
      for (final p in pts) {
        expect(p.x, inInclusiveRange(100 - 1e-6, 200 + 1e-6));
        expect(p.y, inInclusiveRange(50 - 1e-6, 150 + 1e-6));
      }
      for (final c in const [
        Vec2(100, 50),
        Vec2(200, 50),
        Vec2(200, 150),
        Vec2(100, 150)
      ]) {
        expect(pts.any((p) => p.distanceTo(c) < 1e-6), isTrue,
            reason: 'corner $c');
      }
    });

    test('ellipse is closed and every point satisfies the ellipse equation',
        () {
      final r = buildShape(
          ShapeKind.ellipse, const Vec2(0, 0), const Vec2(200, 100))!;
      final pts = _pos(r);
      expect(pts.first.distanceTo(pts.last), lessThan(0.01));
      for (final p in pts) {
        final v = math.pow((p.x - 100) / 100, 2) + math.pow((p.y - 50) / 50, 2);
        expect(v, closeTo(1, 0.01));
      }
      // Starts at the top (t0 = -pi/2).
      expect(pts.first, vecCloseTo(100, 0, 0.01));
    });

    test('triangle is isosceles with its apex at the top middle', () {
      final r = buildShape(
          ShapeKind.triangle, const Vec2(0, 0), const Vec2(100, 80))!;
      final pts = _pos(r);
      expect(pts.first, vecCloseTo(50, 0));
      expect(pts.last, vecCloseTo(50, 0));
      expect(pts.any((p) => p.distanceTo(const Vec2(100, 80)) < 1e-6), isTrue);
      expect(pts.any((p) => p.distanceTo(const Vec2(0, 80)) < 1e-6), isTrue);
    });

    test('applyTo keeps id and raw, replaces points, sets the shape', () {
      final hand = strokeOf('s1', [
        const Vec2(0, 0),
        const Vec2(30, 2),
        const Vec2(60, -1),
        const Vec2(100, 1),
      ]);
      final shape =
          buildShape(ShapeKind.line, const Vec2(0, 0), const Vec2(100, 0))!;
      final snapped = shape.applyTo(hand);
      expect(snapped.id, 's1');
      expect(snapped.shape, ShapeKind.line);
      expect(snapped.raw, hand.raw);
      expect(snapped.points, shape.points);
      expect(snapped.pointsAreRaw, isFalse);
    });
  });

  group('StrokeTiming', () {
    test('interpolates by arc length and never goes backwards', () {
      final timing = StrokeTiming.fromPoints(const [
        InkPoint(0, 0, 0.5, 0),
        InkPoint(10, 0, 0.5, 100),
        InkPoint(40, 0, 0.5, 400),
      ]);
      expect(timing.timeAt(0), 0);
      expect(timing.timeAt(0.25), 100);
      expect(timing.timeAt(1), 400);
      expect(timing.timeAt(2), 400);
      expect(timing.timeAt(-1), 0);
    });

    test('degenerate inputs are safe', () {
      expect(StrokeTiming.fromPoints(const []).timeAt(0.5), 0);
      final dot = StrokeTiming.fromPoints(const [
        InkPoint(1, 1, 0.5, 5),
        InkPoint(1, 1, 0.5, 9),
      ]);
      expect(dot.timeAt(0.5), inInclusiveRange(5, 9));
    });
  });

  group('shape_fitting', () {
    test('douglasPeucker keeps the corners of an L', () {
      final pts = joinPaths([
        linePoints(0, 0, 100, 0),
        linePoints(100, 0, 100, 80),
      ]);
      final keep = douglasPeucker(pts, 1);
      expect(keep.length, 3);
      expect(pts[keep[1]], vecCloseTo(100, 0));
    });

    test('douglasPeuckerClosed finds the 4 corners of a rectangle', () {
      final loop = joinPaths([
        linePoints(0, 0, 100, 0),
        linePoints(100, 0, 100, 60),
        linePoints(100, 60, 0, 60),
        linePoints(0, 60, 0, 0),
      ]);
      loop.removeLast();
      final keep = douglasPeuckerClosed(loop, 1);
      final corners = [for (final i in keep) loop[i]];
      for (final c in const [
        Vec2(0, 0),
        Vec2(100, 0),
        Vec2(100, 60),
        Vec2(0, 60)
      ]) {
        expect(corners.any((p) => p.distanceTo(c) < 1e-6), isTrue,
            reason: 'corner $c');
      }
    });

    test('fitLine recovers a noisy diagonal line', () {
      final rng = math.Random(3);
      final pts = [
        for (var i = 0; i <= 50; i++)
          Vec2(i * 2.0 + rng.nextDouble() - 0.5, i * 2.0 + rng.nextDouble() - 0.5),
      ];
      final fit = fitLine(pts)!;
      expect(fit.dir.x.abs(), closeTo(math.sqrt1_2, 0.02));
      expect(fit.dir.y.abs(), closeTo(math.sqrt1_2, 0.02));
      expect(fit.signedDistance(const Vec2(50, 50)).abs(), lessThan(1));
      expect(fitLine([const Vec2(1, 1)]), isNull);
    });

    test('LineFit.intersect', () {
      const a = LineFit(Vec2(0, 0), Vec2(1, 0));
      const b = LineFit(Vec2(5, -3), Vec2(0, 1));
      expect(a.intersect(b), vecCloseTo(5, 0));
      expect(a.intersect(const LineFit(Vec2(0, 4), Vec2(1, 0))), isNull);
    });

    test('snapAngle snaps within tolerance only', () {
      const step = math.pi / 4;
      expect(snapAngle(0.03, step, 0.07), 0);
      expect(snapAngle(math.pi / 4 + 0.05, step, 0.07), math.pi / 4);
      expect(snapAngle(0.3, step, 0.07), 0.3);
    });

    test('totalTurning of a loop is about 2 pi', () {
      final circle = [
        for (var i = 0; i < 64; i++)
          Vec2(math.cos(i * math.pi / 32), math.sin(i * math.pi / 32)) * 50,
      ];
      expect(totalTurning(circle, closed: true).abs(), closeTo(2 * math.pi, 0.01));
    });

    test('fitEllipse recovers a rotated ellipse', () {
      const theta = 0.5;
      final pts = [
        for (var i = 0; i < 100; i++)
          Vec2(80 * math.cos(i * 2 * math.pi / 100),
                      40 * math.sin(i * 2 * math.pi / 100))
                  .rotate(theta) +
              const Vec2(300, 200),
      ];
      final fit = fitEllipse(pts)!;
      expect(fit.center, vecCloseTo(300, 200, 0.5));
      expect(fit.a, closeTo(80, 0.5));
      expect(fit.b, closeTo(40, 0.5));
    });
  });
}
