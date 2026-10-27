import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../settings/settings_controller.dart';
import 'canvas/document_view.dart';
import 'editor_controller.dart';
import 'editor_integrations.dart';
import 'tool_prefs.dart';
import 'toolbar/editor_tool_row.dart';

/// The notebook editor: top bar (title, undo / redo, page actions), the tool
/// row and the zoomable page list.
///
/// The screen owns one [EditorController]. Saving follows the storage
/// hand-off: the controller autosaves 1.5 s after the last edit, and this
/// screen asks it to save right away when the app goes to the background and
/// before the screen closes. Features beyond the pen plug in through
/// [editorIntegrationsProvider].
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({
    super.key,
    required this.notebookId,
    this.initialPageIndex,
  });

  final String notebookId;

  /// Page to scroll to first; defaults to the page the notebook was left on.
  final int? initialPageIndex;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen>
    with WidgetsBindingObserver {
  late final EditorController _controller;
  StreamSubscription<Object>? _saveErrors;
  bool _closing = false;
  bool _warnedAboutSaveError = false;

  @override
  void initState() {
    super.initState();
    _controller = EditorController(
      repository: ref.read(notebookRepositoryProvider),
      notebookId: widget.notebookId,
      toolPrefsStore: ToolPrefsStore(ref.read(sharedPreferencesProvider)),
      initialPageIndex: widget.initialPageIndex,
      clock: ref.read(clockProvider),
    );
    _controller.applySettings(ref.read(settingsProvider));
    for (final integrate in ref.read(editorIntegrationsProvider)) {
      integrate(_controller, ref);
    }
    _saveErrors = _controller.saveErrors.listen(_onSaveError);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_controller.open());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_saveErrors?.cancel());
    // Disposing flushes anything still pending (see EditorController).
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Android may kill the app after pause: save now, never lose ink.
      unawaited(_controller.close());
    }
  }

  void _onSaveError(Object error) {
    // Say it once; the changes stay pending and the autosave retries.
    if (!mounted || _warnedAboutSaveError) return;
    _warnedAboutSaveError = true;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Your latest changes couldn't be saved. Mariam's Notes will "
          'keep trying.'),
    ));
  }

  Future<void> _leave() async {
    if (_closing) return;
    _closing = true;
    final saved = await _controller.close();
    if (!mounted) return;
    var leave = saved;
    if (!saved) {
      leave = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Couldn't save"),
              content: const Text('Your latest changes are not saved yet. '
                  'Leaving now could lose them.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Stay'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Leave anyway'),
                ),
              ],
            ),
          ) ??
          false;
    }
    _closing = false;
    if (leave && mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDeletePage() async {
    final controller = _controller;
    if (!controller.canDeletePage) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('A notebook needs at least one page.'),
      ));
      return;
    }
    final index = controller.currentPageIndex;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete page ${index + 1}?'),
        content: const Text('You can undo this right after.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-page'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) controller.deletePageAt(index);
  }

  Future<void> _rename() async {
    final text = TextEditingController(text: _controller.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename notebook'),
        content: TextField(
          controller: text,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    text.dispose();
    if (title != null && mounted) _controller.rename(title);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider, (_, next) => _controller.applySettings(next));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Scaffold(
          appBar: _buildAppBar(context),
          body: _buildBody(context),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final c = _controller;
    return AppBar(
      leading: BackButton(onPressed: () => unawaited(_leave())),
      title: Text(
        c.isReady && c.title.isNotEmpty ? c.title : 'Notebook',
        overflow: TextOverflow.ellipsis,
        key: const ValueKey('editor-title'),
      ),
      actions: c.isReady ? _readyActions(context) : null,
    );
  }

  List<Widget> _readyActions(BuildContext context) {
    final c = _controller;
    final ext = c.extensions;
    return [
      ValueListenableBuilder<int>(
        valueListenable: c.currentPage,
        builder: (context, _, _) => Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${c.currentPageIndex + 1} / ${c.pageCount}',
              key: const ValueKey('page-indicator'),
            ),
          ),
        ),
      ),
      if (ext.openPageNavigator != null)
        IconButton(
          key: const ValueKey('open-page-navigator'),
          icon: const Icon(Icons.grid_view),
          tooltip: 'Pages',
          onPressed: () => ext.openPageNavigator!(context, c),
        ),
      IconButton(
        key: const ValueKey('undo'),
        icon: const Icon(Icons.undo),
        tooltip: c.undoLabel == null ? 'Undo' : 'Undo ${c.undoLabel}',
        onPressed: c.canUndo ? c.undo : null,
      ),
      IconButton(
        key: const ValueKey('redo'),
        icon: const Icon(Icons.redo),
        tooltip: c.redoLabel == null ? 'Redo' : 'Redo ${c.redoLabel}',
        onPressed: c.canRedo ? c.redo : null,
      ),
      IconButton(
        key: const ValueKey('add-page'),
        icon: const Icon(Icons.note_add_outlined),
        tooltip: 'Add page',
        onPressed: c.addPageAtEnd,
      ),
      PopupMenuButton<String>(
        key: const ValueKey('editor-menu'),
        tooltip: 'More',
        onSelected: (value) {
          switch (value) {
            case 'rename':
              unawaited(_rename());
            case 'delete':
              unawaited(_confirmDeletePage());
            case 'paper':
              unawaited(ext.changePagePaper?.call(context, c));
            case 'export':
              unawaited(ext.exportPdf?.call(context, c));
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          const PopupMenuItem(value: 'delete', child: Text('Delete page')),
          if (ext.changePagePaper != null)
            const PopupMenuItem(value: 'paper', child: Text('Page paper')),
          if (ext.exportPdf != null)
            const PopupMenuItem(value: 'export', child: Text('Export PDF')),
        ],
      ),
    ];
  }

  Widget _buildBody(BuildContext context) {
    final c = _controller;
    switch (c.status) {
      case EditorStatus.idle:
      case EditorStatus.loading:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                key: const ValueKey('editor-loading'),
                value: c.pagesToLoad > 1 ? c.loadProgress : null,
              ),
              const SizedBox(height: 16),
              const Text('Opening notebook…'),
            ],
          ),
        );
      case EditorStatus.failed:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                Text(
                  c.errorMessage ?? "The notebook couldn't be opened.",
                  key: const ValueKey('editor-error'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: c.open,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        );
      case EditorStatus.ready:
        return Column(
          children: [
            EditorToolRow(controller: c),
            Expanded(child: DocumentView(controller: c)),
          ],
        );
    }
  }
}
