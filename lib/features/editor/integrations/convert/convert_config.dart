import '../../../../document/font_kind.dart';

/// Every tuning number of the "Convert handwriting to typed text" feature.
///
/// None of these have been calibrated on real handwriting yet: they are first
/// guesses to be tuned on the tablet with the "Show what the recognizer saw"
/// section of the convert sheet.
abstract final class ConvertConfig {
  /// A recognised line whose mean word confidence is below this starts
  /// UNCHECKED in the review sheet (with a "Not sure" badge) and so stays
  /// handwriting unless the user ticks it.
  ///
  /// UNCALIBRATED: the confidences come from the CTC / lexicon rescoring in
  /// `lib/recognition` and were never compared with real student handwriting.
  /// Tune on the tablet: raise it if wrong lines get converted, lower it if
  /// good lines are left as ink.
  static const double lowConfidenceThreshold = 0.35;

  /// x-height of a font as a fraction of its font size, per category. Auto
  /// size is `handwriting x-height / ratio`, so a font with a small x-height
  /// (handwriting scripts) gets a larger point size to look as big as the
  /// writing it replaces. Tweakable.
  static const Map<FontCategory, double> fontXHeightRatio = {
    FontCategory.sans: 0.52,
    FontCategory.serif: 0.48,
    FontCategory.mono: 0.52,
    FontCategory.school: 0.52,
    FontCategory.handwriting: 0.42,
  };

  /// Ratio used when a category is missing from [fontXHeightRatio].
  static const double defaultXHeightRatio = 0.5;

  /// Auto size is clamped to this range (points).
  static const double minAutoSize = 10;
  static const double maxAutoSize = 30;

  /// On ruled paper the auto size is at most this fraction of the ruling.
  static const double maxSizeOfRuling = 0.8;

  /// Size slider range (points) and its starting value.
  static const double minFixedSize = 10;
  static const double maxFixedSize = 32;
  static const double defaultFixedSize = 16;

  /// Space kept free at the right page edge (points).
  static const double rightMargin = 24;

  /// A line that is too wide first shrinks down to this fraction of its
  /// intended size (still counted as a gentle shrink)...
  static const double softShrinkFactor = 0.85;

  /// ...then down to this many points...
  static const double floorSize = 9;

  /// ...and only then wraps. As a last resort, to avoid running into the
  /// next line, text may go as small as this.
  static const double absoluteMinSize = 6;

  /// Each shrink step multiplies the size by this while looking for a size
  /// that does not run into the next line.
  static const double shrinkStep = 0.93;

  /// A snapped baseline must be within this fraction of the ruling from the
  /// handwriting baseline.
  static const double snapReach = 0.75;

  /// Ruling assumed when a paper reports a nonsensical spacing.
  static const double fallbackRuling = 26;

  /// Narrowest text box ever made (points).
  static const double minBoxWidth = 24;

  /// Extra width on a single-line box so rounding never wraps it (points).
  static const double lineSlack = 4;

  /// Words recognised per chunk (progress and Cancel are checked between
  /// chunks).
  static const int chunkWords = 24;

  /// Ink colour overrides offered next to "Keep my ink colour".
  static const List<int> colorChoices = [
    0xFF1E1E1E, // near black
    0xFF1A237E, // dark blue
    0xFF1B5E20, // dark green
    0xFF4E342E, // dark brown
    0xFF880E4F, // dark berry
  ];
}
