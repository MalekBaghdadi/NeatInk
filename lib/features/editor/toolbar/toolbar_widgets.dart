import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ink/ink_point.dart';
import '../../../ink/stroke.dart';
import '../../../render/stroke_outline.dart';
import '../editor_tool.dart';
import '../tool_prefs.dart';

/// Side of the square touch target of toolbar controls (tablet friendly).
const double toolbarTargetSize = 44;

/// A user-facing name for a colour: the preset's name, or its hex code.
String colorName(int argb) {
  const names = {
    0xFF1E1E1E: 'Black',
    0xFF1E5BD8: 'Blue',
    0xFFD93025: 'Red',
    0xFF188038: 'Green',
    0xFFF28C00: 'Orange',
    0xFF8E24AA: 'Purple',
    0xFF00838F: 'Teal',
    0xFFFFFFFF: 'White',
    0xFFFFE600: 'Yellow',
    0xFF76FF03: 'Lime',
    0xFF40C4FF: 'Sky blue',
    0xFFFF4081: 'Pink',
    0xFFFFAB40: 'Orange',
    0xFFB388FF: 'Lavender',
  };
  return names[argb] ??
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// User-facing name of a pen style.
String penStyleName(PenStyle style) => switch (style) {
      PenStyle.ballpoint => 'Ballpoint',
      PenStyle.fountain => 'Fountain pen',
      PenStyle.pencil => 'Pencil',
    };

/// Icon of a tool in the tool row.
Widget toolIcon(EditorTool tool, {double size = 24}) => switch (tool) {
      EditorTool.pen => Icon(Icons.draw_outlined, size: size),
      EditorTool.highlighter => Icon(Icons.border_color_outlined, size: size),
      EditorTool.eraser => EraserIcon(size: size),
      EditorTool.lasso => Icon(Icons.highlight_alt, size: size),
      EditorTool.text => Icon(Icons.text_fields, size: size),
      EditorTool.image => Icon(Icons.add_photo_alternate_outlined, size: size),
      EditorTool.shape => Icon(Icons.interests_outlined, size: size),
    };

/// A selectable tool in the tool row. Disabled tools (not integrated yet)
/// are shown greyed out.
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.tool,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final EditorTool tool;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tool.label,
      isSelected: selected,
      onPressed: enabled ? onPressed : null,
      icon: toolIcon(tool),
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(
            Size(toolbarTargetSize, toolbarTargetSize)),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) &&
                    !states.contains(WidgetState.disabled)
                ? scheme.secondaryContainer
                : null),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return scheme.onSurface.withValues(alpha: 0.32);
          }
          return states.contains(WidgetState.selected)
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant;
        }),
      ),
    );
  }
}

/// A round colour swatch. Selected swatches get a ring in the theme's
/// primary colour; every swatch has a hairline outline so white shows on a
/// light toolbar and black on a dark one.
class ColorSwatchButton extends StatelessWidget {
  const ColorSwatchButton({
    super.key,
    required this.color,
    required this.selected,
    required this.onPressed,
    this.tooltip,
    this.diameter = 26,
  });

