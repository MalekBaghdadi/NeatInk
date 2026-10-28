import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'byte_budget_lru.dart';
import 'pdf_engine.dart';
import 'pdfrx_engine.dart';

export 'pdf_engine.dart' show PdfRenderRegion;
export 'pdf_page_background.dart';

/// A rendered PDF page (or part of one). Each holder owns its own [image]
/// handle: the cache hands out clones, and whoever receives one must call
/// [dispose] when done. The pixels are freed when every handle is gone.
class PdfPageImage {
  PdfPageImage(this.image, this.region);

  final ui.Image image;

  /// Which part of the page, at which resolution, [image] shows.
  final PdfRenderRegion region;

  /// Decoded size in bytes.
  int get byteSize => image.width * image.height * 4;

  /// A new handle to the same pixels, owned by the caller.
  PdfPageImage clone() => PdfPageImage(image.clone(), region);

  void dispose() => image.dispose();
}

/// Render priority. Quick low-resolution previews go before sharp renders,
/// so newly visible pages get *something* on screen first.
enum PdfRenderPriority { preview, sharp }

/// A pending render request. [result] completes with an image the caller
/// owns (and must dispose), or null when the request was cancelled or the
/// render failed.
abstract interface class PdfRenderTicket {
  Future<PdfPageImage?> get result;

  /// The caller no longer needs the image. [result] completes with null
  /// right away; the render itself is dropped once nobody else wants it.
  void cancel();
}

/// Renders PDF pages to images, with
/// * an LRU memory budget ([maxBytes], ~150 MB by default),
/// * de-duplication: identical requests share one render,
/// * stale-request dropping: renders nobody waits for any more are removed
///   from the queue, or cancelled in PDFium if already running,
/// * newest-first scheduling, previews before sharp renders,
/// * one open document per file, closed after [documentIdleTimeout] without
///   users (see [retainDocument]).
///
/// The app uses [shared]; tests create their own with a fake [PdfEngine].
class PdfPageCache {
  PdfPageCache({
    this.engine = const PdfrxEngine(),
    this.maxBytes = defaultMaxBytes,
    this.maxConcurrentRenders = 2,
    this.documentIdleTimeout = const Duration(seconds: 30),
  }) {
    _images = ByteBudgetLru<_ImageKey, PdfPageImage>(
      maxBytes: maxBytes,
      sizeOf: (img) => img.byteSize,
      onEvict: (_, img) => img.dispose(),
    );
  }

  static const int defaultMaxBytes = 150 * 1024 * 1024;

  /// The app-wide cache. Clears itself when the system reports memory
  /// pressure.
  static final PdfPageCache shared = PdfPageCache().._watchMemoryPressure();

  /// Opens documents and renders pages (PDFium in the app, a fake in tests).
  final PdfEngine engine;
  final int maxBytes;

  /// PDFium renders one page at a time, so more parallelism only queues
  /// work; two lets one image decode while the next page renders.
  final int maxConcurrentRenders;
  final Duration documentIdleTimeout;

  late final ByteBudgetLru<_ImageKey, PdfPageImage> _images;
  final Map<_ImageKey, _RenderJob> _jobs = {};
  final List<_RenderJob> _queue = [];
  final Map<String, _DocEntry> _docs = {};
  int _running = 0;
  int _sequence = 0;
  bool _disposed = false;

  /// Bytes of images currently held by the cache itself.
  int get cachedBytes => _images.bytes;

  /// Number of cached images.
  int get cachedImageCount => _images.length;

  /// Renders waiting to start.
  @visibleForTesting
  int get queuedRenderCount => _queue.length;

  // ---------------------------------------------------------------------
  // Documents
  // ---------------------------------------------------------------------

  /// Keeps the document for [pdfPath] open while a page of it is on screen.
  /// Pair every call with [releaseDocument].
  void retainDocument(String pdfPath) {
    final entry = _docs.putIfAbsent(pdfPath, () => _DocEntry(pdfPath));
    entry.refs++;
    entry.idleTimer?.cancel();
    entry.idleTimer = null;
  }

  /// Undoes [retainDocument]. The document closes after
  /// [documentIdleTimeout] once nothing uses it; cached images stay.
  void releaseDocument(String pdfPath) {
    final entry = _docs[pdfPath];
    if (entry == null || entry.refs == 0) return;
    entry.refs--;
    if (entry.refs > 0) return;
    entry.idleTimer?.cancel();
    entry.idleTimer = Timer(documentIdleTimeout, () {
      if (entry.refs == 0 && identical(_docs[pdfPath], entry)) {
        _docs.remove(pdfPath);
        unawaited(entry.close());
      }
    });
  }

