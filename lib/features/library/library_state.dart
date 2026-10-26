import 'package:flutter/foundation.dart';

import '../../document/notebook_meta.dart';
import '../settings/app_settings.dart' show LibrarySort;
import 'folder_tree.dart';
import 'tags.dart';

enum LibraryFilterKind { all, favorites, pdfs, tag }

/// Which notebooks the library shows. [LibraryFilter.all] browses the
/// folder tree; the others are flat lists across every folder.
@immutable
class LibraryFilter {
  const LibraryFilter._(this.kind, this.tag);

  /// Browse folders (the current folder is [LibraryState.folderId]).
  static const LibraryFilter all = LibraryFilter._(LibraryFilterKind.all, null);
  static const LibraryFilter favorites =
      LibraryFilter._(LibraryFilterKind.favorites, null);
  static const LibraryFilter pdfs =
      LibraryFilter._(LibraryFilterKind.pdfs, null);

  /// Notebooks carrying [tag] (case-insensitive).
  const LibraryFilter.tag(String this.tag) : kind = LibraryFilterKind.tag;

  final LibraryFilterKind kind;

  /// Set only for [LibraryFilterKind.tag].
  final String? tag;

  bool matches(NotebookMeta n) => switch (kind) {
        LibraryFilterKind.all => true,
        LibraryFilterKind.favorites => n.favorite,
        LibraryFilterKind.pdfs => n.isPdf,
        LibraryFilterKind.tag => hasTag(n, tag!),
      };

  @override
  bool operator ==(Object other) =>
      other is LibraryFilter &&
      other.kind == kind &&
      other.tag?.toLowerCase() == tag?.toLowerCase();

  @override
  int get hashCode => Object.hash(kind, tag?.toLowerCase());

  @override
  String toString() =>
      kind == LibraryFilterKind.tag ? 'LibraryFilter.tag($tag)' : 'LibraryFilter.${kind.name}';
}

/// Everything the library screen shows: the stored notebooks and folders
/// plus the user's current view (folder, filter, sort).
///
/// Immutable; the derived lists are computed once per instance.
class LibraryState {
  LibraryState({
    required this.notebooks,
    required this.library,
    this.folderId,
    this.filter = LibraryFilter.all,
    this.sort = LibrarySort.edited,
    this.thumbnailStamps = const {},
    this.foldersUnavailable = false,
  });

  /// Every notebook, in no particular order.
  final List<NotebookMeta> notebooks;
  final LibraryIndex library;

  /// Folder being browsed (null = library root). Only used with
  /// [LibraryFilter.all].
  final String? folderId;
  final LibraryFilter filter;
  final LibrarySort sort;

  /// Notebook id → `thumb.png` modification time (ms since epoch). A missing
  /// entry means the notebook has no thumbnail yet. The stamp lets the grid
  /// reload a cover after the editor rewrote it.
  final Map<String, int> thumbnailStamps;

  /// `library.json` could not be read. Notebooks are then shown at the top
  /// level and folder changes are refused, so the unreadable file is never
  /// overwritten.
  final bool foldersUnavailable;

  late final FolderTree tree = FolderTree(library);

  /// Distinct tags in use, in name order.
  late final List<String> tags = collectTags(notebooks);

  late final Map<String?, int> _notebooksPerFolder = () {
    final counts = <String?, int>{};
    for (final n in notebooks) {
      final f = folderOf(n);
      counts[f] = (counts[f] ?? 0) + 1;
    }
    return counts;
  }();

  bool get isBrowsingFolders => filter.kind == LibraryFilterKind.all;

  /// Top of the navigation stack: browsing the library root.
  bool get isAtRoot => isBrowsingFolders && folderId == null;

  /// Nothing created yet (first run).
  bool get isLibraryEmpty => notebooks.isEmpty && library.folders.isEmpty;

  Folder? get currentFolder => tree.byId(folderId);

  /// Folders from the top level down to the current folder.
  List<Folder> get breadcrumb => tree.pathTo(folderId);

  /// The folder [n] effectively lives in: null when it is at the top level
  /// or its folder no longer exists (so it never disappears).
  String? folderOf(NotebookMeta n) =>
      tree.contains(n.folderId) ? n.folderId : null;

  /// Folders shown above the notebook grid (only when browsing folders).
  late final List<Folder> visibleFolders = isBrowsingFolders
      ? sortFolders(tree.childrenOf(folderId), sort)
      : const [];

  /// Notebooks shown in the grid, sorted.
  late final List<NotebookMeta> visibleNotebooks = sortNotebooks(
    isBrowsingFolders
        ? notebooks.where((n) => folderOf(n) == folderId)
        : notebooks.where(filter.matches),
    sort,
  );

  /// Notebooks directly inside [folderId] (null = top level).
  int notebookCountIn(String? folderId) => _notebooksPerFolder[folderId] ?? 0;

  int get favoriteCount => notebooks.where((n) => n.favorite).length;
  int get pdfCount => notebooks.where((n) => n.isPdf).length;
  int tagCount(String tag) => notebooks.where((n) => hasTag(n, tag)).length;

  NotebookMeta? notebookById(String id) {
    for (final n in notebooks) {
      if (n.id == id) return n;
    }
    return null;
  }

  LibraryState copyWith({
    List<NotebookMeta>? notebooks,
    LibraryIndex? library,
    String? folderId,
    bool clearFolder = false,
    LibraryFilter? filter,
    LibrarySort? sort,
    Map<String, int>? thumbnailStamps,
    bool? foldersUnavailable,
  }) =>
      LibraryState(
        notebooks: notebooks ?? this.notebooks,
        library: library ?? this.library,
        folderId: clearFolder ? null : (folderId ?? this.folderId),
        filter: filter ?? this.filter,
        sort: sort ?? this.sort,
        thumbnailStamps: thumbnailStamps ?? this.thumbnailStamps,
        foldersUnavailable: foldersUnavailable ?? this.foldersUnavailable,
      );
}

/// Sorts notebooks: most recently edited / created first, or by title
/// (number-aware). Ties fall back to title, then id, so the order is stable.
List<NotebookMeta> sortNotebooks(
    Iterable<NotebookMeta> notebooks, LibrarySort sort) {
  int byTitle(NotebookMeta a, NotebookMeta b) {
    final c = naturalCompare(a.title, b.title);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  final list = notebooks.toList();
  switch (sort) {
    case LibrarySort.edited:
      list.sort((a, b) {
        final c = b.updatedAt.compareTo(a.updatedAt);
        return c != 0 ? c : byTitle(a, b);
      });
    case LibrarySort.created:
      list.sort((a, b) {
        final c = b.createdAt.compareTo(a.createdAt);
        return c != 0 ? c : byTitle(a, b);
      });
    case LibrarySort.title:
      list.sort(byTitle);
  }
  return list;
}

/// Folders sort by name, except for [LibrarySort.created] (newest first).
/// Folders have no edit time, so "last edited" also sorts them by name.
List<Folder> sortFolders(Iterable<Folder> folders, LibrarySort sort) {
  final list = folders.toList();
  if (sort == LibrarySort.created) {
    list.sort((a, b) {
      final c = b.createdAt.compareTo(a.createdAt);
      return c != 0 ? c : compareFolderNames(a, b);
    });
  } else {
    list.sort(compareFolderNames);
  }
  return list;
}
