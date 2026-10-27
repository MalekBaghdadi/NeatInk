> **Note (session 4):** auto-tidy was removed from the app (v1.1 replaces it with "convert handwriting to typed text"). This file is kept for reference only; `lib/beautify/` now holds just the reusable geometry helpers (`features.dart`, `stats.dart`, `resample.dart`, `tidy_config.dart`).

# Tidy-as-you-write — specification (level 3)

## Goal

Make handwriting look neater **while keeping it the user's own handwriting**. After the user finishes a word, the app:

1. **Straightens** it (removes tilt, so the word sits horizontally).
2. **Fixes slant** (makes the lean consistent, or upright if the user chooses).
3. **Makes size consistent** (every word has a similar letter height).
4. **Puts it on the line** (snaps to the ruled line, or to the line the user is writing on).
5. **Evens out letters** inside a word when letters are separate strokes (print handwriting).
6. **Evens out spacing** between words.
7. **Smooths** small shakes.

It never replaces strokes with a font and never deletes ink. The original points are always kept (`raw`).

**Non-goals for now:** changing letter shapes, joining letters, recognizing words, non-Latin scripts.

The reference user writes in **print** (separate strokes per letter, e.g. "H", "e", "l", "l", "o"), so step 5 matters a lot. Cursive (one stroke per word) must also work; step 5 then simply does less.

## Where the code lives

```
lib/beautify/
  tidy_config.dart        # ALL tuning constants (see the table at the end)
  resample.dart           # uniform resampling of points
  word_segmenter.dart     # decides when a word is finished and which strokes belong to it
  features.dart           # baseline/skew, x-height, slant, stroke classification
  line_context.dart       # running state for the current line and page (baseline, x-height, slant)
  transform.dart          # the 2D affine math + composing per-word / per-stroke transforms
  tidy_pipeline.dart      # runs everything, returns a TidyResult
  smoothing.dart          # light post-smoothing
```

Everything here is **pure Dart** with no Flutter imports, so it can be unit tested and run in an isolate.

Public API (suggested):

```dart
class TidyResult {
  final String wordId;
  final Map<String, List<InkPoint>> newPoints; // strokeId -> tidied points
  final Affine2 wordTransform;                 // for debugging / overlay
  final WordFeatures features;                 // detected baseline, xHeight, slant, etc.
}

TidyResult? tidyWord({
  required List<Stroke> wordStrokes,     // uses each stroke's RAW points
  required LineContext line,             // running stats for this line
  required PageContext page,             // paper type, ruled-line spacing, page width
  required TidySettings settings,        // strength, slant mode
  Stroke? previousWordLastStroke,        // for spacing; null if first word on the line
});
```

Return `null` when the word should be left alone (see "When NOT to tidy").

## Step 0 — Preprocessing

- **Resample** each stroke's raw points to a uniform spacing of `resampleStepPt` (default 1.0 pt) for **analysis only**. Never store the resampled points.
- Ignore points with NaN/infinite values.
- Measure everything in page points (see CLAUDE.md "Coordinate system"; y points down).

## Step 1 — Word segmentation (deciding when a word is finished)

Keep a list of "pending" strokes: pen strokes drawn since the last word was committed.

A pending word is **committed** (sent to the pipeline) when any of these happens:
- **Idle timeout:** no pen-down for `wordIdleMs` (default 650 ms) after the last pen-up.
- **Gap:** a new stroke starts with its left edge more than `wordGapFactor × xHeightEstimate` (default 0.9×) to the right of the pending word's right edge, on the same line. The new stroke starts a new pending word.
- **New line:** a new stroke's vertical center is more than `newLineFactor × lineHeight` (default 0.7×) away from the pending word's baseline. Here `lineHeight` = ruled spacing on lined paper, otherwise `2.5 × xHeightEstimate`.
- **Tool change, page change, or the tidy toggle turned off.**

`xHeightEstimate` comes from `LineContext` (running median). Before any words exist, use `0.4 × ruled spacing` on lined paper, or `9 pt` otherwise.

**Late marks (dots on i/j, crossing a t, accents):** if a *small* stroke (bounding box diagonal < `smallMarkFactor × xHeight`, default 0.45) or a *short horizontal* stroke (width < 1.5 × xHeight, height < 0.3 × xHeight) is drawn **after** a word was tidied and it lands inside that word's tidied bounding box (expanded by `0.3 × xHeight`), attach it to that word (`wordId`) **without moving it**. The user drew it relative to the already-tidied word, so it's already in the right place.

