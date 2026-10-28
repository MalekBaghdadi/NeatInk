import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../../../../document/page_items.dart';
import '../../../../ink/stroke.dart';
import '../../../../recognition/htr_channel.dart';
import '../../../../recognition/stroke_grouping.dart' show RecognizedLine;
import '../../editor_controller.dart';
import '../../editor_tool.dart';
import '../../stroke_events.dart';
import 'auto_convert_dots.dart';
import 'auto_convert_merge.dart';
import 'convert_apply.dart';
import 'convert_build.dart';
import 'convert_config.dart';
import 'convert_layout.dart';
import 'convert_overlap.dart';
import 'convert_plan.dart';

/// Whether auto-convert should type [line] by itself: it has text, no word
/// was unreadable and the line's confidence (that of its least sure word) is
/// at least [minConfidence]. Anything less stays handwriting, because nobody
/// reviews the result first. The text typed is the line's [PlannedLine.text]:
/// the reading as it is, plus the spelling fixes only when "Fix spelling
/// automatically" is on (suggestions are never applied silently otherwise).
bool autoConvertsLine(PlannedLine line,
    {double minConfidence = ConvertConfig.autoMinConfidence}) {
  if (line.text.trim().isEmpty) return false;
  for (final w in line.words) {
    if (w.text.trim().isEmpty) return false;
  }
  return line.confidence >= minConfidence;
}

