import 'dart:math' as math;
import 'dart:typed_data';

import 'ink_point.dart';
import 'line_style.dart';

/// The marks that [line] draws along the base path [points] with a pen
/// [size] points wide.
///
/// Each element is one polyline to stroke with the pen's width (the renderer
/// outlines every one with perfect_freehand, see
/// `render/stroke_outline.dart`); a one-point polyline is a dot. A solid
/// line returns `[points]` itself.
///
/// Pure Dart. Every generated point carries the pressure and time of the base
/// path at its arc-length position. Lengths are in points. Never throws and
/// never returns a non-finite coordinate: non-finite input points are
/// dropped, and a path with fewer than two distinct points (or shorter than
/// a thousandth of a point) is a tap, which stays a dot whatever the style.
///
/// * [LineStyle.dashed]: dashes whose length and gap are stretched a little
///   so the first one starts at the beginning of the path and the last one
///   ends at its end (a path shorter than one dash is one dash).
/// * [LineStyle.dotted]: one-point polylines, evenly spaced, the first on the
///   start and the last on the end of the path.
/// * [LineStyle.wavy] / [LineStyle.zigzag]: one polyline, a whole number of
///   waves, starting and ending on the base path.
/// * [LineStyle.parallel]: two polylines either side of the base path, with
///   mitred corners.
///
/// [smooth] smooths a hand-drawn base path before waves and parallel lines
/// are laid along it; it must be false for generated shapes (rectangles keep
/// their corners).
///
/// [fit] false keeps the pattern's nominal pitch from the start of the path
/// and cuts it off wherever the path ends, instead of fitting a whole number
/// of dashes / dots / waves. The live layer uses it while a stroke is still
/// growing, so what is already drawn does not shift under the pen (fitting
/// changes every mark each time the path gets longer).
List<List<InkPoint>> patternPolylines(
  List<InkPoint> points,
  LineSettings line,
  double size, {
  bool smooth = true,
  bool fit = true,
}) {
  if (points.isEmpty) return const [];
  if (line.isSolid) return [points];

  final w = size.isFinite ? math.max(size, _minSize) : _minSize;
  var path = _Path.of(points);
  if (path.length == 0) return const [];
  if (path.total < _tapLength) {
    return [path.length == points.length ? points : path.toList()];
  }
  final followsCurves = line.hasWaveParams || line.style == LineStyle.parallel;
  if (smooth && followsCurves && path.length > 2) path = path.smoothed(w);

  return switch (line.style) {
    LineStyle.solid => [points],
    LineStyle.dashed => _dashes(path, line, w, fit),
    LineStyle.dotted => _dots(path, line, w, fit),
    LineStyle.wavy => [_wave(path, line, w, fit, zigzag: false)],
    LineStyle.zigzag => [_wave(path, line, w, fit, zigzag: true)],
    LineStyle.parallel => _parallel(path, line, w),
  };
}

/// Pens thinner than this are laid out as if they were this wide, so a
/// hairline never asks for a million marks.
const double _minSize = 0.25;

/// Consecutive points closer than this are one point.
const double _samePointDistance = 1e-4;

/// A base path shorter than this is a tap.
const double _tapLength = 1e-3;

/// Coordinates beyond this are not real ink (the spatial index draws the same
/// line), and dropping them keeps every length finite.
const double _maxCoordinate = 1e9;

/// Samples per wave of [LineStyle.wavy].
const int _samplesPerWave = 16;

/// A zigzag follows a curved base path with points at most this far apart.
const double _maxZigzagStep = 3.0;

/// Most marks (dashes, dots) or samples (waves) one stroke may produce; a
/// longer path gets a coarser pattern instead of an endless loop.
const int _maxMarks = 20000;

/// A hand-drawn base path is resampled this far apart (the pen width, kept
/// between these two), then smoothed with [_smoothPasses] passes of the
/// `[1, 2, 1] / 4` filter.
const double _minSmoothStep = 0.75;
const double _maxSmoothStep = 3.0;
const int _smoothPasses = 2;

/// Miter lengths of a double line stop growing at this multiple of the
/// half gap (a very sharp turn is not allowed to shoot a spike).
const double _maxMiterScale = 2.0;

/// A path whose end points are closer than this, and which has at least
/// [_minClosedPoints] points, is a closed shape (the double line then mitres
/// its first corner too).
const double _closedDistance = 1e-3;
const int _minClosedPoints = 4;