  /// Opens (or reuses) the document and holds a reference until the
  /// returned release function runs.
  Future<(PdfEngineDocument, void Function())> _acquire(String path) async {
    retainDocument(path);
    final entry = _docs[path]!;
    var released = false;
    void release() {
      if (released) return;
      released = true;
      releaseDocument(path);
    }

    try {
      final doc = await (entry.document ??= engine.open(path));
      return (doc, release);
    } catch (_) {
      // Forget the failed open so a later request can try again.
      if (identical(_docs[path], entry)) entry.document = null;
      release();
      rethrow;
    }
  }

  // ---------------------------------------------------------------------
  // Words
  // ---------------------------------------------------------------------

  final Map<(String, int), Future<List<PdfWordBox>>> _words = {};

  /// The word boxes of a page (see [PdfEngineDocument.words]), loaded once
  /// per document and page. Empty when the page has no text or reading
  /// failed.
  Future<List<PdfWordBox>> words(String pdfPath, int pageIndex) {
    if (_words.length > 400) _words.clear();
    return _words.putIfAbsent((pdfPath, pageIndex), () async {
      try {
        final (doc, release) = await _acquire(pdfPath);
        try {
          return await doc.words(pageIndex);
        } finally {
          release();
        }
      } catch (e) {
        debugPrint('NeatInk: reading the words of a PDF page failed: $e');
        _words.remove((pdfPath, pageIndex))?.ignore(); // a later call tries again
        return const <PdfWordBox>[];
      }
    });
  }

  // ---------------------------------------------------------------------
  // Images
  // ---------------------------------------------------------------------

  /// The sharpest cached full-page image of the page, as a clone the caller
  /// must dispose. Null when nothing is cached.
  PdfPageImage? largestCached(String pdfPath, int pageIndex) =>
      _pickCached(pdfPath, pageIndex, (best, w) => best == null || w > best);

  /// The smallest cached full-page image at least [minWidth] and at most
  /// [maxWidth] pixels wide, as a clone the caller must dispose.
  PdfPageImage? cachedFullPage(String pdfPath, int pageIndex,
          {required int minWidth, int? maxWidth}) =>
      _pickCached(
        pdfPath,
        pageIndex,
        (best, w) =>
            w >= minWidth &&
            (maxWidth == null || w <= maxWidth) &&
            (best == null || w < best),
      );

  PdfPageImage? _pickCached(String path, int pageIndex,
      bool Function(int? bestWidth, int width) better) {
    _ImageKey? bestKey;
    int? bestWidth;
    for (final e in _images.entries) {
      final k = e.key;
      if (k.path != path || k.pageIndex != pageIndex) continue;
      if (!k.region.isFullPage) continue;
      final w = k.region.fullWidth;
      if (better(bestWidth, w)) {
        bestKey = k;
        bestWidth = w;
      }
    }
    if (bestKey == null) return null;
    return _images.get(bestKey)!.clone();
  }

  /// Requests [region] of page [pageIndex] of [pdfPath].
  ///
  /// A cached image completes the ticket synchronously-fast; otherwise the
  /// render is queued (or joins an identical one already queued/running).
  PdfRenderTicket request(
    String pdfPath,
    int pageIndex,
    PdfRenderRegion region, {
    PdfRenderPriority priority = PdfRenderPriority.sharp,
  }) {
    final key = _ImageKey(pdfPath, pageIndex, region);
    final ticket = _Ticket();
    if (_disposed) {
      ticket._finish(null);
      return ticket;
    }
    final hit = _images.get(key);
    if (hit != null) {
      ticket._finish(hit.clone());
      return ticket;
    }
    var job = _jobs[key];
    // A running render whose waiters all left has been cancelled in PDFium;
    // it will deliver nothing, so start over.
    if (job != null && job.cancel.isCancelled) job = null;
    if (job == null) {
      job = _RenderJob(key, priority);
      _jobs[key] = job;
      _queue.add(job);
    } else if (priority.index < job.priority.index) {
      job.priority = priority;
    }
    job.sequence = ++_sequence; // Newest interest runs first.
    job.waiters.add(ticket);
    ticket._onCancel = () => _cancelWaiter(job!, ticket);
    _pump();
    return ticket;
  }

  void _cancelWaiter(_RenderJob job, _Ticket ticket) {
    job.waiters.remove(ticket);
    if (job.waiters.isNotEmpty) return;
    if (job.started) {
      job.cancel.cancel();
    } else {
      _queue.remove(job);
      _jobs.remove(job.key);
    }
  }

