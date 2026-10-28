import 'package:flutter/material.dart';

import '../../../../document/font_kind.dart';
import '../../../settings/convert_style_prefs.dart';
import '../text_images/text_format_bar.dart';
import 'convert_config.dart';

/// The look of converted handwriting: font, bold / italic, size, colour,
/// and whether the lines of one sentence are joined. Shown in the Convert
/// sheet and in the "Typed text" sheet (open any time from the editor and
/// the settings), so both edit the same remembered look.
class ConvertStyleControls extends StatelessWidget {
  const ConvertStyleControls({
    super.key,
    required this.value,
    required this.onChange,
    this.evenSize,
  });

  final ConvertStylePrefs value;

  /// Applies a change to the owner's current look (a function of it, so two
  /// quick taps before a redraw both count).
  final void Function(ConvertStylePrefs Function(ConvertStylePrefs) change) onChange;

  /// The even size on the page at hand, in points, shown with that choice.
  final double? evenSize;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final scheme = Theme.of(context).colorScheme;
    final label = Theme.of(context).textTheme.labelLarge;
    final custom = v.sizeMode == ConvertSizeMode.custom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PopupMenuButton<FontKind>(
              key: const ValueKey('convert-font'),
              tooltip: 'Font',
              initialValue: v.font,
              onSelected: (f) => onChange((p) => p.copyWith(fontId: f.name)),
              itemBuilder: (_) => TextFormatBar.fontPickerItems(v.font),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outline),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(v.font.label,
                        key: const ValueKey('convert-font-label'),
                        style: TextStyle(fontFamily: v.font.family)),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
            FilterChip(
              key: const ValueKey('convert-bold'),
              label: const Text('Bold'),
              selected: v.bold,
              onSelected: (b) => onChange((p) => p.copyWith(bold: b)),
            ),
            FilterChip(
              key: const ValueKey('convert-italic'),
              label: const Text('Italic'),
              selected: v.italic,
              onSelected: (i) => onChange((p) => p.copyWith(italic: i)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Size', style: label),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              key: const ValueKey('convert-size-even'),
              label: Text(evenSize == null
                  ? 'Even size (fits the lines)'
                  : 'Even size (${evenSize!.round()} pt)'),
              tooltip: 'Every line the same size, chosen to sit on the page lines',
              selected: v.sizeMode == ConvertSizeMode.even,
              onSelected: (_) => onChange((p) => p.copyWith(sizeMode: ConvertSizeMode.even)),
            ),
            ChoiceChip(
              key: const ValueKey('convert-size-auto'),
              label: const Text('Match my handwriting'),
              tooltip: 'Each line as big as it was written',
              selected: v.sizeMode == ConvertSizeMode.handwriting,
              onSelected: (_) => onChange((p) => p.copyWith(sizeMode: ConvertSizeMode.handwriting)),
            ),
            ChoiceChip(
              key: const ValueKey('convert-size-custom'),
              label: const Text('Custom'),
              selected: custom,
              onSelected: (_) => onChange((p) => p.copyWith(sizeMode: ConvertSizeMode.custom)),
            ),
          ],
        ),
        // Dimmed unless Custom is chosen, since only Custom uses it. It still
        // answers a drag, which switches to Custom.
        AnimatedOpacity(
          key: const ValueKey('convert-size-slider-fade'),
          opacity: custom ? 1 : 0.4,
          duration: const Duration(milliseconds: 150),
          child: SizedBox(
            width: 320,
            child: Row(
              children: [
                Expanded(
                  child: Slider(
                    key: const ValueKey('convert-size-slider'),
                    min: ConvertConfig.minFixedSize,
                    max: ConvertConfig.maxFixedSize,
                    divisions: (ConvertConfig.maxFixedSize - ConvertConfig.minFixedSize).round(),
                    value: (v.fixedSize ?? ConvertConfig.defaultFixedSize)
                        .clamp(ConvertConfig.minFixedSize, ConvertConfig.maxFixedSize)
                        .toDouble(),
                    onChanged: (size) =>
                        onChange((p) => p.copyWith(sizeMode: ConvertSizeMode.custom, fixedSize: size)),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    custom ? '${(v.fixedSize ?? ConvertConfig.defaultFixedSize).round()} pt' : '',
                    key: const ValueKey('convert-size-label'),
                  ),
                ),
              ],
            ),
          ),
        ),
        Text('Colour', style: label),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              key: const ValueKey('convert-colour-keep'),
              label: const Text('Keep my ink colour'),
              selected: v.colorOverride == null,
              onSelected: (_) => onChange((p) => p.copyWith(clearColorOverride: true)),
            ),
            for (final c in ConvertConfig.colorChoices)
              GestureDetector(
                key: ValueKey('convert-colour-${c.toRadixString(16)}'),
                onTap: () => onChange((p) => p.copyWith(colorOverride: c)),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      width: v.colorOverride == c ? 3 : 1,
                      color: v.colorOverride == c ? scheme.primary : scheme.outlineVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          key: const ValueKey('convert-join-lines'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Join lines into sentences'),
          subtitle: const Text('A sentence written over several lines becomes one line of '
              'text, wrapping at the page edge.'),
          value: v.joinLines,
          onChanged: (j) => onChange((p) => p.copyWith(joinLines: j)),
        ),
      ],
    );
  }
}
