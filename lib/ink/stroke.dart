import 'dart:collection';

import 'affine2.dart';
import 'ink_point.dart';
import 'ink_rect.dart';
import 'vec2.dart';

enum StrokeTool { pen, highlighter }

/// How a pen stroke is rendered. Highlighters ignore this.
enum PenStyle {
  /// Even width with light pressure response.
  ballpoint,

  /// Strong pressure response and tapered ends.
  fountain,

  /// Thin, slightly translucent, grainy look.
  pencil,
}

/// Set when a stroke was snapped to a geometric shape. `points` then holds
/// the generated shape and `raw` the hand-drawn original.
enum ShapeKind { line, arrow, rectangle, ellipse, triangle }

/// An immutable ink stroke in page coordinates.
///
/// * [raw] is exactly what the pen produced. It is only ever changed by
///   lasso move/resize, which transforms [raw] and [points] together.
/// * [points] is what is displayed. Equal to [raw] until snapped
///   to a shape.
///
/// Old files may still carry `wordId` / `tidy` keys (auto-tidy was removed);
/// they are ignored on load and no longer written.
///
/// Strokes are immutable so commands can keep old/new versions for undo and
/// renderers can cache outlines per instance (e.g. with an `Expando`).
class Stroke {
  /// When [points] is omitted (or is the same list as [raw]) the stroke
  /// shares one list for both, and [pointsAreRaw] is true.
  factory Stroke({
    required String id,
    required StrokeTool tool,
    PenStyle penStyle = PenStyle.ballpoint,
    required int color,
    required double size,
    required List<InkPoint> raw,
    List<InkPoint>? points,
    ShapeKind? shape,
  }) {
    final r = raw is _FrozenPoints ? raw : _FrozenPoints(raw);
    final List<InkPoint> p;
    if (points == null || identical(points, raw)) {
      p = r;
    } else {
      p = points is _FrozenPoints ? points : _FrozenPoints(points);
    }
    return Stroke._(id, tool, penStyle, color, size, r, p, shape);
  }

  Stroke._(this.id, this.tool, this.penStyle, this.color, this.size, this.raw,
      this.points, this.shape);

  factory Stroke.fromJson(Map<String, dynamic> j) {
    final raw = _pointsFromJson(j['raw']);
    var pts = j['points'] == null ? raw : _pointsFromJson(j['points']);
    if (_samePoints(raw, pts)) pts = raw;
    return Stroke(
      id: j['id'] as String,
      tool: _enumByName(StrokeTool.values, j['tool'], StrokeTool.pen),
      penStyle:
          _enumByName(PenStyle.values, j['penStyle'], PenStyle.ballpoint),
      color: colorFromHex(j['color'] as String? ?? '#FF1E1E1E'),
      size: (j['size'] as num?)?.toDouble() ?? 2.2,
      raw: raw,
      points: pts,
      shape: j['shape'] == null
          ? null
          : _enumByName(ShapeKind.values, j['shape'], ShapeKind.line),
    );
  }

  final String id;
  final StrokeTool tool;
  final PenStyle penStyle;

  /// ARGB, e.g. `0xFF1E1E1E`.
  final int color;

  /// Nominal stroke width in points.
  final double size;
  final List<InkPoint> raw;
  final List<InkPoint> points;
  final ShapeKind? shape;

  bool get isHighlighter => tool == StrokeTool.highlighter;

  /// True when [points] is the very same list as [raw] (never
  /// snapped or otherwise changed independently of `raw`).
  bool get pointsAreRaw => identical(points, raw);

  late final InkRect bounds = InkRect.fromPoints(points.map((p) => p.pos));

  /// [bounds] grown by half the stroke width, i.e. the painted area.
  InkRect get paintBounds => bounds.inflate(size / 2 + 0.5);

  Iterable<Vec2> get positions => points.map((p) => p.pos);

  Stroke copyWith({
    String? id,
    StrokeTool? tool,
    PenStyle? penStyle,
    int? color,
    double? size,
    List<InkPoint>? raw,
    List<InkPoint>? points,
    ShapeKind? shape,
    bool clearShape = false,
  }) =>
      Stroke(
        id: id ?? this.id,
        tool: tool ?? this.tool,
        penStyle: penStyle ?? this.penStyle,
        color: color ?? this.color,
        size: size ?? this.size,
        raw: raw ?? this.raw,
        points: points ?? this.points,
        shape: clearShape ? null : (shape ?? this.shape),
      );

  /// Applies [m] to both [raw] and [points] (lasso move/resize). The width
  /// scales with the transform's mean scale when [scaleWidth] is true.
  Stroke transformed(Affine2 m, {bool scaleWidth = true}) {
    final newRaw = [for (final p in raw) p.transformed(m)];
    return Stroke(
      id: id,
      tool: tool,
      penStyle: penStyle,
      color: color,
      size: scaleWidth ? size * m.meanScale : size,
      raw: newRaw,
      points:
          pointsAreRaw ? newRaw : [for (final p in points) p.transformed(m)],
      shape: shape,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tool': tool.name,
        if (tool == StrokeTool.pen) 'penStyle': penStyle.name,
        'color': colorToHex(color),
        'size': size,
        'raw': [for (final p in raw) p.toJson()],
        // Spec: `points` is always written so the file is self-describing.
        'points': [for (final p in points) p.toJson()],
        if (shape != null) 'shape': shape!.name,
      };

  static List<InkPoint> _pointsFromJson(dynamic j) => [
        for (final p in (j as List<dynamic>? ?? const []))
          InkPoint.fromJson(p as List<dynamic>),
      ];

  static bool _samePoints(List<InkPoint> a, List<InkPoint> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// An unmodifiable point list. A dedicated type lets [Stroke] skip copying
/// lists that are already frozen (e.g. when sharing `raw` between versions).
class _FrozenPoints extends UnmodifiableListView<InkPoint> {
  _FrozenPoints(List<InkPoint> source) : super(List.of(source, growable: false));
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// Looks up an enum value by [name], or returns [fallback].
T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
    _enumByName(values, name, fallback);

/// `#AARRGGBB` (or `#RRGGBB`, treated as opaque) → ARGB int.
int colorFromHex(String hex) {
  var h = hex.startsWith('#') ? hex.substring(1) : hex;
  if (h.length == 6) h = 'FF$h';
  return int.tryParse(h, radix: 16) ?? 0xFF1E1E1E;
}

/// ARGB int → `#AARRGGBB`.
String colorToHex(int argb) =>
    '#${(argb & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0').toUpperCase()}';
