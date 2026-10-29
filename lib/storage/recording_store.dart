import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../document/recording.dart';
import 'atomic_file.dart';
import 'notebook_repository.dart';

/// Where a notebook's lecture recordings live (v1.12.0): its `audio/` folder,
/// `recordings.json` (the list, see [recordingsToJson]) and one `.aac` file
/// per recording. Behind an interface so tests keep them in memory.
abstract interface class RecordingStore {
  /// The notebook's recordings, oldest first (empty when it has none or the
  /// list can't be read).
  Future<List<Recording>> list(String notebookId);

  /// Replaces the notebook's list (atomically).
  Future<void> save(String notebookId, List<Recording> recordings);

  /// Absolute path of the audio file [file] of the notebook (may not exist).
  String audioPath(String notebookId, String file);

  /// Deletes the audio file [file]; never throws.
  Future<void> deleteAudio(String notebookId, String file);
}

/// The notebook folders of [repository].
class FileRecordingStore implements RecordingStore {
  FileRecordingStore(this.repository);

  final NotebookRepository repository;
  final Map<String, Future<void>> _queues = {};

  static const String listFile = 'recordings.json';

  String _listPath(String notebookId) => p.join(repository.recordingsFolder(notebookId), listFile);

  /// Runs [task] after the earlier tasks of [notebookId].
  Future<T> _serial<T>(String notebookId, Future<T> Function() task) {
    final run = (_queues[notebookId] ?? Future<void>.value()).then((_) => task());
    _queues[notebookId] = run.then((_) {}, onError: (_) {});
    return run;
  }

  @override
  Future<List<Recording>> list(String notebookId) => _serial(notebookId, () async {
        final file = File(_listPath(notebookId));
        try {
          if (!await file.exists()) return const <Recording>[];
          final json = jsonDecode(await file.readAsString());
          return json is Map<String, dynamic> ? recordingsFromJson(json) : const <Recording>[];
        } catch (e) {
          debugPrint('NeatInk: recordings of $notebookId unreadable: $e');
          return const <Recording>[];
        }
      });

  @override
  Future<void> save(String notebookId, List<Recording> recordings) => _serial(notebookId, () async {
        await Directory(repository.recordingsFolder(notebookId)).create(recursive: true);
        await AtomicFile.writeBytes(_listPath(notebookId), utf8.encode(jsonEncode(recordingsToJson(recordings))));
      });

  @override
  String audioPath(String notebookId, String file) => p.join(repository.recordingsFolder(notebookId), file);

  @override
  Future<void> deleteAudio(String notebookId, String file) async {
    try {
      final f = File(audioPath(notebookId, file));
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('NeatInk: could not delete recording $file: $e');
    }
  }
}

/// Kept in memory (tests).
class InMemoryRecordingStore implements RecordingStore {
  final Map<String, List<Recording>> lists = {};
  final Set<String> deleted = {};

  @override
  Future<List<Recording>> list(String notebookId) async => List.of(lists[notebookId] ?? const []);

  @override
  Future<void> save(String notebookId, List<Recording> recordings) async => lists[notebookId] = List.of(recordings);

  @override
  String audioPath(String notebookId, String file) => '/in-memory-audio/$notebookId/$file';

  @override
  Future<void> deleteAudio(String notebookId, String file) async => deleted.add('$notebookId/$file');
}