  /// ARGB.
  final int color;
  final bool selected;
  final VoidCallback onPressed;
  final String? tooltip;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: tooltip ?? colorName(color),
      child: Tooltip(
        message: tooltip ?? colorName(color),
        child: InkResponse(
          onTap: onPressed,
          radius: toolbarTargetSize / 2,
          child: SizedBox.square(
            dimension: toolbarTargetSize,
            child: Center(
              child: Container(
                width: diameter + 8,
                height: diameter + 8,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(color),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.outline.withValues(alpha: 0.55),
                    ),
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

/// Opens the custom colour picker. Shows the current colour when it isn't
/// one of the presets (and is then drawn selected), otherwise a colour
/// wheel glyph.
class CustomColorButton extends StatelessWidget {
  const CustomColorButton({
    super.key,
    required this.customColor,
    required this.onPressed,
  });

  /// The current colour when it is a custom one, else null.
  final int? customColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final custom = customColor;
    return Tooltip(
      message: 'Custom colour',
      child: InkResponse(
        onTap: onPressed,
        radius: toolbarTargetSize / 2,
        child: SizedBox.square(
          dimension: toolbarTargetSize,
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: custom != null ? scheme.primary : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: custom == null ? null : Color(custom),
                  gradient: custom != null
                      ? null
                      : const SweepGradient(colors: [
                          Color(0xFFFF0000),
                          Color(0xFFFFFF00),
                          Color(0xFF00FF00),
                          Color(0xFF00FFFF),
                          Color(0xFF0000FF),
                          Color(0xFFFF00FF),
                          Color(0xFFFF0000),
                        ]),
                  border: Border.all(
                      color: scheme.outline.withValues(alpha: 0.55)),
                ),
                child: custom != null
                    ? null
                    : const Icon(Icons.add, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the three stroke widths, drawn as a dot of growing size in the
/// tool's colour.
class WidthDotButton extends StatelessWidget {
  const WidthDotButton({
    super.key,
    required this.index,
    required this.width,
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  /// 0 = fine, 1 = medium, 2 = bold.
  final int index;

  /// Width in points (shown in the tooltip).
  final double width;
  final int color;
  final bool selected;
  final VoidCallback onPressed;

  static const List<String> _names = ['Fine', 'Medium', 'Bold'];
  static const List<double> _dots = [5, 9, 14];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = _names[index.clamp(0, _names.length - 1)];
    final dot = _dots[index.clamp(0, _dots.length - 1)];
    var dotColor = Color(color);
    // Keep a white dot visible on a light toolbar (and black on dark).
    final contrast = scheme.brightness == Brightness.light
        ? dotColor.computeLuminance() > 0.85
        : dotColor.computeLuminance() < 0.05;
    if (dotColor.a < 0.2) dotColor = scheme.onSurface;
    return Tooltip(
      message: '$name (${_formatPt(width)} pt)',
      child: InkResponse(
        onTap: onPressed,
        radius: toolbarTargetSize / 2,
        child: Semantics(
          button: true,
          selected: selected,
          label: '$name width',
          child: Container(
            width: toolbarTargetSize - 6,
            height: toolbarTargetSize - 6,
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? scheme.secondaryContainer : null,
            ),
            alignment: Alignment.center,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                border: contrast
                    ? Border.all(color: scheme.outline, width: 0.8)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _formatPt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// A thin vertical separator between tool-row groups.
class ToolbarDivider extends StatelessWidget {
  const ToolbarDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: VerticalDivider(
          width: 1,
          thickness: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      );
}

/// An eraser glyph (Material has no eraser icon): a tilted block with a
/// band, painted in the ambient icon colour.
class EraserIcon extends StatelessWidget {
  const EraserIcon({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? const Color(0xFF000000);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _EraserPainter(color)),
    );
  }
}

class _EraserPainter extends CustomPainter {
  _EraserPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24;
    canvas.save();
    canvas.scale(s);
    // Eraser body rotated 45° around the icon centre.
    canvas.translate(12, 11);
    canvas.rotate(-math.pi / 4);
    final body = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-8, -4.5, 16, 9), const Radius.circular(2));
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(body, stroke);
    // The rubber tip is filled; the sleeve stays outlined.
    canvas.drawRRect(
        RRect.fromRectAndCorners(const Rect.fromLTWH(-8, -4.5, 6, 9),
            topLeft: const Radius.circular(2),
            bottomLeft: const Radius.circular(2)),
        Paint()..color = color);
    canvas.restore();
    // The line it rubs out.
    canvas.drawLine(
      Offset(4 * s, 21 * s),
      Offset(20 * s, 21 * s),
      Paint()
        ..color = color
        ..strokeWidth = 1.8 * s
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_EraserPainter oldDelegate) => oldDelegate.color != color;
}

/// A sample stroke drawn with [style] by the real stroke renderer, so the
/// style picker shows exactly what the pen will look like.
class PenStylePreview extends StatelessWidget {
  const PenStylePreview({
    super.key,
    required this.style,
    required this.color,
    this.width = 56,
    this.height = 24,
  });

  final PenStyle style;
  final int color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: CustomPaint(painter: _PenStylePreviewPainter(style, color)),
      );
}

class _PenStylePreviewPainter extends CustomPainter {
  _PenStylePreviewPainter(this.style, this.color);

  final PenStyle style;
  final int color;

  @override
  void paint(Canvas canvas, Size size) {
    // A gentle wave with pressure rising then falling, like a quick
    // handwritten swash.
    const samples = 40;
    final points = <InkPoint>[
      for (var i = 0; i <= samples; i++)
        InkPoint(
          4 + (size.width - 8) * i / samples,
          size.height / 2 +
              math.sin(i / samples * 2 * math.pi) * size.height * 0.28,
          0.25 + 0.6 * math.sin(i / samples * math.pi),
          i * 8,
        ),
    ];
    final stroke = Stroke(
      id: 'preview',
      tool: StrokeTool.pen,
      penStyle: style,
      color: color,
      size: math.max(2.4, size.height / 9),
      raw: points,
    );
    canvas.drawPath(
      outlinePath(strokeOutline(stroke)),
      Paint()..color = strokeFillColor(stroke),
    );
  }

  @override
  bool shouldRepaint(_PenStylePreviewPainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.color != color;
}

/// Whether [argb] is one of [presets].
bool isPresetColor(int argb, List<int> presets) => presets.contains(argb);

/// The default custom colour offered by the picker when the current
/// colour is a preset.
const int defaultCustomColor = 0xFF5C6BC0;

/// Every remembered custom colour that isn't already a preset.
List<int> customRecentColors(ToolPrefs prefs) => [
      for (final c in prefs.recentColors)
        if (!ToolPresets.penColors.contains(c)) c,
    ];
