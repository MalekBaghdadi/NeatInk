import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../../../ink/ink_point.dart';
import '../../../../ink/stroke.dart';
import '../../canvas/page_painting.dart' show paintStroke;

/// A word moving from the ink it was written with to its tidied points
/// (spec step 6). While it runs the committed layer does not paint these
/// strokes (`EditorExtensions.hiddenStrokeIds`); the overlay draws them.
class TidyAnimation {
  TidyAnimation({
    required this.before,
    required this.after,
    required this.durationMs,
  }) : assert(before.length == after.length);

  /// The strokes as written, and as tidied (same ids, same point counts).
  final List<Stroke> before;
  final List<Stroke> after;
  final int durationMs;

  /// The strokes at animation progress [t] in [0, 1], eased out.
  List<Stroke> at(double t) {
    final e = easeOut(t);
    return [
      for (var i = 0; i < after.length; i++) _lerp(before[i], after[i], e),
    ];
  }

  /// Cubic ease-out.
  static double easeOut(double t) {
    final u = 1 - t.clamp(0.0, 1.0);
    return 1 - u * u * u;
  }

  static Stroke _lerp(Stroke a, Stroke b, double e) {
    final pa = a.points;
    final pb = b.points;
    if (pa.length != pb.length) return e < 1 ? a : b;
    return b.copyWith(points: [
      for (var k = 0; k < pb.length; k++)
        InkPoint(
          pa[k].x + (pb[k].x - pa[k].x) * e,
          pa[k].y + (pb[k].y - pa[k].y) * e,
          pb[k].pressure,
          pb[k].t,
        ),
    ]);
  }
}

/// Draws a [TidyAnimation] frame by frame on the page overlay.
class TidyAnimationLayer extends StatefulWidget {
  const TidyAnimationLayer({super.key, required this.animation});

  final TidyAnimation animation;

  @override
  State<TidyAnimationLayer> createState() => _TidyAnimationLayerState();
}

class _TidyAnimationLayerState extends State<TidyAnimationLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _progress = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    final ms = widget.animation.durationMs <= 0 ? 1 : widget.animation.durationMs;
    _ticker = createTicker((elapsed) {
      _progress.value = (elapsed.inMicroseconds / 1000 / ms).clamp(0.0, 1.0);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          key: const ValueKey('tidy-animation'),
          painter: _AnimationPainter(widget.animation, _progress),
        ),
      );
}

class _AnimationPainter extends CustomPainter {
  _AnimationPainter(this.animation, this.progress) : super(repaint: progress);

  final TidyAnimation animation;
  final ValueListenable<double> progress;

  final Paint _paint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final s in animation.at(progress.value)) {
      paintStroke(canvas, s, _paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AnimationPainter old) =>
      !identical(old.animation, animation);
}
