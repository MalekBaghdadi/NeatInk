import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/audio/audio_channel.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/document/recording.dart';
import 'package:neatink/features/recording/recording_controller.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/storage/recording_store.dart';

import '../fakes/fake_audio.dart';

void main() {
  // Recorded 10:00:00-10:01:00, paused, then 10:02:00-10:03:00.
  const t0 = 1700000000000;
  const rec = Recording(id: 'r', title: 'Lecture', file: 'r.aac', createdAt: t0, spans: [
    RecordingSpan(wallStart: t0, wallEnd: t0 + 60000, audioStart: 0),
    RecordingSpan(wallStart: t0 + 120000, wallEnd: t0 + 180000, audioStart: 60000),
  ]);

  group('the timeline', () {
    test('a note written while recording plays where it was written', () {
      expect(rec.durationMs, 120000);
      expect(rec.audioPositionOf(t0 + 30000), 30000);
      expect(rec.audioPositionOf(t0 + 150000), 90000);
    });

    test('a note written during the pause belongs where the sound went on', () {
      expect(rec.audioPositionOf(t0 + 90000), 60000);
    });

    test('notes from before or after the recording are not part of it', () {
      expect(rec.audioPositionOf(t0 - 1), isNull);
      expect(rec.audioPositionOf(t0 + 180001), isNull);
      expect(rec.audioPositionOf(null), isNull);
      expect(rec.covers(t0 + 90000), isTrue);
    });

    test('the sound at a moment says how far the notes have come', () {
      expect(rec.wallTimeAt(0), t0);
      expect(rec.wallTimeAt(30000), t0 + 30000);
      expect(rec.wallTimeAt(60000), t0 + 120000, reason: 'after the pause');
      expect(rec.wallTimeAt(500000), t0 + 180000);
    });

    test('round trip through JSON', () {
      final back = recordingsFromJson(recordingsToJson([rec, rec.copyWith(inProgress: true)]));
      expect(back.first.spans, rec.spans);
      expect(back.last.inProgress, isTrue);
      expect(formatDuration(3723000), '1:02:03');
      expect(formatDuration(65000), '1:05');
    });

    test('strokes and typed lines keep when they were written', () {
      final s = Stroke(id: 's', tool: StrokeTool.pen, color: 0xFF000000, size: 2, raw: const [InkPoint(1, 2, 0.5, 0)], writtenAt: t0);
      expect(Stroke.fromJson(s.toJson()).writtenAt, t0);
      expect(s.copyWith(color: 0xFF111111).writtenAt, t0);
      const box = TextItem(id: 't', x: 0, y: 0, width: 100, height: 20, text: 'neurons fire. synapses pass it on',
          times: [TextTime(0, t0), TextTime(14, t0 + 9000)]);
      expect(TextItem.fromJson(box.toJson()).times, box.times);
      // An edit before the second line moves its mark with it.
      final edited = box.copyWith(text: 'Neurons fire fast. synapses pass it on');
      expect(edited.times, const [TextTime(0, t0), TextTime(19, t0 + 9000)]);
    });
  });

  group('the recorder', () {
    late FakeAudioBackend audio;
    late InMemoryRecordingStore store;
    late DateTime now;
    late RecordingController c;

    setUp(() {
      audio = FakeAudioBackend();
      store = InMemoryRecordingStore();
      now = DateTime.fromMillisecondsSinceEpoch(t0);
      c = RecordingController(backend: audio, store: store, clock: () => now);
    });
    tearDown(() => c.dispose());

    test('start, pause, resume, stop: one recording with two stretches', () async {
      expect(await c.start('nb', title: 'Lecture'), RecordingStartResult.started);
      expect(audio.asked, isTrue);
      expect(c.state, RecorderState.recording);
      expect(store.lists['nb']!.single.inProgress, isTrue, reason: 'saved from the start');
      now = now.add(const Duration(seconds: 30));
      await c.pause();
      now = now.add(const Duration(seconds: 20));
      await c.resume();
      now = now.add(const Duration(seconds: 10));
      final done = await c.stop();
      expect(c.state, RecorderState.idle);
      expect(done!.durationMs, 40000);
      expect(done.spans, hasLength(2));
      expect(done.audioPositionOf(t0 + 40000), 30000, reason: 'written during the pause');
      final saved = store.lists['nb']!.single;
      expect(saved.inProgress, isFalse);
      expect(saved.durationMs, 40000);
      expect(audio.calls.first, startsWith('start /in-memory-audio/nb/'));
    });

    test('without the microphone nothing starts', () async {
      audio.permission = false;
      expect(await c.start('nb', title: 'x'), RecordingStartResult.noPermission);
      expect(store.lists['nb'], isNull);
    });

    test('a recorder that fails leaves no recording behind', () async {
      audio.startError = Exception('busy');
      expect(await c.start('nb', title: 'x'), RecordingStartResult.failed);
      expect(store.lists['nb'], isEmpty);
      expect(c.isActive, isFalse);
    });

    test('a recording cut short by the app closing is kept, finished', () async {
      store.lists['nb'] = [rec.copyWith(inProgress: true)];
      final list = await c.recordingsOf('nb');
      expect(list.single.inProgress, isFalse);
      expect(list.single.durationMs, 120000);
    });

    test('rename and delete', () async {
      store.lists['nb'] = [rec];
      await c.rename('nb', 'r', 'Synapses');
      expect(store.lists['nb']!.single.title, 'Synapses');
      await c.delete('nb', 'r');
      expect(store.lists['nb'], isEmpty);
      expect(store.deleted, {'nb/r.aac'});
    });

    test('a default name says when', () {
      expect(defaultRecordingTitle(DateTime(2026, 10, 30, 9, 5)), 'Lecture, 30 Oct, 09:05');
    });
  });
}
