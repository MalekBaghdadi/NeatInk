import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import '../lock/pin_hasher.dart';
import 'app_settings.dart';

/// The app's settings. Read with `ref.watch(settingsProvider)` and change
/// with `ref.read(settingsProvider.notifier).update((s) => s.copyWith(...))`.
final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// Loads [AppSettings] from shared_preferences once and writes every change
/// back as a single JSON string under [AppSettings.prefsKey].
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() =>
      decodeSettings(ref.watch(sharedPreferencesProvider).getString(
            AppSettings.prefsKey,
          ));

  /// Applies [change] to the current settings and persists the result.
  ///
  /// The new state is visible immediately; the disk write happens in the
  /// background (shared_preferences updates its in-memory cache first).
  void update(AppSettings Function(AppSettings) change) {
    final next = change(state);
    state = next;
    unawaited(_persist(next));
  }

  /// Turns the app lock on (or changes the PIN) with a fresh random salt.
  /// [pin] must satisfy [PinHasher.isValidPin].
  void setPin(String pin) {
    if (!PinHasher.isValidPin(pin)) {
      throw ArgumentError.value(pin, 'pin', 'must be 4 to 8 digits');
    }
    final salt = PinHasher.newSalt();
    final hash = PinHasher.hash(pin, salt);
    update((s) => s.copyWith(pinHash: hash, pinSalt: salt));
  }

  /// Turns the app lock off.
  void clearPin() => update((s) => s.copyWith(clearPin: true));

  /// Whether [pin] matches the stored PIN. False when no PIN is set.
  bool verifyPin(String pin) {
    final s = state;
    final hash = s.pinHash, salt = s.pinSalt;
    if (hash == null || salt == null) return false;
    return PinHasher.verify(pin, salt: salt, expectedHash: hash);
  }

  Future<void> _persist(AppSettings settings) async {
    final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
    try {
      await prefs.setString(
          AppSettings.prefsKey, jsonEncode(settings.toJson()));
    } catch (e, st) {
      // The in-memory state is still correct; the next change retries.
      debugPrint('NeatInk: could not save settings: $e\n$st');
    }
  }
}

/// Parses stored settings JSON. Missing, unreadable or corrupt data (bad
/// JSON, a non-object, a field of the wrong type) yields the defaults, so a
/// bad prefs entry can never stop the app from starting. Missing fields and
/// unknown enum names fall back individually inside [AppSettings.fromJson].
@visibleForTesting
AppSettings decodeSettings(String? stored) {
  if (stored == null || stored.isEmpty) return const AppSettings();
  try {
    final Object? decoded = jsonDecode(stored);
    if (decoded is Map<String, dynamic>) return AppSettings.fromJson(decoded);
    debugPrint('NeatInk: settings are not a JSON object; using defaults');
  } catch (e) {
    debugPrint('NeatInk: settings are corrupt ($e); using defaults');
  }
  return const AppSettings();
}
