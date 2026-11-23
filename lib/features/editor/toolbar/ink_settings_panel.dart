import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../ink/line_style.dart';
import 'color_picker_dialog.dart';
import 'ink_settings_model.dart';
import 'ink_sliders.dart';
import 'line_style_widgets.dart';
import 'toolbar_widgets.dart';

/// Width of the settings card in dp.
const double inkSettingsPanelWidth = 340;

/// How much of the screen height the card may use before it scrolls.
const double _maxHeightFraction = 0.9;

const double _cardRadius = 28;
const double _cardPadding = 20;

/// Blur of what shows through the translucent card.
const double _backdropBlur = 16;

/// Space between two sections of the card.
const double _sectionGap = 14;

/// How many colours fit in a row of the colour grid.
const int inkColorColumns = 6;

/// Marks the widget that [showInkSettingsPanel] opens its panel under: the
/// tool row wraps itself in one, so a panel opened from any button inside it
/// appears below the whole row. Without one the panel opens under the widget
/// that opened it.
class InkSettingsAnchor extends StatelessWidget {
  const InkSettingsAnchor({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Shows the pen settings panel for [model]: a card that fades in under the
/// tool row at the right edge of the screen. A tap outside, or back, closes
/// it. Changes apply at once; there is nothing to confirm.
Future<void> showInkSettingsPanel(BuildContext context, InkSettingsModel model) {
  final anchor = _anchorRect(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close settings',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => _PanelPlacement(
      anchor: anchor,
      child: InkSettingsPanel(model: model),
    ),
    transitionBuilder: (context, animation, _, child) {
      final eased = animation.drive(CurveTween(curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: eased,
        child: ScaleTransition(
          scale: eased.drive(Tween<double>(begin: 0.94, end: 1)),
          alignment: Alignment.topRight,
          child: child,
        ),
      );
    },
  );
}

/// The screen rectangle of the nearest [InkSettingsAnchor] above [context],
/// else of [context]'s own widget; null when it isn't laid out.
Rect? _anchorRect(BuildContext context) {
  RenderObject? object;
  context.visitAncestorElements((element) {
    if (element.widget is InkSettingsAnchor) {
      object = element.renderObject;
      return false;
    }
    return true;
  });
  object ??= context.findRenderObject();
  final box = object;
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Puts the card at the top right, just under the [anchor], and gives it the
/// height that is left.
class _PanelPlacement extends StatelessWidget {
  const _PanelPlacement({required this.anchor, required this.child});

  final Rect? anchor;
  final Widget child;

  static const double _margin = 8;

  /// The card keeps at least this much room, even if the anchor is low.
  static const double _minRoom = 240;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final bottomEdge = constraints.maxHeight - inset.bottom - _margin;
      final lowest = math.max(inset.top + _margin, bottomEdge - _minRoom);
      final below = anchor == null ? 0.0 : anchor!.bottom + 4;
      final top = math.max(inset.top + _margin, math.min(below, lowest));
      return Padding(
        padding: EdgeInsets.fromLTRB(
          _margin + inset.left,
          top,
          _margin + inset.right,
          inset.bottom + _margin,
        ),
        child: Align(alignment: Alignment.topRight, child: child),
      );
    });
  }
}

/// A listenable that never fires, for models without one.
class _NeverNotifies implements Listenable {
  const _NeverNotifies();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// The pen settings card, recreated from the video: "Reset" and the title,
/// "Thickness", "Concentration", the "Line Style" chips, the two wave
/// sliders (only for wavy and zigzag), "Horizontal drawing", and the "Color"
/// grid. It edits whatever [model] stands for (the pen, the highlighter, a
/// selection) and is 340 dp wide, or as wide as the screen allows; when the
/// screen is short the card scrolls under its title.
class InkSettingsPanel extends StatelessWidget {
  const InkSettingsPanel({super.key, required this.model});

