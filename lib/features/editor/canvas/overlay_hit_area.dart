import 'package:flutter/widgets.dart';

import '../editor_controller.dart';

/// Wraps a control shown over the pages (an autocorrect bubble, a chip).
/// The document view listens to every pointer under it, including those on
/// its overlays, and handles them before the control's buttons see the tap:
/// a pen tap on a button drew a dot or closed the bubble it was on (v1.9.0).
/// Pointers that land on [child] belong to it.
class OverlayHitArea extends StatelessWidget {
  const OverlayHitArea({super.key, required this.controller, required this.child});

  final EditorController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (e) => controller.inputRouter.claimForOverlay(e.pointer),
        child: child,
      );
}
