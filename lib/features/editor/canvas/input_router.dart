import 'package:flutter/gestures.dart';

/// What a new pointer is used for.
enum PointerIntent {
  /// Use the current tool (pen, highlighter, eraser, lasso...).
  tool,

  /// The stylus eraser end or barrel button: route to the eraser.
  eraser,

  /// Scroll / pan / pinch-zoom.
  navigate,

  /// Ignore for the pointer's whole lifetime (palm rejection).
  ignore,
}

/// True for pen-type pointers.
bool isStylusKind(PointerDeviceKind kind) =>
    kind == PointerDeviceKind.stylus ||
    kind == PointerDeviceKind.invertedStylus;

/// Maps a device pressure reading to [0, 1].
///
/// Pens report pressure within [pressureMin, pressureMax] (Android: usually
/// 0..1, but some digitizers use other ranges). Touch and mouse "pressure"
/// is meaningless (contact size, or a constant 1.0), so they get a flat 0.5,
/// which makes the stroke renderer simulate pressure from speed instead.
/// A pen that reports no usable range also gets 0.5.
///
/// Android normalises pen pressure to about 0..1, but some devices report
/// the range in raw sensor units (0..4096) while the readings are already
/// 0..1: dividing by that range made every reading about 0, a pen that
/// "never changes pressure". A reading of at most [_normalisedCeiling] with
/// such a range is taken as already normalised (v1.8.0).
double normalizePressure({
  required PointerDeviceKind kind,
  required double pressure,
  required double pressureMin,
  required double pressureMax,
}) {
  if (!isStylusKind(kind)) return 0.5;
  final range = pressureMax - pressureMin;
  if (!pressure.isFinite || !range.isFinite || range <= 1e-6) return 0.5;
  if (range > _rawRangeAbove && pressure >= 0 && pressure <= _normalisedCeiling) {
    return pressure.clamp(0.0, 1.0).toDouble();
  }
  return ((pressure - pressureMin) / range).clamp(0.0, 1.0).toDouble();
}

/// A pressure range wider than this is in raw sensor units.
const double _rawRangeAbove = 4;

/// Android readings go a little over 1 on a hard press.
const double _normalisedCeiling = 1.5;

/// [normalizePressure] for a pointer event.
double normalizedPressureOf(PointerEvent e) => normalizePressure(
      kind: e.kind,
      pressure: e.pressure,
      pressureMin: e.pressureMin,
      pressureMax: e.pressureMax,
    );

/// Decides what each new pointer does, including palm rejection.
///
/// Rules (CLAUDE.md "Input handling"):
/// * The pen draws with the current tool; its eraser end (inverted stylus)
///   or barrel button erases when [stylusButtonErases] is on.
/// * Fingers navigate, unless [drawWithFinger] is on: then the first finger
///   uses the tool and further fingers navigate.
/// * The mouse draws with the primary button and pans with the others
///   (useful on the emulator).
/// * Palm rejection: while a pen is down or hovering, and for
///   [palmRejectionWindow] after its last event, new touches are ignored
///   entirely: they neither draw nor pan/zoom. Once a pen has been used, a
///   touch that lands while a rejected one (the resting palm) is still down
///   is ignored too ([classifyDown]'s `palmResting`).
///
/// Times are pointer event timestamps (one monotonic clock per device).
class InputRouter {
  InputRouter({
    this.palmRejectionWindow = const Duration(milliseconds: 1000),
  });

  // v1.6.0: 300 ms let the hand scroll the page between words and lines
  // (Mariam: "the screen is moving as much my hand moves"); the palm lands
  // again well after the pen lifted.

  final Duration palmRejectionWindow;

  bool drawWithFinger = false;
  bool stylusButtonErases = true;

  final Set<int> _stylusDown = {};
  Duration? _lastStylusEvent;

  /// True while any pen pointer is in contact.
  bool get stylusDown => _stylusDown.isNotEmpty;

  /// True once a pen has been seen (since the last [reset]).
  bool get penUsed => _lastStylusEvent != null;

  /// Feeds every pointer event (including hover) so pen activity is known.
  void observe(PointerEvent e) {
    if (!isStylusKind(e.kind)) return;
    _lastStylusEvent = e.timeStamp;
    if (e is PointerDownEvent) {
      _stylusDown.add(e.pointer);
    } else if (e is PointerUpEvent || e is PointerCancelEvent) {
      _stylusDown.remove(e.pointer);
    }
  }

  /// Whether a touch at [time] must be ignored because the pen is active
  /// or was active within [palmRejectionWindow].
  bool rejectsTouchAt(Duration time) {
    if (_stylusDown.isNotEmpty) return true;
    final last = _lastStylusEvent;
    if (last == null) return false;
    final since = time - last;
    // A negative difference (clock oddities) counts as "just now".
    return since < palmRejectionWindow;
  }

  /// Classifies a new pointer. [touchInUse] is true when another touch
  /// pointer is already using the tool or navigating; [palmResting] when a
  /// touch that was rejected as a palm is still down.
  PointerIntent classifyDown({
    required PointerDeviceKind kind,
    required int buttons,
    required Duration timeStamp,
    bool touchInUse = false,
    bool palmResting = false,
  }) {
    switch (kind) {
      case PointerDeviceKind.stylus:
        if (stylusButtonErases && buttons & kPrimaryStylusButton != 0) {
          return PointerIntent.eraser;
        }
        return PointerIntent.tool;
      case PointerDeviceKind.invertedStylus:
        return stylusButtonErases ? PointerIntent.eraser : PointerIntent.tool;
      case PointerDeviceKind.touch:
      case PointerDeviceKind.unknown:
        if (rejectsTouchAt(timeStamp)) return PointerIntent.ignore;
        if (palmResting && penUsed) return PointerIntent.ignore;
        if (drawWithFinger && !touchInUse) return PointerIntent.tool;
        return PointerIntent.navigate;
      case PointerDeviceKind.mouse:
        return buttons & kPrimaryMouseButton != 0
            ? PointerIntent.tool
            : PointerIntent.navigate;
      case PointerDeviceKind.trackpad:
        return PointerIntent.navigate;
    }
  }

  /// Forgets all pointer state (e.g. when the view is rebuilt).
  void reset() {
    _stylusDown.clear();
    _lastStylusEvent = null;
  }
}
