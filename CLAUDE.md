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
  document/               # Pure Dart: notebook/page models, paper geometry, undo/redo commands
  render/                 # Flutter painting shared by screen + PDF export (stroke outlines, paper, text styles)
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

## Expanded scope (approved by the owner, 2026-10-25)

The owner asked for a "fully fledged" note app and approved these on top of the MVP:

**Editor**
- **Text boxes & images**: typed text boxes (font, size, colour, bold/italic/underline, alignment, background) that can be moved/resized; insert pictures from the device onto a page. Both are lasso-selectable and exported to PDF.
- **Shapes & straight lines**: hold the pen still at the end of a stroke to snap it to a line, arrow, rectangle, ellipse/circle or triangle (setting, on by default), plus a shape tool. Shapes are strokes with `shape` set (`raw` keeps the hand-drawn version, so "Restore original" works). Shapes are never tidied.
- **Pen styles & partial eraser**: ballpoint / fountain / pencil, a custom colour picker, and a pixel (partial) eraser that cuts strokes, besides the whole-stroke eraser.
- **Page tools & more paper**: page thumbnail grid (jump, reorder, duplicate, insert, delete, change paper), plus dotted, Cornell and music paper, and white / cream / dark paper colours.

**Library**
- **Folders (nested), tags & favourites**, colored covers, sort by edited / created / title, duplicate, move.
- **Search** over notebook titles, tags, folder names, typed text and PDF text (not handwriting).
- **Dark mode** (system / light / dark) and an optional **PIN app lock**.

**Delivery**: public GitHub repo `MalekBaghdadi/NeatInk` with a one-click APK download (GitHub Release) and a GitHub Actions workflow that builds the APK on version tags.

Backup/restore was offered and **not** chosen; it stays in "Later".

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

- [x] **M0 — Project setup.** In *this* folder (it already holds CLAUDE.md and docs/, so keep them): `flutter create --org com.neatink --project-name neatink --platforms=android .`, add lints (`flutter_lints`, strict analysis options), folder structure, Riverpod, remove `INTERNET` from the release manifest, landscape + portrait. Builds a release APK.
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
- Stickers, audio recording.
- Backup to a file, Wi-Fi transfer to a PC.
- Low-latency front-buffer rendering via Android `androidx.graphics` (only if ink latency is a problem).

---

# STATUS & HANDOFF (read this first in a new session)

_Last updated 2026-10-26 by Claude (end of session 1). Keep this section current: update it whenever something here changes._

## Owner decisions so far

- **Scope**: MVP + everything in "Expanded scope" above. Backup/restore was NOT chosen.
- **Delivery**: public repo `MalekBaghdadi/NeatInk` (keep the name and `com.neatink.neatink`), a GitHub Release with a one-click APK download (README links to `releases/latest/download/...`), and a GitHub Actions workflow that builds the APK on version tags.
  - The owner's `gh` token has only `gist, read:org, repo` scopes. Before pushing `.github/workflows/*` the owner must run `gh auth refresh -h github.com -s workflow` (it opens a browser). Ask before every push.
- **How to work**: the main session (Opus) leads: it coordinates, integrates and reviews. Worker agents run on **Sonnet**, **2–3 at a time**. Session 1 ran 7 parallel Opus agents at high effort and hit the account usage limit within ~20 minutes, twice, which cut every agent off mid-work.
- **Approved**: installing **Visual Studio Build Tools (C++ workload)** so `flutter test` can run, but only if no lighter workaround exists. A Windows admin prompt may appear for the owner.
- **Signing (proposed, not done yet)**: generate a release keystore outside the repo, add a git-ignored `android/key.properties`, and put the same key in GitHub Actions secrets so local and CI builds can update each other. Tell the owner before uploading the secrets and tell them where the keystore backup is.

## Toolchain on this PC

