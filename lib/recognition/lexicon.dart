import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// Asset with the English word list: one `word count` per line, lowercase,
/// most frequent first (see docs/htr-model-notes.md for the source).
const String lexiconAsset = 'assets/htr/word_freq.txt';

// Rows of the edit-distance table, reused across calls: the BK-tree search
// computes tens of thousands of distances per word.
Int32List _rowA = Int32List(64);
Int32List _rowB = Int32List(64);

/// Plain Levenshtein distance (insert, delete, substitute all cost 1).
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  if (b.length + 1 > _rowA.length) {
    _rowA = Int32List(b.length + 1);
    _rowB = Int32List(b.length + 1);
  }
  var prev = _rowA;
  var cur = _rowB;
  for (var j = 0; j <= b.length; j++) {
    prev[j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    final ca = a.codeUnitAt(i - 1);
    for (var j = 1; j <= b.length; j++) {
      final sub = prev[j - 1] + (ca == b.codeUnitAt(j - 1) ? 0 : 1);
      final del = prev[j] + 1;
      final ins = cur[j - 1] + 1;
      cur[j] = sub < del ? (sub < ins ? sub : ins) : (del < ins ? del : ins);
    }
    final tmp = prev;
    prev = cur;
    cur = tmp;
  }
  return prev[b.length];
}

/// Letter pairs a recogniser often mixes up in handwriting; replacing one by
/// the other is cheaper than an arbitrary substitution.
const List<String> _confusablePairs = [
  'ao', 'ou', 'oe', 'ec', 'ea', 'nu', 'nr', 'nm', 'mw', 'uv', 'vw', 'vy',
  'il', 'lt', 'it', 'fl', 'ft', 'hb', 'hk', 'gq', 'gy', 'pq', 'ij', 'cl',
  'ds', 'rs', 'sz', 'xz', 'kx', 'lk', 'ck', 'ra', 'rn', 'bd', 'dl', 'sa',
];

final Set<int> _confusable = {
  for (final p in _confusablePairs) ...[
    p.codeUnitAt(0) * 256 + p.codeUnitAt(1),
    p.codeUnitAt(1) * 256 + p.codeUnitAt(0),
  ],
};

/// Letters that are thin strokes in handwriting and so often get lost.
const String _narrowLetters = 'iltjf';

/// Edit distance weighted for handwriting: confusable letters substitute for
/// 0.6, narrow letters insert/delete for 0.8, everything else costs 1.
double weightedEditDistance(String a, String b) {
  if (a == b) return 0;
  double indel(int unit) => _narrowLetters.contains(String.fromCharCode(unit)) ? 0.8 : 1.0;
  var prev = List<double>.filled(b.length + 1, 0);
  for (var j = 1; j <= b.length; j++) {
    prev[j] = prev[j - 1] + indel(b.codeUnitAt(j - 1));
  }
  var cur = List<double>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    final ca = a.codeUnitAt(i - 1);
    cur[0] = prev[0] + indel(ca);
    for (var j = 1; j <= b.length; j++) {
      final cb = b.codeUnitAt(j - 1);
      final double subCost = ca == cb
          ? 0
          : (_confusable.contains(ca * 256 + cb) ? 0.6 : 1.0);
      cur[j] = math.min(
        prev[j - 1] + subCost,
        math.min(prev[j] + indel(ca), cur[j - 1] + indel(cb)),
      );
    }
    final tmp = prev;
    prev = cur;
    cur = tmp;
  }
  return prev[b.length];
}

/// A dictionary word near a query, with its corpus count.
class LexiconCandidate {
  const LexiconCandidate(this.word, this.count, this.distance);

  final String word;
  final int count;

  /// [weightedEditDistance] from the query.
  final double distance;
}

class _BkNode {
  _BkNode(this.word);

  final int word;
  List<int>? distances;
  List<_BkNode>? children;
}

