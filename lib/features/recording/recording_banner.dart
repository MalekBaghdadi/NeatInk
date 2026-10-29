import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_channel.dart';
import '../../document/recording.dart';
import 'recording_controller.dart';

/// Top of the library while a lecture is being recorded (v1.12.0; the user
/// kept it going when she left the notebook): which notebook, how long,
/// and buttons to go back to it or stop.
class RecordingBanner extends ConsumerWidget {
  const RecordingBanner({super.key, required this.onOpenNotebook});

  final void Function(String notebookId) onOpenNotebook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recorder = ref.watch(recordingControllerProvider);
    return ListenableBuilder(
      listenable: recorder,
      builder: (context, _) {
        final notebookId = recorder.notebookId;
        if (!recorder.isActive || notebookId == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        final paused = recorder.state == RecorderState.paused;
        return Material(
          key: const ValueKey('library-recording-banner'),
          color: scheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(paused ? Icons.pause_circle_filled_rounded : Icons.fiber_manual_record_rounded,
                    color: scheme.error, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${paused ? 'Paused' : 'Recording'} for “${recorder.notebookTitle ?? 'a notebook'}” · '
                    '${formatDuration(recorder.elapsedMs)}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  key: const ValueKey('library-recording-open'),
                  style: TextButton.styleFrom(foregroundColor: scheme.onErrorContainer),
                  onPressed: () => onOpenNotebook(notebookId),
                  child: const Text('Open notebook'),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  key: const ValueKey('library-recording-stop'),
                  style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Stop'),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    final done = await recorder.stop();
                    if (done != null) {
                      messenger?.showSnackBar(SnackBar(
                        content: Text('Recording saved (${formatDuration(done.durationMs)}). '
                            'Open the notebook and tap the headphones button to listen.'),
                      ));
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
