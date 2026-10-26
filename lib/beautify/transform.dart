import 'dart:math' as math;

import '../ink/affine2.dart';
import '../ink/ink_point.dart';
import '../ink/ink_rect.dart';
import '../ink/vec2.dart';
import 'features.dart';
import 'tidy_config.dart';

/// Spec step 5: the geometry that builds the tidied points.
///
/// Conventions as in `features.dart`: page points, y down, angles in
/// radians, skew > 0 = baseline descends to the right, slant > 0 = leans
/// right. Every correction is blended by the strength `s`: it moves `s` of
/// the way from "no change" to its ideal.

/// The word-level affine of step 5a (everything except the horizontal
/// spacing shift, which needs the other words).
class WordTransform {
  const WordTransform({
    required this.matrix,
    required this.rotation,
    required this.shear,
    required this.scale,
    required this.dy,
    required this.pivot,
    required this.baselineBefore,
    required this.baselineAfter,
    required this.targetBaselineY,
    required this.snapped,
  });

  /// rotate → shear → scale → vertical translation, as one matrix.
  final Affine2 matrix;

  /// Rotation actually applied (radians, `−s·skew`).
  final double rotation;

  /// Horizontal shear coefficient `k` in `x' = x + k·(y − pivot.y)`.
  final double shear;

  /// Uniform scale `k` (after clamping).
  final double scale;

  /// Vertical translation that put the baseline on its target.
  final double dy;

  /// P0, the left end of the fitted baseline.
  final Vec2 pivot;

  /// The word's baseline at its horizontal centre, before and after.
  final Vec2 baselineBefore;
  final Vec2 baselineAfter;

  /// Where the baseline was asked to go (null = it was left where it was).
  final double? targetBaselineY;

  /// True when the target came from a ruled line or the running line.
  final bool snapped;
}

/// Builds the word transform of step 5a.
///
/// * [targetSlant] is the lean (radians, as measured by the analysis) the
///   word should end up with, or null to leave the lean alone (no reliable
///   estimate to correct from).
/// * [targetBaseline] receives the baseline's x after rotate/shear/scale and
///   its measured y before the transform, and returns the y the baseline
///   should land on, or null to keep it where it is.
WordTransform buildWordTransform({
  required WordAnalysis analysis,
  required double strength,
  required double targetXHeight,
  required double? targetSlant,
  required double? Function(double x, double measuredY) targetBaseline,
  TidyConfig config = const TidyConfig(),
}) {
  final s = strength;
  final p0 = analysis.baselineStart;

  // 1. Rotate about P0. A positive skew is a clockwise tilt and
  //    Affine2.rotation is clockwise for positive angles, so −s·θ levels it.
  final rotation = -s * analysis.skew;
  final rot = Affine2.rotation(rotation, pivot: p0);

  // 2. Shear. The analysis measured the lean φ after a *full* deskew;
  //    rotating by only −s·θ leaves a lean of φ + (1 − s)·θ (rotating a
  //    near-vertical stroke by an angle changes its lean by that angle).
  //    x' = x + k·(y − baselineY) turns the lean's tangent into tan φ − k,
  //    so to reach the blended target lean ψ = φ + s·(target − φ) we use
  //    k = tan φ − tan ψ. The spec writes tan(s·(φ − target)); the two agree
  //    for small angles, this form is exact. Points on the baseline do not
  //    move, so the shear never lifts the word off its line.
  var shear = 0.0;
  if (targetSlant != null) {
    final phi = analysis.slant.angle + (1 - s) * analysis.skew;
    final psi = phi + s * (targetSlant - phi);
    shear = math.tan(phi) - math.tan(psi);
  }
  final shearM = Affine2.shearX(shear, pivotY: p0.y);

  // 3. Scale uniformly about P0. A guessed x-height is trusted less.
  final xh = analysis.xHeight;
  var k = 1.0;
  if (xh.xHeight > 1e-6 && targetXHeight.isFinite && targetXHeight > 0) {
    final blend = (xh.reliable || xh.allCaps)
        ? s
        : s * config.unreliableXHeightBlend;
    k = (1 + blend * (targetXHeight / xh.xHeight - 1))
        .clamp(config.minScale, config.maxScale);
  }
  final scaleM = Affine2.scaling(k, k, pivot: p0);

  final m3 = scaleM * shearM * rot;

  // 4. Vertical translation: the baseline at the word's centre goes to the
  //    target baseline (blended).
  final cx = (analysis.coreBounds.left + analysis.coreBounds.right) / 2;
  final before = analysis.baselinePointAt(cx);
  final moved = m3.apply(before);
  final target = targetBaseline(moved.x, before.y);
  final dy = target == null ? 0.0 : s * (target - moved.y);
  final matrix = Affine2.translation(0, dy) * m3;

  return WordTransform(
    matrix: matrix,
    rotation: rotation,
    shear: shear,
    scale: k,
    dy: dy,
    pivot: p0,
    baselineBefore: before,
    baselineAfter: matrix.apply(before),
    targetBaselineY: target,
    snapped: target != null,
  );
}

