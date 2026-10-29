import 'dart:math' as math;

import '../beautify/resample.dart' show finiteBounds;
import '../ink/ink_point.dart';
import '../ink/stroke.dart';
import 'stroke_grouping.dart';

/// All tuning numbers of [findArrows], in x-heights of the line.
class ArrowConfig {
  const ArrowConfig({
    this.minLength = 1.4,
    this.straightness = 0.35,
    this.maxSlope = 0.3,
    this.headReach = 1.8,
    this.headReachOfShaft = 0.9,
    this.pastTip = 1.0,
    this.headStrokeMax = 2.6,
    this.barbRise = 0.12,
    this.tipOnShaft = 0.4,
    this.overshoot = 0.6,
    this.coneSlope = 2.0,
    this.coneSlack = 0.45,
    this.barbDepth = 0.12,
    this.barbSlant = 0.3,
    this.tipZone = 0.2,
    this.tipNarrow = 0.75,
    this.lineReachAbove = 2.2,
    this.lineReachBelow = 0.8,
  });

  /// A shaft is a straight run of a stroke at least this long...
  final double minLength;

  /// ...(its ink stays within this of a straight line: a hand's wobble and
  /// a sagging shaft are straight, a head's turn is not)...
  final double straightness;

  /// ...nearly level with the line of writing (rise over run).
  final double maxSlope;

  /// The head lies at most this far back from the shaft's end (and at most
  /// [headReachOfShaft] of the shaft: a short arrow has a small head)...
  final double headReach;
  final double headReachOfShaft;

  /// ...and its tip at most this far beyond it (a head drawn as its own
  /// stroke often lands a little past the shaft).
  final double pastTip;

  /// A head drawn as strokes of their own: each no bigger than this.
  final double headStrokeMax;

  /// The head has ink both above and below the shaft by at least this much
  /// (the two barbs)...
  final double barbRise;

  /// ...meeting at a tip on the shaft's line (within this much)...
  final double tipOnShaft;

  /// ...that the shaft does not run past by more than this (a t-bar runs
  /// on past the stem crossing it)...
  final double overshoot;

  /// ...and the barbs open out from the tip: no head ink strays further
  /// from the shaft than [coneSlope] times its distance behind the tip plus
  /// [coneSlack]. A letter's stem crossing the end of a long t-bar has ink
  /// far above and below right at the end (Mariam's "the").
  final double coneSlope;
  final double coneSlack;

  /// Each barb reaches back at least this far behind the tip, and every point
  /// of a barb lies behind it by at least [barbSlant] times its distance
  /// from the shaft (beyond [tipOnShaft]).
  final double barbDepth;
  final double barbSlant;

  /// Near the tip (within [tipZone] of the head's depth behind it) the head
  /// is at most [tipNarrow] of its full height: the barbs meet there.
  final double tipZone;
  final double tipNarrow;

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

/// The horizontal arrows written in [line] (v1.9.0, Mariam's notes): a
/// straight, level run of a stroke along the line with a head at one end or
/// both, drawn in the same stroke or as one or two small strokes of their
/// own at the tip, or a stroke the pen snapped to an arrow. The recogniser
/// does not read arrows (it saw them as nothing or a dash), so the app takes
/// them out of the picture and puts the arrow into the text where it was. A
/// line without a head is a dash or an underline, not an arrow.
///
/// v1.10.0: found 2 of Mariam's 8 test arrows. The shaft is now the longest
/// straight run of the stroke (not the middle of its box, which a one-stroke
/// arrow's head bent), it may be shorter (1.4 x-heights), and the head may
/// be big, flat or steep, a closed triangle, two separate barbs, or land a
/// little past the shaft; a letter written close after the tip no longer
/// spoils it (each nearby stroke is tried on its own and in pairs).
///
/// v1.11.0 (Mariam: one-stroke arrows "sometimes" found): a head drawn back
/// over its first barb no longer passes for more shaft (a straight run goes
/// one way), small and flat heads count (barbs from 0.12 x-heights out), and
/// every stroke that fits joins the head. A head is checked for its shape:
/// barbs above and below the tip, each reaching back, the ink narrow at the
/// tip (a c or an e after a dash is open there).
List<LineArrow> findArrows(RecognizedLine line, {ArrowConfig config = const ArrowConfig()}) {
  final xh = line.xHeight;
  if (!xh.isFinite || xh <= 0) return const [];
  final used = <Stroke>{};
  final out = <LineArrow>[];
  final shafts = [
    for (final s in line.inkStrokes) ?_shaftOf(s, line, xh, config),
  ]..sort((a, b) => b.length.compareTo(a.length));
  for (final shaft in shafts) {
    if (used.contains(shaft.stroke)) continue;
    List<Stroke>? headAt(_End end) => _headAt(shaft, end, [
          for (final o in line.inkStrokes)
            if (!identical(o, shaft.stroke) && !used.contains(o) && _near(o, shaft, end, xh, config)) o,
        ], xh, config);
    final right = headAt(shaft.right);
    final left = headAt(shaft.left);
    if (right == null && left == null) continue;
    final strokes = [shaft.stroke, ...?right, ...?left];
    used.addAll(strokes);
    out.add(LineArrow(
        strokes, right != null && left != null ? 0 : (right != null ? 1 : -1), (shaft.left.x + shaft.right.x) / 2));
  }
  return out;
}

/// One end of a shaft: the point, the unit vector pointing out of the
/// shaft there, and the stroke's ink beyond it (the part of the shaft's
/// stroke attached at this end).
class _End {
  const _End(this.x, this.y, this.dx, this.dy, this.attached);

