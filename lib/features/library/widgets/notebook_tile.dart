import 'package:flutter/material.dart';

import '../../../document/notebook_meta.dart';
import '../relative_time.dart';
import 'library_menus.dart';
import 'notebook_cover.dart';

/// Height of the text area under a notebook cover, for a text scale of 1.
/// The grid scales it with the user's text size.
const double notebookTileInfoHeight = 66;

/// One notebook in the library grid: cover, title, favourite star, menu,
/// and "Edited … · N pages".
class NotebookTile extends StatefulWidget {
  const NotebookTile({
    super.key,
    required this.notebook,
    required this.now,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onAction,
    this.thumbnailPath,
    this.thumbnailStamp,
    this.coverPhotoPath,
  });

  final NotebookMeta notebook;

  /// Reference time for "Edited …".
  final DateTime now;
  final VoidCallback onOpen;
  final VoidCallback onToggleFavorite;
  final ValueChanged<NotebookAction> onAction;
  final String? thumbnailPath;
  final int? thumbnailStamp;

  /// File of the cover photo, when the notebook has one.
  final String? coverPhotoPath;

  @override
  State<NotebookTile> createState() => _NotebookTileState();
}

class _NotebookTileState extends State<NotebookTile> {
  Offset? _pressPosition;

  Future<void> _showMenuAt(Offset position) async {
    final action = await showMenuAt(
        context, position, notebookMenuEntries(context, widget.notebook));
    if (action != null) widget.onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nb = widget.notebook;
    final pages = nb.pages.length;
    final subtitle =
        '${formatEdited(nb.updatedAt, widget.now)} · $pages ${pages == 1 ? 'page' : 'pages'}';

    return Semantics(
      container: true,
      label: '${nb.title}${nb.isPdf ? ', PDF' : ''}'
          '${nb.favorite ? ', favourite' : ''}, $subtitle',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onOpen,
        onTapDown: (d) => _pressPosition = d.globalPosition,
        onLongPress: () {
          final pos = _pressPosition;
          if (pos != null) _showMenuAt(pos);
        },
        onSecondaryTapDown: (d) => _showMenuAt(d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ExcludeSemantics(
                  child: NotebookCover(
                    notebook: nb,
                    thumbnailPath: widget.thumbnailPath,
                    thumbnailStamp: widget.thumbnailStamp,
                    coverPhotoPath: widget.coverPhotoPath,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      nb.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    tooltip: nb.favorite
                        ? 'Remove from favourites'
                        : 'Add to favourites',
                    onPressed: widget.onToggleFavorite,
                    icon: nb.favorite
                        ? const Icon(Icons.star, color: Color(0xFFF9A825))
                        : Icon(Icons.star_outline,
                            color: scheme.onSurfaceVariant),
                  ),
                  PopupMenuButton<NotebookAction>(
                    tooltip: 'Notebook options',
                    iconSize: 20,
                    style: const ButtonStyle(
                        visualDensity: VisualDensity.compact),
                    icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
                    onSelected: widget.onAction,
                    itemBuilder: (context) => notebookMenuEntries(context, nb),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
