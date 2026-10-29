# NeatInk — handwriting notes app for Android tablets

> "NeatInk" and the package id `com.neatink.neatink` are placeholders. Ask the owner before renaming them.

## What we're building

A note-taking app for Android tablets, built with Flutter. It ships as a sideloaded APK. The core features:

1. **Stylus writing** that feels smooth, with pressure and palm rejection.
2. **Notebooks made of pages** (blank, lined, grid), like a paper notebook.
3. **PDF import → write on it → export a new PDF** with the writing baked in.
4. **Convert handwriting to typed text** (the headline feature, planned for v1.1): a button recognizes the handwriting on-device and re-types it in a font the user chooses, laid out on the lines, in one undo step. (The earlier "Tidy as you write" auto-tidy was removed in session 4; its spec is kept for reference in @docs/beautify-spec.md.)

The owner's device is a **Huawei MatePad** with a **Huawei M-Pencil**. Treat this as the reference device.

## Hard rules (do not break these)

- **100% offline and local.** No servers, no accounts, no cloud sync, no analytics, no crash reporting, no ads.
  - The release `AndroidManifest.xml` must **not** request the `INTERNET` permission. Flutter's debug and profile manifests add it for hot reload, and that's fine.
  - No package that phones home. Check new dependencies for this.
- **No Google Play Services / Firebase / ML Kit.** Huawei tablets don't reliably have Google services. Everything (including handwriting recognition) must be plain Dart/Kotlin math that runs on-device.
- **No paid or restrictively licensed dependencies.** Allowed licenses: MIT, BSD, Apache-2.0, zlib. Ask before adding anything else. Do **not** use Syncfusion, PSPDFKit/Nutrient, iText (AGPL) or similar.
- **Never lose the user's ink.** Keep the original stroke points forever, even after snapping or converting, so undo and "restore original" always work. Saves must be atomic (write a temp file, then rename).
- **English handwriting only** for recognition, for now (Latin script, left to right). Don't build Arabic/RTL logic yet, but don't hard-code assumptions that would block it later.

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
      toolbar/            # Pen / highlighter / eraser / lasso / colors / widths
      tools/              # Tool logic (eraser hit-testing, lasso selection & transform)
    settings/             # Theme, finger-drawing toggle, shape snap, paper defaults, PIN lock, backup & restore
    tips/                 # Tips screen (opens once by itself, then from Settings)
  ink/                    # Pure Dart, no Flutter widgets: Stroke, InkPoint, geometry utils
  document/               # Pure Dart: notebook/page models, paper geometry, undo/redo commands
  render/                 # Flutter painting shared by screen + PDF export (stroke outlines, paper, text styles)
  beautify/               # Pure Dart: handwriting geometry helpers (baseline, x-height, deskew, stats, resampling); the tidy pipeline was removed
  pdf/                    # pdfrx rendering helpers + PdfExport channel wrapper
  storage/                # Repositories, JSON codecs, atomic file writes, autosave; backup/ = ZIP backups
android/app/src/main/kotlin/.../PdfExportPlugin.kt   # PdfBox-Android export
android/app/src/main/kotlin/.../FileSavePlugin.kt    # "Save to" dialog that streams a file (backups)
test/                     # Unit tests (beautify/ and ink/ must be heavily tested)
```

Key rules:
- `ink/` and `beautify/` must be **pure Dart**: no `dart:ui` canvas, no widgets. Use your own `Vec2`/`Rect` types or `dart:math`. This keeps them unit-testable and lets them run in an isolate if needed.
- The UI never mutates strokes directly. It sends commands (`AddStroke`, `EraseStrokes`, `TransformSelection` …) through an **undo/redo command stack**, one per notebook.

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
  "pages": [ { "id": "uuid", "width": 595, "height": 842, "paper": {...}, "pdfPageIndex": null,
               "marginLeft": 0, "marginRight": 0 } ],
  "cover": { "kind": "preview | pattern | art | photo", "pattern": "...", "art": "...", "photo": "<asset file>" }
}
```
- `marginLeft` / `marginRight` (optional, v1.4.0): writing space beside a PDF page; `width` includes them and the PDF page sits between (`PageMeta.contentLeft/contentWidth`). `cover` (optional) is the library cover design; a `photo` cover is a file in `assets/` that the unused-asset cleanup keeps.

Stroke (in `pages/<pageId>.json`)
```json
{
  "id": "uuid",
  "tool": "pen | highlighter",
  "color": "#FF1E1E1E",
  "size": 2.2,
  "raw":    [[x, y, pressure, tMillis], ...],
  "points": [[x, y, pressure, tMillis], ...],
  "shape": "line | arrow | rectangle | ellipse | triangle (optional)"
}
```
- `raw` = exactly what the pen produced. It's never modified, except by lasso move/resize, which transforms `raw` and `points` together.
- `points` = what's displayed (equal to `raw` unless snapped to a shape or tidied as a highlight). `rawSize` (optional) is the drawn width of a tidied highlight, for "Restore original". Old files may contain `wordId` / `tidy` keys; they are ignored.
- Text boxes (`texts` in page JSON) may carry `"corrections": [{"at": 12, "from": "nuerons", "to": "neurons"}]` (v1.5.0): words autocorrect changed, for the underline and tap-to-undo. `TextItem.copyWith(text:)` moves them with edits (`remapCorrections`); stale ones are ignored and not written.
- **search.json** pages may carry `"ink"` (what the handwriting reader read on the page, v1.7.0) and `"inkKey"` (count + FNV-1a hash of the pen stroke ids it was read from; also set when nothing could be read). Other on-device files (v1.7.0): `<docs>/recognition/kept_corrections.jsonl` (one format-2 sample line per line converted from the review sheet, no pictures, max 1000 lines / 30 MB) and `<docs>/diagnostics/log.jsonl` (`{"t","m"}` per problem, ~300 kept). Neither is in backups.
- **Trash** (v1.8.0): deleting a notebook moves its folder to `<root>/trash/<id>/` (same files plus `trashed.json` `{"deletedAt"}`); restore moves it back (new id if the id came back meanwhile, top level if its folder is gone); the library empties entries older than 30 days when it opens (`LibraryController.trashKeep`). Not in backups. `deleteNotebook` still deletes for good.
- **Backups** (v1.6.0, `lib/storage/backup/`): one ZIP with `neatink-backup.json` (manifest: format `neatink-backup`, version 1, app, createdAt, notebooks), `app.json` (settings without the PIN/lock, tool prefs, typed-text look, My words), `library.json` and `notebooks/<id>/**` exactly as on disk (temp files left out). A restore only adds: missing notebooks keep their id, unchanged ones (same `updatedAt` and page count) are skipped, changed ones become copies "<title> (from backup)" with a new id (opt-out), each staged in `<root>/.restore-*` and moved in with one rename; folders the restored notebooks need are merged into `library.json`. A newer manifest version is refused.
- Include a `version` field and write a migration stub now.
- **Autosave**: debounce 1.5 s after the last change, plus save on app pause (`AppLifecycleState.paused`). Encode JSON off the UI thread (`compute`/`Isolate.run`) if a page has more than ~2,000 strokes.

## Input handling

- Use a `Listener` (raw pointer events), not gesture detectors, for ink.
- **Pen draws, fingers navigate.** If `event.kind == PointerDeviceKind.stylus`, it's ink. Touch is pan/zoom (two fingers) and scroll (one finger). `PointerDeviceKind.invertedStylus` (eraser end) erases if the pen supports it.
- Palm rejection is simply "touch never draws while stylus mode is on". Add a settings toggle, **"Draw with finger"**, that defaults to off, in case the M-Pencil isn't reported as a stylus.
- **Verify on the MatePad early (Milestone 1).** Log `kind`, `pressure`, `pressureMin`, `pressureMax` and `tilt` from the M-Pencil to make sure they arrive. If pressure is always 1.0, fall back to `perfect_freehand`'s simulated pressure.
- Record a timestamp for every point (word/line grouping for recognition may use timing).

## Rendering & performance

