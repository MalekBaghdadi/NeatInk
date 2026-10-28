import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../document/font_kind.dart';
import '../../ink/stroke.dart' show colorFromHex, colorToHex;

/// How big converted text is.
enum ConvertSizeMode {
  /// One size for every line, chosen from the page: it fits the ruled lines
  /// (16 pt on paper without lines). The default.
  even('Even size'),

  /// Each line as big as its handwriting.
  handwriting('Match my handwriting'),

  /// A size the user picked ([ConvertStylePrefs.fixedSize]).
  custom('Custom');

  const ConvertSizeMode(this.label);
  final String label;
}

/// The look the user last chose for converted handwriting: font, bold /
/// italic, size and colour. The "Convert to text" sheet saves it when the
/// user converts, and auto-convert types with it, so both give the same
/// result without asking again.
///
/// Persisted as one JSON string in shared_preferences under [prefsKey].
/// Defaults: Roboto, even size, keep my ink colour, join lines.
class ConvertStylePrefs {
  const ConvertStylePrefs({
    this.fontId = 'sans',
    this.bold = false,
    this.italic = false,
    this.sizeMode = ConvertSizeMode.even,
    this.fixedSize,
    this.colorOverride,
    this.joinLines = true,
  });

  factory ConvertStylePrefs.fromJson(Map<String, dynamic> j) {
    final size = j['size'];
    final colour = j['colour'];
    final validSize = size is num && size.isFinite && size > 0;
    return ConvertStylePrefs(
      // An unknown id is kept as the default font (FontKind.byName).
      fontId: FontKind.byName(j['font'] is String ? j['font'] as String : null)
          .name,
      bold: j['bold'] == true,
      italic: j['italic'] == true,
      // Before 1.5.0 the default was "auto" (match my handwriting), which
      // gave every line its own size; it reads as the even size now.
      sizeMode: switch (j['sizeMode']) {
        'fixed' when validSize => ConvertSizeMode.custom,
        'handwriting' => ConvertSizeMode.handwriting,
        _ => ConvertSizeMode.even,
      },
      fixedSize: validSize ? size.toDouble() : null,
      colorOverride: j['colourMode'] == 'fixed' && colour is String
          ? _tryColor(colour)
          : null,
      joinLines: j['joinLines'] is bool ? j['joinLines'] as bool : true,
    );
  }

  static const String prefsKey = 'neatink.convert_style.v1';

  /// A [FontKind.name].
  final String fontId;
  final bool bold;
  final bool italic;

  /// How big the typed text is ([ConvertSizeMode]).
  final ConvertSizeMode sizeMode;

  /// The size in points for [ConvertSizeMode.custom] (remembered while
  /// another mode is chosen); null: not chosen yet.
  final double? fixedSize;

  /// ARGB colour for every converted line, or null for "Keep my ink colour".
  final int? colorOverride;

  /// A sentence written over several lines (the writer ran out of room at
  /// the right edge) becomes one text box that wraps at the page edge.
  final bool joinLines;

  FontKind get font => FontKind.byName(fontId);
  bool get autoSize => sizeMode == ConvertSizeMode.handwriting;

  ConvertStylePrefs copyWith({
    String? fontId,
    bool? bold,
    bool? italic,
    ConvertSizeMode? sizeMode,
    double? fixedSize,
    bool clearFixedSize = false,
    int? colorOverride,
    bool clearColorOverride = false,
    bool? joinLines,
  }) =>
      ConvertStylePrefs(
        fontId: fontId ?? this.fontId,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        sizeMode: sizeMode ?? this.sizeMode,
        fixedSize: clearFixedSize ? null : (fixedSize ?? this.fixedSize),
        colorOverride:
            clearColorOverride ? null : (colorOverride ?? this.colorOverride),
        joinLines: joinLines ?? this.joinLines,
      );

  Map<String, dynamic> toJson() => {
        'font': fontId,
        'bold': bold,
        'italic': italic,
        'sizeMode': switch (sizeMode) {
          ConvertSizeMode.even => 'even',
          ConvertSizeMode.handwriting => 'handwriting',
          ConvertSizeMode.custom => 'fixed',
        },
        'size': fixedSize,
        'colourMode': colorOverride == null ? 'keep' : 'fixed',
        'colour': colorOverride == null ? null : colorToHex(colorOverride!),
        'joinLines': joinLines,
      };

  @override
  bool operator ==(Object other) =>
      other is ConvertStylePrefs &&
      other.fontId == fontId &&
      other.bold == bold &&
      other.italic == italic &&
      other.sizeMode == sizeMode &&
      other.fixedSize == fixedSize &&
      other.colorOverride == colorOverride &&
      other.joinLines == joinLines;

  @override
  int get hashCode =>
      Object.hash(fontId, bold, italic, sizeMode, fixedSize, colorOverride, joinLines);

  static int? _tryColor(String hex) {
    try {
      return colorFromHex(hex);
    } catch (_) {
      return null;
    }
  }
}

/// Parses the stored string; missing or corrupt data gives the defaults.
@visibleForTesting
ConvertStylePrefs decodeConvertStylePrefs(String? stored) {
  if (stored == null || stored.isEmpty) return const ConvertStylePrefs();
  try {
    final Object? decoded = jsonDecode(stored);
    if (decoded is Map<String, dynamic>) {
      return ConvertStylePrefs.fromJson(decoded);
    }
  } catch (e) {
    debugPrint('NeatInk: convert style is corrupt ($e); using defaults');
  }
  return const ConvertStylePrefs();
}

/// The remembered convert look. Read with
/// `ref.watch(convertStylePrefsProvider)`, change with
/// `ref.read(convertStylePrefsProvider.notifier).save(prefs)`.
final convertStylePrefsProvider =
    NotifierProvider<ConvertStylePrefsController, ConvertStylePrefs>(
  ConvertStylePrefsController.new,
);

class ConvertStylePrefsController extends Notifier<ConvertStylePrefs> {
  @override
  ConvertStylePrefs build() => decodeConvertStylePrefs(
      ref.watch(sharedPreferencesProvider).getString(ConvertStylePrefs.prefsKey));

  /// Makes [prefs] the remembered look and writes it in the background.
  void save(ConvertStylePrefs prefs) {
    if (prefs == state) return;
    state = prefs;
    unawaited(_persist(prefs));
  }

  Future<void> _persist(ConvertStylePrefs prefs) async {
    try {
      await ref
          .read(sharedPreferencesProvider)
          .setString(ConvertStylePrefs.prefsKey, jsonEncode(prefs.toJson()));
    } catch (e) {
      // The in-memory look is still right; the next change retries.
      debugPrint('NeatInk: could not save the convert style: $e');
    }
  }
}
