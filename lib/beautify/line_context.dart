import 'dart:math' as math;

import '../document/paper.dart';
import '../ink/ink_rect.dart';
import '../ink/vec2.dart';
import 'stats.dart';
import 'tidy_config.dart';

/// Spec step 7: the running state of the page and of the line being written.
///
/// Nothing here is persisted. A page rebuilds its context lazily from the
/// stored strokes (see `rebuildPageContext` in `tidy_pipeline.dart`).

/// What the page remembers about one finished word (tidied or skipped).
class WordRecord {
  const WordRecord({
    required this.wordId,
    required this.bounds,
    required this.baselineCenter,
    required this.baselineSlope,
    required this.tidied,
    this.strokeIds = const [],
    this.xHeight,
    this.slant,
    this.skew,
    this.tallRatio,
  });

  final String wordId;

  /// Where the word's ink is *now* (tidied box for tidied words).
  final InkRect bounds;

  /// Point on the word's baseline (as displayed) at its horizontal centre.
  final Vec2 baselineCenter;

  /// Slope (dy/dx) of the word's displayed baseline. 0 for a flat word.
  final double baselineSlope;

  /// False for words that were skipped (drawings, underlines …): they count
  /// for spacing but never for baselines or statistics.
  final bool tidied;

  final List<String> strokeIds;

  /// Measured (pre-tidy) values that feed the running medians. Null when the
  /// word's own estimate was unreliable.
  final double? xHeight;
  final double? slant;
  final double? skew;
  final double? tallRatio;
}

/// A group of words written on one line (baselines within
/// `lineGroupFactor × lineHeight` of each other).
class LineContext {
  LineContext({this.config = const TidyConfig()});

  final TidyConfig config;
  final List<WordRecord> _words = [];

  List<WordRecord> get words => List.unmodifiable(_words);
  int get wordCount => _words.length;
  bool get isEmpty => _words.isEmpty;
  WordRecord? get lastWord => _words.isEmpty ? null : _words.last;

  /// Words that were tidied (the ones that define the baseline).
  List<WordRecord> get _tidied => [
        for (final w in _words)
          if (w.tidied) w,
      ];
  int get tidiedWordCount => _tidied.length;

  /// Median skew (radians) of the line's words, or null before any.
  double? get skew => median([
        for (final w in _words)
          if (w.skew != null) w.skew!,
      ]);

  /// Median slant (radians) of the line's words.
  double? get slant => median([
        for (final w in _words)
          if (w.slant != null) w.slant!,
      ]);

  /// Median x-height of the line's words.
  double? get xHeight => median([
        for (final w in _words)
          if (w.xHeight != null) w.xHeight!,
      ]);

  /// The line through the tidied words' baselines (spec step 7), or null
  /// when no word has been tidied yet. One word: its own baseline with its
  /// own slope. Several: least squares through their baseline centres, with
  /// the slope limited to `maxSkewDeg` so a bad word cannot tilt the line.
  LineFit? get baselineFit {
    final t = _tidied;
    if (t.isEmpty) return null;
    final one = t.last;
    LineFit single() => LineFit(one.baselineSlope,
        one.baselineCenter.y - one.baselineSlope * one.baselineCenter.x);
    if (t.length < 2) return single();
    final xs = [for (final w in t) w.baselineCenter.x];
    final ys = [for (final w in t) w.baselineCenter.y];
    final fit = leastSquaresLine(xs, ys);
    if (fit == null) return single();
    final maxSlope = math.tan(degToRad(config.maxSkewDeg));
    final slope = fit.slope.clamp(-maxSlope, maxSlope);
    final b = interceptForSlope(xs, ys, slope)!;
    return LineFit(slope, b);
  }

  /// The line's baseline extended to [x] (spec 4, blank paper), or null.
  double? baselineAt(double x) => baselineFit?.yAt(x);

  /// Adds [word], replacing an earlier record with the same id.
  void add(WordRecord word) {
    _words.removeWhere((w) => w.wordId == word.wordId);
    _words.add(word);
  }

