import 'package:flutter/gestures.dart';

import '../../editor_extensions.dart';
import 'ruler_geometry.dart';
import 'ruler_gesture.dart';
import 'ruler_model.dart';

/// Lets fingers move and turn the ruler instead of scrolling the page.
///
/// * A finger that lands on the ruler body (a few pixels of slop around it)
///   drags it. While that finger is down, a second finger landing anywhere
///   joins it and turns the ruler as well; a third finger is not claimed.
/// * While the app draws with fingers, the band along each edge is left to
///   the tool: a finger there draws a line along the edge (see
///   `RulerEdgeConstraint`) instead of moving the ruler.
/// * A hidden ruler claims nothing.
class RulerTouchInterceptor implements TouchInterceptor {
  RulerTouchInterceptor(this.model);

  /// How far outside the ruler body (pixels) a finger still grabs it.
  static const double bodySlop = 14;

  final RulerModel model;
  final RulerGesture _gesture = RulerGesture();

  @override
  bool onPointerDown(PointerDownEvent e, {required bool fingerDraws}) {
    if (!model.visible) return false;
    final position = e.localPosition;
    // A finger joining a ruler gesture that is running is claimed wherever
    // it lands; otherwise it has to land on the ruler.
    if (!_gesture.isActive && !_grabs(position, fingerDraws)) return false;
    return _gesture.add(e.pointer, position);
  }

  bool _grabs(Offset position, bool fingerDraws) {
    final geometry = model.geometry;
    if (!geometry.containsPoint(position, bodySlop)) return false;
    return !(fingerDraws &&
        geometry.nearestEdge(position, rulerSnapDistance) != null);
  }

  @override
  void onPointerMove(PointerMoveEvent e) {
    final step = _gesture.move(e.pointer, e.localPosition);
    if (step == null) return;
    model.translate(step.translation);
    model.rotateBy(step.rotation);
  }

  @override
  void onPointerUp(PointerUpEvent e) => _gesture.remove(e.pointer);

  @override
  void onPointerCancel(PointerCancelEvent e) => _gesture.remove(e.pointer);
}
