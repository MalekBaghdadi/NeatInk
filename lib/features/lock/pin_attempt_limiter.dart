import 'dart:async';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Slows down PIN guessing. The first [freeAttempts] − 1 wrong PINs cost
/// nothing; the [freeAttempts]th starts a [baseCooldown] wait, and every
/// further wrong PIN doubles it (30 s, 1 min, 2 min, …) up to [maxCooldown].
/// A correct PIN resets everything.
///
/// The counters live in shared_preferences, so restarting the app doesn't
/// reset the wait.
class PinAttemptLimiter {
  PinAttemptLimiter(this._prefs, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const int freeAttempts = 5;
  static const Duration baseCooldown = Duration(seconds: 30);
  static const Duration maxCooldown = Duration(minutes: 30);

  static const String failuresKey = 'neatink.lock.failedAttempts';
  static const String lockedUntilKey = 'neatink.lock.lockedUntilMs';

  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  /// Wrong PINs entered since the last correct one.
  int get failedAttempts => max(0, _prefs.getInt(failuresKey) ?? 0);

  /// Wrong PINs still allowed before a cooldown starts (0 once in the
  /// cooldown regime).
  int get attemptsBeforeCooldown => max(0, freeAttempts - failedAttempts);

  /// The wait imposed after the [failures]th wrong PIN.
  static Duration cooldownAfter(int failures) {
    if (failures < freeAttempts) return Duration.zero;
    // 2^k grows fast; cap the exponent before shifting to avoid overflow.
    final doublings = min(failures - freeAttempts, 20);
    final ms = baseCooldown.inMilliseconds * (1 << doublings);
    return Duration(milliseconds: min(ms, maxCooldown.inMilliseconds));
  }

  /// How long until the next attempt is allowed ([Duration.zero] = now).
  ///
  /// If the device clock was moved backwards, the stored deadline could lie
  /// far in the future; the wait is then clamped to the cooldown that was
  /// actually imposed and the deadline is rewritten, so the user is never
  /// stuck longer than that.
  Duration remainingCooldown() {
    final until = _prefs.getInt(lockedUntilKey);
    if (until == null) return Duration.zero;
    final now = _clock().millisecondsSinceEpoch;
    final remainingMs = until - now;
    if (remainingMs <= 0) return Duration.zero;
    final capMs = cooldownAfter(failedAttempts).inMilliseconds;
    if (remainingMs > capMs) {
      unawaited(_prefs.setInt(lockedUntilKey, now + capMs));
      return Duration(milliseconds: capMs);
    }
    return Duration(milliseconds: remainingMs);
  }

  /// Whether a PIN may be checked right now.
  bool get canAttempt => remainingCooldown() == Duration.zero;

  /// Records a wrong PIN and returns the cooldown it started (possibly zero).
  Future<Duration> recordFailure() async {
    final failures = failedAttempts + 1;
    final cooldown = cooldownAfter(failures);
    await _prefs.setInt(failuresKey, failures);
    if (cooldown > Duration.zero) {
      await _prefs.setInt(
        lockedUntilKey,
        _clock().add(cooldown).millisecondsSinceEpoch,
      );
    }
    return cooldown;
  }

  /// Records a correct PIN: clears the failure count and any cooldown.
  Future<void> recordSuccess() async {
    await _prefs.remove(failuresKey);
    await _prefs.remove(lockedUntilKey);
  }
}
