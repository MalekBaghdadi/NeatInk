import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../../../../beautify/beautify.dart';
import '../../../../document/commands.dart';
import '../../../../document/notebook_doc.dart';
import '../../../../document/notebook_meta.dart';
import '../../../../ink/stroke.dart';
import '../../../settings/app_settings.dart';
import '../../editor_controller.dart';
import '../../editor_extensions.dart';
import '../../editor_tool.dart';
import '../../stroke_events.dart';
import 'tidy_animation.dart';
import 'tidy_debug_overlay.dart';
import 'tidy_overlay.dart';

/// Version written to `Stroke.tidy.version` by this pipeline.
const int tidyPipelineVersion = 1;

/// How many recently tidied words per page the debug overlay remembers.
const int _debugWordsPerPage = 8;

/// Everything the tidy integration remembers about one page: the running
/// context (lines, statistics, tidied words) and the word segmenter that
/// collects pen strokes into words. Built lazily when the page is first
/// written on, from the stored strokes (spec step 7).
class _PageState {
  _PageState(this.pageId, this.signature, this.ctx, this.seg);

  final String pageId;

  /// What the context was built for; a different paper / size rebuilds it.
  final String signature;
  PageContext ctx;
  WordSegmenter seg;

  /// Cheap summary of the page's strokes as of our last own change, to notice
  /// undo, redo, erasing and other edits made by someone else.
  int fingerprint = 0;

  final List<TidyDebugWord> recent = [];
}

/// A tidy that is decided but not yet in the document (it waits for the
/// animation, or is applied right away).
class _PendingTidy {
  _PendingTidy({
    required this.state,
    required this.wordId,
    required this.originals,
    required this.locked,
    required this.after,
    required this.debug,
  });

  final _PageState state;
  final String wordId;

  /// The strokes as they are on the page now.
  final List<Stroke> originals;

  /// The same strokes with `wordId` set and marked tidy-locked: what undo
  /// puts back, so an undone word is never tidied again automatically.
  final List<Stroke> locked;

  /// The tidied strokes.
  final List<Stroke> after;
  final TidyDebugWord debug;
}

/// The glue between the editor and the pure tidy engine (`lib/beautify/`).
///
/// * Feeds the [WordSegmenter] from the pen events, with a monotonic clock
///   and an idle timer, and commits words on idle, gap, new line, tool
///   change, page change, tidy toggled off and before saving.
/// * Tidies each committed word and applies it as one undo step ("Tidy"),
///   after a short animation drawn on a page overlay.
/// * Keeps a [PageContext] per page, in step with the document.
class TidySession {
  TidySession({
    required this.controller,
    required this.readSettings,
    required this.nowMs,
    this.config = const TidyConfig(),
    bool Function()? reduceMotion,
    Uuid? uuid,
  })  : _reduceMotion = reduceMotion ?? _systemReduceMotion,
        _uuid = uuid ?? const Uuid();

  final EditorController controller;
  final AppSettings Function() readSettings;

  /// Monotonic milliseconds, shared by every call into the segmenter.
  final int Function() nowMs;
  final TidyConfig config;
  final bool Function() _reduceMotion;
  final Uuid _uuid;

  final Map<String, _PageState> _states = {};
  final Map<String, ValueNotifier<int>> _pageNotifiers = {};

  /// The page whose segmenter holds a pending word (at most one).
  _PageState? _pending;
  Timer? _idleTimer;

  _PendingTidy? _anim;
  TidyAnimation? _animView;
  Timer? _animTimer;

  StreamSubscription<StrokeStartedEvent>? _startedSub;
  StreamSubscription<FinishedStroke>? _finishedSub;
  bool _docAttached = false;
  EditorTool? _lastTool;
  bool _applying = false;
  bool _disposed = false;

  static bool _systemReduceMotion() => WidgetsBinding
      .instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  bool get _enabled => readSettings().tidyEnabled;

