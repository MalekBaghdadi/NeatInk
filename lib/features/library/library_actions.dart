import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../document/notebook_meta.dart';
import '../../pdf/pdf_import.dart';
import '../settings/settings_controller.dart';
import '../editor/integrations/text_images/image_source.dart';
import 'dialogs/color_dialog.dart';
import 'dialogs/confirm_dialog.dart';
import 'dialogs/cover_picker.dart';
import 'dialogs/folder_picker_dialog.dart';
import 'dialogs/name_dialog.dart';
import 'dialogs/pdf_margins_dialog.dart';
import 'dialogs/new_notebook_sheet.dart';
import 'dialogs/progress_dialog.dart';
import 'dialogs/tags_dialog.dart';
import 'library_controller.dart';
import 'library_naming.dart';
import 'library_navigation.dart';
import 'library_palette.dart';
import 'library_state.dart';
import 'pdf_import_service.dart';
import 'widgets/folder_tile.dart' show folderContentsLabel;
import 'widgets/library_menus.dart';

/// The library's user flows: each one shows the dialogs it needs, calls
/// [LibraryController], navigates, and reports failures in a SnackBar.
///
/// Created by the library screen with its own context and ref. Every step
/// after an `await` checks that the screen is still mounted.
class LibraryActions {
  LibraryActions(this.context, this.ref);

  final BuildContext context;
  final WidgetRef ref;

  /// Set while the editor is open, so a quick double tap can't open the
  /// same notebook twice (two editors would overwrite each other's saves).
  bool _editorOpen = false;

  LibraryController get _controller =>
      ref.read(libraryControllerProvider.notifier);
  LibraryState? get _state => ref.read(libraryControllerProvider).value;
  LibraryNavigator get _nav => ref.read(libraryNavigatorProvider);

  // -------------------------------------------------------------------
  // Navigation
  // -------------------------------------------------------------------

  /// Opens the editor and refreshes the grid when it closes (the title,
  /// page count, edit time and thumbnail may have changed).
  Future<void> openNotebook(String notebookId, {int? pageIndex}) async {
    if (_editorOpen) return;
    _editorOpen = true;
    try {
      await _nav.openEditor(context, notebookId, pageIndex: pageIndex);
    } finally {
      _editorOpen = false;
    }
    if (context.mounted) await refresh();
  }

  /// Search can open notebooks, so refresh when it closes too.
  Future<void> openSearch() async {
    await _nav.openSearch(context);
    if (context.mounted) await refresh();
  }

  /// A restore in Settings can add notebooks and folders, so refresh when
  /// it closes too.
  Future<void> openSettings() async {
    await _nav.openSettings(context);
    if (context.mounted) await refresh();
  }

  /// The Trash; the library shows what was brought back.
  Future<void> openTrash() async {
    await _nav.openTrash(context);
    if (context.mounted) await refresh();
  }

  Future<void> refresh() async {
    await _attempt(_controller.refresh, "Couldn't refresh the library.");
  }

  // -------------------------------------------------------------------
  // Creating things
  // -------------------------------------------------------------------

  /// New notebook sheet → create → open it in the editor.
  Future<void> newNotebook() async {
    final notebooks = _state?.notebooks ?? const <NotebookMeta>[];
    final settings = ref.read(settingsProvider);
    final request = await showNewNotebookSheet(
      context,
      defaultTitle: uniqueName(defaultNotebookTitle(ref.read(clockProvider)()),
          notebooks.map((n) => n.title)),
      defaultPaper: settings.defaultPaper,
      // Rotate through the palette so new notebooks are easy to tell apart.
      defaultCoverColor: NotebookMeta
          .coverColors[notebooks.length % NotebookMeta.coverColors.length],
      pickImage: ref.read(imagePickerProvider),
    );
    if (request == null || !context.mounted) return;
    final meta = await _attempt(
      () => _controller.createNotebook(
        title: request.title,
        paper: request.paper,
        coverColor: request.coverColor,
        cover: request.cover,
      ),
      "Couldn't create the notebook.",
    );
    if (meta != null && context.mounted) await openNotebook(meta.id);
  }

