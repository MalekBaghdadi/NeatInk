import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/diagnostics.dart';
import '../../app/providers.dart';
import '../../audio/audio_channel.dart';
import '../../document/recording.dart';
import '../../storage/recording_store.dart';

/// Why a recording did not start.
enum RecordingStartResult { started, noPermission, busy, failed }

/// The app's lecture recorder (v1.12.0). One recording at a time, for one
/// notebook; it goes on when the user leaves that notebook (the library shows
/// it) and when the app is in the background (Android side: a foreground
/// service). The recording's timeline (its [RecordingSpan]s) is saved when it
/// starts, pauses, resumes and stops, and every [persistEvery] in between,
/// so a recording cut short by the app being closed keeps all but the last
/// few seconds of its timeline (see [finishInterrupted]).
class RecordingController extends ChangeNotifier {
  RecordingController({
    required this.backend,
    required this.store,
    DateTime Function()? clock,
    Uuid? uuid,
    this.tick = const Duration(milliseconds: 250),
    this.persistEvery = const Duration(seconds: 10),
  })  : _clock = clock ?? DateTime.now,
        _uuid = uuid ?? const Uuid();

  final AudioBackend backend;
  final RecordingStore store;
  final DateTime Function() _clock;
  final Uuid _uuid;

  /// How often the level meter and the clock update.
  final Duration tick;
  final Duration persistEvery;

  RecorderState _state = RecorderState.idle;
  String? _notebookId;
  String? _notebookTitle;
  Recording? _current;
  double _level = 0;
  Timer? _timer;
  DateTime _lastPersist = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  RecorderState get state => _state;
  bool get isActive => _state != RecorderState.idle;

  /// The notebook being recorded for, while [isActive].
  String? get notebookId => _notebookId;
  String? get notebookTitle => _notebookTitle;

  /// The recording being made, while [isActive].
  Recording? get current => _current;

  /// How loud the microphone is (0..1), for the level meter.
  double get level => _level;

  /// Sound recorded so far, in ms.
  int get elapsedMs => _current?.durationMs ?? 0;

  int _now() => _clock().millisecondsSinceEpoch;

