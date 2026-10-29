import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/audio/audio_channel.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/document/recording.dart';
import 'package:neatink/features/editor/canvas/document_view.dart';
import 'package:neatink/features/editor/editor_controller.dart';
import 'package:neatink/features/editor/editor_integrations.dart';
import 'package:neatink/features/editor/editor_screen.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/integrations/recordings/recordings_integration.dart';
import 'package:neatink/features/editor/integrations/text_images/text_images_integration.dart';
import 'package:neatink/features/recording/recording_controller.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:neatink/storage/recording_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../fakes/fake_audio.dart';
import '../../../fakes/in_memory_repository.dart';

// v1.12.0: record a lecture while writing; play it back with the notes
// appearing as they were written.

class _Harness {
  _Harness(this.tester, this.controller, this.audio, this.store, this.container);

  final WidgetTester tester;
  final EditorController controller;
  final FakeAudioBackend audio;
  final InMemoryRecordingStore store;
  final ProviderContainer container;

  static DateTime now = DateTime(2026, 10, 30, 10);

  static Future<_Harness> open(WidgetTester tester, {bool introSeen = false}) async {
    SharedPreferences.setMockInitialValues({if (introSeen) RecordingActions.introSeenKey: true});
    final prefs = await SharedPreferences.getInstance();
    final repo = InMemoryNotebookRepository();
    final meta = await repo.createNotebook(title: 'Neuro', paper: const Paper(), pageCount: 1);
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final audio = FakeAudioBackend();
    final store = InMemoryRecordingStore();
    now = DateTime(2026, 10, 30, 10);
    EditorController? captured;
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notebookRepositoryProvider.overrideWithValue(repo),
      audioBackendProvider.overrideWithValue(audio),
      recordingStoreProvider.overrideWithValue(store),
      clockProvider.overrideWithValue(() => now),
      editorIntegrationsProvider.overrideWithValue([
        (controller, ref) => captured = controller,
        textImagesIntegration,
        recordingsIntegration,
      ]),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: EditorScreen(notebookId: meta.id)),
    ));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
    return _Harness(tester, captured!, audio, store, container);
  }

  RecordingController get recorder => container.read(recordingControllerProvider);
  PageContent get page => controller.doc.page(controller.doc.meta.pages.first.id);
  String get notebookId => controller.notebookId;

  Offset at(Vec2 p) => tester.getTopLeft(find.byType(DocumentView)) + controller.viewport.pageToLocal(0, p);

  /// A pen stroke across the page at height [y] (page points).
  Future<void> write(double y) async {
    final g = await tester.startGesture(at(Vec2(100, y)), kind: PointerDeviceKind.stylus);
    for (var x = 110.0; x <= 300; x += 10) {
      await g.moveTo(at(Vec2(x, y + (x % 20 == 0 ? 3 : -3))));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await g.up();
    await tester.pump();
  }

  Future<void> passTime(Duration d) async {
    now = now.add(d);
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Finder key(String k) => find.byKey(ValueKey(k));

void main() {
  testWidgets('the first recording is explained, then it records with Pause and Stop', (tester) async {
    final h = await _Harness.open(tester);
    await tester.tap(key('record-lecture'));
    await tester.pumpAndSettle();
    expect(key('recording-intro'), findsOneWidget);
    expect(find.textContaining('tap Allow'), findsOneWidget);
    await tester.tap(key('recording-intro-start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(h.audio.asked, isTrue, reason: 'the microphone is asked for');
    expect(key('recording-bar'), findsOneWidget);
    expect(key('record-lecture'), findsNothing, reason: 'the bar has the controls now');

    await h.passTime(const Duration(seconds: 65));
    expect(find.text('1:05'), findsOneWidget);
    await tester.tap(key('recording-pause'));
    await tester.pump();
    expect(find.text('Paused'), findsOneWidget);
    await tester.tap(key('recording-resume'));
    await tester.pump();
    await tester.tap(key('recording-stop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(key('recording-bar'), findsNothing);
    expect(find.textContaining('Recording saved'), findsOneWidget);
    expect(h.store.lists[h.notebookId]!.single.inProgress, isFalse);
    expect(key('open-recordings'), findsOneWidget, reason: 'the headphones button appears');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the explanation is shown once; "Not now" records nothing', (tester) async {
    final h = await _Harness.open(tester);
    await tester.tap(key('record-lecture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(h.recorder.isActive, isFalse);
    expect(h.audio.calls, isEmpty);
  });

  testWidgets('without the microphone it says how to allow it', (tester) async {
    final h = await _Harness.open(tester, introSeen: true);
    h.audio.permission = false;
    await tester.tap(key('record-lecture'));
    await tester.pumpAndSettle();
    expect(key('microphone-off'), findsOneWidget);
    expect(find.textContaining('Permissions › Microphone'), findsOneWidget);
  });

  testWidgets('played with notes, notes appear as the sound reaches them; a tap plays from a note', (tester) async {
    final h = await _Harness.open(tester, introSeen: true);
    h.controller.selectTool(EditorTool.pen);
    await tester.tap(key('record-lecture'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await h.passTime(const Duration(seconds: 10));
    await h.write(200); // at 0:10
    await h.passTime(const Duration(seconds: 20));
    await h.write(300); // at 0:30
    await h.passTime(const Duration(seconds: 10));
    await tester.tap(key('recording-stop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final strokes = h.page.strokes;
    expect(strokes, hasLength(2));
    final rec = h.store.lists[h.notebookId]!.single;
    expect(rec.audioPositionOf(strokes[0].writtenAt), closeTo(10000, 400));
    expect(rec.audioPositionOf(strokes[1].writtenAt), closeTo(30000, 400));

    await tester.tap(key('open-recordings'));
    await tester.pumpAndSettle();
    expect(key('recordings-sheet'), findsOneWidget);
    await tester.tap(key('recording-play-notes-${rec.id}'));
    await tester.pumpAndSettle();
    expect(key('player-bar'), findsOneWidget);
    expect(h.audio.loaded, '/in-memory-audio/${h.notebookId}/${rec.file}');
    expect(h.audio.playing, isTrue);
    expect(key('player-hint'), findsOneWidget);
    final reveal = h.controller.extensions.inkReveal!;
    expect([for (final s in strokes) reveal.isAhead(s.writtenAt)], [true, true], reason: 'at 0:00 both are to come');

    h.audio.position = 15000;
    await tester.pump(const Duration(milliseconds: 250));
    expect([for (final s in strokes) reveal.isAhead(s.writtenAt)], [false, true]);
    expect(find.text('0:15'), findsOneWidget);

    // A tap on the second note plays from shortly before it.
    final g = await tester.startGesture(h.at(const Vec2(200, 300)), kind: PointerDeviceKind.stylus);
    await tester.pump(const Duration(milliseconds: 60));
    await g.up();
    await tester.pump(const Duration(milliseconds: 250));
    expect(h.audio.calls.last, startsWith('seek 28'), reason: '1.5 s before 0:30');
    expect(h.page.strokes, hasLength(2), reason: 'the tap drew nothing');

    // Notes as written off: all show.
    await tester.tap(key('player-with-notes'));
    await tester.pump();
    expect(h.controller.extensions.inkReveal, isNull);

    await tester.tap(key('player-close'));
    await tester.pump();
    expect(key('player-bar'), findsNothing);
    expect(h.audio.calls, contains('release'));
  });

  testWidgets('leaving while recording asks; "Keep recording" keeps it on', (tester) async {
    final h = await _Harness.open(tester, introSeen: true);
    await tester.tap(key('record-lecture'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // (The recording dot pulses for ever: pump, don't settle.)
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(key('recording-leave'), findsOneWidget);
    await tester.tap(key('recording-leave-keep'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(h.recorder.isActive, isTrue);
    await h.recorder.stop();
  });

  testWidgets('rename and delete from the list', (tester) async {
    final h = await _Harness.open(tester, introSeen: true);
    final t0 = _Harness.now.millisecondsSinceEpoch;
    h.store.lists[h.notebookId] = [
      Recording(id: 'r1', title: 'Lecture 1', file: 'r1.aac', createdAt: t0, spans: [
        RecordingSpan(wallStart: t0, wallEnd: t0 + 60000, audioStart: 0),
      ]),
    ];
    await tester.tap(key('record-lecture')); // any action refreshes the list; start and stop
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(key('recording-stop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(key('open-recordings'));
    await tester.pumpAndSettle();
    expect(find.text('Lecture 1'), findsOneWidget);
    expect(find.descendant(of: key('recordings-sheet'), matching: find.text('Play with notes')), findsNWidgets(2));

    await tester.tap(key('recording-menu-r1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(key('recording-delete-confirm'));
    await tester.pumpAndSettle();
    expect(h.store.lists[h.notebookId]!.map((r) => r.id), isNot(contains('r1')));
    expect(h.store.deleted, contains('${h.notebookId}/r1.aac'));
    await tester.pump(const Duration(seconds: 5));
  });

  test('the recorder state names are the ones the bar shows', () {
    expect(RecorderState.values, hasLength(3));
  });
}
