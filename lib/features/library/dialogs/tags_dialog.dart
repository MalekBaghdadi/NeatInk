import 'package:flutter/material.dart';

import '../tags.dart';

/// Edits a notebook's tags. [suggestions] are the tags already used in the
/// library; tapping one adds it. Returns the new tag list, or null when
/// cancelled.
Future<List<String>?> showTagsDialog(
  BuildContext context, {
  required String notebookTitle,
  required List<String> tags,
  required List<String> suggestions,
}) =>
    showDialog<List<String>>(
      context: context,
      builder: (_) => _TagsDialog(
        notebookTitle: notebookTitle,
        initialTags: tags,
        suggestions: suggestions,
      ),
    );

class _TagsDialog extends StatefulWidget {
  const _TagsDialog({
    required this.notebookTitle,
    required this.initialTags,
    required this.suggestions,
  });

  final String notebookTitle;
  final List<String> initialTags;
  final List<String> suggestions;

  @override
  State<_TagsDialog> createState() => _TagsDialogState();
}

class _TagsDialogState extends State<_TagsDialog> {
  late List<String> _tags = normalizeTags(widget.initialTags);
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  bool _has(String tag) =>
      _tags.any((t) => t.toLowerCase() == tag.toLowerCase());

  void _add(String raw) {
    setState(() => _tags = normalizeTags([..._tags, raw]));
  }

  void _remove(String tag) {
    setState(() => _tags = [for (final t in _tags) if (t != tag) t]);
  }

  /// Typing a comma finishes the current tag, like most tag fields.
  void _onChanged(String value) {
    if (!value.contains(',')) return;
    final parts = value.split(',');
    setState(() {
      _tags = normalizeTags([..._tags, ...parts.take(parts.length - 1)]);
    });
    _input.text = parts.last;
  }

  void _commitInput() {
    if (_input.text.trim().isEmpty) return;
    _add(_input.text);
    _input.clear();
    _inputFocus.requestFocus();
  }

  void _save() {
    // A tag still sitting in the text field counts too.
    Navigator.of(context).pop(normalizeTags([..._tags, _input.text]));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unused = [
      for (final s in widget.suggestions)
        if (!_has(s)) s,
    ];
    return AlertDialog(
      title: const Text('Tags'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.notebookTitle,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              if (_tags.isEmpty)
                Text('No tags yet.', style: theme.textTheme.bodySmall)
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in _tags)
                      InputChip(
                        label: Text(t),
                        avatar: const Icon(Icons.sell_outlined, size: 18),
                        onDeleted: () => _remove(t),
                        deleteButtonTooltipMessage: 'Remove $t',
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _input,
                focusNode: _inputFocus,
                autofocus: true,
                maxLength: maxTagLength,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Add a tag',
                  counterText: '',
                  suffixIcon: IconButton(
                    tooltip: 'Add tag',
                    icon: const Icon(Icons.add),
                    onPressed: _commitInput,
                  ),
                ),
                onChanged: _onChanged,
                onSubmitted: (_) => _commitInput(),
              ),
              if (unused.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Used in your library', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in unused)
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: Text(s),
                        onPressed: () => _add(s),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
