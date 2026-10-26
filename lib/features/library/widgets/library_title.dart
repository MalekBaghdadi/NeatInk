import 'package:flutter/material.dart';

import '../library_state.dart';

/// App bar title: the folder breadcrumb ("Library › School › Physics")
/// while browsing folders, or the name of the active filter.
class LibraryTitle extends StatelessWidget {
  const LibraryTitle({
    super.key,
    required this.state,
    required this.onOpenFolder,
  });

  final LibraryState state;

  /// Called with a breadcrumb's folder id (null = library root).
  final ValueChanged<String?> onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final filter = state.filter;
    switch (filter.kind) {
      case LibraryFilterKind.favorites:
        return const Text('Favourites');
      case LibraryFilterKind.pdfs:
        return const Text('PDFs');
      case LibraryFilterKind.tag:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sell_outlined),
            const SizedBox(width: 8),
            Flexible(
              child: Text(filter.tag!, overflow: TextOverflow.ellipsis),
            ),
          ],
        );
      case LibraryFilterKind.all:
        break;
    }

    final path = state.breadcrumb;
    if (path.isEmpty) return const Text('Library');

    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final crumbStyle = (theme.appBarTheme.titleTextStyle ??
            theme.textTheme.titleLarge)
        ?.copyWith(color: muted);

    Widget crumb(String label, String? folderId) => TextButton(
          style: TextButton.styleFrom(
            foregroundColor: muted,
            textStyle: crumbStyle,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(0, 40),
          ),
          onPressed: () => onOpenFolder(folderId),
          child: Text(label),
        );

    final separator = Icon(Icons.chevron_right, color: muted, size: 22);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Keep the end (the current folder) visible when the path is long.
      reverse: true,
      child: Row(
        children: [
          crumb('Library', null),
          for (final f in path.take(path.length - 1)) ...[
            separator,
            crumb(f.name, f.id),
          ],
          separator,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(path.last.name),
          ),
        ],
      ),
    );
  }
}
