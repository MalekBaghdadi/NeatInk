/// Backups of the whole library: one ZIP file with every notebook folder,
/// `library.json`, and app data handed in by the caller (settings, My
/// words). Restoring only ever adds notebooks; nothing on the device is
/// replaced or deleted.
///
/// Archive layout:
///
/// ```
/// neatink-backup.json                 manifest (format, version, notebooks)
/// app.json                            app data (opaque to this file)
/// library.json                        folder tree (and library.json.bak)
/// notebooks/<id>/...                  the notebook folder, as on disk
/// ```
///
/// The functions here do file work only and take paths, so the caller can
/// run them in a background isolate (see `Isolate.run`).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../../document/notebook_meta.dart';
import '../atomic_file.dart';
import '../file_notebook_repository.dart' show parseNotebookMeta;
import '../json_document_store.dart';
import '../library_json.dart';
import '../storage_ids.dart';
import 'zip_archive.dart';

const String backupManifestName = 'neatink-backup.json';
const String backupAppDataName = 'app.json';
const String backupFormatName = 'neatink-backup';
const int backupFormatVersion = 1;

/// Prefix of the folders a restore stages notebooks in, next to
/// `notebooks/` (never listed as notebooks).
const String _stagingPrefix = '.restore-';

/// Reports progress: [done] of [total] steps (notebooks).
typedef BackupProgress = void Function(int done, int total);

/// A backup cannot be written or read; [message] is for the user.
class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => 'BackupException: $message';
}

/// What [writeBackup] wrote.
class BackupWriteResult {
  const BackupWriteResult({required this.notebooks, required this.bytes});

  final int notebooks;

  /// Size of the backup file.
  final int bytes;
}

/// Writes a backup of the storage folder [rootPath] (the one holding
/// `library.json` and `notebooks/`) to [outputPath], with [appData] as
/// `app.json`. Temp files of interrupted writes and deleted notebooks are
/// left out. The output is deleted again if anything fails.
Future<BackupWriteResult> writeBackup({
  required String rootPath,
  required String outputPath,
  required Map<String, Object?> appData,
  required String appVersion,
  DateTime? now,
  BackupProgress? onProgress,
}) async {
  final createdAt = now ?? DateTime.now();
  final ids = await _notebookIds(rootPath);
  final out = File(outputPath);
  final zip = await ZipWriter.create(out, modified: createdAt);
  try {
    final notebooks = <Map<String, Object?>>[];
    onProgress?.call(0, ids.length);
    for (final (i, id) in ids.indexed) {
      final dir = Directory(p.join(rootPath, 'notebooks', id));
      NotebookMeta? meta;
      try {
        meta = readJsonDocumentSync(
                p.join(dir.path, 'notebook.json'), parseNotebookMeta)
            ?.value;
      } catch (_) {
        // Unreadable: its files are still saved, exactly as they are.
      }
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File || AtomicFile.isTempName(entity.path)) continue;
        final rel = p.posix.joinAll(p.split(p.relative(entity.path, from: dir.path)));
        final name = 'notebooks/$id/$rel';
        if (!isSafeZipPath(name)) continue;
        await zip.addFile(name, entity, compress: _isText(rel));
      }
      notebooks.add({
        'id': id,
        'title': meta?.title,
        'updatedAt': meta?.updatedAt.toUtc().toIso8601String(),
        'pages': meta?.pages.length,
      });
      onProgress?.call(i + 1, ids.length);
    }
    for (final name in const ['library.json', 'library.json.bak']) {
      final f = File(p.join(rootPath, name));
      if (await f.exists()) await zip.addFile(name, f, compress: true);
    }
    await zip.addBytes(backupAppDataName, utf8.encode(jsonEncode(appData)));
    await zip.addBytes(
        backupManifestName,
        utf8.encode(const JsonEncoder.withIndent('  ').convert({
          'format': backupFormatName,
          'version': backupFormatVersion,
          'app': appVersion,
          'createdAt': createdAt.toUtc().toIso8601String(),
          'notebooks': notebooks,
        })));
    await zip.close();
  } catch (e) {
    await zip.abort();
    if (e is ZipException) throw BackupException(e.message);
    rethrow;
  }
  return BackupWriteResult(notebooks: ids.length, bytes: await out.length());
}

