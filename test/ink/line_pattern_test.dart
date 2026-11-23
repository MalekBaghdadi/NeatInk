import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/line_pattern.dart';
import 'package:neatink/ink/line_style.dart';

/// The 2 pt pen of the reference video.
const double pen = 2.0;

/// Half the wave height of the default sliders for [pen]: 3.1 * 2 * 0.4.
const double amplitude = 2.48;

/// A horizontal base path at y = 100 from x = 0 to [length]. Pressure rises
/// from 0.2 to 0.8 and the time (ms) equals x, so both are easy to check.
List<InkPoint> hLine(double length, {double step = 2}) {
  InkPoint at(double x) => InkPoint(x, 100, 0.2 + 0.6 * x / length, x.round());
  return [
    for (var x = 0.0; x < length; x += step) at(x),
    at(length),
  ];
}

/// A circular arc of [radius] around (0, 0), from angle 0 to [sweep].
List<InkPoint> arc(double radius, double sweep, {int count = 200}) => [
      for (var i = 0; i <= count; i++)
        InkPoint(
          radius * math.cos(sweep * i / count),
          radius * math.sin(sweep * i / count),
          0.5,
          i,
        ),
    ];

double pathLength(List<InkPoint> pts) {
  var sum = 0.0;
  for (var i = 1; i < pts.length; i++) {
    sum += math.sqrt(math.pow(pts[i].x - pts[i - 1].x, 2) +
        math.pow(pts[i].y - pts[i - 1].y, 2));
  }
  return sum;
}

bool allFinite(List<List<InkPoint>> polylines) => polylines.every((poly) =>
    poly.every((p) => p.x.isFinite && p.y.isFinite && p.pressure.isFinite));

LineSettings styled(LineStyle style, {double height = 3.1, double width = 3.7}) =>
    LineSettings(style: style, waveHeight: height, waveWidth: width);

/// All the points of the marks, flattened.
List<InkPoint> run(List<InkPoint> pts, LineStyle style, double size,
        {bool smooth = true,
        bool fit = true,
        double height = 3.1,
        double width = 3.7}) =>
    patternPolylines(pts, styled(style, height: height, width: width), size,
            smooth: smooth, fit: fit)
        .expand((e) => e)
        .toList();

/// The x of every sample whose y is a full crest above the line at y = 100.
List<double> crestsOf(List<InkPoint> wave) => [
      for (final p in wave)
        if ((p.y - 100 - amplitude).abs() < 1e-9) p.x,
    ];

