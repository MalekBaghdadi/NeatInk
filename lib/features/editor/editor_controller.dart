import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../document/commands.dart';
import '../../document/notebook_doc.dart';
import '../../document/notebook_meta.dart';
import '../../document/page_content.dart';
import '../../ink/stroke.dart' show PenStyle;
import '../../storage/autosave.dart';
import '../../storage/notebook_repository.dart';
import '../../storage/storage_errors.dart';
import '../settings/app_settings.dart';
import 'canvas/ink_tool_handler.dart';
import 'canvas/input_router.dart';
import 'canvas/live_ink.dart';
import 'canvas/page_painting.dart';
import 'canvas/viewport_controller.dart';
import 'editor_extensions.dart';
import 'editor_tool.dart';
import 'stroke_events.dart';
import 'thumbnail_renderer.dart';
import 'tool_prefs.dart';

/// Where the editor is in its life cycle.
enum EditorStatus {
  /// [EditorController.open] has not been called yet.
  idle,

  /// Loading the notebook's metadata and pages.
  loading,

  /// The notebook is open and editable.
  ready,

  /// Opening failed; see [EditorController.errorMessage].
  failed,
}

/// The state and logic of one open notebook in the editor.
///
/// * Loads the notebook ([open]), keeps it as a [NotebookDoc] and applies
///   every edit through a [CommandStack] ([execute], [undo], [redo]).
/// * Autosaves: every [DocChange] marks the autosave dirty; it writes 1.5 s
///   after the last change, and right away on [saveNow] (app paused) and
///   [close] (editor closing). Saving bumps `updatedAt` when something was
///   edited and records the page being viewed as `lastPageIndex`.
/// * Keeps the per-page render state: one [pageRenderVersion] per page, so
///   only pages whose content changed repaint, the committed-ink
///   [renderCache], and one [LiveInk] per page for the stroke being drawn.
/// * Holds the tool state (current tool, remembered colours / widths /
///   styles in [toolPrefs]) and the [extensions] that later features plug
///   into.
///
/// Listeners are notified for "chrome" changes only (load progress, tool,
/// tool prefs, undo/redo availability, title, page list); drawing and
/// scrolling never notify, so the toolbar doesn't rebuild per frame.
class EditorController extends ChangeNotifier {
  EditorController({
    required this.repository,
    required this.notebookId,
    required ToolPrefsStore toolPrefsStore,
    this.initialPageIndex,
    this.autosaveDelay = const Duration(milliseconds: 1500),
    this.thumbnailWidth = defaultThumbnailWidth,
    this.thumbnailTimeout = const Duration(seconds: 5),
    DateTime Function()? clock,
    Uuid? uuid,
    ViewportController? viewport,
    InputRouter? inputRouter,
  })  : _toolPrefsStore = toolPrefsStore,
        _clock = clock ?? DateTime.now,
        _uuid = uuid ?? const Uuid(),
        viewport = viewport ?? ViewportController(),
        inputRouter = inputRouter ?? InputRouter() {
    _toolPrefs = toolPrefsStore.load();
    commands.onChanged = notifyListeners;
    this.viewport.currentPage.addListener(_rememberCurrentPage);
  }

  final NotebookRepository repository;
  final String notebookId;

  /// Page to show first; defaults to the notebook's `lastPageIndex`.
  final int? initialPageIndex;

  /// Quiet time after the last edit before autosave writes.
  final Duration autosaveDelay;

  /// Width of the library thumbnail in pixels.
  final double thumbnailWidth;

  /// Longest time a thumbnail render may take before it is skipped (the
  /// GPU can be unavailable while the app goes to the background).
  final Duration thumbnailTimeout;

  final ToolPrefsStore _toolPrefsStore;
  final DateTime Function() _clock;
  final Uuid _uuid;

  /// Zoom, pan and page layout of the document view.
  final ViewportController viewport;

  /// Decides what each pointer does (tool, eraser, navigation, palm).
  final InputRouter inputRouter;

  /// Undo / redo history of this notebook.
  final CommandStack commands = CommandStack(capacity: 200);

  /// Pen / highlighter stroke start and finish events (for tidy).
  final StrokeEvents strokeEvents = StrokeEvents();

  /// Plug-in registry for the features built on top of the editor core.
  final EditorExtensions extensions = EditorExtensions();

  /// Cached committed-ink pictures of recently painted pages.
  final PageRenderCache renderCache = PageRenderCache();