  TidySettings get _tidySettings {
    final s = readSettings();
    return TidySettings(
      strength: s.tidyStrength.value,
      slantMode: s.slantMode == SlantMode.upright
          ? TidySlantMode.upright
          : TidySlantMode.keep,
    );
  }

  // ---------------------------------------------------------------------------
  // Wiring

  void install() {
    final ext = controller.extensions;
    _lastTool = controller.tool;
    _startedSub = controller.strokeEvents.started.listen(_onStarted);
    _finishedSub = controller.strokeEvents.finished.listen(_onFinished);
    controller.addListener(_onControllerChanged);
    controller.currentPage.addListener(_onPageScrolled);
    ext.pageOverlays.add(buildOverlay);
    ext.beforeSaveHooks.add(flushForSave);
    _attachDoc();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _idleTimer?.cancel();
    _animTimer?.cancel();
    final ext = controller.extensions;
    ext.pageOverlays.remove(buildOverlay);
    ext.beforeSaveHooks.remove(flushForSave);
    // A running animation is dropped: its word keeps the ink it was drawn
    // with (the controller is closing and saves what is in the document).
    final anim = _anim;
    _anim = null;
    if (anim != null) {
      ext.hiddenStrokeIds.removeAll([for (final s in anim.originals) s.id]);
    }
    unawaited(_startedSub?.cancel());
    unawaited(_finishedSub?.cancel());
    controller.removeListener(_onControllerChanged);
    controller.currentPage.removeListener(_onPageScrolled);
    if (_docAttached) controller.doc.removeListener(_onDocChange);
    for (final n in _pageNotifiers.values) {
      n.dispose();
    }
    _pageNotifiers.clear();
  }

  void _attachDoc() {
    if (_docAttached || !controller.isReady) return;
    _docAttached = true;
    controller.doc.addListener(_onDocChange);
  }

  void _onControllerChanged() {
    if (_disposed) return;
    _attachDoc();
    final tool = controller.tool;
    if (tool != _lastTool) {
      _lastTool = tool;
      _flushPending(CommitReason.toolChange);
    }
  }

  void _onPageScrolled() {
    if (!_disposed) _flushPending(CommitReason.pageChange);
  }

  /// The settings changed (see the integration's listener).
  void onSettingsChanged(AppSettings? previous, AppSettings next) {
    if (_disposed) return;
    if ((previous?.tidyEnabled ?? true) && !next.tidyEnabled) {
      // Tidy turned off: whatever was waiting is left as written.
      _finishAnimation();
      final st = _pending;
      st?.seg.flush(CommitReason.tidyOff);
      _refreshPending(st);
    }
  }

  void _onDocChange(DocChange change) {
    if (_disposed || _applying) return;
    final a = _anim;
    if (a != null && change.pageIds.contains(a.state.pageId)) {
      // Something else changed the page while the word animates (undo of
      // the stroke, an erase). Not in this call: we are inside the command
      // stack, and applying a command here would clear its redo history.
      scheduleMicrotask(_finishAnimation);
    }
  }

  /// Called by `EditorController.close()` before saving.
  void flushForSave() {
    if (_disposed) return;
    _finishAnimation();
    _flushPending(CommitReason.pageChange, animate: false);
  }

  // ---------------------------------------------------------------------------
  // Pen events

  void _onStarted(StrokeStartedEvent e) {
    if (_disposed || !_enabled || !controller.isReady) return;
    // The pen is down again: a running animation jumps to its end.
    _finishAnimation();
    final st = _pending;
    if (st == null) return;
    final CommittedWord? word;
    if (st.pageId != e.pageId) {
      word = st.seg.flush(CommitReason.pageChange);
    } else {
      word = st.seg.onPenDown(tool: e.tool, nowMs: nowMs());
    }
    if (word != null) _commit(st, word, animate: false);
    _refreshPending(st);
  }

