import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../settings/app_settings.dart' show LibrarySort;
import 'library_actions.dart';
import 'library_controller.dart';
import 'library_state.dart';
import 'widgets/library_content.dart';
import 'widgets/library_empty_state.dart';
import 'widgets/library_side_panel.dart';
import 'widgets/library_title.dart';

/// Screen width from which the navigation sits in a side panel instead of
/// a drawer. Low enough that a tablet in portrait gets the panel too.
const double librarySidePanelBreakpoint = 720;

/// Width of the side panel on wide screens.
const double librarySidePanelWidth = 280;

/// Menu labels for the sort options.
String librarySortLabel(LibrarySort sort) => switch (sort) {
      LibrarySort.edited => 'Last edited',
      LibrarySort.created => 'Date created',
      LibrarySort.title => 'Title',
    };

/// The home screen: notebooks, folders, tags and favourites.
///
/// Wide screens show the navigation (All notebooks, Favourites, PDFs,
/// folders, tags) in a side panel; narrow ones in a drawer. The top bar has
/// the folder breadcrumb, search, sort and settings; the "New" button
/// creates notebooks and folders and imports PDFs.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  late final LibraryActions _actions = LibraryActions(context, ref);

  LibraryController get _controller =>
      ref.read(libraryControllerProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(libraryControllerProvider);
    final s = async.value;
    if (s == null) return _buildNotReady(async);

    final wide =
        MediaQuery.sizeOf(context).width >= librarySidePanelBreakpoint;
    final repo = ref.watch(notebookRepositoryProvider);
    final now = ref.watch(clockProvider)();
    final scheme = Theme.of(context).colorScheme;

    Widget panel({required bool inDrawer}) => LibrarySidePanel(
          state: s,
          inDrawer: inDrawer,
          onOpenFolder: _controller.openFolder,
          onSetFilter: _controller.setFilter,
          onNewFolder: () => _actions.newFolder(),
          onFolderAction: _actions.onFolderAction,
        );

    final content = LibraryContent(
      state: s,
      now: now,
      thumbnailPathFor: repo.thumbnailPath,
      callbacks: LibraryContentCallbacks(
        onOpenNotebook: (nb) => _actions.openNotebook(nb.id),
        onToggleFavorite: _actions.toggleFavorite,
        onNotebookAction: _actions.onNotebookAction,
        onOpenFolder: _controller.openFolder,
        onFolderAction: _actions.onFolderAction,
        onNewNotebook: _actions.newNotebook,
        onImportPdf: _actions.importPdf,
        onNewFolder: () => _actions.newFolder(inCurrentFolder: true),
        onRefresh: _actions.refresh,
      ),
    );

    // System back walks up the folder path (or out of a filter) before it
    // leaves the app.
    return PopScope(
      canPop: s.isAtRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _controller.goBack();
      },
      child: Scaffold(
        drawer: wide ? null : Drawer(child: SafeArea(child: panel(inDrawer: true))),
        appBar: AppBar(
          title: LibraryTitle(state: s, onOpenFolder: _controller.openFolder),
          actions: [
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search),
              onPressed: _actions.openSearch,
            ),
            _SortButton(sort: s.sort, onSelected: _controller.setSort),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: _actions.openSettings,
            ),
            const SizedBox(width: 8),
          ],
        ),
        floatingActionButton: _NewButton(
          onNewNotebook: _actions.newNotebook,
          onImportPdf: _actions.importPdf,
          onNewFolder: () => _actions.newFolder(inCurrentFolder: true),
        ),
        body: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: librarySidePanelWidth,
                    child: ColoredBox(
                      color: scheme.surfaceContainerLow,
                      child: panel(inDrawer: false),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              )
            : content,
      ),
    );
  }

  /// First load still running, or it failed.
  Widget _buildNotReady(AsyncValue<LibraryState> async) => Scaffold(
        appBar: AppBar(
          title: const Text('Library'),
          actions: [
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: _actions.openSettings,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: async.hasError
            ? LibraryEmptyState(
                key: const Key('library-load-error'),
                icon: Icons.error_outline,
                title: "Couldn't open your library",
                message: 'Your notebooks were not changed. Try again, or '
                    'restart the app if this keeps happening.',
                actions: [
                  FilledButton.icon(
                    onPressed: () => ref.invalidate(libraryControllerProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              )
            : const Center(child: CircularProgressIndicator()),
      );
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onSelected});

  final LibrarySort sort;
  final ValueChanged<LibrarySort> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<LibrarySort>(
        tooltip: 'Sort',
        icon: const Icon(Icons.sort),
        initialValue: sort,
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final option in LibrarySort.values)
            CheckedPopupMenuItem<LibrarySort>(
              value: option,
              checked: option == sort,
              child: Text(librarySortLabel(option)),
            ),
        ],
      );
}

/// The "New" floating button and its menu.
class _NewButton extends StatelessWidget {
  const _NewButton({
    required this.onNewNotebook,
    required this.onImportPdf,
    required this.onNewFolder,
  });

  final VoidCallback onNewNotebook;
  final VoidCallback onImportPdf;
  final VoidCallback onNewFolder;

  @override
  Widget build(BuildContext context) => MenuAnchor(
        menuChildren: [
          MenuItemButton(
            leadingIcon: const Icon(Icons.note_add_outlined),
            onPressed: onNewNotebook,
            child: const Text('New notebook'),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: onImportPdf,
            child: const Text('Import PDF'),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.create_new_folder_outlined),
            onPressed: onNewFolder,
            child: const Text('New folder'),
          ),
        ],
        builder: (context, menu, _) => FloatingActionButton.extended(
          tooltip: 'Create',
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          icon: const Icon(Icons.add),
          label: const Text('New'),
        ),
      );
}