- **Flutter 3.47.8 / Dart 3.13.7** is a shallow git clone at `C:\dev\flutter`. It is not on PATH, so call `/c/dev/flutter/bin/flutter` (Git Bash) directly. `flutter config` sets the Android SDK to `C:\dev\android-sdk` and the JDK to Temurin 21. `JAVA_HOME` points at JDK 25, so set `JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-21.0.12.101-hotspot"` when running `sdkmanager` or Gradle directly.
- **Android SDK** (`C:\dev\android-sdk`): `cmdline-tools/latest`, `platform-tools`, `platforms;android-36`, `build-tools;36.0.0`.
- **✅ NDK 28.2.13676358 installed** (session 2, at `C:\dev\android-sdk\ndk\28.2.13676358`). How it was done, for reference: Gradle needs **NDK 28.2.13676358**. Its automatic download failed after 2 h on this network ("Android sdkmanager did not install NDK 28.2.13676358"). Install it explicitly. `cmd` splits arguments at `;`, so put the package name in a file. Create `C:\dev\ndk.txt` containing the line `ndk;28.2.13676358`, then run `sdkmanager.bat --sdk_root=C:\dev\android-sdk --package_file=C:\dev\ndk.txt` (with `JAVA_HOME` on JDK 21; run it in the background).
- **❌ `flutter test` is blocked in the real project.** pdfrx pulls in `pdfium_dart`, whose build hook compiles `src/pdfrx_pdfium_gate.c` for the host and fails with "No compiler configured on host 'windows_x64'". `--no-enable-native-assets` is not a workaround (pdfrx requires native assets). A **VS 2019 Build Tools** install exists, but it has no MSVC compiler and no Windows SDK. Fix (session 2): the owner runs `C:\dev\vs\vs_BuildTools.exe --passive --wait --norestart --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621` themselves, because it needs admin and Claude's elevated run was blocked.
- **✅ Test mirror (session 2):** `C:\dev\neatink-mirror` has a pubspec without pdfrx, and its `lib/` and `test/` are **junctions** to the real project. Run `cd /c/dev/neatink-mirror && flutter test test/<dir>`. Every test that doesn't import pdfrx runs there. At the start of session 2: 351 passing, and 6 failing, all in `paper_painter_test`. `flutter analyze` works in the real project.
- Git Bash's `tar` can't unpack `.zip` files; use `/c/Windows/System32/tar.exe -xf`. Bash heredocs containing many quotes or backticks break; write files with the Write/Edit tools or a Python script instead.
- The network is slow (about 0.3–0.7 MB/s in total; parallel connections barely help). Big downloads take tens of minutes, so run them in the background.
- `C:\dev\wait-ready.sh` and `C:\dev\neatink-ready` were a waiting mechanism for session-1 agents and can be ignored.

## Session 2 progress (2026-10-26)

- **Wave 1 is done and committed as `9d12369`:**
  - the full tidy engine in `lib/beautify/` (179 tests);
  - `EditorScreen`;
  - the Kotlin `PdfExportPlugin`, compiled with kotlinc against the real jars, but not yet through Gradle and never run on a device;
  - the `ToolConfig` fixes and the paper painter fix.
- Whole project: `flutter analyze` reports 0 issues and 609 mirror tests pass. **`flutter build apk --debug` works** (the first build took about 23 minutes: Gradle also installed platform 35 and CMake 3.22.1). The Kotlin `PdfExportPlugin` compiles in Gradle.
- **Wave 2 was started** as six editor integrations, each in `lib/features/editor/integrations/<name>/` with tests in `test/editor/integrations/<name>/`: `erase_select`, `tidy`, `text_images`, `shapes` (which adds `tools/shape_recognizer.dart`, because nothing classified shapes before), `pages` and `pdf`. Each exposes one `<name>Integration`. **The lead registers them in `editorIntegrationsProvider`** (`editor_integrations.dart`); the workers don't.
- Open notes from wave 1:
  - Tidy numbers are tuned only on synthetic letters; check them with the debug overlay on the tablet.
  - PDF export drops the source PDF's bookmarks and form fields, because it rebuilds the file by importing pages.
  - Text boxes in exported PDFs use Helvetica, Times or Courier.

## Session 3 (2026-10-27): wave 2 finished

