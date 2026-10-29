import 'dart:math' as math;

import '../../../document/page_items.dart';
import '../../../ink/ink_point.dart';
import '../../../ink/ink_rect.dart';
import '../../../ink/stroke.dart';
import 'tool_config.dart';

// Scribble to delete (v1.6.0): a quick scratch-out with the pen over
// handwriting or typed text deletes what it covers, like on an iPad.
//
// Recognising the gesture from its shape alone is not enough: cursive "mm",
// an "M" or "ll" go back and forth just like a scribble. What makes it a
// scribble is that it is drawn *over* something: whatever it covers must
// span a good part of it ([ToolConfig.scribbleMinContentWidth] and
// [ToolConfig.scribbleMinContentHeight]).
// Writing goes on empty paper, so it stays writing. Shading inside a closed
// outline (a cell drawn as a circle) leaves the outline alone.

/// How much [points] look like a scribble.
enum ScribbleShape {
  /// Not a scribble.
  none,

  /// A short scribble (few turns): only over a lot of content.
  short,

  /// A clear scribble.
  clear,
}

/// Whether [points] have the shape of a clear scribble (see
/// [scribbleShapeOf]).
bool isScribbleShape(List<InkPoint> points, {ToolConfig config = ToolConfig.defaults}) =>
    scribbleShapeOf(points, config: config) == ScribbleShape.clear;

/// Whether [points] have the shape of a scribble: back and forth along their
/// main direction, or zig-zagging across it, with a path much longer than
/// they are wide. The main direction is the points' principal axis, so a
/// scribble slanted over slanted writing counts too.
ScribbleShape scribbleShapeOf(List<InkPoint> points, {ToolConfig config = ToolConfig.defaults}) {
  if (points.length < config.scribbleMinPoints) return ScribbleShape.none;
  // Principal axis from the covariance of the points: the angle that
  // maximises the spread is 0.5 atan2(2 sxy, sxx - syy).
  var mx = 0.0, my = 0.0;
  for (final p in points) {
    mx += p.x;
    my += p.y;
  }
  mx /= points.length;
  my /= points.length;
  var sxx = 0.0, sxy = 0.0, syy = 0.0;
  for (final p in points) {
    final dx = p.x - mx, dy = p.y - my;
    sxx += dx * dx;
    sxy += dx * dy;
    syy += dy * dy;
  }
  final angle = 0.5 * math.atan2(2 * sxy, sxx - syy);
  final ux = math.cos(angle), uy = math.sin(angle);
  final along = [for (final p in points) (p.x - mx) * ux + (p.y - my) * uy];
  final across = [for (final p in points) -(p.x - mx) * uy + (p.y - my) * ux];
  final length = _extent(along), height = _extent(across);
  if (length < config.scribbleMinWidthPt) return ScribbleShape.none;

  var path = 0.0;
  for (var i = 1; i < points.length; i++) {
    path += math.sqrt(math.pow(points[i].x - points[i - 1].x, 2) + math.pow(points[i].y - points[i - 1].y, 2));
  }

  final turnsAlong = _reversals(along, math.max(config.scribbleSwingFraction * length, config.scribbleMinSwingPt));
  if (path >= config.scribbleMinPathRatio * length && turnsAlong >= config.scribbleMinReversals) {
    return ScribbleShape.clear;
  }
  final tall = height >= config.scribbleMinSwingPt;
  final turnsAcross =
      tall ? _reversals(across, math.max(config.scribbleZigzagSwingFraction * height, config.scribbleMinSwingPt)) : 0;
  if (path >= config.scribbleZigzagMinPathRatio * length && turnsAcross >= config.scribbleZigzagMinReversals) {
    return ScribbleShape.clear;
  }
  if (path >= config.scribbleShortMinPathRatio * length && turnsAlong >= config.scribbleShortMinReversals) {
    return ScribbleShape.short;
  }
  final shortTurnsAcross = tall
      ? _reversals(across, math.max(config.scribbleShortZigzagSwingFraction * height, config.scribbleMinSwingPt))
      : 0;
  if (path >= config.scribbleShortZigzagMinPathRatio * length &&
      shortTurnsAcross >= config.scribbleShortZigzagMinReversals) {
    return ScribbleShape.short;
  }
  return ScribbleShape.none;
}

double _extent(List<double> values) => values.reduce(math.max) - values.reduce(math.min);

/// How many times [values] turn back after moving at least [swing] one way
/// (hysteresis, so the wobble of a hand does not count).
int _reversals(List<double> values, double swing) {
  var count = 0;
  var direction = 0;
  var low = values.first, high = values.first, extreme = values.first;
  for (final v in values) {
    if (direction == 0) {
      low = math.min(low, v);
      high = math.max(high, v);
      if (v - low >= swing) {
        direction = 1;
        extreme = v;
      } else if (high - v >= swing) {
        direction = -1;
        extreme = v;
      }
    } else if (direction > 0) {
      if (v > extreme) {
        extreme = v;
      } else if (extreme - v >= swing) {
        count++;
        direction = -1;
        extreme = v;
      }
    } else {
      if (v < extreme) {
        extreme = v;
      } else if (v - extreme >= swing) {
        count++;
        direction = 1;
        extreme = v;
      }
    }
  }
  return count;
}

/// A word of a typed text box: its characters `text[start, end)` and where
/// it is on the page (one rectangle per line it is on).
typedef ScribbleWord = ({int start, int end, List<InkRect> boxes});

/// What a scribble deletes: whole strokes, and words of typed text boxes
/// (each change is `(before, after)`, `after` null when the box is emptied).
class ScribblePlan {
  const ScribblePlan({required this.strokeIds, required this.textChanges});

