import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/providers.dart';
import '../../../../audio/audio_channel.dart';
import '../../../../document/recording.dart';
import '../../../recording/recording_controller.dart';
import '../../editor_controller.dart';
import '../../editor_integrations.dart';
import 'playback_controller.dart';
import 'recording_widgets.dart';

/// Lecture recordings in the editor (v1.12.0): the microphone button in the
/// app bar starts a recording (explained the first time), a bar under the
/// tools shows it with Pause and Stop, the headphones button lists the
/// notebook's recordings with "Play" and "Play with notes", and a player bar
/// plays them. Playing with notes, the notes written during the lecture
/// appear as the sound reaches them and a tap on one plays from there.
final EditorIntegration recordingsIntegration = _install;

void _install(EditorController controller, WidgetRef ref) {
  final recorder = ref.read(recordingControllerProvider);
  final playback = PlaybackController(
    editor: controller,
    backend: ref.read(audioBackendProvider),
    store: ref.read(recordingStoreProvider),
  );
  final list = NotebookRecordings(recorder, controller);
  final prefs = ref.read(sharedPreferencesProvider);
  final actions = RecordingActions(
    editor: controller,
    recorder: recorder,
    playback: playback,
    list: list,
    prefs: prefs,
    clock: ref.read(clockProvider),
  );
  controller.addDisposeCallback(() {
    playback.dispose();
    list.dispose();
  });
  controller.extensions
    ..appBarActions.add((context, c) => RecordButton(actions: actions))
    ..appBarActions.add((context, c) => RecordingsButton(actions: actions))
    ..editorBars.add((context, c) => RecordingBar(actions: actions))
    ..editorBars.add((context, c) => PlayerBar(actions: actions))
    ..pageTapHandlers.add(playback.onTap)
    ..beforeLeave.add((context, c) => actions.beforeLeave(context));
}

/// The recordings of the open notebook, kept up to date while the editor is
/// open (they change when a recording stops, is renamed or deleted).
class NotebookRecordings extends ValueNotifier<List<Recording>> {
  NotebookRecordings(this.recorder, this.editor) : super(const []) {
    recorder.addListener(_onRecorder);
    editor.addListener(_onEditor);
    _onEditor();
  }

  final RecordingController recorder;
  final EditorController editor;
  bool _loaded = false;
  bool _wasActive = false;
  bool _disposed = false;

  void _onEditor() {
    if (_loaded || !editor.isReady) return;
    _loaded = true;
    unawaited(refresh());
  }

  void _onRecorder() {
    final active = recorder.isActive && recorder.notebookId == editor.notebookId;
    if (_wasActive != active) unawaited(refresh());
    _wasActive = active;
  }

  Future<void> refresh() async {
    if (!editor.isReady) return;
    final list = await recorder.recordingsOf(editor.notebookId);
    if (!_disposed) value = list;
  }

  @override
  void dispose() {
    _disposed = true;
    recorder.removeListener(_onRecorder);
    editor.removeListener(_onEditor);
    super.dispose();
  }
}

/// What the recording buttons and bars do.
class RecordingActions {
  RecordingActions({
    required this.editor,
    required this.recorder,
    required this.playback,
    required this.list,
    required this.prefs,
    required this.clock,
  });

  final EditorController editor;
  final RecordingController recorder;
  final PlaybackController playback;
  final NotebookRecordings list;
  final SharedPreferences prefs;
  final DateTime Function() clock;

  static const String introSeenKey = 'recordingIntroSeen';

  /// Recording for this notebook now (recording or paused).
  bool get recordingHere => recorder.isActive && recorder.notebookId == editor.notebookId;

  Future<void> startRecording(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (recorder.isActive) {
      messenger?.showSnackBar(SnackBar(
        content: Text('A recording is already on for “${recorder.notebookTitle ?? 'another notebook'}”. '
            'Stop it first: it shows at the top of your library.'),
      ));
      return;
    }
    if (prefs.getBool(introSeenKey) != true) {
      final go = await showRecordingIntro(context);
      if (go != true || !context.mounted) return;
      await prefs.setBool(introSeenKey, true);
    }
    await playback.close();
    final result = await recorder.start(
      editor.notebookId,
      title: defaultRecordingTitle(clock()),
      notebookTitle: editor.title,
    );
    if (!context.mounted) return;
    switch (result) {
      case RecordingStartResult.started:
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Recording. Write your notes as usual.')));
      case RecordingStartResult.noPermission:
        await showMicrophoneOff(context);
      case RecordingStartResult.failed:
        messenger?.showSnackBar(const SnackBar(
          content: Text("The recording couldn't start. Another app may be using the microphone: "
              'close it and try again.'),
        ));
      case RecordingStartResult.busy:
        break;
    }
  }

  Future<void> stopRecording(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final done = await recorder.stop();
    await list.refresh();
    if (done == null) return;
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      content: Text('Recording saved (${formatDuration(done.durationMs)}). Find it under the headphones button.'),
      action: SnackBarAction(label: 'Play with notes', onPressed: () => unawaited(play(context, done, withNotes: true))),
    ));
  }

  Future<void> play(BuildContext context, Recording recording, {required bool withNotes}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (recordingHere) {
      messenger?.showSnackBar(const SnackBar(content: Text('Stop the recording first, then play it.')));
      return;
    }
    await playback.open(recording, withNotes: withNotes);
    final error = playback.takeError();
    if (error != null) messenger?.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> openList(BuildContext context) async {
    await list.refresh();
    if (!context.mounted) return;
    await showRecordingsSheet(context, this);
  }

  Future<void> rename(BuildContext context, Recording recording) async {
    final title = await askRecordingName(context, recording.title);
    if (title == null || title.trim().isEmpty) return;
    await recorder.rename(editor.notebookId, recording.id, title.trim());
    await list.refresh();
  }

  Future<void> delete(BuildContext context, Recording recording) async {
    final yes = await confirmDeleteRecording(context, recording);
    if (yes != true) return;
    if (playback.recording?.id == recording.id) await playback.close();
    await recorder.delete(editor.notebookId, recording.id);
    await list.refresh();
  }

  /// Leaving the notebook: a recording that is on asks what to do; a
  /// playback just stops.
  Future<bool> beforeLeave(BuildContext context) async {
    if (recordingHere) {
      final choice = await askWhenLeaving(context);
      if (choice == null || !context.mounted) return false;
      if (choice == LeaveChoice.stop) await stopRecording(context);
    }
    await playback.close();
    return true;
  }
}