  void remove(String wordId) => _words.removeWhere((w) => w.wordId == wordId);
}

/// Page-wide context: paper geometry plus rolling statistics and the lines
/// written so far.
class PageContext {
  PageContext({
    required this.width,
    required this.height,
    List<double> ruledLines = const [],
    double? spacingPt,
    this.config = const TidyConfig(),
  })  : ruledLines = List.unmodifiable([...ruledLines]..sort()),
        ruledSpacing = _spacingOf(ruledLines, spacingPt),
        _xHeights = RollingWindow(config.xHeightWindow),
        _slants = RollingWindow(config.slantWindow),
        _tallRatios = RollingWindow(config.tallRatioWindow);

  /// Builds the context for [paper]. Ruled lines come from [PaperGeometry],
  /// the same geometry the painters and the PDF export use. Blank, dotted
  /// and music paper (and PDF pages written on in "blank mode") have none.
  factory PageContext.fromPaper(Paper paper, double width, double height,
      {TidyConfig config = const TidyConfig()}) {
    final lines =
        paper.hasRuledLines ? PaperGeometry(paper, width, height).baselines : <double>[];
    return PageContext(
        width: width,
        height: height,
        ruledLines: lines,
        spacingPt: paper.spacingPt,
        config: config);
  }

  final double width;
  final double height;
  final TidyConfig config;

  /// y of the ruled writing lines, top to bottom. Empty on unruled paper.
  final List<double> ruledLines;

  /// Distance between ruled lines, null on unruled paper.
  final double? ruledSpacing;

  final RollingWindow _xHeights;
  final RollingWindow _slants;
  final RollingWindow _tallRatios;
  final List<LineContext> _lines = [];
  final List<WordRecord> _words = [];
  LineContext? _lastLine;

  static double? _spacingOf(List<double> lines, double? given) {
    if (lines.isEmpty) return null;
    if (lines.length >= 2) {
      final s = [...lines]..sort();
      return s[1] - s[0];
    }
    return given;
  }

  bool get isRuled => ruledLines.isNotEmpty && ruledSpacing != null;

  List<LineContext> get lines => List.unmodifiable(_lines);
  List<WordRecord> get words => List.unmodifiable(_words);

  /// The line the most recent word was recorded on.
  LineContext? get lastLine => _lastLine;

  WordRecord? wordById(String id) {
    for (final w in _words) {
      if (w.wordId == id) return w;
    }
    return null;
  }

  // ---- running statistics ----------------------------------------------

  /// Median x-height of the last [TidyConfig.xHeightWindow] words.
  double? get xHeight => _xHeights.median;

  /// Median slant (radians) of the last [TidyConfig.slantWindow] words.
  double? get slant => _slants.median;

  /// Median tall-stroke height / x-height of the last words.
  double? get tallRatio => _tallRatios.median;

  /// Feeds the rolling windows directly (used when rebuilding and in tests).
  void observe({double? xHeight, double? slant, double? tallRatio}) {
    if (xHeight != null) _xHeights.add(xHeight);
    if (slant != null) _slants.add(slant);
    if (tallRatio != null) _tallRatios.add(tallRatio);
  }

  // ---- derived quantities (spec steps 1 and 4) -------------------------

  /// x-height before any word exists (spec step 1).
  double get initialXHeight => isRuled
      ? config.initialXHeightRuledFactor * ruledSpacing!
      : config.initialXHeightPt;

  /// Best guess of the writer's x-height: the line's median, else the
  /// page's, else the spec's initial estimate.
  double xHeightEstimate([LineContext? line]) =>
      line?.xHeight ?? xHeight ?? initialXHeight;

  /// Line height: the ruled spacing, else `2.5 × x-height`.
  double lineHeight([LineContext? line]) => isRuled
      ? ruledSpacing!
      : config.blankLineHeightFactor * xHeightEstimate(line);

