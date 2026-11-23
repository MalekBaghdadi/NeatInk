import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/ink/affine2.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/line_style.dart';
import 'package:neatink/ink/stroke.dart';

/// A stroke as `Stroke.toJson` would have written it before line styles
/// existed (version 1.3.0 and earlier).
Map<String, dynamic> oldJson() => {
      'id': 'old',
      'tool': 'pen',
      'penStyle': 'fountain',
      'color': '#FF1E5BD8',
      'size': 2.2,
      'raw': [
        [10, 20, 0.5, 0],
        [30, 25, 0.6, 16],
        [60, 22, 0.7, 32],
      ],
      'points': [
        [10, 20, 0.5, 0],
        [30, 25, 0.6, 16],
        [60, 22, 0.7, 32],
      ],
      // Keys of removed features must still be ignored.
      'wordId': 'w1',
      'tidy': {'x': 1},
    };

Stroke styled({
  LineSettings line = const LineSettings(style: LineStyle.wavy),
  double concentration = 0.6,
  double size = 2,
}) =>
    Stroke(
      id: 's',
      tool: StrokeTool.pen,
      penStyle: PenStyle.technical,
      color: 0xFF112233,
      size: size,
      raw: const [
        InkPoint(10, 20, 0.5, 0),
        InkPoint(50, 20, 0.5, 8),
        InkPoint(90, 40, 0.5, 16),
      ],
      line: line,
      concentration: concentration,
    );

