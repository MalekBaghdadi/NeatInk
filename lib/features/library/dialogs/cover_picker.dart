import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/insets.dart';
import '../../../document/cover_design.dart';
import '../../../document/notebook_meta.dart';
import '../../editor/integrations/text_images/image_normalizer.dart';
import '../../editor/integrations/text_images/image_source.dart';
import '../widgets/color_swatch_button.dart';
import '../widgets/notebook_cover.dart';

/// Longest side of a stored cover photo, in pixels (a cover is small).
const int coverPhotoMaxSide = 1200;

/// The cover sheet: colour, style (page preview, plain, patterns), science
/// pictures by subject, or a photo from the device, with a live preview.
/// Returns null when cancelled.
///
/// [photoPath] shows the notebook's current photo; [pickImage] chooses a new
/// one (it is normalised here and returned as bytes, stored by the caller).
Future<CoverChoice?> showCoverPicker(
  BuildContext context, {
  required CoverDesign design,
  required int color,
  String? photoPath,
  required ImagePicker pickImage,
}) => showModalBottomSheet<CoverChoice>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 760),
  builder: (_) => FractionallySizedBox(
    heightFactor: 0.9,
    child: CoverPicker(
      design: design,
      color: color,
      photoPath: photoPath,
      pickImage: pickImage,
    ),
  ),
);

class CoverPicker extends StatefulWidget {
  const CoverPicker({
    super.key,
    required this.design,
    required this.color,
    required this.pickImage,
    this.photoPath,
  });

  final CoverDesign design;
  final int color;
  final String? photoPath;
  final ImagePicker pickImage;

  @override
  State<CoverPicker> createState() => _CoverPickerState();
}

class _CoverPickerState extends State<CoverPicker> {
  late CoverDesign _design = widget.design;
  late int _color = widget.color;
  Uint8List? _photo;
  String _photoExtension = 'png';
  bool _loadingPhoto = false;
  String? _photoError;

  bool get _hasPhoto =>
      _photo != null ||
      widget.photoPath != null && widget.design.kind == CoverKind.photo;

  Future<void> _choosePhoto() async {
    setState(() {
      _loadingPhoto = true;
      _photoError = null;
    });
    try {
      final picked = await widget.pickImage();
      if (picked == null || !mounted) return;
      final image = await normalizeImage(
        picked.bytes,
        maxSide: coverPhotoMaxSide,
      );
      if (!mounted) return;
      setState(() {
        _photo = image.bytes;
        _photoExtension = image.extension;
        _design = const CoverDesign.photo('new');
      });
    } on ImageImportException catch (e) {
      if (mounted) setState(() => _photoError = e.message);
    } catch (_) {
      if (mounted) setState(() => _photoError = "Couldn't open that picture.");
    } finally {
      if (mounted) setState(() => _loadingPhoto = false);
    }
  }

  void _done() {
    final photo = _photo;
    Navigator.of(context).pop(
      CoverChoice(
        design: _design.kind == CoverKind.photo && photo == null
            ? widget.design
            : _design,
        color: _color,
        photoBytes: _design.kind == CoverKind.photo ? photo : null,
        photoExtension: _photoExtension,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );

    Widget tiles(List<Widget> children) =>
        Wrap(spacing: 10, runSpacing: 10, children: children);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            children: [
              Text('Cover', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              Center(
                child: SizedBox(
                  key: const ValueKey('cover-preview'),
                  width: 150,
                  height: 200,
                  child: _preview(),
                ),
              ),
              section(
                'Colour',
                ColorSwatchPicker(
                  colors: NotebookMeta.coverColors,
                  selected: _color,
                  onSelected: (c) => setState(() {
                    _color = c;
                    if (_design.kind == CoverKind.photo) {
                      _design = const CoverDesign.pattern(CoverPattern.plain);
                    }
                  }),
                ),
              ),
              section(
                'Style',
                tiles([
                  _tile(
                    key: 'cover-style-preview',
                    label: 'Page preview',
                    design: const CoverDesign.preview(),
                  ),
                  for (final p in CoverPattern.values)
                    _tile(
                      key: 'cover-style-${p.name}',
                      label: p.label,
                      design: CoverDesign.pattern(p),
                    ),
                ]),
              ),
              for (final subject in CoverSubject.values)
                section(
                  subject.label,
                  tiles([
                    for (final a in subject.arts)
                      _tile(
                        key: 'cover-art-${a.name}',
                        label: a.label,
                        design: CoverDesign.art(a),
                      ),
                  ]),
                ),
              section(
                'Your photo',
                Row(
                  children: [
                    if (_hasPhoto)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _tile(
                          key: 'cover-photo',
                          label: 'Photo',
                          design: _photo != null
                              ? const CoverDesign.photo('new')
                              : widget.design,
                        ),
                      ),
                    OutlinedButton.icon(
                      key: const ValueKey('cover-choose-photo'),
                      onPressed: _loadingPhoto ? null : _choosePhoto,
                      icon: _loadingPhoto
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_outlined),
                      label: Text(
                        _hasPhoto
                            ? 'Choose another picture…'
                            : 'Choose a picture…',
                      ),
                    ),
                  ],
                ),
              ),
              if (_photoError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _photoError!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: withBottomSafeSpace(
            context,
            const EdgeInsets.fromLTRB(24, 12, 24, 12),
            extra: 4,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('cover-done'),
                onPressed: _done,
                child: const Text('Use this cover'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _face(CoverDesign design) => CoverSample(
    design: design,
    color: _color,
    photoBytes: design.kind == CoverKind.photo ? _photo : null,
    photoPath: design.kind == CoverKind.photo && _photo == null
        ? widget.photoPath
        : null,
  );

  Widget _preview() => ClipRRect(
    borderRadius: const BorderRadius.horizontal(
      left: Radius.circular(4),
      right: Radius.circular(10),
    ),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: _face(_design),
    ),
  );

  Widget _tile({
    required String key,
    required String label,
    required CoverDesign design,
  }) {
    final selected =
        _design == design ||
        (design.kind == CoverKind.photo && _design.kind == CoverKind.photo);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        key: ValueKey(key),
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _design = design),
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              Container(
                width: 60,
                height: 80,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: _face(design),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A cover in small, as the picker shows it: the "page preview" style is
/// the colour around a white page (the real cover shows the first page).
class CoverSample extends StatelessWidget {
  const CoverSample({
    super.key,
    required this.design,
    required this.color,
    this.photoBytes,
    this.photoPath,
  });

  final CoverDesign design;
  final int color;
  final Uint8List? photoBytes;
  final String? photoPath;

  @override
  Widget build(BuildContext context) => design.kind == CoverKind.preview
      ? ColoredBox(
          color: Color(color),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        )
      : CoverFace(
          design: design,
          color: Color(color),
          photoBytes: photoBytes,
          photoPath: photoPath,
        );
}
