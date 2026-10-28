import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../document/cover_design.dart';
import '../../document/notebook_meta.dart';
import '../../document/paper.dart';
import '../../storage/notebook_repository.dart';
import '../settings/app_settings.dart';
import '../settings/settings_controller.dart';
import 'folder_tree.dart';
import 'library_palette.dart';
import 'library_state.dart';
import 'pdf_import_service.dart';
import 'tags.dart';

/// The library (home screen) state and every action it offers.
final libraryControllerProvider =
    AsyncNotifierProvider<LibraryController, LibraryState>(
  LibraryController.new,
);

/// Loads notebooks and folders from the [NotebookRepository] and applies the
/// user's changes to them.
///
/// Rules that keep user data safe:
/// * Every change to a notebook's metadata re-reads `notebook.json` first and
///   edits that, never the copy held in [state]. Saving a stale copy could
///   drop pages the editor added since (saveMeta deletes page files that are
///   not in the page list).
/// * Folder changes re-read `library.json` the same way.
/// * Changes run one at a time, in the order they were requested.
/// * Deleting a folder never deletes notebooks: they move to its parent.
class LibraryController extends AsyncNotifier<LibraryState> {
  static const Uuid _uuid = Uuid();

  /// Tail of the queue that serializes changes.
  Future<void> _queue = Future<void>.value();

  NotebookRepository get _repo => ref.read(notebookRepositoryProvider);

  @override
  Future<LibraryState> build() async {
    ref.watch(notebookRepositoryProvider);
    // The sort lives in the settings; follow changes made anywhere (this
    // screen's menu or the settings screen) without reloading.
    ref.listen<LibrarySort>(
      settingsProvider.select((s) => s.librarySort),
      (_, sort) => _emit((s) => s.copyWith(sort: sort)),
    );
    final snapshot = await _loadSnapshot();
    return _applySnapshot(
      LibraryState(
        notebooks: const [],
        library: const LibraryIndex(),
        sort: ref.read(settingsProvider).librarySort,
      ),
      snapshot,
    );
  }

  // -------------------------------------------------------------------
  // Loading
  // -------------------------------------------------------------------

  /// Re-reads everything from storage, keeping the current folder, filter
  /// and sort. Call it after returning from the editor.
  Future<void> refresh() => _serial(() async {
        if (state.value == null) {
          // The first load failed or is still running: start over.
          ref.invalidateSelf();
          return;
        }
        final snapshot = await _loadSnapshot();
        _emit((s) => _applySnapshot(s, snapshot));
      });

  Future<_Snapshot> _loadSnapshot() async {
    final repo = _repo;
    final notebooks = await repo.listNotebooks();
    var library = const LibraryIndex();
    var foldersUnavailable = false;
    try {
      library = await repo.loadLibrary();
    } catch (e, st) {
      // Show the notebooks anyway (at the top level). Folder edits re-read
      // library.json and fail the same way, so the file is never replaced.
      debugPrint('NeatInk: could not load library.json: $e\n$st');
      foldersUnavailable = true;
    }
    return _Snapshot(notebooks, library, foldersUnavailable,
        _thumbnailStamps(notebooks));
  }

  LibraryState _applySnapshot(LibraryState view, _Snapshot snap) {
    final tree = FolderTree(snap.library);
    final keepFolder = tree.contains(view.folderId);
    return view.copyWith(
      notebooks: snap.notebooks,
      library: snap.library,
      foldersUnavailable: snap.foldersUnavailable,
      thumbnailStamps: snap.thumbnailStamps,
      clearFolder: !keepFolder,
    );
  }

  Map<String, int> _thumbnailStamps(Iterable<NotebookMeta> notebooks) => {
        for (final n in notebooks) n.id: ?_thumbnailStamp(n.id),
      };

