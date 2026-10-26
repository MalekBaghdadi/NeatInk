import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../ink/stroke.dart';
import 'editor_tool.dart';

/// Preset colours and widths offered by the tool row.
abstract final class ToolPresets {
  /// The eight pen colours. White is always present so dark paper has a
  /// readable preset.
  static const List<int> penColors = [
    0xFF1E1E1E, // black
    0xFF1E5BD8, // blue
    0xFFD93025, // red
    0xFF188038, // green
    0xFFF28C00, // orange
    0xFF8E24AA, // purple
    0xFF00838F, // teal
    0xFFFFFFFF, // white
  ];

  /// Pen widths in points: fine, medium, bold.
  static const List<double> penWidths = [1.2, 2.2, 3.6];

  /// The six highlighter colours (drawn at 35% opacity).
  static const List<int> highlighterColors = [
    0xFFFFE600, // yellow
    0xFF76FF03, // green
    0xFF40C4FF, // blue
    0xFFFF4081, // pink
    0xFFFFAB40, // orange
    0xFFB388FF, // purple
  ];

  /// Highlighter widths in points.
  static const List<double> highlighterWidths = [8, 14, 22];

  /// Eraser diameters in points (small, medium, large).
  static const List<double> eraserSizes = [6, 14, 30];

  /// How many recently used custom colours are remembered.
  static const int maxRecentColors = 8;
}

/// Last-used pen settings.
class PenPrefs {
  const PenPrefs({
    this.color = 0xFF1E1E1E,
    this.size = 2.2,
    this.style = PenStyle.ballpoint,
  });

  factory PenPrefs.fromJson(Map<String, dynamic>? j) => j == null
      ? const PenPrefs()
      : PenPrefs(
          color: (j['color'] as num?)?.toInt() ?? 0xFF1E1E1E,
          size: _positive(j['size'], 2.2),
          style: enumByName(PenStyle.values, j['style'], PenStyle.ballpoint),
        );

  /// ARGB.
  final int color;

  /// Stroke width in points.
  final double size;
  final PenStyle style;

  PenPrefs copyWith({int? color, double? size, PenStyle? style}) => PenPrefs(
        color: color ?? this.color,
        size: size ?? this.size,
        style: style ?? this.style,
      );

  Map<String, dynamic> toJson() =>
      {'color': color, 'size': size, 'style': style.name};
}

/// Last-used highlighter settings.
class HighlighterPrefs {
  const HighlighterPrefs({this.color = 0xFFFFE600, this.size = 14});

  factory HighlighterPrefs.fromJson(Map<String, dynamic>? j) => j == null
      ? const HighlighterPrefs()
      : HighlighterPrefs(
          color: (j['color'] as num?)?.toInt() ?? 0xFFFFE600,
          size: _positive(j['size'], 14),
        );

  final int color;
  final double size;

  HighlighterPrefs copyWith({int? color, double? size}) =>
      HighlighterPrefs(color: color ?? this.color, size: size ?? this.size);

  Map<String, dynamic> toJson() => {'color': color, 'size': size};
}

/// Last-used eraser settings.
class EraserPrefs {
  const EraserPrefs({this.mode = EraserMode.stroke, this.size = 14});

  factory EraserPrefs.fromJson(Map<String, dynamic>? j) => j == null
      ? const EraserPrefs()
      : EraserPrefs(
          mode: enumByName(EraserMode.values, j['mode'], EraserMode.stroke),
          size: _positive(j['size'], 14),
        );

  final EraserMode mode;

  /// Eraser diameter in points.
  final double size;

  EraserPrefs copyWith({EraserMode? mode, double? size}) =>
      EraserPrefs(mode: mode ?? this.mode, size: size ?? this.size);

  Map<String, dynamic> toJson() => {'mode': mode.name, 'size': size};
}