  final InkSettingsModel model;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final radius = BorderRadius.circular(_cardRadius);
    return LayoutBuilder(builder: (context, constraints) {
      final width = math.min(inkSettingsPanelWidth, constraints.maxWidth);
      final maxHeight =
          math.min(screenHeight * _maxHeightFraction, constraints.maxHeight);
      // The painter casts the soft shadow outside the card; the material is
      // the translucent, blurred card (and the surface the ink splashes of
      // its buttons paint on).
      return SizedBox(
        width: width,
        child: CustomPaint(
          key: const ValueKey('ink-settings-panel'),
          painter: _CardShadowPainter(
            radius: _cardRadius,
            color: scheme.shadow.withValues(alpha: 0.2),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: _backdropBlur, sigmaY: _backdropBlur),
              child: Material(
                color: scheme.surfaceContainerHigh.withValues(alpha: 0.92),
                shape: RoundedRectangleBorder(
                  borderRadius: radius,
                  side: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.6),
                    width: 0.5,
                  ),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: ListenableBuilder(
                    listenable: model.listenable ?? const _NeverNotifies(),
                    builder: (context, _) =>
                        _PanelContent(model: model, values: model.values()),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// A soft drop shadow around a rounded card, drawn only outside the card:
/// under a translucent card a full shadow would tint it (and the
/// `Material` elevation shadow of a clear material is drawn hard by some
/// renderers).
class _CardShadowPainter extends CustomPainter {
  const _CardShadowPainter({required this.radius, required this.color});

  final double radius;
  final Color color;

  static const double _blurSigma = 14;
  static const double _offsetY = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final card = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
    final reach = _blurSigma * 4;
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect((Offset.zero & size).inflate(reach)),
      Path()..addRRect(card),
    );
    canvas
      ..save()
      ..clipPath(outside)
      ..drawRRect(
        card.shift(const Offset(0, _offsetY)),
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _blurSigma),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_CardShadowPainter old) =>
      old.radius != radius || old.color != color;
}

class _PanelContent extends StatelessWidget {
  const _PanelContent({required this.model, required this.values});

  final InkSettingsModel model;
  final InkSettingsValues values;

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        );
    final line = values.line;
    final commit = model.commitOnRelease;
    final onHorizontal = model.onHorizontal;
    final onColor = model.onColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          title: model.title,
          onReset: model.canReset(values) ? model.onReset : null,
          showReset: model.onReset != null,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                _cardPadding, 4, _cardPadding, _cardPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkValueSlider(
                  id: 'thickness',
                  label: 'Thickness',
                  value: values.size,
                  min: model.minSize,
                  max: model.maxSize,
                  onChanged: model.onSize,
                  commitOnRelease: commit,
                ),
                const SizedBox(height: _sectionGap),
                InkValueSlider(
                  id: 'concentration',
                  label: 'Concentration',
                  value: values.concentration,
                  min: minConcentration,
                  max: 1,
                  decimals: 2,
                  format: _percent,
                  steppers: false,
                  onChanged: model.onConcentration,
                  commitOnRelease: commit,
                ),
                const SizedBox(height: _sectionGap),
                Text('Line Style', style: label),
                const SizedBox(height: 8),
                LineStyleGrid(
                  line: line,
                  onSelected: (style) => _editLine(
                    model,
                    (line) => line.copyWith(style: style),
                  ),
                ),
                _Reveal(
                  visible: line.hasWaveParams,
                  child: Padding(
                    padding: const EdgeInsets.only(top: _sectionGap),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InkValueSlider(
                          id: 'wave-height',
                          label: 'Wavy Line Height',
                          value: line.waveHeight,
                          min: LineSettings.minWaveHeight,
                          max: LineSettings.maxWaveHeight,
                          onChanged: (v) => _editLine(
                              model, (line) => line.copyWith(waveHeight: v)),
                          commitOnRelease: commit,
                        ),
                        const SizedBox(height: _sectionGap),
                        InkValueSlider(
                          id: 'wave-width',
                          label: 'Wavy Line Width',
                          value: line.waveWidth,
                          min: LineSettings.minWaveWidth,
                          max: LineSettings.maxWaveWidth,
                          onChanged: (v) => _editLine(
                              model, (line) => line.copyWith(waveWidth: v)),
                          commitOnRelease: commit,
                        ),
                      ],
                    ),
                  ),
                ),
                if (values.horizontal != null && onHorizontal != null)
                  SwitchListTile(
                    key: const ValueKey('ink-settings-horizontal'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('Horizontal drawing', style: label),
                    value: values.horizontal!,
                    onChanged: onHorizontal,
                  ),
                if (onColor != null) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: _sectionGap),
                  _ColorSection(
                    model: model,
                    values: values,
                    onColor: onColor,
                    labelStyle: label,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _percent(double v) => '${(v * 100).round()}%';

  /// Reports [change] applied to the line settings as they are *now*, not as
  /// they were when this widget last built: two fingers on two sliders, or a
  /// chip tap during a drag, must not undo each other.
  static void _editLine(
    InkSettingsModel model,
    LineSettings Function(LineSettings line) change,
  ) =>
      model.onLine(change(model.values().line));
}

/// "Reset" on the left (greyed out when there is nothing to reset), the
/// title in the middle.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.onReset,
    required this.showReset,
  });

  final String title;

  /// Null greys the button out.
  final VoidCallback? onReset;