/// Positions of [points] with non-finite entries replaced by their nearest
/// finite neighbour (previous one, else next), so the displayed stroke has
/// the same point count as the raw one and never contains NaN. Returns null
/// when no point is finite.
List<Vec2>? sanitizePositions(List<InkPoint> points) {
  final out = <Vec2?>[];
  Vec2? last;
  for (final p in points) {
    if (p.x.isFinite && p.y.isFinite) {
      last = Vec2(p.x, p.y);
      out.add(last);
    } else {
      out.add(last);
    }
  }
  Vec2? first;
  for (final p in out) {
    if (p != null) {
      first = p;
      break;
    }
  }
  if (first == null) return null;
  return [for (final p in out) p ?? first];
}

/// One stroke's vertical correction in the baseline frame (`d` = distance
/// below the baseline): `d' = pivot + scale·(d + shift − pivot)`.
class _VMap {
  const _VMap(this.shift, this.pivot, this.scale);
  static const _VMap none = _VMap(0, 0, 1);
  final double shift;
  final double pivot;
  final double scale;
  double apply(double d) => pivot + scale * (d + shift - pivot);
}

/// Spec 5b: per-stroke alignment for print handwriting. [strokes] are the
/// positions after the word transform, [shapes] the stroke classes from the
/// analysis (same order) and [baselineAt] the transformed baseline.
///
/// Only vertical moves; never horizontal. Returns [strokes] itself when the
/// word has fewer than `minNonMarkStrokesForAlignment` non-mark strokes.
List<List<Vec2>> alignStrokes({
  required List<List<Vec2>> strokes,
  required List<StrokeShape> shapes,
  required double Function(double x) baselineAt,
  required double targetXHeight,
  required double targetTallHeight,
  required double strength,
  TidyConfig config = const TidyConfig(),
}) {
  assert(strokes.length == shapes.length);
  final nonMark = [
    for (var i = 0; i < shapes.length; i++)
      if (shapes[i].strokeClass != StrokeClass.mark) i,
  ];
  if (nonMark.length < config.minNonMarkStrokesForAlignment) return strokes;

  final s = strength;
  final maxGap = config.perStrokeMaxGapFactor * targetXHeight;
  final maxScale = config.maxPerStrokeScale;

  // Extent of every stroke in the baseline frame.
  final minD = List<double>.filled(strokes.length, 0);
  final maxD = List<double>.filled(strokes.length, 0);
  final centerX = List<double>.filled(strokes.length, 0);
  for (var i = 0; i < strokes.length; i++) {
    var lo = double.infinity, hi = double.negativeInfinity;
    var xl = double.infinity, xr = double.negativeInfinity;
    for (final p in strokes[i]) {
      final d = p.y - baselineAt(p.x);
      if (d < lo) lo = d;
      if (d > hi) hi = d;
      if (p.x < xl) xl = p.x;
      if (p.x > xr) xr = p.x;
    }
    minD[i] = lo;
    maxD[i] = hi;
    centerX[i] = (xl + xr) / 2;
  }

  final maps = List<_VMap>.filled(strokes.length, _VMap.none);
  for (final i in nonMark) {
    final shape = shapes[i];
    switch (shape.strokeClass) {
      case StrokeClass.core:
      case StrokeClass.tall:
        final tall = shape.strokeClass == StrokeClass.tall;
        final targetH = tall ? targetTallHeight : targetXHeight;
        // Bottom to the baseline, unless the gap is big (probably meant) or
        // the stroke has a tail that must keep its bottom.
        final onBaseline = !shape.keepBottom && maxD[i].abs() < maxGap;
        final shift = onBaseline ? -s * maxD[i] : 0.0;
        final pivot = maxD[i] + shift;
        var scale = 1.0;
        final height = pivot - (minD[i] + shift);
        if ((onBaseline || shape.keepBottom) &&
            height >= config.minStrokeHeightForScaleFactor * targetXHeight &&
            height > 1e-6) {
          // Scaling about the pivot (the stroke's bottom) so the top lands
          // at `targetH` above the baseline: pivot − scale·height = −targetH.
          final ideal = (pivot + targetH) / height;
          scale = (1 + s * (ideal - 1)).clamp(1 - maxScale, 1 + maxScale);
        }
        maps[i] = _VMap(shift, pivot, scale);
      case StrokeClass.descender:
        // Top of the body to the x-height line when it is already close; the
        // tail moves with it, so its length is unchanged.
        final topH = -minD[i];
        if ((topH - targetXHeight).abs() < maxGap) {
          maps[i] = _VMap(s * (topH - targetXHeight), 0, 1);
        }
      case StrokeClass.mark:
        break;
    }
  }

  final out = <List<Vec2>>[];
  for (var i = 0; i < strokes.length; i++) {
    _VMap map;
    double? anchorTop;
    if (shapes[i].strokeClass == StrokeClass.mark) {
      // A mark follows the top of its nearest (horizontally) real stroke, so
      // the dot stays above its i.
      var best = nonMark.first;
      for (final j in nonMark) {
        if ((centerX[j] - centerX[i]).abs() <
            (centerX[best] - centerX[i]).abs()) {
          best = j;
        }
      }
      map = maps[best];
      anchorTop = minD[best];
      final delta = map.apply(anchorTop) - anchorTop;
      out.add([for (final p in strokes[i]) Vec2(p.x, p.y + delta)]);
    } else {
      map = maps[i];
      if (identical(map, _VMap.none)) {
        out.add(strokes[i]);
      } else {
        out.add([
          for (final p in strokes[i])
            Vec2(p.x, p.y + map.apply(p.y - baselineAt(p.x)) - (p.y - baselineAt(p.x))),
        ]);
      }
    }
  }
  return out;
}