/// English word frequencies with fast near-neighbour lookup (a BK-tree on
/// Levenshtein distance: about 5 ms per query for 50k words, and it needs no
/// large delete index in memory).
class Lexicon {
  Lexicon._(this._words, this._counts, this._byWord, this._total);

  /// Parses `word count` lines. Lines that do not parse are skipped, words
  /// are lowercased, and only the first [maxWords] distinct words are kept.
  factory Lexicon.parse(String text, {int maxWords = 100000}) {
    final words = <String>[];
    final counts = <int>[];
    final index = <String, int>{};
    var total = 0;
    for (final line in text.split('\n')) {
      final sp = line.indexOf(' ');
      if (sp <= 0) continue;
      final word = line.substring(0, sp).toLowerCase();
      final count = int.tryParse(line.substring(sp + 1).trim());
      if (count == null || count <= 0 || index.containsKey(word)) continue;
      index[word] = words.length;
      words.add(word);
      counts.add(count);
      total += count;
      if (words.length >= maxWords) break;
    }
    return Lexicon._(words, counts, index, total);
  }

  /// Loads and parses the bundled list (about 50k words).
  static Future<Lexicon> loadAsset({AssetBundle? bundle, String path = lexiconAsset}) async {
    final text = await (bundle ?? rootBundle).loadString(path);
    return Lexicon.parse(text);
  }

  final List<String> _words;
  final List<int> _counts;
  final Map<String, int> _byWord;
  final int _total;
  _BkNode? _root;

  int get length => _words.length;

  bool contains(String word) => _byWord.containsKey(word.toLowerCase());

  /// Count of [word] in the corpus, or null when it is not in the list.
  int? countOf(String word) {
    final i = _byWord[word.toLowerCase()];
    return i == null ? null : _counts[i];
  }

  /// ln(probability) of [word]: its share of all counted words. Null when
  /// the word is not in the list.
  double? logProb(String word) {
    final c = countOf(word);
    return c == null ? null : math.log(c / _total);
  }

  /// ln(probability) of the rarest listed word. Unknown words are scored
  /// below this (see `RescoreConfig.oovPenalty`).
  late final double minLogProb = _words.isEmpty
      ? math.log(1e-9)
      : math.log(_counts.reduce(math.min) / _total);

  _BkNode _tree() {
    final existing = _root;
    if (existing != null) return existing;
    final root = _BkNode(0);
    for (var w = 1; w < _words.length; w++) {
      var node = root;
      while (true) {
        final d = levenshtein(_words[w], _words[node.word]);
        final ds = node.distances ??= [];
        final at = ds.indexOf(d);
        if (at < 0) {
          ds.add(d);
          (node.children ??= []).add(_BkNode(w));
          break;
        }
        node = node.children![at];
      }
    }
    return _root = root;
  }

  /// Words within [maxEdits] Levenshtein edits of [word] (lowercase), the
  /// [limit] best by weighted distance with a small bonus for frequent words.
  /// Includes [word] itself when it is listed.
  List<LexiconCandidate> candidates(String word, {int maxEdits = 2, int limit = 150}) {
    if (_words.isEmpty) return const [];
    final q = word.toLowerCase();
    final found = <LexiconCandidate>[];
    final stack = <_BkNode>[_tree()];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      final w = _words[node.word];
      // Words whose length differs by more than maxEdits cannot match, so the
      // full distance is only needed to steer the search below.
      final d = levenshtein(q, w);
      if (d <= maxEdits) {
        found.add(LexiconCandidate(w, _counts[node.word], weightedEditDistance(q, w)));
      }
      final ds = node.distances;
      if (ds == null) continue;
      final kids = node.children!;
      for (var i = 0; i < ds.length; i++) {
        if (ds[i] >= d - maxEdits && ds[i] <= d + maxEdits) stack.add(kids[i]);
      }
    }
    double rank(LexiconCandidate c) => c.distance - 0.08 * math.log(c.count);
    found.sort((a, b) => rank(a).compareTo(rank(b)));
    return found.length > limit ? found.sublist(0, limit) : found;
  }
}
