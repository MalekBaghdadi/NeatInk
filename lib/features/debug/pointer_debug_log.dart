import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// One pointer event, copied out of the framework's [PointerEvent].
@immutable
class PointerSample {
  const PointerSample({
    required this.type,
    required this.kind,
    required this.device,
    required this.pointer,
    required this.position,
    required this.pressure,
    required this.pressureMin,
    required this.pressureMax,
    required this.tilt,
    required this.orientation,
    required this.distance,
    required this.distanceMax,
    required this.radiusMajor,
    required this.radiusMinor,
    required this.buttons,
    required this.timeStamp,
  });

  factory PointerSample.fromEvent(PointerEvent e) => PointerSample(
        type: eventTypeName(e),
        kind: e.kind,
        device: e.device,
        pointer: e.pointer,
        position: e.localPosition,
        pressure: e.pressure,
        pressureMin: e.pressureMin,
        pressureMax: e.pressureMax,
        tilt: e.tilt,
        orientation: e.orientation,
        distance: e.distance,
        distanceMax: e.distanceMax,
        radiusMajor: e.radiusMajor,
        radiusMinor: e.radiusMinor,
        buttons: e.buttons,
        timeStamp: e.timeStamp,
      );

  /// "down", "move", "up", "hover" or "cancel".
  final String type;
  final PointerDeviceKind kind;
  final int device;
  final int pointer;

  /// Position inside the test area, in logical pixels.
  final Offset position;
  final double pressure;
  final double pressureMin;
  final double pressureMax;

  /// Radians from perpendicular to the screen (0 = upright pen).
  final double tilt;

  /// Radians; direction the pen points / touch ellipse axis.
  final double orientation;

  /// Hover distance from the screen (0 while touching).
  final double distance;
  final double distanceMax;
  final double radiusMajor;
  final double radiusMinor;
  final int buttons;

  /// Engine timestamp of the event.
  final Duration timeStamp;

  /// The pen or finger is on the screen (not hovering, not lifted).
  bool get isContact => type == 'down' || type == 'move';

  /// [pressure] mapped into 0–1 using the device's reported range.
  double get normalizedPressure {
    final range = pressureMax - pressureMin;
    final p = range > 0 ? (pressure - pressureMin) / range : pressure;
    return p.clamp(0.0, 1.0);
  }

  static String eventTypeName(PointerEvent e) => switch (e) {
        PointerDownEvent() => 'down',
        PointerMoveEvent() => 'move',
        PointerUpEvent() => 'up',
        PointerHoverEvent() => 'hover',
        PointerCancelEvent() => 'cancel',
        _ => e.runtimeType.toString(),
      };
}

/// The samples of one contact, from down to up.
class PointerTrace {
  PointerTrace(this.pointer, this.kind);

  final int pointer;
  final PointerDeviceKind kind;
  final List<PointerSample> samples = [];
}

/// Observed min/max of a value.
@immutable
class ValueRange {
  const ValueRange(this.min, this.max);

  final double min;
  final double max;

  double get spread => max - min;

  ValueRange including(double v) =>
      ValueRange(math.min(min, v), math.max(max, v));
}

/// What the test has learned about the input hardware so far.
@immutable
class PointerSummary {
  const PointerSummary({
    required this.eventCount,
    required this.kindsSeen,
    required this.stylusPressure,
    required this.maxStylusTilt,
    required this.hoverSeen,
    required this.rateHz,
  });

  /// A spread smaller than this (on a 0–1 scale) counts as "constant".
  static const double pressureVariationThreshold = 0.05;

  final int eventCount;
  final Set<PointerDeviceKind> kindsSeen;

  /// Pressure range of pen contacts (stylus or eraser end), null if none.
  final ValueRange? stylusPressure;

  /// Largest tilt (radians) seen from the pen, null if none.
  final double? maxStylusTilt;
  final bool hoverSeen;

  /// Event rate of the most recent pointer, null until measurable.
  final double? rateHz;

  bool get stylusSeen =>
      kindsSeen.contains(PointerDeviceKind.stylus) ||
      kindsSeen.contains(PointerDeviceKind.invertedStylus);

  bool get invertedStylusSeen =>
      kindsSeen.contains(PointerDeviceKind.invertedStylus);

  bool get touchSeen => kindsSeen.contains(PointerDeviceKind.touch);

  /// Null until the pen has touched the screen.
  bool? get pressureVaries => stylusPressure == null
      ? null
      : stylusPressure!.spread > pressureVariationThreshold;

  bool get tiltReported => (maxStylusTilt ?? 0) > 0.01;

