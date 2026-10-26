import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'atomic_file.dart';
import 'storage_errors.dart';

/// Turns a decoded JSON object into a model. Throwing (FormatException,
/// TypeError...) marks the document as unreadable.
typedef JsonParser<T> = T Function(Map<String, dynamic> json);

/// Which copy of a document a read came from.
enum JsonSource { main, backup }

class JsonReadResult<T> {
  const JsonReadResult(this.value, this.source);

  final T value;
  final JsonSource source;

  bool get fromBackup => source == JsonSource.backup;
}

/// Path of the previous good copy of [path].
String backupPathFor(String path) => '$path.bak';

/// Where an unreadable main file is kept when it is replaced, so even a
/// corrupt file is never destroyed by a save.
String corruptPathFor(String path) => '$path.corrupt';

/// Encodes [json] as UTF-8 JSON bytes. [pretty] indents with two spaces
/// (used for the small, human-inspected files).
Uint8List encodeJsonBytes(Object? json, {bool pretty = false}) {
  final text = pretty
      ? const JsonEncoder.withIndent('  ').convert(json)
      : jsonEncode(json);
  return utf8.encode(text);
}

/// Reads the document at [path] synchronously, falling back to its `.bak`
/// copy when the main file is missing or cannot be parsed.
///
/// Returns null when neither file exists. Throws [CorruptFileException]
/// when a file exists but no copy can be parsed. Never modifies or deletes
/// anything. Synchronous so it can run whole inside a background isolate.
JsonReadResult<T>? readJsonDocumentSync<T>(String path, JsonParser<T> parse) {
  Object? firstError;
  for (final source in JsonSource.values) {
    final file = File(source == JsonSource.main ? path : backupPathFor(path));
    final String text;
    try {
      text = file.readAsStringSync();
    } on PathNotFoundException {
      continue;
    } catch (e) {
      firstError ??= e;
      continue;
    }
    try {
      return JsonReadResult(parse(_decodeObject(text)), source);
    } catch (e) {
      firstError ??= e;
    }
  }
  if (firstError != null) throw CorruptFileException(path, firstError);
  return null;
}

Map<String, dynamic> _decodeObject(String text) {
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Top-level JSON value is not an object');
  }
  return decoded;
}

// The background helpers are top-level so their closures capture only
// their arguments (an instance method's closure could drag `this`, and
// everything it references, into the isolate message).
Future<JsonReadResult<T>?> _readInBackground<T>(
  String path,
  JsonParser<T> parse,
) =>
    Isolate.run(() => readJsonDocumentSync(path, parse));

Future<bool> _checkInBackground(String path) =>
    Isolate.run(() => _isJsonObjectFileSync(path));

bool _isJsonObjectFileSync(String path) {
  try {
    _decodeObject(File(path).readAsStringSync());
    return true;
  } catch (_) {
    return false;
  }
}

/// Crash-safe JSON documents: atomic writes, a `.bak` copy of the previous
/// good version, and reads that fall back to it.
///
/// Write sequence for `notebook.json`:
/// 1. the new bytes go to `notebook.json.tmp-<random>` and are fsynced;
/// 2. the current `notebook.json`, if known to be good, is renamed to
///    `notebook.json.bak` (an unreadable one is kept as `.corrupt`
///    instead, so a bad file never replaces a good backup);
/// 3. the temp file is renamed to `notebook.json`.
///
/// A crash between 2 and 3 leaves no main file; readers then use the
/// `.bak`, which holds the previous complete version.
///
/// Files larger than [backgroundThresholdBytes] are read and parsed in a
/// background isolate so big pages never stall the UI. Parsers passed to
/// [read] must therefore be sendable: top-level functions or static
/// tear-offs such as `PageContent.fromJson`, not closures over objects.
class JsonDocumentStore {
  JsonDocumentStore({
    this.backgroundThresholdBytes = 1 << 20,
    this._log,
  });

