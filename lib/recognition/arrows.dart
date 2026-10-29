import 'dart:math' as math;

import '../beautify/resample.dart' show finiteBounds;
import '../ink/stroke.dart';
import 'stroke_grouping.dart';

/// All tuning numbers of [findArrows], in x-heights of the line.
class ArrowConfig {
  const ArrowConfig({
    this.minLength = 1.8,
    this.shaftFlatness = 0.45,
    this.maxSlope = 0.25,
    this.headReach = 1.3,
    this.barbRise = 0.35,
    this.tipOnShaft = 0.4,
    this.coneSlope = 1.5,
    this.coneSlack = 0.45,
    this.headStrokeMax = 2.0,
    this.lineReachAbove = 2.2,
    this.lineReachBelow = 0.8,
  });

  /// A shaft is at least this long...
  final double minLength;

  /// ...nearly straight: the middle half of it stays within this band...
  final double shaftFlatness;

  /// ...and nearly level (rise over run).
  final double maxSlope;

  /// The head is looked for this far back from each end of the shaft...
  final double headReach;

  /// ...as ink both above and below the shaft by at least this much (the two
  /// barbs)...
  final double barbRise;

  /// ...meeting at a tip on the shaft's line (within this much).
  final double tipOnShaft;

  /// The barbs open out from the tip: no ink near the end strays further
  /// from the shaft than [coneSlope] times its distance behind the tip plus
  /// [coneSlack] x-heights. A letter's stem crossing the end of a long
  /// t-bar has ink far above and below right at the end (Mariam's "the").
  final double coneSlope;
  final double coneSlack;

  /// A head drawn as a stroke of its own is no bigger than this.
  final double headStrokeMax;

  /// The shaft lies between this far above the baseline and this far below
  /// it: arrows written in the text, not a diagram's arrow under it.
  final double lineReachAbove;
  final double lineReachBelow;
}

/// An arrow written between words (`brain → spinal cord`): its strokes (the
/// shaft and its head, one stroke or several) and where it points.
class LineArrow {
  const LineArrow(this.strokes, this.direction, this.centerX);

  final List<Stroke> strokes;

  /// 1: points right, -1: left, 0: both ways.
  final int direction;

  /// Middle of the shaft (page x), to place it between the words.
  final double centerX;

  /// The arrow as text.
  String get text => switch (direction) {
        1 => '→',
        -1 => '←',
        _ => '↔',
      };
}

/// The horizontal arrows written in [line] (v1.9.0, Mariam's notes): a long,
/// straight, level stroke along the line with a head at one end or both,
/// drawn in the same stroke or as a small stroke of its own at the tip, or a
/// stroke the pen snapped to an arrow. The recogniser does not read arrows
/// (it saw them as nothing or a dash), so the app takes them out of the
/// picture and puts the arrow into the text where it was. A line without a
/// head is a dash or an underline, not an arrow.
List<LineArrow> findArrows(RecognizedLine line, {ArrowConfig config = const ArrowConfig()}) {
  final xh = line.xHeight;
  if (!xh.isFinite || xh <= 0) return const [];
  final used = <Stroke>{};
  final out = <LineArrow>[];
  for (final s in line.inkStrokes) {
    if (used.contains(s)) continue;
    final shaft = _shaftOf(s, line, xh, config);
    if (shaft == null) continue;
    // Small strokes near an end may be the head.
    List<Stroke> headStrokesAt(double tipX) => [
          for (final o in line.inkStrokes)
            if (!identical(o, s) && !used.contains(o))
              if (_near(o, tipX, shaft.yAt(tipX), xh, config)) o,
        ];
    final right = headStrokesAt(shaft.right);
    final left = headStrokesAt(shaft.left);
    final headRight = _headAt(shaft, shaft.right, 1, [s, ...right], xh, config);
    final headLeft = _headAt(shaft, shaft.left, -1, [s, ...left], xh, config);
    if (!headRight && !headLeft) continue;
    final strokes = [s, if (headRight) ...right, if (headLeft) ...left];
    used.addAll(strokes);
    out.add(LineArrow(strokes, headRight && headLeft ? 0 : (headRight ? 1 : -1), (shaft.left + shaft.right) / 2));
  }
  return out;
}

