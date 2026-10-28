import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../document/notebook_meta.dart';
import '../library_state.dart';
import 'folder_tile.dart';
import 'library_empty_state.dart';
import 'library_menus.dart';
import 'notebook_cover.dart';
import 'notebook_tile.dart';

/// Widest a notebook tile gets before the grid adds a column.
const double maxNotebookTileWidth = 210;

/// Widest a folder tile gets before the folder grid adds a column.
const double maxFolderTileWidth = 320;

/// Callbacks the library content needs from the screen.
class LibraryContentCallbacks {
  const LibraryContentCallbacks({
    required this.onOpenNotebook,
    required this.onToggleFavorite,
    required this.onNotebookAction,
    required this.onOpenFolder,
    required this.onFolderAction,
    required this.onNewNotebook,
    required this.onImportPdf,
    required this.onNewFolder,
    required this.onRefresh,
  });

  final ValueChanged<NotebookMeta> onOpenNotebook;
  final ValueChanged<NotebookMeta> onToggleFavorite;
  final void Function(NotebookMeta notebook, NotebookAction action)
      onNotebookAction;
  final ValueChanged<String> onOpenFolder;
  final void Function(Folder folder, FolderAction action) onFolderAction;
  final VoidCallback onNewNotebook;
  final VoidCallback onImportPdf;

  /// Create a folder in the folder being browsed.
  final VoidCallback onNewFolder;
  final Future<void> Function() onRefresh;
}

/// The library's main area: folder tiles, then the notebook grid, or a
/// friendly empty state. Pull down to reload from storage.
class LibraryContent extends StatelessWidget {
  const LibraryContent({
    super.key,
    required this.state,
    required this.now,
    required this.thumbnailPathFor,
    required this.callbacks,
    this.assetPathFor,
  });

  final LibraryState state;

  /// Reference time for the tiles' "Edited …" labels.
  final DateTime now;

  /// Path of a notebook's `thumb.png`.
  final String Function(String notebookId) thumbnailPathFor;

  /// Path of a notebook's asset (the cover photo); null: no photos shown.
  final String Function(String notebookId, String asset)? assetPathFor;
  final LibraryContentCallbacks callbacks;

  static const EdgeInsets _padding = EdgeInsets.fromLTRB(24, 12, 24, 0);

