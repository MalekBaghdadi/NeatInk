import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// Crash-safe file replacement.
///
/// Every write goes to a sibling temp file `<target>.tmp-<random>`, is
/// flushed to disk (`fsync`), and only then renamed over the target. A
/// rename within one directory is atomic, so readers (and a crash at any
/// moment) see either the complete old file or the complete new one, never
/// a partial write. On failure the temp file is deleted and the target is
/// untouched.
///
/// Temp files left behind by a crash are ignored by every reader and
/// removed by [removeStrayTemps]; files still being written by this
/// process are never removed.
abstract final class AtomicFile {
  /// Marker that identifies temp files in a file name.
  static const String tempMarker = '.tmp-';

  static final Random _random = Random();

  /// Base names of temp files currently being written by this isolate, so
  /// [removeStrayTemps] never deletes a write that is in progress.
  static final Set<String> _inFlight = {};

  /// True when [fileName] (a base name or path) is a temp file.
  static bool isTempName(String fileName) =>
      p.basename(fileName).contains(tempMarker);

  /// Writes [bytes] to [path] atomically. Creates the parent folder if
  /// needed.
  static Future<void> writeBytes(String path, List<int> bytes) async {
    final staged = await stageBytes(path, bytes);
    await staged.commit();
  }

  /// Copies [sourcePath] to [targetPath] atomically (the target appears
  /// only once the whole copy is on disk).
  static Future<void> copy(String sourcePath, String targetPath) async {
    final staged = await stageCopy(sourcePath, targetPath);
    await staged.commit();
  }

  /// Writes [bytes] to a new temp file next to [path] without touching
  /// [path] yet. Call [StagedFile.commit] to move it into place, or
  /// [StagedFile.discard] to drop it.
  static Future<StagedFile> stageBytes(String path, List<int> bytes) =>
      _stage(path, (raf) => raf.writeFrom(bytes));

  /// Like [stageBytes], streaming the contents of [sourcePath].
  static Future<StagedFile> stageCopy(String sourcePath, String targetPath) =>
      _stage(targetPath, (raf) async {
        await for (final chunk in File(sourcePath).openRead()) {
          await raf.writeFrom(chunk);
        }
      });

  static Future<StagedFile> _stage(
    String target,
    Future<void> Function(RandomAccessFile raf) fill,
  ) async {
    await Directory(p.dirname(target)).create(recursive: true);
    final tempPath = '$target$tempMarker${_token()}';
    final tempName = p.basename(tempPath);
    _inFlight.add(tempName);
    try {
      final raf = await File(tempPath).open(mode: FileMode.writeOnly);
      try {
        await fill(raf);
        // fsync, so the data is on disk before the rename makes it visible.
        await raf.flush();
      } finally {
        await raf.close();
      }
    } catch (_) {
      _inFlight.remove(tempName);
      await _deleteQuietly(File(tempPath));
      rethrow;
    }
    return StagedFile._(tempPath, target);
  }

  /// Deletes temp files in [dir] (not recursive) that no write in this
  /// process is using. Returns how many were removed. Errors are ignored:
  /// a leftover temp file is harmless.
  static Future<int> removeStrayTemps(Directory dir) async {
    var removed = 0;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.contains(tempMarker) || _inFlight.contains(name)) continue;
        if (await _deleteQuietly(entity)) removed++;
      }
    } on FileSystemException {
      // Folder missing or unreadable: nothing to clean.
    }
    return removed;
  }

  /// True when the temp file at [path] belongs to a write in progress.
  static bool isInFlight(String path) => _inFlight.contains(p.basename(path));

  static String _token() =>
      _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');

  static Future<bool> _deleteQuietly(File file) async {
    try {
      await file.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }
}

/// A fully written temp file waiting to replace its target. See
/// [AtomicFile.stageBytes].
class StagedFile {
  StagedFile._(this.tempPath, this.targetPath);

  /// Where the data currently is.
  final String tempPath;

  /// Where [commit] puts it.
  final String targetPath;

  bool _done = false;

  /// Renames the temp file over [targetPath] (atomic, replaces an existing
  /// file). If the rename fails the temp file is deleted and the error is
  /// rethrown; the target is left as it was.
  Future<void> commit() async {
    _checkOpen();
    try {
      await File(tempPath).rename(targetPath);
    } catch (_) {
      await AtomicFile._deleteQuietly(File(tempPath));
      rethrow;
    } finally {
      _finish();
    }
  }

  /// Deletes the temp file without touching the target.
  Future<void> discard() async {
    if (_done) return;
    _finish();
    await AtomicFile._deleteQuietly(File(tempPath));
  }

  void _checkOpen() {
    if (_done) throw StateError('Staged file already committed or discarded');
  }

  void _finish() {
    _done = true;
    AtomicFile._inFlight.remove(p.basename(tempPath));
  }
}
