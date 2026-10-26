import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'pointer_debug_log.dart';

/// Colour used for each input kind in the pointer test.
Color colorForPointerKind(PointerDeviceKind kind) => switch (kind) {
      PointerDeviceKind.stylus => const Color(0xFF3949AB),
      PointerDeviceKind.invertedStylus => const Color(0xFFE53935),
      PointerDeviceKind.touch => const Color(0xFF2E7D32),
      PointerDeviceKind.mouse => const Color(0xFF6D4C41),
      PointerDeviceKind.trackpad => const Color(0xFF00838F),
      PointerDeviceKind.unknown => const Color(0xFF8E24AA),
    };

/// Paints the recorded traces: colour by input kind, width by pressure,
/// plus a ring at the hover position whose size follows the hover distance.
class PointerTracePainter extends CustomPainter {
  PointerTracePainter(this.log) : super(repaint: log);

  final PointerDebugLog log;

  static const double minWidth = 1.0;
  static const double maxWidth = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final trace in log.traces) {
      paint.color = colorForPointerKind(trace.kind);
      final samples = trace.samples;
      if (samples.length == 1) {
        final s = samples.first;
        canvas.drawCircle(
          s.position,
          _width(s) / 2,
          Paint()..color = paint.color,
        );
        continue;
      }
      for (var i = 1; i < samples.length; i++) {
        final a = samples[i - 1], b = samples[i];
        // Average the two ends so width changes smoothly along the trace.
        paint.strokeWidth = (_width(a) + _width(b)) / 2;
        canvas.drawLine(a.position, b.position, paint);
      }
    }

    final last = log.last;
    if (last != null && last.type == 'hover') {
      final reach = last.distanceMax > 0
          ? (last.distance / last.distanceMax).clamp(0.0, 1.0)
          : 0.0;
      canvas.drawCircle(
        last.position,
        6 + 30 * reach,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = colorForPointerKind(last.kind).withValues(alpha: 0.7),
      );
    }
  }

  double _width(PointerSample s) =>
      minWidth + (maxWidth - minWidth) * s.normalizedPressure;

  @override
  bool shouldRepaint(PointerTracePainter oldDelegate) =>
      !identical(oldDelegate.log, log);
}