  /// A value that changes whenever `thumb.png` is rewritten (modification
  /// time and size, since some file systems keep only whole seconds), or
  /// null when there is no usable thumbnail.
  ///
  /// Uses a synchronous stat: it is a metadata lookup of a few microseconds
  /// per notebook, and it keeps loading free of extra async hops.
  int? _thumbnailStamp(String notebookId) {
    try {
      final stat = File(_repo.thumbnailPath(notebookId)).statSync();
      if (stat.type != FileSystemEntityType.file || stat.size == 0) return null;
      return Object.hash(stat.modified.microsecondsSinceEpoch, stat.size);
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------
  // View (folder, filter, sort)
  // -------------------------------------------------------------------

  /// Browses [folderId] (null = library root).
  void openFolder(String? folderId) => _emit((s) => s.copyWith(
        filter: LibraryFilter.all,
        folderId: folderId,
        clearFolder: !s.tree.contains(folderId),
      ));

  /// Shows a flat filtered list ([LibraryFilter.all] returns to the root).
  void setFilter(LibraryFilter filter) =>
      _emit((s) => s.copyWith(filter: filter, clearFolder: true));

  /// One step back: from a subfolder to its parent, from a filter to the
  /// root. Returns false when already at the root.
  bool goBack() {
    final s = state.value;
    if (s == null || s.isAtRoot) return false;
    final folderId = s.folderId;
    if (!s.isBrowsingFolders || folderId == null) {
      setFilter(LibraryFilter.all);
    } else {
      openFolder(s.tree.parentOf(folderId));
    }
    return true;
  }

  /// Changes the sort order (stored in the settings).
  void setSort(LibrarySort sort) {
    ref
        .read(settingsProvider.notifier)
        .update((settings) => settings.copyWith(librarySort: sort));
    _emit((s) => s.copyWith(sort: sort));
  }

  // -------------------------------------------------------------------
  // Notebooks
  // -------------------------------------------------------------------

  /// Creates a blank notebook where the user is looking: in the current
  /// folder, and marked favourite / tagged when a favourites / tag view is
  /// shown, so it appears in that view.
  ///
  /// [cover] (from the cover sheet) wins over [coverColor].
  Future<NotebookMeta> createNotebook({
    required String title,
    required Paper paper,
    int? coverColor,
    CoverChoice? cover,
  }) =>
      _serial(() async {
        final view = state.value;
        final created = await _repo.createNotebook(
          title: title,
          paper: paper,
          folderId: _targetFolder(view),
          coverColor: cover?.color ?? coverColor,
        );
        var meta = await _adoptIntoView(created, view?.filter);
        if (cover != null && cover.design.kind != CoverKind.preview) {
          // Safe to save: the notebook was created a moment ago by this queue.
          meta = meta.copyWith(cover: await _storeCover(meta.id, cover));
          await _repo.saveMeta(meta);
        }
        _upsert(meta);
        return meta;
      });

  /// Imports [pdf] as a new notebook (see [createNotebook] for placement).
  /// Throws the import service's errors (a `PdfImportException` carries a
  /// user-facing message).
  Future<NotebookMeta> importPdf(PickedPdf pdf) => _serial(() async {
        final view = state.value;
        final imported = await ref
            .read(pdfImportServiceProvider)
            .importPdf(_repo, pdf, folderId: _targetFolder(view));
        final meta = await _adoptIntoView(imported, view?.filter);
        _upsert(meta);
        return meta;
      });

  Future<void> renameNotebook(String notebookId, String title) =>
      _serial(() async {
        await _repo.renameNotebook(notebookId, title);
        final meta = await _repo.loadMeta(notebookId);
        if (meta == null) {
          _removeNotebook(notebookId);
        } else {
          _upsert(meta);
        }
      });

  Future<NotebookMeta> duplicateNotebook(String notebookId) =>
      _serial(() async {
        final copy = await _repo.duplicateNotebook(notebookId);
        _upsert(copy);
        return copy;
      });

  /// Permanently deletes the notebook and its files.
  Future<void> deleteNotebook(String notebookId) => _serial(() async {
        await _repo.deleteNotebook(notebookId);
        _removeNotebook(notebookId);
      });

  Future<void> setFavorite(String notebookId, bool favorite) =>
      _editMeta(notebookId, (m) => m.copyWith(favorite: favorite));

  Future<void> toggleFavorite(String notebookId) =>
      _editMeta(notebookId, (m) => m.copyWith(favorite: !m.favorite));

  /// Replaces the notebook's tags (cleaned up with [normalizeTags]).
  Future<void> setTags(String notebookId, List<String> tags) =>
      _editMeta(notebookId, (m) => m.copyWith(tags: normalizeTags(tags)));

  Future<void> setCoverColor(String notebookId, int color) =>
      _editMeta(notebookId, (m) => m.copyWith(coverColor: color));

  /// Sets the cover colour and design; a newly chosen photo is stored in
  /// the notebook's assets first.
  Future<void> setCover(String notebookId, CoverChoice cover) =>
      _serial(() async {
        if (await _repo.loadMeta(notebookId) == null) {
          _removeNotebook(notebookId);
          return;
        }
        final design = await _storeCover(notebookId, cover);
        await _editMetaNow(notebookId,
            (m) => m.copyWith(coverColor: cover.color, cover: design));
      });

  /// The design to save for [cover]: a new photo becomes a notebook asset.
  Future<CoverDesign> _storeCover(String notebookId, CoverChoice cover) async {
    final bytes = cover.photoBytes;
    if (bytes == null) return cover.design;
    final asset =
        await _repo.addAssetBytes(notebookId, bytes, cover.photoExtension);
    return CoverDesign.photo(asset);
  }

  /// Moves a notebook into [folderId] (null = library root). An unknown
  /// folder id moves it to the root rather than hiding it.
  Future<void> moveNotebook(String notebookId, String? folderId) =>
      _serial(() async {
        final library = await _repo.loadLibrary();
        final target = library.folderById(folderId)?.id;
        await _editMetaNow(
          notebookId,
          (m) => target == null
              ? m.copyWith(clearFolder: true)
              : m.copyWith(folderId: target),
        );
      });

  // -------------------------------------------------------------------
  // Folders
  // -------------------------------------------------------------------

  /// Creates a folder inside [parentId] (null = top level).
  Future<Folder> createFolder(String name, {String? parentId, int? color}) =>
      _editLibrary((library) {
        final folder = Folder(
          id: _uuid.v4(),
          name: name,
          parentId: library.folderById(parentId)?.id,
          color: color ?? defaultFolderColor,
          createdAt: ref.read(clockProvider)(),
        );
        return (library.copyWith(folders: [...library.folders, folder]), folder);
      });

  Future<void> renameFolder(String folderId, String name) =>
      _editFolder(folderId, (f) => f.copyWith(name: name));

  Future<void> setFolderColor(String folderId, int color) =>
      _editFolder(folderId, (f) => f.copyWith(color: color));

  /// Moves a folder (with everything in it) under [newParentId]
  /// (null = top level). Returns false, changing nothing, when that would
  /// put the folder inside itself or one of its subfolders.
  Future<bool> moveFolder(String folderId, String? newParentId) =>
      _editLibrary((library) {
        final tree = FolderTree(library);
        if (!tree.canMove(folderId, newParentId)) return (null, false);
        if (tree.parentOf(folderId) == newParentId) return (null, true);
        return (
          _replaceFolder(
            library,
            folderId,
            (f) => newParentId == null
                ? f.copyWith(clearParent: true)
                : f.copyWith(parentId: newParentId),
          ),
          true,
        );
      });

  /// Deletes a folder. Its notebooks and subfolders move to its parent
  /// folder (or the top level); no notebook is ever deleted.
  Future<void> deleteFolder(String folderId) => _serial(() async {
        final library = await _repo.loadLibrary();
        final tree = FolderTree(library);
        if (!tree.contains(folderId)) {
          _emit((s) => _withLibrary(s, library));
          return;
        }
        final parentId = tree.parentOf(folderId);

        // Notebooks move first. Should the app stop half way, each notebook
        // still points at either the parent or the (still existing) folder.
        final moved = <String, NotebookMeta>{};
        for (final n in await _repo.listNotebooks()) {
          if (n.folderId != folderId) continue;
          final m = parentId == null
              ? n.copyWith(clearFolder: true)
              : n.copyWith(folderId: parentId);
          await _repo.saveMeta(m);
          moved[m.id] = m;
        }

        final updated = library.copyWith(folders: [
          for (final f in library.folders)
            if (f.id != folderId)
              f.parentId == folderId
                  ? (parentId == null
                      ? f.copyWith(clearParent: true)
                      : f.copyWith(parentId: parentId))
                  : f,
        ]);
        await _repo.saveLibrary(updated);

        _emit((s) {
          final next = s.copyWith(notebooks: [
            for (final n in s.notebooks) moved[n.id] ?? n,
          ]);
          final viewed = s.folderId == folderId ? parentId : s.folderId;
          return _withLibrary(next, updated)
              .copyWith(folderId: viewed, clearFolder: viewed == null);
        });
      });

  // -------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------

  /// Folder that new notebooks go into for the current view.
  String? _targetFolder(LibraryState? view) =>
      view != null && view.isBrowsingFolders ? view.folderId : null;

  /// Gives a freshly created notebook what the shown filter needs so it is
  /// visible there (favourite, or the filtered tag).
  Future<NotebookMeta> _adoptIntoView(
      NotebookMeta meta, LibraryFilter? filter) async {
    final NotebookMeta updated;
    switch (filter?.kind) {
      case LibraryFilterKind.favorites:
        updated = meta.copyWith(favorite: true);
      case LibraryFilterKind.tag:
        updated = meta.copyWith(tags: normalizeTags([...meta.tags, filter!.tag!]));
      case LibraryFilterKind.all || LibraryFilterKind.pdfs || null:
        return meta;
    }
    // Safe to save: the notebook was created a moment ago by this queue.
    await _repo.saveMeta(updated);
    return updated;
  }

  Future<void> _editMeta(
          String notebookId, NotebookMeta Function(NotebookMeta) change) =>
      _serial(() => _editMetaNow(notebookId, change));

  /// Applies [change] to the stored (not the cached) metadata. A notebook
  /// that no longer exists just disappears from the list.
  Future<void> _editMetaNow(
      String notebookId, NotebookMeta Function(NotebookMeta) change) async {
    final latest = await _repo.loadMeta(notebookId);
    if (latest == null) {
      _removeNotebook(notebookId);
      return;
    }
    final updated = change(latest);
    await _repo.saveMeta(updated);
    _upsert(updated);
  }

  Future<void> _editFolder(String folderId, Folder Function(Folder) change) =>
      _editLibrary((library) => library.folderById(folderId) == null
          ? (null, null)
          : (_replaceFolder(library, folderId, change), null));

  /// Re-reads `library.json`, applies [change] and saves the result. The
  /// change returns the new index (null = nothing to save) and a result.
  Future<T> _editLibrary<T>(
          (LibraryIndex?, T) Function(LibraryIndex latest) change) =>
      _serial(() async {
        final latest = await _repo.loadLibrary();
        final (updated, result) = change(latest);
        if (updated != null) await _repo.saveLibrary(updated);
        _emit((s) => _withLibrary(s, updated ?? latest));
        return result;
      });

  static LibraryIndex _replaceFolder(
          LibraryIndex library, String folderId, Folder Function(Folder) f) =>
      library.copyWith(folders: [
        for (final folder in library.folders)
          folder.id == folderId ? f(folder) : folder,
      ]);

  /// [s] with a new folder index. Leaves a folder view that no longer exists.
  static LibraryState _withLibrary(LibraryState s, LibraryIndex library) {
    final next = s.copyWith(library: library, foldersUnavailable: false);
    return next.tree.contains(s.folderId) ? next : next.copyWith(clearFolder: true);
  }

  void _upsert(NotebookMeta meta) {
    final stamp = _thumbnailStamp(meta.id);
    _emit((s) {
      final notebooks = List.of(s.notebooks);
      final i = notebooks.indexWhere((n) => n.id == meta.id);
      if (i < 0) {
        notebooks.add(meta);
      } else {
        notebooks[i] = meta;
      }
      final stamps = Map.of(s.thumbnailStamps);
      if (stamp == null) {
        stamps.remove(meta.id);
      } else {
        stamps[meta.id] = stamp;
      }
      return s.copyWith(notebooks: notebooks, thumbnailStamps: stamps);
    });
  }

  void _removeNotebook(String notebookId) => _emit((s) => s.copyWith(
        notebooks: [for (final n in s.notebooks) if (n.id != notebookId) n],
        thumbnailStamps: Map.of(s.thumbnailStamps)..remove(notebookId),
      ));

  /// Updates the state when there is data to update (and the provider is
  /// still alive).
  void _emit(LibraryState Function(LibraryState s) change) {
    if (!ref.mounted) return;
    final s = state.value;
    if (s != null) state = AsyncData(change(s));
  }

  /// Runs [action] after every previously requested change has finished.
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then<T>((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

class _Snapshot {
  const _Snapshot(this.notebooks, this.library, this.foldersUnavailable,
      this.thumbnailStamps);
  final List<NotebookMeta> notebooks;
  final LibraryIndex library;
  final bool foldersUnavailable;
  final Map<String, int> thumbnailStamps;
}
