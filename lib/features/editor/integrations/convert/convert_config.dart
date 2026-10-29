import '../../../../document/font_kind.dart';

/// Every tuning number of the "Convert handwriting to typed text" feature.
///
/// None of these have been calibrated on real handwriting yet: they are first
/// guesses to be tuned on the tablet with the "Show what the recognizer saw"
/// section of the convert sheet.
abstract final class ConvertConfig {
  /// A recognised line whose confidence (the least sure of its words, see
  /// `LineReading.confidence`) is below this starts UNCHECKED in the review
  /// sheet (with a "Not sure" badge) and so stays handwriting unless the user
  /// ticks it.
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

  /// The even size on ruled paper, as a fraction of the ruling: 26 pt lines
  /// (the default) give 16 pt text, about as big as handwriting on them.
  static const double evenSizeOfRuling = 0.62;

  /// Joining lines into sentences (`continuesOnNextLine`): the next line
  /// starts at most this many x-heights right of where the line started...
  static const double joinIndentXHeights = 4;

  /// ...its baseline is at most this many rulings (or x-heights on paper
  /// without lines) lower: 2.6 lets a writer skip one ruled line between
  /// lines, as Mariam and the owner do with big handwriting (v1.6.0; it was
  /// 1.6 and 5.5, so their sentences never joined)...
  static const double joinMaxRulings = 2.6;
  static const double joinMaxXHeights = 8;

  /// ...and either the words carry on (`textCarriesOn`: the line ends with
  /// a comma or hyphen, or on a word no sentence ends on), or the line ran
  /// out of room: the first word of the next line would not have fitted
  /// after it before the right margin, with a gap of this many x-heights (a
  /// little more than a word gap: nobody squeezes a word in up to the
  /// margin), and the next line does not start with a capital. A writer who
  /// had room for the word and went to a new line meant a new line: notes
  /// rarely end in a full stop and their lines often start in lowercase
  /// (v1.10.0; before, a lowercase start was enough, and a page of notes
  /// became one paragraph after a few lines).
  static const double joinWordGapXHeights = 1.0;

  /// Space kept free at the right page edge (points).
  static const double rightMargin = 24;

  /// Space kept free beside a PDF page by text in its writing margins
  /// (points): margin text wraps this far from the PDF's edge.
  static const double pdfEdgeGap = 6;

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

  /// Lines recognised per chunk (progress and Cancel are checked between
  /// chunks). A line is one picture for the model, so a chunk is a handful of
  /// pictures; the chunks of a page follow each other.
  static const int chunkLines = 4;

  // ---------------------------------------------------------------------------
  // Auto-convert (like the Freenote app): the handwriting turns into text by
  // itself a moment after the pen stops.

  /// Quiet time after the pen lifts before auto-convert reads the new
  /// handwriting (milliseconds), when nothing else is given. The app reads
  /// the user's choice, `AppSettings.autoConvertDelayMs` (2 s by default);
  /// it is longer than the pause between the strokes of one letter or word,
  /// so it never fires mid-word.
  static const int autoIdleMs = 2000;

  /// Auto-convert only types a line whose confidence (the least sure of its
  /// words) is at least this and which has text; anything less stays ink
  /// until more is written on that line (then the whole line is read again),
  /// and a chip offers the review sheet.
  ///
  /// It was 0.5, which on Mariam's first page (v1.3.0) held back every line,
  /// even the two the recogniser read perfectly (0.45 and 0.57): a word the
  /// language layer repaired is reported as a gamble, so a correct line with
  /// one repair scores about 0.2-0.5. The bar now only keeps back what is
  /// clearly unreadable (scribbles, sketches); a slip is one undo away.
  /// Still uncalibrated beyond her page.
  static const double autoMinConfidence = 0.25;

  /// A pass that has not finished reading after this long is given up as a
  /// failure, so a stuck recogniser can never leave auto-convert waiting
  /// forever.
  static const Duration autoPassTimeout = Duration(minutes: 2);

  /// A new auto-converted line is appended to a text box on the page instead
  /// of starting a second one when it sits on the same baseline (within this
  /// many x-heights, or on the same ruled line)...
  ///
  /// v1.6.0: 0.6 -> 1.0 and 2.5 -> 4: on the tablet a short word's baseline
  /// and the end of the earlier writing were too uncertain for the tight
  /// numbers, so the next words of a sentence got a box of their own with a
  /// gap ("the gap is still here").
  static const double mergeBaselineTol = 1.0;

  /// ...and starts at most this many x-heights after where the handwriting
  /// the box replaced ended (anywhere over the space it left is fine)...
  static const double mergeMaxGap = 4;

  /// ...and at most this far over the typed text's last letter, or this far
  /// over where the replaced handwriting ended (the pen lands a little
  /// early).
  static const double mergeOverlap = 0.5;
  static const double mergeInkOverlap = 1.5;

  /// For a box whose handwriting end is not remembered, the writing is
  /// assumed at most this many times wider than its typed text.
  static const double maxInkWidthScale = 3;

  /// Ink colour overrides offered next to "Keep my ink colour".
  static const List<int> colorChoices = [
    0xFF1E1E1E, // near black
    0xFF1A237E, // dark blue
    0xFF1B5E20, // dark green
    0xFF4E342E, // dark brown
    0xFF880E4F, // dark berry
  ];
}