/// Two vertices closer than this to a mark's end are not added a second time.
const double _vertexSlop = 1e-6;

/// A vertex this close to the straight line through its neighbours counts as
/// part of a straight run.
const double _straightTolerance = 1e-3;

/// The lines of a double line are subdivided to steps of about this many
/// points (the spacing of the points of a generated shape).
const double _ringStep = 2.0;

List<List<InkPoint>> _dashes(
    _Path path, LineSettings line, double w, bool fit) {
  final dash = line.dashLength(w), gap = line.gapLength(w);
  final total = path.total;
  if (total <= dash) return [path.toList()];
  final pitch = dash + gap;
  final int n;
  final double k; // the factor that stretches dash and gap
  if (fit) {
    // n dashes and n - 1 gaps fill the path exactly: k * (n * pitch - gap).
    n = math.min(math.max(1, ((total + gap) / pitch).round()), _maxMarks);
    k = total / (n * pitch - gap);
  } else {
    k = math.max(1.0, total / (_maxMarks * pitch));
    n = (total / (pitch * k)).ceil();
  }
  return [
    for (var i = 0; i < n; i++)
      path.slice(i * pitch * k,
          fit && i == n - 1 ? total : math.min(i * pitch * k + dash * k, total)),
  ];
}

List<List<InkPoint>> _dots(_Path path, LineSettings line, double w, bool fit) {
  final total = path.total, spacing = line.dotSpacing(w);
  final int n;
  final double step;
  if (fit) {
    n = math.min(math.max(1, (total / spacing).round()), _maxMarks);
    step = total / n;
  } else {
    step = math.max(spacing, total / _maxMarks);
    n = (total / step + 1e-9).floor();
  }
  return [
    for (var j = 0; j <= n; j++) [path.at(j * step)],
  ];
}

/// The wave of [LineStyle.wavy] (a sine) or [LineStyle.zigzag] (a triangle
/// wave) laid along [path], as one polyline.
List<InkPoint> _wave(_Path path, LineSettings line, double w, bool fit,
    {required bool zigzag}) {
  final total = path.total;
  final amplitude = _finiteOr(line.amplitude(w), 0);
  var wavelength = math.max(_finiteOr(line.wavelength(w), 2 * w), 2 * w);
  if (fit) wavelength = total / math.max(1, (total / wavelength).round());

  // A zigzag needs a point at every quarter wave, and extra points between
  // them so it stays on a curved base path.
  final quarter = wavelength / 4;
  final natural = zigzag
      ? quarter / math.max(1, (quarter / _maxZigzagStep).ceil())
      : wavelength / _samplesPerWave;
  final step = math.max(natural, total / _maxMarks);
  final samples = math.max(1, (total / step - 1e-9).ceil());
  final out = <InkPoint>[];
  for (var k = 0; k <= samples; k++) {
    final pos = math.min(k * step, total);
    final turn = pos / wavelength;
    final offset =
        amplitude * (zigzag ? _triangle(turn) : math.sin(2 * math.pi * turn));
    final q = path.sample(pos);
    out.add(InkPoint(q.x + q.nx * offset, q.y + q.ny * offset, q.p, q.t.round()));
  }
  return out;
}

/// A triangle wave of period 1 that is 0 at 0, 1 at a quarter, 0 at a half
/// and -1 at three quarters, so a zigzag has its vertices every quarter wave.
double _triangle(double turn) {
  final f = turn - turn.floorToDouble();
  return f < 0.25 ? 4 * f : (f < 0.75 ? 2 - 4 * f : 4 * f - 4);
}

