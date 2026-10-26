import 'package:flutter/material.dart';

import '../folder_tree.dart';

/// The destination chosen in [showFolderPicker]. [folderId] null means the
/// library's top level (a null *result* means the dialog was cancelled).
class FolderPick {
  const FolderPick(this.folderId);
  final String? folderId;
}

/// Lets the user choose a destination folder. The current location is shown
/// but can't be chosen; folders in [excluded] (and their subfolders) are
/// hidden, e.g. a folder can't be moved into itself.
Future<FolderPick?> showFolderPicker(
  BuildContext context, {
  required String title,
  required FolderTree tree,
  required String? currentFolderId,
  Set<String> excluded = const {},
}) =>
    showDialog<FolderPick>(
      context: context,
      builder: (context) {
        final entries = tree.flatten(exclude: excluded);
        final scheme = Theme.of(context).colorScheme;

        Widget tile({
          required Widget icon,
          required String label,
          required String? folderId,
          int depth = 0,
        }) {
          final isCurrent = folderId == currentFolderId;
          return ListTile(
            contentPadding:
                EdgeInsetsDirectional.only(start: 16.0 + depth * 20, end: 16),
            leading: icon,
            title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: isCurrent ? const Text('Current location') : null,
            trailing: isCurrent ? Icon(Icons.check, color: scheme.primary) : null,
            enabled: !isCurrent,
            onTap: () => Navigator.of(context).pop(FolderPick(folderId)),
          );
        }

        return AlertDialog(
          title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                tile(
                  icon: const Icon(Icons.home_outlined),
                  label: 'Library (top level)',
                  folderId: null,
                ),
                for (final e in entries)
                  tile(
                    icon: Icon(Icons.folder, color: Color(e.folder.color)),
                    label: e.folder.name,
                    folderId: e.folder.id,
                    depth: e.depth + 1,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