- Three wave-2 files had been NUL-corrupted by a cut-off (shapes handler + integration, tidy test); they were deleted and redone. **After any cut-off, scan for NUL bytes** (Grep `backslash-x00` with multiline over lib/ and test/).
- All six integrations exist, are tested in the mirror, and are installed by the real app: `lib/features/editor/default_integrations.dart` lists them and `main.dart` overrides `editorIntegrationsProvider` with it. The provider's own default stays empty on purpose: `pdfIntegration` imports pdfrx, which would stop every editor test from loading in the mirror.
- Full mirror suite: 739 tests pass (`flutter test --reporter expanded --timeout 30s`, ~20 s). `flutter analyze`: 0 issues. Always pass `--timeout`: a stuck test otherwise hangs the run for 20+ min.
- Test gotcha: `controller.close()` renders a thumbnail (`picture.toImage`), which hangs under `flutter_tester`; tests call the handlers' `commitPending()` / `beforeSaveHooks` instead.
- Fixed: image corner-resize could not shrink horizontally (`resizedImageFrame`).
- Untested by construction (import pdfrx): `integrations/pdf/pdf_background.dart`, `pdf_integration.dart`. Never run on a device: everything in wave 2.
- Tablet checks flagged by workers: a stylus tap on the page quick-nav pill might also draw ink; PDF page thumbnails in the navigator are white under the ink (no PDF render).

## Code state (end of session 1; superseded by the section above where they differ)

Commits: `c72d25b` project brief; `6a7126b` M0 scaffold and shared contracts; then a **WIP checkpoint commit** of everything the agents had written (see `git log`). Nothing has been pushed; no GitHub repo exists yet.

