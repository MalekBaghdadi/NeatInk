# Ruler and line styles — design

Date: 2026-11-23 · Written by the lead session (Claude) for the repo owner.
Status: the owner asked for this directly ("implement this feature … recreate the same
menu from the video"), so there was no separate approval round. The calls in section 4
are the lead's; the owner can veto any of them.

**Built in v1.4.0:** packages F, P and R. **Not built:** package S (restyle a lasso selection).

## 1. Intent

The owner sent a TikTok (@kamilstudies_, video 7708028658421714184, 15.7 s). It shows
Notability on an iPad: lines drawn with a **ruler**, then restyled with different
**pens and markers** and a **pen settings menu** (thickness and, above all, the **kind
of line**: dotted, wavy, zigzag, double). The owner wants that in NeatInk ("Mariam's
Notes") and wants **the same menu** recreated.

## 2. What the video shows (this is the spec)

Reference frames were saved from the video while designing (they are not in the repo):

| File | Shows |
|---|---|
| `panel_t12_0.jpg` | the pen settings panel, fully visible (a hand covers its right part) |
| `panel_t11_7.jpg` | the same panel fading in: shows the wave sliders' values (3.1 and 3.7), the steppers and the "Horizontal drawing" switch |
| `ruler_t4_5.jpg` | the ruler, with a line being drawn along its top edge |
| `lines_t15_6.jpg` | zoom on the finished wavy, zigzag and double lines |
| `radial_t13_0.jpg` | the Apple Pencil squeeze palette (not built, see non-goals) |
| `toolbar_t14_5.jpg` | the right end of the toolbar: size dots, the **pill**, colour dots |

The story of the video: four labels "Normal / Beginner / Pro / Legend", each with a line
under it. Normal = a wobbly freehand line. Beginner = a line drawn along the **ruler**.
Pro = a hand-drawn line that snaps straight. **Legend** = the Technical Pen with line
styles: solid, dashed, wavy, zigzag, double.

### 2.1 The ruler (t = 3 – 5 s)
* A translucent band across the page, about 12% of the screen width thick, as long as
  the screen is wide. Barely any fill; its two long edges are drawn as **tick scales**.
* Ticks are in centimetres: small ticks every mm, a medium one every 5 mm, a long one
  every cm, with the cm number under the long tick. Numbers count **outward from the
  centre**: `9 8 7 … 1 | 1 2 3 … 9`.
* The **top edge** has its ticks and numbers just inside it, upright. The **bottom
  edge** has the mirror image, with the numbers turned 180° (readable from the other
  side).
* In the centre: a small **dotted circle with the angle**, "0°".
* The pen draws a perfectly straight line along an edge: the ink follows the edge
  whatever the pen does (t = 4.5: the red line runs from the centre mark to the pen).
* The ruler is moved and turned with the fingers; the label shows the angle.

### 2.2 The pen settings panel "Technical Pen" (t = 11.5 – 13 s)
A rounded, translucent ("glass") card, about 0.45 × the screen width, portrait. Top to
bottom, with the exact labels:
1. Header: a **Reset** pill button on the left (greyed out when nothing differs), the
   title **Technical Pen** centred.
2. **Thickness**, value `2.0` on the right between two small circled **− / +** steppers;
   a slider under it (range about 0.1–10; the thumb at 2.0 sits at ~20%).
3. **Concentration**, value `100%` on the right; a slider.
4. **Line Style**, then chips in a 3-column grid: row 1: *solid*, *dashed*, *wavy*; row 2:
   *zigzag*, *double*. Each chip is a rounded pill showing a tiny sample of the line.
   The selected chip has a lilac fill and a thin lilac outline.
5. **Wavy Line Height**, value `3.1` with − / + steppers; a slider.
6. **Wavy Line Width**, value `3.7` with − / + steppers; a slider.
7. **Horizontal drawing**, an on/off switch (off in the video).
8. A hairline divider.
9. **Color**: a header row with two small icons on the right (a swatches icon and a
   rainbow colour-wheel); under it a grid of round swatches, 6 per row, 3 rows; the
   first (black) is selected, the last cell is a **+** button for a custom colour.

Sliders: a thin grey track, the part left of the thumb filled lilac, the thumb a white
rounded pill with a soft shadow.

### 2.3 The line styles (measured on `lines_t15_6.jpg`, pen 2.0 pt)
All lengths below are in multiples of the pen width `w`.
* **Dashed**: a dash looks about 4.4 w long, a gap about 1.9 w (round caps).
* **Wavy**: a smooth sine, 2.5 w high peak to peak, one wave every ≈ 7 w (sliders 3.1 / 3.7).
* **Zigzag**: a triangle wave with sharp corners, here 5.7 w high and ≈ 23 w per wave (the
  author moved the sliders up before drawing it; same two sliders as the wave).
* **Double**: two parallel lines, centres ≈ 2 w apart.
* All five end where the pen lifted; the patterns start and end cleanly on the line.

### 2.4 The toolbar (t = 14.5 s)
A **pill** in the toolbar shows a miniature of the current line style (a single line at
t = 11, two parallel lines at t = 14.5): it is the current style's indicator and the way
into the settings. Tapping the already-selected pen also opens the panel.

## 3. Goals, non-goals, anti-goals

**Goals**
1. A **ruler** that can be put on the page, moved and rotated with fingers; the pen
   draws straight lines along its edges.
2. **Line styles** for lines: solid, dashed, dotted, wavy, zigzag, double.
3. The **pen settings panel**, recreated from the video (section 2.2), for the pen and
   the highlighter; live (changes apply to the next stroke).
4. Different pens and markers: the existing ballpoint / fountain / pencil / highlighter
   plus a new **Technical pen** (constant width).
5. Existing lines can be **restyled** with the lasso (thickness, concentration, line
   style, colour), in one undo step.
6. Everything goes into the **PDF export** exactly as on screen.

**Non-goals** (offer later): the squeeze arc palette, saved pen presets, a ruler that
is saved in the notebook, calibrated centimetres (the ticks are approximate, see 4.2),
pressure-sensitive patterns.

**Anti-goals / hard rules** (CLAUDE.md): never lose ink (`raw` keeps what the pen drew),
no new dependency, no network, atomic saves untouched, old notebooks and old tool prefs
must load unchanged, old app versions must still open new files (unknown keys ignored).

## 4. Calls made by the lead (veto-able)

1. **The ruler is a screen overlay**, not part of the page: it stays put while the page
   scrolls or zooms (like the video, and like a real ruler lying on the tablet). It is
   not saved in the notebook and starts hidden each time the editor opens.
2. **Ticks are in physical-ish centimetres**: 1 cm = 160/2.54 logical pixels (Android's
   160 dpi definition). Real screens differ by up to ~15%, so it is a drawing aid, not a
   measuring tool.
3. **Six line styles**, not five: the video's five plus **dotted**, because the owner
   said "dotted". The grid is 3 × 2: Solid, Dashed, Dotted / Wavy, Zigzag, Double.
4. **Line styles work for every pen, the highlighter and shapes**, not only the
   Technical pen (a wavy highlighter or a dashed rectangle is just as useful).
   Patterns are drawn with a constant width.
5. **"Horizontal drawing"** = the stroke becomes a straight horizontal line from where
   the pen landed. (The video does not say more; this is the natural reading.)
6. **Ruler lines and horizontal lines are `ShapeKind.line` strokes** whose `raw` keeps
   the real pen path, exactly like hold-to-snap lines; "Restore original" works on them.
7. **Concentration** is the ink's opacity (10–100%), multiplied with the tool's own
   opacity (the highlighter stays translucent).
8. The settings panel uses the app's **theme colours** (indigo seed; its container tones
   are close to the video's lilac) so dark mode works, with the video's layout and labels.
9. **Reset** restores thickness, concentration, line style and horizontal drawing; it
   keeps the colour and which pen it is.

## 5. How it fits together

```
 pen sample ──► InkToolHandler ──(ruler? horizontal?)── StrokeConstraint.project()
                    │   live: ActiveStroke.preview = ShapeKind.line from project(start) to project(now)
                    │   commit: Stroke(raw: real pen path, points: the line, shape: line,
                    ▼                 line: LineSettings, concentration)
              AddStrokesCommand ─► PageContent ─► JSON (keys `line`, `conc` only when set)
 render:  Stroke ─► patternPolylines()  (ink/, pure Dart: dashes, dots, waves, zigzag, 2 lines)
                 ─► perfect_freehand outline per polyline ─► strokeOutlines() : List<List<Offset>>
                 ─► screen: one Path of all polygons      PDF export: one ExportPolygon each
```

Already in the tree (compiles, `flutter analyze` is clean) — **read these first**:
* `lib/ink/line_style.dart` — `LineStyle`, `LineSettings` (+ the pattern constants and
  JSON), `concentrationFrom`.
* `lib/ink/line_pattern.dart` — `patternPolylines(...)`: **a stub**, package F fills it.
* `lib/ink/stroke.dart` — `PenStyle.technical`; `Stroke.line`, `Stroke.concentration`,
  `paintHalfWidth`, JSON, `copyWith`, `transformed`.
* `lib/render/stroke_outline.dart` — technical pen options, concentration in the fill
  colour, `strokeOutlines` (**stub, solid only**), `cachedStrokeOutlines`,
  `outlinesPath`.
* `lib/features/editor/tool_prefs.dart` — `PenPrefs` / `HighlighterPrefs` with `line`,
  `concentration`, `horizontal`; `ToolPresets.penSizeMin/Max`, `highlighterSizeMin/Max`.
* `lib/features/editor/editor_controller.dart` — `setPenLine`, `setPenConcentration`,
  `setPenHorizontal`, `resetPen`, and the same four for the highlighter.
* `lib/features/editor/canvas/{stroke_constraint,stroke_builder,live_ink,ink_tool_handler}.dart`
  and `integrations/shapes/shape_tool_handler.dart` — line and concentration are
  plumbed from the prefs to the committed stroke; `ActiveStroke.constraint` exists but
  nothing sets it yet.
* `lib/features/editor/editor_extensions.dart` — new extension points
  `TouchInterceptor touchInterceptor`, `StrokeConstraintProvider strokeConstraint`,
  `toolRowActions`.

## 6. Work packages

Four workers, each owning **only** the files listed. Nobody else edits them. If you need
a change in a file you don't own, say so in your report (do not edit it).

### Package F — pattern geometry, rendering, export, tools (foundation)
Owns: `lib/ink/line_pattern.dart`, `lib/render/stroke_outline.dart`,
`lib/features/editor/canvas/live_ink.dart` (the `LiveInkPainter` only),
`lib/pdf/export_builder.dart`, `lib/features/editor/tools/{stroke_eraser,lasso,pixel_eraser}.dart`,
the four Convert exclusion sites (see below), and tests under `test/ink`, `test/render`,
`test/pdf`, `test/editor_tools` (new files or additions).

1. **`patternPolylines`** (pure Dart, no `dart:ui`):
   * `w = max(size, 0.25)`. Drop non-finite points and consecutive points closer than
     1e-4; compute the arc length. With fewer than 2 distinct points or a total length
     under 1e-3 return `[points]` (a tap stays a dot, whatever the style). `solid`
     returns `[points]` itself (same list object).
   * **dashed**: `dash = line.dashLength(w)`, `gap = line.gapLength(w)`. Fit them to the
     length `L`: `n = max(1, round((L + gap) / (dash + gap)))`, `k = (L + gap) / (n *
     (dash + gap))`, use `dash*k`, `gap*k`, so the first dash starts at 0 and the last
     one ends at `L`. If `L <= dash` the whole path is one dash. Each dash is the base
     path between its two arc lengths (interpolated end points).
   * **dotted**: `n = max(1, round(L / line.dotSpacing(w)))`, a dot at `j * L / n` for
     `j = 0..n`, each a one-point polyline.
   * **wavy**: `A = line.amplitude(w)`, `λ = max(line.wavelength(w), 2w)`, fitted to a
     whole number of waves `λ' = L / max(1, round(L/λ))`; sample every `λ'/16` (raise the
     step if it would exceed 20 000 samples); point = base(s) + normal(s) · A · sin(2π s/λ').
     One polyline that starts and ends on the base path.
   * **zigzag**: same `A`, `λ'`; vertices every quarter wave with offsets
     `0, +A, 0, −A, 0, …`, plus extra samples so consecutive points are never more than
     3 pt apart (so a curved base is followed). One polyline.
   * **parallel**: two polylines offset by `±line.lineGap(w)/2` along the normal; use the
     miter scale `1/cos(half the turning angle)` at corners, clamped to 2.
   * normal(s) = `(-t.y, t.x)` of the unit tangent. With `smooth` true, more than 2 points
     and style wavy / zigzag / parallel: first resample the base every `clamp(w, 0.75, 3)`
     pt and apply two passes of the `[1,2,1]/4` filter to the interior points (end points
     fixed). With `smooth` false use the vertices as they are (generated shapes keep
     their corners).
   * Generated points interpolate pressure and `t` by arc length. Never throws, never
     returns NaN, handles huge inputs fast (50 000 points in well under a second).
2. **`strokeOutlines`**: empty points → `const []`; solid → exactly today's single polygon;
   otherwise `patternPolylines(s.points, s.line, s.size, smooth: s.shape == null)` and one
   perfect_freehand polygon per polyline with the options `size: s.size, thinning: 0,
   smoothing: 0.2, streamline: 0, simulatePressure: false`, `isComplete: true`, round caps
   (flat caps for the highlighter, like `strokeOptionsFor`). Keep polygons with 3+ points.
   **Check what `getStroke` does with a one-point polyline** (a dot). If it is not a round
   dot of diameter `size`, build the circle polygon by hand (at least 12 segments).
   `isComplete` for the live stroke: patterns ignore it (every mark is complete).
3. **Use it everywhere**: `LiveInkPainter` draws `outlinesPath(strokeOutlines(...))`; the
   PDF `buildExportPage` adds one `ExportPolygon` per polygon of
   `cachedStrokeOutlines(stroke)` (same colour); `cachedStrokePath` already unions them.
4. **Reach**: stroke eraser, lasso and pixel eraser must also hit the wave crests and the
   second line: add `stroke.line.extraHalfWidth(stroke.size)` to their reach
   (`stroke_eraser.dart:22`, `lasso.dart:194`, `pixel_eraser.dart:68`).
5. **Pixel eraser pieces keep `line` and `concentration`** (both `Stroke(...)` calls in
   `pixel_eraser.dart`).
6. **Convert ignores line-styled strokes**: add `|| !s.line.isSolid` next to the
   existing `s.shape != null` checks in `auto_convert_session.dart` (two places),
   `convert_scope.dart` and `recognition/stroke_grouping.dart`.
7. Tests (new files): `test/ink/line_style_test.dart` (JSON round trip, tolerant reads,
   clamping), `test/ink/line_pattern_test.dart` (every style: counts, fitted ends,
   amplitude and period, offsets, pressure carry, degenerate input, speed),
   additions for `Stroke` JSON (old JSON loads solid and opaque; new keys only when
   set; `copyWith` / `transformed` keep them; `paintBounds` includes the amplitude),
   `test/render/stroke_outline_test.dart` (one polygon for solid, many for dashed,
   two for double, concentration in the fill colour, technical pen constant width),
   `test/pdf/export_builder_test.dart` additions (a dashed stroke exports several
   polygons), eraser / lasso / pixel-eraser reach and piece-keeps-style tests, and a
   `ToolPrefs` JSON test (old prefs load, new fields round-trip).

### Package P — settings panel, toolbar, previews
Owns: `lib/features/editor/toolbar/**` (new files and `tool_options.dart`,
`editor_tool_row.dart`, `toolbar_widgets.dart`), tests under `test/editor/toolbar/`.

New files (suggested names): `ink_settings_model.dart`, `ink_settings_panel.dart`,
`line_style_widgets.dart` (chip, preview, pill), `ink_sliders.dart`.

* **`InkSettingsModel`**: what the panel edits, so the same panel serves the pen, the
  highlighter and (package S) a lasso selection: title, `size` + min/max, `concentration`,
  `LineSettings line`, `bool? horizontal` (null = hide the switch), `int? color`,
  and the callbacks `onSize`, `onConcentration`, `onLine`, `onHorizontal`, `onColor`,
  `onReset`, `onCustomColor`, plus a `Listenable` the panel rebuilds on.
  `InkSettingsModel.forPen(controller)` and `.forHighlighter(controller)` read
  `controller.toolPrefs` and call the controller setters from section 5.
  Slider callbacks for the selection variant fire on *release* (`onChangeEnd`) so one
  drag is one undo step; give the model a flag `commitOnRelease` for that.
* **`InkSettingsPanel`**: section 2.2, top to bottom, with these **exact strings**:
  `Reset`, the pen name as the title (`penStyleName(style)`; `Highlighter` for the
  marker), `Thickness`, `Concentration`, `Line Style`, `Wavy Line Height`,
  `Wavy Line Width`, `Horizontal drawing`, `Color`. The wave sliders show only for wavy
  and zigzag (animate the height). The grid has 6 chips: Solid, Dashed, Dotted / Wavy,
  Zigzag, Double, each with a tooltip and a sample drawn by the **real renderer**
  (`strokeOutlines` of a short horizontal stroke, like `PenStylePreview`). The colour
  grid: 6 per row, the 8 preset colours, then the recent custom colours, then a **+**
  (opens the existing `showColorPickerDialog`); the header's rainbow button does the
  same. Value formats: thickness `2.0` (1 decimal), concentration `100%`, waves `3.1`.
  Steppers step by 0.1 for thickness, 0.1 for the wave values. Sliders: thin track, the
  filled part in `scheme.primary` at ~55% alpha, a white rounded-pill thumb (about 30 ×
  20) with a soft shadow. Chips: stadium shape, selected = `primaryContainer` fill with
  a 1.5 dp `primary` outline. Card: width 340 dp, radius 28, translucent surface
  (`surfaceContainerHigh` at ~92%) with a `BackdropFilter` blur, hairline border, soft
  shadow, scrollable when the screen is short (max height 90% of the screen).
  Use `ValueKey`s: `ink-settings-panel`, `ink-settings-reset`, `ink-settings-thickness`,
  `ink-settings-concentration`, `ink-settings-line-<style name>` (e.g.
  `ink-settings-line-wavy`), `ink-settings-wave-height`, `ink-settings-wave-width`,
  `ink-settings-horizontal`, `ink-settings-color-<argb decimal>`, `ink-settings-color-add`.
* **`showInkSettingsPanel(BuildContext, InkSettingsModel)`**: a `showGeneralDialog` with a
  transparent barrier (tap outside closes), fade + slight scale in, anchored top-right
  under the tool row.
* **Toolbar**: in `PenOptions` and `HighlighterOptions` add, after the width dots, a
  divider and the **pill** (a stadium button, 64 × 32, showing a miniature of the current
  line style in the pen colour, tooltip `Pen settings` / `Highlighter settings`) that opens
  the panel. In `_ToolButtons` (editor_tool_row.dart) tapping the **already selected** pen
  or highlighter opens its panel; also render `controller.extensions.toolRowActions` after
  the tool buttons (a divider before them when there are any).
* The Technical pen shows up in `PenStyleMenu` automatically; give `PenStylePreview` a
  sensible sample for it.
* Tests: panel shows all labels; chip taps call the model; wave sliders hide for solid
  and show for wavy and zigzag; Reset is disabled at defaults; the pen model writes
  through `controller.toolPrefs`; the pill opens the panel; tapping the selected pen opens
  it; light and dark theme build without overflow on 360 × 800 and 1280 × 800 screens.

### Package R — ruler
Owns: `lib/features/editor/integrations/ruler/**` (all new), `canvas/document_view.dart`,
`canvas/ink_tool_handler.dart`, `integrations/shapes/hold_snap_hook.dart`,
`default_integrations.dart`, tests under `test/editor/integrations/ruler/` and
`test/editor/canvas/` (new files).

* **`RulerGeometry`** (immutable, plain Dart + `dart:ui` `Offset`): `center`, `angle`
  (radians, 0 = horizontal, positive = clockwise on screen), `length`, `thickness`.
  `axis`, `normal` (= `(-sin a, cos a)`, pointing "down" at angle 0), the corner points,
  `containsPoint(p, slop)`, `nearestEdge(p, maxDistance)` → `RulerEdge.top` / `.bottom`
  / null (the point must also lie within the ruler's length plus a small margin),
  `project(p, edge)` → the point of that edge line closest to `p`, **clamped to the
  ruler's length** (the line cannot run past the ruler's end), and
  `displayAngleDegrees` (counter-clockwise positive, in `[0, 180)`, one decimal).
* **`RulerModel extends ChangeNotifier`**: `visible`, `geometry`; `show(Size viewport)`
  (first time: centred horizontally, at 38% of the height, angle 0, length 92% of the
  width clamped to 360..1500 px, thickness 96 px), `hide()`, `toggle(viewport)`,
  `translate(Offset)`, `rotateBy(radians)` with **angle snapping**: within ±2.5° of a
  multiple of 15° the shown angle snaps to it (keep the unsnapped angle underneath so
  the snap does not make the ruler stick), `fit(Size)` after a resize (keep the centre
  inside the viewport, length ≤ width).
* **`RulerGesture`**: one finger moves the ruler; a second finger (anywhere) makes it a
  two-finger move + rotate (translation of the midpoint, rotation by the change of the
  angle between the fingers). Pure maths with its own unit tests. A third finger is not
  claimed.
* **`RulerTouchInterceptor implements TouchInterceptor`**: claims a touch that lands on
  the ruler body (rotated rectangle, 14 px slop), or any touch while a one-finger ruler
  gesture is running (to let a second finger join). With `fingerDraws` true it does not
  claim touches within the pen snap band of an edge (those should draw). Never claims
  when the ruler is hidden.
* **`RulerEdgeConstraint implements StrokeConstraint`** (+ the provider function): at
  pen-down, if the ruler is visible and the pen is within **24 px** of an edge
  (outside or inside), return a constraint that projects onto that edge
  (`geometry.project`), using a snapshot of the geometry.
* **`RulerPainter` / `RulerOverlay`** (an `IgnorePointer` screen overlay in
  `viewportOverlays`, repainting on the model only): section 2.1. Body: rounded
  rectangle (radius 10), fill `scheme.surface` at ~30% with a hairline outline; ticks
  and numbers in `scheme.onSurface` at ~75%; 1 cm = 160/2.54 px (`const double
  rulerPxPerCm`), ticks every mm (6 px), 5 mm (10 px), cm (16 px); numbers 11 px,
  counting outward from the centre; the bottom edge mirrored with its numbers rotated
  180°; the centre badge is a dotted circle (radius 16) with the angle `"0°"` (use
  `displayAngleDegrees`, no decimals when whole). Build the tick `Path` once per paint,
  not per tick. Works in light and dark.
* **`RulerToggleButton`** in `toolRowActions` (icon `Icons.straighten`, tooltip `Ruler`,
  selected while visible; it listens to the model itself).
* **`rulerIntegration`**: registers the overlay, the interceptor, the provider and the
  button; disposes the model with `controller.addDisposeCallback`. Add it to
  `defaultEditorIntegrations` (after `shapesIntegration`).
* **`DocumentView`**: before classifying a touch as navigation or tool, offer it to
  `controller.extensions.touchInterceptor` (touch kinds only, and only when palm
  rejection did not ignore it). Claimed pointers are kept in a set and receive moves,
  up and cancel from the same listener; they never reach navigation or the tool. A claimed
  pointer must not be left behind when the pen lands (palm rejection cancels it).
* **`InkToolHandler`** (the core constraint logic): at pen-down compute
  `constraint = controller.extensions.strokeConstraint?.call(e) ?? (prefs.horizontal ?
  HorizontalConstraint(e.localPosition.dy) : null)` (the prefs of the active tool) and
  pass it to `ActiveStroke`. While a constrained stroke is drawn, behave like the shape
  tool: `stroke.preview = buildShape(ShapeKind.line, from, to, …)?.applyTo(stroke.current)`
  with `from = localToPage(constraint.project(startLocal))` and `to =
  localToPage(constraint.project(currentLocal))`; at pen-up commit
  `shape.applyTo(rawStroke)` (so `raw` is the real pen path, `points` the line,
  `shape` = line). Clip the segment to the page rectangle (Liang–Barsky) instead of
  clamping x and y separately, so a ruler running over a page edge stays straight; if
  nothing is left inside the page, or the line is shorter than 1 pt, commit the plain
  hand-drawn stroke (a tap stays a dot). The hold-to-snap hook must not run for a
  constrained stroke (`HoldSnapHook.onStart`: return early when `stroke.constraint !=
  null`). The undo label for these strokes stays `Shape`.
* Tests: geometry (projection, clamping, nearest edge, hit tests, angle display and
  snapping), gesture maths, model, interceptor routing, painter smoke test, the toggle
  button, `InkToolHandler` constrained strokes with a fake constraint and with the ruler
  (a wobbly pen path along an edge gives a straight `ShapeKind.line` stroke whose `raw`
  is the wobbly path; horizontal drawing; page-edge clipping; the pen away from the
  ruler draws freely), `DocumentView` with a fake interceptor.

### Package S — restyle a selection (runs after P)
Owns: `integrations/erase_select/{lasso_handler,selection_menu}.dart` and
`test/editor/integrations/erase_select/`. Add a **Line style** button to the lasso's
floating menu (icon `Icons.line_style`, tooltip `Line style`) that opens the same panel
(`InkSettingsModel` with `commitOnRelease`, `horizontal: null`) for the selected strokes:
thickness, concentration, line style (+ wave sliders) and colour, applied to **every
selected pen and highlighter stroke** with one `ReplaceStrokesCommand` per change
(label `Change line style`). Sizes keep the stroke's relative size when several strokes
are selected only if trivial; otherwise set them all to the chosen value. Shows the
first stroke's values (`mixed` is fine to ignore). Hidden when the selection holds no
strokes.

## 7. Rules for every worker

* Work in the project folder. Use absolute
  paths. The shell is Git Bash for `flutter`: `/c/dev/flutter/bin/flutter`.
* **Never** run `git commit`, `checkout`, `stash`, `reset`, `clean`, `flutter pub add` or
  `flutter create`. Never edit `pubspec.yaml` or `CLAUDE.md`. Do not delete files you did
  not create. Do not touch files outside your package's list.
* **Keep the tree compiling at all times** (other workers share it): small edits, and run
  `cd <the project folder> && /c/dev/flutter/bin/flutter analyze
  <your files>` after each batch. An error in somebody else's file that you cannot cause:
  wait a minute and retry; do not "fix" it.
* **Tests** run in your own mirror (`flutter test` cannot run in the real project because
  of pdfrx): F `C:\dev\neatink-mirror-F`, P `C:\dev\neatink-mirror-P`, R
  `C:\dev\neatink-mirror-R`; their `lib/` and `test/` are junctions to the project, so
  new files appear at once. Command (Git Bash):
  `cd /c/dev/neatink-mirror-X && /c/dev/flutter/bin/flutter test --reporter compact --timeout 30s <files>`.
  **Always pass `--timeout`** (a stuck test hangs for 20 minutes otherwise). Tests that
  import pdfrx cannot run there. `controller.close()` renders a thumbnail that hangs
  under flutter_tester; call the handlers' `commitPending()` instead.
* Follow the code base: small focused files, `///` comments on the why, no magic numbers
  spread around (named constants), `ink/` stays pure Dart (no `dart:ui`, no widgets).
  Every new non-trivial logic gets a test. A shortcut with a known limit gets a
  `shortcut: <limit>, <when to upgrade>` comment.
* Keep all user-visible text in plain English, sentence case, as in the video.
* After a cut-off, scan your files for NUL bytes before continuing.
* **Report** (your final message, under 250 words): files created/changed, tests added and
  the exact pass/fail counts from your last run, `flutter analyze` result for your files,
  anything you deviated from, and anything you need from another package.

## 8. Acceptance

* `flutter analyze` on the whole project: 0 issues. Whole mirror suite green
  (baseline before this work: 1183 passed, 2 skipped).
* Old data: a page JSON written by v1.3.0 loads; a stroke JSON without `line` / `conc` is
  solid and opaque; the tool prefs written by v1.3.0 load.
* A solid stroke renders and exports **byte-for-byte as before** (same outline).
* Release build still has no INTERNET permission (nothing here touches the manifest).
* Tablet checklist for the owner (written by the lead at the end).