  final double x;
  final double y;
  final double dx;
  final double dy;
  final List<InkPoint> attached;

  /// How far [x], [y] lies out beyond this end along the shaft (negative:
  /// behind it), and its signed distance from the shaft's line.
  (double, double) frame(double px, double py) {
    final ax = px - x, ay = py - y;
    return (ax * dx + ay * dy, ax * -dy + ay * dx);
  }
}

/// A straight level run of [stroke], from [left] to [right].
class _Shaft {
  const _Shaft(this.stroke, this.left, this.right, this.length);

  final Stroke stroke;
  final _End left;
  final _End right;
  final double length;
}

_Shaft? _shaftOf(Stroke s, RecognizedLine line, double xh, ArrowConfig config) {
  final pts = [
    for (final p in s.points)
      if (p.x.isFinite && p.y.isFinite) p,
  ];
  if (pts.length < 2) return null;
  final b = finiteBounds(pts);
  if (b == null || b.right - b.left < config.minLength * xh) return null;
  // The longest straight run that is long enough and level enough: a chain
  // of the stroke's corners whose ink stays near the chord between its ends.
  final corners = _simplify(pts, 0.5 * config.straightness * xh);
  int? from, to;
  var best = 0.0;
  for (var a = 0; a < corners.length; a++) {
    for (var z = corners.length - 1; z > a; z--) {
      final i = corners[a], j = corners[z];
      final dx = pts[j].x - pts[i].x, dy = pts[j].y - pts[i].y;
      final length = math.sqrt(dx * dx + dy * dy);
      if (length < config.minLength * xh || length <= best) continue;
      if (dx.abs() < 1e-9 || (dy / dx - line.baselineSlope).abs() > config.maxSlope) continue;
      if (!_straight(pts, i, j, config.straightness * xh)) continue;
      best = length;
      from = i;
      to = j;
    }
  }
  if (from == null || to == null) return null;
  // Along the line of writing, not far above or under it.
  final p = pts[from], q = pts[to];
  final midX = (p.x + q.x) / 2, midY = (p.y + q.y) / 2;
  final baseline = line.baselineAt(midX);
  if (midY < baseline - config.lineReachAbove * xh || midY > baseline + config.lineReachBelow * xh) return null;
  final ux = (q.x - p.x) / best, uy = (q.y - p.y) / best;
  // [p] is the end the stroke's earlier ink hangs on, [q] the later ink's.
  final atP = _End(p.x, p.y, -ux, -uy, pts.sublist(0, from));
  final atQ = _End(q.x, q.y, ux, uy, pts.sublist(to + 1));
  return p.x <= q.x ? _Shaft(s, atP, atQ, best) : _Shaft(s, atQ, atP, best);
}

/// Douglas-Peucker: the indices of [pts] where the polyline turns by more
/// than [tolerance] (first and last included), in order.
List<int> _simplify(List<InkPoint> pts, double tolerance) {
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = keep[pts.length - 1] = true;
  final stack = <(int, int)>[(0, pts.length - 1)];
  while (stack.isNotEmpty) {
    final (a, z) = stack.removeLast();
    if (z - a < 2) continue;
    var far = -1;
    var farDist = tolerance;
    for (var i = a + 1; i < z; i++) {
      final d = _toSegment(pts[i], pts[a], pts[z]);
      if (d > farDist) {
        farDist = d;
        far = i;
      }
    }
    if (far < 0) continue;
    keep[far] = true;
    stack
      ..add((a, far))
      ..add((far, z));
  }
  return [
    for (var i = 0; i < pts.length; i++)
      if (keep[i]) i,
  ];
}

/// Whether the points of [pts] from [i] to [j] all lie within [tolerance]
/// of the segment between those two and go one way along it: a barb drawn
/// back over itself and out again lies along the shaft's line, but the pen
/// went back (v1.11.0: such a run took the first barb for more shaft).
bool _straight(List<InkPoint> pts, int i, int j, double tolerance) {
  final dx = pts[j].x - pts[i].x, dy = pts[j].y - pts[i].y;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 1e-9) return false;
  var furthest = 0.0;
  for (var k = i + 1; k < j; k++) {
    if (_toSegment(pts[k], pts[i], pts[j]) > tolerance) return false;
    final along = ((pts[k].x - pts[i].x) * dx + (pts[k].y - pts[i].y) * dy) / len;
    if (along < furthest - tolerance) return false;
    furthest = math.max(furthest, along);
  }
  return true;
}