/// JSON documents and their `.bak` / `.corrupt` copies compress well; PDFs
/// and pictures are compressed already and are stored as they are.
bool _isText(String relativePath) => p.basename(relativePath).contains('.json');

/// Notebook folders under [rootPath], sorted (deleted and staged folders
/// have names that are not valid ids, so they are skipped).
Future<List<String>> _notebookIds(String rootPath) async {
  final dir = Directory(p.join(rootPath, 'notebooks'));
  if (!await dir.exists()) return const [];
  return [
    await for (final e in dir.list(followLinks: false))
      if (e is Directory && isValidStorageId(p.basename(e.path)))
        p.basename(e.path),
  ]..sort();
}

/// One notebook found in a backup.
class BackupNotebook {
  const BackupNotebook(this.meta);

  final NotebookMeta meta;

  String get id => meta.id;
  String get title => meta.title;
}

/// What a backup file holds, read by [readBackupInfo].
class BackupInfo {
  const BackupInfo({
    required this.createdAt,
    required this.appVersion,
    required this.notebooks,
    required this.unreadable,
    required this.library,
    required this.appData,
  });

  final DateTime? createdAt;
  final String appVersion;

  /// Notebooks whose `notebook.json` could be read, by title.
  final List<BackupNotebook> notebooks;

  /// Number of notebook folders whose `notebook.json` could not be read
  /// (they cannot be restored).
  final int unreadable;

  final LibraryIndex library;
  final Map<String, Object?> appData;
}

/// Reads the manifest, folders, app data and every notebook's metadata
/// from the backup at [zipPath]. Throws [BackupException] when it is not a
/// backup this version can read.
Future<BackupInfo> readBackupInfo(String zipPath) async {
  final zip = await _openBackup(zipPath);
  try {
    final manifest = await _jsonEntry(zip, backupManifestName);
    if (manifest == null || manifest['format'] != backupFormatName) {
      throw const BackupException('This file is not a notebook backup.');
    }
    final version = manifest['version'];
    if (version is! int || version > backupFormatVersion) {
      throw const BackupException(
          'This backup was made by a newer version of the app. Update the app '
          'first.');
    }
    final folders = <String>{
      for (final e in zip.entries)
        if (e.name.split('/') case ['notebooks', final id, _, ...]
            when isValidStorageId(id))
          id,
    };
    final notebooks = <BackupNotebook>[];
    for (final id in folders) {
      final meta = await _metaOf(zip, id);
      if (meta != null) notebooks.add(BackupNotebook(meta));
    }
    notebooks.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    LibraryIndex library = const LibraryIndex();
    for (final name in const ['library.json', 'library.json.bak']) {
      try {
        final json = await _jsonEntry(zip, name);
        if (json != null) {
          library = libraryFromJson(json);
          break;
        }
      } catch (_) {
        // Try the backup copy; without either, no folders come back.
      }
    }
    Map<String, Object?> appData = const {};
    try {
      appData = await _jsonEntry(zip, backupAppDataName) ?? const {};
    } catch (_) {
      // The notebooks matter most; settings are optional.
    }
    return BackupInfo(
      createdAt: DateTime.tryParse('${manifest['createdAt']}'),
      appVersion: '${manifest['app'] ?? ''}',
      notebooks: notebooks,
      unreadable: folders.length - notebooks.length,
      library: library,
      appData: appData,
    );
  } finally {
    await zip.close();
  }
}

/// The notebook's metadata from the backup: `notebook.json`, or its
/// `.bak` when the main copy cannot be parsed. Null when neither can.
Future<NotebookMeta?> _metaOf(ZipReader zip, String id) async {
  for (final name in ['notebooks/$id/notebook.json', 'notebooks/$id/notebook.json.bak']) {
    try {
      final json = await _jsonEntry(zip, name);
      if (json == null) continue;
      final meta = parseNotebookMeta(json);
      // As on disk, the folder name is the id.
      return meta.id == id ? meta : meta.copyWith(id: id);
    } catch (_) {
      continue;
    }
  }
  return null;
}