  final Set<String> strokeIds;
  final List<(TextItem, TextItem?)> textChanges;
}

/// What [scribble] deletes from a page with [strokes] and [texts], or null
/// when it is not a scribble over anything (then it is ink like any other).
///
/// [wordsOf] lays a text box out and returns its words; [measureHeight] is
/// the height of a box's text once words are gone. Both come from Flutter's
/// text layout, which this file does not use.
ScribblePlan? planScribble({
  required Stroke scribble,
  required List<Stroke> strokes,
  required List<TextItem> texts,
  required List<ScribbleWord> Function(TextItem item) wordsOf,
  required double Function(TextItem item) measureHeight,
  ToolConfig config = ToolConfig.defaults,
}) {
  final shape = scribbleShapeOf(scribble.points, config: config);
  if (shape == ScribbleShape.none) return null;
  final clear = shape == ScribbleShape.clear;
  final minWidth = clear ? config.scribbleMinContentWidth : config.scribbleShortMinContentWidth;
  final minHeight = clear ? config.scribbleMinContentHeight : config.scribbleShortMinContentHeight;
  final area = scribble.bounds.inflate(config.scribbleMarginPt);
  if (area.isEmpty) return null;

  InkRect? content;
  void cover(InkRect r) {
    final part = r.intersect(area);
    content = content == null ? part : content!.union(part);
  }

  final strokeIds = <String>{};
  for (final s in strokes) {
    if (s.id == scribble.id || s.points.isEmpty || !s.bounds.overlaps(area)) continue;
    if (_encloses(s, scribble.bounds, config)) continue;
    if (_strokeCovered(s, area, config)) {
      strokeIds.add(s.id);
      cover(s.bounds);
    }
  }

  final textChanges = <(TextItem, TextItem?)>[];
  for (final t in texts) {
    if (t.text.trim().isEmpty || !t.frame.overlaps(area)) continue;
    final gone = <ScribbleWord>[];
    for (final w in wordsOf(t)) {
      if (w.boxes.any((b) => _boxCovered(b, area, config))) {
        gone.add(w);
        for (final b in w.boxes) {
          cover(b);
        }
      }
    }
    if (gone.isEmpty) continue;
    final text = withoutWords(t.text, [for (final w in gone) (w.start, w.end)]);
    if (text.trim().isEmpty) {
      textChanges.add((t, null));
    } else {
      final changed = t.copyWith(text: text);
      textChanges.add((t, changed.copyWith(height: measureHeight(changed))));
    }
  }

  final covered = content;
  if (covered == null || (strokeIds.isEmpty && textChanges.isEmpty)) return null;
  if (covered.width < minWidth * area.width || covered.height < minHeight * area.height) return null;
  return ScribblePlan(strokeIds: strokeIds, textChanges: textChanges);
}

bool _strokeCovered(Stroke s, InkRect area, ToolConfig config) {
  var inside = 0;
  for (final p in s.points) {
    if (area.contains(p.pos)) inside++;
  }
  if (inside >= config.scribbleStrokeInsideFraction * s.points.length) return true;
  return _boxCovered(s.bounds, area, config);
}

/// [s] is a closed outline around [inner] (the scribble's bounds): the
/// scribble shades the inside of a drawing, it does not scratch it out.
bool _encloses(Stroke s, InkRect inner, ToolConfig config) {
  final b = s.bounds.inflate(s.size / 2);
  if (b.left > inner.left || b.top > inner.top || b.right < inner.right || b.bottom < inner.bottom) return false;
  final shape = s.shape;
  if (shape != null) return shape != ShapeKind.line && shape != ShapeKind.arrow;
  return s.points.first.pos.distanceTo(s.points.last.pos) <= config.scribbleClosedGapFraction * s.bounds.diagonal;
}

/// The area covers most of [box]'s width and a good part of its height.
bool _boxCovered(InkRect box, InkRect area, ToolConfig config) {
  double share(double lo, double hi, double alo, double ahi) {
    final size = hi - lo;
    final overlap = math.min(hi, ahi) - math.max(lo, alo);
    if (overlap < 0) return 0;
    // A flat bar or a dot: inside is all of it.
    return size <= 1e-6 ? 1 : math.min(1, overlap / size);
  }

  return share(box.left, box.right, area.left, area.right) >= config.scribbleAcrossFraction &&
      share(box.top, box.bottom, area.top, area.bottom) >= config.scribbleDownFraction;
}

/// [text] without the words at [ranges] (`[start, end)`, from a word
/// match), keeping one separator where they were: a line break if one was
/// there, else the space after the word before.
String withoutWords(String text, List<(int, int)> ranges) {
  final gone = {for (final r in ranges) r.$1};
  final words = [for (final m in RegExp(r'\S+').allMatches(text)) (m.start, m.end)];
  final kept = [for (final w in words) if (!gone.contains(w.$1)) w];
  if (kept.isEmpty) return '';
  final out = StringBuffer(text.substring(0, words.first.$1));
  for (var i = 0; i < kept.length; i++) {
    if (i > 0) {
      final gap = text.substring(kept[i - 1].$2, kept[i].$1);
      final separators = RegExp(r'\s+').allMatches(gap).map((m) => m.group(0)!).toList();
      out.write(separators.firstWhere((s) => s.contains('\n'), orElse: () => separators.first));
    }
    out.write(text.substring(kept[i].$1, kept[i].$2));
  }
  if (kept.last == words.last) out.write(text.substring(words.last.$2));
  return out.toString();
}
