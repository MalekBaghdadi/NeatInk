import 'dart:collection';

import '../../../ink/ink_point.dart';
import '../../../ink/stroke.dart';
import '../../../ink/vec2.dart';
import 'geometry.dart';
import 'spatial_index.dart';
import 'tool_config.dart';

/// Partial ("pixel") eraser: cuts strokes where the eraser passes and keeps
/// the remaining pieces as new strokes.
///
/// The erased region is the capsule a circle of `radius` sweeps moving from
/// `from` to `to`. A stroke's centre line is cut where it comes within
/// `radius + factor × width / 2` of the sweep (see
/// [ToolConfig.pixelEraserPenWidthFactor]); cuts get an interpolated point
/// exactly on that boundary so the pieces end cleanly.
///
/// Positions along a polyline are measured as `s = i + t`: segment `i`
/// (from point `i` to point `i + 1`) at fraction `t`.

/// Cuts every stroke in [candidates] touched by the sweep.
///
/// Returns original stroke id → remaining pieces (possibly empty), ready for
/// `SpliceStrokesCommand`. Strokes the sweep doesn't touch are absent.
/// Pieces get fresh ids from [newId] and keep the original's tool, pen
/// style, colour, size, word id and tidy info.
Map<String, List<Stroke>> pixelErase({
  required Iterable<Stroke> candidates,
  required Vec2 from,
  required Vec2 to,
  required double radius,
  required String Function() newId,
  ToolConfig config = ToolConfig.defaults,
}) {
  final bounds = sweepBounds(from, to, radius);
  final out = <String, List<Stroke>>{};
  for (final s in candidates) {
    if (!s.paintBounds.overlaps(bounds)) continue;
    final pieces = cutStroke(s, from, to, radius, newId: newId, config: config);
    if (pieces != null) out[s.id] = pieces;
  }
  return out;
}

/// Cuts one stroke. Returns null when the sweep doesn't touch it, otherwise
/// the pieces that remain (empty when it is erased completely).
///
/// Raw/points alignment: when the stroke is not a shape and `raw` and
/// `points` have the same length (always true for untidied and tidied
/// strokes, because tidy moves points one-to-one), both lists are cut at the
/// same positions, so every piece still knows its original ink. Otherwise
/// (snapped shapes) the cut is made on `points`, each piece uses those
/// points as both `raw` and `points`, and the shape kind is dropped: a piece
/// of a rectangle is just a line. Such pieces are marked tidy-locked
/// because their `raw` is no longer hand-drawn ink.
List<Stroke>? cutStroke(
  Stroke stroke,
  Vec2 from,
  Vec2 to,
  double radius, {
  required String Function() newId,
  ToolConfig config = ToolConfig.defaults,
}) {
  final pts = stroke.points;
  if (pts.isEmpty) return null;
  final widthFactor = stroke.isHighlighter
      ? config.pixelEraserHighlighterWidthFactor
      : config.pixelEraserPenWidthFactor;
  final reach = radius + widthFactor * stroke.size / 2;

  if (pts.length == 1) {
    final p = pts.first;
    final d2 =
        distanceSquaredToSegmentXY(p.x, p.y, from.x, from.y, to.x, to.y);
    return d2 <= reach * reach ? const [] : null;
  }

  final erased = _erasedIntervals(pts, from, to, reach);
  if (erased.isEmpty) return null;

  final last = (pts.length - 1).toDouble();
  final kept = <(double, double)>[];
  var cursor = 0.0;
  for (final (a, b) in erased) {
    if (a - cursor > _eps) kept.add((cursor, a));
    cursor = b;
  }
  if (last - cursor > _eps) kept.add((cursor, last));

  final aligned =
      stroke.shape == null && stroke.raw.length == stroke.points.length;
  final pieces = <Stroke>[];
  for (final (a, b) in kept) {
    final piecePoints = _slice(pts, a, b);
    if (piecePoints.length < config.pixelEraserMinPiecePoints ||
        _length(piecePoints) < config.pixelEraserMinPieceLengthPt) {
      continue;
    }
    if (aligned) {
      pieces.add(Stroke(
        id: newId(),
        tool: stroke.tool,
        penStyle: stroke.penStyle,
        color: stroke.color,
        size: stroke.size,
        raw: stroke.pointsAreRaw ? piecePoints : _slice(stroke.raw, a, b),
        points: stroke.pointsAreRaw ? null : piecePoints,
        wordId: stroke.wordId,
        tidy: stroke.tidy,
      ));
    } else {
      pieces.add(Stroke(
        id: newId(),
        tool: stroke.tool,
        penStyle: stroke.penStyle,
        color: stroke.color,
        size: stroke.size,
        raw: piecePoints,
        wordId: stroke.wordId,
        tidy: TidyInfo(version: stroke.tidy.version, locked: true),
      ));
    }
  }
  return pieces;
}

const double _eps = 1e-9;