/// Remembered tool state: the last tool plus colours, widths and styles per
/// tool. Persisted as one JSON string under [ToolPrefs.prefsKey].
///
/// [extra] keeps settings owned by integrations (e.g. the shape tool's
/// last shape) without this model having to know them; unknown keys found
/// in storage are preserved there too.
class ToolPrefs {
  const ToolPrefs({
    this.lastTool = EditorTool.pen,
    this.pen = const PenPrefs(),
    this.highlighter = const HighlighterPrefs(),
    this.eraser = const EraserPrefs(),
    this.recentColors = const [],
    this.extra = const {},
  });

  factory ToolPrefs.fromJson(Map<String, dynamic> j) => ToolPrefs(
        lastTool: enumByName(EditorTool.values, j['lastTool'], EditorTool.pen),
        pen: PenPrefs.fromJson(j['pen'] as Map<String, dynamic>?),
        highlighter:
            HighlighterPrefs.fromJson(j['highlighter'] as Map<String, dynamic>?),
        eraser: EraserPrefs.fromJson(j['eraser'] as Map<String, dynamic>?),
        recentColors: [
          for (final c in (j['recentColors'] as List<dynamic>? ?? const []))
            if (c is num) c.toInt(),
        ],
        extra: {
          for (final e in j.entries)
            if (!_knownKeys.contains(e.key)) e.key: e.value,
        },
      );

  static const String prefsKey = 'neatink.toolprefs.v1';

  static const Set<String> _knownKeys = {
    'lastTool',
    'pen',
    'highlighter',
    'eraser',
    'recentColors',
  };

  final EditorTool lastTool;
  final PenPrefs pen;
  final HighlighterPrefs highlighter;
  final EraserPrefs eraser;

  /// Custom colours picked recently, most recent first.
  final List<int> recentColors;

  /// Integration-owned settings, stored at the top level of the JSON.
  final Map<String, Object?> extra;

  ToolPrefs copyWith({
    EditorTool? lastTool,
    PenPrefs? pen,
    HighlighterPrefs? highlighter,
    EraserPrefs? eraser,
    List<int>? recentColors,
    Map<String, Object?>? extra,
  }) =>
      ToolPrefs(
        lastTool: lastTool ?? this.lastTool,
        pen: pen ?? this.pen,
        highlighter: highlighter ?? this.highlighter,
        eraser: eraser ?? this.eraser,
        recentColors: recentColors ?? this.recentColors,
        extra: extra ?? this.extra,
      );

  /// Moves [argb] to the front of [recentColors] (deduplicated, capped at
  /// [ToolPresets.maxRecentColors]).
  ToolPrefs withRecentColor(int argb) => copyWith(recentColors: [
        argb,
        for (final c in recentColors)
          if (c != argb) c,
      ].take(ToolPresets.maxRecentColors).toList(growable: false));

  Map<String, dynamic> toJson() => {
        ...extra,
        'lastTool': lastTool.name,
        'pen': pen.toJson(),
        'highlighter': highlighter.toJson(),
        'eraser': eraser.toJson(),
        'recentColors': recentColors,
      };
}

/// Loads and saves [ToolPrefs] in [SharedPreferences].
class ToolPrefsStore {
  ToolPrefsStore(this._prefs);

  final SharedPreferences _prefs;

  /// The stored preferences, or defaults when none are stored or the stored
  /// value can't be read.
  ToolPrefs load() {
    final raw = _prefs.getString(ToolPrefs.prefsKey);
    if (raw == null) return const ToolPrefs();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return ToolPrefs.fromJson(decoded);
    } on FormatException {
      // Fall through to defaults; a bad value must never block the editor.
    } on TypeError {
      // Same: a structurally unexpected value falls back to defaults.
    }
    return const ToolPrefs();
  }

  Future<void> save(ToolPrefs prefs) =>
      _prefs.setString(ToolPrefs.prefsKey, jsonEncode(prefs.toJson()));
}

double _positive(Object? v, double fallback) {
  if (v is num && v.isFinite && v > 0) return v.toDouble();
  return fallback;
}