/// Converts handwriting to typed text by itself, like the Freenote app.
///
/// While [enabled], every finished PEN stroke (highlighter strokes and
/// snapped shapes are ignored) restarts a timer of [idle] (the user's
/// "Wait before converting" setting, read each time). A new pen-down
/// postpones it. When it fires with the pen up the *pending* strokes (pen
/// strokes finished since the last pass that are still on the page) are
/// grouped into lines, each line is read as a whole, and it is typed only if
/// the line was read confidently (see [autoConvertsLine]). A line that is not
/// typed keeps its ink exactly as it is and is *held*: it is read again, as
/// a whole, only when more is written on the same line (a sentence finished
/// after a pause), and [keptLines] lets the user know (the manual Convert
/// button reads it any time). With "Autocorrect" on
/// ([readAutoFix]) the recogniser's spelling and grammar fixes are applied to
/// the typed text too.
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
    bool Function()? readAutoFix,
    this._enabled = false,
    Duration? idle,
    Duration Function()? readIdle,
    this.minConfidence = ConvertConfig.autoMinConfidence,
    this.metrics = const FlutterTextMetrics(),
    Uuid? uuid,
    bool observeLifecycle = true,
  })  : _readIdle = readIdle ??
            (() => idle ?? const Duration(milliseconds: ConvertConfig.autoIdleMs)),
        readAutoFix = readAutoFix ?? _noAutoFix,
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

  /// Whether to apply the recogniser's spelling and grammar fixes, read at the
  /// start of every pass (the setting "Autocorrect", on by
  /// default).
  final bool Function() readAutoFix;

  static bool _noAutoFix() => false;

  /// Quiet time after the last stroke before a pass starts; read every time
  /// the timer starts, so a new setting applies to the next stroke.
  Duration get idle => _readIdle();
  final Duration Function() _readIdle;
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

  /// Strokes auto-convert must not look at again: converted (so an undo does
  /// not convert them again), or written while the app was away.
  final Set<String> _ignored = {};

  /// Strokes of lines a pass was not sure about, per page: left as ink, and
  /// read again (with the rest of their line) only when new strokes are
  /// written on the same line.
  final Map<String, Set<String>> _held = {};

  /// Held strokes that are only dots away from any text: they wait like the
  /// held lines, but do not count as unsure lines ([keptLines]).
  final Set<String> _quietHeld = {};

  /// Lines kept as handwriting because auto-convert was not sure what they
  /// say, since the user last looked ([clearKept]); a line that is read
  /// again and kept again counts once. Drives the "Kept as handwriting" chip.
  final ValueNotifier<int> keptLines = ValueNotifier(0);

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

  /// The user looked at the kept lines (opened the review sheet).
  void clearKept() {
    if (!_disposed) keptLines.value = 0;
  }

  @visibleForTesting
  Set<String> get ignoredIds => Set.unmodifiable(_ignored);

  @visibleForTesting
  int get pendingCount => _pending.values.fold(0, (n, l) => n + l.length);

  @visibleForTesting
  int get heldCount => _held.values.fold(0, (n, l) => n + l.length);

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
    _held.clear();
    keptLines.value = 0;
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
    keptLines.dispose();
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

  /// Puts [taken] back at the front of the waiting strokes; those that were
  /// held before the pass ([reheld]) are held again instead.
  void _restore(Map<String, List<String>> taken, [Map<String, Set<String>> reheld = const {}]) {
    if (!_enabled || _away) return;
    taken.forEach((pageId, ids) {
      final back = reheld[pageId] ?? const <String>{};
      final waiting = [for (final id in ids) if (!back.contains(id)) id];
      final held = [for (final id in ids) if (back.contains(id)) id];
      if (held.isNotEmpty) _held.putIfAbsent(pageId, () => <String>{}).addAll(held);
      if (waiting.isNotEmpty) _pending[pageId] = [...waiting, ...?_pending[pageId]];
    });
  }

  Future<void> _pass() async {
    final generation = _generation;
    final style = readStyle();
    final autoFix = readAutoFix();
    final doc = controller.doc;

    // 1. Take what is waiting.
    final taken = <String, List<String>>{};
    // Held strokes that join this pass (their line got new strokes).
    final reheld = <String, Set<String>>{};
    final scope = <PageStrokes>[];
    for (final entry in _pending.entries) {
      final pageId = entry.key;
      if (entry.value.isEmpty) continue;
      final meta = doc.pageMeta(pageId);
      if (meta == null || !controller.isPageEditable(pageId)) {
        _ignored.addAll(entry.value);
        continue;
      }
      final pageStrokes = doc.page(pageId).strokes;
      final byId = {for (final s in pageStrokes) s.id: s};
      bool usable(String id) {
        final s = byId[id];
        if (s == null || _ignored.contains(id)) return false; // gone, or not ours
        return s.tool == StrokeTool.pen && s.shape == null;
      }

      final fresh = {for (final id in entry.value) if (usable(id)) id};
      if (fresh.isEmpty) continue;
      // A held line that got new strokes is read again as a whole.
      final held = _held[pageId];
      final chosen = {...fresh};
      if (held != null) {
        held.removeWhere((id) => !usable(id));
        if (held.isNotEmpty) {
          final lines = groupPageStrokes([
            for (final s in pageStrokes)
              if (held.contains(s.id) || fresh.contains(s.id)) s,
          ]);
          for (final RecognizedLine line in lines) {
            final ids = [for (final s in line.inkStrokes) s.id];
            if (ids.any(fresh.contains)) chosen.addAll(ids);
          }
          final back = chosen.where(held.contains).toSet();
          if (back.isNotEmpty) reheld[pageId] = back;
          held.removeAll(back);
        }
      }
      // In writing order.
      final strokes = [for (final s in pageStrokes) if (chosen.contains(s.id)) s];
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
      plans = await recognizePages(scope, recognizer,
              cancel: token, autoFix: autoFix)
          .timeout(ConvertConfig.autoPassTimeout);
    } on ConvertCancelled {
      rethrow;
    } catch (_) {
      token.cancel();
      _restore(taken, reheld);
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
      _restore(taken, reheld);
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
    var kept = keptLines.value;

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
      final before = reheld[pageId] ?? const <String>{};
      bool wasHeld(PlannedLine l) =>
          l.strokeIds.any((id) => before.contains(id) && !_quietHeld.contains(id));
      final ruling = PageRuling.of(meta.paper, meta.width, meta.height,
          isPdf: meta.isPdf);
      // Late dots (an i-dot, a t-bar or a full stop written after the word
      // was typed) go with the text they finish (auto_convert_dots.dart).
      final dotStrokes = <String>{};
      final marks = <String, String>{}; // box id -> punctuation to add
      AutoBoxVersion? memoryOf(TextItem live) {
        for (final b in _boxes[pageId]?.values ?? const <AutoBox>[]) {
          final v = b.versionOf(live);
          if (v != null) return v;
        }
        return null;
      }

      for (final line in plan.lines) {
        // Strokes that moved or vanished while we were reading: not ours to
        // convert now; they wait for the next pass.
        final fresh = line.strokeIds.every((id) =>
            identical(current[id], originals[pageId]![id]));
        final dotsOnly = fresh &&
            onlyDots(line.line.inkStrokes,
                reference: ruling?.spacing ?? ConvertConfig.fallbackRuling);
        final late = !dotsOnly
            ? null
            : lateDotsTarget(
                strokes: line.line.inkStrokes,
                boxes: page.texts,
                memory: memoryOf,
                metrics: metrics,
              );
        if (!fresh) {
          stale.putIfAbsent(pageId, () => []).addAll(line.strokeIds);
        } else if (late != null) {
          dotStrokes.addAll(line.strokeIds);
          final mark = late.mark;
          if (mark != null) marks.putIfAbsent(late.box.id, () => mark);
          if (wasHeld(line)) kept--;
        } else if (dotsOnly) {
          // Dots on their own are never a text box ("." or "?"): they wait,
          // quietly, for writing next to them (a bullet, then its text).
          _held.putIfAbsent(pageId, () => <String>{}).addAll(line.strokeIds);
          _quietHeld.addAll(line.strokeIds);
        } else if (autoConvertsLine(line, minConfidence: minConfidence)) {
          typeIt.add(line.id);
          if (wasHeld(line)) kept--; // a kept line came through after all
        } else {
          // Not sure: stays ink, and waits for the rest of its line.
          _held.putIfAbsent(pageId, () => <String>{}).addAll(line.strokeIds);
          if (!wasHeld(line)) kept++;
        }
      }
      if (typeIt.isEmpty && dotStrokes.isEmpty) continue;

      final laid = typeIt.isEmpty
          ? const <LaidOutLine>[]
          : layoutPlannedPage(
              plan: plan,
              meta: meta,
              style: style,
              metrics: metrics,
              uuid: _uuid,
              convert: (l) => typeIt.contains(l.id),
            );
      if (laid.isEmpty && dotStrokes.isEmpty) {
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
      final ids = <String>{...dotStrokes};
      // Text boxes as they will be after this pass, so a new or grown box
      // never covers another (convert_overlap.dart).
      final grownIds = <String>{};
      final placed = <TextItem>[];
      List<TextItem> occupied() => [
            for (final t in page.texts)
              if (!grownIds.contains(t.id)) t,
            ...placed,
          ];
      for (final out in laid) {
        // A box may hold several written lines (joined into a sentence).
        final lines = [for (final id in out.members) lineById[id]!];
        final geometry = LineGeometry.of(lines.first.line);
        final last =
            lines.length == 1 ? geometry : LineGeometry.of(lines.last.line);
        for (final l in lines) {
          ids.addAll(l.strokeIds);
        }
        var merge = planMerge(
          boxes: boxes?.values ?? const <AutoBox>[],
          pageTexts: occupied(),
          liveItem: page.textById,
          line: geometry,
          text: out.item.text,
          corrections: out.item.corrections,
          pageWidth: meta.width,
          metrics: metrics,
          taken: takenBoxes,
          joinLines: style.joinLines,
          ruling: ruling,
        );
        // Growing a box over text written earlier would hide it: the line
        // gets a box of its own instead.
        if (merge != null && overlapsAny(merge.after, occupied())) merge = null;
        final inkRight = last.right;
        final inkBaseline = last.baselineAt(last.right);
        if (merge != null) {
          takenBoxes.add(merge.box.id);
          grownIds.add(merge.before.id);
          placed.add(merge.after);
          replacements.add((merge.before, merge.after));
          grownBoxes.putIfAbsent(pageId, () => []).add((
            merge.box,
              AutoBoxVersion(merge.after, inkRight, inkBaseline, inkXHeight: last.xHeight),
          ));
        } else {
          final item = placeClear(out.item, occupied(),
              pageHeight: meta.height, metrics: metrics, ruling: ruling);
          placed.add(item);
          items.add(item);
          newBoxes.putIfAbsent(pageId, () => []).add(
              AutoBox(AutoBoxVersion(item, inkRight, inkBaseline, inkXHeight: last.xHeight)));
        }
      }
      // A full stop or comma written late joins its box's text.
      marks.forEach((boxId, mark) {
        final at = replacements.indexWhere((r) => r.$1.id == boxId);
        final live = at >= 0 ? replacements[at].$2 : page.textById(boxId);
        if (live == null) return;
        final punctuated = live.copyWith(text: '${live.text.trimRight()}$mark');
        final natural = metrics.naturalWidth(punctuated) + ConvertConfig.lineSlack;
        final room = meta.width - ConvertConfig.rightMargin - live.x;
        final wider = natural > live.width && natural <= room
            ? punctuated.copyWith(width: natural)
            : punctuated;
        final after = wider.copyWith(height: metrics.heightOf(wider));
        if (at >= 0) {
          replacements[at] = (replacements[at].$1, after);
          // The box grew this pass too: remember it with the mark.
          final grown = grownBoxes[pageId] ?? const [];
          for (var i = 0; i < grown.length; i++) {
            final (b, v) = grown[i];
            if (v.item.id == boxId) {
              grown[i] = (b, AutoBoxVersion(after, v.inkRight, v.inkBaseline, inkXHeight: v.inkXHeight));
            }
          }
          return;
        }
        replacements.add((live, after));
        final memory = memoryOf(live);
        for (final b in _boxes[pageId]?.values ?? const <AutoBox>[]) {
          if (b.versionOf(live) != null && memory != null) {
            grownBoxes.putIfAbsent(pageId, () => []).add((
              b,
              AutoBoxVersion(after, memory.inkRight, memory.inkBaseline, inkXHeight: memory.inkXHeight),
            ));
            break;
          }
        }
      });
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
    _quietHeld.removeAll(converted);
    if (stale.isNotEmpty) _restore(stale, reheld);
    keptLines.value = kept < 0 ? 0 : kept;
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
      final map = _boxes.putIfAbsent(pageId, () => {});
      for (final (box, version) in list) {
        box.versions.add(version);
        // A box typed earlier (Convert button, another session) that a line
        // was appended to is followed from now on, like the ones made here.
        map.putIfAbsent(box.id, () => box);
      }
    });
  }
}