| Area | State |
|---|---|
| **Contracts**: `lib/ink/*`, `lib/document/*`, `lib/storage/notebook_repository.dart`, `lib/features/settings/app_settings.dart`, `lib/app/providers.dart`, `lib/render/stroke_outline.dart`, `lib/pdf/pdf_export_request.dart` | Done, analyzer clean. Every other part builds on these, so only make additive changes. |
| **Storage** `lib/storage/` | **Done.** `FileNotebookRepository`, atomic writes with `.bak`/`.corrupt` copies, search, `AutosaveController` and `NotebookSaver`. 132 tests in `test/storage/` (they passed in the mirror; still to be rerun in the real project). |
| **Tidy engine** `lib/beautify/` | **Barely started.** Only `features.dart`, `resample.dart`, `stats.dart` and `tidy_config.dart` exist. Missing: `word_segmenter`, `line_context`, `transform`, `tidy_pipeline` and `smoothing`, plus every spec test (`test/beautify/` doesn't exist). |
| **Tool logic** `lib/features/editor/tools/` | Mostly written: spatial index, eraser, pixel eraser, lasso, selection transform, shapes, hold detector, plus `test/editor_tools/`. Analyzer errors: `ToolConfig` lacks the `arrowBuild*` getters. Unverified, because tests can't run yet. |
| **PDF** `lib/pdf/` | Dart side written: import, page cache and background, export builder, exporter channel, coordinates. Kotlin: only `PdfCoords.kt` exists. **`PdfExportPlugin.kt` is not written** and isn't registered in `MainActivity`. The PdfBox dependency and `proguard-rules.pro` are in place. `test/pdf/` is missing. Check that `lib/render/text_style.dart` exists. |
| **App shell, settings, lock, debug** | Written: real `main.dart`, theme, routes, settings screen and controller, PIN lock, pointer debug screen. Tests in `test/app`, `test/settings` and `test/lock`. `routes.dart` fails only because `editor_screen.dart` is missing. |
| **Library** `lib/features/library/` | Written: 32 files covering the grid, folders, tags, favourites, the new-notebook sheet, PDF import and search. Also `lib/render/paper_painter.dart`, `test/library/` and `test/fakes/in_memory_repository.dart`. Tests not yet run. |
| **Editor core** `lib/features/editor/` | Mostly written: 32 files covering the controller, viewport, input router, live ink, page painting, toolbar, tool prefs and thumbnails. **`editor_screen.dart` is missing** and `test/editor/` doesn't exist. |
| **Editor features (wave 2)** | **Not started.** They need wiring into the editor: eraser, pixel eraser, lasso and selection; text boxes and images; shapes (hold-to-snap plus a shape tool); the page navigator grid (reorder, duplicate, insert, delete, change paper); tidy (segmenter glue, 180 ms animation, `ApplyTidy` undo, Restore original, debug overlay); PDF backgrounds in the editor; the export UI (progress, save, share); and search results that jump to the right page. |

`flutter analyze` (2026-10-26) reports 7 issues: 2 come from the missing `editor_screen.dart`, 4 from the missing `ToolConfig.arrowBuild*`, and 1 is an info in `test/library/paper_painter_test.dart`.

### Agreed cross-module names (agents rely on these)

- `FileNotebookRepository(Directory root, {Uuid? uuid, DateTime Function()? clock})`. Use one instance for the whole app.
- `AutosaveController({required Future<void> Function(DocChange) save, Duration delay})` with `markDirty`, `flushNow` (never throws), `hasPendingChanges`, `errors` and `dispose`.
- `NotebookSaver(repo).save(doc, dirty)`. Wiring: `doc.addListener(autosave.markDirty)`, then `flushNow()` on pause and before closing.
- `settingsProvider`: a `NotifierProvider<SettingsController, AppSettings>` with `update(fn)`, in `lib/features/settings/settings_controller.dart`. `clockProvider` lives in `lib/app/providers.dart`.
- `AppRoutes.openEditor(context, notebookId, {pageIndex})`, `.openSettings`, `.openSearch` and `.openPointerDebug`, in `lib/app/routes.dart`.
- `LibraryScreen()`, `SearchScreen()`, and `EditorScreen({required notebookId, int? initialPageIndex})` in `lib/features/editor/editor_screen.dart`.
- `importPdfNotebook(repo, path, {title, folderId})` throws `PdfImportException(message)`.
- `PaperPainter(Paper, pageWidthPt, pageHeightPt)`, `textStyleFor(TextItem)` in `lib/render/text_style.dart`, and `InMemoryNotebookRepository` in `test/fakes/`.
- `MethodChannel('neatink/pdf_export')`, which reports `progress {done,total}` back to Dart.

### Rules that kept parallel agents from colliding

- Each agent owns specific folders and edits only those. Only the lead edits `pubspec.yaml` and `analysis_options.yaml`.
- Agents never run `git commit`, `checkout`, `stash` or `reset`, `flutter create`, or `pub add`. The lead commits.
- Each agent checks only its own files with `flutter analyze <paths>` and runs only its own tests.
- Partial work from an agent that was cut off is continued, not rewritten: read what exists first.

## Next steps (in order)

1. Install the NDK (see Toolchain) and get `flutter build apk --debug` building.
2. Make `flutter test` work in the real project (VS Build Tools C++ is approved), then run every existing test.
3. Finish the wave-1 areas with Sonnet agents, 2–3 at a time, each continuing the partial work in its own folders:
   - the tidy engine, built in full and passing every test in the spec's table;
   - `EditorScreen` and the editor tests;
   - the tool-logic fixes and tests;
   - the Kotlin `PdfExportPlugin`, its registration, and `test/pdf`;
   - shell and library tests passing.
4. Integration gate: whole-project `flutter analyze` with 0 issues, all tests passing, a debug APK that builds, and the app launching (an emulator is optional; the network is slow).
5. Wave 2: the editor features listed in the table.
6. Review pass:
   - no `INTERNET` permission in the **merged release** manifest (check the built APK with `apkanalyzer manifest permissions`) and no storage permissions;
   - every dependency's license is allowed;
   - never-lose-ink paths (raw kept, atomic saves, flush on pause);
   - performance (lazy pages, cached pictures).
7. Release:
   - app icon and version 1.0.0;
   - signing (see above);
   - `flutter build apk --release --split-per-abi` plus a universal APK;
   - a README with a big "Download APK" link;
   - create the public repo and push (ask first);
   - a GitHub Release with the APK assets (stable asset name for `releases/latest/download/NeatInk.apk`);
   - `.github/workflows/release.yml` (needs the `workflow` scope).
8. Give the owner a "test this on the tablet" checklist covering the M-Pencil (pressure, palm rejection, eraser end), tidy, PDF import and export, autosave after swiping the app away, and the app lock.
