import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../storage/notebook_repository.dart';
import 'library_navigation.dart';
import 'search_results.dart';
import 'widgets/highlighted_text.dart';
import 'widgets/library_empty_state.dart';

/// Pause after the last keystroke before searching.
const Duration searchDebounce = Duration(milliseconds: 250);

/// What search covers, shown above the results.
const String searchScopeInfo =
    'Searches notebook titles, tags, folder names, typed text, PDF text and '
    'handwriting. Handwriting is read while a notebook is open and you pause, '
    'so open a notebook once to make its writing searchable.';

/// Full-screen search over the library. Results are grouped by notebook;
/// tapping one opens the editor at the matching page.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _input = TextEditingController();
  Timer? _debounce;

  /// Bumped for every search; results of an older search are dropped.
  int _generation = 0;

  /// Query the shown results (or error) belong to.
  String _query = '';

  /// Null until a search has finished for the current text.
  List<SearchGroup>? _groups;
  bool _searching = false;
  bool _failed = false;

  /// Guards against a double tap opening the editor twice.
  bool _editorOpen = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.isEmpty) {
      _generation++;
      setState(() {
        _query = '';
        _groups = null;
        _searching = false;
        _failed = false;
      });
      return;
    }
    _debounce = Timer(searchDebounce, () => _search(q));
  }

  void _searchNow() {
    _debounce?.cancel();
    final q = _input.text.trim();
    if (q.isNotEmpty) unawaited(_search(q));
  }

  void _clear() {
    _input.clear();
    _onChanged('');
  }

  Future<void> _search(String q) async {
    final generation = ++_generation;
    setState(() => _searching = true);
    try {
      final hits = await ref.read(notebookRepositoryProvider).search(q);
      if (!mounted || generation != _generation) return;
      setState(() {
        _query = q;
        _groups = groupSearchHits(hits);
        _failed = false;
        _searching = false;
      });
    } catch (e, st) {
      debugPrint('NeatInk: search failed: $e\n$st');
      if (!mounted || generation != _generation) return;
      setState(() {
        _query = q;
        _groups = null;
        _failed = true;
        _searching = false;
      });
    }
  }

  Future<void> _open(String notebookId, int? pageIndex) async {
    if (_editorOpen) return;
    _editorOpen = true;
    try {
      await ref
          .read(libraryNavigatorProvider)
          .openEditor(context, notebookId, pageIndex: pageIndex);
    } finally {
      _editorOpen = false;
    }
    // Titles and typed text may have changed in the editor.
    if (mounted) _searchNow();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const Key('searchField'),
          controller: _input,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: theme.textTheme.titleLarge,
          decoration: const InputDecoration(
            hintText: 'Search notebooks',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
          onChanged: _onChanged,
          onSubmitted: (_) => _searchNow(),
        ),
        actions: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _input,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: _clear,
                  ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _searching
              ? const LinearProgressIndicator(minHeight: 2)
              : const SizedBox(height: 2),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _ScopeInfo(),
              Expanded(child: _buildResults(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_failed) {
      return LibraryEmptyState(
        key: const Key('search-error'),
        icon: Icons.error_outline,
        title: "Search didn't work",
        message: 'Something went wrong while searching. Your notebooks were '
            'not changed.',
        actions: [
          FilledButton.icon(
            onPressed: _searchNow,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      );
    }
    final groups = _groups;
    if (groups == null) {
      if (_input.text.trim().isNotEmpty) return const SizedBox.shrink();
      return const LibraryEmptyState(
        key: Key('search-start'),
        icon: Icons.search,
        title: 'Search your library',
        message: 'Find notebooks by title, tag or folder, and pages by the '
            'text typed or printed on them.',
      );
    }
    if (groups.isEmpty) {
      return LibraryEmptyState(
        key: const Key('search-no-results'),
        icon: Icons.search_off,
        title: 'No results for “$_query”',
        message: 'Try a shorter or different word.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: groups.length,
      itemBuilder: (context, i) => _ResultGroup(
        key: Key('search-group-${groups[i].notebookId}'),
        group: groups[i],
        query: _query,
        onOpen: _open,
      ),
    );
  }
}

class _ScopeInfo extends StatelessWidget {
  const _ScopeInfo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              searchScopeInfo,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// One notebook's results: a header (opens the notebook) and a row per hit
/// (opens the matching page).
class _ResultGroup extends StatelessWidget {
  const _ResultGroup({
    super.key,
    required this.group,
    required this.query,
    required this.onOpen,
  });

  final SearchGroup group;
  final String query;
  final void Function(String notebookId, int? pageIndex) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = group.hits.length;
    return Card.filled(
      color: scheme.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(Icons.menu_book_outlined, color: scheme.primary),
            title: HighlightedText(
              group.notebookTitle,
              query: query,
              maxLines: 1,
              style: theme.textTheme.titleMedium,
            ),
            subtitle: Text('$count ${count == 1 ? 'match' : 'matches'}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onOpen(group.notebookId, group.firstPageIndex),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          for (var i = 0; i < group.hits.length; i++)
            _HitRow(
              key: Key('search-hit-${group.notebookId}-$i'),
              hit: group.hits[i],
              query: query,
              onTap: () =>
                  onOpen(group.hits[i].notebookId, group.hits[i].pageIndex),
            ),
        ],
      ),
    );
  }
}

class _HitRow extends StatelessWidget {
  const _HitRow({
    super.key,
    required this.hit,
    required this.query,
    required this.onTap,
  });

  final SearchHit hit;
  final String query;
  final VoidCallback onTap;

  static IconData _iconFor(SearchMatchKind kind) => switch (kind) {
        SearchMatchKind.title => Icons.title,
        SearchMatchKind.tag => Icons.sell_outlined,
        SearchMatchKind.folder => Icons.folder_outlined,
        SearchMatchKind.text => Icons.text_fields,
        SearchMatchKind.handwriting => Icons.draw_outlined,
        SearchMatchKind.pdf => Icons.picture_as_pdf_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final label = searchMatchKindLabel(hit.kind);
    final page = hit.pageIndex;
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.only(start: 32, end: 16),
      leading: Tooltip(message: label, child: Icon(_iconFor(hit.kind))),
      title: HighlightedText(
        searchHitDisplayText(hit),
        query: query,
        maxLines: 2,
      ),
      subtitle: Text(page == null ? label : '$label · Page ${page + 1}'),
      onTap: onTap,
    );
  }
}
