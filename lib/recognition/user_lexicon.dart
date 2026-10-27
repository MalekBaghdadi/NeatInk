import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../storage/atomic_file.dart';
import 'lexicon.dart';

/// Where the personal dictionary lives between app runs.
abstract class UserLexiconStore {
  /// The saved words (as typed by the user), oldest first. Returns an empty
  /// list when nothing was saved yet or the data is unreadable.
  Future<List<String>> load();

  /// Replaces the saved words.
  Future<void> save(List<String> words);
}

/// Keeps the words in memory only (tests, and the default when no store is
/// given).
class InMemoryUserLexiconStore implements UserLexiconStore {
  InMemoryUserLexiconStore([Iterable<String> initial = const []]) : _words = [...initial];

  List<String> _words;

  /// Number of [save] calls so far.
  int saves = 0;

  /// The words as last saved.
  List<String> get saved => List.unmodifiable(_words);

  @override
  Future<List<String>> load() async => [..._words];

  @override
  Future<void> save(List<String> words) async {
    saves++;
    _words = [...words];
  }
}

/// Saves the words as JSON (`{"version": 1, "words": [...]}`) in
/// `<application documents>/recognition/user_lexicon.json`, with atomic
/// writes (temp file, then rename).
class JsonFileUserLexiconStore implements UserLexiconStore {
  /// [directory] resolves the folder lazily (default: the application
  /// documents directory from `path_provider`).
  JsonFileUserLexiconStore({
    Future<Directory> Function()? directory,
    this.subFolder = 'recognition',
    this.fileName = 'user_lexicon.json',
  }) : _directory = directory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directory;
  final String subFolder;
  final String fileName;

  Future<File> _file() async {
    final dir = await _directory();
    return File(p.join(dir.path, subFolder, fileName));
  }

  @override
  Future<List<String>> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return const [];
      final json = jsonDecode(await file.readAsString());
      final words = json is Map<String, dynamic> ? json['words'] : null;
      if (words is! List) return const [];
      return [
        for (final w in words)
          if (w is String) w,
      ];
    } catch (e) {
      debugPrint('NeatInk: personal dictionary unreadable: $e');
      return const [];
    }
  }

  @override
  Future<void> save(List<String> words) async {
    final file = await _file();
    final text = const JsonEncoder.withIndent('  ').convert({'version': 1, 'words': words});
    await AtomicFile.writeBytes(file.path, utf8.encode('$text\n'));
  }
}

/// The user's personal dictionary: names, places and jargon the word list
/// does not know. Entries keep their capitalisation exactly as the user typed
/// them (`Malek`, `Baghdadi`, `NASA`) and get a high language prior in the
/// rescorer, so the recogniser prefers them when the image allows.
///
/// The UI fills it with [learn] whenever the user corrects a recognised word.
/// All lookups are synchronous; changes are saved in the background through
/// the [UserLexiconStore] (use [flush] to wait for it).
class UserLexicon {
  UserLexicon({UserLexiconStore? store, this.maxWords = 5000})
      : _store = store ?? InMemoryUserLexiconStore();

  final UserLexiconStore _store;

  /// The oldest entries are dropped beyond this many.
  final int maxWords;

  /// Shortest and longest word that is accepted.
  static const int minLength = 2;
  static const int maxLength = 40;

  // lowercase -> the form the user typed; insertion ordered.
  final Map<String, String> _forms = {};
  Future<void>? _loading;
  Future<void> _saving = Future<void>.value();

  static final RegExp _wordShape = RegExp(r"^[A-Za-z]+(?:'[A-Za-z]+)?$");
  static final RegExp _chunkSeparators = RegExp(r'[\s\-\u2010-\u2015/\\|_]+');
  static final RegExp _surroundingPunctuation = RegExp(r'^[\s\p{P}\p{S}]+|[\s\p{P}\p{S}]+$', unicode: true);

  /// Reads the saved words (once). Safe to call repeatedly; words added
  /// before the load finished are kept.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final saved = await _store.load();
      final current = Map<String, String>.of(_forms);
      _forms.clear();
      for (final w in saved) {
        final form = normalize(w);
        if (form != null) _forms[form.toLowerCase()] = form;
      }
      _forms.addAll(current);
    } catch (e) {
      debugPrint('NeatInk: personal dictionary could not be loaded: $e');
    }
  }

  /// The words in the order they were added, as typed.
  List<String> get words => List.unmodifiable(_forms.values);

  int get length => _forms.length;

  bool get isEmpty => _forms.isEmpty;

  /// Whether [word] (any capitalisation) is in the dictionary.
  bool contains(String word) => _forms.containsKey(word.toLowerCase());

  /// The stored spelling of [word] (`Malek` for `malek`), or null.
  String? formOf(String word) => _forms[word.toLowerCase()];

  /// [word] cleaned for storage (surrounding punctuation removed, a
  /// typographic apostrophe fixed, a possessive `'s` dropped), or null when
  /// it is not a plain Latin word (digits, accents, hyphens inside ...).
  static String? normalize(String word) {
    var w = word.replaceAll('\u2019', "'").replaceAll(_surroundingPunctuation, '');
    if (w.length > 2 && w.endsWith("'s") && _wordShape.hasMatch(w.substring(0, w.length - 2))) {
      w = w.substring(0, w.length - 2);
    }
    if (w.length < minLength || w.length > maxLength || !_wordShape.hasMatch(w)) return null;
    return w;
  }

  /// Adds [word] with the spelling and capitalisation given. Returns true
  /// when the dictionary changed (a new word, or a new spelling of a known
  /// one).
  bool add(String word) {
    final form = normalize(word);
    if (form == null) return false;
    final key = form.toLowerCase();
    if (_forms[key] == form) return false;
    // Re-adding moves the word to the end, so it survives trimming longest.
    _forms.remove(key);
    _forms[key] = form;
    while (_forms.length > maxWords) {
      _forms.remove(_forms.keys.first);
    }
    _scheduleSave();
    return true;
  }

  /// Learns from text the user typed or corrected: every plain word of
  /// [correctedWord] (one word, or several) is added unless [isKnownWord]
  /// says the word list already knows it (it gets the lowercase spelling).
  /// Returns how many entries were added or changed.
  int learn(String correctedWord, {bool Function(String lowercase)? isKnownWord}) {
    var changed = 0;
    for (final chunk in correctedWord.split(_chunkSeparators)) {
      final word = normalize(chunk);
      if (word == null) continue;
      if (isKnownWord != null && isKnownWord(word.toLowerCase())) continue;
      if (add(word)) changed++;
    }
    return changed;
  }

  /// Removes [word]; true when it was there.
  bool remove(String word) {
    final removed = _forms.remove(word.toLowerCase()) != null;
    if (removed) _scheduleSave();
    return removed;
  }

  void clear() {
    if (_forms.isEmpty) return;
    _forms.clear();
    _scheduleSave();
  }

  /// Stored spellings within [maxEdits] Levenshtein edits of [lowercase].
  List<String> nearby(String lowercase, int maxEdits) {
    final out = <String>[];
    for (final e in _forms.entries) {
      if ((e.key.length - lowercase.length).abs() > maxEdits) continue;
      if (levenshtein(lowercase, e.key) <= maxEdits) out.add(e.value);
    }
    return out;
  }

  void _scheduleSave() {
    _saving = _saving.then((_) async {
      await load(); // never overwrite saved words that were not read yet
      await _store.save(words);
    }).catchError((Object e) {
      debugPrint('NeatInk: personal dictionary could not be saved: $e');
    });
  }

  /// Completes when every change so far has been saved.
  Future<void> flush() => _saving;
}
