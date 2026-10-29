import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/canvas/input_router.dart';

double norm(double p, {double min = 0, double max = 1, PointerDeviceKind kind = PointerDeviceKind.stylus}) =>
    normalizePressure(kind: kind, pressure: p, pressureMin: min, pressureMax: max);

void main() {
  test('a pen with the usual 0..1 range keeps its readings', () {
    expect(norm(0.2), closeTo(0.2, 1e-9));
    expect(norm(0.9), closeTo(0.9, 1e-9));
    expect(norm(1.2), 1.0);
  });

  test('a pen whose range is in raw units but whose readings are 0..1', () {
    // Some devices say 0..4096 yet report 0.3 for a light touch: dividing by
    // the range made every stroke look like zero pressure.
    expect(norm(0.3, max: 4096), closeTo(0.3, 1e-9));
    expect(norm(0.8, max: 8191), closeTo(0.8, 1e-9));
    expect(norm(1.3, max: 4096), 1.0);
  });

  test('raw readings in a raw range are scaled', () {
    expect(norm(2048, max: 4096), closeTo(0.5, 1e-9));
    expect(norm(1024, max: 4096), closeTo(0.25, 1e-9));
  });

  test('fingers, and pens without a range, get a flat 0.5', () {
    expect(norm(0.9, kind: PointerDeviceKind.touch), 0.5);
    expect(norm(0.9, min: 1, max: 1), 0.5);
    expect(norm(double.nan), 0.5);
  });
}