void main() {
  group('old files', () {
    test('a stroke from before line styles is solid and fully opaque', () {
      final s = Stroke.fromJson(oldJson());
      expect(s.line, LineSettings.solid);
      expect(s.line.isSolid, isTrue);
      expect(s.concentration, 1.0);
      expect(s.penStyle, PenStyle.fountain);
      expect(s.points, hasLength(3));
    });

    test('rewriting it adds no new keys', () {
      final json = Stroke.fromJson(oldJson()).toJson();
      expect(json.containsKey('line'), isFalse);
      expect(json.containsKey('conc'), isFalse);
      expect(json.keys.toSet(),
          {'id', 'tool', 'penStyle', 'color', 'size', 'raw', 'points'});
    });

    test('a solid, opaque stroke written now equals one written before', () {
      final before = Stroke.fromJson(oldJson());
      final now = Stroke.fromJson(jsonDecode(jsonEncode(before.toJson()))
          as Map<String, dynamic>);
      expect(now.toJson(), before.toJson());
    });
  });

  group('new keys', () {
    test('`line` is written only for a styled line, `conc` only below 1', () {
      final both = styled().toJson();
      expect(both['line'], {'style': 'wavy', 'height': 3.1, 'width': 3.7});
      expect(both['conc'], 0.6);
      final lineOnly = styled(concentration: 1).toJson();
      expect(lineOnly.containsKey('line'), isTrue);
      expect(lineOnly.containsKey('conc'), isFalse);
      final concOnly = styled(line: LineSettings.solid).toJson();
      expect(concOnly.containsKey('line'), isFalse);
      expect(concOnly['conc'], 0.6);
    });

    test('they survive a JSON round trip', () {
      for (final style in LineStyle.values.skip(1)) {
        final s = styled(
            line: LineSettings(style: style, waveHeight: 5.5, waveWidth: 8),
            concentration: 0.35);
        final back = Stroke.fromJson(
            jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
        expect(back.line, s.line, reason: style.name);
        expect(back.concentration, closeTo(0.35, 1e-9));
        expect(back.penStyle, PenStyle.technical);
      }
    });

    test('a solid line keeps no slider values (they mean nothing to it)', () {
      final s = styled(
          line: const LineSettings(waveHeight: 5.5, waveWidth: 8),
          concentration: 1);
      expect(s.toJson().containsKey('line'), isFalse);
    });

    test('the concentration is written with three decimals', () {
      final json = styled(concentration: 0.123456).toJson();
      expect(json['conc'], 0.123);
    });

    test('unreadable values fall back to a solid, opaque stroke', () {
      for (final bad in <Object?>['wavy', 3, true, <Object?>[], null]) {
        final s = Stroke.fromJson({...oldJson(), 'line': bad});
        expect(s.line, LineSettings.solid, reason: '$bad');
      }
      for (final bad in <Object?>['dark', null, true, double.nan, double.infinity]) {
        final s = Stroke.fromJson({...oldJson(), 'conc': bad});
        expect(s.concentration, 1.0, reason: '$bad');
      }
    });

    test('a concentration is kept within 10% and 100%', () {
      expect(Stroke.fromJson({...oldJson(), 'conc': 0.0}).concentration,
          minConcentration);
      expect(Stroke.fromJson({...oldJson(), 'conc': -4}).concentration,
          minConcentration);
      expect(Stroke.fromJson({...oldJson(), 'conc': 7}).concentration, 1.0);
      expect(styled(concentration: 0).concentration, minConcentration);
    });

    test('a style that this version does not know is read as solid', () {
      final s = Stroke.fromJson({
        ...oldJson(),
        'line': {'style': 'sparkle', 'height': 4, 'width': 6},
      });
      expect(s.line.style, LineStyle.solid);
      expect(s.line.waveHeight, 4);
    });
  });

  group('copying and moving', () {
    test('copyWith keeps the line and the concentration', () {
      final s = styled(line: const LineSettings(style: LineStyle.parallel));
      final c = s.copyWith(color: 0xFF000000, id: 'other');
      expect(c.line, s.line);
      expect(c.concentration, s.concentration);
      final changed = s.copyWith(
          line: const LineSettings(style: LineStyle.dashed), concentration: 0.2);
      expect(changed.line.style, LineStyle.dashed);
      expect(changed.concentration, 0.2);
      expect(changed.penStyle, s.penStyle);
    });

    test('copyWith can put a solid line back', () {
      final s = styled();
      expect(s.copyWith(line: LineSettings.solid).line.isSolid, isTrue);
    });

    test('transformed keeps them and scales the width, so patterns scale', () {
      final s = styled(line: const LineSettings(style: LineStyle.zigzag), size: 2);
      final moved = s.transformed(Affine2.translation(40, 10));
      expect(moved.line, s.line);
      expect(moved.concentration, s.concentration);
      expect(moved.size, 2);
      final scaled = s.transformed(Affine2.scaling(2, 2));
      expect(scaled.line, s.line);
      expect(scaled.concentration, s.concentration);
      expect(scaled.size, closeTo(4, 1e-9));
      // A zigzag's height is a multiple of the pen width: twice as tall now.
      expect(scaled.line.extraHalfWidth(scaled.size),
          closeTo(2 * s.line.extraHalfWidth(s.size), 1e-9));
    });

    test('shape strokes keep a line style across snapping', () {
      final s = styled(line: const LineSettings(style: LineStyle.dashed));
      final snapped = s.copyWith(
          points: const [InkPoint(10, 20, 0.5, 0), InkPoint(90, 40, 0.5, 16)],
          shape: ShapeKind.line);
      expect(snapped.line.style, LineStyle.dashed);
      expect(snapped.raw, hasLength(3));
      expect(snapped.points, hasLength(2));
    });
  });

  group('paint bounds', () {
    test('a solid stroke is inflated by half its width, as before', () {
      final s = styled(line: LineSettings.solid);
      expect(s.paintHalfWidth, 1);
      expect(s.paintBounds.left, s.bounds.left - 1.5);
      expect(s.paintBounds.bottom, s.bounds.bottom + 1.5);
    });

    test('dashes and dots stay within the pen width', () {
      for (final style in [LineStyle.dashed, LineStyle.dotted]) {
        final s = styled(line: LineSettings(style: style));
        expect(s.paintHalfWidth, 1, reason: style.name);
      }
    });

    test('waves reach one amplitude further each side', () {
      for (final style in [LineStyle.wavy, LineStyle.zigzag]) {
        final line = LineSettings(style: style, waveHeight: 5);
        final s = styled(line: line);
        final amplitude = 5 * 2 * 0.4;
        expect(s.paintHalfWidth, closeTo(1 + amplitude, 1e-9), reason: style.name);
        expect(s.paintBounds.top, closeTo(s.bounds.top - (1 + amplitude + 0.5), 1e-9));
        expect(s.paintBounds.right, closeTo(s.bounds.right + 1 + amplitude + 0.5, 1e-9));
      }
    });

    test('a double line reaches half the line gap beyond the pen', () {
      final s = styled(line: const LineSettings(style: LineStyle.parallel));
      expect(s.paintHalfWidth, closeTo(1 + 2.2, 1e-9));
      expect(s.paintBounds.left, closeTo(s.bounds.left - (1 + 2.2 + 0.5), 1e-9));
    });

    test('the painted area grows with the pen', () {
      final thin = styled(size: 1, line: const LineSettings(style: LineStyle.wavy));
      final thick = styled(size: 4, line: const LineSettings(style: LineStyle.wavy));
      expect(thick.paintHalfWidth, closeTo(4 * thin.paintHalfWidth, 1e-9));
    });
  });
}
