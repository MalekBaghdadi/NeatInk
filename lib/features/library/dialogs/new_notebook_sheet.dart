import 'package:flutter/material.dart';

import '../../../document/cover_design.dart';
import '../../../document/notebook_meta.dart';
import '../../../document/paper.dart';
import '../../editor/integrations/text_images/image_source.dart';
import '../library_naming.dart';
import '../widgets/color_swatch_button.dart';
import '../widgets/paper_preview.dart';
import 'cover_picker.dart';
import 'name_dialog.dart' show maxNameLength;
import '../../../app/insets.dart';

/// What the user chose in the new-notebook sheet.
class NewNotebookRequest {
  const NewNotebookRequest({
    required this.title,
    required this.paper,
    required this.coverColor,
    this.cover,
  });

  final String title;
  final Paper paper;
  final int coverColor;

  /// The design from the cover sheet (null: the plain page-preview cover).
  final CoverChoice? cover;
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
/// paper colour, line spacing and cover (colour, or the full cover sheet;
/// [pickImage] chooses a cover photo). Returns null when cancelled.
Future<NewNotebookRequest?> showNewNotebookSheet(
  BuildContext context, {
  required String defaultTitle,
  required Paper defaultPaper,
  int? defaultCoverColor,
  ImagePicker pickImage = pickImageWithSystemPicker,
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
        pickImage: pickImage,
      ),
    );

class NewNotebookSheet extends StatefulWidget {
  const NewNotebookSheet({
    super.key,
    required this.defaultTitle,
    required this.defaultPaper,
    required this.defaultCoverColor,
    this.pickImage = pickImageWithSystemPicker,
  });

  final String defaultTitle;
  final Paper defaultPaper;
  final int defaultCoverColor;
  final ImagePicker pickImage;

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
  CoverDesign _design = const CoverDesign.preview();
  CoverChoice? _choice;

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
      cover: _choice == null
          ? null
          : CoverChoice(
              design: _design,
              color: _cover,
              photoBytes: _choice!.photoBytes,
              photoExtension: _choice!.photoExtension,
            ),
    ));
  }

  /// The cover preview, quick colours, and the way into the cover sheet.
  Widget _coverRow() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            key: const Key('newNotebookCover'),
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 54,
              height: 72,
              child: CoverSample(
                  design: _design, color: _cover, photoBytes: _choice?.photoBytes),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ColorSwatchPicker(
                  colors: NotebookMeta.coverColors,
                  selected: _design.usesColor ? _cover : null,
                  onSelected: (c) => setState(() {
                    _cover = c;
                    // A colour replaces a photo with a plain cover.
                    if (!_design.usesColor) {
                      _design = const CoverDesign.pattern(CoverPattern.plain);
                      _choice = CoverChoice(design: _design, color: c);
                    }
                  }),
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  key: const Key('newNotebookMoreCovers'),
                  onPressed: _moreCovers,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Patterns, science pictures & photos…'),
                ),
              ],
            ),
          ),
        ],
      );

  Future<void> _moreCovers() async {
    final choice = await showCoverPicker(context,
        design: _design, color: _cover, pickImage: widget.pickImage);
    if (choice == null || !mounted) return;
    setState(() {
      _choice = choice;
      _design = choice.design;
      _cover = choice.color;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The keyboard while typing the title, else the system navigation bar.
    final bottomInset = bottomSafeSpace(context, extra: 8);

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

    // The fields scroll; Cancel / Create stay in view below them.
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
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
                  section('Cover', _coverRow()),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Row(
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
          ),
        ],
      ),
    );
  }
}
