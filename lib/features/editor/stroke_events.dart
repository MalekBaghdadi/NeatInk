import 'dart:async';

import '../../ink/stroke.dart';

/// A pen or highlighter stroke started (pen down).
class StrokeStartedEvent {
  const StrokeStartedEvent({
    required this.pageId,
    required this.tool,
    required this.startMs,
  });

  final String pageId;
  final StrokeTool tool;

  /// Pointer-clock time of pen down, in milliseconds. Same clock as
  /// [FinishedStroke.startMs] / [FinishedStroke.endMs].
  final int startMs;
}

/// A pen or highlighter stroke was committed to a page.
class FinishedStroke {
  const FinishedStroke({
    required this.pageId,
    required this.stroke,
    required this.startMs,
    required this.endMs,
  });

  final String pageId;

  /// The stroke as committed (already in the page's content).
  final Stroke stroke;

  /// Pointer-clock times of pen down and pen up, in milliseconds. The clock
  /// is monotonic (Android: uptime) and shared by all strokes, so gaps
  /// between strokes are `next.startMs - previous.endMs`.
  final int startMs;
  final int endMs;
}

/// Broadcast streams of stroke lifecycle events, for the tidy integration.
///
/// Events are delivered asynchronously (after the command has been
/// applied), in order.
class StrokeEvents {
  final StreamController<StrokeStartedEvent> _started =
      StreamController.broadcast();
  final StreamController<FinishedStroke> _finished =
      StreamController.broadcast();

  Stream<StrokeStartedEvent> get started => _started.stream;
  Stream<FinishedStroke> get finished => _finished.stream;

  /// Called by the ink tool.
  void emitStarted(StrokeStartedEvent e) {
    if (!_started.isClosed) _started.add(e);
  }

  /// Called by the ink tool after committing a stroke.
  void emitFinished(FinishedStroke e) {
    if (!_finished.isClosed) _finished.add(e);
  }

  Future<void> close() async {
    await Future.wait([_started.close(), _finished.close()]);
  }
}
