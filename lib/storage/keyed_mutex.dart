import 'dart:async';

/// Runs async actions one at a time per key, in call order.
///
/// The repository uses one key per notebook so that read-modify-write
/// sequences (search text, orphan cleanup) never interleave. Actions for
/// different keys run concurrently. Not re-entrant: an action must not
/// wait on another action with the same key.
class KeyedMutex {
  /// Key → completer of the last queued action for that key.
  final Map<String, Completer<void>> _tails = {};

  /// Runs [action] after every earlier action for [key] has finished
  /// (successfully or not) and returns its result.
  Future<T> run<T>(String key, Future<T> Function() action) {
    final previous = _tails[key]?.future;
    final done = Completer<void>();
    _tails[key] = done;

    Future<T> guarded() async {
      try {
        if (previous != null) await previous;
        return await action();
      } finally {
        done.complete();
        if (identical(_tails[key], done)) _tails.remove(key);
      }
    }

    return guarded();
  }

  /// Whether any action for [key] is running or queued.
  bool isLocked(String key) => _tails.containsKey(key);
}
