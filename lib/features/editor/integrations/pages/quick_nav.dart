import 'package:flutter/material.dart';

import '../../editor_controller.dart';
import 'page_ops.dart';

/// Small floating pill: previous page, "n / total" (tap to jump to a page
/// number), next page.
class QuickPageNav extends StatelessWidget {
  const QuickPageNav({super.key, required this.controller, required this.ops});

  final EditorController controller;
  final PageOps ops;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, controller.currentPage]),
      builder: (context, _) {
        if (!controller.isReady || controller.pageCount < 2) {
          return const SizedBox.shrink();
        }
        final i = controller.currentPageIndex;
        final n = controller.pageCount;
        return Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Material(
              key: const ValueKey('quick-nav'),
              elevation: 3,
              borderRadius: BorderRadius.circular(24),
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const ValueKey('quick-prev'),
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Previous page',
                    onPressed: i > 0 ? ops.previous : null,
                  ),
                  InkWell(
                    key: const ValueKey('quick-jump'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => showJumpToPage(context, ops),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: Text('${i + 1} / $n'),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('quick-next'),
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Next page',
                    onPressed: i < n - 1 ? ops.next : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Asks for a page number (1-based) and scrolls there. Out-of-range
/// numbers are clamped.
Future<void> showJumpToPage(BuildContext context, PageOps ops) async {
  final result = await showDialog<int>(
    context: context,
    builder: (_) => _JumpDialog(pageCount: ops.pageCount),
  );
  if (result != null) ops.goTo(result - 1);
}

class _JumpDialog extends StatefulWidget {
  const _JumpDialog({required this.pageCount});
  final int pageCount;

  @override
  State<_JumpDialog> createState() => _JumpDialogState();
}

class _JumpDialogState extends State<_JumpDialog> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Go to page'),
      content: TextField(
        key: const ValueKey('jump-field'),
        controller: _text,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(hintText: '1 - ${widget.pageCount}'),
        onSubmitted: (v) => Navigator.pop(context, int.tryParse(v.trim())),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('jump-go'),
          onPressed: () =>
              Navigator.pop(context, int.tryParse(_text.text.trim())),
          child: const Text('Go'),
        ),
      ],
    );
  }
}
