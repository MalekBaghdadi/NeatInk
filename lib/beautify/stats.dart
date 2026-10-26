import 'dart:math' as math;

/// Small robust-statistics helpers shared by the tidy pipeline.
///
/// All functions are pure and deterministic. They never modify their input
/// lists (they sort copies).

/// Median of [values], or null when empty. For an even count it is the mean
/// of the two middle values.
double? median(Iterable<double> values) {
  final v = values.toList()..sort();
  if (v.isEmpty) return null;
  final mid = v.length ~/ 2;
  return v.length.isOdd ? v[mid] : (v[mid - 1] + v[mid]) / 2;
}

/// Lower nearest-rank quantile: the element at index `floor(q · (n − 1))` of
/// the sorted values. Unlike an interpolated quantile it always returns an
/// actual sample, so a two-cluster set keeps a value from the lower cluster.
double? lowerQuantile(Iterable<double> values, double q) {
  final v = values.toList()..sort();
  if (v.isEmpty) return null;
  final i = (q.clamp(0.0, 1.0) * (v.length - 1)).floor();
  return v[i];
}

/// Weighted median: the value where the cumulative weight (sorted by value)
/// first reaches half of the total. Null when empty or all weights are zero.
double? weightedMedian(List<double> values, List<double> weights) {
  assert(values.length == weights.length);
  final order = List<int>.generate(values.length, (i) => i)
    ..sort((a, b) {
      final c = values[a].compareTo(values[b]);
      return c != 0 ? c : a.compareTo(b);
    });
  var total = 0.0;
  for (final w in weights) {
    if (w > 0) total += w;
  }
  if (total <= 0) return null;
  final half = total / 2;
  var acc = 0.0;
  for (final i in order) {
    final w = weights[i];
    if (w <= 0) continue;
    acc += w;
    if (acc >= half) return values[i];
  }
  return values[order.last];
}

/// A line `y = slope · x + intercept`.
class LineFit {
  const LineFit(this.slope, this.intercept);

  final double slope;
  final double intercept;

  double yAt(double x) => slope * x + intercept;

  /// Angle of the line from horizontal, radians. Positive means the line
  /// descends to the right on screen (y points down).
  double get angle => math.atan(slope);
}

/// Ordinary least-squares fit of `y = a·x + b` through the points
/// ([xs], [ys]). Returns null with fewer than two points or when all x are
/// (numerically) equal, i.e. the slope is undefined.
LineFit? leastSquaresLine(List<double> xs, List<double> ys) {
  assert(xs.length == ys.length);
  final n = xs.length;
  if (n < 2) return null;
  var mx = 0.0, my = 0.0;
  for (var i = 0; i < n; i++) {
    mx += xs[i];
    my += ys[i];
  }
  mx /= n;
  my /= n;
  var sxx = 0.0, sxy = 0.0;
  for (var i = 0; i < n; i++) {
    final dx = xs[i] - mx;
    sxx += dx * dx;
    sxy += dx * (ys[i] - my);
  }
  // Centred sums keep this numerically stable for page coordinates in the
  // hundreds; 1e-9 pt² of spread means "no horizontal extent".
  if (sxx <= 1e-9) return null;
  final a = sxy / sxx;
  return LineFit(a, my - a * mx);
}

/// Least-squares intercept for a fixed [slope]: the `b` that minimises
/// Σ(y − slope·x − b)², i.e. the mean residual. Null when empty.
double? interceptForSlope(List<double> xs, List<double> ys, double slope) {
  if (xs.isEmpty) return null;
  var sum = 0.0;
  for (var i = 0; i < xs.length; i++) {
    sum += ys[i] - slope * xs[i];
  }
  return sum / xs.length;
}

/// Converts degrees to radians.
double degToRad(double deg) => deg * math.pi / 180;

/// Converts radians to degrees.
double radToDeg(double rad) => rad * 180 / math.pi;

/// A fixed-capacity FIFO window of recent values (spec step 7: "last 12
/// x-heights, last 20 slants…").
class RollingWindow {
  RollingWindow(this.capacity) : assert(capacity > 0);

  final int capacity;
  final List<double> _values = [];

  /// Oldest first.
  List<double> get values => List.unmodifiable(_values);
  int get length => _values.length;
  bool get isEmpty => _values.isEmpty;

  void add(double v) {
    if (!v.isFinite) return;
    _values.add(v);
    if (_values.length > capacity) _values.removeAt(0);
  }

  void clear() => _values.clear();

  /// Median of the values in the window, or null when empty.
  double? get median => _medianOf(_values);
}

double? _medianOf(Iterable<double> values) => median(values);