  @override
  Widget build(BuildContext context) {
    final s = state;
    final folders = s.visibleFolders;
    final notebooks = s.visibleNotebooks;
    final empty = folders.isEmpty && notebooks.isEmpty
        ? _emptyState(context)
        : null;

    return RefreshIndicator(
      onRefresh: callbacks.onRefresh,
      child: CustomScrollView(
        // Pull-to-refresh must work even when the content is short.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (s.foldersUnavailable)
            const SliverPadding(
              padding: _padding,
              sliver: SliverToBoxAdapter(child: _FoldersUnavailableNotice()),
            ),
          if (folders.isNotEmpty) ...[
            if (notebooks.isNotEmpty) const _SectionLabel('Folders'),
            SliverPadding(
              padding: _padding,
              sliver: _folderGrid(context, folders),
            ),
          ],
          if (notebooks.isNotEmpty) ...[
            if (folders.isNotEmpty) const _SectionLabel('Notebooks'),
            SliverPadding(
              padding: _padding,
              sliver: _notebookGrid(notebooks),
            ),
          ],
          if (empty != null)
            SliverFillRemaining(hasScrollBody: false, child: empty)
          else
            // Room so the last row can scroll clear of the "New" button.
            const SliverToBoxAdapter(child: SizedBox(height: 112)),
        ],
      ),
    );
  }

  Widget _folderGrid(BuildContext context, List<Folder> folders) {
    final height = MediaQuery.textScalerOf(context).scale(folderTileHeight);
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxFolderTileWidth,
        mainAxisExtent: height,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      delegate: SliverChildBuilderDelegate(
        childCount: folders.length,
        (context, i) {
          final f = folders[i];
          return FolderTile(
            key: ValueKey('folder-${f.id}'),
            folder: f,
            notebookCount: state.notebookCountIn(f.id),
            folderCount: state.tree.childrenOf(f.id).length,
            onOpen: () => callbacks.onOpenFolder(f.id),
            onAction: (a) => callbacks.onFolderAction(f, a),
          );
        },
      ),
    );
  }

  Widget _notebookGrid(List<NotebookMeta> notebooks) => SliverLayoutBuilder(
        builder: (context, constraints) {
          const spacing = 16.0;
          final width = constraints.crossAxisExtent;
          final columns =
              math.max(2, ((width + spacing) / (maxNotebookTileWidth + spacing)).ceil());
          final tileWidth = (width - spacing * (columns - 1)) / columns;
          // The tile pads its content by 4 on every side; the cover keeps
          // its aspect ratio and the text block scales with the text size.
          final coverHeight = (tileWidth - 8) / notebookCoverAspect;
          final info =
              MediaQuery.textScalerOf(context).scale(notebookTileInfoHeight);
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: spacing,
              mainAxisSpacing: 12,
              mainAxisExtent: coverHeight + 8 + 4 + info,
            ),
            delegate: SliverChildBuilderDelegate(
              childCount: notebooks.length,
              (context, i) {
                final nb = notebooks[i];
                return NotebookTile(
                  key: ValueKey('notebook-${nb.id}'),
                  notebook: nb,
                  now: now,
                  thumbnailPath: thumbnailPathFor(nb.id),
                  thumbnailStamp: state.thumbnailStamps[nb.id],
                  coverPhotoPath: nb.cover.photo == null ? null : assetPathFor?.call(nb.id, nb.cover.photo!),
                  onOpen: () => callbacks.onOpenNotebook(nb),
                  onToggleFavorite: () => callbacks.onToggleFavorite(nb),
                  onAction: (a) => callbacks.onNotebookAction(nb, a),
                );
              },
            ),
          );
        },
      );

  /// What to show when the current view has nothing in it.
  Widget? _emptyState(BuildContext context) {
    final s = state;
    final newNotebook = FilledButton.icon(
      onPressed: callbacks.onNewNotebook,
      icon: const Icon(Icons.note_add_outlined),
      label: const Text('New notebook'),
    );
    final importPdf = OutlinedButton.icon(
      onPressed: callbacks.onImportPdf,
      icon: const Icon(Icons.picture_as_pdf_outlined),
      label: const Text('Import a PDF'),
    );

    switch (s.filter.kind) {
      case LibraryFilterKind.all:
        if (s.folderId == null) {
          return LibraryEmptyState(
            key: const Key('empty-first-run'),
            icon: Icons.auto_stories_outlined,
            title: 'Create your first notebook',
            message: 'Write with your pen on blank, lined or grid pages, '
                'or import a PDF and write on it.',
            actions: [newNotebook, importPdf],
          );
        }
        return LibraryEmptyState(
          key: const Key('empty-folder'),
          icon: Icons.folder_open_outlined,
          title: 'This folder is empty',
          message: 'Create a notebook here, or move one in with '
              '“Move to folder…” in its menu.',
          actions: [
            newNotebook,
            OutlinedButton.icon(
              onPressed: callbacks.onNewFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('New folder'),
            ),
          ],
        );
      case LibraryFilterKind.favorites:
        return const LibraryEmptyState(
          key: Key('empty-favorites'),
          icon: Icons.star_outline,
          title: 'No favourites yet',
          message: 'Tap the star on a notebook to keep it here for quick '
              'access.',
        );
      case LibraryFilterKind.pdfs:
        return LibraryEmptyState(
          key: const Key('empty-pdfs'),
          icon: Icons.picture_as_pdf_outlined,
          title: 'No PDFs yet',
          message: 'Import a PDF to write on its pages, then export it with '
              'your notes.',
          actions: [importPdf],
        );
      case LibraryFilterKind.tag:
        return LibraryEmptyState(
          key: const Key('empty-tag'),
          icon: Icons.sell_outlined,
          title: 'No notebooks tagged “${s.filter.tag}”',
          message: 'Add this tag to a notebook with “Tags…” in its menu.',
        );
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(28, 16, 24, 0),
      sliver: SliverToBoxAdapter(
        child: Text(
          label,
          style: theme.textTheme.titleSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Shown when `library.json` could not be read: notebooks are listed at the
/// top level and folder changes are blocked until the file is readable.
class _FoldersUnavailableNotice extends StatelessWidget {
  const _FoldersUnavailableNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.folder_off_outlined, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Your folders couldn't be loaded, so all notebooks are shown "
                'here. Nothing was deleted. Pull down to try again.',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
