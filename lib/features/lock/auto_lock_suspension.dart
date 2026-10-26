/// Lets a feature send the user to a system screen (file picker, share
/// sheet, document saver) without the app lock appearing when they come
/// back to NeatInk.
///
/// Opening such a screen moves NeatInk to the background, which normally
/// starts the lock timeout ("Lock after: immediately" would lock at once).
/// While [during] is running, `LockGate` instead allows at least
/// [minimumTimeout] in the background before locking.
///
/// ```dart
/// final result = await AutoLockSuspension.during(
///   () => FilePicker.platform.pickFiles(type: FileType.custom,
///       allowedExtensions: ['pdf']),
/// );
/// ```
abstract final class AutoLockSuspension {
  /// Background time allowed while suspended, unless the user's own
  /// timeout is longer.
  static const Duration minimumTimeout = Duration(minutes: 5);

  static int _depth = 0;

  /// Whether some [during] call is in progress.
  static bool get isActive => _depth > 0;

  /// Runs [action] with the auto-lock relaxed. Calls may nest.
  static Future<T> during<T>(Future<T> Function() action) async {
    _depth++;
    try {
      return await action();
    } finally {
      _depth--;
    }
  }
}