/// Merged, sorted erased intervals in `s` coordinates. Intervals that only
/// graze the stroke (zero length) are ignored.
List<(double, double)> _erasedIntervals(
    List<InkPoint> pts, Vec2 from, Vec2 to, double reach) {
  final out = <(double, double)>[];
  for (var i = 0; i < pts.length - 1; i++) {
    final iv = segmentCapsuleInterval(
        pts[i].pos, pts[i + 1].pos, from, to, reach);
    if (iv == null) continue;
    final a = _snap(i + iv.$1), b = _snap(i + iv.$2);
    if (out.isNotEmpty && a <= out.last.$2 + _eps) {
      final prev = out.removeLast();
      out.add((prev.$1, b > prev.$2 ? b : prev.$2));
    } else {
      out.add((a, b));
    }
  }
  out.removeWhere((iv) => iv.$2 - iv.$1 <= _eps);
  return out;
}

/// Snaps `s` values within rounding noise of a point index onto it, so a
/// cut at a vertex doesn't produce a near-duplicate interpolated point.
double _snap(double s) {
  final r = s.roundToDouble();
  return (s - r).abs() < 1e-7 ? r : s;
}

/// The points of [list] between positions [a] and [b], with interpolated
/// end points when a cut falls inside a segment.
List<InkPoint> _slice(List<InkPoint> list, double a, double b) {
  final out = <InkPoint>[_pointAt(list, a)];
  final firstInner = a.floor() + 1;
  final lastInner = b.ceil() - 1;
  for (var k = firstInner; k <= lastInner; k++) {
    out.add(list[k]);
  }
  out.add(_pointAt(list, b));
  return out;
}

/// The point at position [s]; interpolated (position, pressure and time)
/// and quantized like captured points when [s] is between two points.
InkPoint _pointAt(List<InkPoint> list, double s) {
  final i = s.floor();
  if (i >= list.length - 1) return list.last;
  final t = s - i;
  if (t <= 0) return list[i];
  final p = list[i], q = list[i + 1];
  return InkPoint.quantized(
    p.x + (q.x - p.x) * t,
    p.y + (q.y - p.y) * t,
    p.pressure + (q.pressure - p.pressure) * t,
    (p.t + (q.t - p.t) * t).round(),
  );
}

double _length(List<InkPoint> pts) {
  var sum = 0.0;
  for (var i = 1; i < pts.length; i++) {
    sum += pts[i - 1].pos.distanceTo(pts[i].pos);
  }
  return sum;
}

/// Accumulates one partial-eraser drag into a single set of replacements,
/// so the whole drag becomes one `SpliceStrokesCommand` (one undo step).
///
/// The page itself is not touched while dragging. The canvas should hide
/// [replacedIds] and draw [pieces] instead; on pen-up, if [isEmpty] is
/// false, run `SpliceStrokesCommand(pageId, session.replacements)`.
/// Pieces cut again later in the same drag are replaced in place, so
/// [replacements] always maps page stroke ids to their final pieces.
class PixelEraseSession {
  PixelEraseSession({
    required this.index,
    required this.newId,
    this.config = ToolConfig.defaults,
  });

  /// The page's index, in sync with the page at the start of the drag.
  final SpatialIndex index;
  final String Function() newId;
  final ToolConfig config;

  /// Page stroke id → its current pieces, in polyline order.
  final Map<String, List<Stroke>> _replacements = {};

  /// Piece id → the page stroke it came from.
  final Map<String, String> _origin = {};

  bool get isEmpty => _replacements.isEmpty;

  /// Page stroke ids that are cut (hide these while dragging).
  Set<String> get replacedIds => UnmodifiableSetView(_replacements.keys.toSet());

  /// The current pieces (draw these while dragging).
  Iterable<Stroke> get pieces => _replacements.values.expand((p) => p);

  /// Page stroke id → final pieces, for `SpliceStrokesCommand`.
  Map<String, List<Stroke>> get replacements => {
        for (final MapEntry(:key, :value) in _replacements.entries)
          key: List.unmodifiable(value),
      };

  /// Erases along one pointer move. Returns true when anything was cut.
  bool sweep(Vec2 from, Vec2 to, double radius) {
    final area = sweepBounds(from, to, radius);
    final candidates = <Stroke>[
      for (final s in index.strokesIn(area))
        if (!_replacements.containsKey(s.id)) s,
      for (final p in pieces)
        if (p.paintBounds.overlaps(area)) p,
    ];
    if (candidates.isEmpty) return false;
    final cut = pixelErase(
      candidates: candidates,
      from: from,
      to: to,
      radius: radius,
      newId: newId,
      config: config,
    );
    cut.forEach(_record);
    return cut.isNotEmpty;
  }

  void _record(String cutId, List<Stroke> newPieces) {
    final origin = _origin.remove(cutId);
    if (origin == null) {
      // A page stroke cut for the first time.
      _replacements[cutId] = List.of(newPieces);
      for (final p in newPieces) {
        _origin[p.id] = cutId;
      }
      return;
    }
    // A piece cut again: splice its sub-pieces in where it was.
    final list = _replacements[origin]!;
    final at = list.indexWhere((p) => p.id == cutId);
    list
      ..removeAt(at)
      ..insertAll(at, newPieces);
    for (final p in newPieces) {
      _origin[p.id] = origin;
    }
  }
}
