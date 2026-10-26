import 'package:flutter/material.dart';

import '../../../document/notebook_meta.dart';
import '../../../document/paper.dart';
import '../library_naming.dart';
import '../widgets/color_swatch_button.dart';
import '../widgets/paper_preview.dart';
import 'name_dialog.dart' show maxNameLength;

/// What the user chose in the new-notebook sheet.
class NewNotebookRequest {
  const NewNotebookRequest({
    required this.title,
    required this.paper,
    required this.coverColor,
  });

  final String title;
  final Paper paper;
  final int coverColor;
}

/// Line spacing presets offered when creating a notebook, in points.
const Map<String, double> lineSpacingPresets = {
  'Small': 20,
  'Medium': 26,
  'Large': 32,
};

/// The preset closest to [spacingPt].
double nearestSpacingPreset(double spacingPt) {
  var best = lineSpacingPresets.values.first;
  for (final v in lineSpacingPresets.values) {
    if ((v - spacingPt).abs() < (best - spacingPt).abs()) best = v;
  }
  return best;
}

/// Shows the "New notebook" sheet: title, paper type (with live previews),
/// paper colour, line spacing and cover colour. Returns null when
/// cancelled.
Future<NewNotebookRequest?> showNewNotebookSheet(
  BuildContext context, {
  required String defaultTitle,
  required Paper defaultPaper,
  int? defaultCoverColor,
}) =>
    showModalBottomSheet<NewNotebookRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => NewNotebookSheet(
        defaultTitle: defaultTitle,
        defaultPaper: defaultPaper,
        defaultCoverColor: defaultCoverColor ?? NotebookMeta.defaultCoverColor,
      ),
    );

class NewNotebookSheet extends StatefulWidget {
  const NewNotebookSheet({
    super.key,
    required this.defaultTitle,
    required this.defaultPaper,
    required this.defaultCoverColor,
  });

  final String defaultTitle;
  final Paper defaultPaper;
  final int defaultCoverColor;

  @override
  State<NewNotebookSheet> createState() => _NewNotebookSheetState();
}

class _NewNotebookSheetState extends State<NewNotebookSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.defaultTitle);
  late PaperType _type = widget.defaultPaper.type;
  late int _paperColor = Paper.colors.contains(widget.defaultPaper.color)
      ? widget.defaultPaper.color
      : Paper.white;
  late double _spacing = nearestSpacingPreset(widget.defaultPaper.spacingPt);
  late int _cover = widget.defaultCoverColor;

  Paper get _paper =>
      Paper(type: _type, spacingPt: _spacing, color: _paperColor);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _create() {
    Navigator.of(context).pop(NewNotebookRequest(
      // An emptied title falls back to the suggested one.
      title: cleanName(_title.text, maxLength: maxNameLength) ??
          widget.defaultTitle,
      paper: _paper,
      coverColor: _cover,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    Widget section(String label, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.titleSmall),
              const SizedBox(height: 10),
              child,
            ],
          ),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('New notebook', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),
            TextField(
              key: const Key('newNotebookTitle'),
              controller: _title,
              maxLength: maxNameLength,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              onSubmitted: (_) => _create(),
            ),
            section(
              'Paper',
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final type in PaperType.values)
                    PaperChoice(
                      paper: _paper.copyWith(type: type),
                      selected: type == _type,
                      onTap: () => setState(() => _type = type),
                    ),
                ],
              ),
            ),
            section(
              'Paper colour',
              ColorSwatchPicker(
                colors: Paper.colors,
                selected: _paperColor,
                onSelected: (c) => setState(() => _paperColor = c),
              ),
            ),
            section(
              'Line spacing',
              SegmentedButton<double>(
                segments: [
                  for (final e in lineSpacingPresets.entries)
                    ButtonSegment(value: e.value, label: Text(e.key)),
                ],
                selected: {_spacing},
                showSelectedIcon: false,
                onSelectionChanged: _type == PaperType.blank
                    ? null
                    : (s) => setState(() => _spacing = s.first),
              ),
            ),
            section(
              'Cover',
              ColorSwatchPicker(
                colors: NotebookMeta.coverColors,
                selected: _cover,
                onSelected: (c) => setState(() => _cover = c),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Create'),
                  onPressed: _create,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