  /// Files at least this big are decoded off the calling isolate.
  final int backgroundThresholdBytes;

  final void Function(String message)? _log;

  /// Main files known to hold a valid document (read or written by this
  /// store), keyed by normalized path. Only these are promoted to `.bak`
  /// without re-checking them.
  final Set<String> _verified = {};

  /// Reads the document at [path] (or its `.bak`); null when neither
  /// exists. Throws [CorruptFileException] when no copy is readable.
  Future<T?> read<T>(String path, JsonParser<T> parse) async =>
      (await readWithSource(path, parse))?.value;

  /// Like [read], also telling whether the backup was used.
  Future<JsonReadResult<T>?> readWithSource<T>(
    String path,
    JsonParser<T> parse,
  ) async {
    final size = await _sizeOf(path) ?? await _sizeOf(backupPathFor(path));
    if (size == null) return null;

    final JsonReadResult<T>? result;
    if (size >= backgroundThresholdBytes) {
      result = await _readInBackground(path, parse);
    } else {
      result = await _readOnThisIsolate(path, parse);
    }
    if (result == null) return null;
    if (result.fromBackup) {
      _log?.call('NeatInk storage: $path unreadable, using its backup copy');
    } else {
      _verified.add(_key(path));
    }
    return result;
  }

  Future<JsonReadResult<T>?> _readOnThisIsolate<T>(
    String path,
    JsonParser<T> parse,
  ) async {
    Object? firstError;
    for (final source in JsonSource.values) {
      final file = File(source == JsonSource.main ? path : backupPathFor(path));
      final String text;
      try {
        text = await file.readAsString();
      } on PathNotFoundException {
        continue;
      } catch (e) {
        firstError ??= e;
        continue;
      }
      try {
        return JsonReadResult(parse(_decodeObject(text)), source);
      } catch (e) {
        firstError ??= e;
      }
    }
    if (firstError != null) throw CorruptFileException(path, firstError);
    return null;
  }

  /// Atomically replaces the document at [path] with [utf8Json], keeping
  /// the previous good version as `<path>.bak`.
  Future<void> write(String path, List<int> utf8Json) async {
    final staged = await AtomicFile.stageBytes(path, utf8Json);
    try {
      await _retireCurrent(path);
      await staged.commit();
    } catch (_) {
      await staged.discard();
      rethrow;
    }
    _verified.add(_key(path));
  }

  /// Moves the current main file out of the way: to `.bak` when it is a
  /// valid document, to `.corrupt` when it is not.
  Future<void> _retireCurrent(String path) async {
    final size = await _sizeOf(path);
    if (size == null) return;
    final bool good;
    if (_verified.contains(_key(path))) {
      good = true;
    } else if (size >= backgroundThresholdBytes) {
      good = await _checkInBackground(path);
    } else {
      good = await _isJsonObjectFile(path);
    }
    if (!good) {
      _log?.call('NeatInk storage: keeping unreadable $path as .corrupt');
    }
    await File(path).rename(good ? backupPathFor(path) : corruptPathFor(path));
  }

  Future<bool> _isJsonObjectFile(String path) async {
    try {
      _decodeObject(await File(path).readAsString());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether a main or backup copy of [path] exists.
  Future<bool> exists(String path) async =>
      await File(path).exists() || await File(backupPathFor(path)).exists();

  /// Forgets what this store knows about files under [folder] (call after
  /// deleting or moving it).
  void forgetUnder(String folder) {
    final prefix = '${_key(folder)}${p.separator}';
    _verified.removeWhere((k) => k.startsWith(prefix));
  }

  /// Forgets what this store knows about the file at [path].
  void forget(String path) => _verified.remove(_key(path));

  static String _key(String path) => p.normalize(p.absolute(path));

  static Future<int?> _sizeOf(String path) async {
    final stat = await FileStat.stat(path);
    return stat.type == FileSystemEntityType.file ? stat.size : null;
  }
}