  /// System file picker → import with a progress dialog → open the editor.
  Future<void> importPdf() async {
    final pdf = await _pickPdf();
    if (pdf == null || !context.mounted) return;
    final margins = await showPdfMarginsDialog(context,
        initial: ref.read(settingsProvider).pdfMargins, confirmLabel: 'Import');
    if (margins == null || !context.mounted) {
      await ref.read(pdfImportServiceProvider).discard(pdf);
      return;
    }
    // The next import offers the same margins.
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(pdfMargins: margins));

    final NotebookMeta meta;
    try {
      meta = await runWithProgress(context, 'Importing “${pdf.name}”…',
          () => _controller.importPdf(pdf, margins: margins));
    } on PdfImportException catch (e) {
      _snack(e.message);
      return;
    } catch (e, st) {
      debugPrint('NeatInk: PDF import failed: $e\n$st');
      _snack("Couldn't import this PDF.");
      return;
    }
    if (context.mounted) await openNotebook(meta.id);
  }

  /// The picked PDF, or null when the user cancelled or the picker failed.
  Future<PickedPdf?> _pickPdf() async {
    try {
      return await ref.read(pdfImportServiceProvider).pickPdf();
    } catch (e, st) {
      debugPrint('NeatInk: file picker failed: $e\n$st');
      _snack("Couldn't open the file picker.");
      return null;
    }
  }

  /// Asks for a name and creates a folder in [parentId], or in the folder
  /// being browsed when [inCurrentFolder] is true.
  Future<void> newFolder({String? parentId, bool inCurrentFolder = false}) async {
    final s = _state;
    final parent = inCurrentFolder && s != null && s.isBrowsingFolders
        ? s.folderId
        : parentId;
    final siblings = s?.tree.childrenOf(parent) ?? const [];
    final name = await showNameDialog(
      context,
      title: 'New folder',
      initialValue: uniqueName('New folder', siblings.map((f) => f.name)),
      confirmLabel: 'Create',
    );
    if (name == null || !context.mounted) return;
    await _attempt(() => _controller.createFolder(name, parentId: parent),
        "Couldn't create the folder.");
  }

  // -------------------------------------------------------------------
  // Notebook menu
  // -------------------------------------------------------------------

  Future<void> toggleFavorite(NotebookMeta nb) => _attempt(
      () => _controller.setFavorite(nb.id, !nb.favorite),
      "Couldn't update the notebook.");

  Future<void> onNotebookAction(NotebookMeta nb, NotebookAction action) async {
    switch (action) {
      case NotebookAction.rename:
        final title = await showNameDialog(
          context,
          title: 'Rename notebook',
          initialValue: nb.title,
          label: 'Title',
          confirmLabel: 'Rename',
        );
        if (title == null || title == nb.title || !context.mounted) return;
        await _attempt(() => _controller.renameNotebook(nb.id, title),
            "Couldn't rename the notebook.");

      case NotebookAction.favorite:
        await toggleFavorite(nb);

      case NotebookAction.tags:
        final tags = await showTagsDialog(
          context,
          notebookTitle: nb.title,
          tags: nb.tags,
          suggestions: _state?.tags ?? const [],
        );
        if (tags == null || !context.mounted) return;
        await _attempt(() => _controller.setTags(nb.id, tags),
            "Couldn't save the tags.");

      case NotebookAction.cover:
        final photo = nb.cover.photo;
        final choice = await showCoverPicker(
          context,
          design: nb.cover,
          color: nb.coverColor,
          photoPath: photo == null
              ? null
              : ref.read(notebookRepositoryProvider).assetPath(nb.id, photo),
          pickImage: ref.read(imagePickerProvider),
        );
        if (choice == null || !context.mounted) return;
        await _attempt(() => _controller.setCover(nb.id, choice),
            "Couldn't change the cover.");

      case NotebookAction.move:
        final s = _state;
        if (s == null) return;
        final pick = await showFolderPicker(
          context,
          title: 'Move “${nb.title}” to',
          tree: s.tree,
          currentFolderId: s.folderOf(nb),
        );
        if (pick == null || !context.mounted) return;
        final ok = await _attempt(
            () => _controller.moveNotebook(nb.id, pick.folderId).then((_) => true),
            "Couldn't move the notebook.");
        if (ok == true) {
          _snack('Moved to ${s.tree.byId(pick.folderId)?.name ?? 'Library'}');
        }

      case NotebookAction.duplicate:
        final copy = await _attempt(() => _controller.duplicateNotebook(nb.id),
            "Couldn't duplicate the notebook.");
        if (copy != null) _snack('Created “${copy.title}”');

      case NotebookAction.delete:
        final confirmed = await showConfirmDialog(
          context,
          title: 'Delete “${nb.title}”?',
          message: 'It moves to the Trash (at the bottom of the side menu), '
              'where you can bring it back for '
              '${LibraryController.trashKeep.inDays} days.',
          confirmLabel: 'Move to Trash',
          destructive: true,
        );
        if (!confirmed || !context.mounted) return;
        final ok = await _attempt(
            () => _controller.moveToTrash(nb.id).then((_) => true),
            "Couldn't delete the notebook.");
        if (ok == true) {
          _snack('Moved “${nb.title}” to the Trash',
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => _attempt(() => _controller.restoreFromTrash(nb.id),
                    "Couldn't bring the notebook back."),
              ));
        }
    }
  }

  // -------------------------------------------------------------------
  // Folder menu
  // -------------------------------------------------------------------

  Future<void> onFolderAction(Folder folder, FolderAction action) async {
    final s = _state;
    if (s == null) return;
    switch (action) {
      case FolderAction.rename:
        final name = await showNameDialog(
          context,
          title: 'Rename folder',
          initialValue: folder.name,
          confirmLabel: 'Rename',
        );
        if (name == null || name == folder.name || !context.mounted) return;
        await _attempt(() => _controller.renameFolder(folder.id, name),
            "Couldn't rename the folder.");

      case FolderAction.color:
        final color = await showColorDialog(
          context,
          title: 'Folder colour',
          colors: folderColors,
          selected: folder.color,
        );
        if (color == null || !context.mounted) return;
        await _attempt(() => _controller.setFolderColor(folder.id, color),
            "Couldn't change the folder colour.");

      case FolderAction.move:
        final pick = await showFolderPicker(
          context,
          title: 'Move “${folder.name}” to',
          tree: s.tree,
          currentFolderId: s.tree.parentOf(folder.id),
          excluded: {folder.id},
        );
        if (pick == null || !context.mounted) return;
        final moved = await _attempt(
            () => _controller.moveFolder(folder.id, pick.folderId),
            "Couldn't move the folder.");
        if (moved == false) _snack("A folder can't go inside itself.");

      case FolderAction.delete:
        final parentId = s.tree.parentOf(folder.id);
        final parentName = s.tree.byId(parentId)?.name ?? 'Library';
        final contents = folderContentsLabel(
            s.notebookCountIn(folder.id), s.tree.childrenOf(folder.id).length);
        final message = contents == 'Empty'
            ? 'The folder is empty.'
            : 'Its contents ($contents) will move to “$parentName”. '
                'No notebooks are deleted.';
        final confirmed = await showConfirmDialog(
          context,
          title: 'Delete folder “${folder.name}”?',
          message: message,
          confirmLabel: 'Delete folder',
          destructive: true,
        );
        if (!confirmed || !context.mounted) return;
        await _attempt(() => _controller.deleteFolder(folder.id),
            "Couldn't delete the folder.");
    }
  }

  // -------------------------------------------------------------------

  /// Runs [op]; on failure logs it, shows [failureMessage] and returns null.
  Future<T?> _attempt<T>(Future<T> Function() op, String failureMessage) async {
    try {
      return await op();
    } catch (e, st) {
      debugPrint('NeatInk: $failureMessage $e\n$st');
      _snack(failureMessage);
      return null;
    }
  }

  void _snack(String message, {SnackBarAction? action}) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }
}
