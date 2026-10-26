import 'package:flutter/material.dart';

import '../../../document/notebook_meta.dart';
import 'library_menus.dart';

/// Height of a folder tile, for a text scale of 1.
const double folderTileHeight = 68;

/// "3 notebooks · 1 folder", or "Empty".
String folderContentsLabel(int notebooks, int folders) {
  final parts = [
    if (notebooks > 0) '$notebooks ${notebooks == 1 ? 'notebook' : 'notebooks'}',
    if (folders > 0) '$folders ${folders == 1 ? 'folder' : 'folders'}',
  ];
  return parts.isEmpty ? 'Empty' : parts.join(' · ');
}

/// A folder shown above the notebook grid.
class FolderTile extends StatefulWidget {
  const FolderTile({
    super.key,
    required this.folder,
    required this.notebookCount,
    required this.folderCount,
    required this.onOpen,
    required this.onAction,
  });

  final Folder folder;
  final int notebookCount;
  final int folderCount;
  final VoidCallback onOpen;
  final ValueChanged<FolderAction> onAction;

  @override
  State<FolderTile> createState() => _FolderTileState();
}

class _FolderTileState extends State<FolderTile> {
  Offset? _pressPosition;

  Future<void> _showMenuAt(Offset position) async {
    final action =
        await showMenuAt(context, position, folderMenuEntries(context));
    if (action != null) widget.onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final contents =
        folderContentsLabel(widget.notebookCount, widget.folderCount);
    return Card.filled(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpen,
        onTapDown: (d) => _pressPosition = d.globalPosition,
        onLongPress: () {
          final pos = _pressPosition;
          if (pos != null) _showMenuAt(pos);
        },
        onSecondaryTapDown: (d) => _showMenuAt(d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
          child: Row(
            children: [
              Icon(Icons.folder, size: 34, color: Color(widget.folder.color)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      contents,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<FolderAction>(
                tooltip: 'Folder options',
                icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
                onSelected: widget.onAction,
                itemBuilder: folderMenuEntries,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