  /// Starts recording for [notebookId] (asks for the microphone the first
  /// time). The new recording is called [title].
  Future<RecordingStartResult> start(String notebookId, {required String title, String? notebookTitle}) async {
    if (isActive) return RecordingStartResult.busy;
    if (!await backend.microphonePermission(ask: true)) return RecordingStartResult.noPermission;
    final id = _uuid.v4();
    final file = '$id.aac';
    final now = _now();
    var recording = Recording(
      id: id,
      title: title,
      file: file,
      createdAt: now,
      spans: [RecordingSpan(wallStart: now, wallEnd: now, audioStart: 0)],
      inProgress: true,
    );
    final list = await store.list(notebookId);
    await store.save(notebookId, [...list, recording]);
    try {
      await backend.startRecording(store.audioPath(notebookId, file));
    } catch (e) {
      appDiagnostics.record('Recording could not start: $e');
      await store.save(notebookId, list);
      return RecordingStartResult.failed;
    }
    // The sound starts once the recorder runs: the timeline starts there too.
    final started = _now();
    recording = recording.copyWith(spans: [RecordingSpan(wallStart: started, wallEnd: started, audioStart: 0)]);
    _current = recording;
    _notebookId = notebookId;
    _notebookTitle = notebookTitle;
    _state = RecorderState.recording;
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) => unawaited(_onTick()));
    await _persist();
    _notify();
    return RecordingStartResult.started;
  }

  Future<void> pause() async {
    final rec = _current;
    if (_state != RecorderState.recording || rec == null) return;
    await backend.pauseRecording();
    _current = _closed(rec);
    _state = RecorderState.paused;
    _level = 0;
    await _persist();
    _notify();
  }

  Future<void> resume() async {
    final rec = _current;
    if (_state != RecorderState.paused || rec == null) return;
    await backend.resumeRecording();
    final now = _now();
    _current = rec.copyWith(spans: [...rec.spans, RecordingSpan(wallStart: now, wallEnd: now, audioStart: rec.durationMs)]);
    _state = RecorderState.recording;
    await _persist();
    _notify();
  }

  /// Stops and saves the recording; returns it (null when nothing was being
  /// recorded).
  Future<Recording?> stop() async {
    final rec = _current;
    final notebookId = _notebookId;
    if (!isActive || rec == null || notebookId == null) return null;
    _timer?.cancel();
    _timer = null;
    try {
      await backend.stopRecording();
    } catch (e) {
      appDiagnostics.record('Recording did not stop cleanly: $e');
    }
    final done = (_state == RecorderState.recording ? _closed(rec) : rec).copyWith(inProgress: false);
    _current = done;
    await _persist();
    _state = RecorderState.idle;
    _current = null;
    _notebookId = null;
    _notebookTitle = null;
    _level = 0;
    _notify();
    return done;
  }

  /// [rec] with its last span ending now.
  Recording _closed(Recording rec) {
    if (rec.spans.isEmpty) return rec;
    final now = _now();
    final last = rec.spans.last;
    return rec.copyWith(spans: [...rec.spans.take(rec.spans.length - 1), last.endingAt(now < last.wallStart ? last.wallStart : now)]);
  }

  Future<void> _onTick() async {
    final rec = _current;
    if (rec == null || _state == RecorderState.idle) return;
    if (_state == RecorderState.recording) _current = _closed(rec);
    try {
      final status = await backend.recorderStatus();
      _level = status.level;
      if (status.state == RecorderState.idle && isActive) {
        // The recorder stopped without us (the system ended it): keep what
        // was recorded.
        appDiagnostics.record('Recording ended by the system');
        await stop();
        return;
      }
    } catch (_) {
      _level = 0;
    }
    if (_clock().difference(_lastPersist) >= persistEvery) await _persist();
    _notify();
  }

  Future<void> _persist() async {
    final rec = _current;
    final notebookId = _notebookId;
    if (rec == null || notebookId == null) return;
    _lastPersist = _clock();
    try {
      final list = await store.list(notebookId);
      final i = list.indexWhere((r) => r.id == rec.id);
      await store.save(notebookId, [
        if (i < 0) ...list else ...[...list.take(i), rec, ...list.skip(i + 1)],
        if (i < 0) rec,
      ]);
    } catch (e) {
      appDiagnostics.record('Saving the recording timeline failed: $e');
    }
  }

  /// The recordings of [notebookId], with any left "in progress" by an app
  /// that was closed while recording marked finished (their sound is kept
  /// up to the last saved moment). The one being recorded now stays.
  Future<List<Recording>> recordingsOf(String notebookId) async {
    final list = await store.list(notebookId);
    final activeId = _notebookId == notebookId ? _current?.id : null;
    if (!list.any((r) => r.inProgress && r.id != activeId)) return list;
    final fixed = [
      for (final r in list) r.inProgress && r.id != activeId ? r.copyWith(inProgress: false) : r,
    ];
    await store.save(notebookId, fixed);
    return fixed;
  }

  /// Renames recording [id] of [notebookId].
  Future<void> rename(String notebookId, String id, String title) async {
    final list = await store.list(notebookId);
    await store.save(notebookId, [for (final r in list) r.id == id ? r.copyWith(title: title) : r]);
    if (_current?.id == id) _current = _current!.copyWith(title: title);
    _notify();
  }

  /// Deletes recording [id] of [notebookId] and its sound (not the one being
  /// recorded).
  Future<void> delete(String notebookId, String id) async {
    if (_current?.id == id) return;
    final list = await store.list(notebookId);
    final gone = list.where((r) => r.id == id).toList();
    await store.save(notebookId, [for (final r in list) if (r.id != id) r]);
    for (final r in gone) {
      await store.deleteAudio(notebookId, r.file);
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// The notebook files' recordings. Tests override it.
final recordingStoreProvider =
    Provider<RecordingStore>((ref) => FileRecordingStore(ref.watch(notebookRepositoryProvider)));

/// The app's one recorder.
final recordingControllerProvider = Provider<RecordingController>((ref) {
  final c = RecordingController(
    backend: ref.watch(audioBackendProvider),
    store: ref.watch(recordingStoreProvider),
    clock: ref.watch(clockProvider),
  );
  ref.onDispose(c.dispose);
  return c;
});

/// The default name of a recording started at [t]: "Lecture, 30 Oct, 10:15".
String defaultRecordingTitle(DateTime t) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Lecture, ${t.day} ${months[t.month - 1]}, ${two(t.hour)}:${two(t.minute)}';
}
