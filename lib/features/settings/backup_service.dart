import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/app_info.dart';
import '../../app/providers.dart';
import '../../storage/backup/notebook_backup.dart';
import '../../storage/file_notebook_repository.dart';
import '../lock/auto_lock_suspension.dart';

/// Everything the backup screens need from the outside world (the storage
/// folder, the system pickers), behind one interface so the flows can be
/// tested with a fake.
abstract interface class BackupService {
  /// Writes a backup with [appData] to a temporary file and returns its
  /// path. Throws [BackupException].
  Future<String> create(Map<String, Object?> appData,
      {required BackupProgress onProgress});

  /// Lets the user choose where to save the backup at [path] (system "Save
  /// to" dialog). False when they cancelled.
  Future<bool> save(String path, String fileName);

  /// Lets the user pick a backup file. Returns a local path, or null.
  Future<String?> pick();

  /// Reads what the backup at [path] holds. Throws [BackupException].
  Future<BackupInfo> inspect(String path);

  /// Restores [items] from the backup at [path] into the storage folder.
  Future<RestoreResult> restore(String path, List<RestoreItem> items,
      {required BackupProgress onProgress});

  /// Removes a temporary file made by [create] or [pick]. Never throws.
  Future<void> discard(String path);
}

/// The storage folder backups are made from and restored into (the one with
/// `library.json` and `notebooks/`), or null when notebooks are not stored
/// in files (tests).
final backupRootProvider = Provider<Directory?>((ref) {
  final repo = ref.watch(notebookRepositoryProvider);
  return repo is FileNotebookRepository ? repo.root : null;
});

final backupServiceProvider = Provider<BackupService?>((ref) {
  final root = ref.watch(backupRootProvider);
  return root == null ? null : DefaultBackupService(root.path);
});

/// `MariamsNotes-backup-2026-10-28.zip`
String backupFileName(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  final app = AppInfo.name.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  return '$app-backup-${now.year}-${two(now.month)}-${two(now.day)}.zip';
}

/// The real service: the backup work runs in a background isolate, saving
/// goes through `FileSavePlugin.kt` (streams the file, so large backups
/// never sit in memory) and picking through file_picker.
class DefaultBackupService implements BackupService {
  DefaultBackupService(this.rootPath);

  final String rootPath;

  static const MethodChannel _channel = MethodChannel('neatink/file_save');

  @override
  Future<String> create(Map<String, Object?> appData,
      {required BackupProgress onProgress}) async {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'backups'));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final out = p.join(dir.path, 'backup.zip');
    final root = rootPath;
    await _withProgress(
        onProgress,
        (progress) => writeBackup(
            rootPath: root,
            outputPath: out,
            appData: appData,
            appVersion: AppInfo.displayVersion,
            onProgress: progress));
    return out;
  }

  @override
  Future<bool> save(String path, String fileName) =>
      AutoLockSuspension.during(() async {
        try {
          return await _channel.invokeMethod<bool>('saveCopy', {
                'path': path,
                'fileName': fileName,
                'mimeType': 'application/zip',
              }) ??
              false;
        } on PlatformException catch (e) {
          throw BackupException('The backup could not be saved there (${e.message}).');
        }
      });

  @override
  Future<String?> pick() async {
    final file = await AutoLockSuspension.during<PlatformFile?>(
        () => FilePicker.pickFile(type: FileType.any));
    if (file == null) return null;
    if (file.path != null) return file.path;
    // Only a content URI: stream it into a temp file (never all in memory).
    final dir = await Directory.systemTemp.createTemp('neatink_restore_');
    final target = File(p.join(dir.path, 'backup.zip'));
    final sink = target.openWrite();
    try {
      await sink.addStream(file.readAsByteStream());
    } finally {
      await sink.close();
    }
    return target.path;
  }

  @override
  Future<BackupInfo> inspect(String path) => Isolate.run(() => readBackupInfo(path));

  @override
  Future<RestoreResult> restore(String path, List<RestoreItem> items,
      {required BackupProgress onProgress}) {
    final root = rootPath;
    return _withProgress(
        onProgress,
        (progress) => restoreNotebooks(
            zipPath: path, rootPath: root, items: items, onProgress: progress));
  }

  @override
  Future<void> discard(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
      if (p.basename(f.parent.path).startsWith('neatink_restore_')) {
        await f.parent.delete(recursive: true);
      }
      await FilePicker.clearTemporaryFiles();
    } catch (e) {
      debugPrint('NeatInk: could not remove backup temp file: $e');
    }
  }

  /// Runs [job] in a background isolate, forwarding its progress reports.
  static Future<T> _withProgress<T>(BackupProgress onProgress,
      Future<T> Function(BackupProgress progress) job) async {
    final port = ReceivePort();
    port.listen((m) {
      if (m case (final int done, final int total)) onProgress(done, total);
    });
    final send = port.sendPort;
    try {
      return await Isolate.run(() => job((done, total) => send.send((done, total))));
    } finally {
      port.close();
    }
  }
}