/// Distance from [p] to the segment [a]-[b] (not to its line: a point past
/// the end of a stroke's run, like an arrow's tip, is far from it).
double _toSegment(InkPoint p, InkPoint a, InkPoint b) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final len2 = dx * dx + dy * dy;
  final t = len2 < 1e-12 ? 0.0 : (((p.x - a.x) * dx + (p.y - a.y) * dy) / len2).clamp(0.0, 1.0);
  final ex = a.x + t * dx - p.x, ey = a.y + t * dy - p.y;
  return math.sqrt(ex * ex + ey * ey);
}

/// How far back from [end] a head may reach on [shaft].
double _reach(_Shaft shaft, double xh, ArrowConfig config) =>
    math.min(config.headReach * xh, config.headReachOfShaft * shaft.length);

/// Whether [o] is a small stroke at [end] of [shaft]: all of it within the
/// head's reach behind the end and [ArrowConfig.pastTip] beyond it.
bool _near(Stroke o, _Shaft shaft, _End end, double xh, ArrowConfig config) {
  final b = finiteBounds(o.points);
  if (b == null) return false;
  if (b.right - b.left > config.headStrokeMax * xh || b.bottom - b.top > config.headStrokeMax * xh) return false;
  final reach = _reach(shaft, xh, config);
  for (final p in o.points) {
    if (!p.x.isFinite || !p.y.isFinite) continue;
    final (out, side) = end.frame(p.x, p.y);
    if (out < -reach || out > config.pastTip * xh || side.abs() > config.headStrokeMax * xh) return false;
  }
  return true;
}

/// The strokes that draw a head at [end] of [shaft]: the shaft's own ink
/// beyond the end, with none, one or two of the [nearby] strokes; null when
/// no such set draws a head (see [_isHead]).
List<Stroke>? _headAt(_Shaft shaft, _End end, List<Stroke> nearby, double xh, ArrowConfig config) {
  final reach = _reach(shaft, xh, config);
  // The shaft's own ink beyond this end counts while it stays near it.
  final attached = [
    for (final p in end.attached)
      if (p.x.isFinite && p.y.isFinite) p,
  ];
  for (final p in attached) {
    final (out, side) = end.frame(p.x, p.y);
    if (out < -reach || out > config.pastTip * xh || side.abs() > config.headStrokeMax * xh) {
      // The stroke goes on into something else (a letter): no head here.
      return null;
    }
  }
  bool head(List<Stroke> extra) => _isHead(end, [
        ...attached,
        for (final s in extra) ...s.points.where((p) => p.x.isFinite && p.y.isFinite),
      ], extra.isNotEmpty, xh, config);
  // The smallest set that draws a head...
  List<Stroke>? found;
  if (attached.isNotEmpty && head(const [])) {
    found = [];
  } else {
    for (final o in nearby) {
      if (head([o])) {
        found = [o];
        break;
      }
    }
    if (found == null) {
      outer:
      for (var i = 0; i < nearby.length; i++) {
        for (var j = i + 1; j < nearby.length; j++) {
          if (head([nearby[i], nearby[j]])) {
            found = [nearby[i], nearby[j]];
            break outer;
          }
        }
      }
    }
  }
  if (found == null) return null;
  // ... then every other stroke there that is part of it too (the second
  // barb, drawn apart): left out, it would be read as a letter.
  var whole = found;
  for (final o in nearby) {
    if (!whole.contains(o) && head([...whole, o])) whole = [...whole, o];
  }
  return whole;
}

