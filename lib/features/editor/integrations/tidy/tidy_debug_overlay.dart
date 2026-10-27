import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../beautify/beautify.dart';
import '../../../../ink/ink_rect.dart';
import '../../../settings/settings_controller.dart';

/// What the debug overlay remembers about a tidied word.
class TidyDebugWord {
  const TidyDebugWord({
    required this.wordId,
    required this.features,
    required this.strokeCenters,
  });

  final String wordId;
  final WordFeatures features;

  /// Centre of each stroke's box as written, by stroke id (for the class
  /// dots).
  final Map<String, ({double x, double y})> strokeCenters;
}

/// The developer overlay of spec "Debug overlay": for recently tidied words,
/// the detected baseline (blue), x-height line (green), slant line (orange)
/// and bounding box (grey) in the ink as written, the same after tidying
/// (thin), stroke classes as coloured dots, and the numbers θ, φ, x-height
/// and scale k. Only built when the "debug overlay" setting is on.
class TidyDebugLayer extends ConsumerWidget {
  const TidyDebugLayer({super.key, required this.words});

  final List<TidyDebugWord> words;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(settingsProvider.select((s) => s.debugOverlay));
    if (!on || words.isEmpty) return const SizedBox.shrink();
    return RepaintBoundary(
      child: CustomPaint(
        key: const ValueKey('tidy-debug-overlay'),
        painter: TidyDebugPainter(words),
      ),
    );
  }
}

class TidyDebugPainter extends CustomPainter {
  TidyDebugPainter(this.words);

  final List<TidyDebugWord> words;

  static const Color baselineColor = Color(0xFF1E66F5);
  static const Color xHeightColor = Color(0xFF2EA043);
  static const Color slantColor = Color(0xFFF08A24);
  static const Color boxColor = Color(0xFF8A8F98);

  static Color classColor(StrokeClass c) => switch (c) {
        StrokeClass.core => const Color(0xFF1E66F5),
        StrokeClass.tall => const Color(0xFFD62C8B),
        StrokeClass.descender => const Color(0xFF8250DF),
        StrokeClass.mark => const Color(0xFFE5A100),
      };

  @override
  void paint(Canvas canvas, Size size) {
    for (final w in words) {
      _paintWord(canvas, w);
    }
  }

  void _paintWord(Canvas canvas, TidyDebugWord w) {
    final f = w.features;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..isAntiAlias = true;
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.35
      ..isAntiAlias = true;

    void seg(Seg s, Paint p, Color c) {
      p.color = c;
      canvas.drawLine(Offset(s.a.x, s.a.y), Offset(s.b.x, s.b.y), p);
    }

    void box(InkRect r, Paint p) {
      p.color = boxColor;
      canvas.drawRect(Rect.fromLTRB(r.left, r.top, r.right, r.bottom), p);
    }

    // As written.
    box(f.bounds, line);
    seg(f.baseline, line, baselineColor);
    seg(f.xHeightLine, line, xHeightColor);
    seg(f.slantLine, line, slantColor);
    // As tidied.
    box(f.tidiedBounds, thin);
    seg(f.tidiedBaseline, thin, baselineColor);
    seg(f.tidiedXHeightLine, thin, xHeightColor);

    final dot = Paint()..style = PaintingStyle.fill;
    f.strokeClasses.forEach((id, cls) {
      final c = w.strokeCenters[id];
      if (c == null) return;
      dot.color = classColor(cls);
      canvas.drawCircle(Offset(c.x, c.y), 1.6, dot);
    });

    String deg(double rad) => (rad * 180 / math.pi).toStringAsFixed(1);
    final text = 'θ ${deg(f.skew)}°  φ ${deg(f.slant)}°  '
        'x ${f.xHeight.toStringAsFixed(1)}  k ${f.scale.toStringAsFixed(2)}'
        '${f.snapped ? '  snap' : ''}';
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFF444B55),
          fontSize: 5,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(f.bounds.left, f.bounds.top - tp.height - 1));
    tp.dispose();
  }

  @override
  bool shouldRepaint(TidyDebugPainter old) => !identical(old.words, words);
}
