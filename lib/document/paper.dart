import '../ink/stroke.dart' show colorFromHex, colorToHex, enumByName;
import '../ink/vec2.dart';

enum PaperType { blank, lined, grid, dotted, cornell, music }

/// The look of a page: ruling pattern, spacing and background colour.
class Paper {
  const Paper({
    this.type = PaperType.lined,
    this.spacingPt = 26,
    this.color = white,
  });

  factory Paper.fromJson(Map<String, dynamic>? j) => j == null
      ? const Paper()
      : Paper(
          type: enumByName(PaperType.values, j['type'], PaperType.lined),
          spacingPt: (j['spacingPt'] as num?)?.toDouble() ?? 26,
          color: j['color'] == null
              ? white
              : colorFromHex(j['color'] as String),
        );

  static const int white = 0xFFFFFFFF;
  static const int cream = 0xFFFAF5E8;
  static const int dark = 0xFF1F2124;

  /// Background colours offered in the UI, in display order.
  static const List<int> colors = [white, cream, dark];

  final PaperType type;

  /// Distance between ruled lines / grid cells, in points.
  final double spacingPt;

  /// Background colour (ARGB).
  final int color;

  /// Dark paper flips the default ink colour and ruling colours.
  bool get isDark => _luminance(color) < 0.4;

  /// Colour of ruled lines, grid lines and dots.
  int get lineColor => isDark ? 0x40FFFFFF : 0xFFB9C9DD;

  /// Colour of the accent lines (lined-paper margin, Cornell dividers).
  int get accentColor => isDark ? 0x66FF8A80 : 0xFFE8A0A0;

  /// Paper types whose horizontal lines the tidy feature can snap words to.
  bool get hasRuledLines =>
      type == PaperType.lined ||
      type == PaperType.grid ||
      type == PaperType.cornell;

  Paper copyWith({PaperType? type, double? spacingPt, int? color}) => Paper(
        type: type ?? this.type,
        spacingPt: spacingPt ?? this.spacingPt,
        color: color ?? this.color,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'spacingPt': spacingPt,
        'color': colorToHex(color),
      };

  @override
  bool operator ==(Object other) =>
      other is Paper &&
      other.type == type &&
      other.spacingPt == spacingPt &&
      other.color == color;

  @override
  int get hashCode => Object.hash(type, spacingPt, color);

  static double _luminance(int argb) {
    final r = ((argb >> 16) & 0xFF) / 255.0;
    final g = ((argb >> 8) & 0xFF) / 255.0;
    final b = (argb & 0xFF) / 255.0;
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }
}

/// Kinds of paper marks, so painters can pick widths/colours consistently.
enum PaperLineRole { rule, accent }

class PaperLine {
  const PaperLine(this.from, this.to, this.role);
  final Vec2 from;
  final Vec2 to;
  final PaperLineRole role;
}

/// Pure geometry of a paper pattern for a page of [width] × [height] pt.
///
/// The screen painter, the PDF exporter and the tidy feature all use this,
/// so ruled lines are in exactly the same place everywhere.
class PaperGeometry {
  PaperGeometry(this.paper, this.width, this.height) {
    _build();
  }

  final Paper paper;
  final double width;
  final double height;

  final List<PaperLine> lines = [];
  final List<Vec2> dots = [];

  /// y positions of horizontal writing lines (top to bottom). Tidy snaps
  /// word baselines to these. Empty for blank, dotted and music paper.
  final List<double> baselines = [];

  /// Line width in points for each role (before any zoom).
  static double strokeWidthFor(PaperLineRole role) =>
      role == PaperLineRole.rule ? 0.6 : 0.9;

  /// Dot radius in points for dotted paper.
  static const double dotRadius = 0.9;

  double get _s => paper.spacingPt <= 4 ? 26 : paper.spacingPt;

  void _build() {
    switch (paper.type) {
      case PaperType.blank:
        break;
      case PaperType.lined:
        _lined();
      case PaperType.grid:
        _grid();
      case PaperType.dotted:
        _dotted();
      case PaperType.cornell:
        _cornell();
      case PaperType.music:
        _music();
    }
  }

  /// Ruled lines start below a header band of three line spacings, with a
  /// left margin line like a school notebook.
  void _lined() {
    final s = _s;
    for (var y = s * 3; y <= height - s * 0.5; y += s) {
      lines.add(PaperLine(Vec2(0, y), Vec2(width, y), PaperLineRole.rule));
      baselines.add(y);
    }
    final marginX = s * 2.75;
    if (marginX < width / 3) {
      lines.add(PaperLine(
          Vec2(marginX, 0), Vec2(marginX, height), PaperLineRole.accent));
    }
  }

  /// Square grid centred on the page.
  void _grid() {
    final s = _s;
    final x0 = (width % s) / 2, y0 = (height % s) / 2;
    for (var x = x0; x <= width + 0.01; x += s) {
      lines.add(PaperLine(Vec2(x, 0), Vec2(x, height), PaperLineRole.rule));
    }
    for (var y = y0; y <= height + 0.01; y += s) {
      lines.add(PaperLine(Vec2(0, y), Vec2(width, y), PaperLineRole.rule));
      if (y > s && y < height - s * 0.5) baselines.add(y);
    }
  }

  void _dotted() {
    final s = _s;
    final x0 = (width % s) / 2, y0 = (height % s) / 2;
    for (var y = y0; y <= height + 0.01; y += s) {
      for (var x = x0; x <= width + 0.01; x += s) {
        dots.add(Vec2(x, y));
      }
    }
  }

  /// Cornell notes: a title band, a cue column on the left (30% of the
  /// width) and a summary box at the bottom (5 line spacings tall).
  void _cornell() {
    final s = _s;
    final titleBottom = s * 3;
    final summaryTop = height - s * 5;
    final cueRight = width * 0.3;
    lines.add(PaperLine(
        Vec2(0, titleBottom), Vec2(width, titleBottom), PaperLineRole.accent));
    lines.add(PaperLine(
        Vec2(0, summaryTop), Vec2(width, summaryTop), PaperLineRole.accent));
    lines.add(PaperLine(Vec2(cueRight, titleBottom), Vec2(cueRight, summaryTop),
        PaperLineRole.accent));
    for (var y = titleBottom + s; y < summaryTop - s * 0.25; y += s) {
      lines.add(PaperLine(Vec2(0, y), Vec2(width, y), PaperLineRole.rule));
      baselines.add(y);
    }
    for (var y = summaryTop + s; y <= height - s * 0.5; y += s) {
      lines.add(PaperLine(Vec2(0, y), Vec2(width, y), PaperLineRole.rule));
      baselines.add(y);
    }
  }

  /// Music staves: five lines per staff. The staff line gap is 0.3 × spacing
  /// and staves are 3 × spacing apart, inside side margins of one spacing.
  void _music() {
    final s = _s;
    final gap = s * 0.3;
    final staffHeight = gap * 4;
    final pitch = staffHeight + s * 1.8;
    final left = s, right = width - s;
    for (var top = s * 2.5; top + staffHeight <= height - s; top += pitch) {
      for (var i = 0; i < 5; i++) {
        final y = top + gap * i;
        lines.add(PaperLine(Vec2(left, y), Vec2(right, y), PaperLineRole.rule));
      }
    }
  }
}
