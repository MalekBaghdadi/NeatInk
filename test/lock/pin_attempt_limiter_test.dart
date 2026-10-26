import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/lock/pin_attempt_limiter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late DateTime now;
  DateTime clock() => now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 10, 25, 12);
  });

  PinAttemptLimiter limiter() => PinAttemptLimiter(prefs, clock: clock);

  Future<void> fail(PinAttemptLimiter l, int times) async {
    for (var i = 0; i < times; i++) {
      await l.recordFailure();
    }
  }

  group('cooldownAfter', () {
    test('is zero for the first four failures', () {
      for (var f = 0; f < 5; f++) {
        expect(PinAttemptLimiter.cooldownAfter(f), Duration.zero, reason: '$f');
      }
    });

    test('starts at 30 s on the fifth failure and doubles', () {
      expect(PinAttemptLimiter.cooldownAfter(5), const Duration(seconds: 30));
      expect(PinAttemptLimiter.cooldownAfter(6), const Duration(minutes: 1));
      expect(PinAttemptLimiter.cooldownAfter(7), const Duration(minutes: 2));
      expect(PinAttemptLimiter.cooldownAfter(8), const Duration(minutes: 4));
    });

    test('is capped at 30 minutes, even for huge counts', () {
      expect(PinAttemptLimiter.cooldownAfter(11), const Duration(minutes: 30));
      expect(PinAttemptLimiter.cooldownAfter(1000), const Duration(minutes: 30));
    });
  });

  test('four wrong PINs cost nothing', () async {
    final l = limiter();
    for (var i = 1; i <= 4; i++) {
      expect(await l.recordFailure(), Duration.zero);
      expect(l.canAttempt, isTrue);
      expect(l.attemptsBeforeCooldown, 5 - i);
    }
  });

  test('the fifth wrong PIN starts a 30 s cooldown', () async {
    final l = limiter();
    await fail(l, 4);
    expect(await l.recordFailure(), const Duration(seconds: 30));
    expect(l.canAttempt, isFalse);
    expect(l.remainingCooldown(), const Duration(seconds: 30));

    now = now.add(const Duration(seconds: 12));
    expect(l.remainingCooldown(), const Duration(seconds: 18));
    expect(l.canAttempt, isFalse);

    now = now.add(const Duration(seconds: 18));
    expect(l.remainingCooldown(), Duration.zero);
    expect(l.canAttempt, isTrue);
  });

  test('each further wrong PIN doubles the wait', () async {
    final l = limiter();
    await fail(l, 5);
    now = now.add(const Duration(seconds: 30));
    expect(await l.recordFailure(), const Duration(minutes: 1));
    expect(l.remainingCooldown(), const Duration(minutes: 1));
    now = now.add(const Duration(minutes: 1));
    expect(await l.recordFailure(), const Duration(minutes: 2));
    expect(l.failedAttempts, 7);
  });

  test('a correct PIN resets the count and the cooldown', () async {
    final l = limiter();
    await fail(l, 5);
    expect(l.canAttempt, isFalse);
    await l.recordSuccess();
    expect(l.failedAttempts, 0);
    expect(l.canAttempt, isTrue);
    expect(l.attemptsBeforeCooldown, 5);
    expect(await l.recordFailure(), Duration.zero);
  });

  test('the cooldown survives an app restart (new limiter, same prefs)',
      () async {
    await fail(limiter(), 5);
    now = now.add(const Duration(seconds: 10));

    // A fresh instance reading the persisted values, as after a restart.
    final restarted = PinAttemptLimiter(prefs, clock: clock);
    expect(restarted.failedAttempts, 5);
    expect(restarted.canAttempt, isFalse);
    expect(restarted.remainingCooldown(), const Duration(seconds: 20));
    expect(prefs.getInt(PinAttemptLimiter.failuresKey), 5);
    expect(prefs.getInt(PinAttemptLimiter.lockedUntilKey), isNotNull);
  });

  test('a clock moved backwards never extends the wait past the cooldown',
      () async {
    final l = limiter();
    await fail(l, 5);
    // The user sets the clock back by a day: the stored deadline now lies
    // a day + 30 s in the future.
    now = now.subtract(const Duration(days: 1));
    expect(l.remainingCooldown(), const Duration(seconds: 30));
    // The deadline was rewritten relative to the new clock.
    now = now.add(const Duration(seconds: 30));
    expect(l.canAttempt, isTrue);
  });

  test('ignores negative stored counts', () async {
    await prefs.setInt(PinAttemptLimiter.failuresKey, -3);
    expect(limiter().failedAttempts, 0);
  });
}
