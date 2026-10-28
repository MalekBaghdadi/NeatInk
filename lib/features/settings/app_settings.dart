import '../../document/paper.dart';
import '../../document/pdf_margins.dart';
import '../../ink/stroke.dart' show enumByName;

enum AppThemeMode { system, light, dark }

enum LibrarySort { edited, created, title }

/// User preferences, persisted with shared_preferences as one JSON string
/// under [AppSettings.prefsKey]. Immutable; change with [copyWith].
///
/// Unknown keys in saved JSON (e.g. the removed tidy settings) are ignored.
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.drawWithFinger = false,
    this.stylusButtonErases = true,
    this.shapeSnapEnabled = true,
    this.tidyHighlighter = true,
    this.pdfMargins = PdfMargins.none,
    this.exportPaperLines = true,
    this.autoConvert = false,
    this.autoConvertDelayMs = defaultAutoConvertDelayMs,
    this.autocorrect = true,
    this.defaultPaper = const Paper(),
    this.librarySort = LibrarySort.edited,
    this.pinHash,
    this.pinSalt,
    this.lockAfterSeconds = 0,
    this.lastBackupAt,
    this.tipsSeen = false,
  });

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        themeMode:
            enumByName(AppThemeMode.values, j['themeMode'], AppThemeMode.system),
        drawWithFinger: j['drawWithFinger'] as bool? ?? false,
        stylusButtonErases: j['stylusButtonErases'] as bool? ?? true,
        shapeSnapEnabled: j['shapeSnapEnabled'] as bool? ?? true,
        tidyHighlighter: j['tidyHighlighter'] is bool ? j['tidyHighlighter'] as bool : true,
        pdfMargins: PdfMargins.byName(j['pdfMargins']),
        exportPaperLines: j['exportPaperLines'] as bool? ?? true,
        autoConvert: j['autoConvert'] as bool? ?? false,
        autoConvertDelayMs: clampAutoConvertDelay(switch (j['autoConvertDelayMs']) {
          final num ms => ms.toInt(),
          _ => defaultAutoConvertDelayMs,
        }),
        // 1.5.0: replaces 'autoFixSpelling' (off by default), so everyone
        // starts with autocorrect on.
        autocorrect: j['autocorrect'] is bool ? j['autocorrect'] as bool : true,
        defaultPaper:
            Paper.fromJson(j['defaultPaper'] as Map<String, dynamic>?),
        librarySort:
            enumByName(LibrarySort.values, j['librarySort'], LibrarySort.edited),
        pinHash: j['pinHash'] as String?,
        pinSalt: j['pinSalt'] as String?,
        lockAfterSeconds: (j['lockAfterSeconds'] as num?)?.toInt() ?? 0,
        lastBackupAt: DateTime.tryParse('${j['lastBackupAt'] ?? ''}'),
        tipsSeen: j['tipsSeen'] as bool? ?? false,
      );

  static const String prefsKey = 'neatink.settings.v1';

  final AppThemeMode themeMode;

  /// Let touch draw. Off by default: the pen draws, fingers navigate.
  final bool drawWithFinger;

  /// The pen's eraser end / button (inverted stylus) erases.
  final bool stylusButtonErases;

  /// Hold the pen still at the end of a stroke to snap it to a shape.
  final bool shapeSnapEnabled;

  /// A highlight drawn over a line of writing, typed text or PDF text
  /// becomes a straight band that fits the line (the drawn one is kept for
  /// "Restore original"). On by default.
  final bool tidyHighlighter;

  /// Writing margins last chosen when importing a PDF (the next import
  /// offers the same).
  final PdfMargins pdfMargins;

  /// Draw paper lines/grid when exporting blank notebooks as PDF.
  final bool exportPaperLines;

  /// Auto-convert: a moment after the pen stops ([autoConvertDelayMs]), the
  /// new handwriting is turned into typed text by itself (see
  /// `AutoConvertSession`). Off by default; the manual Convert button always
  /// works.
  final bool autoConvert;

  /// How long auto-convert waits after the pen lifts before it reads
  /// (milliseconds, [minAutoConvertDelayMs] to [maxAutoConvertDelayMs]). A
  /// longer wait lets a sentence be finished after a pause.
  final int autoConvertDelayMs;

  static const int defaultAutoConvertDelayMs = 2000;
  static const int minAutoConvertDelayMs = 1000;
  static const int maxAutoConvertDelayMs = 10000;

  static int clampAutoConvertDelay(int ms) =>
      ms.clamp(minAutoConvertDelayMs, maxAutoConvertDelayMs).toInt();

  /// Convert: apply the suggested spelling, apostrophe, capital-letter and
  /// grammar fixes by themselves (each one can be undone in the review
  /// sheet). Off by default: the fixes are only suggested there.
  final bool autocorrect;

  /// Paper preselected when creating a notebook.
  final Paper defaultPaper;
  final LibrarySort librarySort;

  /// App lock: salted SHA-256 of the PIN (hex). Null = no lock.
  final String? pinHash;
  final String? pinSalt;

  /// Lock again after the app was in the background this long (0 = always).
  final int lockAfterSeconds;

  /// When a backup was last saved (Settings > Backup), or null.
  final DateTime? lastBackupAt;

  /// The Tips screen has been shown once (it opens by itself until then).
  final bool tipsSeen;

  bool get appLockEnabled => pinHash != null && pinSalt != null;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    bool? drawWithFinger,
    bool? stylusButtonErases,
    bool? shapeSnapEnabled,
    bool? tidyHighlighter,
    PdfMargins? pdfMargins,
    bool? exportPaperLines,
    bool? autoConvert,
    int? autoConvertDelayMs,
    bool? autocorrect,
    Paper? defaultPaper,
    LibrarySort? librarySort,
    String? pinHash,
    String? pinSalt,
    bool clearPin = false,
    int? lockAfterSeconds,
    DateTime? lastBackupAt,
    bool? tipsSeen,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        drawWithFinger: drawWithFinger ?? this.drawWithFinger,
        stylusButtonErases: stylusButtonErases ?? this.stylusButtonErases,
        shapeSnapEnabled: shapeSnapEnabled ?? this.shapeSnapEnabled,
        tidyHighlighter: tidyHighlighter ?? this.tidyHighlighter,
        pdfMargins: pdfMargins ?? this.pdfMargins,
        exportPaperLines: exportPaperLines ?? this.exportPaperLines,
        autoConvert: autoConvert ?? this.autoConvert,
        autoConvertDelayMs: autoConvertDelayMs == null
            ? this.autoConvertDelayMs
            : clampAutoConvertDelay(autoConvertDelayMs),
        autocorrect: autocorrect ?? this.autocorrect,
        defaultPaper: defaultPaper ?? this.defaultPaper,
        librarySort: librarySort ?? this.librarySort,
        pinHash: clearPin ? null : (pinHash ?? this.pinHash),
        pinSalt: clearPin ? null : (pinSalt ?? this.pinSalt),
        lockAfterSeconds: lockAfterSeconds ?? this.lockAfterSeconds,
        lastBackupAt: lastBackupAt ?? this.lastBackupAt,
        tipsSeen: tipsSeen ?? this.tipsSeen,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'drawWithFinger': drawWithFinger,
        'stylusButtonErases': stylusButtonErases,
        'shapeSnapEnabled': shapeSnapEnabled,
        'tidyHighlighter': tidyHighlighter,
        'pdfMargins': pdfMargins.name,
        'exportPaperLines': exportPaperLines,
        'autoConvert': autoConvert,
        'autoConvertDelayMs': autoConvertDelayMs,
        'autocorrect': autocorrect,
        'defaultPaper': defaultPaper.toJson(),
        'librarySort': librarySort.name,
        'pinHash': pinHash,
        'pinSalt': pinSalt,
        'lockAfterSeconds': lockAfterSeconds,
        'lastBackupAt': lastBackupAt?.toUtc().toIso8601String(),
        'tipsSeen': tipsSeen,
      };
}
