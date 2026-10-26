import 'package:flutter/material.dart';

import '../../../document/notebook_meta.dart';
import '../library_state.dart';
import 'library_menus.dart';

/// The library navigation: All notebooks, Favourites, PDFs, the folder tree
/// and the tags. Shown as a side panel on wide screens and in a drawer on
/// narrow ones ([inDrawer] closes the drawer after a choice).
class LibrarySidePanel extends StatefulWidget {
  const LibrarySidePanel({
    super.key,
    required this.state,
    required this.onOpenFolder,
    required this.onSetFilter,
    required this.onNewFolder,
    required this.onFolderAction,
    this.inDrawer = false,
  });

  final LibraryState state;
  final ValueChanged<String?> onOpenFolder;
  final ValueChanged<LibraryFilter> onSetFilter;

  /// Create a top-level folder.
  final VoidCallback onNewFolder;
  final void Function(Folder folder, FolderAction action) onFolderAction;
  final bool inDrawer;

  @override
  State<LibrarySidePanel> createState() => _LibrarySidePanelState();
}

class _LibrarySidePanelState extends State<LibrarySidePanel> {
  /// Folders whose subfolders are shown.
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _revealCurrentFolder();
  }

  @override
  void didUpdateWidget(LibrarySidePanel old) {
    super.didUpdateWidget(old);
    if (old.state.folderId != widget.state.folderId) _revealCurrentFolder();
  }

  /// Expands the path to the folder being browsed so it is visible.
  void _revealCurrentFolder() {
    _expanded.addAll(widget.state.breadcrumb.map((f) => f.id));
  }

  void _done() {
    if (widget.inDrawer) Scaffold.maybeOf(context)?.closeDrawer();
  }

  void _openFolder(String? id) {
    widget.onOpenFolder(id);
    _done();
  }

  void _setFilter(LibraryFilter filter) {
    widget.onSetFilter(filter);
    _done();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    final folderRows = <Widget>[];
    void addFolders(String? parentId, int depth) {
      for (final f in s.tree.childrenOf(parentId)) {
        final hasChildren = s.tree.hasChildren(f.id);
        final expanded = _expanded.contains(f.id);
        folderRows.add(_FolderRow(
          key: Key('nav-folder-${f.id}'),
          folder: f,
          depth: depth,
          count: s.notebookCountIn(f.id),
          selected: s.isBrowsingFolders && s.folderId == f.id,
          expanded: hasChildren ? expanded : null,
          onTap: () => _openFolder(f.id),
          onToggle: () => setState(() {
            if (!_expanded.remove(f.id)) _expanded.add(f.id);
          }),
          onAction: (a) => widget.onFolderAction(f, a),
        ));
        if (hasChildren && expanded) addFolders(f.id, depth + 1);
      }
    }

    addFolders(null, 0);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (widget.inDrawer)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 16, 12),
            child: Text('NeatInk', style: theme.textTheme.titleLarge),
          ),
        _NavRow(
          key: const Key('nav-all'),
          icon: Icons.library_books_outlined,
          label: 'All notebooks',
          count: s.notebookCountIn(null),
          selected: s.isAtRoot,
          onTap: () => _openFolder(null),
        ),
        _NavRow(
          key: const Key('nav-favorites'),
          icon: Icons.star_outline,
          label: 'Favourites',
          count: s.favoriteCount,
          selected: s.filter == LibraryFilter.favorites,
          onTap: () => _setFilter(LibraryFilter.favorites),
        ),
        _NavRow(
          key: const Key('nav-pdfs'),
          icon: Icons.picture_as_pdf_outlined,
          label: 'PDFs',
          count: s.pdfCount,
          selected: s.filter == LibraryFilter.pdfs,
          onTap: () => _setFilter(LibraryFilter.pdfs),
        ),
        const Divider(indent: 24, endIndent: 24, height: 24),
        _SectionHeader(
          label: 'Folders',
          trailing: IconButton(
            tooltip: 'New folder',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: widget.onNewFolder,
          ),
        ),
        if (folderRows.isEmpty)
          _Hint('No folders yet.', color: muted)
        else
          ...folderRows,
        const Divider(indent: 24, endIndent: 24, height: 24),
        const _SectionHeader(label: 'Tags'),
        if (s.tags.isEmpty)
          _Hint('Tags you add to notebooks show up here.', color: muted)
        else
          for (final tag in s.tags)
            _NavRow(
              key: Key('nav-tag-$tag'),
              icon: Icons.sell_outlined,
              label: tag,
              count: s.tagCount(tag),
              selected: s.filter == LibraryFilter.tag(tag),
              onTap: () => _setFilter(LibraryFilter.tag(tag)),
            ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 4, 12, 4),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 24, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      );
}

/// A rounded navigation row (Material 3 drawer style).
class _NavRow extends StatelessWidget {
  const _NavRow({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _RowShell(
        selected: selected,
        onTap: onTap,
        leading: Icon(icon),
        label: label,
        count: count,
      );
}

/// A folder in the tree, with an expand arrow when it has subfolders and a
/// menu on long-press / right-click.
class _FolderRow extends StatefulWidget {
  const _FolderRow({
    super.key,
    required this.folder,
    required this.depth,
    required this.count,
    required this.selected,
    required this.expanded,
    required this.onTap,
    required this.onToggle,
    required this.onAction,
  });

  final Folder folder;
  final int depth;
  final int count;
  final bool selected;

  /// Null when the folder has no subfolders.
  final bool? expanded;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final ValueChanged<FolderAction> onAction;

  @override
  State<_FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends State<_FolderRow> {
  Offset? _pressPosition;

  Future<void> _showMenu(Offset position) async {
    final action =
        await showMenuAt(context, position, folderMenuEntries(context));
    if (action != null) widget.onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final expanded = widget.expanded;
    return Listener(
      onPointerDown: (e) => _pressPosition = e.position,
      child: GestureDetector(
        onSecondaryTapDown: (d) => _showMenu(d.globalPosition),
        child: _RowShell(
          selected: widget.selected,
          onTap: widget.onTap,
          onLongPress: () {
            final pos = _pressPosition;
            if (pos != null) _showMenu(pos);
          },
          indent: widget.depth * 16.0,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: expanded == null
                    ? null
                    : IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                        tooltip: expanded ? 'Collapse' : 'Expand',
                        onPressed: widget.onToggle,
                        icon: Icon(expanded
                            ? Icons.expand_more
                            : Icons.chevron_right),
                      ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.folder, color: Color(widget.folder.color)),
            ],
          ),
          label: widget.folder.name,
          count: widget.count,
        ),
      ),
    );
  }
}

class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.selected,
    required this.onTap,
    required this.leading,
    required this.label,
    required this.count,
    this.onLongPress,
    this.indent = 0,
  });

  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget leading;
  final String label;
  final int count;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: ListTile(
        selected: selected,
        onTap: onTap,
        onLongPress: onLongPress,
        visualDensity: VisualDensity.compact,
        shape: const StadiumBorder(),
        selectedTileColor: scheme.secondaryContainer,
        selectedColor: scheme.onSecondaryContainer,
        iconColor: scheme.onSurfaceVariant,
        contentPadding:
            EdgeInsetsDirectional.only(start: 16 + indent, end: 16),
        minLeadingWidth: 24,
        horizontalTitleGap: 12,
        leading: leading,
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: count > 0
            ? Text('$count', style: Theme.of(context).textTheme.labelMedium)
            : null,
      ),
    );
  }
}
