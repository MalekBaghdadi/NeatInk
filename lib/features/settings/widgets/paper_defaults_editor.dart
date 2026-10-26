import 'package:flutter/material.dart';

import '../../../document/paper.dart';
import '../../../render/paper_painter.dart';

/// Picks the paper preselected for new notebooks: ruling type (with live
/// previews), background colour and line spacing.
class PaperDefaultsEditor extends StatelessWidget {
  const PaperDefaultsEditor({
    super.key,
    required this.paper,
    required this.onChanged,
  });

  final Paper paper;
  final ValueChanged<Paper> onChanged;

  /// Line spacing range offered, in points (≈ 5.6 mm to 14.1 mm).
  static const double minSpacingPt = 16;
  static const double maxSpacingPt = 40;
  static const double spacingStepPt = 2;

  /// Previews show the top-left 300 × 424 pt of a page (A4 aspect ratio)
  /// so the ruling is large enough to read in a small tile.
  static const double previewWidthPt = 300;
  static const double previewHeightPt = 424;

  static String paperTypeLabel(PaperType type) => switch (type) {
        PaperType.blank => 'Blank',
        PaperType.lined => 'Lined',
        PaperType.grid => 'Grid',
        PaperType.dotted => 'Dotted',
        PaperType.cornell => 'Cornell',
        PaperType.music => 'Music',
      };

  static String paperColorLabel(int color) => switch (color) {
        Paper.white => 'White',
        Paper.cream => 'Cream',
        Paper.dark => 'Dark',
        _ => 'Custom',
      };

  /// Spacing in points and millimetres, e.g. "26 pt · 9.2 mm".
  static String spacingLabel(double pt) =>
      '${pt.round()} pt · ${(pt * 25.4 / 72).toStringAsFixed(1)} mm';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spacing = paper.spacingPt.clamp(minSpacingPt, maxSpacingPt);
    final spacingMatters = paper.type != PaperType.blank;
    final labelStyle = theme.textTheme.bodyLarge;
    final hintStyle =
        theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Paper', style: labelStyle),
          const SizedBox(height: 2),
          Text('Used when you create a notebook. You can still change it '
              'there, and per page.', style: hintStyle),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final type in PaperType.values)
                _PaperTile(
                  key: ValueKey('paper-type-${type.name}'),
                  paper: paper.copyWith(type: type),
                  label: paperTypeLabel(type),
                  selected: paper.type == type,
                  onTap: () => onChanged(paper.copyWith(type: type)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Paper colour', style: labelStyle),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final color in Paper.colors)
                _ColorSwatch(
                  key: ValueKey('paper-color-${paperColorLabel(color)}'),
                  color: color,
                  label: paperColorLabel(color),
                  selected: paper.color == color,
                  onTap: () => onChanged(paper.copyWith(color: color)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Line spacing',
                  style: labelStyle?.copyWith(
                    color: spacingMatters
                        ? null
                        : scheme.onSurface.withValues(alpha: 0.38),
                  ),
                ),
              ),
              Text(
                spacingMatters ? spacingLabel(spacing) : 'No lines',
                style: hintStyle,
              ),
            ],
          ),
          Slider(
            key: const ValueKey('paper-spacing'),
            value: spacing,
            min: minSpacingPt,
            max: maxSpacingPt,
            divisions: ((maxSpacingPt - minSpacingPt) / spacingStepPt).round(),
            label: spacingLabel(spacing),
            onChanged: spacingMatters
                ? (v) => onChanged(paper.copyWith(
                      // Snap away the slider's floating-point noise.
                      spacingPt: (v / spacingStepPt).round() * spacingStepPt,
                    ))
                : null,
          ),
        ],
      ),
    );
  }
}

class _PaperTile extends StatelessWidget {
  const _PaperTile({
    super.key,
    required this.paper,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Paper paper;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const double width = 84;
  static const double height =
      width * PaperDefaultsEditor.previewHeightPt / PaperDefaultsEditor.previewWidthPt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label paper',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: width,
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                    width: selected ? 2.5 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.18),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CustomPaint(
                    painter: PaperPainter(
                      paper,
                      PaperDefaultsEditor.previewWidthPt,
                      PaperDefaultsEditor.previewHeightPt,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    super.key,
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final int color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final swatch = Color(color);
    // Tick colour that stays visible on light and dark paper.
    final tick = ThemeData.estimateBrightnessForColor(swatch) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label paper colour',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outline,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check_rounded, size: 20, color: tick)
                    : null,
              ),
              const SizedBox(width: 8),
              Text(label, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
