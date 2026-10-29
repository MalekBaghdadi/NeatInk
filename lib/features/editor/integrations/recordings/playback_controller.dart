import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../../../../app/diagnostics.dart';
import '../../../../audio/audio_channel.dart';
import '../../../../document/recording.dart';
import '../../../../ink/vec2.dart';
import '../../../../render/text_style.dart';
import '../../../../storage/recording_store.dart';
import '../../canvas/ink_reveal.dart';
import '../../editor_controller.dart';

/// Plays a lecture recording of the open notebook (v1.12.0), plain or "with
/// notes": then the notes written during the lecture show up as the sound
/// reaches the moment they were written (the others stay faint), the pages
/// follow along, and tapping a note plays from there.
class PlaybackController extends ChangeNotifier implements InkReveal {
  PlaybackController({
    required this.editor,
    required this.backend,
    required this.store,
    this.tick = const Duration(milliseconds: 100),
  });

  final EditorController editor;
  final AudioBackend backend;
  final RecordingStore store;

  /// How often the position is read while playing.
  final Duration tick;

  /// Speeds offered, in the order the speed button goes through them.
  static const List<double> speeds = [1, 1.25, 1.5, 2, 0.75];

  /// A tapped note plays from this long before it was written.
  static const int leadInMs = 1500;

  Recording? _recording;
  bool _withNotes = false;
  bool _follow = true;
  int _position = 0;
  int _duration = 0;
  bool _playing = false;
  double _speed = 1;
  String? _error;
  Timer? _timer;
  bool _disposed = false;

  /// The wall-clock moment the sound is at.
  int _wall = 0;

  /// (written at, page id) of every note written during the recording,
  /// by time.
  List<(int, String)> _notes = const [];

  Recording? get recording => _recording;
  bool get isOpen => _recording != null;
  bool get withNotes => _withNotes;
  bool get follow => _follow;
  int get position => _position;
  int get duration => _duration;
  bool get playing => _playing;
  double get speed => _speed;

  /// Why the last recording couldn't be played, once.
  String? takeError() {
    final e = _error;
    _error = null;
    return e;
  }

  /// Opens [recording] and plays it from the start.
  Future<void> open(Recording recording, {required bool withNotes}) async {
    await close();
    final int length;
    try {
      length = await backend.load(store.audioPath(editor.notebookId, recording.file));
    } catch (e) {
      appDiagnostics.record('Recording could not be played: $e');
      _error = "This recording can't be played. Its sound file may be missing.";
      _notify();
      return;
    }
    _recording = recording;
    _duration = length > 0 ? length : recording.durationMs;
    _position = 0;
    _withNotes = withNotes;
    _wall = recording.wallTimeAt(0);
    _indexNotes();
    if (withNotes) {
      editor.extensions.inkReveal = this;
      _repaint(_notes.map((n) => n.$2));
    }
    _timer = Timer.periodic(tick, (_) => unawaited(_onTick()));
    await play();
  }

  void _indexNotes() {
    final rec = _recording;
    if (rec == null || !editor.isReady) return;
    final notes = <(int, String)>[];
    for (final page in editor.doc.meta.pages) {
      final content = editor.doc.pages[page.id];
      if (content == null) continue;
      for (final s in content.strokes) {
        final t = s.writtenAt;
        if (rec.covers(t)) notes.add((t!, page.id));
      }
      for (final item in content.texts) {
        for (final t in item.times) {
          if (rec.covers(t.writtenAt)) notes.add((t.writtenAt, page.id));
        }
      }
    }
    notes.sort((a, b) => a.$1.compareTo(b.$1));
    _notes = notes;
  }

  /// Whether the notebook has notes written during [recording].
  bool hasNotesFor(Recording recording) {
    if (!editor.isReady) return false;
    for (final content in editor.doc.pages.values) {
      if (content.strokes.any((s) => recording.covers(s.writtenAt))) return true;
      if (content.texts.any((t) => t.times.any((x) => recording.covers(x.writtenAt)))) return true;
    }
    return false;
  }

  @override
  bool isAhead(int? writtenAt) {
    final rec = _recording;
    return _withNotes && rec != null && rec.covers(writtenAt) && writtenAt! > _wall;
  }

  Future<void> play() async {
    if (!isOpen) return;
    if (_position >= _duration - 50) await seek(0);
    await backend.play();
    _playing = true;
    _notify();
  }

  Future<void> pause() async {
    if (!isOpen) return;
    await backend.pause();
    _playing = false;
    _notify();
  }

  Future<void> togglePlay() => _playing ? pause() : play();

  Future<void> seek(int ms) async {
    if (!isOpen) return;
    final to = ms.clamp(0, math.max(0, _duration)).toInt();
    await backend.seek(to);
    _position = to;
    _moveTo(_recording!.wallTimeAt(to), jump: true);
    _notify();
  }

