import 'dart:math' as math;

/// How the centre line of a stroke is drawn.
///
/// Pure Dart (`ink/` has no `dart:ui`). The geometry that turns a style into
/// marks is `line_pattern.dart`; the outlines are built in
/// `render/stroke_outline.dart`.
enum LineStyle {
  solid('Solid'),
  dashed('Dashed'),
  dotted('Dotted'),
  wavy('Wavy'),
  zigzag('Zigzag'),

  /// Two parallel lines.
  parallel('Double');

  const LineStyle(this.label);

  /// User-facing name.
  final String label;
}

/// A stroke's [LineStyle] plus the two wave sliders ("Wavy Line Height" and
/// "Wavy Line Width" in the pen settings, used by [LineStyle.wavy] and
/// [LineStyle.zigzag]).
///
/// Every length of a pattern is a multiple of the pen width (`Stroke.size`),
/// so a pattern scales with the pen and with lasso resizing. The multipliers
/// below were measured on the reference video (Notability's Technical Pen,
/// default sliders 3.1 / 3.7: a wave about 2.5 pen widths high and 8 wide).
class LineSettings {
  const LineSettings({
    this.style = LineStyle.solid,
    this.waveHeight = defaultWaveHeight,
    this.waveWidth = defaultWaveWidth,
  });

  /// Reads a stored value; anything unreadable is a plain solid line (a
  /// stroke must always load).
  factory LineSettings.fromJson(Object? j) {
    if (j is! Map) return solid;
    var style = LineStyle.solid;
    for (final s in LineStyle.values) {
      if (s.name == j['style']) style = s;
    }
    return LineSettings(
      style: style,
      waveHeight: _slider(j['height'], defaultWaveHeight, minWaveHeight, maxWaveHeight),
      waveWidth: _slider(j['width'], defaultWaveWidth, minWaveWidth, maxWaveWidth),
    );
  }

  /// A plain line (the default of every stroke).
  static const LineSettings solid = LineSettings();

  static const double defaultWaveHeight = 3.1;
  static const double defaultWaveWidth = 3.7;

  /// The slider ranges.
  static const double minWaveHeight = 0.5;
  static const double maxWaveHeight = 12.0;
  static const double minWaveWidth = 1.0;
  static const double maxWaveWidth = 20.0;

  final LineStyle style;

  /// "Wavy Line Height" slider value, see [amplitude].
  final double waveHeight;

  /// "Wavy Line Width" slider value, see [wavelength].
  final double waveWidth;

  bool get isSolid => style == LineStyle.solid;

  /// Whether the wave sliders matter for [style].
  bool get hasWaveParams =>
      style == LineStyle.wavy || style == LineStyle.zigzag;

  /// Distance from the base path to a wave crest, in points, for a pen
  /// [size] points wide (peak-to-peak is twice this).
  double amplitude(double size) => waveHeight * size * 0.4;

  /// Length of one full wave, in points.
  double wavelength(double size) => waveWidth * size * 2.0;

  /// Length of one dash, along the path (end to end of its centre line;
  /// the round caps add one pen width, so a dash looks about 4.4 widths
  /// long).
  double dashLength(double size) => 3.4 * size;

  /// Gap between two dashes, along the path (between the centre lines'
  /// ends; the round caps eat one pen width of it, leaving about 1.9).
  double gapLength(double size) => 2.9 * size;

  /// Distance between the centres of two neighbouring dots.
  double dotSpacing(double size) => 2.4 * size;

  /// Distance between the centre lines of the two lines of
  /// [LineStyle.parallel].
  double lineGap(double size) => 2.2 * size;

  /// How far the marks reach to each side of the base path, beyond the pen's
  /// own half width. Used for paint bounds and eraser / lasso reach.
  double extraHalfWidth(double size) => switch (style) {
        LineStyle.solid || LineStyle.dashed || LineStyle.dotted => 0,
        LineStyle.wavy || LineStyle.zigzag => amplitude(size),
        LineStyle.parallel => lineGap(size) / 2,
      };

  LineSettings copyWith({
    LineStyle? style,
    double? waveHeight,
    double? waveWidth,
  }) =>
      LineSettings(
        style: style ?? this.style,
        waveHeight: waveHeight ?? this.waveHeight,
        waveWidth: waveWidth ?? this.waveWidth,
      );

  Map<String, dynamic> toJson() => {
        'style': style.name,
        'height': _round2(waveHeight),
        'width': _round2(waveWidth),
      };

  @override
  bool operator ==(Object other) =>
      other is LineSettings &&
      other.style == style &&
      other.waveHeight == waveHeight &&
      other.waveWidth == waveWidth;

  @override
  int get hashCode => Object.hash(style, waveHeight, waveWidth);

  @override
  String toString() => 'LineSettings(${style.name}, $waveHeight, $waveWidth)';

  static double _slider(Object? v, double fallback, double min, double max) =>
      v is num && v.isFinite ? v.toDouble().clamp(min, max).toDouble() : fallback;

  static double _round2(double v) => (v * 100).roundToDouble() / 100;
}

/// Opacity ("Concentration" in the pen settings) bounds: a stroke can't be
/// made invisible.
const double minConcentration = 0.1;

/// [v] as a usable concentration in [minConcentration]..1, or [fallback].
double concentrationFrom(Object? v, [double fallback = 1.0]) => v is num && v.isFinite
    ? math.min(1.0, math.max(minConcentration, v.toDouble()))
    : fallback;
