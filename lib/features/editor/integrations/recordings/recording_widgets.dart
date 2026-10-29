import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../audio/audio_channel.dart';
import '../../../../document/recording.dart';
import 'playback_controller.dart';
import 'recordings_integration.dart';

// The recording screens of the editor (v1.12.0), worded for someone who has
// never recorded a lecture with an app: every button says what it does, the
// first recording is explained step by step, and the player says what the
// faint notes mean.

/// App bar: the microphone. Hidden while this notebook is recording (the
/// recording bar has the controls).
class RecordButton extends StatelessWidget {
  const RecordButton({super.key, required this.actions});

  final RecordingActions actions;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: actions.recorder,
        builder: (context, _) {
          if (actions.recordingHere) return const SizedBox.shrink();
          return IconButton(
            key: const ValueKey('record-lecture'),
            icon: const Icon(Icons.mic_none_rounded),
            tooltip: 'Record a lecture',
            onPressed: () => unawaited(actions.startRecording(context)),
          );
        },
      );
}

/// App bar: the notebook's recordings, with how many there are. Hidden when
/// it has none.
class RecordingsButton extends StatelessWidget {
  const RecordingsButton({super.key, required this.actions});

  final RecordingActions actions;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<Recording>>(
        valueListenable: actions.list,
        builder: (context, list, _) {
          final done = list.where((r) => !r.inProgress).length;
          if (done == 0) return const SizedBox.shrink();
          return IconButton(
            key: const ValueKey('open-recordings'),
            icon: Badge(label: Text('$done'), child: const Icon(Icons.headphones_rounded)),
            tooltip: 'Recordings: listen again',
            onPressed: () => unawaited(actions.openList(context)),
          );
        },
      );
}

/// Under the tools while this notebook is recording: a pulsing dot, the
/// time, the microphone level, Pause / Go on and Stop.
class RecordingBar extends StatelessWidget {
  const RecordingBar({super.key, required this.actions});

