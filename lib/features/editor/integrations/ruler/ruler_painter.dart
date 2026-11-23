import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'ruler_geometry.dart';
import 'ruler_model.dart';

/// Logical pixels per centimetre of the ruler's scale: Android's 160 dpi
/// definition. Real screens differ from it by up to about 15%, so the ruler
/// is a drawing aid, not a measuring tool.
const double rulerPxPerCm = 160 / 2.54;

/// Draws the ruler like the one in the video: a nearly clear band whose two
/// long edges are centimetre scales, counting outward from the middle
/// (`9 8 7 … 1 | 1 2 3 … 9`), the bottom scale mirrored so it reads from the
/// other side, and a dotted badge with the angle in the middle.
///
/// It repaints when [model] changes and builds nothing per tick: the ticks
/// are one path, and the numbers are laid out once each.
class RulerPainter extends CustomPainter {
  RulerPainter({required this.model}) : super(repaint: model);

  final RulerModel model;

  static const double cornerRadius = 10;

  /// Tick lengths: every millimetre, every 5 mm, every centimetre.
  static const double mmTick = 6;
  static const double halfCmTick = 10;
  static const double cmTick = 16;

  static const double labelSize = 11;

  /// Gap between the long ticks and the numbers.
  static const double labelGap = 2;

  static const double badgeRadius = 16;
  static const int badgeDots = 24;

  static const double _mmPerCm = 10;

  final Map<int, TextPainter> _numbers = {};
  TextPainter? _badge;
  String? _badgeText;

  /// The ruler looks the same on every paper and in every theme: a frosted
  /// band with dark scales. (Colours taken from the theme would vanish on a
  /// dark page in the light theme, or the other way round.)
  static const Color bodyColor = Color(0x6BFFFFFF); // white, 42%
  static const Color borderColor = Color(0x47000000); // black, 28%
  static const Color inkColor = Color(0xD9262626); // near black, 85%

  /// Releases the laid-out text. Call when the painter is replaced.
  void dispose() {
    for (final p in _numbers.values) {
      p.dispose();
    }
    _numbers.clear();
    _badge?.dispose();
    _badge = null;
    _badgeText = null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!model.visible) return;
    final g = model.geometry;
    canvas.save();
    canvas.translate(g.center.dx, g.center.dy);
    canvas.rotate(g.angle);
    _paintBody(canvas, g);
    canvas.drawPath(
      _ticks(g),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = inkColor,
    );
    _paintNumbers(canvas, g);
    canvas.restore();
    // The badge is not turned with the ruler: it stays readable.
    _paintBadge(canvas, g);
  }

  void _paintBody(Canvas canvas, RulerGeometry g) {
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset.zero, width: g.length, height: g.thickness),
      const Radius.circular(cornerRadius),
    );
    canvas.drawRRect(
        body, Paint()..color = bodyColor);
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = borderColor,
    );
  }

  /// Every tick of both scales, in the ruler's own space (x along it, y
  /// across it, the middle at the origin), as one path.
  Path _ticks(RulerGeometry g) {
    final half = g.length / 2;
    final top = -g.thickness / 2, bottom = g.thickness / 2;
    final path = Path();
    void tick(double x, double length) {
      path
        ..moveTo(x, top)
        ..lineTo(x, top + length)
        ..moveTo(x, bottom)
        ..lineTo(x, bottom - length);
    }

    const pxPerMm = rulerPxPerCm / _mmPerCm;
    for (var mm = 0; mm * pxPerMm <= half; mm++) {
      final length = mm % 10 == 0
          ? cmTick
          : mm % 5 == 0
              ? halfCmTick
              : mmTick;
      tick(mm * pxPerMm, length);
      if (mm > 0) tick(-mm * pxPerMm, length);
    }
    return path;
  }

  void _paintNumbers(Canvas canvas, RulerGeometry g) {
    final half = g.length / 2;
    final top = -g.thickness / 2, bottom = g.thickness / 2;
    for (var cm = 1;; cm++) {
      final label = _number(cm);
      final x = cm * rulerPxPerCm;
      // Written so that a length that isn't a number ends the loop too.
      if (!(x + label.width / 2 <= half)) break;
      for (final side in const [-1.0, 1.0]) {
        // Upright, just inside the top edge...
        label.paint(
          canvas,
          Offset(side * x - label.width / 2, top + cmTick + labelGap),
        );
        // ...and turned half a turn just inside the bottom edge.
        canvas.save();
        canvas.translate(side * x,
            bottom - cmTick - labelGap - label.height / 2);
        canvas.rotate(math.pi);
        label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
        canvas.restore();
      }
    }
  }

  TextPainter _number(int cm) => _numbers.putIfAbsent(
      cm, () => _text('$cm', fontWeight: FontWeight.normal));

  void _paintBadge(Canvas canvas, RulerGeometry g) {
    final c = g.center;
    canvas.drawPoints(
      PointMode.points,
      [
        for (var i = 0; i < badgeDots; i++)
          c + Offset.fromDirection(2 * math.pi * i / badgeDots, badgeRadius),
      ],
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.6
        ..color = inkColor,
    );
    final text = angleLabel(g.displayAngleDegrees);
    if (text != _badgeText) {
      _badge?.dispose();
      _badge = _text(text, fontWeight: FontWeight.w600);
      _badgeText = text;
    }
    final badge = _badge!;
    badge.paint(canvas, c - Offset(badge.width / 2, badge.height / 2));
  }

  TextPainter _text(String text, {required FontWeight fontWeight}) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: inkColor,
            fontSize: labelSize,
            fontWeight: fontWeight,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  /// The badge's text: `0°`, `15°`, `37.5°`; no decimals for a whole angle.
  static String angleLabel(double degrees) {
    final whole = degrees == degrees.roundToDouble();
    return '${degrees.toStringAsFixed(whole ? 0 : 1)}°';
  }

  @override
  bool shouldRepaint(RulerPainter oldDelegate) =>
      !identical(oldDelegate.model, model);
}

/// The ruler over the document view: a screen overlay that ignores pointers
/// (fingers reach the ruler through the touch interceptor) and repaints only
/// when the ruler changes.
///
/// It also tells the model the size of the view, so a ruler that was longer
/// than the view is wide (after the tablet was turned) is fitted to it.
class RulerOverlay extends StatefulWidget {
  const RulerOverlay({super.key, required this.model});

  final RulerModel model;

  @override
  State<RulerOverlay> createState() => _RulerOverlayState();
}

class _RulerOverlayState extends State<RulerOverlay> {
  RulerPainter? _painter;

  @override
  void dispose() {
    _painter?.dispose();
    super.dispose();
  }

  RulerPainter _painterFor() {
    final old = _painter;
    if (old != null && identical(old.model, widget.model)) return old;
    old?.dispose();
    return _painter = RulerPainter(model: widget.model);
  }

  @override
  Widget build(BuildContext context) {
    final painter = _painterFor();
    return IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(builder: (context, constraints) {
          final size = constraints.biggest;
          if (size != widget.model.viewport) {
            // Layout may not notify listeners: fit once it is done.
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.model.fit(size);
            });
          }
          return CustomPaint(painter: painter, size: Size.infinite);
        }),
      ),
    );
  }
}
