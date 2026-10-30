import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// One stop of a guided tour (v1.12.0): the screen dims, [target] (the
/// `ValueKey<String>` of a button on screen) shows through a lit cut-out,
/// and a card next to it says what it is ([title]) and what it does
/// ([text]). Without a target the card sits in the middle (a welcome or a
/// last word). With [prefix] every widget whose key starts with [target] is
/// lit together (all the pen colours).
class TourStep {
  const TourStep({this.target, this.prefix = false, required this.title, required this.text, this.icon});

  final String? target;
  final bool prefix;
  final String title;
  final String text;
  final IconData? icon;
}

/// Shows [steps] one after the other over the current screen; returns when
/// the user finished or skipped it. Steps whose button is not on screen
/// (not built here, scrolled away) are left out.
Future<void> showTour(BuildContext context, List<TourStep> steps) {
  final shown = [
    for (final s in steps)
      if (s.target == null || findTourTarget(s) != null) s,
  ];
  if (shown.isEmpty) return Future.value();
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (context, _, _) => TourOverlay(steps: shown),
    transitionsBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
  ));
}

/// Where [step]'s button is on screen (global coordinates), or null when it
/// is not showing.
Rect? findTourTarget(TourStep step) {
  final target = step.target;
  if (target == null) return null;
  Rect? found;
  void visit(Element e) {
    final key = e.widget.key;
    if (key is ValueKey<String> &&
        (step.prefix ? key.value.startsWith(target) : key.value == target) &&
        (step.prefix || found == null)) {
      final box = e.renderObject;
      if (box is RenderBox && box.attached && box.hasSize && _onScreen(box)) {
        final rect = box.localToGlobal(Offset.zero) & box.size;
        found = found == null ? rect : found!.expandToInclude(rect);
      }
    }
    e.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return found;
}

/// Painted (not inside an offstage route or an [Offstage]) and of some size.
bool _onScreen(RenderBox box) {
  if (box.size.isEmpty) return false;
  RenderObject? o = box;
  while (o != null) {
    if (o is RenderOffstage && o.offstage) return false;
    o = o.parent;
  }
  return true;
}

/// The tour's screen: the dim layer with the lit cut-out, and the card.
class TourOverlay extends StatefulWidget {
  const TourOverlay({super.key, required this.steps});

  final List<TourStep> steps;

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay> {
  int _index = 0;

  /// The lit button, in this overlay's coordinates. Measured outside build
  /// (the element tree cannot be walked while it is being built): when a
  /// step is chosen, and after a frame whose size changed (rotation).
  Rect? _target;
  Size? _measuredSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize ? box.localToGlobal(Offset.zero) : Offset.zero;
    final size = box != null && box.hasSize ? box.size : null;
    var target = findTourTarget(widget.steps[_index])?.shift(-origin).inflate(6);
    if (target != null && size != null) {
      // Kept inside the screen, so the ring of a button at its edge shows.
      target = Rect.fromLTRB(math.max(target.left, 3), math.max(target.top, 3), math.min(target.right, size.width - 3),
          math.min(target.bottom, size.height - 3));
    }
    _measuredSize = size;
    if (target != _target) setState(() => _target = target);
  }

  void _go(int i) {
    if (i >= widget.steps.length) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _index = i.clamp(0, widget.steps.length - 1));
    _measure();
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_index];
    return PopScope(
      canPop: true,
      child: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        if (size != _measuredSize) WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        final target = _target;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // A tap anywhere moves on, like Next.
                onTap: () => _go(_index + 1),
                child: CustomPaint(painter: _DimPainter(hole: target)),
              ),
            ),
            _placeCard(
              size,
              target,
              _TourCard(
                key: ValueKey('tour-card-$_index'),
                step: step,
                index: _index,
                count: widget.steps.length,
                onBack: _index > 0 ? () => _go(_index - 1) : null,
                onNext: () => _go(_index + 1),
                onSkip: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        );
      }),
    );
  }

  /// The card below the lit button when there is room, else above it, else
  /// in the middle; never wider than 420.
  Widget _placeCard(Size size, Rect? target, Widget card) {
    const margin = 16.0;
    final width = math.min(420.0, size.width - 2 * margin);
    if (target == null) {
      return Center(child: SizedBox(width: width, child: card));
    }
    final left = (target.center.dx - width / 2).clamp(margin, math.max(margin, size.width - width - margin)).toDouble();
    final below = target.bottom + 12;
    final roomBelow = size.height - below;
    final roomAbove = target.top - 12;
    if (roomBelow >= 220 || roomBelow >= roomAbove) {
      return Positioned(left: left, top: below, width: width, child: card);
    }
    return Positioned(left: left, bottom: size.height - roomAbove, width: width, child: card);
  }
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    super.key,
    required this.step,
    required this.index,
    required this.count,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
  });

  final TourStep step;
  final int index;
  final int count;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = index == count - 1;
    return Material(
      elevation: 8,
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (step.icon != null) ...[
                  Icon(step.icon, color: scheme.primary),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(step.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Text('${index + 1} of $count', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(step.text, style: const TextStyle(fontSize: 15.5, height: 1.4)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(key: const ValueKey('tour-skip'), onPressed: onSkip, child: Text(last ? 'Close' : 'Skip tour')),
                const Spacer(),
                if (onBack != null) TextButton(key: const ValueKey('tour-back'), onPressed: onBack, child: const Text('Back')),
                const SizedBox(width: 4),
                FilledButton(
                  key: const ValueKey('tour-next'),
                  onPressed: onNext,
                  child: Text(last ? 'Done' : 'Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DimPainter extends CustomPainter {
  _DimPainter({required this.hole});

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = const Color(0xB3000000);
    final screen = Path()..addRect(Offset.zero & size);
    final h = hole;
    if (h == null) {
      canvas.drawPath(screen, dim);
      return;
    }
    final cut = RRect.fromRectAndRadius(h, const Radius.circular(14));
    canvas.drawPath(Path.combine(PathOperation.difference, screen, Path()..addRRect(cut)), dim);
    canvas.drawRRect(
      cut,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        // White shows on the dim layer in light and dark mode alike.
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.hole != hole;
}