Target: ink must feel instant at 60–120 Hz.
- Three layers per page, each in its own `RepaintBoundary`:
  1. **Background**: paper lines/grid, or the PDF page image (render at device-pixel resolution for the current zoom; cache it; re-render lazily after zoom settles).
  2. **Committed ink**: all finished strokes, cached as a `ui.Picture` that's rebuilt only when strokes change.
  3. **Live layer**: only the stroke currently being drawn, plus any transient overlays.
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
- Tools: **pen**, **highlighter** (semi-transparent, drawn under pen ink), **stroke eraser** (erases whole strokes it touches), **lasso** (select → move, resize, delete, change color).
- Pen: 8 preset colors + 3 widths. Remember the last-used values.
- **Undo / redo** buttons (at least 100 steps per session).
- Lasso menu item **"Restore original"**: puts selected snapped-shape strokes back to `raw`.

**PDF**
- Import → each PDF page becomes a notebook page with the PDF as its background.
- Write on it with all tools.
- **Export PDF** (menu): makes a new PDF file and lets the user choose where to save/share it. Also allow exporting blank notebooks as PDF.

## Expanded scope (approved by the owner, 2026-10-25)

The owner asked for a "fully fledged" note app and approved these on top of the MVP:

**Editor**
- **Text boxes & images**: typed text boxes (font, size, colour, bold/italic/underline, alignment, background) that can be moved/resized; insert pictures from the device onto a page. Both are lasso-selectable and exported to PDF.
- **Shapes & straight lines**: hold the pen still at the end of a stroke to snap it to a line, arrow, rectangle, ellipse/circle or triangle (setting, on by default), plus a shape tool. Shapes are strokes with `shape` set (`raw` keeps the hand-drawn version, so "Restore original" works). 
- **Pen styles & partial eraser**: ballpoint / fountain / pencil, a custom colour picker, and a pixel (partial) eraser that cuts strokes, besides the whole-stroke eraser.
- **Page tools & more paper**: page thumbnail grid (jump, reorder, duplicate, insert, delete, change paper), plus dotted, Cornell and music paper, and white / cream / dark paper colours.

**Library**
- **Folders (nested), tags & favourites**, colored covers, sort by edited / created / title, duplicate, move.
- **Search** over notebook titles, tags, folder names, typed text and PDF text (not handwriting).
- **Dark mode** (system / light / dark) and an optional **PIN app lock**.

**Delivery**: public GitHub repo `MalekBaghdadi/NeatInk` with a one-click APK download (GitHub Release) and a GitHub Actions workflow that builds the APK on version tags.

Backup/restore was offered and not chosen at first; the owner approved it on 2026-10-28 (session 8, see "Session 8").

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
- [x] **M1 — Ink canvas.** One blank page; stylus drawing with `perfect_freehand`; pressure; pen/finger separation; pan/zoom; a debug screen that shows raw pointer info from the M-Pencil.
- [x] **M2 — Notebooks & storage.** Library screen, create/rename/delete, multiple pages, paper types, autosave/load, atomic writes, thumbnails.
- [x] **M3 — Tools.** Highlighter, stroke eraser, lasso (move/resize/delete/recolor), colors/widths, undo/redo command stack.
- [x] ~~**M4 — Tidy, part 1 (geometry).**~~ Built, then the tidy pipeline was removed in session 4 (replaced by Convert to text); the geometry helpers stay for recognition. Pure-Dart `beautify/` package: resampling, word segmentation, baseline/skew, x-height, slant estimation, with unit tests on synthetic words. Debug overlay showing what was detected. **No changes to the ink yet.**
- [x] ~~**M5 — Tidy, part 2 (apply).**~~ Built, then removed in session 4. Deskew, slant correction, size normalization, baseline snapping, per-stroke alignment, spacing, animation, undo integration, toggle and strength settings, "Restore original".
- [x] **M6 — PDF import & viewing.** pdfrx backgrounds, lazy page rendering, ink on PDFs, tidy in blank-paper mode.
- [x] **M7 — PDF export.** Kotlin PdfBox channel, vector ink, highlighter alpha, rotation handling, save/share.
- [x] **M8 — Polish.** Performance pass on the device, app icon, empty states, error messages, settings screen, final release APK. (Everything except the on-device performance pass: nothing has been run on the MatePad yet, see "Start here".)

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
- Explain non-obvious math in short code comments (especially in `beautify/`). Put tuning numbers in one config file (e.g. `beautify/tidy_config.dart`), never as magic numbers spread around.
- When something in this file or the spec is unclear or seems wrong, ask the owner instead of guessing. The owner is a CS graduate who knows Flutter, so technical questions are fine.
- Don't add features beyond the MVP list without asking. Ideas go in "Later" below.

## Later (not now)

- Real handwriting-style synthesis (rewriting letters in a nicer style) — needs an on-device model.
- Arabic / French recognition support.
- Stickers, audio recording (offered again in session 9; the owner has not chosen its scope yet).
- Wi-Fi transfer to a PC (backup to a file was built in session 8).
- Low-latency front-buffer rendering via Android `androidx.graphics` (only if ink latency is a problem).

---

# STATUS & HANDOFF (read this first in a new session)

**Session 4 (2026-10-27): auto-tidy was removed.** After alpha testing, the owner replaced it with a planned "convert handwriting to typed text" feature (v1.1, plan in `~/.claude/plans/shimmering-kindling-thacker.md`). Removed: `integrations/tidy/`, the toolbar `TidyToggle`, the settings `tidyEnabled`/`tidyStrength`/`slantMode`/`debugOverlay`, `Stroke.wordId` and `TidyInfo`, and the tidy pipeline files in `lib/beautify/` (`tidy_pipeline`, `transform`, `smoothing`, `word_segmenter`, `line_context`). Kept: `lib/beautify/{features,stats,resample,tidy_config}.dart` (reused by recognition) and their tests. Old saved prefs and page JSON that contain the removed keys still load (unknown keys are ignored). Sections below that describe tidy are historical.

_Last updated 2026-10-29 by Claude (end of session 10). Keep this section current: update it whenever something here changes._

## Start here (state at the end of session 10)

