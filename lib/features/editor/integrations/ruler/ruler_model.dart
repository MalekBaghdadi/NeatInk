import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';

import 'ruler_geometry.dart';

/// Where the ruler is and whether it is showing.
///
/// The ruler is not part of the notebook: it starts hidden every time the
/// editor opens, and the editor's widgets just listen to this.
class RulerModel extends ChangeNotifier {
  /// The first time the ruler shows it is centred sideways, this far down the
  /// view (fraction of the height)...
  static const double initialHeightFraction = 0.38;

  /// ...and this long (fraction of the width), kept between the two bounds.
  static const double initialLengthFraction = 0.92;
  static const double minInitialLength = 360;
  static const double maxInitialLength = 1500;

  /// The shown angle snaps to a multiple of this many degrees when the ruler
  /// is turned to within [snapToleranceDegrees] of it.
  static const double snapStepDegrees = 15;
  static const double snapToleranceDegrees = 2.5;

  /// Used when asked to place the ruler before the view has a size.
  static const Size fallbackViewport = Size(1024, 768);

  bool _visible = false;
  bool _placed = false;
  Size _viewport = Size.zero;
  RulerGeometry _geometry =
      RulerGeometry(center: Offset.zero, length: minInitialLength);

  /// The ruler's turn as the fingers made it. [geometry]'s angle is this
  /// snapped to a multiple of [snapStepDegrees] when it is close; keeping the
  /// unsnapped value is what lets the ruler turn on through a snap instead of
  /// sticking to it.
  double _rawAngle = 0;

  bool get visible => _visible;

  /// The ruler's placement; it keeps its place while hidden.
  RulerGeometry get geometry => _geometry;

  /// The view size the ruler was last fitted to.
  Size get viewport => _viewport;

  /// Shows the ruler in a view of size [viewport]: at its default place the
  /// first time, where it was left after that.
  void show(Size viewport) {
    if (_visible) return;
    _visible = true;
    if (_placed) {
      _fit(viewport);
    } else {
      final size = _usable(viewport) ? viewport : fallbackViewport;
      _viewport = size;
      _geometry = _initialGeometry(size);
      _rawAngle = 0;
      _placed = true;
    }
    notifyListeners();
  }

  void hide() {
    if (!_visible) return;
    _visible = false;
    notifyListeners();
  }

  void toggle(Size viewport) => _visible ? hide() : show(viewport);

  /// Moves the ruler by [delta] pixels, keeping its centre inside the view.
  void translate(Offset delta) {
    if (!delta.dx.isFinite || !delta.dy.isFinite || delta == Offset.zero) {
      return;
    }
    _setGeometry(_geometry.copyWith(center: _keepInside(_geometry.center + delta)));
  }

  /// Turns the ruler by [radians] about its centre (positive is clockwise).
  void rotateBy(double radians) {
    if (!radians.isFinite || radians == 0) return;
    _rawAngle = math.atan2(math.sin(_rawAngle + radians), math.cos(_rawAngle + radians));
    _setGeometry(_geometry.copyWith(angle: snapAngle(_rawAngle)));
  }

  /// Adapts the ruler to a view that changed size (the tablet was turned):
  /// its centre stays in the view and it is never longer than the view is
  /// wide.
  void fit(Size viewport) {
    if (!_usable(viewport)) return;
    if (!_placed) {
      _viewport = viewport;
      return;
    }
    final before = _geometry;
    _fit(viewport);
    if (_geometry != before) notifyListeners();
  }

  /// [angle] (radians), or the nearest multiple of [snapStepDegrees] when it
  /// is within [snapToleranceDegrees] of one.
  static double snapAngle(double angle) {
    if (!angle.isFinite) return 0;
    const step = snapStepDegrees * math.pi / 180;
    const tolerance = snapToleranceDegrees * math.pi / 180;
    final nearest = (angle / step).round() * step;
    return (angle - nearest).abs() <= tolerance ? nearest : angle;
  }

  void _fit(Size viewport) {
    if (!_usable(viewport)) return;
    _viewport = viewport;
    _geometry = _geometry.copyWith(
      length: math.min(_geometry.length, viewport.width),
      center: _keepInside(_geometry.center),
    );
  }

  void _setGeometry(RulerGeometry next) {
    if (next == _geometry) return;
    _geometry = next;
    notifyListeners();
  }

  Offset _keepInside(Offset p) {
    if (!_usable(_viewport)) return p;
    return Offset(
      math.min(math.max(p.dx, 0.0), _viewport.width),
      math.min(math.max(p.dy, 0.0), _viewport.height),
    );
  }

  static RulerGeometry _initialGeometry(Size viewport) {
    final preferred = (viewport.width * initialLengthFraction)
        .clamp(minInitialLength, maxInitialLength)
        .toDouble();
    return RulerGeometry(
      center: Offset(viewport.width / 2, viewport.height * initialHeightFraction),
      length: math.min(preferred, viewport.width),
    );
  }

  static bool _usable(Size size) =>
      size.width.isFinite &&
      size.height.isFinite &&
      size.width > 0 &&
      size.height > 0;
}
