import 'package:flutter/material.dart';

import '../../../../document/paper.dart';

/// Display name of a paper type.
String paperTypeName(PaperType t) => switch (t) {
      PaperType.blank => 'Blank',
      PaperType.lined => 'Lined',
      PaperType.grid => 'Grid',
      PaperType.dotted => 'Dotted',
      PaperType.cornell => 'Cornell',
      PaperType.music => 'Music',
    };

/// Display name of a paper colour.
String paperColorName(int argb) => switch (argb) {
      Paper.white => 'White',
      Paper.cream => 'Cream',
      Paper.dark => 'Dark',
      _ => 'Custom',
    };

/// What the paper dialog returns: the new paper and whether it applies to
/// every page.
class PaperChoice {
  const PaperChoice(this.paper, {this.allPages = false});
  final Paper paper;
  final bool allPages;
}

/// Asks for a paper type and colour. Returns null when cancelled.
Future<PaperChoice?> showPaperPicker(
  BuildContext context, {
  required Paper initial,
  bool offerAllPages = true,
}) =>
    showDialog<PaperChoice>(
      context: context,
      builder: (_) =>
          _PaperDialog(initial: initial, offerAllPages: offerAllPages),
    );

class _PaperDialog extends StatefulWidget {
  const _PaperDialog({required this.initial, required this.offerAllPages});
  final Paper initial;
  final bool offerAllPages;

  @override
  State<_PaperDialog> createState() => _PaperDialogState();
}

class _PaperDialogState extends State<_PaperDialog> {
  late Paper _paper = widget.initial;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Page paper'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in PaperType.values)
                  ChoiceChip(
                    key: ValueKey('paper-type-${t.name}'),
                    label: Text(paperTypeName(t)),
                    selected: _paper.type == t,
                    onSelected: (_) =>
                        setState(() => _paper = _paper.copyWith(type: t)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in Paper.colors)
                  ChoiceChip(
                    key: ValueKey(
                        'paper-color-${paperColorName(c).toLowerCase()}'),
                    avatar: CircleAvatar(backgroundColor: Color(c), radius: 8),
                    label: Text(paperColorName(c)),
                    selected: _paper.color == c,
                    onSelected: (_) =>
                        setState(() => _paper = _paper.copyWith(color: c)),
                  ),
              ],
            ),
            if (widget.offerAllPages)
              CheckboxListTile(
                key: const ValueKey('paper-all-pages'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Apply to all pages'),
                value: _all,
                onChanged: (v) => setState(() => _all = v ?? false),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('paper-apply'),
          onPressed: () =>
              Navigator.pop(context, PaperChoice(_paper, allPages: _all)),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