- **Released: v1.8.0** (pubspec `1.8.0+10`, `AppInfo`), published 2026-10-29 13:10 UTC from `main` at `de94b77` (release.yml run 10, started by hand, see "How to release"; arm64 43.2 MB, versionCode 2010, release-signed, no INTERNET, SHA-256 checked after download). New in it: the fixes for Mariam's 1.6 answers and the owner's session-10 list (backup/restore working, late full stop, raw pressure ranges + copyable Pointer report, lasso selecting words and restyling typed text, eraser on typed text, short/tall scribbles, line joining after typed text, names known, Check spelling underlines, Trash); details in "Session 10". Previous: v1.7.0 (`1.7.0+9`, 2026-10-29 08:24 UTC: copy/cut/paste, search handwriting, keep my corrections, share diagnostics, PDF bookmarks and forms), v1.6.0 (`1.6.0+8`, 2026-10-28 21:23 UTC: backup & restore, tips, PDF page thumbnails, scribble to delete, the fixes for Mariam's 1.5 answers), v1.5.0 (`1.5.0+7`, 2026-10-28 17:03 UTC). Download: `https://github.com/MalekBaghdadi/NeatInk/releases/latest/download/MariamsNotes.apk` (arm64, 43 MB; `MariamsNotes-armeabi-v7a.apk` and `SHA256SUMS.txt` beside it). `main` = the released code. The app is **Mariam's Notes**, used by the owner's cousin Mariam (neuroscience/psychology student) on the MatePad.
- **What the app has** (v1.0-1.8): notebooks with 7 paper types, pens/highlighter/erasers (typed words too)/lasso (restyles typed text)/shapes, scribble to delete, Trash, Check spelling (wavy underlines), copy/cut/paste across notebooks, text boxes and pictures, folders/tags/search (handwriting included)/PIN lock/dark mode, PDF import + margins + export, Convert to text (PP-OCRv5 line recogniser + decoder + My words), Auto-convert (delay setting, held unsure lines, joins sentences), Autocorrect with tap-to-undo, Typed text settings (even size, join lines), tidy highlighter, notebook covers, backup & restore, tips, kept corrections, diagnostics. Details per version in the session sections below.
- **Little has been verified on the tablet**: the device reports are Mariam's answers to steps 1-12 of the 1.5 checklist (session 8, part 2) and steps 3-13 of the 1.6 one (session 10: backup, restore, PDF page thumbnails, pressure and the late full stop failed; typed text size, Auto on one line, sentences, lists and autocorrect worked). Treat every feature as unverified on the device; the riskiest are PDF export (PdfBox-Android, margins only checked on the JVM with Apache PDFBox), ONNX Runtime speed on the Huawei device, M-Pencil pressure/palm rejection, autocorrect taps, the line-joining thresholds, the backup Save dialog (`FileSavePlugin.kt`), the scribble thresholds, the background handwriting reader's cost on the device and `PdfStructure.kt` on PdfBox-Android.
- **Working in a cloud session** (no PC): Flutter 3.47.8 is not preinstalled; unpack it to `/opt/flutter` and call `/opt/flutter/bin/flutter` (`~/.bashrc` edits are blocked). `flutter analyze` and `flutter test --timeout 60s` run in the real project (gcc builds pdfrx's PDFium hook): **1478 pass, 2 skipped** at v1.8.0 (1428 / 2 at v1.7.0). Visual checks: render widgets to PNG in a temporary test with real fonts loaded by `FontLoader` (delete before committing); for PDF pages also fake the `plugins.flutter.io/path_provider` channel and copy `.dart_tool/hooks_runner/shared/pdfium_dart/build/*/linux-x64/libpdfium.so` to `/opt/flutter/bin/cache/artifacts/engine/linux-x64/lib/` (remove it after).
- **APKs can be built in a cloud session** (session 8): install the Android SDK to `/opt/android-sdk` (command-line tools from `dl.google.com/android/repository/commandlinetools-linux-*_latest.zip`, then `sdkmanager --sdk_root=/opt/android-sdk "platform-tools" "platforms;android-36" "build-tools;36.0.0" "ndk;28.2.13676358" "cmake;3.22.1"`, `flutter config --android-sdk /opt/android-sdk`). Maven Central answers **429** to this network's Gradle downloads: add a `~/.gradle/init.d/` script that rewrites `repo.maven.apache.org` to Google's mirror `https://maven-central.storage-download.googleapis.com/maven2/` (session 8 used one). Build in a separate `git worktree` so edits in progress do not leak into the build. Local builds are signed with the debug key (no `key.properties`): fine for checking, never for Mariam (it would not install over the release-signed app).
- **How to release from a cloud session**: the git proxy answers 403 to tag pushes, so (1) bump `version:` in pubspec.yaml and `AppInfo` (keep the build number increasing), (2) push `main`, (3) start `release.yml` by hand with the GitHub MCP tool `actions_run_trigger` (`run_workflow`, `ref: main`, `inputs: {"version": "vX.Y.Z"}`). The workflow checks the version against pubspec, builds and signs the split APKs, creates the tag with the release. From the PC, pushing a `vX.Y.Z` tag still works. Never move or delete a published tag.
- Commits from session 7 went to branch `claude/v1.4.0-mariam` first and were fast-forwarded into `main` for each release; sessions 8, 9 and 10 did the same with `claude/backup-tips-thumbnails`.
- **Waiting on**: Mariam's answers to the 1.8 checklist (`docs/tablet-test-1.8.md`, 16 steps, which fold in the 1.6 problems and three 1.7 steps never answered: copy/paste, search handwriting, share corrections; PDF bookmarks and copying typed text to other apps are still untested), the Pointer test report (Settings > Developer > Pointer test > Copy: does the M-Pencil send pressure at all?), a screenshot + Share diagnostics if PDF page thumbnails are still blank, her "Share my corrections" file; the owner's choice on audio recording (scope: simple record/play per notebook, or recordings synced to the ink). Start there when the owner brings them.

## Next steps (suggested at the end of session 7; updated in sessions 8, 9 and 10)

1. **Tablet test pass with Mariam on 1.8.0.** The checklist page the owner shares with her (https://claude.ai/artifact/FVxnATseRk6FUJcyePQRch, private until shared; read it with the Artifact tool's `read` action) holds the 16 steps of `docs/tablet-test-1.8.md` (step -> code table there; the 1.7, 1.6 and 1.5 steps are in `docs/tablet-test-1.7.md` / `-1.6.md` / `-1.5.md`; the step numbers in the notes below are the 1.6 ones). When the owner pastes her answers ("N. title: ✅ Works / ❌ Problem / ⏭️ Skipped" plus notes) and step 16's samples file:
   - fix every ❌ first, starting with data loss (backup/restore steps 3-5, scribble step 2 deleting too much), PDF export (14) and anything that crashes; ask for screenshots when a note is unclear;
   - step 2 (scribble) deleting writing or drawings it should not -> tune `ToolConfig.scribble*` (`scribbleMinContentWidth`/`Height`, `scribbleMinReversals` and the `scribbleShort*` tier) from her description, and ask whether she shades drawings;
   - steps 10-11 (sentence not joined / list joined by mistake) -> tune `ConvertConfig.join*` with her samples, not by guessing;
   - step 16's file -> recognition calibration (item 3 below);
   - after the fixes, release the next version (see "How to release" above) and give her only the steps that changed.
   Fix what she finds before adding features.
2. ~~Backup & restore~~: **built in session 8**, released in 1.6.0. Still remind the owner to back up the signing keystore (`~/Documents/MariamNotes-keystore/` on the PC): without it no update can install over the current app.
3. **Calibrate recognition on Mariam's real writing.** Since 1.7.0 every line she converts from the review sheet is kept (Settings > "Share my corrections", format 2 without pictures, `kind: kept-corrections`; render the pictures again with the desktop pipeline). Ask the owner for that file every week or two; lines with `corrected: false` were accepted as read (likely right, not certain). Measure CER/WER on 100+ lines (desktop pipeline in the session-6 notes), then tune `ConvertConfig.autoMinConfidence`, `lowConfidenceThreshold`, the decoder weights and the join thresholds (`ConvertConfig.join*`); fine-tune the 7.8 MB recogniser on her lines only if accuracy is still short.
4. ~~Local diagnostics~~: **built in session 9** (Settings > About > Share diagnostics). Read the file she sends before guessing at a device problem.
5. **Run the tests in CI.** `release.yml` runs `flutter analyze` but not `flutter test`; add the test step (with `--timeout`) before the build so a broken version cannot be published.
6. ~~Tips screen~~: **built in session 8**, released in 1.6.0.
7. Smaller: ~~PDF export drops the source PDF's bookmarks and form fields~~ (fixed in session 9, JVM-checked only). ~~White PDF thumbnails in the page grid~~ and ~~the size slider looking active with Even size~~: fixed in session 8.

## Owner decisions so far

- **Scope**: MVP + everything in "Expanded scope" above. Backup/restore was not chosen at first, then approved on 2026-10-28 (session 8), together with the Tips screen, PDF page thumbnails and the dimmed size slider (the owner picked these from the next-steps list). Scribble to delete (iPad style) was the owner's own request in session 8, with "build and release" right after. Session 9 (2026-10-29): from the list of what was still missing, the owner picked the error log + Share diagnostics, searching handwriting (moved out of "Later"), copy and paste, keeping the PDF's bookmarks and form fields, and "Keep my corrections", then "push, build and release". Audio recording was in the same list; its scope is still to be asked.
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

## Session 4 (2026-10-27): v1.1.0 'Convert to text' (model and tuning details SUPERSEDED by Session 5 below: the recogniser is now PaddleOCR PP-OCRv5, not SimpleHTR/IAM)

- Alpha test of 1.0.0: all fine except auto-tidy (it tidied after every stroke after toggling / visiting a PDF notebook). Owner then asked for a 'level 4' feature, so **auto-tidy was removed** and replaced by **Convert handwriting to typed text**.
- Pipeline: `lib/recognition/` (stroke_grouping -> word_image 128x32 -> `HtrPlugin.kt` ONNX Runtime -> ctc + lexicon rescoring) -> `integrations/convert/` (review sheet with editable lines, font picker, layout onto the baseline, one undo step). Model: SimpleHTR ONNX from PellelNitram/xournalpp-htr-simple-htr (MIT, trained on IAM, owner OK'd non-commercial use), word list = SymSpell en-80k (MIT; Google Books Ngrams CC BY 3.0). Notes + python check: `docs/htr-model-notes.md`, `docs/htr_check.py`. Credits are on the licences page (`registerRecognitionLicenses`).
- Fonts: 18 OFL families in `assets/fonts/` with the `FontKind` registry (`lib/document/font_kind.dart`); PDF export embeds the same TTFs (`PdfExportPlugin.kt`).
- Tunables to adjust after the tablet test: `ConvertConfig.lowConfidenceThreshold` (0.35, uncalibrated), `fontXHeightRatio` per font category, grouping thresholds (`GroupingConfig`), lexicon weight 0.3. The review sheet has a 'Show what the recognizer saw' section for tuning.
- Build: release arm64 APK is ~45 MB (native libs compressed via `useLegacyPackaging`; ORT adds ~34 MB per ABI uncompressed). Manifest strips INTERNET and ACCESS_NETWORK_STATE. ORT 1.31.1 (fallback 1.24.3 if it misbehaves on the Huawei device).
- NOT verified on a device: ORT session, real handwriting accuracy, UiWordImageRenderer crops, font metrics on screen, PDF font embedding. Mirror suite: 782 tests green (`--timeout 30s`).
- Removed from the code: Stroke.wordId/tidy, tidy settings, tidy integration, most of lib/beautify (kept features/stats/resample/config for grouping).
## Session 10 (2026-10-29, cloud session): v1.8.0

Same branch (`claude/backup-tips-thumbnails`), fast-forwarded into `main` for the release. Input: Mariam's answers to the 1.6 checklist (steps 3-13, photo: backup "didn't work", restore "didn't find them, add also a trash section", bring back ❌, PDF pages ❌, pressure "remains constant and no eraser at the end of my pen", full stop "didn't appear"; 7, 9-12 ✅), the owner's own test (lasso "mostly doesn't select words", no eraser for typed text, quick up-and-down scribbles typed as "A", "Baghdadidoesn't", "wong" not corrected, "Marianne" for Mariam, "test my app" put in a separate place, wants Word-style underlines and text options in the lasso) and an exported page of Mariam's real neuroscience notes.
- **Backup/restore** (`backup_service.dart`): the closure sent to `Isolate.run` captured the Settings screen through the progress callback ("object is unsendable") -> top-level `runWithProgress`; `test/settings/backup_service_test.dart` runs the real service with real isolates.
- **Late full stop** (`auto_convert_dots.dart`): band 0.8 above to 1.1 below the line (was +-0.5 x-heights); a thin upright mark below is a comma.
- **Pressure** (`InputRouter.normalizePressure`): a device reporting a raw range (0..4096) with readings already 0..1 is read as is. Pointer test has **Copy** (a short report). Unconfirmed whether the M-Pencil sends pressure; it has no eraser end (hardware).
- **Lasso** (`tools/lasso.dart`, `selection_menu.dart`): a text box is selected when the middle of any of its words is inside the loop (`textWordsOf` in `render/text_style.dart`); a stroke needs 50% of its points inside, 30% when its bounds' centre is (`lassoStroke*Fraction`); **Text style** panel (font, size, bold, italic, underline; `LassoHandler.restyleTexts`, one undo step).
- **Eraser** (`tools/text_eraser.dart`, `eraser_handler.dart`): both modes remove typed words the swept circle touches, with the ink, as one "Erase" step.
- **Scribble** (`tools/scribble.dart`): `ScribbleShape.short` tier (3 passes / 3 zig-zag turns, must cover 60% of its width); coverage as width/height shares (clear 50%/20%, short 60%/25%).
- **Recognition on her real page** (strokes rebuilt from the exported PDF's outlines, run through the app's own grouping/renderer/decoder; data in the scratchpad only): 15 lines, greedy CER 25.5%, decoded 23.2%, after autocorrect 22.7%. The current line-image settings (x-height 10 px, margin 0.15, pen 2 px) were the best of the sweeps; decoder weight sweeps moved CER by <1%. Most remaining errors are the model's reading of her writing (e.g. "controls" read as cotel/wntels/watels): the next real gain needs her corrected lines (kept corrections) for calibration or fine-tuning. Decoder lowercases words read in capitals ("PAIN" -> "Pain", by design; acronyms excepted).
- **Joining** (`convert_plan.dart` `textBeforeLine`, `PageStrokes.texts`): auto-convert reads only new writing, so each pass started a sentence and autocorrect capitalised its first word, which then failed `textCarriesOn` ("test my app" became its own box). The typed box before the line (reading order) now decides the sentence start (Convert sheet too).
- **Autocorrect** (`text_polish.dart`): a contraction glued to a name is split ("Baghdadi doesn't"); My words count in splits; `suspectsFor` (rare listed word, a letter left out of a far more frequent one with the same first letter: wong/wrong; never applied by itself). Names Mariam/Malek/Baghdadi are study words (`make_subject_words.py` `NAMES`).
- **Check spelling** (`recognition/spell_check.dart`, `integrations/autocorrect/`, `TextLayerPainter.spellMarks`): red wavy underline for unknown words, amber for suspects (scan: 1.6% of rare listed words); tap -> up to 3 spellings, Add to My words (Ignore for amber); `AppSettings.checkSpelling` (on), screen only. The word list loads in the background (`HtrRecognizer.polisher()`).
- **Trash** (see "Data & storage"; `trash_screen.dart`, side panel row "Trash", Undo in the delete snackbar).
- Tips: wavy underlines, restyle typed text, Trash, eraser on typed words.
- Verified here: analyze clean, 1478 pass / 2 skipped, local release split build (see "Start here"). NOT verified on the tablet: all of the above.

## Session 9 (2026-10-29, cloud session): v1.7.0

Same branch (`claude/backup-tips-thumbnails`), fast-forwarded into `main` for the release.
- **Keep my corrections** (`integrations/convert/kept_corrections.dart`): `ConvertSession.onKeep` gets the converted lines on apply; `keptLineEntries` makes format-2 entries without pictures (+ `keptAt`); `FileKeptCorrections` appends JSONL (serial writes, a line cut short by a crash is skipped and the next starts on a new line, oldest dropped past 1000 lines / 30 MB). Settings > Writing: switch (`AppSettings.keepCorrections`, on), "Share my corrections" (one samples file `mariams-notes-corrections-*.json` via `SampleShareService`) and delete. Only the review sheet feeds it: auto-convert lines are never reviewed, so ask Mariam to use Convert on some pages.
- **Diagnostics** (`lib/app/diagnostics.dart`): `installDiagnostics()` in `main` wraps the global `debugPrint`, so every existing `debugPrint('NeatInk: ...')` and uncaught Flutter/platform errors (`installErrorHandlers`) land in `FileDiagnosticsLog` (`<docs>/diagnostics/log.jsonl`, ~300 entries, a repeat within a minute skipped, messages cut at 6000 chars; the log's own errors go to the console only). PDF export, backup/restore and HtrException failures now log too. Settings > About > Share diagnostics (`widgets/diagnostics_tile.dart`): text report with app/system version. Tests use `InMemoryDiagnosticsLog` / `diagnosticsLogProvider`.
- **Copy / cut / paste** (`integrations/erase_select/clipboard.dart`): app-wide `editorClipboardProvider`; the lasso menu has Cut and Copy (typed text also to the system clipboard); paste = a "Paste" bubble after a lasso tap on an empty spot (`paste_bubble.dart`, `LassoState.pasteTarget`/`pasteRect`) or More > Paste (`EditorExtensions.paste`/`canPaste`, middle of the view). `LassoHandler.pasteAt`: new ids, kept on the page (`pasteOffset`), one undo step "Paste", pasted things selected. Pictures: same notebook reuses the asset (the repository keeps session assets), another notebook gets a copy of the bytes read at copy time (`NotebookRepository.readAsset`, new).
- **Search handwriting** (`integrations/search_index/handwriting_indexer.dart`): after 8 s with no stroke, controller change or viewport change, pages whose `handwritingKeyOf(strokes)` differs from the stored key are read with `recognizePages(autoFix: true)` (page in view first, cancelled by any activity) and saved with `NotebookRepository.saveHandwritingText` (new; `handwritingKeys` too). Search: `SearchMatchKind.handwriting` (rank between typed text and PDF), "Handwriting" label, draw icon. Only notebooks opened since 1.7 are searchable (the search screen and a tip say so). Setting `AppSettings.searchHandwriting` (on).
- **PDF bookmarks and forms** (`android/.../PdfStructure.kt`, called at the end of `finish`; `Session.exported` maps source page index -> first exported page): outline copied with destinations retargeted (x/y/zoom, fit, named destinations and GoTo actions resolved; items whose page was left out dropped, children kept; open state, bold/italic, colour, page mode), AcroForm copied with DA/DR/Q/NeedAppearances, fields kept when a widget is on an exported page (other widgets pruned), widgets' /P set to the exported page. Mirrored in `docs/pdf_structure_check/PdfStructureCheck.java` (Apache PDFBox 2.0.27): 17 checks pass. NOT run with PdfBox-Android on a device.
- Tips: "Search your handwriting", "Copy and paste". About text: corrections and diagnostics leave the device only when shared.
- Verified here: analyze clean, 1428 pass / 2 skipped, local release split build (see the release notes in "Start here"). NOT verified on the tablet: all of the above.

## Session 8 (2026-10-28, cloud session): backup & restore, tips, PDF thumbnails, scribble to delete; v1.6.0

Branch `claude/backup-tips-thumbnails` (from `main` at v1.5.0). The owner asked for four of the next steps: backup & restore, the Tips screen, PDF pages in the page grid, and the dimmed size slider.
- **Backup & restore** (Settings > Backup, between Export and Security):
  - Engine `lib/storage/backup/`: `zip_archive.dart` is a small ZIP writer/reader on `dart:io` (stored + deflated entries, UTF-8 names, CRC checked on every read, no ZIP64: archives over 4 GB are refused with a message). It was written instead of adding the `archive` package; tests check it against Python's `zipfile` both ways. `notebook_backup.dart` has `writeBackup`, `readBackupInfo`, `planRestore`, `restoreNotebooks`, `mergeRestoredFolders` (format and rules in "Data & storage"). Everything runs in a background isolate (`DefaultBackupService` in `lib/features/settings/backup_service.dart`, progress over a `SendPort`).
  - Saving goes through the new `FileSavePlugin.kt` (`MethodChannel('neatink/file_save')`, `saveCopy {path, fileName, mimeType}`): `ACTION_CREATE_DOCUMENT`, then the file is streamed to the chosen document on a background thread. file_picker's `saveFile` needs the whole file as bytes over the channel, which a backup with lecture PDFs (hundreds of MB) would not survive. Picking uses file_picker (`FileType.any`; the manifest check says when a file is not a backup).
  - `app.json` = `BackupAppData` (`lib/features/settings/backup_app_data.dart`): settings minus `pinHash`, `pinSalt`, `lockAfterSeconds`, `lastBackupAt`, `tipsSeen`; tool prefs; typed-text look; My words. On restore My words are always merged (add only); settings, pens and the typed-text look only when "Also restore the settings" is ticked (off by default); the device's PIN and lock stay.
  - UI `lib/features/settings/widgets/backup_settings.dart`: progress dialogs, the restore summary (`RestoreDialog`: N to add, M unchanged skipped, "Also add K changed notebooks as copies" ticked by default, settings checkbox, words count, unreadable count), a list of notebooks that failed. `AppSettings.lastBackupAt` shows "Last backup: yesterday" under the button. The library now refreshes when Settings closes (`LibraryActions.openSettings`). The About text says notebooks leave the device only when the user exports or backs them up.
- **Tips** (`lib/features/tips/`): eight tips (`appTips`), `TipsOnce` wraps the library in `NeatInkApp` and opens them once (`AppSettings.tipsSeen`, set when shown); it sits under `LockGate`, so with a PIN the tips appear after unlocking. Existing users see them once after updating. Settings > About > Tips opens them any time.
- **Page grid**: new hook `EditorExtensions.pageThumbnailBackgroundBuilder`; the PDF integration returns the same `PdfPageBackground` at thumbnail scale (renders a small image off the UI thread, reuses the shared page cache). `PageThumbnail` stacks frame (paper in the margins) -> PDF page -> ink. Checked by rendering a real two-page PDF through PDFium in a temporary test.
- **Typed text**: the size slider is dimmed (opacity 0.4) unless Custom is chosen; dragging it still switches to Custom.
- Verified here: `flutter analyze` 0 issues, **1335 tests pass, 2 skipped**, `flutter build apk --release --split-per-abi` OK in this container (arm64 43.1 MB, debug-key signed, versionCode 2007; no INTERNET permission; the `neatink/file_save` channel is in the dex). NOT verified on the tablet: the Save-to dialog and streaming (`FileSavePlugin.kt` is new native code), picking a backup from Huawei's file manager, restore on a real device, backup time and size with many PDFs, the tips text against the real screens.
- **Tablet checklist for 1.6.0**: superseded by `docs/tablet-test-1.6.md` (adds scribble to delete and the cut-off 1.5 steps); the list as first written: (1) after updating, the Tips open once; Got it closes them; they do not come back on the next start; Settings > About > Tips opens them. (2) Settings > Back up all notebooks: a progress dialog, then the system Save dialog; save to the tablet's Download folder and note how long it took and the file size; "Last backup: just now" appears. (3) Restore from a backup, pick that file: the summary says all notebooks are already here and Restore is greyed out unless something changed; edit one notebook, restore again: it comes back as "... (from backup)", the edited one is untouched. (4) Delete a test notebook, restore: it comes back in its folder with its pages, pictures and PDF. (5) In a PDF notebook, open Pages: thumbnails show the PDF pages under the ink. (6) Typed text sheet: the size slider is faint with Even size and Match my handwriting, bright with Custom. Re-test of her 1.5 problems: (7) write with the hand resting on the screen, moving to the next line: the page stays still; press harder: the line gets thicker (and send the Pointer test pressure numbers if not). (8) Auto on, write a few words, wait, carry on on the same line: one box, no gap. (9) Auto on, a sentence over two or three lines that stops before the page edge (also with a line skipped between): one box, the same size throughout, wrapped lines on the ruled lines, nothing overlapping. (10) A list, one word per line: stays a list. (11) Autocorrect: write "nuerons", "joming", "itworked", "I a not": fixed and underlined; tap to get her word back. (12) Write a word with an i or t, wait for it to be typed, then dot the i / cross the t / add a full stop: no stray marks, the full stop appears in the text.

### Session 8, part 2: Mariam's 1.5 answers and the owner's test page (fixed, released in 1.6.0)

Mariam (steps 1-12; the photo was cut off after 12): 1 ✅, **2 ❌** "no stray marks from my hand but the screen is moving as much my hand moves; no thicker lines if I pressed harder", 3 ✅, 4 ✅ "no words were wrong, just one (i) wasn't converted", **5 ❌** "it was converted but the gap is still here", 6 ✅, 7 ✅, **8 ❌** "it didn't work", 9 ✅, 10 ✅ "very good", 11 ✅ "excellent", 12 ✅ "EXCELLENT". The owner's own Auto page (lined paper, big writing two rulings apart): lines never joined; "Okay this time it worked" covered the wrapped second line of the box above; "What is the" came out smaller; autocorrect left "joming", "hamberger", "I a not" alone and turned "onvert" into "overt"; "itworked" / "Whyisn't!" glued; phrases on one line stayed separate boxes with gaps. Fixes (each with tests; numbers in `ConvertConfig` / `PolishConfig`):
- **Joining** (`continuesOnNextLine`, `textCarriesOn`, `startsListItem`; batch layout and `planMerge` alike): besides "ran to the right edge", the words decide: the line ends with a comma/hyphen or a `continuationWords` word (articles, prepositions, conjunctions, auxiliaries...), or the next line starts in lowercase and the lines have >= 3 and >= 2 words. One skipped ruled line is fine (`joinMaxRulings` 2.6, `joinMaxXHeights` 8). Never across a sentence end or into a list item; Mariam's step-7 list (brain / neurons / synapse) stays apart.
- **Size**: even and custom sizes never shrink (no collision shrink, no cap from the line above); a box in the way of the next is pushed down to the next free ruled line (`_pushDown`). Match-my-handwriting still shrinks to fit.
- **Ruled line spacing**: converted text on ruled paper gets `TextItem.lineSpacing` = the ruling (JSON `lineSpacing`, optional; `textStyleFor` sets `height`), so wrapped lines sit on the ruled lines (screen, PDF export and the editor all use `layoutTextItem`).
- **No overlaps** (`convert_overlap.dart`): new boxes from Auto or the Convert sheet move down to the next free line instead of covering a box; a merge that would grow over a box written earlier is not made.
- **Auto on the same line** (`planMerge`): same ruled line or within 1 x-height (`mergeBaselineTol`), the pen may start over the old writing's end (`mergeInkOverlap` 1.5) or anywhere over the space it left, up to 4 x-heights after it (`mergeMaxGap`), no other box in between; for boxes without session memory the old writing's end is estimated (`estimatedInkRight`, `maxInkWidthScale` 3).
- **Autocorrect** (`TextPolisher._spelling`, `handwritingDistance` in `lexicon.dart`): a noisy channel, score = ln P(word) - 5 x distance, with look-alike letters (0.6) and letter groups (`m`~`in`, `cl`~`d`: 0.5) cheap, +0.25 for another first letter, words of 4+ letters, close matches (<= 1) down to rank 45000, a 1.0 margin (rivals that may not win still count, so `onvert` stays). Split of glued words when two listed words (or contractions) explain it (`itworked`, `Whyisn't`), and `I a` -> `I am`. Checked on correct neuroscience sentences with the real list: no false fixes; `todo` -> `to do` is the one borderline.
- **Palm** (`InputRouter`, `DocumentView`): touches ignored 1 s after the pen (was 0.3 s); a pan by touches still down when the pen lands is undone if it began up to 3 s before (was 0.4 s); a touch landing while a rejected palm rests is ignored. **Pressure**: ballpoint thinning 0.25 -> 0.5 (about 0.7x-1.3x width). Pressure itself is NOT confirmed on the device: ask for the Pointer test reading.
- **Late dots** (`auto_convert_dots.dart`): an i-dot, t-bar or full stop written after its word was typed was kept as a stray mark; now dots/short bars on a typed box or on the writing it replaced are removed with the conversion, a dot at the end on the baseline adds `.` (below it `,`), and dots away from any text never become a box of their own (held quietly). `PageConversion.hasChanges` counts stroke removals. If Mariam's "(i) not converted" (Convert button) persists, ask for a Share-samples file of that page.
- Verified here: analyze clean, full suite 1362 pass / 2 skipped, release split APKs built in the container (arm64 43.1 MB, no INTERNET). NOT verified on the tablet: everything in this list; the join rules and palm timings are first guesses tuned on the owner's photo.

### Session 8, part 3: Scribble to delete and the 1.6.0 release

- **Scribble to delete** (owner request, like the iPad): a pen stroke that goes back and forth over handwriting or typed text deletes what it covers, in one undo step "Scribble to delete"; the scribble itself is not added. Settings > Writing > "Scribble to delete" (`AppSettings.scribbleToDelete`, JSON key `scribbleToDelete`, on by default; backups carry it) and a tip.
  - Shape (`tools/scribble.dart`, `isScribbleShape`): principal axis of the points; back and forth along it (>= 4 reversals with hysteresis, swings >= 30% of its length, path >= 2.5 x length) or zig-zag across it (>= 5 turns, swings >= 60% of its height, path >= 1.8 x length); at least 8 pt long. Letters like "M", "ll" or cursive "mm" pass the shape test too.
  - So what counts is the content (`planScribble`): strokes with >= 60% of their points in the scribble's bounds (+2 pt), or covered over >= 60% of their width and >= 35% of their height (a tall `l` crossed out through its middle); typed words whose box is covered the same way (laid out with `layoutTextItem`). The covered things must fill >= 30% of the scribble's area, else it is ink (writing over a stray dot, a scribble on empty paper). A closed outline around the whole scribble (a hand-drawn circle, a snapped rectangle/ellipse/triangle) is kept: shading inside a drawn cell does not erase the cell. Long lines crossing it stay.
  - Typed text loses only the covered words (`withoutWords` keeps a line break if one was there), the box is re-measured, and an emptied box is removed. Numbers: `ToolConfig.scribble*`.
  - Wiring: new hook `EditorExtensions.strokeGestures`, asked by `InkToolHandler._finish` for pen strokes before the shape hook and the stroke finishers; a taken stroke cancels the live hook and emits no finished event (auto-convert skips strokes that vanished). `integrations/scribble/scribble_integration.dart`, installed last in `defaultEditorIntegrations`.
  - Not verified on the tablet: the thresholds (first guesses on synthetic strokes). Risk: shading inside a drawing that is not a closed outline (hatching between separate lines) erases those lines; undo brings them back and the setting turns it off.
- **Release 1.6.0**: pubspec `1.6.0+8`, `AppInfo`; README (scribble, backup, tips, PDF thumbnails, "leaves the tablet only when you export or back up"); `docs/tablet-test-1.6.md`; the shared checklist page updated in place to the 16 steps. Verified before releasing: analyze clean, 1389 pass / 2 skipped, local `flutter build apk --release --split-per-abi` in a worktree. `main` fast-forwarded to the branch, then `release.yml` started by hand with `v1.6.0`.

## Session 7 (2026-10-28, cloud session): v1.4.0 and v1.5.0 (details; the summary is in "Start here")

- **v1.3.0 was released** (tag `v1.3.0`, GitHub Release published 2026-10-28 09:43 UTC).
- **Environment**: this session ran in a Linux cloud container, not on the owner's PC. Flutter 3.47.8 was unpacked to `/opt/flutter` (call `/opt/flutter/bin/flutter`; `~/.bashrc` edits are blocked); no test mirror is needed there because gcc/clang build pdfrx's PDFium hook, so `flutter test` runs in the real project (1212 pass, 2 skipped). There is no Android SDK, so APKs come only from the tag workflow. The container is wiped between sessions: the owner can add the Flutter download to the environment's setup script. Desktop ONNX checks used a Python venv (numpy, pillow, onnxruntime) in the session scratchpad.
- **Mariam's samples** (format 2, 7 lines of neuroscience notes, NOT corrected in the sheet; truth transcribed from the strokes): 27.1% CER / 74% WER on the tablet -> 7.5% / 31% now. Changes: horizontal stretch of small x-heights (`recognitionLineImageConfig.xHeightWidthPx` 10), safer i-dot snapping (short stems, upright stems only, t-bars are not dots), decoder no longer glues unknown words (per-letter cost beyond 8 letters, `cutPeak` 0.6, ascent from one start per word count, split after `.`/`,` inside a word, 3 edits for 10+ letters), study vocabulary `assets/htr/subject_words.txt` + always-capital acronyms. Details and reproduction: `docs/htr-model-notes.md` (v1.4.0 section). Tuned on 7 lines only: ask for CORRECTED pages next.
- **Auto-convert** "sometimes does not convert": a line below the confidence gate was skipped silently and never read again, and the gate (0.5) held back every one of Mariam's lines, even perfectly read ones. Now: gate 0.25 (`ConvertConfig.autoMinConfidence`), an unsure line is *held* and read again as a whole when more is written on the same line, and a "Not sure about N lines: kept as handwriting · Review" chip (6 s, opens the review sheet). New setting **Wait before converting** (`AppSettings.autoConvertDelayMs`, 1-10 s, default 2 s; Settings > Writing).
- **System bars**: Android 15+ draws the app edge to edge and `showModalBottomSheet(useSafeArea: true)` does not guard the bottom, so the Convert sheet's button, the new-notebook sheet's Create button, the page pill, the page grid and the "New" menu sat under the navigation bar. `lib/app/insets.dart` (`bottomSafeSpace`, `withBottomSafeSpace`, `menuSafePadding`): use it for anything new at the bottom edge.
- Version **1.4.0+6** (pubspec + `AppInfo`). Not verified on the tablet: everything above; the wider line images cost the model up to 2.5x more width per line (decode measured 15-125 ms/line in debug JIT on the desktop).
- **Later in session 7 (owner request, before releasing 1.4.0)**:
  - *Auto-convert gap*: writing just after already-typed text now joins that text box (gap measured from the typed text's end, `auto_convert_merge.dart`), instead of starting a new box with a big space.
  - *Tidy highlighter* (Settings > Writing, on by default): a highlight over handwriting, typed text or PDF text becomes a straight band fitted to that line (`tools/highlight_tidy.dart`, `integrations/highlight/`); `raw` and the drawn width (`rawSize`) are kept, lasso "Restore original" undoes it. PDF word boxes come from pdfrx (`PdfEngine.words`).
  - *Covers*: library menu "Cover…" and the new-notebook sheet open a cover sheet (16 colours, 9 patterns, 16 science pictures in 4 subjects drawn in code in `render/cover_painter.dart`, or a photo normalised to 1200 px).
  - *PDF margins*: None / Narrow (25% of the PDF page width per side) / Wide (50%), asked at import (last choice remembered in `AppSettings.pdfMargins`) and changeable from the editor menu ("PDF margins…", one undo step, notes move with their page, asks before hiding notes). Export grows the imported page's visible box on the displayed sides (`PdfMargins.kt`, `PdfCoords.withSideMargins`, mirrored and tested in `pdf_coords.dart`) and clips the original content to its old box; verified on the JVM with Apache PDFBox 2.0.32 + PDFium render for 0/90/270 degree pages and an offset CropBox, NOT on the device (PdfBox-Android).
  - Full suite: 1272 pass, 2 skipped. Not verified on the tablet: all of the above.
  - Release: the cloud session's git proxy answers **403 to tag pushes**; `release.yml` got a manual start with a `version` input that creates the tag (see "Start here"). v1.4.0 was released that way.
- **v1.5.0 Typed text (owner request after trying auto-convert)**: `ConvertStylePrefs.sizeMode` (`ConvertSizeMode.even` default / `handwriting` / `custom`; old saved 'auto' reads as even) and `joinLines` (default on). Even size = `evenFontSize(ruling)`: ruling x `ConvertConfig.evenSizeOfRuling` (0.62: 26 pt lines -> 16 pt), 16 pt without lines; even and custom sizes wrap at the right margin instead of shrinking (only a collision with the line below still shrinks). Joining: `continuesOnNextLine` (no sentence end, ink within max(20% page width, 8 x-heights) of the right edge, next line starts within 4 x-heights of the left, at most 1.6 rulings / 5.5 x-heights lower) merges lines in `layoutPage` (`LaidOutLine.members`) and, across auto-convert passes, `planMerge(joinLines:)` appends to the box above (wrapping). The "Typed text" sheet (`convert_style_sheet.dart`, shared `ConvertStyleControls`) opens from the tune button next to Auto (`EditorExtensions.convertSettings`) and Settings > Typed text, with nothing to convert too; it also holds Auto-convert on/off, the wait and Autocorrect. Thresholds untested on real writing: ask Mariam whether list items get joined by mistake.
- **v1.5.0 Autocorrect (iPad style, owner request)**: Settings > "Autocorrect" (`AppSettings.autocorrect`, JSON key `autocorrect`, ON by default; it replaces "Fix spelling automatically"/`autoFixSpelling`, whose old saved value is ignored, so everyone starts with it on). Fixes from `TextPolisher` (spelling, apostrophes, capitals, a/an both ways, `could of` -> `could have`, `their is` -> `there is`, `alot`, repeated words) are applied when handwriting becomes text (sheet and auto-convert); every non-capital fix is recorded on its box (`TextItem.corrections`, `locateCorrections` in `convert_plan.dart`, carried through auto-convert merges). The text layer draws a dotted blue underline (screen only). A pen tap or quick finger tap on the word (`EditorExtensions.pageTapHandlers`, tap detection in `InkToolHandler` and `DocumentView`) opens a bubble (`integrations/autocorrect/`): "undo-arrow + written word" puts it back (one undo step, and a spelling fix taken back is learned in My words), the tick keeps it and removes the mark. Not verified on the tablet.

## Session 6 (2026-10-28): v1.3.0 whole-line recognition

- Owner's Share-samples file from 1.2.1 (strokes of "Malek"/"Baghdadi" on two lines, "Nuerons are in the brain", "isnt working well"): the app produced "Male", nothing, "3 erons are A the e b ri U", "Sat work r in well" (~49% CER). Cause was the pipeline, not the model: word splitter cut letters apart, i-dots became words, two lines merged (single-valley line split bug), and the rescorer overwrote correct unknown words. Details and numbers: `docs/htr-model-notes.md` (v1.3.0 section).
- Research (2026-10-28, workflow): no off-the-shelf model beat PP-OCRv5 mobile on whole lines of this handwriting (PP-OCRv6 small/medium ~same, TrOCR-small hallucinates, OnlineHTR IAM-OnDB weights ~20% CER, Kraken v6 worse); small OCR-VLMs (PaddleOCR-VL, GLM-OCR) are 0.6-1.4 GB, ~2-6 s/line est., unproven on handwriting at that size. Owner chose: fix the pipeline, keep the model; corrections suggested by default with an auto-fix setting.
- New code: `stroke_grouping.dart` (peak-first line split, per-line x-height, dot assignment, `RecognizedLine.inkStrokes`/`copyWith`), `word_image.dart` (`renderLineImages`, `LineImage`, `assignStrokesToSpans`, `snapDots` on for recognition), `line_decoder.dart` (evidence-preserving line decoder), `text_polish.dart` (suggestions), `htr_channel.dart` `recognizeLines`, `HtrPlugin.kt` max width 2400, convert plan/session/sheet/auto-convert line-level, suggestion chips + "Fix all" + undo chips, Settings "Fix spelling automatically" (`autoFixSpelling`, default off), Share samples **format 2** (one entry per line with the exact model image, strokes in writing order, recognised + final text).
- Verified: full mirror suite 1183 passed / 2 skipped (the two env-gated sample tests), analyze 0 issues, release split build OK (arm64 40.9 MB, versionCode 2005, no INTERNET). End-to-end on the owner's page through the Dart renderer + desktop ORT + Dart decoder: 4 lines found, CER 5% with empty My words (only "Malck"), 0% with Malek/Baghdadi in My words; decode 2-10 ms/line.
- Env-gated desktop checks (personal data stays in the session scratchpad, never in git): `NEATINK_SAMPLES=<samples.json> NEATINK_DUMP_DIR=<dir> flutter test test/recognition/sample_render_dump_test.dart` (in the mirror) renders the lines; `python dump_probs.py --pngs <dir> out.json` (scratchpad `htrbench/`, needs a `truth.json`) runs the model; `NEATINK_LINE_PROBS=out.json flutter test test/recognition/line_decoder_samples_test.dart` decodes.
- NOT verified on the tablet. Uncalibrated: line confidence (min word confidence; "Not sure" < 0.35, auto-convert >= 0.5); a confidently misread unknown word ("Malck") scores ~0.95. Stroke timestamps are still per-stroke relative (no absolute start time on `Stroke`), which online/trajectory models would need.
- Next: owner's cousin Mariam (the real user) writes 2-3 pages (copied passage + own notes), corrects each line to exactly what she wrote (mistakes included, do not accept spelling chips for these), and shares format-2 files. Use them to measure CER/WER on 100+ lines, calibrate the thresholds, and, if needed, fine-tune the 7.8 MB recogniser on her lines with a held-out split.

## Session 5 (2026-10-27): v1.2.0 recognition rework

- Owner tested v1.1.0 on the tablet with real handwriting: about half the letters were wrong (SimpleHTR/IAM model: 'Malek'->'Maick', 'Mariam'->'Masiasn', 'Note'->'Notc'), with 0.9+ confidence on wrong words. Benchmarked on real crops from the tablet screenshot (exact words of 9): SimpleHTR 2, TrOCR-small 3 (hallucinates words, rejected), **PaddleOCR PP-OCRv5 English mobile rec 5-6** -> adopted (Apache-2.0, 7.8 MB, `assets/htr/model.onnx` + `charset.json`). Bench scripts + notes: `docs/htr_bench/`, `docs/htr-model-notes.md` (crops themselves are personal and were NOT committed).
- Remaining errors are genuinely ambiguous letters ('e' written like 'c', cursive 'r'), so the language layer matters: `lib/recognition/rescorer.dart` (look-alike smoothing, word list + **personal dictionary**), `user_lexicon.dart` (JSON in app docs dir), learning from review-sheet corrections (`RecognizerWordLearner`), **Settings > My words** screen. With Malek/Mariam/Baghdadi in My words the desktop benchmark reaches 7/9.
- Word grouping is adaptive now (the 'Note'+'boo'+'k' split bug).
- NEW **Auto-convert** (toggle in the editor top bar + Settings, like the old tidy toggle): ~1 s after the pen lifts, lines whose words all pass `autoMinConfidence` (0.5) become text in the remembered style; others stay ink; merges into the previous box on the same baseline; one undo step 'Auto-convert'. Code: `integrations/convert/auto_convert_*.dart`.
- NEW **Share samples** button in the Convert review sheet: writes `mariams-notes-samples-*.json` (word strokes + the exact model input PNG + corrected text) and opens the share sheet so the owner can send real data for tuning/fine-tuning (nothing is sent automatically). Ask the owner for these files before tuning more.
- Tunables (all uncalibrated until real data): `RescoreConfig` (lambda 0.6, confusionMass 0.08...), `ConvertConfig.lowConfidenceThreshold` 0.35 / `autoMinConfidence` 0.5 / `autoIdleMs` 1000, `GroupingConfig`, `wordImageStrokePx` 1.8.
- Possible next steps if accuracy is still short: fine-tune the recogniser on the owner's shared samples (convert ONNX->PyTorch with onnx2torch, CPU is enough for a 7 MB model), add a line-level pass, ensemble with a second model.
- Release 1.2.0: pubspec 1.2.0+3. Licence credits updated (PaddleOCR Apache-2.0; SimpleHTR/IAM credit removed).
- **Released 2026-10-27: v1.2.0** (tag pushed, release published by `release.yml`, ~93 MB universal APK, arm64 ~41 MB; manifest has no INTERNET / ACCESS_NETWORK_STATE). Download link unchanged: `releases/latest/download/MariamsNotes.apk`. Not yet tested on the tablet: ask the owner for the result of the 'My words' + Convert + Auto test and for a 'Share samples' file before tuning further.
- Publishing workflow: the owner added allow rules to `~/.claude/settings.json` (`git push`, `git tag`, `gh run`, `gh release view`), so `git push origin main`, `git tag vX.Y.Z && git push origin vX.Y.Z` and `gh run watch` now work without prompts. `gh secret set` / `gh repo create` / deleting tags are still blocked by the auto-mode classifier (its environment says no trusted repo; adding `MalekBaghdadi/NeatInk` as the trusted repo in `autoMode.environment` would be the next step if pushes get blocked again). Never move/delete a published tag: bump the version and tag again.
- **v1.2.1 (2026-10-27): the 1.2.0 download link was reported as not downloading.** From the PC everything about v1.2.0 was fine (link resolves, 92.85 MB universal and 42.87 MB arm64 files match GitHub's SHA-256, arm64 APK is valid and signed with the release key), so the cause could not be reproduced; the real symptom on the tablet is not known (ask: browser download failing, "App not installed", or a crash on launch?). Two real weaknesses were fixed: (1) the universal APK had versionCode = build number (3) while per-ABI APKs have 1000 x ABI + build (arm64 2003), so a tablet that had any split APK installed refused the universal one as a downgrade; (2) the universal APK was 93 MB because ONNX Runtime ships once per ABI. Now `release.yml` publishes only split APKs: `MariamsNotes.apk` is the **arm64** build (~43 MB) and `MariamsNotes-armeabi-v7a.apk` the 32-bit one, plus `SHA256SUMS.txt`, and it runs `apksigner verify` before publishing. `flutter build apk --target-platform android-arm64` does NOT strip other ABIs here (still 66 MB with all three ABIs' native libs), so use `--split-per-abi`. Keep versionCodes monotonic: release only through the split build.

## Session 3 (2026-10-27): wave 2 finished

- Three wave-2 files had been NUL-corrupted by a cut-off (shapes handler + integration, tidy test); they were deleted and redone. **After any cut-off, scan for NUL bytes** (Grep `backslash-x00` with multiline over lib/ and test/).
- All six integrations exist, are tested in the mirror, and are installed by the real app: `lib/features/editor/default_integrations.dart` lists them and `main.dart` overrides `editorIntegrationsProvider` with it. The provider's own default stays empty on purpose: `pdfIntegration` imports pdfrx, which would stop every editor test from loading in the mirror.
- Full mirror suite: 739 tests pass (`flutter test --reporter expanded --timeout 30s`, ~20 s). `flutter analyze`: 0 issues. Always pass `--timeout`: a stuck test otherwise hangs the run for 20+ min.
- Test gotcha: `controller.close()` renders a thumbnail (`picture.toImage`), which hangs under `flutter_tester`; tests call the handlers' `commitPending()` / `beforeSaveHooks` instead.
- Fixed: image corner-resize could not shrink horizontally (`resizedImageFrame`).
- Untested by construction (import pdfrx): `integrations/pdf/pdf_background.dart`, `pdf_integration.dart`. Never run on a device: everything in wave 2.
- Gate (2026-10-27): `flutter build apk --debug` OK; `flutter build apk --release --split-per-abi` OK (arm64 31.9 MB, debug-key signed). `apkanalyzer manifest permissions` on the arm64 release APK shows no INTERNET and no storage permissions (only the app's own DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION). Dependency licenses are all MIT/BSD/Apache. Remaining: release steps 7-8 (icon, signing, README, repo + push [ask first], GitHub Release, workflow [needs `workflow` scope], tablet checklist).
- **Released 2026-10-27: v1.0.0** at https://github.com/MalekBaghdadi/NeatInk/releases (public repo, GitHub Actions `release.yml` builds on `v*` tags). The app is named **Mariam's Notes** (for the owner's cousin Mariam; `AppInfo.name`, launcher label, pink flower icon); project, package and repo stay NeatInk. Download link: `releases/latest/download/MariamsNotes.apk`. Signing: keystore + password in `~/Documents/MariamNotes-keystore/` (owner must back it up; the same key is in the repo secrets `KEYSTORE_BASE64`, `KEY_PASSWORD`; local `android/key.properties` is git-ignored). Not yet verified on a tablet. Next version: bump `version:` in pubspec.yaml and `AppInfo`, push a new tag (do not move or delete tags: the auto-mode classifier blocks it).
- Auto-mode classifier blocks public-repo creation, secret writes and tag deletes even when the owner approves in chat; the owner ran those commands with `!` (keep commands under ~90 chars so they do not wrap).
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

## Original build plan (session 1)

Done: NDK, tests in the real project, waves 1 and 2, the review pass and the v1.0.0 release (sessions 2-3). The current next steps are in "Start here" at the top of this section.
