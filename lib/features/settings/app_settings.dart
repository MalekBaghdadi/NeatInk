import '../../document/paper.dart';
import '../../ink/stroke.dart' show enumByName;

enum AppThemeMode { system, light, dark }

/// Tidy blend strength (docs/beautify-spec.md, step 5).
enum TidyStrength {
  light(0.5),
  medium(0.8),
  strong(1.0);

  const TidyStrength(this.value);
  final double value;
}

enum SlantMode { keep, upright }

enum LibrarySort { edited, created, title }

/// User preferences, persisted with shared_preferences as one JSON string
/// under [AppSettings.prefsKey]. Immutable; change with [copyWith].
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.tidyEnabled = true,
    this.tidyStrength = TidyStrength.medium,
    this.slantMode = SlantMode.keep,
    this.drawWithFinger = false,
    this.stylusButtonErases = true,
    this.shapeSnapEnabled = true,
    this.debugOverlay = false,
    this.exportPaperLines = true,
    this.defaultPaper = const Paper(),
    this.librarySort = LibrarySort.edited,
    this.pinHash,
    this.pinSalt,
    this.lockAfterSeconds = 0,
  });

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        themeMode:
            enumByName(AppThemeMode.values, j['themeMode'], AppThemeMode.system),
        tidyEnabled: j['tidyEnabled'] as bool? ?? true,
        tidyStrength: enumByName(
            TidyStrength.values, j['tidyStrength'], TidyStrength.medium),
        slantMode: enumByName(SlantMode.values, j['slantMode'], SlantMode.keep),
        drawWithFinger: j['drawWithFinger'] as bool? ?? false,
        stylusButtonErases: j['stylusButtonErases'] as bool? ?? true,
        shapeSnapEnabled: j['shapeSnapEnabled'] as bool? ?? true,
        debugOverlay: j['debugOverlay'] as bool? ?? false,
        exportPaperLines: j['exportPaperLines'] as bool? ?? true,
        defaultPaper:
            Paper.fromJson(j['defaultPaper'] as Map<String, dynamic>?),
        librarySort:
            enumByName(LibrarySort.values, j['librarySort'], LibrarySort.edited),
        pinHash: j['pinHash'] as String?,
        pinSalt: j['pinSalt'] as String?,
        lockAfterSeconds: (j['lockAfterSeconds'] as num?)?.toInt() ?? 0,
      );

  static const String prefsKey = 'neatink.settings.v1';

  final AppThemeMode themeMode;

  /// "Tidy as you write" toolbar toggle (on by default).
  final bool tidyEnabled;
  final TidyStrength tidyStrength;
  final SlantMode slantMode;

  /// Let touch draw. Off by default: the pen draws, fingers navigate.
  final bool drawWithFinger;

  /// The pen's eraser end / button (inverted stylus) erases.
  final bool stylusButtonErases;

  /// Hold the pen still at the end of a stroke to snap it to a shape.
  final bool shapeSnapEnabled;

  /// Developer: draw detected baselines, x-height and slant.
  final bool debugOverlay;

  /// Draw paper lines/grid when exporting blank notebooks as PDF.
  final bool exportPaperLines;

  /// Paper preselected when creating a notebook.
  final Paper defaultPaper;
  final LibrarySort librarySort;

  /// App lock: salted SHA-256 of the PIN (hex). Null = no lock.
  final String? pinHash;
  final String? pinSalt;

  /// Lock again after the app was in the background this long (0 = always).
  final int lockAfterSeconds;

  bool get appLockEnabled => pinHash != null && pinSalt != null;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    bool? tidyEnabled,
    TidyStrength? tidyStrength,
    SlantMode? slantMode,
    bool? drawWithFinger,
    bool? stylusButtonErases,
    bool? shapeSnapEnabled,
    bool? debugOverlay,
    bool? exportPaperLines,
    Paper? defaultPaper,
    LibrarySort? librarySort,
    String? pinHash,
    String? pinSalt,
    bool clearPin = false,
    int? lockAfterSeconds,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        tidyEnabled: tidyEnabled ?? this.tidyEnabled,
        tidyStrength: tidyStrength ?? this.tidyStrength,
        slantMode: slantMode ?? this.slantMode,
        drawWithFinger: drawWithFinger ?? this.drawWithFinger,
        stylusButtonErases: stylusButtonErases ?? this.stylusButtonErases,
        shapeSnapEnabled: shapeSnapEnabled ?? this.shapeSnapEnabled,
        debugOverlay: debugOverlay ?? this.debugOverlay,
        exportPaperLines: exportPaperLines ?? this.exportPaperLines,
        defaultPaper: defaultPaper ?? this.defaultPaper,
        librarySort: librarySort ?? this.librarySort,
        pinHash: clearPin ? null : (pinHash ?? this.pinHash),
        pinSalt: clearPin ? null : (pinSalt ?? this.pinSalt),
        lockAfterSeconds: lockAfterSeconds ?? this.lockAfterSeconds,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'tidyEnabled': tidyEnabled,
        'tidyStrength': tidyStrength.name,
        'slantMode': slantMode.name,
        'drawWithFinger': drawWithFinger,
        'stylusButtonErases': stylusButtonErases,
        'shapeSnapEnabled': shapeSnapEnabled,
        'debugOverlay': debugOverlay,
        'exportPaperLines': exportPaperLines,
        'defaultPaper': defaultPaper.toJson(),
        'librarySort': librarySort.name,
        'pinHash': pinHash,
        'pinSalt': pinSalt,
        'lockAfterSeconds': lockAfterSeconds,
      };
}
