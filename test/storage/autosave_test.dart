import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/notebook_doc.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/storage/autosave.dart';
import 'package:neatink/storage/file_notebook_repository.dart';
import 'package:neatink/storage/notebook_repository.dart';

import 'storage_test_support.dart';

const _delay = Duration(milliseconds: 1500);

DocChange pages(Set<String> ids, {bool meta = false}) =>
    DocChange(pageIds: ids, meta: meta);

/// Records save calls; each call can be completed or failed by the test.
class _ScriptedSaver {
  final List<DocChange> calls = [];
  final List<Completer<void>> pending = [];
  int active = 0;
  int maxActive = 0;

  /// When true, saves complete immediately.
  bool autoComplete = true;

  /// Errors thrown by the next saves, in order.
  final List<Object> failures = [];

  Future<void> call(DocChange dirty) async {
    calls.add(dirty);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      if (failures.isNotEmpty) throw failures.removeAt(0);
      if (!autoComplete) {
        final c = Completer<void>();
        pending.add(c);
        await c.future;
      }
    } finally {
      active--;
    }
  }
}

void main() {
  group('AutosaveController', () {
    late FakeTimers timers;
    late _ScriptedSaver saver;
    late AutosaveController autosave;

    setUp(() {
      timers = FakeTimers();
      saver = _ScriptedSaver();
      autosave = timers.run(() => AutosaveController(save: saver.call));
    });

    tearDown(() => autosave.dispose());

    void mark(DocChange c) => timers.run(() => autosave.markDirty(c));

    test('waits 1.5 s after the last change, then saves once', () async {
      mark(pages({'a'}));
      await timers.elapse(const Duration(milliseconds: 1000));
      mark(pages({'b'}, meta: true));
      await timers.elapse(const Duration(milliseconds: 1000));
      expect(saver.calls, isEmpty, reason: 'debounce restarted by 2nd change');
      expect(autosave.hasPendingChanges, isTrue);

      await timers.elapse(const Duration(milliseconds: 500));
      expect(saver.calls, hasLength(1));
      expect(saver.calls.single.pageIds, {'a', 'b'});
      expect(saver.calls.single.meta, isTrue);
      expect(autosave.hasPendingChanges, isFalse);

      await timers.elapse(const Duration(seconds: 10));
      expect(saver.calls, hasLength(1), reason: 'nothing left to save');
    });

    test('uses the default 1.5 s delay', () {
      expect(autosave.delay, _delay);
    });

    test('empty changes are ignored', () async {
      mark(DocChange.none);
      expect(autosave.hasPendingChanges, isFalse);
      expect(timers.pendingTimers, 0);
      await timers.elapse(const Duration(seconds: 5));
      expect(saver.calls, isEmpty);
    });

    test('flushNow saves immediately and cancels the timer', () async {
      mark(pages({'a'}));
      await timers.run(autosave.flushNow);
      expect(saver.calls, hasLength(1));
      expect(timers.pendingTimers, 0);
      await timers.elapse(const Duration(seconds: 5));
      expect(saver.calls, hasLength(1));
    });

    test('flushNow with nothing pending does not call save', () async {
      await timers.run(autosave.flushNow);
      expect(saver.calls, isEmpty);
    });

    test('saves never overlap; flushNow waits for the running save',
        () async {
      saver.autoComplete = false;
      mark(pages({'a'}));
      await timers.elapse(_delay);
      expect(saver.calls, hasLength(1));
      expect(saver.active, 1);

      // A change during the running save, then a flush.
      mark(pages({'b'}));
      var flushed = false;
      final flush = timers.run(autosave.flushNow).then((_) => flushed = true);
      await settle();
      expect(saver.calls, hasLength(1), reason: 'must wait for save #1');
      expect(flushed, isFalse);
      expect(autosave.hasPendingChanges, isTrue);

      saver.pending.removeAt(0).complete();
      await settle();
      expect(saver.calls, hasLength(2));
      expect(saver.calls[1].pageIds, {'b'});
      expect(flushed, isFalse, reason: 'save #2 still running');

      saver.pending.removeAt(0).complete();
      await flush;
      expect(flushed, isTrue);
      expect(saver.maxActive, 1);
      expect(autosave.hasPendingChanges, isFalse);
    });

    test('timer firing during a save queues behind it', () async {
      saver.autoComplete = false;
      mark(pages({'a'}));
      await timers.elapse(_delay);
      mark(pages({'b'}));
      await timers.elapse(_delay);
      expect(saver.calls, hasLength(1));

      saver.pending.removeAt(0).complete();
      await settle();
      expect(saver.calls, hasLength(2));
      saver.pending.removeAt(0).complete();
      await settle();
      expect(saver.maxActive, 1);
    });

    test('a failed save keeps changes, reports, and retries on next change',
        () async {
      final errors = <Object>[];
      final sub = autosave.errors.listen(errors.add);
      addTearDown(sub.cancel);
      saver.failures.add(StateError('disk full'));

      mark(pages({'a'}, meta: true));
      await timers.elapse(_delay);
      expect(saver.calls, hasLength(1));
      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
      expect(autosave.hasPendingChanges, isTrue);

      // No automatic retry without a new change or flush.
      await timers.elapse(const Duration(seconds: 10));
      expect(saver.calls, hasLength(1));

      mark(pages({'b'}));
      await timers.elapse(_delay);
      expect(saver.calls, hasLength(2));
      expect(saver.calls[1].pageIds, {'a', 'b'});
      expect(saver.calls[1].meta, isTrue);
      expect(autosave.hasPendingChanges, isFalse);
    });

    test('flushNow retries after a failure and completes normally', () async {
      final errors = <Object>[];
      final sub = autosave.errors.listen(errors.add);
      addTearDown(sub.cancel);
      saver.failures.add(Exception('io'));

      mark(pages({'a'}));
      await timers.run(autosave.flushNow);
      expect(errors, hasLength(1));
      expect(autosave.hasPendingChanges, isTrue);

      await timers.run(autosave.flushNow);
      expect(saver.calls, hasLength(2));
      expect(saver.calls[1].pageIds, {'a'});
      expect(autosave.hasPendingChanges, isFalse);
    });

    test('changes made while a failing save runs are kept too', () async {
      saver.autoComplete = false;
      mark(pages({'a'}));
      await timers.elapse(_delay);
      mark(pages({'b'}));
      // Fail the running save.
      saver.pending.removeAt(0).completeError(Exception('boom'));
      await settle();
      saver.autoComplete = true;
      await timers.run(autosave.flushNow);
      expect(saver.calls.last.pageIds, {'a', 'b'});
      expect(autosave.hasPendingChanges, isFalse);
    });

    test('dispose cancels the timer and ignores later changes', () async {
      mark(pages({'a'}));
      autosave.dispose();
      expect(timers.pendingTimers, 0);
      mark(pages({'b'}));
      await timers.elapse(const Duration(seconds: 5));
      expect(saver.calls, isEmpty);
    });
  });

  group('NotebookSaver', () {
    test('writes existing loaded dirty pages, then meta', () async {
      final repo = _RecordingRepository();
      final meta = _meta(['p1', 'p2', 'p3']);
      final doc = NotebookDoc(meta, pages: {
        'p1': PageContent(),
        'p2': PageContent(),
        // p3 is not loaded.
      });
      final saver = NotebookSaver(repo, touchUpdatedAt: false);
      await saver.save(
          doc, pages({'p1', 'p2', 'p3', 'deleted'}, meta: true));
      expect(repo.calls, ['page:p1', 'page:p2', 'meta']);
    });

    test('meta only when dirty.meta and touchUpdatedAt is off', () async {
      final repo = _RecordingRepository();
      final doc = NotebookDoc(_meta(['p1']), pages: {'p1': PageContent()});
      final saver = NotebookSaver(repo, touchUpdatedAt: false);
      await saver.save(doc, pages({'p1'}));
      expect(repo.calls, ['page:p1']);
      repo.calls.clear();
      await saver.save(doc, pages({}, meta: true));
      expect(repo.calls, ['meta']);
    });

    test('bumps updatedAt and saves meta when a page was written', () async {
      final repo = _RecordingRepository();
      final doc = NotebookDoc(_meta(['p1']), pages: {'p1': PageContent()});
      final when = DateTime.utc(2027, 1, 2, 3, 4);
      final saver = NotebookSaver(repo, clock: () => when);
      await saver.save(doc, pages({'p1'}));
      expect(repo.calls, ['page:p1', 'meta']);
      expect(doc.meta.updatedAt, when);
      expect(repo.savedMetas.single.updatedAt, when);

      // A metadata-only change (e.g. last page index) is not an edit.
      repo.calls.clear();
      final before = doc.meta.updatedAt;
      doc.meta = doc.meta.copyWith(lastPageIndex: 0);
      await NotebookSaver(repo, clock: () => DateTime.utc(2030))
          .save(doc, pages({}, meta: true));
      expect(doc.meta.updatedAt, before);
    });

    test('a page-list change is an edit; scrolling (lastPageIndex) is not',
        () async {
      final original = _meta(['p1', 'p2']);
      final repo = _RecordingRepository(stored: original);
      final doc = NotebookDoc(original);
      var now = DateTime.utc(2027, 5, 1);
      final saver = NotebookSaver(repo, clock: () => now);

      doc.meta = doc.meta.copyWith(lastPageIndex: 1);
      await saver.save(doc, pages({}, meta: true));
      expect(repo.savedMetas.last.updatedAt, original.updatedAt);
      expect(repo.savedMetas.last.lastPageIndex, 1);

      // Deleting a page changes only the metadata, but it is an edit.
      now = DateTime.utc(2027, 5, 2);
      doc.meta = doc.meta.copyWith(pages: [doc.meta.pages.first]);
      await saver.save(doc, pages({}, meta: true));
      expect(repo.savedMetas.last.updatedAt, now);
      expect(doc.meta.updatedAt, now);

      // Same content again (e.g. a no-op meta notification): no bump.
      now = DateTime.utc(2027, 5, 3);
      await saver.save(doc, pages({}, meta: true));
      expect(repo.savedMetas.last.updatedAt, DateTime.utc(2027, 5, 2));
    });

    test('unknown stored metadata counts as an edit', () async {
      final repo = _RecordingRepository();
      final doc = NotebookDoc(_meta(['p1']));
      final when = DateTime.utc(2028);
      await NotebookSaver(repo, clock: () => when)
          .save(doc, pages({}, meta: true));
      expect(repo.savedMetas.single.updatedAt, when);
    });

    test('a meta change made while pages are written is not lost', () async {
      final repo = _RecordingRepository();
      final doc = NotebookDoc(_meta(['p1']), pages: {'p1': PageContent()});
      // Simulates a command (insert page) running while savePage awaits.
      repo.onSavePage = () => doc.meta = doc.meta.copyWith(
          pages: [...doc.meta.pages, const PageMeta(id: 'p2')]);
      final when = DateTime.utc(2029);
      await NotebookSaver(repo, clock: () => when).save(doc, pages({'p1'}));
      expect(doc.meta.pages.map((p) => p.id), ['p1', 'p2']);
      expect(doc.meta.updatedAt, when);
      expect(repo.savedMetas.single.pages, hasLength(2));
    });

    test('real timers: saves once after the debounce delay', () async {
      final calls = <DocChange>[];
      final autosave = AutosaveController(
        save: (dirty) async => calls.add(dirty),
        delay: const Duration(milliseconds: 40),
      );
      addTearDown(autosave.dispose);
      autosave.markDirty(pages({'a'}));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      autosave.markDirty(pages({'b'}));
      expect(calls, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(calls.single.pageIds, {'a', 'b'});
      expect(autosave.hasPendingChanges, isFalse);
    });

    test('end to end with the file repository', () async {
      final root = await createTempRoot();
      final repo = FileNotebookRepository(root);
      final meta =
          await repo.createNotebook(title: 'Auto', paper: const Paper());
      final pageId = meta.pages.single.id;
      final doc = NotebookDoc(meta, pages: {pageId: PageContent()});
      final autosave = AutosaveController(
        save: (dirty) => NotebookSaver(repo).save(doc, dirty),
      );
      addTearDown(autosave.dispose);
      doc.addListener(autosave.markDirty);

      final page = doc.page(pageId);
      page.strokes.add(penStroke('s1'));
      page.texts.add(const TextItem(
          id: 't1', x: 10, y: 10, width: 100, height: 20, text: 'hello'));
      page.touch();
      doc.notify(DocChange(pageIds: {pageId}));
      expect(autosave.hasPendingChanges, isTrue);

      await autosave.flushNow();
      expect(autosave.hasPendingChanges, isFalse);

      final fresh = FileNotebookRepository(root);
      final loaded = await fresh.loadPage(meta.id, pageId);
      expect(loaded.strokes.single.raw, page.strokes.single.raw);
      expect(loaded.texts.single.text, 'hello');
      final hits = await fresh.search('hello');
      expect(hits.single.kind, SearchMatchKind.text);
    });
  });
}

NotebookMeta _meta(List<String> pageIds) => NotebookMeta(
      id: 'nb1',
      title: 'T',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      pages: [for (final id in pageIds) PageMeta(id: id)],
    );

/// Records the order of save calls; [loadMeta] returns the last saved (or
/// [stored]) metadata. Everything else is unused.
class _RecordingRepository implements NotebookRepository {
  _RecordingRepository({this.stored});

  final List<String> calls = [];
  final List<NotebookMeta> savedMetas = [];

  /// What [loadMeta] returns until a meta is saved.
  NotebookMeta? stored;

  @override
  Future<NotebookMeta?> loadMeta(String notebookId) async =>
      savedMetas.isEmpty ? stored : savedMetas.last;

  /// Runs inside every [savePage] call.
  void Function()? onSavePage;

  @override
  Future<void> savePage(
      String notebookId, String pageId, PageContent content) async {
    calls.add('page:$pageId');
    await Future<void>.value();
    onSavePage?.call();
  }

  @override
  Future<void> saveMeta(NotebookMeta meta) async {
    calls.add('meta');
    savedMetas.add(meta);
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