  void _onFinished(FinishedStroke e) {
    if (_disposed || !_enabled || !controller.isReady) return;
    final stroke = e.stroke;
    if (!controller.isPageEditable(e.pageId)) return;
    final st = _stateFor(e.pageId);
    if (st == null) return;
    final other = _pending;
    if (other != null && other != st) {
      _flushPending(CommitReason.pageChange);
    }
    _sync(st);
    final out = st.seg.onStrokeEnd(stroke, upMs: nowMs());
    final committed = out.committed;
    if (committed != null) _commit(st, committed, animate: true);
    final mark = out.lateMarkWordId;
    if (mark != null) _assignWordId(st, stroke.id, mark);
    _refreshPending(st);
  }

  void _onIdleTimer() {
    if (_disposed) return;
    final st = _pending;
    if (st == null) return;
    if (!_enabled) {
      st.seg.flush(CommitReason.tidyOff);
      _refreshPending(st);
      return;
    }
    final word = st.seg.onTick(nowMs());
    if (word != null) _commit(st, word, animate: true);
    _refreshPending(st);
  }

  /// Commits whatever is pending now.
  void _flushPending(CommitReason reason, {bool animate = true}) {
    final st = _pending;
    if (st == null) return;
    final word = st.seg.flush(reason);
    if (word != null && _enabled && controller.isReady) {
      _commit(st, word, animate: animate);
    }
    _refreshPending(st);
  }

  /// Tracks which page has a pending word and keeps the idle timer on its
  /// deadline.
  void _refreshPending(_PageState? st) {
    if (st != null && st.seg.hasPending) {
      _pending = st;
      final deadline = st.seg.idleDeadlineMs;
      _idleTimer?.cancel();
      if (deadline != null) {
        final wait = deadline - nowMs();
        _idleTimer = Timer(
            Duration(milliseconds: wait < 1 ? 1 : wait), _onIdleTimer);
      }
    } else {
      if (identical(_pending, st)) _pending = null;
      if (_pending == null) _idleTimer?.cancel();
    }
  }

  // ---------------------------------------------------------------------------
  // Page state

  String _signature(PageMeta p) {
    // PDF pages and unruled paper both use "blank paper" mode.
    final ruled = !p.isPdf && p.paper.hasRuledLines;
    return '${p.width}x${p.height}|${ruled ? '${p.paper.type.name}:${p.paper.spacingPt}' : 'blank'}';
  }

  _PageState? _stateFor(String pageId) {
    final doc = controller.doc;
    final meta = doc.pageMeta(pageId);
    if (meta == null) return null;
    final sig = _signature(meta);
    var st = _states[pageId];
    if (st != null && st.signature != sig) {
      // Different paper or size: the old context describes another page.
      if (identical(_pending, st)) {
        st.seg.reset();
        _refreshPending(st);
      }
      st = null;
    }
    if (st == null) {
      final strokes = doc.page(pageId).strokes;
      final ctx = _newContext(meta, strokes);
      st = _PageState(pageId, sig, ctx, WordSegmenter(page: ctx, config: config))
        ..fingerprint = _fingerprint(strokes);
      _states[pageId] = st;
    }
    return st;
  }

  PageContext _newContext(PageMeta meta, List<Stroke> strokes) {
    final ruled = !meta.isPdf && meta.paper.hasRuledLines;
    final ctx = ruled
        ? PageContext.fromPaper(meta.paper, meta.width, meta.height,
            config: config)
        : PageContext(width: meta.width, height: meta.height, config: config);
    rebuildPageContext(ctx, strokes, config: config);
    return ctx;
  }

  static int _fingerprint(List<Stroke> strokes) {
    var h = strokes.length;
    for (final s in strokes) {
      if (s.wordId == null) continue;
      h = Object.hash(h, s.id, s.wordId, s.tidy.applied);
    }
    return h;
  }

