import 'dart:collection';

/// A least-recently-used map that evicts entries once their total size
/// exceeds [maxBytes].
///
/// [onEvict] runs for every entry that leaves the map (eviction, [remove],
/// [removeWhere], [clear], or replacement by [put]), so values holding
/// native memory (images) can be released there.
///
/// The most recently inserted entry is never evicted by its own insertion,
/// so a single value larger than the whole budget is still kept (alone).
class ByteBudgetLru<K, V> {
  ByteBudgetLru({
    required this.maxBytes,
    required this.sizeOf,
    this.onEvict,
  });

  final int maxBytes;
  final int Function(V value) sizeOf;
  final void Function(K key, V value)? onEvict;

  // Iteration order of a LinkedHashMap is insertion order, so re-inserting
  // on access keeps the least recently used entry first.
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();
  int _bytes = 0;

  /// Total size of all entries.
  int get bytes => _bytes;

  int get length => _map.length;

  bool get isEmpty => _map.isEmpty;

  bool containsKey(K key) => _map.containsKey(key);

  /// Entries from least to most recently used. Reading them does not count
  /// as a use.
  Iterable<MapEntry<K, V>> get entries => _map.entries;

  /// Returns the value for [key] and marks it as most recently used.
  V? get(K key) {
    final value = _map.remove(key);
    if (value == null) return null;
    _map[key] = value;
    return value;
  }

  /// Returns the value for [key] without changing its recency.
  V? peek(K key) => _map[key];

  /// Inserts or replaces [key] as the most recently used entry, then evicts
  /// old entries until the total fits the budget.
  void put(K key, V value) {
    final old = _map.remove(key);
    if (old != null) {
      _bytes -= sizeOf(old);
      if (!identical(old, value)) onEvict?.call(key, old);
    }
    _map[key] = value;
    _bytes += sizeOf(value);
    _trim();
  }

  /// Removes [key] (calling [onEvict]) and returns its value.
  V? remove(K key) {
    final value = _map.remove(key);
    if (value != null) {
      _bytes -= sizeOf(value);
      onEvict?.call(key, value);
    }
    return value;
  }

  /// Removes every entry for which [test] is true.
  void removeWhere(bool Function(K key, V value) test) {
    final doomed = [
      for (final e in _map.entries)
        if (test(e.key, e.value)) e.key,
    ];
    doomed.forEach(remove);
  }

  void clear() => removeWhere((_, _) => true);

  void _trim() {
    while (_bytes > maxBytes && _map.length > 1) {
      remove(_map.keys.first);
    }
  }
}
