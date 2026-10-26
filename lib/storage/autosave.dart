import 'dart:async';
import 'dart:convert';

import '../document/notebook_doc.dart';
import '../document/notebook_meta.dart';
import 'notebook_repository.dart';

/// Debounced, serialized autosave for one open notebook (pure Dart).
///
/// * [markDirty] collects what changed and (re)starts a [delay] timer; the
///   save runs once the user has paused for [delay].
/// * Saves never overlap: a save requested while one is running waits for
///   it, then writes everything that became dirty in the meantime.
/// * A failed save keeps its changes dirty, reports the error on [errors]
///   and is retried with the next change or [flushNow].
///
/// Typical use in the editor: `doc.addListener(autosave.markDirty)`, call
/// [flushNow] on `AppLifecycleState.paused` and before closing, then
/// [dispose].
class AutosaveController {
  AutosaveController({
    required this._save,
    this.delay = const Duration(milliseconds: 1500),
  });

  /// Quiet time after the last change before saving.
  final Duration delay;

  final Future<void> Function(DocChange dirty) _save;

  // Synchronous, so an error has reached every listener by the time the
  // [flushNow] that hit it completes. Safe here: events are only added at
  // the end of a save, never from inside a listener.
  final StreamController<Object> _errors =
      StreamController<Object>.broadcast(sync: true);

  /// Changes not yet handed to a save.
  DocChange _dirty = DocChange.none;

  /// The batch currently being written, if any.
  DocChange? _saving;

  Timer? _timer;

  /// The last queued save; new saves chain after it so they never overlap.
  Future<void> _tail = Future<void>.value();

  bool _disposed = false;

  /// Errors thrown by failed saves (broadcast, delivered before the failing
  /// save's [flushNow] completes). The changes stay pending.
  Stream<Object> get errors => _errors.stream;

  /// True while some change is not yet safely written (pending, waiting for
  /// the timer, or being written right now).
  bool get hasPendingChanges => !_dirty.isEmpty || _saving != null;

  /// Records [change] and restarts the debounce timer. Ignored after
  /// [dispose].
  void markDirty(DocChange change) {
    if (_disposed || change.isEmpty) return;
    _dirty = _dirty.merge(change);
    _timer?.cancel();
    _timer = Timer(delay, _onTimer);
  }

  /// Saves everything pending now: waits for a save in progress, then
  /// writes what is left. Completes normally even when the save fails (the
  /// error goes to [errors]); check [hasPendingChanges] afterwards to know
  /// whether everything was written.
  Future<void> flushNow() {
    _timer?.cancel();
    _timer = null;
    return _enqueue();
  }

  /// Stops the timer and closes [errors]. Call [flushNow] first; a save
  /// already running still completes.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_errors.close());
  }

  void _onTimer() {
    _timer = null;
    unawaited(_enqueue());
  }

  Future<void> _enqueue() {
    final next = _tail.then((_) => _saveDirty());
    _tail = next;
    return next;
  }

  /// Writes the current dirty set. Never throws, so the chain in [_tail]
  /// stays healthy.
  Future<void> _saveDirty() async {
    if (_dirty.isEmpty) return;
    final batch = _dirty;
    _dirty = DocChange.none;
    _saving = batch;
    try {
      await _save(batch);
    } catch (error) {
      // Keep the changes so the next change or flush writes them again.
      _dirty = batch.merge(_dirty);
      if (!_errors.isClosed) _errors.add(error);
    } finally {
      _saving = null;
    }
  }
}

/// Writes a [NotebookDoc]'s dirty parts through a [NotebookRepository].
///
/// Pass `saver.save` (bound to the doc) as [AutosaveController]'s `save`:
/// `AutosaveController(save: (dirty) => saver.save(doc, dirty))`.
class NotebookSaver {
  /// [touchUpdatedAt]: when the save contains a real edit, set
  /// `doc.meta.updatedAt` to [clock]'s time (and save the metadata), so the
  /// library's "last edited" order follows edits without every command
  /// having to bump it. A real edit is a written page, or a metadata change
  /// other than `lastPageIndex` (pages inserted, deleted or reordered, paper,
  /// title, tags...).
  NotebookSaver(
    this.repository, {
    DateTime Function()? clock,
    this.touchUpdatedAt = true,
  }) : _clock = clock ?? DateTime.now;

  final NotebookRepository repository;
  final bool touchUpdatedAt;
  final DateTime Function() _clock;

  /// Notebook id → [_fingerprint] of the metadata this saver last wrote.
  final Map<String, String> _written = {};

  /// Saves the pages in [dirty] that still exist in `doc.meta.pages` and
  /// have loaded content, then the metadata when `dirty.meta` is set (or an
  /// edit bumped `updatedAt`, see [touchUpdatedAt]).
  ///
  /// Pages are written before the metadata: a crash in between leaves at
  /// most an extra page file (cleaned up by the next metadata save), never
  /// metadata pointing at a page that was not written.
  Future<void> save(NotebookDoc doc, DocChange dirty) async {
    final notebookId = doc.meta.id;
    var wrotePage = false;
    for (final pageId in dirty.pageIds) {
      // Re-read the page list each time: edits continue while we write.
      if (doc.pageMeta(pageId) == null) continue; // Deleted since.
      final content = doc.pages[pageId];
      if (content == null) continue; // Never loaded: nothing to write.
      await repository.savePage(notebookId, pageId, content);
      wrotePage = true;
    }
    if (!wrotePage && !dirty.meta) return;

    final edited = touchUpdatedAt &&
        (wrotePage || await _metaContentChanged(doc.meta));
    if (!edited && !dirty.meta) return;
    if (edited) {
      // Read and replace synchronously so a concurrent command's change to
      // doc.meta is never overwritten.
      doc.meta = doc.meta.copyWith(updatedAt: _clock());
    }
    final meta = doc.meta;
    await repository.saveMeta(meta);
    _written[meta.id] = _fingerprint(meta);
  }

  /// Whether [meta] differs from the stored metadata in anything but
  /// `updatedAt` and `lastPageIndex`. Unknown stored metadata counts as
  /// changed.
  Future<bool> _metaContentChanged(NotebookMeta meta) async {
    var previous = _written[meta.id];
    if (previous == null) {
      try {
        final stored = await repository.loadMeta(meta.id);
        if (stored != null) previous = _fingerprint(stored);
      } catch (_) {
        // Unreadable: treat as changed, the save rewrites it anyway.
      }
    }
    return previous != _fingerprint(meta);
  }

  /// Canonical JSON of [meta] without the fields that change by just
  /// opening or scrolling a notebook.
  static String _fingerprint(NotebookMeta meta) => jsonEncode(meta.toJson()
    ..remove('updatedAt')
    ..remove('lastPageIndex'));
}