  /// Brings the page context in step with the document if something else
  /// changed the strokes since we last looked: forgets words whose strokes
  /// were erased or whose tidy was undone, and rebuilds the context when a
  /// tidied word appeared that it doesn't know (redo).
  void _sync(_PageState st) {
    final strokes = controller.doc.page(st.pageId).strokes;
    final fp = _fingerprint(strokes);
    if (fp == st.fingerprint) return;
    final byId = {for (final s in strokes) s.id: s};
    for (final w in List.of(st.ctx.words)) {
      final intact = w.strokeIds.every((id) {
        final s = byId[id];
        return s != null && (!w.tidied || s.tidy.applied);
      });
      if (!intact) {
        st.ctx.removeWord(w.wordId);
        st.recent.removeWhere((d) => d.wordId == w.wordId);
      }
    }
    final known = {for (final w in st.ctx.words) w.wordId};
    final unseen = strokes.any(
        (s) => s.wordId != null && s.tidy.applied && !known.contains(s.wordId));
    if (unseen) {
      // The pending word was written on top of the old context; commit it
      // first, then rebuild from what is stored now.
      final pending = st.seg.flush(CommitReason.pageChange);
      if (pending != null && _enabled) _commit(st, pending, animate: false);
      final meta = controller.doc.pageMeta(st.pageId);
      if (meta != null) {
        st.ctx = _newContext(meta, controller.doc.page(st.pageId).strokes);
        st.seg = WordSegmenter(page: st.ctx, config: config);
        st.recent.clear();
      }
      if (identical(_pending, st)) _refreshPending(st);
    }
    st.fingerprint = _fingerprint(controller.doc.page(st.pageId).strokes);
    _notifyPage(st.pageId);
  }

  // ---------------------------------------------------------------------------
  // Tidying a word

  void _commit(_PageState st, CommittedWord word, {required bool animate}) {
    if (!_enabled || !controller.isReady) return;
    if (!controller.isPageEditable(st.pageId)) return;
    // A word still animating lands before the next one starts.
    _finishAnimation();

    // Use the strokes as they are now (the user may have erased or moved
    // some while the word waited).
    final content = controller.doc.page(st.pageId);
    final byId = {for (final s in content.strokes) s.id: s};
    final strokes = <Stroke>[
      for (final s in word.strokes)
        if (byId[s.id] case final cur? when !cur.isHighlighter && cur.shape == null)
          cur,
    ];
    if (strokes.isEmpty) return;

    final wordId = _uuid.v4();
    final watch = kDebugMode ? (Stopwatch()..start()) : null;
    final decision = tidyWordOnPage(
      wordStrokes: strokes,
      page: st.ctx,
      settings: _tidySettings,
      wordId: wordId,
      config: config,
    );
    if (watch != null && watch.elapsedMilliseconds > config.slowWordWarnMs) {
      debugPrint('NeatInk: tidy took ${watch.elapsedMilliseconds} ms for a '
          'word of ${strokes.length} strokes');
    }
    final result = decision.result;
    if (result == null) return; // skipped: the ink stays exactly as written

    final locked = <Stroke>[];
    final after = <Stroke>[];
    for (final s in strokes) {
      locked.add(s.copyWith(
          wordId: wordId, tidy: s.tidy.copyWith(locked: true)));
      final pts = result.newPoints[s.id];
      after.add(pts == null
          ? s.copyWith(wordId: wordId)
          : s.copyWith(
              wordId: wordId,
              points: pts,
              tidy: TidyInfo(applied: true, version: tidyPipelineVersion)));
    }
    final pending = _PendingTidy(
      state: st,
      wordId: wordId,
      originals: strokes,
      locked: locked,
      after: after,
      debug: TidyDebugWord(
        wordId: wordId,
        features: result.features,
        strokeCenters: {
          for (final s in strokes)
            s.id: (x: s.bounds.center.x, y: s.bounds.center.y),
        },
      ),
    );

    if (animate && config.animMs > 0 && !_reduceMotion()) {
      _anim = pending;
      _animView = TidyAnimation(
          before: strokes, after: after, durationMs: config.animMs);
      controller.extensions.hiddenStrokeIds
          .addAll([for (final s in strokes) s.id]);
      controller.invalidatePageRender(st.pageId);
      _notifyPage(st.pageId);
      _animTimer?.cancel();
      _animTimer =
          Timer(Duration(milliseconds: config.animMs), _finishAnimation);
    } else {
      _apply(pending);
    }
  }