  /// The ruled line nearest to [y] if it is within
  /// `snapMaxDistanceFactor × spacing`, else null (spec 4, target baseline).
  double? nearestRuledLine(double y) {
    if (!isRuled) return null;
    double? best;
    var bestDist = double.infinity;
    for (final r in ruledLines) {
      final d = (r - y).abs();
      if (d < bestDist) {
        bestDist = d;
        best = r;
      }
    }
    if (best == null || bestDist > config.snapMaxDistanceFactor * ruledSpacing!) {
      return null;
    }
    return best;
  }

  /// Target x-height for a word whose own x-height is [own].
  double targetXHeight(double own) {
    if (isRuled) return config.lineXFactor * ruledSpacing!;
    return xHeight ?? own;
  }

  /// Target slant (radians) for [mode]; [own] is the word's own slant.
  double targetSlant(TidySlantMode mode, double own) =>
      mode == TidySlantMode.upright ? 0.0 : (slant ?? own);

  /// Target height of tall strokes for a given target x-height (spec 4).
  double targetTallHeight(double targetX) {
    final ratio = (tallRatio ?? config.defaultTallRatio)
        .clamp(config.minTallRatio, config.maxTallRatio);
    return ratio * targetX;
  }

  // ---- lines -----------------------------------------------------------

  /// The line a word with baseline `y ≈ baselineY` at horizontal position
  /// [x] belongs to: the existing line whose baseline is nearest and within
  /// `lineGroupFactor × lineHeight`, else a new empty line (not yet part of
  /// the page until a word is recorded on it).
  LineContext lineFor(double baselineY, double x) {
    final limit = config.lineGroupFactor * lineHeight(_lastLine);
    LineContext? best;
    var bestDist = double.infinity;
    for (final l in _lines) {
      final b = l.baselineAt(x) ?? l.lastWord?.baselineCenter.y;
      if (b == null) continue;
      final d = (b - baselineY).abs();
      if (d <= limit && d < bestDist) {
        bestDist = d;
        best = l;
      }
    }
    return best ?? LineContext(config: config);
  }

  /// Records a finished word on [line] and feeds the rolling windows.
  void recordWord(LineContext line, WordRecord word) {
    line.add(word);
    if (!_lines.contains(line)) _lines.add(line);
    _lastLine = line;
    _words.removeWhere((w) => w.wordId == word.wordId);
    _words.add(word);
    while (_words.length > config.rememberedWordLimit) {
      _words.removeAt(0);
    }
    if (word.tidied) {
      observe(
          xHeight: word.xHeight,
          slant: word.slant,
          tallRatio: word.tallRatio);
    }
  }

  /// Forgets a word (it was erased or its tidy was undone). Rolling
  /// statistics keep their values, they are only a smoothing aid.
  void removeWord(String wordId) {
    _words.removeWhere((w) => w.wordId == wordId);
    for (final l in _lines) {
      l.remove(wordId);
    }
    _lines.removeWhere((l) => l.isEmpty);
    if (_lastLine != null && !_lines.contains(_lastLine)) {
      _lastLine = _lines.isEmpty ? null : _lines.last;
    }
  }

  /// Tidied words whose box overlaps [box] by more than [fraction] of
  /// [box]'s own area (spec step 2, scribble over tidied ink). [exceptId] is
  /// the word being tidied.
  bool overlapsTidied(InkRect box, {String? exceptId, double? fraction}) {
    final f = fraction ?? config.maxTidiedOverlapFraction;
    final m = config.overlapMinBoxPt;
    // Give flat boxes a little thickness so their area is not zero.
    final b = InkRect(
        box.left,
        box.top,
        box.right + math.max(0.0, m - box.width),
        box.bottom + math.max(0.0, m - box.height));
    final area = b.area;
    if (area <= 0) return false;
    for (final w in _words) {
      if (!w.tidied || w.wordId == exceptId) continue;
      final i = b.intersect(w.bounds);
      if (i.area / area > f) return true;
    }
    return false;
  }
}