/// Spec 5c: the horizontal shift that moves this word towards the target gap
/// after the previous word. Returns 0 (no change) when there is no previous
/// word on the line, when the words overlap or when the gap is a deliberate
/// layout gap; the shift is clamped to `maxSpacingShiftFactor × x-height`
/// and dropped (0) if it would overlap the previous word or push the word
/// past the page's right margin.
double spacingShift({
  required InkRect wordBounds,
  required double? previousRight,
  required double targetXHeight,
  required double strength,
  required double pageWidth,
  TidyConfig config = const TidyConfig(),
}) {
  if (previousRight == null || !previousRight.isFinite) return 0;
  final gap = wordBounds.left - previousRight;
  // Negative gap: the word was written before/over the previous one (an
  // insertion), not a spacing problem. Huge gap: columns, a date at the end
  // of the line …
  if (gap < 0 || gap > config.maxSpacingGapFactor * targetXHeight) return 0;
  final targetGap = config.wordSpaceFactor * targetXHeight;
  final limit = config.maxSpacingShiftFactor * targetXHeight;
  final dx = (strength * (targetGap - gap)).clamp(-limit, limit);
  if (gap + dx < 0) return 0;
  if (dx > 0 && wordBounds.right + dx > pageWidth - config.pageRightMarginPt) {
    return 0;
  }
  return dx;
}
