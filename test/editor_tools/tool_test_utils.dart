import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';

/// Shared builders and matchers for the editor tool tests.

/// A pen (or highlighter) stroke through [pts], 8 ms apart, pressure 0.5.
Stroke strokeOf(
  String id,
  List<Vec2> pts, {
  double size = 2,
  StrokeTool tool = StrokeTool.pen,
  int color = 0xFF1E1E1E,
  int msPerPoint = 8,
}) {
  return Stroke(
    id: id,
    tool: tool,
    color: color,
    size: size,
    raw: [
      for (var i = 0; i < pts.length; i++)
        InkPoint(pts[i].x, pts[i].y, 0.5, i * msPerPoint),
    ],
  );
}

/// Points from (x0, y0) to (x1, y1), about [spacing] apart (ends included).
List<Vec2> linePoints(double x0, double y0, double x1, double y1,
    {double spacing = 2}) {
  final a = Vec2(x0, y0), b = Vec2(x1, y1);
  final n = math.max(1, (a.distanceTo(b) / spacing).ceil());
  return [for (var i = 0; i <= n; i++) a.lerp(b, i / n)];
}

/// Joins polylines, skipping a duplicated joint.
List<Vec2> joinPaths(List<List<Vec2>> parts) {
  final out = <Vec2>[];
  for (final part in parts) {
    for (final p in part) {
      if (out.isNotEmpty && out.last.distanceTo(p) < 1e-9) continue;
      out.add(p);
    }
  }
  return out;
}

/// Matches a [Vec2] within [eps] of ([x], [y]).
Matcher vecCloseTo(double x, double y, [double eps = 1e-6]) =>
    _VecCloseTo(Vec2(x, y), eps);

class _VecCloseTo extends Matcher {
  _VecCloseTo(this.expected, this.eps);

  final Vec2 expected;
  final double eps;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) =>
      item is Vec2 && item.distanceTo(expected) <= eps;

  @override
  Description describe(Description description) =>
      description.add('a Vec2 within $eps of $expected');
}
