import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/ink/line_style.dart';

void main() {
  group('LineSettings JSON', () {
    test('round trips every style with its sliders', () {
      for (final style in LineStyle.values) {
        final settings =
            LineSettings(style: style, waveHeight: 4.5, waveWidth: 9.25);
        final back = LineSettings.fromJson(
            jsonDecode(jsonEncode(settings.toJson())) as Object?);
        expect(back, settings, reason: style.name);
        expect(back.style, style);
      }
    });

    test('rounds the sliders to two decimals when writing', () {
      final json =
          const LineSettings(waveHeight: 3.14159, waveWidth: 7.777).toJson();
      expect(json['height'], 3.14);
      expect(json['width'], 7.78);
    });

    test('anything unreadable is a plain solid line', () {
      for (final bad in <Object?>[
        null,
        'wavy',
        42,
        true,
        const <Object?>[],
        const <String, Object?>{},
      ]) {
        final s = LineSettings.fromJson(bad);
        expect(s.style, LineStyle.solid, reason: '$bad');
        expect(s.waveHeight, LineSettings.defaultWaveHeight);
        expect(s.waveWidth, LineSettings.defaultWaveWidth);
      }
    });

    test('an unknown style falls back to solid but keeps the sliders', () {
      final s = LineSettings.fromJson(
          {'style': 'rainbow', 'height': 5, 'width': 6});
      expect(s.style, LineStyle.solid);
      expect(s.waveHeight, 5);
      expect(s.waveWidth, 6);
    });

    test('sliders are clamped to their ranges', () {
      final high = LineSettings.fromJson(
          {'style': 'wavy', 'height': 1e9, 'width': 1e9});
      expect(high.waveHeight, LineSettings.maxWaveHeight);
      expect(high.waveWidth, LineSettings.maxWaveWidth);
      final low = LineSettings.fromJson(
          {'style': 'wavy', 'height': -3, 'width': 0});
      expect(low.waveHeight, LineSettings.minWaveHeight);
      expect(low.waveWidth, LineSettings.minWaveWidth);
    });

    test('sliders that are not finite numbers use the defaults', () {
      for (final bad in <Object?>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
        'big',
        null,
      ]) {
        final s = LineSettings.fromJson({'style': 'zigzag', 'height': bad, 'width': bad});
        expect(s.style, LineStyle.zigzag);
        expect(s.waveHeight, LineSettings.defaultWaveHeight, reason: '$bad');
        expect(s.waveWidth, LineSettings.defaultWaveWidth, reason: '$bad');
      }
    });

    test('unknown keys are ignored', () {
      final s = LineSettings.fromJson(
          {'style': 'dashed', 'height': 2, 'width': 3, 'future': [1, 2]});
      expect(s, const LineSettings(style: LineStyle.dashed, waveHeight: 2, waveWidth: 3));
    });
  });

  group('LineSettings', () {
    test('the defaults are the reference video\'s sliders', () {
      expect(LineSettings.solid.style, LineStyle.solid);
      expect(LineSettings.solid.isSolid, isTrue);
      expect(LineSettings.defaultWaveHeight, 3.1);
      expect(LineSettings.defaultWaveWidth, 3.7);
    });

    test('equality and hash cover the style and both sliders', () {
      const a = LineSettings(style: LineStyle.wavy);
      expect(a, const LineSettings(style: LineStyle.wavy));
      expect(a.hashCode, const LineSettings(style: LineStyle.wavy).hashCode);
      expect(a == a.copyWith(style: LineStyle.zigzag), isFalse);
      expect(a == a.copyWith(waveHeight: 4), isFalse);
      expect(a == a.copyWith(waveWidth: 4), isFalse);
      expect(a.copyWith(), a);
    });

    test('copyWith changes only what it is given', () {
      const a = LineSettings(style: LineStyle.dashed, waveHeight: 2, waveWidth: 5);
      final b = a.copyWith(style: LineStyle.parallel);
      expect(b.style, LineStyle.parallel);
      expect(b.waveHeight, 2);
      expect(b.waveWidth, 5);
    });

    test('only wavy and zigzag use the wave sliders', () {
      for (final style in LineStyle.values) {
        expect(LineSettings(style: style).hasWaveParams,
            style == LineStyle.wavy || style == LineStyle.zigzag,
            reason: style.name);
      }
    });

    test('every length is a multiple of the pen width', () {
      const s = LineSettings(style: LineStyle.wavy);
      for (final f in [
        s.amplitude,
        s.wavelength,
        s.dashLength,
        s.gapLength,
        s.dotSpacing,
        s.lineGap,
        s.extraHalfWidth,
      ]) {
        expect(f(6), closeTo(3 * f(2), 1e-12));
      }
    });

    test('the default sliders give the video\'s numbers for a 2 pt pen', () {
      const s = LineSettings(style: LineStyle.wavy);
      // About 5 pt peak to peak and 15 pt long (measured on the video).
      expect(2 * s.amplitude(2), closeTo(5, 0.1));
      expect(s.wavelength(2), closeTo(15, 0.3));
      // A dash is 8.8 pt long and a gap 3.8 pt wide once the round caps (one
      // pen width) are counted.
      expect(s.dashLength(2) + 2, closeTo(8.8, 1e-9));
      expect(s.gapLength(2) - 2, closeTo(3.8, 1e-9));
      expect(s.lineGap(2), closeTo(4.4, 1e-9));
    });

    test('extraHalfWidth is how far the marks reach beyond the pen', () {
      const size = 2.0;
      for (final style in [LineStyle.solid, LineStyle.dashed, LineStyle.dotted]) {
        expect(LineSettings(style: style).extraHalfWidth(size), 0,
            reason: style.name);
      }
      const wavy = LineSettings(style: LineStyle.wavy);
      expect(wavy.extraHalfWidth(size), wavy.amplitude(size));
      const zigzag = LineSettings(style: LineStyle.zigzag, waveHeight: 8);
      expect(zigzag.extraHalfWidth(size), zigzag.amplitude(size));
      const double_ = LineSettings(style: LineStyle.parallel);
      expect(double_.extraHalfWidth(size), double_.lineGap(size) / 2);
    });

    test('labels are the names on the settings panel', () {
      expect([for (final s in LineStyle.values) s.label],
          ['Solid', 'Dashed', 'Dotted', 'Wavy', 'Zigzag', 'Double']);
    });
  });

  group('concentrationFrom', () {
    test('keeps a valid value and clamps the rest into 0.1..1', () {
      expect(concentrationFrom(0.5), 0.5);
      expect(concentrationFrom(1), 1.0);
      expect(concentrationFrom(7), 1.0);
      expect(concentrationFrom(0), minConcentration);
      expect(concentrationFrom(-2), minConcentration);
      expect(concentrationFrom(0.05), minConcentration);
    });

    test('anything that is not a finite number uses the fallback', () {
      expect(concentrationFrom(null), 1.0);
      expect(concentrationFrom('half'), 1.0);
      expect(concentrationFrom(double.nan), 1.0);
      expect(concentrationFrom(double.infinity), 1.0);
      expect(concentrationFrom(null, 0.4), 0.4);
    });
  });
}