void main() {
  group('degenerate input', () {
    test('no points give no marks, in every style', () {
      for (final style in LineStyle.values) {
        expect(patternPolylines(const [], styled(style), pen), isEmpty,
            reason: style.name);
      }
    });

    test('a solid line returns the very same list', () {
      final pts = hLine(100);
      final out = patternPolylines(pts, LineSettings.solid, pen);
      expect(out, hasLength(1));
      expect(identical(out.single, pts), isTrue);
    });

    test('a tap stays one dot, whatever the style', () {
      final tap = [const InkPoint(10, 20, 0.5, 0)];
      for (final style in LineStyle.values) {
        final out = patternPolylines(tap, styled(style), pen);
        expect(out, hasLength(1), reason: style.name);
        expect(out.single, tap, reason: style.name);
        expect(identical(out.single, tap), isTrue, reason: style.name);
      }
    });

    test('a tap recorded twice is still one single point', () {
      final tap = [const InkPoint(10, 20, 0.5, 0), const InkPoint(10, 20, 0.5, 8)];
      for (final style in LineStyle.values.skip(1)) {
        final out = patternPolylines(tap, styled(style), pen);
        expect(out, hasLength(1), reason: style.name);
        expect(out.single, hasLength(1), reason: style.name);
        expect(out.single.single.x, 10);
        expect(out.single.single.y, 20);
      }
    });

    test('a path shorter than a thousandth of a point is a tap', () {
      final tiny = [const InkPoint(0, 0, 0.5, 0), const InkPoint(0.0005, 0, 0.5, 4)];
      for (final style in LineStyle.values.skip(1)) {
        final out = patternPolylines(tiny, styled(style), pen);
        expect(out, hasLength(1), reason: style.name);
        expect(out.single, tiny, reason: style.name);
      }
    });

    test('points that are not finite (or not on any page) are dropped', () {
      final pts = [
        const InkPoint(0, 100, 0.5, 0),
        const InkPoint(double.nan, 100, 0.5, 5),
        const InkPoint(40, double.infinity, 0.5, 10),
        const InkPoint(60, 100, double.nan, 15),
        const InkPoint(1e12, 100, 0.5, 20),
        const InkPoint(100, 100, 0.5, 25),
      ];
      for (final style in LineStyle.values.skip(1)) {
        final out = patternPolylines(pts, styled(style), pen);
        expect(allFinite(out), isTrue, reason: style.name);
        final xs = [for (final p in out.expand((e) => e)) p.x];
        expect(xs.reduce(math.min), greaterThanOrEqualTo(0), reason: style.name);
        expect(xs.reduce(math.max), lessThanOrEqualTo(100 + 1e-9),
            reason: style.name);
      }
    });

    test('a path of only unusable points has no marks', () {
      final bad = [
        const InkPoint(double.nan, 0, 0.5, 0),
        const InkPoint(0, double.infinity, 0.5, 1),
      ];
      for (final style in LineStyle.values.skip(1)) {
        expect(patternPolylines(bad, styled(style), pen), isEmpty,
            reason: style.name);
      }
    });

    test('a pen that is not a positive finite width is laid out as 0.25', () {
      final pts = hLine(100);
      for (final style in LineStyle.values.skip(1)) {
        final quarter = run(pts, style, 0.25);
        for (final odd in [0.0, -3.0, double.nan, double.infinity]) {
          final out = run(pts, style, odd);
          expect(out, quarter, reason: '${style.name} $odd');
        }
      }
    });

    test('settings that are not finite fall back instead of poisoning the line', () {
      final out = patternPolylines(
          hLine(100),
          const LineSettings(
              style: LineStyle.wavy,
              waveHeight: double.nan,
              waveWidth: double.infinity),
          pen);
      expect(allFinite(out), isTrue);
      expect(out.single.length, greaterThan(16));
    });

    test('it never throws and never returns a non-finite number', () {
      final rnd = math.Random(42);
      for (var round = 0; round < 400; round++) {
        final pts = <InkPoint>[];
        for (var i = 0; i < rnd.nextInt(40); i++) {
          final roll = rnd.nextInt(10);
          if (roll == 0 && pts.isNotEmpty) {
            pts.add(pts.last); // a repeated point
          } else if (roll == 1 && pts.length > 2) {
            pts.add(pts[pts.length - 2]); // straight back
          } else {
            pts.add(InkPoint(
              roll == 2 ? double.nan : rnd.nextDouble() * 500 - 100,
              roll == 3 ? double.infinity : rnd.nextDouble() * 300,
              roll == 4 ? double.nan : rnd.nextDouble(),
              i * 8,
            ));
          }
        }
        final settings = styled(
          LineStyle.values[rnd.nextInt(LineStyle.values.length)],
          height: 0.5 + rnd.nextDouble() * 11.5,
          width: 1 + rnd.nextDouble() * 19,
        );
        final w = rnd.nextBool() ? rnd.nextDouble() * 20 : 0.1;
        final out = patternPolylines(pts, settings, w,
            smooth: rnd.nextBool(), fit: rnd.nextBool());
        if (settings.isSolid) continue; // the input itself; the renderer filters
        expect(allFinite(out), isTrue, reason: 'round $round $settings');
      }
    });
  });

  group('dashed', () {
    const dashed = LineSettings(style: LineStyle.dashed);

    test('first dash starts on the path, last one ends on it', () {
      final out = patternPolylines(hLine(200), dashed, pen);
      expect(out.first.first.x, 0);
      expect(out.first.first.y, 100);
      expect(out.last.last.x, closeTo(200, 1e-9));
    });

    test('every dash and every gap has the same fitted length', () {
      // 200 pt, pen 2: dash 6.8, gap 5.8 (pitch 12.6); 16 dashes and 15 gaps
      // fill it when both are stretched by k.
      final out = patternPolylines(hLine(200), dashed, pen);
      const k = 200 / (16 * 12.6 - 5.8);
      expect(out, hasLength(16));
      for (var i = 0; i < out.length; i++) {
        expect(out[i].last.x - out[i].first.x, closeTo(6.8 * k, 1e-9),
            reason: 'dash $i');
        if (i > 0) {
          expect(out[i].first.x - out[i - 1].last.x, closeTo(5.8 * k, 1e-9),
              reason: 'gap $i');
        }
      }
    });

    test('whatever the length, a long path ends exactly on its end', () {
      for (var length = 20.0; length < 400; length += 7.3) {
        final out = patternPolylines(hLine(length), dashed, pen);
        expect(out.first.first.x, 0, reason: 'length $length');
        expect(out.last.last.x, closeTo(length, 1e-9), reason: 'length $length');
        if (length > 80) {
          for (final dash in out) {
            // The slack shared between the dashes keeps them near 6.8.
            expect(dash.last.x - dash.first.x,
                inInclusiveRange(6.8 * 0.75, 6.8 * 1.25),
                reason: 'length $length');
          }
        }
      }
    });

    test('a path shorter than one dash is one dash', () {
      final out = patternPolylines(hLine(5), dashed, pen);
      expect(out, hasLength(1));
      expect(out.single.first.x, 0);
      expect(out.single.last.x, 5);
    });

    test('a path a little longer than a dash is one (stretched) dash', () {
      final out = patternPolylines(hLine(8), dashed, pen);
      expect(out, hasLength(1));
      expect(out.single.first.x, 0);
      expect(out.single.last.x, 8);
    });

    test('dashes scale with the pen width', () {
      final thin = patternPolylines(hLine(300), dashed, 1);
      final thick = patternPolylines(hLine(300), dashed, 4);
      expect(thin.length, greaterThan(thick.length * 3));
    });

    test('dashes follow a curved path and have an equal arc length', () {
      final out = patternPolylines(arc(50, math.pi / 2), dashed, pen);
      expect(out, hasLength(7)); // 78.5 pt: (78.5 + 5.8) / 12.6 is 6.7
      final first = pathLength(out.first);
      for (final dash in out) {
        expect(pathLength(dash), closeTo(first, 1e-6));
        for (final p in dash) {
          expect(math.sqrt(p.x * p.x + p.y * p.y), closeTo(50, 0.05));
        }
      }
      // The whole quarter circle is covered end to end.
      expect(out.first.first.x, closeTo(50, 1e-6));
      expect(out.last.last.y, closeTo(50, 1e-6));
    });

    test('a corner inside a dash is a vertex of that dash', () {
      // An L: 105 pt right, then 95 down: 200 pt, so 16 dashes of 6.8 * k.
      final base = [
        for (var x = 0.0; x <= 105; x += 5) InkPoint(x, 0, 0.5, 0),
        for (var y = 5.0; y <= 95; y += 5) InkPoint(105, y, 0.5, 0),
      ];
      final out = patternPolylines(base, dashed, pen);
      const k = 200 / (16 * 12.6 - 5.8);
      final start = 8 * 12.6 * k; // dash 8 runs over the corner at 105
      expect(start, lessThan(105));
      expect(start + 6.8 * k, greaterThan(105));
      final bent = out.firstWhere((d) => d.any((p) => p.x == 105 && p.y == 0));
      expect(bent.first.x, closeTo(start, 1e-9));
      expect(bent.first.y, 0);
      expect(bent.last.x, 105);
      expect(bent.last.y, closeTo(start + 6.8 * k - 105, 1e-9));
      expect(pathLength(bent), closeTo(6.8 * k, 1e-9));
    });

    test('pressure and time are interpolated along the path', () {
      final out = patternPolylines(hLine(200), dashed, pen);
      for (final dash in out) {
        for (final p in dash) {
          expect(p.pressure, closeTo(0.2 + 0.6 * p.x / 200, 1e-9));
          expect((p.t - p.x).abs(), lessThanOrEqualTo(1));
        }
      }
    });

    test('with fit off the dashes keep their nominal length and pitch', () {
      final out = patternPolylines(hLine(92), dashed, pen, fit: false);
      // Pitch 12.6: dashes start at 0, 12.6 ... 88.2 (8 of them).
      expect(out, hasLength(8));
      for (var i = 0; i < out.length; i++) {
        expect(out[i].first.x, closeTo(i * 12.6, 1e-9));
        expect(out[i].last.x, closeTo(math.min(i * 12.6 + 6.8, 92), 1e-9));
      }
      // The last dash is cut off by the end of the path (88.2 + 6.8 > 92).
      expect(out.last.last.x, closeTo(92, 1e-9));
    });

    test('growing a path with fit off never moves the dashes already there', () {
      final shorter = patternPolylines(hLine(60), dashed, pen, fit: false);
      final longer = patternPolylines(hLine(120), dashed, pen, fit: false);
      for (var i = 0; i < shorter.length; i++) {
        expect(longer[i].first.x, shorter[i].first.x);
        expect(longer[i].last.x, shorter[i].last.x);
      }
    });

    test('a huge path gets coarser dashes instead of millions of them', () {
      final huge = [const InkPoint(0, 0, 0.5, 0), const InkPoint(1e7, 0, 0.5, 1)];
      final out = patternPolylines(huge, dashed, 0.25);
      expect(out.length, lessThanOrEqualTo(20000));
      expect(out.first.first.x, 0);
      expect(out.last.last.x, closeTo(1e7, 1e-3));
      final live = patternPolylines(huge, dashed, 0.25, fit: false);
      expect(live.length, lessThanOrEqualTo(20000));
      expect(live, isNotEmpty);
    });
  });

  group('dotted', () {
    const dotted = LineSettings(style: LineStyle.dotted);

    test('every dot is a one-point polyline, the first and last on the ends', () {
      final out = patternPolylines(hLine(200), dotted, pen);
      expect(out.every((d) => d.length == 1), isTrue);
      expect(out.first.single.x, 0);
      expect(out.first.single.y, 100);
      expect(out.last.single.x, closeTo(200, 1e-9));
    });

    test('dots are evenly spaced near 2.4 pen widths', () {
      // round(200 / 4.8) = 42 gaps, so 43 dots 200 / 42 apart.
      final out = patternPolylines(hLine(200), dotted, pen);
      expect(out, hasLength(43));
      for (var i = 1; i < out.length; i++) {
        expect(out[i].single.x - out[i - 1].single.x, closeTo(200 / 42, 1e-9));
      }
    });

    test('a path shorter than half a spacing still has a dot at each end', () {
      final out = patternPolylines(hLine(2), dotted, pen);
      expect(out, hasLength(2));
      expect(out.first.single.x, 0);
      expect(out.last.single.x, 2);
    });

    test('dots lie on a curved path', () {
      final out = patternPolylines(arc(40, math.pi), dotted, pen);
      expect(out.length, greaterThan(20));
      for (final d in out) {
        final p = d.single;
        expect(math.sqrt(p.x * p.x + p.y * p.y), closeTo(40, 0.02));
      }
    });

    test('pressure and time are interpolated along the path', () {
      for (final d in patternPolylines(hLine(200), dotted, pen)) {
        final p = d.single;
        expect(p.pressure, closeTo(0.2 + 0.6 * p.x / 200, 1e-9));
        expect((p.t - p.x).abs(), lessThanOrEqualTo(1));
      }
    });

    test('with fit off the dots sit at multiples of the spacing', () {
      final out = patternPolylines(hLine(50), dotted, pen, fit: false);
      expect(out, hasLength(11)); // 0, 4.8 ... 48
      for (var i = 0; i < out.length; i++) {
        expect(out[i].single.x, closeTo(i * 4.8, 1e-9));
      }
    });
  });

  group('wavy', () {
    test('one polyline that starts and ends on the base path', () {
      final out = patternPolylines(hLine(200), styled(LineStyle.wavy), pen);
      expect(out, hasLength(1));
      final w = out.single;
      expect(w.first.x, 0);
      expect(w.first.y, 100);
      expect(w.last.x, closeTo(200, 1e-9));
      expect(w.last.y, closeTo(100, 1e-9));
    });

    test('the crest height is the amplitude and the crests are a wave apart', () {
      // 148 pt is exactly ten waves of 14.8 pt.
      final w = run(hLine(148), LineStyle.wavy, pen);
      final offsets = [for (final p in w) p.y - 100];
      expect(offsets.reduce(math.max), closeTo(amplitude, 1e-9));
      expect(offsets.reduce(math.min), closeTo(-amplitude, 1e-9));
      final crests = crestsOf(w);
      expect(crests, hasLength(10));
      for (var i = 1; i < crests.length; i++) {
        expect(crests[i] - crests[i - 1], closeTo(14.8, 1e-9));
      }
      expect(crests.first, closeTo(14.8 / 4, 1e-9));
    });

    test('the path is fitted to a whole number of waves', () {
      // 150 pt is 10.14 waves of 14.8 pt: ten waves of 15 pt.
      final w = run(hLine(150), LineStyle.wavy, pen);
      final crests = crestsOf(w);
      expect(crests, hasLength(10));
      expect(crests[1] - crests[0], closeTo(15, 1e-9));
      expect(w, hasLength(16 * 10 + 1)); // 16 samples a wave, plus the end
      expect(w.last.y, closeTo(100, 1e-9));
    });

    test('a path shorter than a wave is one squeezed wave', () {
      final w = run(hLine(6), LineStyle.wavy, pen);
      expect(w, hasLength(17));
      expect(w.last.x, closeTo(6, 1e-9));
      expect(w.last.y, closeTo(100, 1e-9));
    });

    test('the sliders set the height and the length of the wave', () {
      final base = hLine(400);
      final normal = run(base, LineStyle.wavy, pen);
      final tall = run(base, LineStyle.wavy, pen, height: 6.2);
      final wide = run(base, LineStyle.wavy, pen, width: 7.4);
      double heightOf(List<InkPoint> w) =>
          w.map((p) => (p.y - 100).abs()).reduce(math.max);
      expect(heightOf(tall), closeTo(2 * heightOf(normal), 1e-9));
      // Twice the wavelength: half as many samples.
      expect(wide.length, closeTo(normal.length / 2, 17));
    });

    test('a wave is never shorter than twice the pen width', () {
      // waveWidth 0.5 would make a 2 pt wave for a 2 pt pen; it is raised to
      // 4 pt, which is 25 waves on 100 pt.
      final w = run(hLine(100), LineStyle.wavy, pen, width: 0.5);
      expect(w, hasLength(16 * 25 + 1));
    });

    test('the offset goes along the normal of a vertical path', () {
      final base = [for (var y = 0.0; y <= 100; y += 2) InkPoint(50, y, 0.5, 0)];
      final w = run(base, LineStyle.wavy, pen);
      // Travelling down, the normal (-ty, tx) points towards -x.
      for (final p in w) {
        expect(p.x, inInclusiveRange(50 - amplitude - 1e-9, 50 + amplitude + 1e-9));
      }
      expect(w.map((p) => p.x).reduce(math.max), closeTo(50 + amplitude, 1e-9));
      expect(w.map((p) => p.x).reduce(math.min), closeTo(50 - amplitude, 1e-9));
      expect(w.last.y, closeTo(100, 1e-9));
    });

    test('on a curved path the wave stays around the curve', () {
      final w = run(arc(60, math.pi), LineStyle.wavy, pen);
      final radii = [for (final p in w) math.sqrt(p.x * p.x + p.y * p.y)];
      expect(radii.reduce(math.max), closeTo(60 + amplitude, 0.05));
      expect(radii.reduce(math.min), closeTo(60 - amplitude, 0.05));
    });

    test('pressure and time follow the base path', () {
      for (final p in run(hLine(200), LineStyle.wavy, pen)) {
        expect(p.pressure, closeTo(0.2 + 0.6 * p.x / 200, 1e-9));
        expect((p.t - p.x).abs(), lessThanOrEqualTo(1));
      }
    });

    test('smoothing evens out a shaky hand-drawn path and keeps its ends', () {
      final rnd = math.Random(5);
      final shaky = [
        for (var i = 0; i <= 100; i++)
          InkPoint(i * 2.0, 100 + (rnd.nextDouble() - 0.5) * 3, 0.5, i * 8),
      ];
      final smooth = run(shaky, LineStyle.wavy, pen);
      final raw = run(shaky, LineStyle.wavy, pen, smooth: false);
      // How much each step's rise differs from the step before.
      double roughness(List<InkPoint> w) {
        var sum = 0.0;
        for (var i = 2; i < w.length; i++) {
          sum += ((w[i].y - w[i - 1].y) - (w[i - 1].y - w[i - 2].y)).abs();
        }
        return sum / w.length;
      }

      expect(roughness(smooth), lessThan(roughness(raw)));
      expect(smooth.first.x, shaky.first.x);
      expect(smooth.first.y, closeTo(shaky.first.y, 1e-9));
      expect(smooth.last.x, closeTo(shaky.last.x, 1e-9));
      expect(smooth.last.y, closeTo(shaky.last.y, 1e-9));
    });

    test('two points are never smoothed, and generated shapes keep corners', () {
      final two = [const InkPoint(0, 100, 0.5, 0), const InkPoint(100, 100, 0.5, 1)];
      expect(run(two, LineStyle.wavy, pen),
          run(two, LineStyle.wavy, pen, smooth: false));
      final bend = [
        const InkPoint(0, 100, 0.5, 0),
        const InkPoint(50, 100, 0.5, 1),
        const InkPoint(50, 150, 0.5, 2),
      ];
      expect(run(bend, LineStyle.zigzag, pen, smooth: false),
          isNot(run(bend, LineStyle.zigzag, pen)));
    });

    test('with fit off the wave keeps its wavelength and is cut by the end', () {
      final w = run(hLine(40), LineStyle.wavy, pen, fit: false);
      // 14.8 pt waves: crests at 3.7, 18.5 and 33.3.
      final crests = crestsOf(w);
      expect(crests, hasLength(3));
      expect(crests.first, closeTo(3.7, 1e-9));
      expect(crests[1] - crests[0], closeTo(14.8, 1e-9));
      expect(w.last.x, closeTo(40, 1e-9));
    });

    test('growing a path with fit off never moves the waves already there', () {
      final a = run(hLine(60), LineStyle.wavy, pen, fit: false);
      final b = run(hLine(120), LineStyle.wavy, pen, fit: false);
      for (var i = 0; i < a.length - 1; i++) {
        expect(b[i].x, closeTo(a[i].x, 1e-9));
        expect(b[i].y, closeTo(a[i].y, 1e-9));
      }
    });

    test('a very long path is sampled coarsely, not endlessly', () {
      final w = run([const InkPoint(0, 0, 0.5, 0), const InkPoint(2e6, 0, 0.5, 1)],
          LineStyle.wavy, 0.25);
      expect(w.length, lessThanOrEqualTo(20001));
      expect(allFinite([w]), isTrue);
    });
  });

  group('zigzag', () {
    test('vertices every quarter wave: 0, +A, 0, -A, 0 ...', () {
      // 148 pt is ten waves of 14.8 pt, so a vertex every 3.7 pt.
      final w = run(hLine(148), LineStyle.zigzag, pen);
      double offsetAt(double x) =>
          w.firstWhere((p) => (p.x - x).abs() < 1e-9).y - 100;
      for (var j = 0; j <= 40; j++) {
        final expected = const [0.0, 1.0, 0.0, -1.0][j % 4] * amplitude;
        expect(offsetAt(j * 3.7), closeTo(expected, 1e-9), reason: 'vertex $j');
      }
      expect(w.first.y, 100);
      expect(w.last.y, closeTo(100, 1e-9));
    });

    test('between the vertices it is straight', () {
      final w = run(hLine(148), LineStyle.zigzag, pen);
      final leg = [for (final p in w) if (p.x >= 3.7 - 1e-9 && p.x <= 11.1 + 1e-9) p];
      expect(leg.length, greaterThanOrEqualTo(3));
      final slope = (leg.last.y - leg.first.y) / (leg.last.x - leg.first.x);
      for (final p in leg) {
        expect(p.y, closeTo(leg.first.y + slope * (p.x - leg.first.x), 1e-9));
      }
      expect(slope, lessThan(0)); // from the crest down through the base line
    });

    test('the corners are sharp: only the vertices reach the crest', () {
      final w = run(hLine(148), LineStyle.zigzag, pen);
      expect(crestsOf(w), hasLength(10));
    });

    test('points are never more than 3 pt apart along the base path', () {
      // A wide, low zigzag has long legs: extra points keep them short.
      final w = run(hLine(400), LineStyle.zigzag, pen, width: 20, height: 1);
      for (var i = 1; i < w.length; i++) {
        expect(w[i].x - w[i - 1].x, lessThanOrEqualTo(3 + 1e-9));
      }
    });

    test('a curved path is followed, not cut across', () {
      final w = run(arc(60, math.pi), LineStyle.zigzag, pen,
          width: 20, height: 1, smooth: false);
      const low = 1 * 2 * 0.4; // the amplitude of the 1.0 height slider
      for (final p in w) {
        expect(math.sqrt(p.x * p.x + p.y * p.y),
            inInclusiveRange(60 - low - 0.01, 60 + low + 0.01));
      }
      expect(w.length, greaterThan(60));
    });

    test('with fit off the quarter waves keep their size', () {
      final w = run(hLine(10), LineStyle.zigzag, pen, fit: false);
      expect(crestsOf(w).single, closeTo(3.7, 1e-9));
      expect(w.last.x, closeTo(10, 1e-9));
    });
  });

  group('double (parallel)', () {
    const parallel = LineSettings(style: LineStyle.parallel);

    test('two lines, half the line gap either side of the base', () {
      final out = patternPolylines(hLine(100), parallel, pen);
      expect(out, hasLength(2));
      for (final p in out[0]) {
        expect(p.y, closeTo(100 + 2.2, 1e-9));
      }
      for (final p in out[1]) {
        expect(p.y, closeTo(100 - 2.2, 1e-9));
      }
      // The centres are 2.2 pen widths apart.
      expect(out[0].first.y - out[1].first.y, closeTo(4.4, 1e-9));
      for (final line in out) {
        expect(line.first.x, 0);
        expect(line.last.x, closeTo(100, 1e-9));
      }
    });

    test('the gap scales with the pen width', () {
      final out = patternPolylines(hLine(100), parallel, 5);
      expect(out[0].first.y - out[1].first.y, closeTo(11, 1e-9));
    });

    test('a right-angle corner is mitred', () {
      // Right then down; the corner is at (100, 0).
      final base = [
        for (var x = 0.0; x <= 100; x += 2) InkPoint(x, 0, 0.5, 0),
        for (var y = 2.0; y <= 100; y += 2) InkPoint(100, y, 0.5, 0),
      ];
      final out = patternPolylines(base, parallel, pen, smooth: false);
      bool has(List<InkPoint> line, double x, double y) =>
          line.any((p) => (p.x - x).abs() < 1e-9 && (p.y - y).abs() < 1e-9);
      // The inner line (the base's normal side) cuts the corner at (97.8, 2.2),
      // the outer line goes round it at (102.2, -2.2).
      expect(has(out[0], 100 - 2.2, 2.2), isTrue);
      expect(has(out[1], 100 + 2.2, -2.2), isTrue);
      // Straight runs keep the plain offset.
      final along = out[0].where((p) => p.x > 10 && p.x < 90).toList();
      expect(along, isNotEmpty);
      expect(along.every((p) => (p.y - 2.2).abs() < 1e-9), isTrue);
      final down = out[1].where((p) => p.y > 10 && p.y < 90).toList();
      expect(down, isNotEmpty);
      expect(down.every((p) => (p.x - 102.2).abs() < 1e-9), isTrue);
    });

    test('the miter of a very sharp turn is clamped to twice the half gap', () {
      // A 170 degree turn: unclamped, the miter would be 11.5 half gaps long.
      final corner = const InkPoint(1.5, 0, 0.5, 1);
      final base = [
        const InkPoint(0, 0, 0.5, 0),
        corner,
        InkPoint(1.5 - 1.5 * math.cos(10 * math.pi / 180),
            1.5 * math.sin(10 * math.pi / 180), 0.5, 2),
      ];
      final out = patternPolylines(base, parallel, pen, smooth: false);
      var farthest = 0.0;
      for (final line in out) {
        for (final p in line) {
          farthest = math.max(
              farthest, math.sqrt(math.pow(p.x - corner.x, 2) + math.pow(p.y, 2)));
        }
      }
      expect(farthest, closeTo(2 * 2.2, 1e-9));
    });

    test('a path that doubles back on itself gives finite lines', () {
      final base = [
        for (var x = 0.0; x <= 40; x += 2) InkPoint(x, 0, 0.5, 0),
        for (var x = 38.0; x >= 0; x -= 2) InkPoint(x, 0, 0.5, 0),
      ];
      final out = patternPolylines(base, parallel, pen, smooth: false);
      expect(allFinite(out), isTrue);
      expect(out, hasLength(2));
    });

    test('a closed shape is mitred at its start corner too', () {
      final base = [
        const InkPoint(10, 10, 0.5, 0),
        const InkPoint(90, 10, 0.5, 1),
        const InkPoint(90, 60, 0.5, 2),
        const InkPoint(10, 60, 0.5, 3),
        const InkPoint(10, 10, 0.5, 4),
      ];
      final out = patternPolylines(base, parallel, pen, smooth: false);
      // Clockwise on screen: the normal side is the inside.
      expect(out[0].first.x, closeTo(10 + 2.2, 1e-9));
      expect(out[0].first.y, closeTo(10 + 2.2, 1e-9));
      expect(out[1].first.x, closeTo(10 - 2.2, 1e-9));
      expect(out[1].first.y, closeTo(10 - 2.2, 1e-9));
      for (final line in out) {
        expect(line.last.x, closeTo(line.first.x, 1e-9));
        expect(line.last.y, closeTo(line.first.y, 1e-9));
      }
    });

    test('straight runs are subdivided for perfect_freehand', () {
      final base = [const InkPoint(0, 0, 0.5, 0), const InkPoint(100, 0, 0.5, 100)];
      final out = patternPolylines(base, parallel, pen);
      for (final line in out) {
        expect(line.length, greaterThan(40));
        for (var i = 1; i < line.length; i++) {
          expect(line[i].x - line[i - 1].x, lessThanOrEqualTo(3));
        }
        expect(line[line.length ~/ 2].t, closeTo(50, 2));
      }
    });

    test('a generated rectangle keeps only its corners before the offset', () {
      // 40 collinear points per side: the double line has to come out as a
      // clean rectangle ring, not as a ring with a dent at every corner.
      final base = [
        for (var x = 0.0; x < 80; x += 2) InkPoint(x, 0, 0.5, 0),
        for (var y = 0.0; y < 50; y += 2) InkPoint(80, y, 0.5, 0),
        for (var x = 80.0; x > 0; x -= 2) InkPoint(x, 50, 0.5, 0),
        for (var y = 50.0; y > 0; y -= 2) InkPoint(0, y, 0.5, 0),
        const InkPoint(0, 0, 0.5, 0),
      ];
      final out = patternPolylines(base, parallel, pen, smooth: false);
      for (final line in out) {
        // Never a step backwards along a side: every point is on one of the
        // four sides of the offset rectangle.
        final inner = line.first.x > 0;
        final d = inner ? 2.2 : -2.2;
        for (final p in line) {
          final onSide = (p.x - d).abs() < 1e-9 ||
              (p.x - (80 - d)).abs() < 1e-9 ||
              (p.y - d).abs() < 1e-9 ||
              (p.y - (50 - d)).abs() < 1e-9;
          expect(onSide, isTrue, reason: '${p.x}, ${p.y}');
        }
      }
    });

    test('pressure and time carry over to both lines', () {
      for (final line in patternPolylines(hLine(100), parallel, pen)) {
        for (final p in line) {
          expect(p.pressure, closeTo(0.2 + 0.6 * p.x / 100, 1e-9));
          expect((p.t - p.x).abs(), lessThanOrEqualTo(1));
        }
      }
    });

    test('the two lines follow a curved path', () {
      final out = patternPolylines(arc(60, math.pi), parallel, pen);
      // Counter-clockwise arc: the normal side is towards the centre.
      for (final p in out[0]) {
        expect(math.sqrt(p.x * p.x + p.y * p.y), closeTo(60 - 2.2, 0.05));
      }
      for (final p in out[1]) {
        expect(math.sqrt(p.x * p.x + p.y * p.y), closeTo(60 + 2.2, 0.05));
      }
    });
  });

  group('speed', () {
    // 50 000 points of a shaky path across a page.
    final rnd = math.Random(9);
    final huge = [
      for (var i = 0; i < 50000; i++)
        InkPoint(
          10 + i * 0.011,
          400 + 40 * math.sin(i / 700) + (rnd.nextDouble() - 0.5),
          0.5 + 0.3 * math.sin(i / 90),
          i,
        ),
    ];

    for (final style in LineStyle.values.skip(1)) {
      test('50 000 points as ${style.name} in well under a second', () {
        final watch = Stopwatch()..start();
        final out = patternPolylines(huge, styled(style), pen);
        watch.stop();
        expect(watch.elapsedMilliseconds, lessThan(1000), reason: style.name);
        expect(out, isNotEmpty);
        expect(allFinite(out), isTrue);
      });
    }

    test('it is deterministic', () {
      final a = patternPolylines(
          huge.take(2000).toList(), styled(LineStyle.wavy), pen);
      final b = patternPolylines(
          huge.take(2000).toList(), styled(LineStyle.wavy), pen);
      expect(a.single, b.single);
    });
  });

  test('the video\'s numbers for a 2 pt pen and the default sliders', () {
    // A wave about 5 pt peak to peak and 15 pt long.
    final wave = run(hLine(296), LineStyle.wavy, pen);
    final ys = [for (final p in wave) p.y];
    expect(ys.reduce(math.max) - ys.reduce(math.min), closeTo(4.96, 1e-9));
    final crests = crestsOf(wave);
    expect(crests[1] - crests[0], closeTo(14.8, 1e-9));
    // Dashes 8.8 pt long and 3.8 pt apart as drawn (the round caps add one
    // pen width to the dash and take one off the gap).
    final dashes = patternPolylines(
        hLine(296), const LineSettings(style: LineStyle.dashed), pen);
    final dash = dashes[3].last.x - dashes[3].first.x;
    final gap = dashes[4].first.x - dashes[3].last.x;
    expect(dash + pen, closeTo(8.8, 0.1));
    expect(gap - pen, closeTo(3.8, 0.1));
    // Double: centres 4.4 pt apart.
    final two = patternPolylines(
        hLine(100), const LineSettings(style: LineStyle.parallel), pen);
    expect((two[0].first.y - two[1].first.y).abs(), closeTo(4.4, 1e-9));
  });
}
