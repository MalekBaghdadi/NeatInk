import 'package:flutter/material.dart';

import '../../../document/notebook_meta.dart';

/// Actions in a notebook's menu (tile menu button or long-press).
enum NotebookAction { rename, favorite, tags, cover, move, duplicate, delete }

/// Actions in a folder's menu.
enum FolderAction { rename, color, move, delete }

List<PopupMenuEntry<NotebookAction>> notebookMenuEntries(
    BuildContext context, NotebookMeta notebook) {
  final error = Theme.of(context).colorScheme.error;
  return [
    _item(NotebookAction.rename, Icons.edit_outlined, 'Rename'),
    notebook.favorite
        ? _item(NotebookAction.favorite, Icons.star, 'Remove from favourites')
        : _item(NotebookAction.favorite, Icons.star_outline, 'Add to favourites'),
    _item(NotebookAction.tags, Icons.sell_outlined, 'Tags…'),
    _item(NotebookAction.cover, Icons.palette_outlined, 'Cover colour…'),
    _item(NotebookAction.move, Icons.drive_file_move_outlined,
        'Move to folder…'),
    _item(NotebookAction.duplicate, Icons.copy_all_outlined, 'Duplicate'),
    const PopupMenuDivider(),
    _item(NotebookAction.delete, Icons.delete_outline, 'Delete', color: error),
  ];
}

List<PopupMenuEntry<FolderAction>> folderMenuEntries(BuildContext context) {
  final error = Theme.of(context).colorScheme.error;
  return [
    _item(FolderAction.rename, Icons.edit_outlined, 'Rename'),
    _item(FolderAction.color, Icons.palette_outlined, 'Colour…'),
    _item(FolderAction.move, Icons.drive_file_move_outlined, 'Move to…'),
    const PopupMenuDivider(),
    _item(FolderAction.delete, Icons.delete_outline, 'Delete folder',
        color: error),
  ];
}

PopupMenuItem<T> _item<T>(T value, IconData icon, String label,
        {Color? color}) =>
    PopupMenuItem<T>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(label, style: color == null ? null : TextStyle(color: color)),
        ],
      ),
    );

/// Shows a popup menu at [globalPosition] (where the user long-pressed or
/// right-clicked).
Future<T?> showMenuAt<T>(
  BuildContext context,
  Offset globalPosition,
  List<PopupMenuEntry<T>> items,
) {
  final overlay =
      Overlay.of(context).context.findRenderObject()! as RenderBox;
  final local = overlay.globalToLocal(globalPosition);
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(
        local & const Size(1, 1), Offset.zero & overlay.size),
    items: items,
  );
}
