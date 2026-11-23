import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The sliders and steppers of the pen settings panel (`ink_settings_panel`).
///
/// They follow the video's panel: a thin track whose part left of the thumb
/// is filled with the theme's primary colour, a white rounded-pill thumb with
/// a soft shadow, and small circled minus / plus steppers next to the value.

/// [v] rounded to [decimals] decimal places as the clean decimal (2.3, not
/// 2.3000000000000003), so stored values and displayed text agree.
double roundToDecimals(double v, int decimals) =>
    v.isFinite ? double.parse(v.toStringAsFixed(decimals)) : v;

/// The next value on the 0.1 grid above ([direction] > 0) or below
/// ([direction] < 0) [v], kept within [min]..[max]. A value that is already
/// on the grid moves by exactly 0.1 (2.3 -> 2.4 even though 2.3 * 10 is
/// 22.999999999999996); one between two grid points moves to the next one in
/// the chosen direction (2.25 -> 2.3 or 2.2). A value that isn't a number
/// gives [min].
double stepTenth(double v, int direction,
    {required double min, required double max}) {
  if (!v.isFinite) return min;
  final tenths = v * 10;
  final nearest = tenths.roundToDouble();
  final onGrid = (tenths - nearest).abs() < 1e-6;
  final next = direction >= 0
      ? (onGrid ? nearest + 1 : tenths.ceilToDouble())
      : (onGrid ? nearest - 1 : tenths.floorToDouble());
  // Dividing (not multiplying by 0.1) gives the double nearest the decimal.
  return (next / 10).clamp(min, math.max(min, max)).toDouble();
}

/// Side of the touch target of a stepper button.
const double _stepTarget = 36;

/// Diameter of the circle drawn in a stepper button.
const double _stepCircle = 22;

/// A small circled minus or plus button.
class InkStepButton extends StatelessWidget {
  const InkStepButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;

  /// Null greys the button out (the value is at its limit).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final color = scheme.onSurfaceVariant.withValues(alpha: enabled ? 0.9 : 0.35);
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onPressed,
          radius: _stepTarget / 2,
          child: SizedBox.square(
            dimension: _stepTarget,
            child: Center(
              child: Container(
                width: _stepCircle,
                height: _stepCircle,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.2),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A slider drawn like the video's: a thin grey track, the part left of the
/// thumb filled with the primary colour at about 55%, and a white
/// rounded-pill thumb (30 x 20) with a soft shadow. A plain [Slider] inside,
/// so dragging, keyboard and accessibility behave as usual.
class InkSlider extends StatelessWidget {
  const InkSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.divisions,
    this.semanticFormatter,
  });

  /// Must lie within [min]..[max].
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final int? divisions;

  /// What a screen reader says for a value.
  final String Function(double value)? semanticFormatter;

  /// Height of the touch area (the drawn track is only 3 dp thin).
  static const double touchHeight = 36;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: touchHeight,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          activeTrackColor: scheme.primary.withValues(alpha: 0.55),
          inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.16),
          thumbColor: Colors.white,
          thumbShape: const _PillThumbShape(),
          overlayShape: SliderComponentShape.noOverlay,
          tickMarkShape: SliderTickMarkShape.noTickMark,
          showValueIndicator: ShowValueIndicator.never,
          trackShape: const RoundedRectSliderTrackShape(),
        ),
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          onChangeStart: onChangeStart,
          onChangeEnd: onChangeEnd,
          semanticFormatterCallback: semanticFormatter,
        ),
      ),
    );
  }
}

/// The white rounded-pill thumb with a soft shadow.
class _PillThumbShape extends SliderComponentShape {
  const _PillThumbShape();

  static const Size _size = Size(30, 20);

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => _size;

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final pill = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: _size.width, height: _size.height),
      Radius.circular(_size.height / 2),
    );
    canvas.drawShadow(Path()..addRRect(pill), const Color(0xFF000000), 3, true);
    canvas.drawRRect(pill, Paint()..color = sliderTheme.thumbColor ?? Colors.white);
    // A hairline keeps the white pill visible on a pale card.
    canvas.drawRRect(
      pill,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = const Color(0x1F000000),
    );
  }
}

