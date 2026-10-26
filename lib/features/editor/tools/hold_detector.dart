import 'dart:math' as math;

import 'tool_config.dart';

/// Detects the "pen held still" gesture at the end of a stroke while the pen
/// is still down (hold-to-snap shapes).
///
/// Feed every sample of the stroke being drawn to [addPoint]. Because a pen
/// held perfectly still may stop producing move events, the UI also calls
/// [check] from a timer with the current time. Both return true exactly
/// once: on the call that detects the hold.
///
/// The hold is detected when, for the last [ToolConfig.holdDurationMs], the
/// pen has stayed within [ToolConfig.holdRadiusPt] of where it is now, and
/// the stroke drawn so far is longer than [ToolConfig.holdMinPathLengthPt]
/// (so a dot or a short tick never snaps).
///
/// Times are in milliseconds on the same clock for [addPoint] and [check]
/// (the stroke's point timestamps).
class HoldDetector {
  HoldDetector({ToolConfig config = ToolConfig.defaults})
      : holdDurationMs = config.holdDurationMs,
        holdRadiusPt = config.holdRadiusPt,
        minPathLengthPt = config.holdMinPathLengthPt;

  /// How long the pen must stay still.
  final int holdDurationMs;

  /// How far the pen may wander while "still".
  final double holdRadiusPt;

  /// Minimum length of ink drawn before a hold counts.
  final double minPathLengthPt;

  final List<double> _xs = [];
  final List<double> _ys = [];
  final List<int> _ts = [];
  double _pathLength = 0;
  bool _fired = false;

  /// True once the hold has been detected for this stroke.
  bool get fired => _fired;

  /// Length of the polyline fed so far, in points.
  double get pathLength => _pathLength;

  /// Number of samples fed so far.
  int get pointCount => _ts.length;

  /// Forgets the current stroke (call on pen-down of a new stroke).
  void reset() {
    _xs.clear();
    _ys.clear();
    _ts.clear();
    _pathLength = 0;
    _fired = false;
  }

  /// Adds one pen sample and returns true if this sample completes the hold.
  ///
  /// Samples must arrive in time order; a sample older than the previous
  /// one is treated as simultaneous with it.
  bool addPoint(double x, double y, int tMillis) {
    if (!x.isFinite || !y.isFinite) return false;
    final t = _ts.isEmpty ? tMillis : math.max(tMillis, _ts.last);
    if (_ts.isNotEmpty) {
      final dx = x - _xs.last, dy = y - _ys.last;
      _pathLength += math.sqrt(dx * dx + dy * dy);
    }
    _xs.add(x);
    _ys.add(y);
    _ts.add(t);
    return check(t);
  }

  /// Checks whether the pen, resting at its last sample until [nowMs], has
  /// been held still long enough. Returns true only on the first detection.
  bool check(int nowMs) {
    if (_fired || _ts.isEmpty || _pathLength <= minPathLengthPt) return false;
    if (_isHolding(nowMs)) {
      _fired = true;
      return true;
    }
    return false;
  }

  /// True when every pen position in `[now − holdDurationMs, now]` lies
  /// within [holdRadiusPt] of the last sample. The pen is assumed to stay at
  /// the last sample until [nowMs] and to move in straight lines between
  /// samples, so the position at the window start is interpolated.
  bool _isHolding(int nowMs) {
    final n = _ts.length;
    final windowStart = nowMs - holdDurationMs;
    // The window must be fully covered by the stroke.
    if (_ts.first > windowStart) return false;
    final cx = _xs[n - 1], cy = _ys[n - 1];
    final r2 = holdRadiusPt * holdRadiusPt;
    var i = n - 1;
    for (; i >= 0 && _ts[i] >= windowStart; i--) {
      final dx = _xs[i] - cx, dy = _ys[i] - cy;
      if (dx * dx + dy * dy > r2) return false;
    }
    if (i < 0 || i == n - 1) return true; // no sample before / inside window
    // Interpolate between sample i (before the window) and i + 1 (inside).
    final t0 = _ts[i], t1 = _ts[i + 1];
    final k = t1 == t0 ? 1.0 : (windowStart - t0) / (t1 - t0);
    final px = _xs[i] + (_xs[i + 1] - _xs[i]) * k;
    final py = _ys[i] + (_ys[i + 1] - _ys[i]) * k;
    final dx = px - cx, dy = py - cy;
    return dx * dx + dy * dy <= r2;
  }
}
