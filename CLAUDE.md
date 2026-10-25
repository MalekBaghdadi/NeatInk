# NeatInk — handwriting notes app for Android tablets

> "NeatInk" and the package id `com.neatink.neatink` are placeholders. Ask the owner before renaming them.

## What we're building

A note-taking app for Android tablets, built with Flutter. It ships as a sideloaded APK. The core features:

1. **Stylus writing** that feels smooth, with pressure and palm rejection.
2. **Notebooks made of pages** (blank, lined, grid), like a paper notebook.
3. **PDF import → write on it → export a new PDF** with the writing baked in.
4. **"Tidy as you write"** (the headline feature). About half a second after you finish a word, the app gently straightens it, puts it on the line, makes its size consistent and evens out spacing. It keeps the user's own handwriting; it does **not** turn it into a font. The full algorithm is in @docs/beautify-spec.md.

The owner's device is a **Huawei MatePad** with a **Huawei M-Pencil**. Treat this as the reference device.

## Hard rules (do not break these)

- **100% offline and local.** No servers, no accounts, no cloud sync, no analytics, no crash reporting, no ads.
  - The release `AndroidManifest.xml` must **not** request the `INTERNET` permission. Flutter's debug and profile manifests add it for hot reload, and that's fine.
  - No package that phones home. Check new dependencies for this.
- **No Google Play Services / Firebase / ML Kit.** Huawei tablets don't reliably have Google services. Everything (including the handwriting tidy-up) must be plain Dart/Kotlin math that runs on-device.
- **No paid or restrictively licensed dependencies.** Allowed licenses: MIT, BSD, Apache-2.0, zlib. Ask before adding anything else. Do **not** use Syncfusion, PSPDFKit/Nutrient, iText (AGPL) or similar.
- **Never lose the user's ink.** Keep the original stroke points forever, even after tidying, so undo and "restore original" always work. Saves must be atomic (write a temp file, then rename).
- **English handwriting only** for the tidy feature, for now (Latin script, left to right). Don't build Arabic/RTL logic yet, but don't hard-code assumptions that would block it later.

## Tech stack

| Concern | Choice | Notes |
|---|---|---|
| Framework | Flutter, latest stable; Dart 3 | Android only for now. Create with `--platforms=android`. |
| State | `flutter_riverpod` | Keep providers small and testable. |
| Stroke rendering | `perfect_freehand` (MIT) | Pressure-sensitive outlines. Check the current API on pub.dev; v2 uses `PointVector` and `StrokeOptions`. |
| PDF viewing | `pdfrx` (PDFium-based, permissive) | Render page images for the background layer. |
| PDF export | **PdfBox-Android** (`com.tom-roush:pdfbox-android`, Apache-2.0) via a Kotlin `MethodChannel` | Appends vector ink to the *original* PDF pages, so the original text stays selectable. See "PDF export" below. |
| File picking | `file_picker` | Import PDFs. Export via Android's Storage Access Framework (`ACTION_CREATE_DOCUMENT`) or `file_picker`'s save dialog. No broad storage permissions. |
| Storage | App documents dir (`path_provider`) + JSON files | Simple, easy to debug. See "Data & storage". |
| IDs | `uuid` | |

Prefer writing small focused code over pulling in packages. Each new dependency needs a one-line reason in the commit message.

## Architecture

```
lib/
  main.dart
  app/                    # MaterialApp, theme, routes
  features/
    library/              # Home screen: notebook grid, create/rename/delete, import PDF
    editor/               # Notebook editor screen
      canvas/             # Ink input, page rendering, active stroke painter
      toolbar/            # Pen / highlighter / eraser / lasso / colors / widths / tidy toggle
      tools/              # Tool logic (eraser hit-testing, lasso selection & transform)
    settings/             # Tidy strength, slant mode, finger-drawing toggle, debug overlay
  ink/                    # Pure Dart, no Flutter widgets: Stroke, InkPoint, geometry utils
  beautify/               # Pure Dart: the tidy pipeline (see docs/beautify-spec.md)
  pdf/                    # pdfrx rendering helpers + PdfExport channel wrapper
  storage/                # Repositories, JSON codecs, atomic file writes, autosave
android/app/src/main/kotlin/.../PdfExportPlugin.kt   # PdfBox-Android export
test/                     # Unit tests (beautify/ and ink/ must be heavily tested)
```

Key rules:
- `ink/` and `beautify/` must be **pure Dart**: no `dart:ui` canvas, no widgets. Use your own `Vec2`/`Rect` types or `dart:math`. This keeps them unit-testable and lets them run in an isolate if needed.
- The UI never mutates strokes directly. It sends commands (`AddStroke`, `EraseStrokes`, `ApplyTidy`, `TransformSelection` …) through an **undo/redo command stack**, one per notebook.

## Coordinate system