  /// The pen and highlighter.
  late final InkToolHandler inkTool = InkToolHandler(this, uuid: _uuid);

  EditorStatus _status = EditorStatus.idle;
  String? _errorMessage;
  int _pagesLoaded = 0;
  int _pagesToLoad = 0;

  NotebookDoc? _doc;
  Set<String> _unreadable = const {};
  NotebookSaver? _saver;
  AutosaveController? _autosave;
  StreamSubscription<Object>? _autosaveErrors;
  final StreamController<Object> _saveErrors =
      StreamController<Object>.broadcast();

  /// Set by every document change, cleared when a save picks it up; a save
  /// with edits stamps `updatedAt`.
  bool _unsavedEdits = false;

  /// The page list last handed to the viewport (identity), to detect page
  /// list changes in [_onDocChange].
  List<PageMeta> _knownPages = const [];
  final ValueNotifier<int> _documentViewVersion = ValueNotifier(0);

  final Map<String, ValueNotifier<int>> _pageVersions = {};
  final Map<String, int> _pageGenerations = {};
  int _globalGeneration = 0;
  final Map<String, LiveInk> _liveInks = {};

  int _lastViewedPage = 0;

  /// What page 1 looked like when its thumbnail was last made (or when the
  /// notebook was opened), see [_thumbnailKey].
  Object? _thumbnailState;
  Future<void> _thumbnailTail = Future<void>.value();

  late ToolPrefs _toolPrefs;
  EditorTool _tool = EditorTool.pen;
  AppSettings _settings = const AppSettings();

  final List<VoidCallback> _disposeCallbacks = [];
  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // Loading

  EditorStatus get status => _status;
  bool get isReady => _status == EditorStatus.ready;

  /// User-facing reason why [open] failed.
  String? get errorMessage => _errorMessage;

  /// Pages loaded so far / pages to load, while [status] is loading.
  int get pagesLoaded => _pagesLoaded;
  int get pagesToLoad => _pagesToLoad;

  /// Load progress in [0, 1].
  double get loadProgress =>
      _pagesToLoad == 0 ? 0 : (_pagesLoaded / _pagesToLoad).clamp(0.0, 1.0);

  /// Loads the notebook and all its pages. Safe to call again after a
  /// failure (retry). Never throws: failures end in [EditorStatus.failed].
  ///
  /// A page whose file can't be read does not stop the notebook from
  /// opening: it is shown empty, can't be edited, and is never saved, so
  /// its file stays untouched on disk ([unreadablePageIds]).
  Future<void> open() async {
    if (_status == EditorStatus.loading || _status == EditorStatus.ready) {
      return;
    }
    _status = EditorStatus.loading;
    _errorMessage = null;
    _pagesLoaded = 0;
    _pagesToLoad = 0;
    notifyListeners();
    try {
      final meta = await repository.loadMeta(notebookId);
      if (_disposed) return;
      if (meta == null) {
        _fail('This notebook no longer exists.');
        return;
      }
      _pagesToLoad = meta.pages.length;
      notifyListeners();

      final pages = <String, PageContent>{};
      final unreadable = <String>{};
      // A few pages at a time: overlaps file reads with JSON decoding
      // without flooding the IO queue on big notebooks.
      const batch = 4;
      for (var i = 0; i < meta.pages.length; i += batch) {
        final chunk = meta.pages.skip(i).take(batch);
        await Future.wait([
          for (final page in chunk)
            _loadPage(page.id).then((content) {
              if (content == null) {
                unreadable.add(page.id);
                pages[page.id] = PageContent();
              } else {
                pages[page.id] = content;
              }
              _pagesLoaded++;
            }),
        ]);
        if (_disposed) return;
        notifyListeners();
      }
      _finishOpen(meta, pages, unreadable);
    } catch (e, st) {
      debugPrint('NeatInk: could not open notebook $notebookId: $e\n$st');
      if (!_disposed) _fail(_describeOpenError(e));
    }
  }

  /// The page's content, or null when its file can't be read.
  Future<PageContent?> _loadPage(String pageId) async {
    try {
      return await repository.loadPage(notebookId, pageId);
    } catch (e, st) {
      debugPrint('NeatInk: page $pageId of $notebookId unreadable: $e\n$st');
      return null;
    }
  }

