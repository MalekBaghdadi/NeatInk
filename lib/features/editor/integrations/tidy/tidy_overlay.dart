import 'package:flutter/widgets.dart';

import 'tidy_animation.dart';
import 'tidy_debug_overlay.dart';

/// Everything tidy puts over one page: the animation of the word being
/// tidied and the developer debug overlay. Never takes pointer events.
class TidyPageOverlay extends StatelessWidget {
  const TidyPageOverlay({
    super.key,
    required this.changes,
    required this.animation,
    required this.words,
  });

  /// Notifies when the animation starts / ends or a word was tidied.
  final Listenable changes;
  final TidyAnimation? Function() animation;
  final List<TidyDebugWord> Function() words;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ListenableBuilder(
          listenable: changes,
          builder: (context, _) {
            final anim = animation();
            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                if (anim != null)
                  TidyAnimationLayer(key: ObjectKey(anim), animation: anim),
                TidyDebugLayer(words: words()),
              ],
            );
          },
        ),
      );
}