/// A labelled slider row of the settings panel: the label on the left, the
/// value on the right (between two circled minus / plus steppers when
/// [steppers] is true), and the slider under them.
///
/// With [commitOnRelease] a drag only moves the thumb and the value text;
/// [onChanged] is called once when the finger lifts (one drag, one undo
/// step). Stepper taps and keyboard / accessibility changes always commit at
/// once.
class InkValueSlider extends StatefulWidget {
  const InkValueSlider({
    super.key,
    required this.id,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.decimals = 1,
    this.format,
    this.steppers = true,
    this.commitOnRelease = false,
  });

  /// Names the parts for tests and tooling: the slider is
  /// `ink-settings-<id>`, the steppers `ink-settings-<id>-minus` and
  /// `ink-settings-<id>-plus`.
  final String id;
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  /// Decimal places of the values this slider produces (1 = steps of 0.1).
  final int decimals;

  /// The text of a value; the default is [decimals] decimal places.
  final String Function(double value)? format;

  /// Show the circled minus / plus (steps of 0.1) around the value.
  final bool steppers;
  final bool commitOnRelease;

  @override
  State<InkValueSlider> createState() => _InkValueSliderState();
}

class _InkValueSliderState extends State<InkValueSlider> {
  /// The value under the thumb while a drag is in progress and
  /// [InkValueSlider.commitOnRelease] holds the commit back.
  double? _held;
  bool _dragging = false;

  // A range that is not a number is an empty one (a disabled slider).
  double get _lo => widget.min.isFinite ? widget.min : 0;
  double get _hi => widget.max.isFinite ? math.max(_lo, widget.max) : _lo;

  String _text(double v) =>
      widget.format?.call(v) ?? v.toStringAsFixed(widget.decimals);

  double _inRange(double v) => v.isFinite ? v.clamp(_lo, _hi).toDouble() : _lo;

  void _onDragStart(double _) => _dragging = true;

  void _onChanged(double v) {
    final rounded = roundToDecimals(v, widget.decimals);
    if (widget.commitOnRelease && _dragging) {
      setState(() => _held = rounded);
    } else {
      widget.onChanged(rounded);
    }
  }

  void _onDragEnd(double v) {
    _dragging = false;
    final held = _held;
    if (held == null) return;
    // Commit first, then drop the held value, so the next frame already shows
    // what the commit changed. Dragging back to where it started commits
    // nothing (no empty undo step).
    if (held != widget.value) widget.onChanged(held);
    setState(() => _held = null);
  }

  void _step(int direction) {
    final next = stepTenth(widget.value, direction, min: _lo, max: _hi);
    if (next != widget.value) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final shown = _held ?? widget.value;
    final range = _hi - _lo;
    final divisions = (range * math.pow(10, widget.decimals)).round();
    final lower = widget.label.toLowerCase();
    final valueText = Text(
      _text(shown.isFinite ? shown : _lo),
      style: style,
      maxLines: 1,
      textAlign: widget.steppers ? TextAlign.center : TextAlign.end,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.steppers) ...[
              InkStepButton(
                key: ValueKey('ink-settings-${widget.id}-minus'),
                icon: Icons.remove,
                tooltip: 'Decrease $lower',
                onPressed: widget.value > _lo ? () => _step(-1) : null,
              ),
              SizedBox(
                width: 44,
                child: FittedBox(fit: BoxFit.scaleDown, child: valueText),
              ),
              InkStepButton(
                key: ValueKey('ink-settings-${widget.id}-plus'),
                icon: Icons.add,
                tooltip: 'Increase $lower',
                onPressed: widget.value < _hi ? () => _step(1) : null,
              ),
            ] else
              valueText,
          ],
        ),
        InkSlider(
          key: ValueKey('ink-settings-${widget.id}'),
          value: _inRange(shown),
          min: _lo,
          max: _hi,
          divisions: divisions > 0 ? divisions : null,
          onChanged: range > 0 ? _onChanged : null,
          onChangeStart: _onDragStart,
          onChangeEnd: _onDragEnd,
          semanticFormatter: (v) => '${widget.label} ${_text(v)}',
        ),
      ],
    );
  }
}