  void _finishOpen(
    NotebookMeta loaded,
    Map<String, PageContent> pages,
    Set<String> unreadable,
  ) {
    var meta = loaded;
    var repair = DocChange.none;
    if (meta.pages.isEmpty) {
      // A notebook always has at least one page; repair one that has none.
      final page = PageMeta(id: _uuid.v4(), paper: meta.defaultPaper);
      meta = meta.copyWith(pages: [page]);
      pages[page.id] = PageContent();
      repair = DocChange(pageIds: {page.id}, meta: true);
    }
    final doc = NotebookDoc(meta, pages: pages);
    _doc = doc;
    _unreadable = Set.unmodifiable(unreadable);
    _saver = NotebookSaver(repository, clock: _clock, touchUpdatedAt: false);
    final autosave = AutosaveController(save: _save, delay: autosaveDelay);
    _autosave = autosave;
    _autosaveErrors = autosave.errors.listen(_onSaveError);
    doc.addListener(_onDocChange);

    _knownPages = meta.pages;
    viewport.setPages(meta.pages);
    final start = (initialPageIndex ?? meta.lastPageIndex)
        .clamp(0, meta.pages.length - 1);
    _lastViewedPage = start;
    viewport.jumpToPage(start);
    _thumbnailState = _thumbnailKey();

    final last = _toolPrefs.lastTool;
    _tool = isToolAvailable(last) ? last : EditorTool.pen;
    _status = EditorStatus.ready;
    _pagesLoaded = _pagesToLoad;
    handlerFor(_tool)?.onActivated();
    notifyListeners();
    if (!repair.isEmpty) {
      _unsavedEdits = true;
      autosave.markDirty(repair);
    }
  }

  void _fail(String message) {
    _status = EditorStatus.failed;
    _errorMessage = message;
    notifyListeners();
  }

  static String _describeOpenError(Object e) {
    if (e is NotebookNotFoundException) {
      return 'This notebook no longer exists.';
    }
    if (e is CorruptFileException) {
      return "This notebook's data couldn't be read. Nothing was changed on "
          'disk.';
    }
    if (e is FormatException) {
      return "This notebook was saved by a newer version of Mariam's Notes, or its "
          'data is damaged. Nothing was changed on disk.';
    }
    return "The notebook couldn't be opened: $e";
  }

  // ---------------------------------------------------------------------------
  // Document

  /// The open notebook. Only valid once [isReady].
  NotebookDoc get doc {
    final d = _doc;
    if (d == null) {
      throw StateError('The notebook is not open yet (status: $_status)');
    }
    return d;
  }

  /// The notebook's title ('' before it is open).
  String get title => _doc?.meta.title ?? '';

  /// Pages whose files couldn't be read: shown empty, never edited or
  /// saved.
  Set<String> get unreadablePageIds => _unreadable;

  /// Whether tools may change [pageId]: the page exists and was read.
  bool isPageEditable(String pageId) =>
      isReady && !_unreadable.contains(pageId) && doc.pageMeta(pageId) != null;

  /// Runs [command] as one undo step.
  DocChange execute(EditCommand command) => commands.execute(command, doc);

  bool get canUndo => commands.canUndo;
  bool get canRedo => commands.canRedo;
  String? get undoLabel => commands.undoLabel;
  String? get redoLabel => commands.redoLabel;

  DocChange undo() => isReady ? commands.undo(doc) : DocChange.none;
  DocChange redo() => isReady ? commands.redo(doc) : DocChange.none;

  /// Renames the notebook (saved with the next autosave). Blank titles are
  /// ignored.
  void rename(String newTitle) {
    final t = newTitle.trim();
    if (!isReady || t.isEmpty || t == doc.meta.title) return;
    doc.meta = doc.meta.copyWith(title: t);
    doc.notify(const DocChange(meta: true));
  }

  void _onDocChange(DocChange change) {
    _unsavedEdits = true;
    _autosave?.markDirty(change);
    for (final id in change.pageIds) {
      _pageVersions[id]?.value++;
    }
    if (change.meta) {
      final pages = doc.meta.pages;
      if (!identical(pages, _knownPages)) _onPageListChanged(pages);
      notifyListeners();
    }
  }

  void _onPageListChanged(List<PageMeta> pages) {
    _knownPages = pages;
    viewport.setPages(pages);
    final ids = {for (final p in pages) p.id};
    renderCache.retainOnly(ids);
    final active = inkTool.active;
    if (active != null && !ids.contains(active.pageId)) inkTool.cancelActive();
    _documentViewVersion.value++;
  }

  // ---------------------------------------------------------------------------
  // Pages

  int get pageCount => _doc?.meta.pages.length ?? 0;