## Step 2 — When NOT to tidy (return null)

Skip the whole word if any of these are true:
- It contains a highlighter stroke (highlighters are never tidied).
- The word's bounding box height > `maxWordHeightFactor × lineHeight` (default 2.2): probably a drawing or diagram.
- Any stroke's width > `maxStrokeWidthFactor × xHeight` (default 12) and its height < 0.5 × xHeight: probably an underline or a long line.
- The word has fewer than `minPointsForTidy` resampled points (default 12).
- The word is a strike-through or scribble over existing tidied ink (it overlaps another word's tidied box by > 50%).
- Estimated skew > `maxSkewDeg` (default 20°) or slant beyond `maxSlantDeg` (default 40°): probably intentional, so leave it.

Skipped words are still recorded as "words" (so spacing for the next word works), just with no changes.

## Step 3 — Feature detection

### 3a. Baseline and skew (tilt)
1. From the resampled points, find **bottom extrema**: points where y is a local maximum (y points down) along each stroke, using a window of ±3 samples. Include each stroke's final point if it's a local max.
2. Remove descender extrema (g, p, y, j, q tails). Let `m` = median y of all bottom extrema. Drop extrema with `y > m + 0.35 × (bboxHeight)`.
3. Fit a line `y = a·x + b` to the remaining extrema with **least squares + one round of outlier removal** (drop points with residual > 2× median absolute residual, then refit). RANSAC is fine too.
4. Skew angle `θ = atan(a)`.
5. **Short words are unreliable.** If the word width < `minWidthForSkew × xHeight` (default 2.5) or there are fewer than 3 extrema, don't use its own θ. Use `line.skew` (running median of the current line's skews), or 0 if there's no line yet.
6. Blend with the line: `θ_final = 0.6·θ_word + 0.4·line.skew` when the line already has ≥ 2 words. This keeps words on one line consistent.

### 3b. x-height (the height of letters like a, e, o)
After rotating the points by −θ around the word's baseline start (so the word is horizontal):
1. Find **top extrema** (local minima of y).
2. Heights `h_i = baselineY − y_i`. Keep only positive ones.
3. Remove ascender/capital tops (b, d, h, k, l, t and capitals): let `hm` = median(h). Drop `h_i > 1.45 × hm`. If more than 60% of tops would be dropped (an all-caps word like "HELLO"), keep them all and mark the word `allCaps = true`.
4. `xHeight = median(remaining h)`. Fallback if there are fewer than 2 values: `0.45 × bboxHeight`.

### 3c. Slant (lean)
1. Take segments between consecutive resampled points. Keep **near-vertical** ones: angle within ±45° of vertical, length ≥ 0.5 pt.
2. For each, the slant angle φ_i = angle from vertical (positive = leaning right).
3. Slant `φ = length-weighted median of φ_i`. A weighted median is more robust than a mean.
4. If the total length of near-vertical segments is < 1.5 × xHeight, the estimate is unreliable: use `line.slant`.

### 3d. Stroke classification (for print handwriting, step 5)
For each stroke in the word, after deskew, compute its top `t` and bottom `b` relative to the baseline, measured in units of xHeight:
- **mark**: bounding box diagonal < 0.45 × xHeight (dots, small accents, apostrophes). Never resized; repositioned only with the word.
- **descender**: bottom below the baseline by more than 0.35 × xHeight (g, p, y, q, j).
- **tall**: top above the baseline by more than 1.45 × xHeight (b, d, h, k, l, t, capitals, digits).
- **core**: everything else (a, c, e, m, n, o, r, s, u, v, w, x, z).
- A stroke can be both tall and descender (f in some styles): treat as **tall**, but don't change its bottom.

## Step 4 — Targets

Targets make words consistent with each other. They come from the paper (if lined) or from the running median of recent words.

- **Target x-height**
  - Lined paper: `targetX = lineXFactor × spacing` (default 0.36). Example: 26 pt spacing → ~9.4 pt x-height.
  - Otherwise: `targetX = median xHeight of the last 12 tidied words on this page`, or this word's own x-height if it's the first.
