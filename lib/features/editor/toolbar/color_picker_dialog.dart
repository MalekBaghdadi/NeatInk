import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'toolbar_widgets.dart';

/// Ready colours at the top of the picker (v1.13.0): four rows of ten, dark
/// to light, so most choices are one tap; mixing your own is below them.
const List<int> pickerPalette = [
  // Dark
  0xFF000000, 0xFF424242, 0xFFB71C1C, 0xFFE65100, 0xFF5D4037,
  0xFF1B5E20, 0xFF004D40, 0xFF0D47A1, 0xFF1A237E, 0xFF4A148C,
  // Strong
  0xFF757575, 0xFFE53935, 0xFFFB8C00, 0xFFFDD835, 0xFF7CB342,
  0xFF43A047, 0xFF00ACC1, 0xFF1E88E5, 0xFF5E35B1, 0xFFD81B60,
  // Bright
  0xFFFFFFFF, 0xFFFF7043, 0xFFFFB300, 0xFFFFEB3B, 0xFFC6FF00,
  0xFF26A69A, 0xFF4FC3F7, 0xFF3949AB, 0xFF8E24AA, 0xFFC2185B,
  // Light
  0xFFBDBDBD, 0xFFEF9A9A, 0xFFFFCC80, 0xFFFFF59D, 0xFFC5E1A5,
  0xFFA5D6A7, 0xFF80DEEA, 0xFF90CAF9, 0xFFB39DDB, 0xFFF48FB1,
];

/// Shows the colour picker: ready colours, then a saturation/value square,
/// a hue bar and a hex field to mix any colour, and the recently used
/// custom colours. Returns the chosen opaque ARGB colour, or null when
/// cancelled.
Future<int?> showColorPickerDialog(
  BuildContext context, {
  required int initialColor,
  List<int> recentColors = const [],
  String title = 'Choose a colour',
}) =>
    showDialog<int>(
      context: context,
      builder: (_) => _ColorPickerDialog(
        initialColor: initialColor,
        recentColors: recentColors,
        title: title,
      ),
    );

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.initialColor,
    required this.recentColors,
    required this.title,
  });

  final int initialColor;
  final List<int> recentColors;
  final String title;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv =
      HSVColor.fromColor(Color(widget.initialColor).withValues(alpha: 1));
  late final TextEditingController _hex =
      TextEditingController(text: hexOf(_argb));
  final FocusNode _hexFocus = FocusNode();

  int get _argb => _hsv.toColor().toARGB32() | 0xFF000000;

  @override
  void dispose() {
    _hex.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  void _set(HSVColor hsv, {bool fromHexField = false}) {
    setState(() => _hsv = hsv);
    if (!fromHexField) _hex.text = hexOf(_argb);
  }

  void _onHexChanged(String text) {
    final argb = parseHexColor(text);
    if (argb == null) return;
    // Keep the hue when a grey is typed (its hue is undefined).
    var hsv = HSVColor.fromColor(Color(argb));
    if (hsv.saturation == 0 || hsv.value == 0) hsv = hsv.withHue(_hsv.hue);
    _set(hsv, fromHexField: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final c in pickerPalette)
                    _PaletteDot(
                      key: ValueKey('palette-${hexOf(c)}'),
                      color: c,
                      selected: c == _argb,
                      onTap: () => _set(HSVColor.fromColor(Color(c))),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Or mix your own', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SaturationValueBox(value: _hsv, onChanged: _set, height: 150),
              const SizedBox(height: 16),
              HueBar(value: _hsv, onChanged: _set),
              const SizedBox(height: 16),
              Row(
                children: [
                  _ColorComparison(
                      before: widget.initialColor | 0xFF000000, after: _argb),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _hex,
                      focusNode: _hexFocus,
                      decoration: const InputDecoration(
                        labelText: 'Hex',
                        prefixText: '#',
                        isDense: true,
                      ),
                      maxLength: 6,
                      buildCounter: (_,
                              {required currentLength,
                              required isFocused,
                              maxLength}) =>
                          null,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp('[0-9a-fA-F]')),
                      ],
                      textCapitalization: TextCapitalization.characters,
                      onChanged: _onHexChanged,
                    ),
                  ),
                ],
              ),
              if (widget.recentColors.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Recent', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Wrap(
                  children: [
                    for (final c in widget.recentColors)
                      ColorSwatchButton(
                        color: c,
                        selected: c == _argb,
                        onPressed: () => _set(HSVColor.fromColor(Color(c))),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_argb),
          child: const Text('Use colour'),
        ),
      ],
    );
  }
}

