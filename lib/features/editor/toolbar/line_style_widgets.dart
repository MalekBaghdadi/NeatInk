import 'package:flutter/material.dart';

import '../../../ink/ink_point.dart';
import '../../../ink/line_style.dart';
import '../../../ink/stroke.dart';
import '../../../render/stroke_outline.dart';
import 'toolbar_widgets.dart';

/// Pen width, in points, of the line samples in chips and the toolbar pill
/// (the video's panel shows its samples with a fine pen).
const double linePreviewPenSize = 2.0;

/// A short horizontal stroke drawn with [line] by the real stroke renderer
/// (`strokeOutlines`), so a sample shows exactly what the pen will draw. The
/// sample is clipped to its box: a tall wave in a small chip is cut, not
/// spilled over the neighbours.
class LineStylePreview extends StatelessWidget {
  const LineStylePreview({
    super.key,
    required this.line,
    required this.color,
    this.width,
    this.height = 20,
    this.penSize = linePreviewPenSize,
  });

  final LineSettings line;

  /// ARGB colour of the ink.
  final int color;

  /// Null fills the width the parent allows.
  final double? width;
  final double height;
  final double penSize;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: CustomPaint(painter: _LinePreviewPainter(line, color, penSize)),
      );
}

class _LinePreviewPainter extends CustomPainter {
  const _LinePreviewPainter(this.line, this.color, this.penSize);

  final LineSettings line;
  final int color;
  final double penSize;

  @override
  void paint(Canvas canvas, Size size) {
    // The round caps reach half a pen width past the end points.
    final inset = penSize + 1;
    final length = size.width - 2 * inset;
    if (!(length > 1) || !size.height.isFinite) return;
    final y = size.height / 2;
    final stroke = Stroke(
      id: 'line-preview',
      tool: StrokeTool.pen,
      penStyle: PenStyle.technical,
      color: color,
      size: penSize,
      raw: [
        InkPoint(inset, y, 0.5, 0),
        InkPoint(inset + length, y, 0.5, 100),
      ],
      line: line,
    );
    canvas.clipRect(Offset.zero & size);
    canvas.drawPath(
      outlinesPath(strokeOutlines(stroke)),
      Paint()..color = strokeFillColor(stroke),
    );
  }

  @override
  bool shouldRepaint(_LinePreviewPainter old) =>
      old.line != line || old.color != color || old.penSize != penSize;
}

/// One entry of the "Line Style" grid: a stadium chip holding a sample of
/// the line style. The selected chip has the container fill and a thin
/// outline in the primary colour.
class LineStyleChip extends StatelessWidget {
  const LineStyleChip({
    super.key,
    required this.line,
    required this.selected,
    required this.onPressed,
  });

  /// The sample to draw; its [LineSettings.style] is the chip's style and
  /// its wave sliders shape the sample, so the wavy chip follows the sliders.
  final LineSettings line;
  final bool selected;
  final VoidCallback onPressed;

  static const double height = 36;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: line.style.label,
      excludeSemantics: true,
      child: Tooltip(
        message: line.style.label,
        child: Material(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest.withValues(alpha: 0.8),
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? scheme.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                  child: LineStylePreview(
                    line: line,
                    color: ink.toARGB32(),
                    height: height - 6,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "Line Style" chips in a grid of [columns] columns, one per
/// [LineStyle]: with the default three, Solid, Dashed, Dotted on the first
/// row and Wavy, Zigzag, Double on the second.
///
/// The chip of the style [line] already has does nothing when tapped.
class LineStyleGrid extends StatelessWidget {
  const LineStyleGrid({
    super.key,
    required this.line,
    required this.onSelected,
    this.columns = 3,
  }) : assert(columns > 0);

  /// The current settings: the selected chip, and the wave sliders that shape
  /// the wavy and zigzag samples.
  final LineSettings line;

  /// Called with the tapped style, unless it is the current one.
  final ValueChanged<LineStyle> onSelected;
  final int columns;

  static const double gap = 8;

  @override
  Widget build(BuildContext context) {
    final styles = LineStyle.values;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var start = 0; start < styles.length; start += columns) ...[
          if (start > 0) const SizedBox(height: gap),
          Row(
            children: [
              for (var i = start; i < start + columns; i++) ...[
                if (i > start) const SizedBox(width: gap),
                Expanded(
                  child: i < styles.length
                      ? LineStyleChip(
                          key: ValueKey('ink-settings-line-${styles[i].name}'),
                          line: line.copyWith(style: styles[i]),
                          selected: styles[i] == line.style,
                          onPressed: () {
                            if (styles[i] != line.style) onSelected(styles[i]);
                          },
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// The toolbar's stadium button (64 x 32) with a miniature of the current
/// line style in the pen colour. It opens the pen settings panel.
class LineStylePill extends StatelessWidget {
  const LineStylePill({
    super.key,
    required this.line,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  final LineSettings line;

  /// ARGB colour of the miniature (see [inkSampleColor]).
  final int color;
  final String tooltip;

  /// Gets the pill's own context, so a panel can open under it.
  final void Function(BuildContext context) onPressed;

  static const Size size = Size(64, 32);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: Padding(
          // Breathing room around the pill inside the tool row.
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Material(
            color: scheme.secondaryContainer.withValues(alpha: 0.7),
            shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onPressed(context),
              child: SizedBox.fromSize(
                size: size,
                child: Center(
                  child: LineStylePreview(
                    line: line,
                    color: color,
                    width: size.width - 20,
                    height: size.height - 8,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