- All ink is stored in **page coordinates measured in PDF points** (1 pt = 1/72 inch), with the origin at the top-left of the page and y pointing down.
- Blank notebook pages default to **A4 portrait: 595 × 842 pt**.
- PDF-backed pages use each PDF page's own size (respect its rotation and CropBox).
- The screen view is a transform (zoom + pan) applied on top. Convert pointer positions with the inverse transform before storing.
- This makes PDF export a direct mapping. The only conversion is flipping y (PDF's origin is bottom-left) and handling page rotation.

## Data & storage

```
<appDocs>/notebooks/<notebookId>/
  notebook.json        # metadata (below)
  source.pdf           # only for PDF-backed notebooks (a copy of the imported file)
  pages/<pageId>.json  # strokes for one page
  thumb.png            # cover thumbnail for the library grid
```

`notebook.json`
```json
{
  "version": 1,
  "id": "uuid", "title": "Physics", "createdAt": "...", "updatedAt": "...",
  "kind": "blank | pdf",
  "defaultPaper": { "type": "blank | lined | grid", "spacingPt": 26 },
  "pages": [ { "id": "uuid", "width": 595, "height": 842, "paper": {...}, "pdfPageIndex": null } ]
}
```

Stroke (in `pages/<pageId>.json`)
```json
{
  "id": "uuid",
  "tool": "pen | highlighter",
  "color": "#FF1E1E1E",
  "size": 2.2,
  "raw":    [[x, y, pressure, tMillis], ...],
  "points": [[x, y, pressure, tMillis], ...],
  "wordId": "uuid | null",
  "tidy": { "applied": true, "version": 1 }
}
```
- `raw` = exactly what the pen produced. It's never modified, except by lasso move/resize, which transforms `raw` and `points` together.
- `points` = what's displayed (equal to `raw` until tidied).
- Include a `version` field and write a migration stub now.
- **Autosave**: debounce 1.5 s after the last change, plus save on app pause (`AppLifecycleState.paused`). Encode JSON off the UI thread (`compute`/`Isolate.run`) if a page has more than ~2,000 strokes.

## Input handling

- Use a `Listener` (raw pointer events), not gesture detectors, for ink.
- **Pen draws, fingers navigate.** If `event.kind == PointerDeviceKind.stylus`, it's ink. Touch is pan/zoom (two fingers) and scroll (one finger). `PointerDeviceKind.invertedStylus` (eraser end) erases if the pen supports it.
- Palm rejection is simply "touch never draws while stylus mode is on". Add a settings toggle, **"Draw with finger"**, that defaults to off, in case the M-Pencil isn't reported as a stylus.
- **Verify on the MatePad early (Milestone 1).** Log `kind`, `pressure`, `pressureMin`, `pressureMax` and `tilt` from the M-Pencil to make sure they arrive. If pressure is always 1.0, fall back to `perfect_freehand`'s simulated pressure.
- Record a timestamp for every point. The tidy feature needs timing.

## Rendering & performance

Target: ink must feel instant at 60–120 Hz.
- Three layers per page, each in its own `RepaintBoundary`:
  1. **Background**: paper lines/grid, or the PDF page image (render at device-pixel resolution for the current zoom; cache it; re-render lazily after zoom settles).
  2. **Committed ink**: all finished strokes, cached as a `ui.Picture` that's rebuilt only when strokes change.
  3. **Live layer**: only the stroke currently being drawn, plus any tidy animation in progress.
- Only build and paint pages that are visible (vertical scrolling list of pages with lazy building).
- Cache each stroke's `perfect_freehand` outline `Path`; recompute only when its points change.
- Profile on the real device in `--profile` mode. A 50-page notebook should scroll smoothly.

## Features — MVP scope

**Library (home screen)**
- Grid of notebooks with thumbnail, title and last-edited date.
- New notebook: title + paper type (blank / lined / grid).
- Import PDF: creates a PDF-backed notebook (copies the file in).
- Rename, delete (with confirmation), sort by last edited.

**Editor**
- Vertical scroll through pages; pinch to zoom (0.5×–4×); add a page at the end; delete a page.
- Tools: **pen**, **highlighter** (semi-transparent, drawn under pen ink, never tidied), **stroke eraser** (erases whole strokes it touches), **lasso** (select → move, resize, delete, change color).
- Pen: 8 preset colors + 3 widths. Remember the last-used values.
- **Undo / redo** buttons (at least 100 steps per session).
- **Tidy toggle** in the toolbar (on by default) + settings for strength (Light / Medium / Strong) and slant (Keep my slant / Upright).
- Lasso menu item **"Restore original"**: puts selected tidied strokes back to `raw`.
- Debug overlay (hidden in settings → Developer): draws detected baselines, x-height band and slant lines. Essential for tuning the tidy feature.

**PDF**
- Import → each PDF page becomes a notebook page with the PDF as its background.
- Write on it with all tools; tidy works too, using the "blank paper" mode from the spec.
- **Export PDF** (menu): makes a new PDF file and lets the user choose where to save/share it. Also allow exporting blank notebooks as PDF.

## PDF export (details)

Implement in Kotlin with PdfBox-Android, called from Dart through a `MethodChannel("neatink/pdf_export")`.
- Call `PDFBoxResourceLoader.init(context)` once before using PdfBox.
- **PDF-backed notebook**: load `source.pdf`. For each page, open `PDPageContentStream(doc, page, AppendMode.APPEND, true, true)` and draw each stroke as a **filled path** using the same `perfect_freehand` outline the app displays. Send the outline polygons from Dart, so the export looks identical to the screen.
- **Blank notebook**: create pages of the right size, draw the paper lines lightly (optional setting), then draw the ink.
- Highlighter: set transparency with `PDExtendedGraphicsState` (non-stroking alpha ≈ 0.35).
- Coordinate mapping: `pdfY = pageHeight − y`; account for `/Rotate` and the CropBox origin. Add a test PDF with a rotated page.
- Run export in the background and show a progress indicator. Never block the UI thread.
- Fallback (only if PdfBox is unusable): render each page to an image with ink on top and build the PDF with the `pdf` package (Apache-2.0). Text won't be selectable. Ask before switching.

## Milestones (do in order; each ends with a working APK)

Mark them `[x]` here as you finish them. After each milestone, build an APK and list what the owner should test on the tablet.

- [ ] **M0 — Project setup.** In *this* folder (it already holds CLAUDE.md and docs/, so keep them): `flutter create --org com.neatink --project-name neatink --platforms=android .`, add lints (`flutter_lints`, strict analysis options), folder structure, Riverpod, remove `INTERNET` from the release manifest, landscape + portrait. Builds a release APK.
- [ ] **M1 — Ink canvas.** One blank page; stylus drawing with `perfect_freehand`; pressure; pen/finger separation; pan/zoom; a debug screen that shows raw pointer info from the M-Pencil.
- [ ] **M2 — Notebooks & storage.** Library screen, create/rename/delete, multiple pages, paper types, autosave/load, atomic writes, thumbnails.
- [ ] **M3 — Tools.** Highlighter, stroke eraser, lasso (move/resize/delete/recolor), colors/widths, undo/redo command stack.
- [ ] **M4 — Tidy, part 1 (geometry).** Pure-Dart `beautify/` package: resampling, word segmentation, baseline/skew, x-height, slant estimation, with unit tests on synthetic words. Debug overlay showing what was detected. **No changes to the ink yet.**
- [ ] **M5 — Tidy, part 2 (apply).** Deskew, slant correction, size normalization, baseline snapping, per-stroke alignment, spacing, animation, undo integration, toggle and strength settings, "Restore original".
- [ ] **M6 — PDF import & viewing.** pdfrx backgrounds, lazy page rendering, ink on PDFs, tidy in blank-paper mode.
- [ ] **M7 — PDF export.** Kotlin PdfBox channel, vector ink, highlighter alpha, rotation handling, save/share.
- [ ] **M8 — Polish.** Performance pass on the device, app icon, empty states, error messages, settings screen, final release APK.

## Testing & definition of done

- `flutter analyze` → zero issues. `flutter test` → all green.
- `beautify/` needs tests for every step in the spec. Build synthetic words from simple letter shapes, apply a known rotation/shear/scale, run the pipeline, and assert it recovers them within tolerance (listed in the spec).
- Golden or snapshot tests are optional. Don't let them slow you down.
- A milestone is done only when: it builds a release APK, the analyzer is clean, tests pass, and you've written a short "test this on the tablet" checklist for the owner. You can't run the real device yourself, so be explicit about what needs human checking.

## Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter run                         # with the tablet connected over USB (adb devices to check)
flutter run --profile               # for performance checks
flutter build apk --release --split-per-abi
# Install on the MatePad: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Signing: for now, the default Flutter template signs release builds with the debug key, which is fine for personal sideloading. Leave a `key.properties` setup ready (git-ignored) for real signing later. Never commit keystores.

## Working style

- Small commits with clear messages. Commit after each meaningful step.
- Explain non-obvious math in short code comments (especially in `beautify/`). Put all tidy tuning numbers in **one** config file (`beautify/tidy_config.dart`), never as magic numbers spread around.
- When something in this file or the spec is unclear or seems wrong, ask the owner instead of guessing. The owner is a CS graduate who knows Flutter, so technical questions are fine.
- Don't add features beyond the MVP list without asking. Ideas go in "Later" below.

## Later (not now)

- Real handwriting-style synthesis (rewriting letters in a nicer style) — needs an on-device model.
- Arabic / French tidy support.
- Searching handwriting (on-device recognition).
- Templates, stickers, images, text boxes, audio recording.
- Folders/tags, backup to a file, Wi-Fi transfer to a PC.
- Low-latency front-buffer rendering via Android `androidx.graphics` (only if ink latency is a problem).