- **Target baseline**
  - Lined paper: the nearest ruled line to the word's measured baseline (at the word's horizontal center). Only snap if within `0.5 × spacing`; otherwise use the measured baseline.
  - Blank paper / PDF: the current line's baseline, extended to this word's x position (`line.baselineAt(x)`). For the first word on a line, use the word's own baseline (rotated flat).
- **Target slant**
  - Setting **"Keep my slant"** (default): `targetSlant = running median slant of the last 20 words on this page` (so the lean is *consistent* but still the user's own).
  - Setting **"Upright"**: `targetSlant = 0`.
- **Target tall height** (for tall strokes): `targetTall = running median of tall-stroke heights / xHeight` × targetX, clamped to [1.6, 2.4] × targetX. Default ratio 1.9 if unknown.

## Step 5 — Build and apply the transform

All corrections are blended by **strength** `s`: Light = 0.5, Medium = 0.8 (default), Strong = 1.0.
For any correction with "ideal" value v and "no change" value v0, apply `v0 + s·(v − v0)`.

### 5a. Word-level transform (one affine for the whole word)
Use the word's baseline start point `P0` (left end of the fitted baseline) as the pivot. In order:
1. **Rotate** around P0 so the fitted baseline turns `s·θ_final` back toward horizontal (at s = 1 it becomes exactly horizontal). Watch the sign: y points down.
2. **Shear** horizontally to fix slant: `x' = x + tan(s·(φ − targetSlant)) · (y − baselineY)`. Check: for a right-leaning word (φ > 0), a point above the baseline has `y − baselineY < 0`, so it moves left and the word stands up. Pivot on the baseline, so the baseline doesn't move.
3. **Scale** uniformly by `k = 1 + s·(targetX/xHeight − 1)`, clamped to [`minScale`, `maxScale`] = [0.75, 1.35]. Pivot on P0.
4. **Translate vertically** so the baseline lands on the target baseline: `dy = s·(targetBaselineY − baselineY')`, where `baselineY'` is the baseline after steps 1–3.
5. **Translate horizontally** for spacing (step 5c).

Compose these into one `Affine2` and apply it to the stroke's **raw** points.

### 5b. Per-stroke alignment (print handwriting)
Only when the word has ≥ 2 non-mark strokes. After the word transform:
- **core** strokes: move vertically so their bottom sits on the baseline: `dy = s·(baseline − bottom)`, but **only if** `|baseline − bottom| < 0.3 × targetX` (bigger gaps are probably intentional). Then scale vertically around the baseline toward `targetX`, by at most ±15% (`maxPerStrokeScale`), blended by s.
- **tall** strokes: bottom → baseline (same rule); scale toward `targetTall`, max ±15%.
- **descender** strokes: align the *top* of the stroke's main body to the x-height line if it's within 0.3 × targetX; don't change the length of the tail.
- **marks**: move by the same amount as the nearest non-mark stroke horizontally (so the dot stays above its i).
- Never move a stroke horizontally in this step.

### 5c. Word spacing
If there's a previous word on the same line (tidied or not):
- `gap = left edge of this word (after 5a/5b) − right edge of the previous word`.
- `targetGap = wordSpaceFactor × targetX` (default 1.0).
- Shift this word horizontally by `dx = s·(targetGap − gap)`, clamped to ±`maxSpacingShiftFactor × targetX` (default ±0.8).
- Don't shift left so far that it overlaps the previous word. Don't shift right if it would push the word past the page's right margin. Then set dx = 0.
- Only move the current word; never move already-finished words.

### 5d. Light smoothing
On the transformed points, apply one pass of a 3-point weighted moving average `(0.25, 0.5, 0.25)` to x and y. Keep the first and last points fixed. Leave pressure unchanged. Skip strokes with fewer than 5 points.

## Step 6 — Show it to the user

- **Animate** from the current points to the tidied points over `animMs` (default 180 ms), with ease-out. Interpolate each point (raw and tidied have the same point count because the transform is applied point by point; smoothing doesn't change the count).
- During the animation, the word is drawn on the live layer. When it ends, commit to the ink layer.
- If the user starts writing again during the animation, finish the animation instantly (jump to the end).
- The tidy is **one undo step** (`ApplyTidy` command storing the old and new `points`). Undo restores the untidied look; the word is then marked so it isn't tidied again automatically.
- "Restore original" (lasso) sets `points = raw` and marks `tidy.applied = false`.

## Step 7 — Running context (`LineContext` / `PageContext`)

- A **line** is a group of words whose baselines are within `0.5 × lineHeight` of each other. Store per line: the list of words, the fitted baseline (line through all word baselines), and median skew, slant and xHeight.
- **Page** stats: rolling windows (last 12 x-heights, last 20 slants, last 20 tall ratios).
- Rebuild context lazily from stored strokes when a page is opened (the stats are cheap to recompute). Don't persist it.

## Performance

- The whole pipeline for one word must take **< 8 ms** on the tablet. Words have a few hundred points at most, so this should be easy.
- Measure with `Stopwatch` in debug builds and log words that take longer. If it's slow, move it to `Isolate.run`. The UI must never wait for it.

## Debug overlay (settings → Developer)

For each word, draw:
- the fitted baseline (blue), the x-height line (green), the slant line (orange) and the bounding box (grey);
- small text with θ, φ, xHeight and scale `k`;
- stroke classes as colored dots (core / tall / descender / mark).

This is how the owner will tune the numbers. Keep it cheap and off by default.

## Tests (required)

Make a tiny synthetic "font" in the test folder: simple polyline letters (l, o, e, h, n, g, i with a dot, H, capital E) built from line segments and arcs, with a baseline at y = 0 and x-height = 10.

Build words from it ("hello", "line", "go", "HE", "i"), then distort them with known values and run the pipeline at strength 1.0:

| Test | Distortion | Expect after tidy |
|---|---|---|
| Deskew | rotate 8° | baseline angle within ±1° |
| Slant (upright mode) | shear 20° | slant within ±3° of 0 |
| Slant (keep mode) | words at 10°, 12°, 25° | third word's slant ends within ±4° of ~11° |
| Size | scale 1.3× with target x-height 10 | x-height within ±5% of 10 |
| Snap to line | baseline 4 pt off a ruled line | baseline within 0.5 pt of the line |
| Per-stroke | in "hello" (print), raise the "e" by 2 pt | "e" bottom within 0.5 pt of the baseline |
| Descender kept | "go" | tail of g still below the baseline by ≥ 0.6 × xHeight |
| Dots | "i" | dot stays above the stem (horizontal offset < 1 pt) |
| Spacing | gap 25 pt, target 10 | gap within 10 ± 1 pt (clamping considered) |
| Skip drawing | a 60 pt tall circle | returns null |
| Skip underline | 150 pt horizontal line | returns null |
| Strength | Light vs Strong on the same skewed word | Light corrects about half the skew |
| Raw kept | any | `raw` unchanged byte-for-byte |
| Determinism | same input twice | identical output |

Also test word segmentation with timed point sequences: idle timeout, a large gap, a new line, and a late dot.

## Tuning constants (`tidy_config.dart`)

| Name | Default | Meaning |
|---|---|---|
| resampleStepPt | 1.0 | analysis resampling distance |
| wordIdleMs | 650 | idle time that ends a word |
| wordGapFactor | 0.9 | gap (× xHeight) that starts a new word |
| newLineFactor | 0.7 | vertical jump (× lineHeight) that starts a new line |
| smallMarkFactor | 0.45 | max size (× xHeight) of a dot/mark |
| maxWordHeightFactor | 2.2 | taller than this (× lineHeight) = drawing, skip |
| maxStrokeWidthFactor | 12 | wider than this (× xHeight) and flat = underline, skip |
| minPointsForTidy | 12 | too few points = skip |
| maxSkewDeg | 20 | more tilt than this = intentional, skip |
| maxSlantDeg | 40 | more slant than this = intentional, skip |
| minWidthForSkew | 2.5 | words narrower than this (× xHeight) borrow line skew |
| lineXFactor | 0.36 | target x-height on lined paper (× spacing) |
| minScale / maxScale | 0.75 / 1.35 | word scale clamp |
| maxPerStrokeScale | 0.15 | per-stroke vertical scale limit (±) |
| wordSpaceFactor | 1.0 | target word gap (× xHeight) |
| maxSpacingShiftFactor | 0.8 | max horizontal shift (× xHeight) |
| strength (L/M/S) | 0.5 / 0.8 / 1.0 | blend amount |
| animMs | 180 | tidy animation length |

These are starting guesses. Expect the owner to tune them on the tablet with the debug overlay.