  /// False when the model has no Reset at all.
  final bool showReset;

  /// Room the title leaves free on each side for the Reset button.
  static const double _side = 84;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _side, vertical: 16),
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.onSurface),
            ),
          ),
          if (showReset)
            Positioned(
              left: 14,
              top: 0,
              bottom: 0,
              child: Center(
                child: FilledButton.tonal(
                  key: const ValueKey('ink-settings-reset'),
                  onPressed: onReset,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Reset'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Slides and fades [child] in and out as [visible] changes, and builds
/// nothing at all while it is hidden.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(end: visible ? 1 : 0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: child,
        builder: (context, t, child) => t == 0
            ? const SizedBox.shrink()
            : ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: t,
                  child: Opacity(opacity: t, child: child),
                ),
              ),
      );
}

/// The "Color" header with the colour-wheel button, and the colour grid.
class _ColorSection extends StatelessWidget {
  const _ColorSection({
    required this.model,
    required this.values,
    required this.onColor,
    required this.labelStyle,
  });

  final InkSettingsModel model;
  final InkSettingsValues values;
  final ValueChanged<int> onColor;
  final TextStyle? labelStyle;

  Future<void> _pickCustom(BuildContext context) async {
    final custom = model.onCustomColor;
    if (custom != null) return custom(context);
    final picked = await showColorPickerDialog(
      context,
      initialColor: values.color ?? defaultCustomColor,
      recentColors: values.recentColors,
      title: 'Custom colour',
    );
    if (picked != null) onColor(picked);
  }

  @override
  Widget build(BuildContext context) {
    // The presets, the recent custom colours, and the selected colour if it
    // is neither (so what is selected is always on view); no colour twice.
    final colors = <int>{
      ...model.presetColors,
      ...values.recentColors,
      ?values.color,
    }.toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Color', style: labelStyle)),
            _ColorWheelButton(onPressed: () => _pickCustom(context)),
          ],
        ),
        const SizedBox(height: 8),
        InkColorGrid(
          colors: colors,
          selected: values.color,
          onColor: onColor,
          onAdd: () => _pickCustom(context),
        ),
      ],
    );
  }
}

/// Round swatches, [columns] to a row, then a "+" cell that adds a custom
/// colour. Every swatch is named `ink-settings-color-<argb decimal>`, the
/// "+" cell `ink-settings-color-add`.
class InkColorGrid extends StatelessWidget {
  const InkColorGrid({
    super.key,
    required this.colors,
    required this.selected,
    required this.onColor,
    required this.onAdd,
    this.columns = inkColorColumns,
  }) : assert(columns > 0);

  /// ARGB colours, without repeats.
  final List<int> colors;
  final int? selected;
  final ValueChanged<int> onColor;
  final VoidCallback onAdd;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[
      for (final c in colors)
        ColorSwatchButton(
          key: ValueKey('ink-settings-color-$c'),
          color: c,
          selected: c == selected,
          onPressed: () => onColor(c),
        ),
      _AddColorButton(
        key: const ValueKey('ink-settings-color-add'),
        onPressed: onAdd,
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var start = 0; start < cells.length; start += columns)
          Row(
            children: [
              for (var i = start; i < start + columns; i++)
                Expanded(
                  child: i < cells.length
                      ? Center(child: cells[i])
                      : const SizedBox.shrink(),
                ),
            ],
          ),
      ],
    );
  }
}

/// The grey "+" circle that ends the colour grid.
class _AddColorButton extends StatelessWidget {
  const _AddColorButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Custom color',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Custom color',
        child: InkResponse(
          onTap: onPressed,
          radius: toolbarTargetSize / 2,
          child: SizedBox.square(
            dimension: toolbarTargetSize,
            child: Center(
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surfaceContainerHighest,
                  border: Border.all(
                    color: scheme.outline.withValues(alpha: 0.55),
                  ),
                ),
                child: Icon(Icons.add, size: 20, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small rainbow circle in the "Color" header; opens the colour picker.
class _ColorWheelButton extends StatelessWidget {
  const _ColorWheelButton({required this.onPressed});

  final VoidCallback onPressed;

  static const List<Color> _rainbow = [
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Pick any color',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Pick any color',
        child: InkResponse(
          key: const ValueKey('ink-settings-color-wheel'),
          onTap: onPressed,
          radius: toolbarTargetSize / 2,
          child: SizedBox.square(
            dimension: toolbarTargetSize - 8,
            child: Center(
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const SweepGradient(colors: _rainbow),
                  border: Border.all(
                    color: scheme.outline.withValues(alpha: 0.55),
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
