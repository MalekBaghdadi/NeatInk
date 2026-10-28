import 'package:flutter/material.dart';

import '../../editor_controller.dart';
import 'page_ops.dart';
import 'page_thumbnail.dart';
import 'paper_picker.dart';
import '../../../../app/insets.dart';

/// Opens the page grid as a bottom sheet.
Future<void> showPageNavigator(
        BuildContext context, EditorController controller) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: PageNavigator(controller: controller),
      ),
    );

/// Grid of page thumbnails: tap to jump, long-press and drop to reorder,
/// per-page menu for move, duplicate, insert, paper and delete. Deleting
/// shows an Undo bar; the editor's own undo restores the page as well.
class PageNavigator extends StatefulWidget {
  const PageNavigator({super.key, required this.controller, this.ops});

  final EditorController controller;
  final PageOps? ops;

  @override
  State<PageNavigator> createState() => _PageNavigatorState();
}

class _PageNavigatorState extends State<PageNavigator> {
  late final PageOps _ops = widget.ops ?? PageOps(widget.controller);
  bool _showUndo = false;

  EditorController get _c => widget.controller;

  void _onSelected(int index, String action) {
    switch (action) {
      case 'earlier':
        _ops.move(index, index - 1);
      case 'later':
        _ops.move(index, index + 1);
      case 'duplicate':
        _ops.duplicate(index);
      case 'insert':
        _ops.insertBlankAfter(index);
      case 'paper':
        _changePaper(index);
      case 'delete':
        if (_ops.delete(index)) setState(() => _showUndo = true);
    }
  }

  Future<void> _changePaper(int index) async {
    final page = _c.doc.meta.pages[index];
    final choice = await showPaperPicker(context, initial: page.paper);
    if (choice == null) return;
    if (choice.allPages) {
      _ops.setPaperAll(choice.paper);
    } else {
      _ops.setPaper(index, choice.paper);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_c, _c.currentPage]),
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final count = _c.isReady ? _c.pageCount : 0;
        return Scaffold(
          backgroundColor: scheme.surface,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text('Pages ($count)'),
            actions: [
              IconButton(
                key: const ValueKey('nav-add-page'),
                icon: const Icon(Icons.note_add_outlined),
                tooltip: 'Add page at end',
                onPressed: () => _ops.insertBlankAfter(count - 1),
              ),
              IconButton(
                key: const ValueKey('nav-close'),
                icon: const Icon(Icons.close),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: GridView.builder(
                  key: const ValueKey('page-grid'),
                  padding: _showUndo
                      ? const EdgeInsets.all(16)
                      : withBottomSafeSpace(context, const EdgeInsets.all(16)),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.62,
                  ),
                  itemCount: count,
                  itemBuilder: (context, i) => _tile(context, i),
                ),
              ),
              if (_showUndo) _undoBar(context),
            ],
          ),
        );
      },
    );
  }

  Widget _undoBar(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.inverseSurface,
      // The bar is the last thing in the sheet: clear of the navigation bar.
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomSafeSpace(context)),
        child: ListTile(
          key: const ValueKey('nav-undo-bar'),
          textColor: Theme.of(context).colorScheme.onInverseSurface,
          title: const Text('Page deleted'),
          trailing: TextButton(
            key: const ValueKey('nav-undo'),
            onPressed: () {
              if (_c.canUndo) _c.undo();
              setState(() => _showUndo = false);
            },
            child: const Text('Undo'),
          ),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, int i) {
    final scheme = Theme.of(context).colorScheme;
    final current = i == _c.currentPageIndex;
    final card = _card(context, i, current, scheme);
    return DragTarget<int>(
      key: ValueKey('page-tile-$i'),
      onWillAcceptWithDetails: (d) => d.data != i,
      onAcceptWithDetails: (d) => _ops.move(d.data, i),
      builder: (context, candidates, _) => LongPressDraggable<int>(
        data: i,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
              width: 110, child: PageThumbnail(controller: _c, pageIndex: i)),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: card),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: candidates.isEmpty
                ? null
                : Border.all(color: scheme.primary, width: 3),
          ),
          child: card,
        ),
      ),
    );
  }

  Widget _card(
      BuildContext context, int i, bool current, ColorScheme scheme) {
    final page = _c.doc.meta.pages[i];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: InkWell(
            key: ValueKey('page-open-$i'),
            onTap: () {
              _ops.goTo(i);
              Navigator.of(context).maybePop();
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                    color: current ? scheme.primary : scheme.outlineVariant,
                    width: current ? 3 : 1),
              ),
              alignment: Alignment.center,
              child: PageThumbnail(controller: _c, pageIndex: i),
            ),
          ),
        ),
        Row(
          children: [
            const SizedBox(width: 4),
            Expanded(
              child: Text('${i + 1}',
                  style: TextStyle(
                      fontWeight: current ? FontWeight.bold : null)),
            ),
            PopupMenuButton<String>(
              key: ValueKey('page-menu-$i'),
              padding: EdgeInsets.zero,
              tooltip: 'Page ${i + 1}',
              onSelected: (a) => _onSelected(i, a),
              itemBuilder: (context) => [
                if (i > 0)
                  const PopupMenuItem(
                      value: 'earlier', child: Text('Move earlier')),
                if (i < _c.pageCount - 1)
                  const PopupMenuItem(value: 'later', child: Text('Move later')),
                if (!_ops.isLocked(i))
                  const PopupMenuItem(
                      value: 'duplicate', child: Text('Duplicate')),
                const PopupMenuItem(
                    value: 'insert', child: Text('Insert blank page after')),
                if (_ops.canChangePaper(i))
                  PopupMenuItem(
                      value: 'paper',
                      child: Text('Paper (${paperTypeName(page.paper.type)})')),
                if (_ops.canDelete(i))
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