/// Two copies of [base], half the line gap to each side. At a corner the
/// offset is the miter point, `1 / cos(half the turning angle)` times the
/// half gap, so the two lines stay parallel round it.
///
/// Offsetting every vertex of a straight run would leave tiny backwards steps
/// next to an inner corner (its neighbours are nearer to the corner than the
/// half gap), which perfect_freehand draws as ragged ears. So straight runs
/// are offset by their end points only, and the offset lines are then
/// subdivided again: perfect_freehand also needs a regular point between two
/// sharp corners (its corner cap reads the direction of the last regular
/// point, so a stroke of consecutive corners comes out as slanted wedges).
List<List<InkPoint>> _parallel(_Path base, LineSettings line, double w) {
  final half = line.lineGap(w) / 2;
  final path = base.withoutStraightVertices();
  final n = path.length;
  if (n < 2) return [base.toList()];
  final nx = Float64List(n - 1), ny = Float64List(n - 1);
  for (var i = 0; i < n - 1; i++) {
    final dx = path.x[i + 1] - path.x[i], dy = path.y[i + 1] - path.y[i];
    final d = math.sqrt(dx * dx + dy * dy); // at least _samePointDistance
    nx[i] = -dy / d;
    ny[i] = dx / d;
  }
  final closed = n >= _minClosedPoints &&
      (path.x[0] - path.x[n - 1]).abs() < _closedDistance &&
      (path.y[0] - path.y[n - 1]).abs() < _closedDistance;

  final left = <InkPoint>[], right = <InkPoint>[];
  for (var i = 0; i < n; i++) {
    final before = i > 0 ? i - 1 : (closed ? n - 2 : -1);
    final after = i < n - 1 ? i : (closed ? 0 : -1);
    var ox = 0.0, oy = 0.0;
    if (before < 0 || after < 0) {
      final seg = before < 0 ? after : before;
      ox = nx[seg] * half;
      oy = ny[seg] * half;
    } else {
      // |n1 + n2| is twice the cosine of half the turning angle.
      final bx = nx[before] + nx[after], by = ny[before] + ny[after];
      final bl = math.sqrt(bx * bx + by * by);
      if (bl < 1e-9) {
        // The path doubles back on itself: no miter, keep the old side.
        ox = nx[before] * half;
        oy = ny[before] * half;
      } else {
        final k = math.min(_maxMiterScale, 2 / bl) * half / bl;
        ox = bx * k;
        oy = by * k;
      }
    }
    _addSubdivided(left, path.x[i] + ox, path.y[i] + oy, path.p[i], path.t[i]);
    _addSubdivided(right, path.x[i] - ox, path.y[i] - oy, path.p[i], path.t[i]);
  }
  return [left, right];
}

/// Appends a point to [out], with points between it and the last one so no
/// step is much longer than [_ringStep] (pressure and time interpolated).
void _addSubdivided(
    List<InkPoint> out, double x, double y, double p, double t) {
  if (out.isNotEmpty) {
    final a = out.last;
    final dx = x - a.x, dy = y - a.y;
    final pieces =
        math.max(1, (math.sqrt(dx * dx + dy * dy) / _ringStep).round());
    for (var k = 1; k < pieces; k++) {
      final f = k / pieces;
      out.add(InkPoint(a.x + dx * f, a.y + dy * f,
          a.pressure + (p - a.pressure) * f, (a.t + (t - a.t) * f).round()));
    }
  }
  out.add(InkPoint(x, y, p, t.round()));
}

double _finiteOr(double v, double fallback) => v.isFinite ? v : fallback;

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// A point of a [_Path], with the unit normal of the segment it lies on.
typedef _Sample = ({
  double x,
  double y,
  double p,
  double t,
  double nx,
  double ny,
});

/// The cleaned base path as parallel arrays (only the first [length] entries
/// count): every point finite, neighbours at least [_samePointDistance] apart,
/// with the arc length [s] at each point.
class _Path {
  _Path._(this.x, this.y, this.p, this.t, this.s, this.length);

  /// Cleans the arrays in place (they are not reused by the caller).
  factory _Path._clean(
      Float64List x, Float64List y, Float64List p, Float64List t, int n) {
    final s = Float64List(n);
    var c = 0;
    for (var i = 0; i < n; i++) {
      // Written so that NaN fails the test.
      if (!(x[i].abs() <= _maxCoordinate &&
          y[i].abs() <= _maxCoordinate &&
          p[i].isFinite)) {
        continue;
      }
      if (c > 0) {
        final dx = x[i] - x[c - 1], dy = y[i] - y[c - 1];
        final d = math.sqrt(dx * dx + dy * dy);
        if (d < _samePointDistance) continue;
        s[c] = s[c - 1] + d;
      }
      x[c] = x[i];
      y[c] = y[i];
      p[c] = p[i];
      t[c] = t[i];
      c++;
    }
    return _Path._(x, y, p, t, s, c);
  }

  factory _Path.of(List<InkPoint> points) {
    final n = points.length;
    final x = Float64List(n), y = Float64List(n);
    final p = Float64List(n), t = Float64List(n);
    for (var i = 0; i < n; i++) {
      final q = points[i];
      x[i] = q.x;
      y[i] = q.y;
      p[i] = q.pressure;
      t[i] = q.t.toDouble();
    }
    return _Path._clean(x, y, p, t, n);
  }