/// One ready colour of [pickerPalette].
class _PaletteDot extends StatelessWidget {
  const _PaletteDot({super.key, required this.color, required this.selected, required this.onTap});

  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: colorName(color),
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Color(color),
            shape: BoxShape.circle,
            border: Border.all(
              width: selected ? 3 : 1,
              color: selected ? scheme.primary : scheme.outline.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// `RRGGBB` of [argb] (alpha dropped), upper case.
String hexOf(int argb) =>
    (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

/// Parses `RRGGBB` (optionally with `#`) to an opaque ARGB colour, or null
/// when it isn't exactly six hex digits.
int? parseHexColor(String text) {
  final t = text.trim().replaceFirst('#', '');
  if (t.length != 6) return null;
  final v = int.tryParse(t, radix: 16);
  return v == null ? null : 0xFF000000 | v;
}

/// The saturation (x) / value (y) square for the current hue. Drag or tap
/// to pick.
class SaturationValueBox extends StatelessWidget {
  const SaturationValueBox({
    super.key,
    required this.value,
    required this.onChanged,
    this.height = 180,
  });

  final HSVColor value;
  final ValueChanged<HSVColor> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, height);
          void pick(Offset p) {
            final s = (p.dx / size.width).clamp(0.0, 1.0);
            final v = 1 - (p.dy / size.height).clamp(0.0, 1.0);
            onChanged(value.withSaturation(s).withValue(v));
          }

          return Semantics(
            label: 'Saturation and brightness',
            child: GestureDetector(
              onPanDown: (d) => pick(d.localPosition),
              onPanUpdate: (d) => pick(d.localPosition),
              child: CustomPaint(
                size: size,
                painter: _SaturationValuePainter(value),
              ),
            ),
          );
        },
      );
}

class _SaturationValuePainter extends CustomPainter {
  _SaturationValuePainter(this.color);

  final HSVColor color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
        rect, Paint()..color = HSVColor.fromAHSV(1, color.hue, 1, 1).toColor());
    // White → transparent left to right adds saturation; transparent →
    // black top to bottom lowers the value.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xFF000000)],
        ).createShader(rect),
    );
    canvas.restore();
    final thumb = Offset(
        color.saturation * size.width, (1 - color.value) * size.height);
    _paintThumb(canvas, thumb, color.toColor());
  }

  @override
  bool shouldRepaint(_SaturationValuePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The hue bar: a horizontal rainbow. Drag or tap to pick the hue.
class HueBar extends StatelessWidget {
  const HueBar({
    super.key,
    required this.value,
    required this.onChanged,
    this.height = 28,
  });

  final HSVColor value;
  final ValueChanged<HSVColor> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          void pick(Offset p) {
            final hue = (p.dx / width).clamp(0.0, 1.0) * 360;
            // 360° is the same hue as 0°, and HSVColor rejects 360.
            onChanged(value.withHue(hue >= 360 ? 359.999 : hue));
          }

          return Semantics(
            label: 'Hue',
            child: GestureDetector(
              onPanDown: (d) => pick(d.localPosition),
              onPanUpdate: (d) => pick(d.localPosition),
              child: CustomPaint(
                size: Size(width, height),
                painter: _HuePainter(value),
              ),
            ),
          );
        },
      );
}

class _HuePainter extends CustomPainter {
  _HuePainter(this.color);

  final HSVColor color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2)),
      Paint()
        ..shader = LinearGradient(colors: [
          for (var h = 0; h <= 360; h += 60)
            HSVColor.fromAHSV(1, h == 360 ? 359.999 : h.toDouble(), 1, 1)
                .toColor(),
        ]).createShader(rect),
    );
    _paintThumb(
      canvas,
      Offset(color.hue / 360 * size.width, size.height / 2),
      HSVColor.fromAHSV(1, color.hue, 1, 1).toColor(),
    );
  }

  @override
  bool shouldRepaint(_HuePainter oldDelegate) => oldDelegate.color != color;
}

void _paintThumb(Canvas canvas, Offset center, Color fill) {
  canvas.drawCircle(center, 11, Paint()..color = const Color(0x40000000));
  canvas.drawCircle(center, 10, Paint()..color = const Color(0xFFFFFFFF));
  canvas.drawCircle(center, 7.5, Paint()..color = fill);
}

/// The previous colour next to the new one.
class _ColorComparison extends StatelessWidget {
  const _ColorComparison({required this.before, required this.after});

  final int before;
  final int after;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return Tooltip(
      message: 'Previous and new colour',
      child: Container(
        width: 64,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: outline.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          // Childless boxes take only the height they are made to.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ColoredBox(color: Color(before))),
            Expanded(child: ColoredBox(color: Color(after))),
          ],
        ),
      ),
    );
  }
}