  /// The page at the centre of the view (0 before the notebook is open).
  int get currentPageIndex {
    final n = pageCount;
    if (n == 0) return 0;
    return viewport.currentPage.value.clamp(0, n - 1);
  }

  /// Notifies when the page at the centre of the view changes.
  ValueListenable<int> get currentPage => viewport.currentPage;

  PageMeta? get currentPageMeta =>
      pageCount == 0 ? null : doc.meta.pages[currentPageIndex];

  /// Notifies when the document view must rebuild its pages: the page
  /// list changed (added, removed, moved, resized, new paper) or
  /// [extensionsChanged] was called.
  Listenable get documentViewChanges => _documentViewVersion;

  /// Bumps whenever [pageId]'s committed content must repaint (content
  /// changed or [invalidatePageRender]).
  ValueListenable<int> pageRenderVersion(String pageId) =>
      _pageVersions.putIfAbsent(pageId, () => ValueNotifier(0));

  /// Forces [pageId]'s committed-content pictures to be re-recorded, e.g.
  /// when an image it shows finished decoding.
  void invalidatePageRender(String pageId) {
    _pageGenerations[pageId] = (_pageGenerations[pageId] ?? 0) + 1;
    _pageVersions[pageId]?.value++;
  }

  /// Changes whenever [pageId]'s pictures must be re-recorded for reasons
  /// other than its content revision.
  int renderGeneration(String pageId) =>
      _globalGeneration + (_pageGenerations[pageId] ?? 0);

  /// The live layer of [pageId].
  LiveInk liveInkFor(String pageId) => _liveInks.putIfAbsent(pageId, LiveInk.new);

  /// Adds a page after the last one, like the page being viewed, and
  /// scrolls to it.
  PageMeta addPageAtEnd() => _insertPage(pageCount, label: 'Add page');

  /// Inserts a page right after the page being viewed and scrolls to it.
  PageMeta insertPageAfterCurrent() =>
      _insertPage(currentPageIndex + 1, label: 'Insert page');

  PageMeta _insertPage(int index, {required String label}) {
    final like = currentPageMeta;
    // New pages use the notebook's paper. They take the viewed page's size
    // (A4 for blank notebooks; the PDF page size in PDF notebooks), but
    // never its PDF background.
    final page = PageMeta(
      id: _uuid.v4(),
      width: like?.width ?? a4WidthPt,
      height: like?.height ?? a4HeightPt,
      paper: doc.meta.defaultPaper,
    );
    execute(InsertPageCommand(index, page, PageContent(), label: label));
    scrollToPage(doc.meta.indexOfPage(page.id));
    return page;
  }

  /// A notebook keeps at least one page.
  bool get canDeletePage => pageCount > 1;

  /// Deletes the page at [index] (undoable). Returns false when it is the
  /// only page.
  bool deletePageAt(int index) {
    if (!canDeletePage || index < 0 || index >= pageCount) return false;
    execute(DeletePageCommand(index));
    return true;
  }

  /// Deletes the page being viewed (see [deletePageAt]).
  bool deleteCurrentPage() => deletePageAt(currentPageIndex);

  /// Scrolls so page [index] is at the top of the view.
  void scrollToPage(int index) => viewport.jumpToPage(index);

  void _rememberCurrentPage() => _lastViewedPage = viewport.currentPage.value;

  // ---------------------------------------------------------------------------
  // Tools

  EditorTool get tool => _tool;

  /// Pen and highlighter are always available; other tools once an
  /// integration registered a handler for them.
  bool isToolAvailable(EditorTool tool) =>
      tool.drawsInk || extensions.toolHandlers.containsKey(tool);

  /// The handler that receives pointers for [tool], if any.
  CanvasToolHandler? handlerFor(EditorTool tool) =>
      tool.drawsInk ? inkTool : extensions.toolHandlers[tool];

  /// The handler of the selected tool.
  CanvasToolHandler? get activeHandler => handlerFor(_tool);

  /// The handler for the pen's eraser end / button (null until the eraser
  /// is integrated; such pointers then do nothing).
  CanvasToolHandler? get eraserHandler =>
      extensions.toolHandlers[EditorTool.eraser];

  /// Selects [tool] (ignored when it isn't available) and remembers it.
  void selectTool(EditorTool tool) {
    if (!isToolAvailable(tool) || tool == _tool) return;
    final old = handlerFor(_tool);
    final next = handlerFor(tool);
    if (!identical(old, next)) old?.onDeactivated();
    _tool = tool;
    if (!identical(old, next)) next?.onActivated();
    updateToolPrefs((p) => p.copyWith(lastTool: tool));
    notifyListeners();
  }