  /// Puts a running animation's word into the document right now.
  void _finishAnimation() {
    final a = _anim;
    if (a == null) return;
    _anim = null;
    _animView = null;
    _animTimer?.cancel();
    controller.extensions.hiddenStrokeIds
        .removeAll([for (final s in a.originals) s.id]);
    if (!_disposed && controller.isReady) _apply(a);
    controller.invalidatePageRender(a.state.pageId);
    _notifyPage(a.state.pageId);
  }

  /// Applies a tidy as one undoable step. Strokes that changed or vanished
  /// since the decision (erased, moved) are left out.
  void _apply(_PendingTidy t) {
    final st = t.state;
    final pageId = st.pageId;
    if (!controller.isPageEditable(pageId)) return;
    final content = controller.doc.page(pageId);
    final current = {for (final s in content.strokes) s.id: s};
    final before = <Stroke>[];
    final after = <Stroke>[];
    for (var i = 0; i < t.originals.length; i++) {
      if (identical(current[t.originals[i].id], t.originals[i])) {
        before.add(t.locked[i]);
        after.add(t.after[i]);
      }
    }
    if (before.isEmpty) {
      st.ctx.removeWord(t.wordId);
      return;
    }
    _applying = true;
    try {
      controller.execute(
          ReplaceStrokesCommand(pageId, before, after, label: 'Tidy'));
    } finally {
      _applying = false;
    }
    st.fingerprint = _fingerprint(content.strokes);
    st.recent.add(t.debug);
    while (st.recent.length > _debugWordsPerPage) {
      st.recent.removeAt(0);
    }
    _notifyPage(pageId);
  }

  /// A late mark (i-dot, t-crossing) belongs to an already tidied word: it
  /// only gets that word's id. Its points are not touched and it is not an
  /// undo step of its own (undoing the stroke removes it as before).
  void _assignWordId(_PageState st, String strokeId, String wordId) {
    final content = controller.doc.page(st.pageId);
    final i = content.indexOfStroke(strokeId);
    if (i < 0) return;
    content.strokes[i] = content.strokes[i].copyWith(wordId: wordId);
    content.touch();
    _applying = true;
    try {
      controller.doc.notify(DocChange(pageIds: {st.pageId}));
    } finally {
      _applying = false;
    }
    st.fingerprint = _fingerprint(content.strokes);
  }

  // ---------------------------------------------------------------------------
  // Overlay support

  ValueNotifier<int> pageChanges(String pageId) =>
      _pageNotifiers.putIfAbsent(pageId, () => ValueNotifier(0));

  void _notifyPage(String pageId) {
    if (_disposed) return;
    _pageNotifiers[pageId]?.value++;
  }

  /// The animation running on [pageId], if any.
  TidyAnimation? animationFor(String pageId) {
    final a = _anim;
    if (a == null || a.state.pageId != pageId) return null;
    return _animView;
  }

  /// Recently tidied words of [pageId], for the debug overlay.
  List<TidyDebugWord> debugWordsFor(String pageId) =>
      List.unmodifiable(_states[pageId]?.recent ?? const <TidyDebugWord>[]);

  /// The page overlay builder registered on the editor.
  Widget? buildOverlay(BuildContext context, EditorPageInfo page) =>
      TidyPageOverlay(
        changes: pageChanges(page.pageId),
        animation: () => animationFor(page.pageId),
        words: () => debugWordsFor(page.pageId),
      );
}