  final Float64List x, y, p, t, s;
  final int length;

  double get total => length == 0 ? 0 : s[length - 1];

  List<InkPoint> toList() => [
        for (var i = 0; i < length; i++)
          InkPoint(x[i], y[i], p[i], t[i].round()),
      ];

  /// The last segment `i` (from point `i` to `i + 1`) that starts at or
  /// before arc length [pos].
  int _segmentAt(double pos) {
    var lo = 0, hi = length - 2;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (s[mid] <= pos) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// The point at arc length [pos] (clamped to the path).
  _Sample sample(double pos) {
    final i = _segmentAt(pos);
    final f = _clamp01((pos - s[i]) / (s[i + 1] - s[i]));
    final dx = x[i + 1] - x[i], dy = y[i + 1] - y[i];
    final d = math.sqrt(dx * dx + dy * dy);
    return (
      x: x[i] + dx * f,
      y: y[i] + dy * f,
      p: p[i] + (p[i + 1] - p[i]) * f,
      t: t[i] + (t[i + 1] - t[i]) * f,
      nx: -dy / d,
      ny: dx / d,
    );
  }

  InkPoint at(double pos) {
    final q = sample(pos);
    return InkPoint(q.x, q.y, q.p, q.t.round());
  }

  /// The base path between arc lengths [a] and [b], with interpolated end
  /// points.
  List<InkPoint> slice(double a, double b) {
    final out = <InkPoint>[at(a)];
    for (var i = _segmentAt(a) + 1; i < length && s[i] < b - _vertexSlop; i++) {
      if (s[i] > a + _vertexSlop) {
        out.add(InkPoint(x[i], y[i], p[i], t[i].round()));
      }
    }
    out.add(at(b));
    return out;
  }

  /// This path without the points that lie on the straight line between
  /// their neighbours (a generated line or rectangle keeps its ends and
  /// corners). The ends are always kept.
  _Path withoutStraightVertices() {
    final rx = Float64List(length), ry = Float64List(length);
    final rp = Float64List(length), rt = Float64List(length);
    var c = 0;
    for (var i = 0; i < length; i++) {
      if (i > 0 && i < length - 1 && _isStraight(rx[c - 1], ry[c - 1], i)) {
        continue;
      }
      rx[c] = x[i];
      ry[c] = y[i];
      rp[c] = p[i];
      rt[c] = t[i];
      c++;
    }
    return _Path._clean(rx, ry, rp, rt, c);
  }

  /// Whether point [i] lies between (ax, ay) and the next point, within
  /// [_straightTolerance] of the line through them.
  bool _isStraight(double ax, double ay, int i) {
    final abx = x[i] - ax, aby = y[i] - ay;
    final acx = x[i + 1] - ax, acy = y[i + 1] - ay;
    final ac2 = acx * acx + acy * acy;
    if (ac2 < _samePointDistance * _samePointDistance) return false;
    final along = (abx * acx + aby * acy) / ac2;
    if (along <= 0 || along >= 1) return false; // a turn back, not a straight run
    return (abx * acy - aby * acx).abs() / math.sqrt(ac2) <= _straightTolerance;
  }

  /// A hand-drawn path made smooth enough to lay a wave along: resampled
  /// evenly, then smoothed with the `[1, 2, 1] / 4` filter, end points fixed.
  _Path smoothed(double w) {
    final spacing = math.min(math.max(w, _minSmoothStep), _maxSmoothStep);
    final m = math.min(math.max(1, (total / spacing).round()), _maxMarks);
    final rx = Float64List(m + 1), ry = Float64List(m + 1);
    final rp = Float64List(m + 1), rt = Float64List(m + 1);
    for (var k = 0; k <= m; k++) {
      final q = sample(total * k / m);
      rx[k] = q.x;
      ry[k] = q.y;
      rp[k] = q.p;
      rt[k] = q.t;
    }
    for (var pass = 0; pass < _smoothPasses; pass++) {
      var px = rx[0], py = ry[0];
      for (var k = 1; k < m; k++) {
        final cx = rx[k], cy = ry[k];
        rx[k] = (px + 2 * cx + rx[k + 1]) / 4;
        ry[k] = (py + 2 * cy + ry[k + 1]) / 4;
        px = cx;
        py = cy;
      }
    }
    return _Path._clean(rx, ry, rp, rt, m + 1);
  }
}
