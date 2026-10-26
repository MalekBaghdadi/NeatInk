import 'package:flutter/material.dart';

import '../library_naming.dart';

/// Asks for a name (new folder, rename). Returns the cleaned-up name, or
/// null when cancelled. The confirm button stays disabled while the field
/// is blank.
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String label = 'Name',
  String confirmLabel = 'Save',
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: title,
        initialValue: initialValue,
        label: label,
        confirmLabel: confirmLabel,
      ),
    );

/// Longest name accepted for notebooks and folders.
const int maxNameLength = 120;

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initialValue,
    required this.label,
    required this.confirmLabel,
  });

  final String title;
  final String initialValue;
  final String label;
  final String confirmLabel;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  )..selection = TextSelection(
      baseOffset: 0, extentOffset: widget.initialValue.length);

  String? get _name => cleanName(_controller.text, maxLength: maxNameLength);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name;
    if (name != null) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: _controller,
            autofocus: true,
            maxLength: maxNameLength,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: widget.label,
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _name == null ? null : _submit,
            child: Text(widget.confirmLabel),
          ),
        ],
      );
}