  void _pump() {
    while (_running < maxConcurrentRenders && _queue.isNotEmpty) {
      var next = _queue.first;
      for (final j in _queue) {
        final higher = j.priority.index < next.priority.index;
        final sameButNewer =
            j.priority == next.priority && j.sequence > next.sequence;
        if (higher || sameButNewer) next = j;
      }
      _queue.remove(next);
      unawaited(_run(next));
    }
  }

  Future<void> _run(_RenderJob job) async {
    _running++;
    job.started = true;
    ui.Image? image;
    void Function()? release;
    try {
      final (doc, rel) = await _acquire(job.key.path);
      release = rel;
      if (!job.cancel.isCancelled && !_disposed) {
        image = await doc.render(job.key.pageIndex, job.key.region,
            cancel: job.cancel);
      }
    } catch (e) {
      debugPrint('NeatInk: PDF page render failed '
          '(${job.key.pageIndex + 1}, ${job.key.region}): $e');
    } finally {
      release?.call();
      _running--;
      if (identical(_jobs[job.key], job)) _jobs.remove(job.key);
    }

    if (image != null && _disposed) {
      image.dispose();
      image = null;
    }
    if (image != null) {
      final entry = PdfPageImage(image, job.key.region);
      // Cache even if every waiter left meanwhile: the page is likely to be
      // shown again soon and the work is already done.
      _images.put(job.key, entry);
      for (final w in List.of(job.waiters)) {
        w._finish(entry.clone());
      }
    } else {
      for (final w in List.of(job.waiters)) {
        w._finish(null);
      }
    }
    job.waiters.clear();
    if (!_disposed) _pump();
  }

  /// Drops every cached image and closes the document of [pdfPath], e.g.
  /// when its notebook is deleted.
  Future<void> forgetFile(String pdfPath) async {
    _images.removeWhere((k, _) => k.path == pdfPath);
    final entry = _docs.remove(pdfPath);
    entry?.idleTimer?.cancel();
    await entry?.close();
  }

  /// Drops all cached images (open documents and running renders stay).
  void clearImages() => _images.clear();

  /// Cancels everything, frees all images and closes all documents.
  Future<void> dispose() async {
    _disposed = true;
    for (final job in [..._queue, ..._jobs.values]) {
      for (final w in List.of(job.waiters)) {
        w._finish(null);
      }
      job.waiters.clear();
      job.cancel.cancel();
    }
    _queue.clear();
    _jobs.clear();
    _images.clear();
    final docs = List.of(_docs.values);
    _docs.clear();
    for (final d in docs) {
      d.idleTimer?.cancel();
      await d.close();
    }
  }

  void _watchMemoryPressure() {
    WidgetsFlutterBinding.ensureInitialized()
        .addObserver(_MemoryPressureObserver(this));
  }
}

class _ImageKey {
  const _ImageKey(this.path, this.pageIndex, this.region);

  final String path;
  final int pageIndex;
  final PdfRenderRegion region;

  @override
  bool operator ==(Object other) =>
      other is _ImageKey &&
      other.path == path &&
      other.pageIndex == pageIndex &&
      other.region == region;

  @override
  int get hashCode => Object.hash(path, pageIndex, region);
}

class _RenderJob {
  _RenderJob(this.key, this.priority);

  final _ImageKey key;
  PdfRenderPriority priority;
  int sequence = 0;
  bool started = false;
  final List<_Ticket> waiters = [];
  final PdfRenderCancelToken cancel = PdfRenderCancelToken();
}

class _Ticket implements PdfRenderTicket {
  final Completer<PdfPageImage?> _completer = Completer<PdfPageImage?>();
  void Function()? _onCancel;
  bool _done = false;

  @override
  Future<PdfPageImage?> get result => _completer.future;

  @override
  void cancel() {
    if (_done) return;
    _done = true;
    _completer.complete(null);
    _onCancel?.call();
  }

  /// Delivers [image]; disposes it if the ticket was already cancelled.
  void _finish(PdfPageImage? image) {
    if (_done) {
      image?.dispose();
      return;
    }
    _done = true;
    _completer.complete(image);
  }
}

class _DocEntry {
  _DocEntry(this.path);

  final String path;
  int refs = 0;
  Timer? idleTimer;
  Future<PdfEngineDocument>? document;

  Future<void> close() async {
    final pending = document;
    document = null;
    if (pending == null) return;
    try {
      await (await pending).close();
    } catch (_) {
      // Opening failed, so there is nothing to close.
    }
  }
}

class _MemoryPressureObserver with WidgetsBindingObserver {
  _MemoryPressureObserver(this.cache);

  final PdfPageCache cache;

  @override
  void didHaveMemoryPressure() => cache.clearImages();
}