Future<ZipReader> _openBackup(String zipPath) async {
  try {
    return await ZipReader.open(File(zipPath));
  } on ZipException {
    throw const BackupException('This file is not a notebook backup.');
  } on FileSystemException {
    throw const BackupException('The backup file could not be opened.');
  }
}

Future<Map<String, dynamic>?> _jsonEntry(ZipReader zip, String name) async {
  final e = zip.entry(name);
  if (e == null) return null;
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(await zip.readBytes(e)));
  } on ZipException catch (err) {
    throw BackupException('The backup file is damaged (${err.message}).');
  }
  return json is Map<String, dynamic> ? json : null;
}

/// Why a notebook gets the [RestoreItem.action] it has.
enum RestoreReason {
  /// Not on this device.
  missing,

  /// On this device with the same last-edited time and page count.
  unchanged,

  /// On this device, but edited since the backup (or before it).
  changed,
}

enum RestoreAction {
  /// Restore under its own id.
  add,

  /// Restore as a separate notebook with a new id and title.
  copy,

  skip,
}

class RestoreItem {
  const RestoreItem({
    required this.notebook,
    required this.reason,
    required this.action,
    required this.targetId,
    required this.title,
  });

  final BackupNotebook notebook;
  final RestoreReason reason;
  final RestoreAction action;

  /// Id the notebook gets on this device.
  final String targetId;

  /// Title it gets on this device.
  final String title;
}

/// Decides what restoring [info] does on a device holding [local]: missing
/// notebooks are added, unchanged ones skipped, and changed ones added as
/// copies titled "… (from backup)" when [copyChanged] (skipped otherwise).
/// A notebook on the device is never replaced.
List<RestoreItem> planRestore(
  BackupInfo info,
  Iterable<NotebookMeta> local, {
  required bool copyChanged,
  required String Function() newId,
}) {
  final here = {for (final m in local) m.id: m};
  return [
    for (final n in info.notebooks)
      _planOne(n, here[n.id], copyChanged: copyChanged, newId: newId),
  ];
}

RestoreItem _planOne(BackupNotebook n, NotebookMeta? mine,
    {required bool copyChanged, required String Function() newId}) {
  RestoreItem item(RestoreReason reason, RestoreAction action,
          [String? targetId, String? title]) =>
      RestoreItem(
          notebook: n,
          reason: reason,
          action: action,
          targetId: targetId ?? n.id,
          title: title ?? n.title);
  if (mine == null) return item(RestoreReason.missing, RestoreAction.add);
  if (mine.updatedAt.isAtSameMomentAs(n.meta.updatedAt) &&
      mine.pages.length == n.meta.pages.length) {
    return item(RestoreReason.unchanged, RestoreAction.skip);
  }
  if (!copyChanged) return item(RestoreReason.changed, RestoreAction.skip);
  return item(RestoreReason.changed, RestoreAction.copy, newId(),
      '${n.title} (from backup)');
}

/// What [restoreNotebooks] did.
class RestoreResult {
  const RestoreResult({required this.restored, required this.failed});

  /// Ids (on this device) of the notebooks restored.
  final List<String> restored;

  /// Titles of the notebooks that could not be restored.
  final List<String> failed;
}