  final RecordingActions actions;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: actions.recorder,
        builder: (context, _) {
          if (!actions.recordingHere) return const SizedBox.shrink();
          final recorder = actions.recorder;
          final paused = recorder.state == RecorderState.paused;
          final scheme = Theme.of(context).colorScheme;
          final wide = MediaQuery.sizeOf(context).width >= 700;
          return Material(
            key: const ValueKey('recording-bar'),
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  _RecordingDot(paused: paused, color: scheme.error),
                  const SizedBox(width: 10),
                  Text(
                    paused ? 'Paused' : 'Recording',
                    style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onErrorContainer),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatDuration(recorder.elapsedMs),
                    key: const ValueKey('recording-time'),
                    style: TextStyle(
                      color: scheme.onErrorContainer,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (!paused) _LevelMeter(level: recorder.level, color: scheme.onErrorContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: wide
                        ? Text(
                            paused
                                ? 'Nothing is recorded now. Tap Go on to record again.'
                                : 'Write as usual: your notes are kept in step with the sound.',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: scheme.onErrorContainer),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Tooltip(
                    message: paused ? 'Record again' : 'Pause the recording for a moment',
                    child: TextButton.icon(
                      key: ValueKey(paused ? 'recording-resume' : 'recording-pause'),
                      style: TextButton.styleFrom(foregroundColor: scheme.onErrorContainer),
                      icon: Icon(paused ? Icons.fiber_manual_record_rounded : Icons.pause_rounded),
                      label: Text(paused ? 'Go on' : 'Pause'),
                      onPressed: () => unawaited(paused ? recorder.resume() : recorder.pause()),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Stop and save the recording',
                    child: FilledButton.icon(
                      key: const ValueKey('recording-stop'),
                      style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('Stop'),
                      onPressed: () => unawaited(actions.stopRecording(context)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class _RecordingDot extends StatefulWidget {
  const _RecordingDot({required this.paused, required this.color});

  final bool paused;
  final Color color;

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(_RecordingDot old) {
    super.didUpdateWidget(old);
    _update();
  }

  void _update() {
    final still = widget.paused || MediaQuery.of(context).disableAnimations;
    if (still) {
      _pulse.stop();
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      unawaited(_pulse.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.35, end: 1).animate(_pulse),
        child: Icon(
          widget.paused ? Icons.pause_circle_filled_rounded : Icons.fiber_manual_record_rounded,
          color: widget.color,
          size: 18,
        ),
      );
}

/// Five bars that light up with the microphone's loudness: proof that it
/// hears the lecture.
class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level, required this.color});

  final double level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Speech is far from full scale: the square root spreads it out.
    final lit = (math.sqrt(level.clamp(0.0, 1.0)) * 5).round();
    return Tooltip(
      message: 'How loud the microphone hears it',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 5; i++)
            Container(
              width: 4,
              height: 6.0 + 3 * i,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: i < lit ? color : color.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }
}

/// Under the tools while a recording plays: back 10 s, play / pause, ahead
/// 10 s, where it is, the speed, "Notes appear as written" and close.
class PlayerBar extends StatefulWidget {
  const PlayerBar({super.key, required this.actions});

  final RecordingActions actions;

  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar> {
  double? _dragging;

  PlaybackController get _p => widget.actions.playback;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _p,
        builder: (context, _) {
          final rec = _p.recording;
          if (rec == null) return const SizedBox.shrink();
          final scheme = Theme.of(context).colorScheme;
          final wide = MediaQuery.sizeOf(context).width >= 700;
          final duration = math.max(1, _p.duration);
          final position = (_dragging ?? _p.position.toDouble()).clamp(0, duration).toDouble();
          final time = TextStyle(fontFeatures: const [FontFeature.tabularFigures()], color: scheme.onSurfaceVariant);
          return Material(
            key: const ValueKey('player-bar'),
            color: scheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 8, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        key: const ValueKey('player-close'),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Stop playing and close',
                        onPressed: () => unawaited(_p.close()),
                      ),
                      Icon(Icons.headphones_rounded, size: 18, color: scheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(rec.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Tooltip(
                        message: _p.withNotes
                            ? 'On: notes appear when the sound reaches the moment you wrote them'
                            : 'Off: all your notes show as usual',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(wide ? 'Notes appear as written' : 'Notes as written'),
                            Switch(
                              key: const ValueKey('player-with-notes'),
                              value: _p.withNotes,
                              onChanged: _p.setWithNotes,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        key: const ValueKey('player-back'),
                        icon: const Icon(Icons.replay_10_rounded),
                        tooltip: 'Back 10 seconds',
                        onPressed: () => unawaited(_p.skip(-10000)),
                      ),
                      IconButton.filled(
                        key: const ValueKey('player-play'),
                        icon: Icon(_p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        tooltip: _p.playing ? 'Pause' : 'Play',
                        onPressed: () => unawaited(_p.togglePlay()),
                      ),
                      IconButton(
                        key: const ValueKey('player-ahead'),
                        icon: const Icon(Icons.forward_10_rounded),
                        tooltip: 'Ahead 10 seconds',
                        onPressed: () => unawaited(_p.skip(10000)),
                      ),
                      Text(formatDuration(position.round()), style: time),
                      Expanded(
                        child: Slider(
                          key: const ValueKey('player-slider'),
                          value: position,
                          max: duration.toDouble(),
                          onChanged: (v) => setState(() => _dragging = v),
                          onChangeEnd: (v) {
                            setState(() => _dragging = null);
                            unawaited(_p.seek(v.round()));
                          },
                        ),
                      ),
                      Text(formatDuration(_p.duration), style: time),
                      Tooltip(
                        message: 'Playing speed: tap to change',
                        child: TextButton(
                          key: const ValueKey('player-speed'),
                          onPressed: () => unawaited(_p.nextSpeed()),
                          child: Text('${_p.speed.toString().replaceAll(RegExp(r'\.0$'), '')}×'),
                        ),
                      ),
                    ],
                  ),
                  if (_p.withNotes)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                      child: Text(
                        'Faint notes are still to come. Tap any note to hear that moment.',
                        key: const ValueKey('player-hint'),
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
}

/// The first time: what recording a lecture does, in three steps. True:
/// start now.
Future<bool?> showRecordingIntro(BuildContext context) => showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('recording-intro'),
        icon: const Icon(Icons.mic_rounded),
        title: const Text('Record a lecture'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('The tablet records the sound while you write. Later you can listen again, '
                  'and watch your notes appear as you wrote them.'),
              SizedBox(height: 16),
              _Step(n: 1, text: 'Tap Start recording. The first time, the tablet asks to use the microphone: tap Allow.'),
              _Step(n: 2, text: 'Write your notes as usual. You can pause, or switch to another app: it keeps recording.'),
              _Step(n: 3, text: 'Tap Stop when the lecture ends.'),
              SizedBox(height: 8),
              Text('To listen: tap the headphones button at the top, then Play or Play with notes.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          FilledButton.icon(
            key: const ValueKey('recording-intro-start'),
            icon: const Icon(Icons.fiber_manual_record_rounded),
            onPressed: () => Navigator.pop(context, true),
            label: const Text('Start recording'),
          ),
        ],
      ),
    );

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});

  final int n;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(radius: 12, child: Text('$n', style: const TextStyle(fontSize: 13))),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

/// The microphone was refused: how to allow it.
Future<void> showMicrophoneOff(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('microphone-off'),
        icon: const Icon(Icons.mic_off_rounded),
        title: const Text('The microphone is off'),
        content: const Text("Mariam's Notes needs the microphone to record. Open the tablet's Settings › Apps › "
            "Mariam's Notes › Permissions › Microphone, choose Allow, then tap the microphone button again."),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );

/// The notebook's recordings, each with Play and Play with notes.
Future<void> showRecordingsSheet(BuildContext context, RecordingActions actions) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ValueListenableBuilder<List<Recording>>(
          valueListenable: actions.list,
          builder: (context, list, _) {
            final done = list.where((r) => !r.inProgress).toList().reversed.toList();
            final scheme = Theme.of(context).colorScheme;
            return ListView(
              key: const ValueKey('recordings-sheet'),
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text('Recordings', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('Play: listen to the lecture.\n'
                    'Play with notes: your notes appear as you wrote them, in step with the sound. '
                    'Tap any note to hear that moment.',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                if (done.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No recordings yet. Tap the microphone at the top to record a lecture '
                        'while you take notes.'),
                  ),
                for (final r in done) _RecordingCard(recording: r, actions: actions),
              ],
            );
          },
        ),
      ),
    );

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({required this.recording, required this.actions});

  final Recording recording;
  final RecordingActions actions;

  @override
  Widget build(BuildContext context) {
    final busy = actions.recordingHere;
    final hasNotes = actions.playback.hasNotesFor(recording);
    final when = DateTime.fromMillisecondsSinceEpoch(recording.createdAt);
    void playThen(bool withNotes) {
      Navigator.pop(context);
      unawaited(actions.play(context, recording, withNotes: withNotes));
    }

    return Card(
      key: ValueKey('recording-${recording.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(recording.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      // The default name already says when.
                      Text(recording.title.contains(_date(when))
                          ? 'Length ${formatDuration(recording.durationMs)}'
                          : '${_date(when)} · ${formatDuration(recording.durationMs)}'),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  key: ValueKey('recording-menu-${recording.id}'),
                  tooltip: 'Rename or delete',
                  onSelected: (v) => unawaited(
                      v == 'rename' ? actions.rename(context, recording) : actions.delete(context, recording)),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: ValueKey('recording-play-${recording.id}'),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                  onPressed: busy ? null : () => playThen(false),
                ),
                Tooltip(
                  message: hasNotes
                      ? 'Your notes appear as you wrote them'
                      : 'No notes were written while this was recorded',
                  child: FilledButton.icon(
                    key: ValueKey('recording-play-notes-${recording.id}'),
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('Play with notes'),
                    onPressed: busy || !hasNotes ? null : () => playThen(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime t) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.day} ${months[t.month - 1]}, ${two(t.hour)}:${two(t.minute)}';
  }
}

/// A new name for a recording.
Future<String?> askRecordingName(BuildContext context, String current) {
  final text = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename recording'),
      content: TextField(
        key: const ValueKey('recording-name'),
        controller: text,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, text.text), child: const Text('Rename')),
      ],
    ),
  ).whenComplete(text.dispose);
}

Future<bool?> confirmDeleteRecording(BuildContext context, Recording recording) => showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this recording?'),
        content: Text('“${recording.title}” (${formatDuration(recording.durationMs)}) is deleted for good. '
            'Your notes stay as they are.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            key: const ValueKey('recording-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

/// What to do with a recording that is on when the notebook closes.
enum LeaveChoice { keepRecording, stop }

Future<LeaveChoice?> askWhenLeaving(BuildContext context) => showDialog<LeaveChoice>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('recording-leave'),
        icon: const Icon(Icons.mic_rounded),
        title: const Text('Your recording is still on'),
        content: const Text('You can keep recording while you look at other notebooks: it shows at the top '
            'of your library, with a Stop button. Notes you write here are kept in step with it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Stay here')),
          TextButton(
            key: const ValueKey('recording-leave-stop'),
            onPressed: () => Navigator.pop(context, LeaveChoice.stop),
            child: const Text('Stop and save'),
          ),
          FilledButton(
            key: const ValueKey('recording-leave-keep'),
            onPressed: () => Navigator.pop(context, LeaveChoice.keepRecording),
            child: const Text('Keep recording'),
          ),
        ],
      ),
    );
