import '../editor/tool_prefs.dart';
import 'app_settings.dart';
import 'convert_style_prefs.dart';

/// The part of a backup that is not notebooks (`app.json`): settings, pen
/// choices, the typed-text look and My words.
///
/// The app lock (PIN hash and salt, lock timeout) is never put in a backup:
/// the file may be copied anywhere, and a short PIN's hash is easy to break.
abstract final class BackupAppData {
  static const String settingsKey = 'settings';
  static const String toolPrefsKey = 'toolPrefs';
  static const String convertStyleKey = 'convertStyle';
  static const String myWordsKey = 'myWords';

  /// Settings fields that stay with the device.
  static const Set<String> _deviceOnly = {
    'pinHash',
    'pinSalt',
    'lockAfterSeconds',
    'lastBackupAt',
    'tipsSeen',
  };

  static Map<String, Object?> collect({
    required AppSettings settings,
    required ToolPrefs toolPrefs,
    required ConvertStylePrefs convertStyle,
    required List<String> myWords,
  }) =>
      {
        settingsKey: {
          for (final e in settings.toJson().entries)
            if (!_deviceOnly.contains(e.key)) e.key: e.value,
        },
        toolPrefsKey: toolPrefs.toJson(),
        convertStyleKey: convertStyle.toJson(),
        myWordsKey: myWords,
      };

  /// Whether [data] holds settings that can be restored.
  static bool hasSettings(Map<String, Object?> data) =>
      data[settingsKey] is Map<String, dynamic>;

  /// The saved words, or none.
  static List<String> myWords(Map<String, Object?> data) => [
        if (data[myWordsKey] case final List<Object?> words)
          for (final w in words)
            if (w is String) w,
      ];

  /// The backup's settings on top of [current], keeping this device's app
  /// lock, last-backup date and tips state. Null when there are none.
  static AppSettings? settings(Map<String, Object?> data, AppSettings current) {
    final saved = data[settingsKey];
    if (saved is! Map<String, dynamic>) return null;
    final AppSettings restored;
    try {
      restored = AppSettings.fromJson(saved);
    } catch (_) {
      return null;
    }
    return restored.copyWith(
      pinHash: current.pinHash,
      pinSalt: current.pinSalt,
      clearPin: !current.appLockEnabled,
      lockAfterSeconds: current.lockAfterSeconds,
      lastBackupAt: current.lastBackupAt,
      tipsSeen: current.tipsSeen,
    );
  }

  static ToolPrefs? toolPrefs(Map<String, Object?> data) {
    final saved = data[toolPrefsKey];
    if (saved is! Map<String, dynamic>) return null;
    try {
      return ToolPrefs.fromJson(saved);
    } catch (_) {
      return null;
    }
  }

  static ConvertStylePrefs? convertStyle(Map<String, Object?> data) {
    final saved = data[convertStyleKey];
    if (saved is! Map<String, dynamic>) return null;
    try {
      return ConvertStylePrefs.fromJson(saved);
    } catch (_) {
      return null;
    }
  }
}
