import 'package:flutter/material.dart';

import '../../../document/notebook_meta.dart';
import '../../../document/paper.dart';
import '../../../render/paper_painter.dart';

/// Display names for paper types.
String paperTypeLabel(PaperType type) => switch (type) {
      PaperType.blank => 'Blank',
      PaperType.lined => 'Lined',
      PaperType.grid => 'Grid',
      PaperType.dotted => 'Dotted',
      PaperType.cornell => 'Cornell',
      PaperType.music => 'Music',
    };

/// A small page drawn with [PaperPainter], keeping the page's aspect ratio.
class PaperThumbnail extends StatelessWidget {
  const PaperThumbnail({
    super.key,
    required this.paper,
    this.pageWidthPt = a4WidthPt,
    this.pageHeightPt = a4HeightPt,
  });

  final Paper paper;
  final double pageWidthPt;
  final double pageHeightPt;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: pageWidthPt / pageHeightPt,
        child: CustomPaint(
          painter: PaperPainter(paper, pageWidthPt, pageHeightPt),
        ),
      );
}

/// A selectable paper option: a live preview with a label underneath.
class PaperChoice extends StatelessWidget {
  const PaperChoice({
    super.key,
    required this.paper,
    required this.selected,
    required this.onTap,
    this.width = 84,
  });

  final Paper paper;
  final bool selected;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = paperTypeLabel(paper.type);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label paper',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: selected ? scheme.primary : scheme.outlineVariant,
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: PaperThumbnail(paper: paper),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected ? scheme.primary : null,
                    fontWeight: selected ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
