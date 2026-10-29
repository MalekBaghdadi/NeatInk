import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/insets.dart';
import '../../app/providers.dart';
import '../../storage/notebook_repository.dart';
import 'dialogs/confirm_dialog.dart';
import 'library_controller.dart';
import 'relative_time.dart';

/// Deleted notebooks (v1.8.0, Mariam's request): each can be brought back
/// or deleted for good; they are deleted by themselves after
/// [LibraryController.trashKeep].
class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  List<TrashedNotebook>? _items;
  bool _failed = false;
  bool _busy = false;

  NotebookRepository get _repo => ref.read(notebookRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _repo.listTrash();
      if (mounted) {
        setState(() {
          _items = items;
          _failed = false;
        });
      }
    } catch (e) {
      debugPrint('NeatInk: could not read the Trash: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      debugPrint('NeatInk: $failure $e');
      _snack(failure);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _restore(TrashedNotebook t) => _run(() async {
        await _repo.restoreFromTrash(t.meta.id);
        _snack('“${t.meta.title}” is back in the library');
      }, "Couldn't bring the notebook back.");

  Future<void> _deleteForGood(TrashedNotebook t) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete “${t.meta.title}” for good?',
      message: "Its pages are deleted from this device. This can't be undone.",
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(() => _repo.deleteFromTrash(t.meta.id), "Couldn't delete the notebook.");
  }

  Future<void> _emptyTrash() async {
    final n = _items?.length ?? 0;
    final ok = await showConfirmDialog(
      context,
      title: 'Empty the Trash?',
      message: '${n == 1 ? 'The notebook' : 'All $n notebooks'} in the Trash '
          "will be deleted from this device. This can't be undone.",
      confirmLabel: 'Empty Trash',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(() => _repo.emptyTrash(), "Couldn't empty the Trash.");
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final now = ref.watch(clockProvider)();
    final keep = LibraryController.trashKeep;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          if (items != null && items.isNotEmpty)
            TextButton(
              key: const Key('trash-empty'),
              onPressed: _busy ? null : _emptyTrash,
              child: const Text('Empty Trash'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _failed
          ? const _Message(icon: Icons.error_outline, text: "Couldn't read the Trash.")
          : items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? _Message(
                      icon: Icons.delete_outline,
                      text: 'The Trash is empty.\nDeleted notebooks stay here for ${keep.inDays} days.',
                    )
                  : ListView(
                      padding: withBottomSafeSpace(context, const EdgeInsets.symmetric(vertical: 8)),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: Text(
                            'Notebooks are deleted for good ${keep.inDays} days after they were moved here.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        for (final t in items)
                          ListTile(
                            key: Key('trash-${t.meta.id}'),
                            leading: _Thumb(path: t.thumbnailPath),
                            title: Text(t.meta.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(_subtitle(t, now, keep)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  key: Key('trash-restore-${t.meta.id}'),
                                  tooltip: 'Bring back',
                                  icon: const Icon(Icons.restore),
                                  onPressed: _busy ? null : () => _restore(t),
                                ),
                                IconButton(
                                  key: Key('trash-delete-${t.meta.id}'),
                                  tooltip: 'Delete for good',
                                  icon: const Icon(Icons.delete_forever_outlined),
                                  onPressed: _busy ? null : () => _deleteForGood(t),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
    );
  }

  static String _subtitle(TrashedNotebook t, DateTime now, Duration keep) {
    final pages = t.meta.pages.length;
    final left = t.deletedAt.add(keep).difference(now).inDays.clamp(0, keep.inDays);
    return '$pages ${pages == 1 ? 'page' : 'pages'} · deleted ${formatRelative(t.deletedAt, now)} · '
        '${left == 0 ? 'goes today' : '$left ${left == 1 ? 'day' : 'days'} left'}';
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = path;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 40,
        height: 52,
        child: p == null
            ? ColoredBox(
                color: scheme.surfaceContainerHigh,
                child: Icon(Icons.menu_book_outlined, color: scheme.onSurfaceVariant),
              )
            : Image.file(
                File(p),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => ColoredBox(color: scheme.surfaceContainerHigh),
              ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: muted),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: muted)),
          ],
        ),
      ),
    );
  }
}