/// A straight level run: y = a + b x between [left] and [right].
class _Shaft {
  const _Shaft(this.a, this.b, this.left, this.right);

  final double a;
  final double b;
  final double left;
  final double right;

  double yAt(double x) => a + b * x;
}

_Shaft? _shaftOf(Stroke s, RecognizedLine line, double xh, ArrowConfig config) {
  final b = finiteBounds(s.points);
  if (b == null) return null;
  final width = b.right - b.left;
  if (width < config.minLength * xh) return null;
  // The middle half: the shaft, whatever the head does at the ends.
  final lo = b.left + 0.25 * width, hi = b.right - 0.25 * width;
  final xs = <double>[], ys = <double>[];
  for (final p in s.points) {
    if (p.x >= lo && p.x <= hi && p.x.isFinite && p.y.isFinite) {
      xs.add(p.x);
      ys.add(p.y);
    }
  }
  if (xs.length < 2) return null;
  // Least-squares line through the middle.
  final n = xs.length;
  final mx = xs.reduce((a, c) => a + c) / n, my = ys.reduce((a, c) => a + c) / n;
  var sxx = 0.0, sxy = 0.0;
  for (var i = 0; i < n; i++) {
    sxx += (xs[i] - mx) * (xs[i] - mx);
    sxy += (xs[i] - mx) * (ys[i] - my);
  }
  final slope = sxx > 0 ? sxy / sxx : 0.0;
  if (slope.abs() > config.maxSlope) return null;
  final a = my - slope * mx;
  var spread = 0.0;
  for (var i = 0; i < n; i++) {
    spread = math.max(spread, (ys[i] - (a + slope * xs[i])).abs());
  }
  if (2 * spread > config.shaftFlatness * xh) return null;
  // Along the line of writing, not far above or under it.
  final mid = (b.left + b.right) / 2;
  final y = a + slope * mid;
  final baseline = line.baselineAt(mid);
  if (y < baseline - config.lineReachAbove * xh || y > baseline + config.lineReachBelow * xh) return null;
  // The barbs are measured from a level parallel to the writing through the
  // shaft's middle: the fitted slope, carried out to a tip, invents a barb
  // from a hand's wobble (a long t-bar in Mariam's notes).
  final level = [for (var i = 0; i < n; i++) ys[i] - line.baselineSlope * xs[i]]..sort();
  return _Shaft(level[n ~/ 2], line.baselineSlope, b.left, b.right);
}

/// Whether [o] is a small stroke at the tip [tipX] of a shaft at [tipY].
bool _near(Stroke o, double tipX, double tipY, double xh, ArrowConfig config) {
  final b = finiteBounds(o.points);
  if (b == null) return false;
  if (b.right - b.left > config.headStrokeMax * xh || b.bottom - b.top > config.headStrokeMax * xh) return false;
  final reach = config.headReach * xh;
  return b.left >= tipX - reach - 0.3 * xh &&
      b.right <= tipX + reach &&
      b.top >= tipY - config.headStrokeMax * xh &&
      b.bottom <= tipY + config.headStrokeMax * xh;
}

/// Whether [strokes] draw a head at the end [tipX] of [shaft] pointing
/// [dir] (1 right, -1 left): ink above and below the shaft just behind the
/// tip, and the ink furthest out on the shaft's line.
bool _headAt(_Shaft shaft, double tipX, int dir, List<Stroke> strokes, double xh, ArrowConfig config) {
  final reach = config.headReach * xh;
  var above = false, below = false;
  double? tip;
  double tipDev = 0;
  for (final s in strokes) {
    for (final p in s.points) {
      final behind = dir > 0 ? tipX - p.x : p.x - tipX;
      if (behind < -0.4 * xh || behind > reach) continue;
      final dev = p.y - shaft.yAt(p.x);
      if (dev.abs() > config.coneSlope * math.max(behind, 0) + config.coneSlack * xh) return false;
      if (dev < -config.barbRise * xh) above = true;
      if (dev > config.barbRise * xh) below = true;
      final out = dir > 0 ? p.x : -p.x;
      if (tip == null || out > tip) {
        tip = out;
        tipDev = dev.abs();
      }
    }
  }
  return above && below && tip != null && tipDev <= config.tipOnShaft * xh;
}
