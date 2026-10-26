import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'pin_attempt_limiter.dart';

/// The shared wrong-PIN limiter, used by the lock screen and by the PIN
/// change/remove flows in Settings (they share one counter).
final pinAttemptLimiterProvider = Provider<PinAttemptLimiter>(
  (ref) => PinAttemptLimiter(
    ref.watch(sharedPreferencesProvider),
    clock: ref.watch(clockProvider),
  ),
);
