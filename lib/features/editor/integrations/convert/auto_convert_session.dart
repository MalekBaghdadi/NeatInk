import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../../../../document/page_items.dart';
import '../../../../ink/stroke.dart';
import '../../../../recognition/htr_channel.dart';
import '../../editor_controller.dart';
import '../../editor_tool.dart';
import '../../stroke_events.dart';
import 'auto_convert_merge.dart';
import 'convert_apply.dart';
import 'convert_build.dart';
import 'convert_config.dart';
import 'convert_layout.dart';
import 'convert_plan.dart';

/// Whether auto-convert should type [line] by itself: no word was unreadable
/// and EVERY word was read with at least [minConfidence]. Anything less stays
/// handwriting, because nobody reviews the result first.
bool autoConvertsLine(PlannedLine line,
    {double minConfidence = ConvertConfig.autoMinConfidence}) {
  if (line.words.isEmpty) return false;
  for (final w in line.words) {
    if (w.text.trim().isEmpty) return false;
    if (!(w.confidence >= minConfidence)) return false;
  }
  return true;
}

/// Converts handwriting to typed text by itself, like the Freenote app.
///
/// While [enabled], every finished PEN stroke (highlighter strokes and
/// snapped shapes are ignored) restarts a timer of [idle]
/// (`ConvertConfig.autoIdleMs`). A new pen-down postpones it. When it fires
/// with the pen up the *pending* strokes (pen strokes finished since the last
/// pass that are still on the page) are grouped, read, and each line is typed
/// only if every word was read confidently (see [autoConvertsLine]). Lines
/// that are not typed keep their ink exactly as it is and are never tried
/// again by auto-convert (the manual Convert button still reads them).
///
/// One pass is one undo step ("Auto-convert"). Strokes it converted are
/// remembered as ignored, so undoing never converts them again. A line that
/// starts just after an earlier auto-typed box on the same baseline is
/// appended to that box instead of making a second one.
///
/// Nothing is converted while the page is read-only, a tool other than the
/// pen is selected, the pen is down or the app is in the background. The
/// recogniser never runs inside the pen path: all work happens on the timer,
/// and a failure only shows up on [failures].
class AutoConvertSession with WidgetsBindingObserver {
  AutoConvertSession({
    required this.controller,
    required this.recognizer,
    required this.readStyle,
    this._enabled = false,
    Duration? idle,
    this.minConfidence = ConvertConfig.autoMinConfidence,
    this.metrics = const FlutterTextMetrics(),
    Uuid? uuid,
    bool observeLifecycle = true,
  })  : idle = idle ?? const Duration(milliseconds: ConvertConfig.autoIdleMs),
        _uuid = uuid ?? const Uuid() {
    _startedSub = controller.strokeEvents.started.listen(_onStarted);
    _finishedSub = controller.strokeEvents.finished.listen(_onFinished);
    controller.addListener(_onControllerChanged);
    if (observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
  }

  final EditorController controller;
  final HtrRecognizer recognizer;

  /// The look to type with, read at the start of every pass.
  final ConvertStyle Function() readStyle;

  /// Quiet time after the last stroke before a pass starts.
  final Duration idle;
  final double minConfidence;
  final ConvertTextMetrics metrics;
  final Uuid _uuid;

  bool _enabled;
  bool _away = false;
  bool _disposed = false;
  bool _observing = false;
  bool _running = false;
  bool _rearm = false;
  bool _failurePaused = false;
  String? _lastFailure;
  Timer? _timer;
  ConvertCancelToken? _token;

  /// Counts pen activity; a pass whose number changed while it was reading
  /// is thrown away (the user is still writing).
  int _generation = 0;

  /// Pen strokes finished since the last pass, per page, oldest first.
  final Map<String, List<String>> _pending = {};

  /// Strokes auto-convert must not look at again: left as ink on purpose,
  /// converted (so an undo does not convert them again), or written while the
  /// app was away.
  final Set<String> _ignored = {};

  /// The boxes auto-convert made, per page (in memory only).
  final Map<String, Map<String, AutoBox>> _boxes = {};

  StreamSubscription<StrokeStartedEvent>? _startedSub;
  StreamSubscription<FinishedStroke>? _finishedSub;
  final StreamController<String> _failures = StreamController.broadcast();

  /// True while a pass is reading handwriting (drives the small
  /// "Converting..." indicator).
  final ValueNotifier<bool> working = ValueNotifier(false);

  /// Messages for failed passes: once per failure, not repeated until a pass
  /// works again. Auto-convert then waits for the next stroke.
  Stream<String> get failures => _failures.stream;

  bool get enabled => _enabled;

  @visibleForTesting
  Set<String> get ignoredIds => Set.unmodifiable(_ignored);

  @visibleForTesting
  int get pendingCount => _pending.values.fold(0, (n, l) => n + l.length);

  @visibleForTesting
  bool get hasTimer => _timer != null;

  bool get _hasPending => _pending.values.any((l) => l.isNotEmpty);

  // ---------------------------------------------------------------------------
  // Switching on and off

  /// The "Auto-convert" setting changed. Turning it off cancels a pending
  /// pass and forgets what was waiting (it all stays ink).
  void setEnabled(bool value) {
    if (_disposed || value == _enabled) return;
    _enabled = value;
    if (!value) _standDown();
  }

  void _standDown() {
    _timer?.cancel();
    _timer = null;
    _generation++;
    _token?.cancel();
    _pending.clear();
    _failurePaused = false;
    _lastFailure = null;
  }

  /// The app went to the background or came back. Nothing is flushed on the
  /// way out: what was waiting stays ink for good.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (away == _away) return;
    _away = away;
    if (away) {
      for (final ids in _pending.values) {
        _ignored.addAll(ids);
      }
      _standDown();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _token?.cancel();
    unawaited(_startedSub?.cancel());
    unawaited(_finishedSub?.cancel());
    controller.removeListener(_onControllerChanged);
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    working.dispose();
    unawaited(_failures.close());
  }

  // ---------------------------------------------------------------------------
  // Pen events

  void _onStarted(StrokeStartedEvent e) {
    if (_disposed || !_enabled || _away || e.tool != StrokeTool.pen) return;
    // Pen down: whatever was about to be read waits for this stroke too.
    _generation++;
    _arm();
  }

  void _onFinished(FinishedStroke e) {
    if (_disposed || !_enabled || _away) return;
    final s = e.stroke;
    if (s.tool != StrokeTool.pen || s.shape != null) return;
    _generation++;
    _failurePaused = false;
    if (!controller.isPageEditable(e.pageId)) return;
    _pending.putIfAbsent(e.pageId, () => <String>[]).add(s.id);
    _arm();
  }

  /// A tool switch back to the pen releases strokes that waited for it.
  void _onControllerChanged() {
    if (_disposed || !_enabled || _away || _running || _timer != null) return;
    if (_failurePaused || !_hasPending) return;
    if (!controller.isReady || controller.tool != EditorTool.pen) return;
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(idle, _onIdle);
  }

  void _onIdle() {
    _timer = null;
    if (_disposed || !_enabled || _away || !controller.isReady) return;
    if (_running) {
      _rearm = true;
      return;
    }
    // The pen is down again: try later.
    if (controller.inkTool.active != null) {
      _arm();
      return;
    }
    // Another tool is in use (lasso selection, eraser...): the strokes wait.
    if (controller.tool != EditorTool.pen) return;
    if (_failurePaused || !_hasPending) return;
    unawaited(_runPass());
  }

  // ---------------------------------------------------------------------------
  // One pass

  Future<void> _runPass() async {
    _running = true;
    try {
      await _pass();
    } on ConvertCancelled {
      // Switched off, paused or closed meanwhile: nothing to do.
    } catch (e, st) {
      debugPrint('NeatInk: auto-convert failed: $e\n$st');
      _reportFailure(e);
    } finally {
      _running = false;
      if (!_disposed) {
        working.value = false;
        if (_rearm) {
          _rearm = false;
          if (_enabled && !_away) _arm();
        }
      }
    }
  }

  void _reportFailure(Object e) {
    _failurePaused = true;
    final message =
        e is HtrException ? e.userMessage : 'Reading the handwriting failed.';
    if (_disposed || message == _lastFailure) return;
    _lastFailure = message;
    _failures.add(message);
  }

  /// Puts [taken] back at the front of the waiting strokes.
  void _restore(Map<String, List<String>> taken) {
    if (!_enabled || _away) return;
    taken.forEach((pageId, ids) {
      if (ids.isEmpty) return;
      _pending[pageId] = [...ids, ...?_pending[pageId]];
    });
  }

  Future<void> _pass() async {
    final generation = _generation;
    final style = readStyle();
    final doc = controller.doc;

    // 1. Take what is waiting.
    final taken = <String, List<String>>{};
    final scope = <PageStrokes>[];
    for (final entry in _pending.entries) {
      final pageId = entry.key;
      if (entry.value.isEmpty) continue;
      final meta = doc.pageMeta(pageId);
      if (meta == null || !controller.isPageEditable(pageId)) {
        _ignored.addAll(entry.value);
        continue;
      }
      final byId = {for (final s in doc.page(pageId).strokes) s.id: s};
      final strokes = <Stroke>[];
      for (final id in entry.value) {
        final s = byId[id];
        if (s == null || _ignored.contains(id)) continue; // gone, or not ours
        if (s.tool != StrokeTool.pen || s.shape != null) continue;
        strokes.add(s);
      }
      if (strokes.isEmpty) continue;
      taken[pageId] = [for (final s in strokes) s.id];
      scope.add(PageStrokes(
        pageId: pageId,
        pageIndex: doc.meta.indexOfPage(pageId),
        strokes: strokes,
      ));
    }
    _pending.clear();
    if (scope.isEmpty) return;

    // 2. Read it.
    final token = _token = ConvertCancelToken();
    working.value = true;
    final List<PagePlan> plans;
    try {
      plans = await recognizePages(scope, recognizer, cancel: token)
          .timeout(ConvertConfig.autoPassTimeout);
    } on ConvertCancelled {
      rethrow;
    } catch (_) {
      token.cancel();
      _restore(taken);
      rethrow;
    }
    if (_disposed) return;
    _lastFailure = null;

    // 3. Still the right moment? Otherwise throw the reading away and let
    //    the strokes wait for the next pass.
    if (!_enabled || _away) return;
    if (generation != _generation ||
        controller.inkTool.active != null ||
        controller.tool != EditorTool.pen) {
      _restore(taken);
      return;
    }

    // 4. Decide, lay out, merge and apply.
    final originals = {
      for (final p in scope) p.pageId: {for (final s in p.strokes) s.id: s},
    };
    final conversions = <PageConversion>[];
    final converted = <String>{};
    final newBoxes = <String, List<AutoBox>>{};
    final grownBoxes = <String, List<(AutoBox, AutoBoxVersion)>>{};
    final stale = <String, List<String>>{};

    for (final plan in plans) {
      final pageId = plan.pageId;
      final meta = doc.pageMeta(pageId);
      if (meta == null || !controller.isPageEditable(pageId)) {
        for (final l in plan.lines) {
          _ignored.addAll(l.strokeIds);
        }
        continue;
      }
      final page = doc.page(pageId);
      final current = {for (final s in page.strokes) s.id: s};
      final typeIt = <String>{};
      for (final line in plan.lines) {
        // Strokes that moved or vanished while we were reading: not ours to
        // convert now; they wait for the next pass.
        final fresh = line.strokeIds.every((id) =>
            identical(current[id], originals[pageId]![id]));
        if (!fresh) {
          stale.putIfAbsent(pageId, () => []).addAll(line.strokeIds);
        } else if (autoConvertsLine(line, minConfidence: minConfidence)) {
          typeIt.add(line.id);
        } else {
          _ignored.addAll(line.strokeIds);
        }
      }
      if (typeIt.isEmpty) continue;

      final laid = layoutPlannedPage(
        plan: plan,
        meta: meta,
        style: style,
        metrics: metrics,
        uuid: _uuid,
        convert: (l) => typeIt.contains(l.id),
      );
      if (laid.isEmpty) {
        // Nothing came out (a line without text): leave the ink alone.
        for (final l in plan.lines) {
          if (typeIt.contains(l.id)) _ignored.addAll(l.strokeIds);
        }
        continue;
      }

      final lineById = {for (final l in plan.lines) l.id: l};
      final boxes = _boxes[pageId];
      final takenBoxes = <String>{};
      final items = <TextItem>[];
      final replacements = <(TextItem, TextItem)>[];
      final ids = <String>{};
      for (final out in laid) {
        final line = lineById[out.id]!;
        final geometry = LineGeometry.of(line.line);
        ids.addAll(line.strokeIds);
        final merge = boxes == null
            ? null
            : planMerge(
                boxes: boxes.values,
                liveItem: page.textById,
                line: geometry,
                text: out.item.text,
                pageWidth: meta.width,
                metrics: metrics,
                taken: takenBoxes,
              );
        final inkRight = geometry.right;
        final inkBaseline = geometry.baselineAt(geometry.right);
        if (merge != null) {
          takenBoxes.add(merge.box.id);
          replacements.add((merge.before, merge.after));
          grownBoxes.putIfAbsent(pageId, () => []).add((
            merge.box,
            AutoBoxVersion(merge.after, inkRight, inkBaseline),
          ));
        } else {
          items.add(out.item);
          newBoxes.putIfAbsent(pageId, () => []).add(
              AutoBox(AutoBoxVersion(out.item, inkRight, inkBaseline)));
        }
      }
      converted.addAll(ids);
      conversions.add(PageConversion(
        pageId: pageId,
        strokeIds: ids,
        items: items,
        replacements: replacements,
      ));
    }

    // Strokes that were converted are ignored from now on, so an undo puts
    // the ink back for good.
    _ignored.addAll(converted);
    if (stale.isNotEmpty) _restore(stale);
    if (conversions.isEmpty) return;

    final outcome = applyConversion(controller, conversions,
        label: autoConvertCommandLabel);
    if (outcome == null) return;
    newBoxes.forEach((pageId, list) {
      final map = _boxes.putIfAbsent(pageId, () => {});
      for (final b in list) {
        map[b.id] = b;
      }
    });
    grownBoxes.forEach((pageId, list) {
      for (final (box, version) in list) {
        box.versions.add(version);
      }
    });
  }
}