  /// Remembered colours, widths and styles per tool.
  ToolPrefs get toolPrefs => _toolPrefs;

  /// Changes and persists [toolPrefs].
  void updateToolPrefs(ToolPrefs Function(ToolPrefs prefs) change) {
    final next = change(_toolPrefs);
    if (identical(next, _toolPrefs)) return;
    _toolPrefs = next;
    notifyListeners();
    unawaited(_persistToolPrefs(next));
  }

  /// Sets the pen colour. A [custom] colour (from the colour picker) is
  /// also added to the recent custom colours.
  void setPenColor(int argb, {bool custom = false}) => updateToolPrefs((p) {
        final next = p.copyWith(pen: p.pen.copyWith(color: argb));
        return custom ? next.withRecentColor(argb) : next;
      });

  void setPenSize(double size) =>
      updateToolPrefs((p) => p.copyWith(pen: p.pen.copyWith(size: size)));

  void setPenStyle(PenStyle style) =>
      updateToolPrefs((p) => p.copyWith(pen: p.pen.copyWith(style: style)));

  void setHighlighterColor(int argb) => updateToolPrefs(
      (p) => p.copyWith(highlighter: p.highlighter.copyWith(color: argb)));

  void setHighlighterSize(double size) => updateToolPrefs(
      (p) => p.copyWith(highlighter: p.highlighter.copyWith(size: size)));

  void setEraserMode(EraserMode mode) => updateToolPrefs(
      (p) => p.copyWith(eraser: p.eraser.copyWith(mode: mode)));

  void setEraserSize(double size) => updateToolPrefs(
      (p) => p.copyWith(eraser: p.eraser.copyWith(size: size)));