  /// A one-sentence conclusion for the owner.
  String get verdict {
    if (eventCount == 0) {
      return 'Draw in the test area with your pen, then with a finger.';
    }
    if (!stylusSeen) {
      return touchSeen
          ? 'Only touch input so far. If you drew with the pen, it is '
              'reported as a finger: turn on Settings › Draw with finger to '
              'write with it (palm rejection is then off).'
          : 'No pen input yet. Draw with the pen.';
    }
    if (pressureVaries != true) {
      return 'The pen is recognised as a stylus, but its pressure stays '
          'constant, so line width cannot follow how hard you press.';
    }
    return 'The pen is recognised as a stylus with pressure. Keep "Draw with '
        'finger" off: fingers then only scroll and zoom (palm rejection).';
  }
}

/// Records pointer events for the pointer test screen: drawable traces, a
/// short history and a [summary]. Notifies listeners on every change.
class PointerDebugLog extends ChangeNotifier {
  /// How many recent events are kept for the list.
  static const int maxRecent = 40;

  /// Total stored trace points; the oldest traces are dropped beyond this.
  static const int maxTracePoints = 6000;

  /// Samples of one pointer used to measure the event rate.
  static const int rateWindow = 32;

  final List<PointerTrace> _traces = [];
  final Map<int, PointerTrace> _active = {};
  final List<PointerSample> _recent = [];
  final Set<PointerDeviceKind> _kinds = {};
  final List<Duration> _rateTimes = [];
  int? _ratePointer;
  int _eventCount = 0;
  int _tracePoints = 0;
  ValueRange? _stylusPressure;
  double? _maxStylusTilt;
  bool _hoverSeen = false;

  /// Contact traces, oldest first (including ones still being drawn).
  List<PointerTrace> get traces => List.unmodifiable(_traces);

  /// Recent events, newest first.
  Iterable<PointerSample> get recent => _recent.reversed;

  PointerSample? get last => _recent.isEmpty ? null : _recent.last;

  PointerSummary get summary => PointerSummary(
        eventCount: _eventCount,
        kindsSeen: Set.unmodifiable(_kinds),
        stylusPressure: _stylusPressure,
        maxStylusTilt: _maxStylusTilt,
        hoverSeen: _hoverSeen,
        rateHz: _rateHz(),
      );

  void record(PointerEvent event) {
    final s = PointerSample.fromEvent(event);
    _eventCount++;
    _kinds.add(s.kind);
    _recent.add(s);
    if (_recent.length > maxRecent) _recent.removeAt(0);
    _trackRate(s);

    final isPen = s.kind == PointerDeviceKind.stylus ||
        s.kind == PointerDeviceKind.invertedStylus;
    if (s.type == 'hover') _hoverSeen = true;
    if (isPen && s.isContact) {
      _stylusPressure = _stylusPressure?.including(s.pressure) ??
          ValueRange(s.pressure, s.pressure);
      _maxStylusTilt = math.max(_maxStylusTilt ?? 0, s.tilt.abs());
    }

    switch (s.type) {
      case 'down':
        final trace = PointerTrace(s.pointer, s.kind);
        _active[s.pointer] = trace;
        _traces.add(trace);
        _addPoint(trace, s);
      case 'move':
        final trace = _active[s.pointer];
        if (trace != null) _addPoint(trace, s);
      case 'up':
      case 'cancel':
        final trace = _active.remove(s.pointer);
        if (trace != null) _addPoint(trace, s);
    }
    notifyListeners();
  }

  void clear() {
    _traces.clear();
    _active.clear();
    _recent.clear();
    _kinds.clear();
    _rateTimes.clear();
    _ratePointer = null;
    _eventCount = 0;
    _tracePoints = 0;
    _stylusPressure = null;
    _maxStylusTilt = null;
    _hoverSeen = false;
    notifyListeners();
  }

  void _addPoint(PointerTrace trace, PointerSample s) {
    trace.samples.add(s);
    _tracePoints++;
    // Drop whole old traces (never the newest) to bound memory and paint
    // cost.
    while (_tracePoints > maxTracePoints && _traces.length > 1) {
      final oldest = _traces.removeAt(0);
      _active.removeWhere((_, t) => identical(t, oldest));
      _tracePoints -= oldest.samples.length;
    }
  }

  void _trackRate(PointerSample s) {
    if (s.type != 'move' && s.type != 'hover') return;
    if (_ratePointer != s.pointer) {
      _ratePointer = s.pointer;
      _rateTimes.clear();
    }
    _rateTimes.add(s.timeStamp);
    if (_rateTimes.length > rateWindow) _rateTimes.removeAt(0);
  }

  double? _rateHz() {
    if (_rateTimes.length < 3) return null;
    final spanUs = (_rateTimes.last - _rateTimes.first).inMicroseconds;
    if (spanUs <= 0) return null;
    return (_rateTimes.length - 1) * 1e6 / spanUs;
  }
}