/// Restores the notebooks of [items] whose action is add or copy from the
/// backup at [zipPath] into [rootPath]. Each notebook is unpacked into a
/// staging folder first and moved into `notebooks/` in one rename, so it
/// appears whole or not at all. A notebook whose target folder exists is
/// never overwritten (it fails instead). Folders and app data are left to
/// the caller.
Future<RestoreResult> restoreNotebooks({
  required String zipPath,
  required String rootPath,
  required List<RestoreItem> items,
  BackupProgress? onProgress,
}) async {
  final todo = [for (final i in items) if (i.action != RestoreAction.skip) i];
  await _removeStaleStaging(rootPath);
  final staging = Directory(p.join(rootPath,
      '$_stagingPrefix${Random().nextInt(1 << 32).toRadixString(16)}'));
  final notebooksDir = Directory(p.join(rootPath, 'notebooks'));
  await notebooksDir.create(recursive: true);
  final zip = await _openBackup(zipPath);
  final restored = <String>[];
  final failed = <String>[];
  try {
    onProgress?.call(0, todo.length);
    for (final (i, item) in todo.indexed) {
      final target = Directory(p.join(notebooksDir.path, checkStorageId(item.targetId)));
      final staged = Directory(p.join(staging.path, item.targetId));
      try {
        if (await target.exists()) {
          throw const BackupException('A notebook with this id already exists.');
        }
        await _unpackNotebook(zip, item.notebook.id, staged);
        if (item.action == RestoreAction.copy) {
          await _renameStaged(staged, item.targetId, item.title);
        }
        await staged.rename(target.path);
        restored.add(item.targetId);
      } catch (e) {
        failed.add(item.notebook.title);
        try {
          if (await staged.exists()) await staged.delete(recursive: true);
        } catch (_) {}
      }
      onProgress?.call(i + 1, todo.length);
    }
  } finally {
    await zip.close();
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
    } catch (_) {}
  }
  return RestoreResult(restored: restored, failed: failed);
}

/// Extracts `notebooks/<id>/**` into [dir].
Future<void> _unpackNotebook(ZipReader zip, String id, Directory dir) async {
  final prefix = 'notebooks/$id/';
  var any = false;
  for (final e in zip.entries) {
    if (!e.name.startsWith(prefix) || e.isDirectory) continue;
    final rel = e.name.substring(prefix.length);
    if (!isSafeZipPath(rel) || AtomicFile.isTempName(rel)) continue;
    try {
      await zip.extractTo(e, File(p.joinAll([dir.path, ...rel.split('/')])));
    } on ZipException catch (err) {
      throw BackupException(err.message);
    }
    any = true;
  }
  if (!any) throw const BackupException('The notebook is missing from the backup.');
}

/// Gives a staged notebook a new id and title (its `notebook.json` is
/// rewritten; the `.bak` copy, which still has the old title, is dropped).
Future<void> _renameStaged(Directory staged, String id, String title) async {
  final path = p.join(staged.path, 'notebook.json');
  final meta = readJsonDocumentSync(path, parseNotebookMeta)?.value;
  if (meta == null) throw const BackupException('The notebook has no metadata.');
  final renamed = meta.copyWith(id: id, title: title);
  await AtomicFile.writeBytes(path, encodeJsonBytes(renamed.toJson(), pretty: true));
  final bak = File(backupPathFor(path));
  if (await bak.exists()) await bak.delete();
}

/// Removes staging folders left by a restore that was interrupted.
Future<void> _removeStaleStaging(String rootPath) async {
  final root = Directory(rootPath);
  if (!await root.exists()) return;
  await for (final e in root.list(followLinks: false)) {
    if (e is Directory && p.basename(e.path).startsWith(_stagingPrefix)) {
      try {
        await e.delete(recursive: true);
      } catch (_) {}
    }
  }
}

/// [local] plus the folders of [backup] that the [restored] notebooks are
/// in (with their parents), for folders this device does not have. Null
/// when nothing needs adding.
LibraryIndex? mergeRestoredFolders(
    LibraryIndex local, LibraryIndex backup, Iterable<NotebookMeta> restored) {
  final have = {for (final f in local.folders) f.id};
  final add = <Folder>[];
  final added = <String>{};
  void need(String? folderId) {
    while (folderId != null && !have.contains(folderId) && !added.contains(folderId)) {
      final f = backup.folderById(folderId);
      if (f == null) return;
      add.add(f);
      added.add(f.id);
      folderId = f.parentId;
    }
  }

  for (final m in restored) {
    need(m.folderId);
  }
  if (add.isEmpty) return null;
  return local.copyWith(folders: [...local.folders, ...add.reversed]);
}
