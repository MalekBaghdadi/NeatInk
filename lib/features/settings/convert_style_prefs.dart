import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../document/font_kind.dart';
import '../../ink/stroke.dart' show colorFromHex, colorToHex;

/// The look the user last chose for converted handwriting: font, bold /
/// italic, size and colour. The "Convert to text" sheet saves it when the
/// user converts, and auto-convert types with it, so both give the same
/// result without asking again.
///
/// Persisted as one JSON string in shared_preferences under [prefsKey].
/// Defaults: Roboto, Auto size (match my handwriting), keep my ink colour.
class ConvertStylePrefs {
  const ConvertStylePrefs({
    this.fontId = 'sans',
    this.bold = false,
    this.italic = false,
    this.fixedSize,
    this.colorOverride,
  });

  factory ConvertStylePrefs.fromJson(Map<String, dynamic> j) {
    final size = j['size'];
    final colour = j['colour'];
    return ConvertStylePrefs(
      // An unknown id is kept as the default font (FontKind.byName).
      fontId: FontKind.byName(j['font'] is String ? j['font'] as String : null)
          .name,
      bold: j['bold'] == true,
      italic: j['italic'] == true,
      fixedSize: j['sizeMode'] == 'fixed' && size is num && size.isFinite && size > 0
          ? size.toDouble()
          : null,
      colorOverride: j['colourMode'] == 'fixed' && colour is String
          ? _tryColor(colour)
          : null,
    );
  }

  static const String prefsKey = 'neatink.convert_style.v1';

  /// A [FontKind.name].
  final String fontId;
  final bool bold;
  final bool italic;

  /// Font size in points, or null for "Auto (match my handwriting)".
  final double? fixedSize;

  /// ARGB colour for every converted line, or null for "Keep my ink colour".
  final int? colorOverride;

  FontKind get font => FontKind.byName(fontId);
  bool get autoSize => fixedSize == null;

  ConvertStylePrefs copyWith({
    String? fontId,
    bool? bold,
    bool? italic,
    double? fixedSize,
    bool clearFixedSize = false,
    int? colorOverride,
    bool clearColorOverride = false,
  }) =>
      ConvertStylePrefs(
        fontId: fontId ?? this.fontId,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        fixedSize: clearFixedSize ? null : (fixedSize ?? this.fixedSize),
        colorOverride:
            clearColorOverride ? null : (colorOverride ?? this.colorOverride),
      );

  Map<String, dynamic> toJson() => {
        'font': fontId,
        'bold': bold,
        'italic': italic,
        'sizeMode': fixedSize == null ? 'auto' : 'fixed',
        'size': fixedSize,
        'colourMode': colorOverride == null ? 'keep' : 'fixed',
        'colour': colorOverride == null ? null : colorToHex(colorOverride!),
      };

  @override
  bool operator ==(Object other) =>
      other is ConvertStylePrefs &&
      other.fontId == fontId &&
      other.bold == bold &&
      other.italic == italic &&
      other.fixedSize == fixedSize &&
      other.colorOverride == colorOverride;

  @override
  int get hashCode => Object.hash(fontId, bold, italic, fixedSize, colorOverride);

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