  Future<void> _persistToolPrefs(ToolPrefs prefs) async {
    try {
      await _toolPrefsStore.save(prefs);
    } catch (e) {
      // The in-memory prefs are still right; the next change retries.
      debugPrint('NeatInk: could not save tool preferences: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Settings and extensions

  AppSettings get settings => _settings;

  /// Applies the app settings that affect the editor core (finger drawing,
  /// the pen's eraser button).
  void applySettings(AppSettings settings) {
    _settings = settings;
    inputRouter
      ..drawWithFinger = settings.drawWithFinger
      ..stylusButtonErases = settings.stylusButtonErases;
  }

  /// Call after changing [extensions] while the editor is showing: re-reads
  /// the tool availability, rebuilds the pages and re-records their
  /// pictures.
  void extensionsChanged() {
    _globalGeneration++;
    for (final v in _pageVersions.values) {
      v.value++;
    }
    if (!isToolAvailable(_tool)) _tool = EditorTool.pen;
    _documentViewVersion.value++;
    notifyListeners();
  }

  /// Registers [callback] to run when the controller is disposed (for
  /// integrations that hold subscriptions or timers).
  void addDisposeCallback(VoidCallback callback) =>
      _disposeCallbacks.add(callback);

  // ---------------------------------------------------------------------------
  // Saving

  /// Errors from failed saves (the changes stay pending and are retried).
  Stream<Object> get saveErrors => _saveErrors.stream;

  /// True while some change is not yet written to disk.
  bool get hasUnsavedChanges => _autosave?.hasPendingChanges ?? false;

  /// Writes everything now and refreshes the library thumbnail if page 1
  /// changed. Call when the app goes to the background. Returns true when
  /// nothing is left unsaved.
  Future<bool> saveNow() async {
    final autosave = _autosave;
    if (!isReady || autosave == null) return true;
    _markViewStateDirty();
    await autosave.flushNow();
    await refreshThumbnail();
    return !autosave.hasPendingChanges;
  }

  /// Prepares for leaving the editor: commits any stroke or gesture in
  /// progress and saves everything ([saveNow]). Returns false when some
  /// change could not be written; the editor can stay open and retry.
  Future<bool> close() {
    if (!isReady) return Future.value(true);
    inkTool.commitPending();
    for (final handler in extensions.toolHandlers.values) {
      handler.commitPending();
    }
    for (final hook in List.of(extensions.beforeSaveHooks)) {
      hook();
    }
    return saveNow();
  }

  /// Re-renders the thumbnail when page 1 changed since the last one. Never
  /// throws; a failure only means the library keeps the old thumbnail.
  Future<void> refreshThumbnail() {
    final next = _thumbnailTail.then((_) => _refreshThumbnailOnce());
    _thumbnailTail = next;
    return next;
  }

  Future<void> _refreshThumbnailOnce() async {
    final doc = _doc;
    if (doc == null || doc.meta.pages.isEmpty) return;
    final page = doc.meta.pages.first;
    // An unreadable page shows empty here; keep the old thumbnail instead.
    if (_unreadable.contains(page.id)) return;
    final key = _thumbnailKey();
    if (key == _thumbnailState) return;
    try {
      final png = await renderPageThumbnail(
        PagePaintContext(
          notebookId: notebookId,
          pageId: page.id,
          pageIndex: 0,
          page: page,
          content: doc.page(page.id),
          forThumbnail: true,
        ),
        width: thumbnailWidth,
        imageLayer: extensions.imageLayer,
        textLayer: extensions.textLayer,
        pdfBackground: extensions.thumbnailBackground,
      ).timeout(thumbnailTimeout);
      if (png == null) return;
      await repository.saveThumbnail(notebookId, png);
      _thumbnailState = key;
    } catch (e, st) {
      debugPrint('NeatInk: thumbnail not updated: $e\n$st');
    }
  }

  /// Identifies what page 1 looks like: its metadata instance (paper, size),
  /// its content instance and revision, and its render generation.
  Object? _thumbnailKey() {
    final doc = _doc;
    if (doc == null || doc.meta.pages.isEmpty) return null;
    final page = doc.meta.pages.first;
    final content = doc.pages[page.id];
    return (
      page,
      content == null ? 0 : identityHashCode(content),
      content?.revision ?? -1,
      renderGeneration(page.id),
    );
  }

  /// Saves `lastPageIndex` when the user scrolled to another page.
  void _markViewStateDirty() {
    final doc = _doc;
    if (doc != null && doc.meta.lastPageIndex != _currentPageForSave) {
      _autosave?.markDirty(const DocChange(meta: true));
    }
  }

  int get _currentPageForSave {
    final n = pageCount;
    return n == 0 ? 0 : _lastViewedPage.clamp(0, n - 1);
  }

  /// The autosave's save function: stamps `updatedAt` (when edited) and
  /// `lastPageIndex`, then writes the dirty pages (never unreadable ones)
  /// and the metadata.
  Future<void> _save(DocChange dirty) async {
    final doc = _doc!;
    final saver = _saver!;
    final edited = _unsavedEdits;
    _unsavedEdits = false;
    var meta = doc.meta;
    if (edited) meta = meta.copyWith(updatedAt: _clock());
    final lastPage = _currentPageForSave;
    if (meta.lastPageIndex != lastPage) {
      meta = meta.copyWith(lastPageIndex: lastPage);
    }
    final metaStamped = !identical(meta, doc.meta);
    // copyWith keeps the same page list, so this isn't a page list change.
    doc.meta = meta;
    try {
      await saver.save(
        doc,
        DocChange(
          pageIds: dirty.pageIds.difference(_unreadable),
          meta: dirty.meta || metaStamped,
        ),
      );
    } catch (_) {
      if (edited) _unsavedEdits = true;
      rethrow;
    }
  }

  void _onSaveError(Object error) {
    debugPrint('NeatInk: autosave failed: $error');
    if (!_saveErrors.isClosed) _saveErrors.add(error);
  }

  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final autosave = _autosave;
    if (autosave != null) {
      // Normally close() already flushed; this covers the editor being torn
      // down without it (e.g. the route was removed).
      if (autosave.hasPendingChanges) {
        unawaited(autosave.flushNow().whenComplete(autosave.dispose));
      } else {
        autosave.dispose();
      }
    }
    unawaited(_autosaveErrors?.cancel());
    unawaited(_saveErrors.close());
    _doc?.removeListener(_onDocChange);
    inkTool.dispose();
    for (final handler in extensions.toolHandlers.values) {
      handler.dispose();
    }
    for (final callback in _disposeCallbacks.reversed) {
      callback();
    }
    _disposeCallbacks.clear();
    unawaited(strokeEvents.close());
    renderCache.clear();
    for (final live in _liveInks.values) {
      live.dispose();
    }
    for (final v in _pageVersions.values) {
      v.dispose();
    }
    _documentViewVersion.dispose();
    viewport.currentPage.removeListener(_rememberCurrentPage);
    viewport.dispose();
    super.dispose();
  }
}