/// Whether the ink [points] around [end] is an arrow head: barbs above and
/// below the shaft that meet at a tip on the shaft's line, at or a little
/// beyond the end ([separate]: drawn as strokes of their own, which may
/// stop short of a shaft that runs on by [ArrowConfig.overshoot]), and slope
/// back from there.
bool _isHead(_End end, List<InkPoint> points, bool separate, double xh, ArrowConfig config) {
  if (points.isEmpty) return false;
  final frame = [for (final p in points) end.frame(p.x, p.y)];
  // The tip: the head's ink furthest out (of near ties, the one nearest the
  // shaft); a head drawn on in the shaft's stroke starts from its end.
  var tipOut = frame.map((f) => f.$1).reduce(math.max);
  var tipSide = 0.0;
  if (!separate && tipOut < 0) {
    tipOut = 0;
  } else {
    tipSide = double.infinity;
    for (final (out, side) in frame) {
      if (out >= tipOut - 0.1 * xh && side.abs() < tipSide.abs()) tipSide = side;
    }
  }
  if (separate && tipOut < -config.overshoot * xh) return false;
  if (tipSide.abs() > config.tipOnShaft * xh) return false;
  // Each barb reaches out to one side of the tip and back from it.
  var depthAbove = 0.0, depthBelow = 0.0;
  var depth = 0.0, top = tipSide, bottom = tipSide;
  for (final (out, side) in frame) {
    final behind = tipOut - out;
    if (side.abs() > config.coneSlope * math.max(behind, 0) + config.coneSlack * xh) return false;
    depth = math.max(depth, behind);
    top = math.min(top, side);
    bottom = math.max(bottom, side);
    if (side.abs() <= config.barbRise * xh) continue;
    // A barb slopes back from the tip; a letter's stem stands upright.
    if (behind < config.barbSlant * (side.abs() - config.tipOnShaft * xh)) return false;
    final rise = side - tipSide;
    if (rise < -config.barbRise * xh) depthAbove = math.max(depthAbove, behind);
    if (rise > config.barbRise * xh) depthBelow = math.max(depthBelow, behind);
  }
  if (depthAbove < config.barbDepth * xh || depthBelow < config.barbDepth * xh) return false;
  // The barbs meet at the tip: close to it the head is narrow. A c or an e
  // after a dash has ink above and below there too, but it is open at the
  // front (v1.11.0: "- c" was typed as "→ c").
  var nearTop = tipSide, nearBottom = tipSide;
  for (final (out, side) in frame) {
    if (tipOut - out > config.tipZone * depth) continue;
    nearTop = math.min(nearTop, side);
    nearBottom = math.max(nearBottom, side);
  }
  return nearBottom - nearTop <= config.tipNarrow * (bottom - top);
}

final RegExp _bothWays = RegExp(r'\s*<[-–—=]+>\s*');
final RegExp _rightward = RegExp(r'\s*(?:[-–—]+|=+)>\s*');
final RegExp _leftward = RegExp(r'\s*<[-–—]+\s*');

/// [text] with arrows the recogniser read as characters (`->`, `-->`, `=>`,
/// `<-`, `<->`) typed as →, ← and ↔ between spaces: an arrow the shape
/// test missed still comes out as an arrow. `<=` stays (less or equal).
String typedArrows(String text) {
  if (!text.contains('>') && !text.contains('<')) return text;
  final out = text
      .replaceAll(_bothWays, ' ↔ ')
      .replaceAll(_rightward, ' → ')
      .replaceAll(_leftward, ' ← ');
  return out == text ? text : out.replaceAll(RegExp(' {2,}'), ' ').trim();
}