  /// Back or ahead by [deltaMs].
  Future<void> skip(int deltaMs) => seek(_position + deltaMs);

  /// The next of [speeds].
  Future<void> nextSpeed() async {
    final i = speeds.indexOf(_speed);
    _speed = speeds[(i + 1) % speeds.length];
    await backend.setSpeed(_speed);
    _notify();
  }

  /// Notes appear as written ([on]) or all show as usual.
  void setWithNotes(bool on) {
    if (!isOpen || on == _withNotes) return;
    _withNotes = on;
    editor.extensions.inkReveal = on ? this : null;
    _repaint(_notes.map((n) => n.$2));
    _notify();
  }

  void setFollow(bool on) {
    _follow = on;
    _notify();
  }

  /// Plays from shortly before the note written at [writtenAt].
  Future<void> seekToNote(int writtenAt) async {
    final at = _recording?.audioPositionOf(writtenAt);
    if (at == null) return;
    await seek(math.max(0, at - leadInMs));
    if (!_playing) await play();
  }

  /// Page tap: a note written during the recording under [point] plays from
  /// its moment (only while playing with notes). True when one was found.
  bool onTap(String pageId, Vec2 point) {
    final rec = _recording;
    if (rec == null || !_withNotes || !editor.isReady) return false;
    final content = editor.doc.pages[pageId];
    if (content == null) return false;
    final reach = 8 / math.max(editor.viewport.scale, 0.25);
    int? found;
    for (final s in content.strokes.reversed) {
      final t = s.writtenAt;
      if (!rec.covers(t) || !s.bounds.inflate(reach).contains(point)) continue;
      if (s.points.any((p) => (p.x - point.x).abs() <= reach && (p.y - point.y).abs() <= reach)) {
        found = t;
        break;
      }
    }
    if (found == null) {
      for (final item in content.texts.reversed) {
        if (item.times.isEmpty || !item.frame.contains(point)) continue;
        final painter = layoutTextItem(item);
        final offset = painter.getPositionForOffset(Offset(point.x - item.x, point.y - item.y)).offset;
        painter.dispose();
        for (final t in item.times) {
          if (t.start <= offset && rec.covers(t.writtenAt)) found = t.writtenAt;
        }
        if (found != null) break;
      }
    }
    if (found == null) return false;
    unawaited(seekToNote(found));
    return true;
  }

  Future<void> _onTick() async {
    final rec = _recording;
    if (rec == null) return;
    final PlayerStatus status;
    try {
      status = await backend.playerStatus();
    } catch (_) {
      return;
    }
    if (_recording != rec) return;
    _position = status.position;
    if (status.duration > 0) _duration = status.duration;
    _playing = status.playing && !status.completed;
    if (status.completed) _position = _duration;
    _moveTo(rec.wallTimeAt(_position), jump: false);
    _notify();
  }

  /// The playback reached wall-clock [wall]: repaint the pages whose notes
  /// appeared or went faint, and (playing on) show the page of the newest
  /// note when it is out of view.
  void _moveTo(int wall, {required bool jump}) {
    final old = _wall;
    _wall = wall;
    if (!_withNotes || old == wall) return;
    final lo = math.min(old, wall), hi = math.max(old, wall);
    final changed = <String>{};
    String? newest;
    for (final (t, pageId) in _notes) {
      if (t <= lo) continue;
      if (t > hi) break;
      changed.add(pageId);
      newest = pageId;
    }
    _repaint(changed);
    if (_follow && newest != null && (wall > old || jump)) _show(newest);
  }

  void _show(String pageId) {
    if (!editor.isReady) return;
    final index = editor.doc.meta.pages.indexWhere((p) => p.id == pageId);
    final viewport = editor.viewport;
    if (index < 0 || !viewport.hasSize || index >= viewport.layout.rects.length) return;
    if (viewport.layout.rects[index].overlaps(viewport.visibleDocRect)) return;
    editor.scrollToPage(index);
  }

  void _repaint(Iterable<String> pageIds) {
    if (!editor.isReady) return;
    for (final id in pageIds.toSet()) {
      editor.invalidatePageRender(id);
    }
  }

  /// Stops playing and closes the recording; all notes show as usual.
  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
    final was = _recording;
    if (was == null) return;
    _recording = null;
    _playing = false;
    if (identical(editor.extensions.inkReveal, this)) editor.extensions.inkReveal = null;
    _repaint(_notes.map((n) => n.$2));
    _notes = const [];
    try {
      await backend.release();
    } catch (_) {}
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_recording != null) unawaited(backend.release().catchError((_) {}));
    if (identical(editor.extensions.inkReveal, this)) editor.extensions.inkReveal = null;
    super.dispose();
  }
}
