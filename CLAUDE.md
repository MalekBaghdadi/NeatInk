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
    tour/                 # Guided tours: dim the screen, light one button at a time (v1.12.0)
    recording/            # Lecture recorder (one at a time, survives leaving the notebook) + library banner
  audio/                  # MethodChannel wrapper for the native recorder/player
  ink/                    # Pure Dart, no Flutter widgets: Stroke, InkPoint, geometry utils
  document/               # Pure Dart: notebook/page models, paper geometry, undo/redo commands
  render/                 # Flutter painting shared by screen + PDF export (stroke outlines, paper, text styles)
  beautify/               # Pure Dart: handwriting geometry helpers (baseline, x-height, deskew, stats, resampling); the tidy pipeline was removed
  pdf/                    # pdfrx rendering helpers + PdfExport channel wrapper
  storage/                # Repositories, JSON codecs, atomic file writes, autosave; backup/ = ZIP backups
android/app/src/main/kotlin/.../PdfExportPlugin.kt   # PdfBox-Android export
android/app/src/main/kotlin/.../FileSavePlugin.kt    # "Save to" dialog that streams a file (backups)
android/app/src/main/kotlin/.../AudioPlugin.kt       # MediaRecorder (AAC/ADTS) + MediaPlayer, channel neatink/audio
android/app/src/main/kotlin/.../RecordingService.kt  # Foreground service (type microphone) while recording
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
- **Recordings** (v1.12.0): `<notebook>/audio/<id>.aac` (AAC in ADTS, 64 kbit/s mono, ~29 MB per hour; plays even when cut short) and `audio/recordings.json` (`{"version": 1, "recordings": [{"id", "title", "file", "createdAt", "spans": [{"wallStart", "wallEnd", "audioStart"}], "inProgress"}]}`: one span per stretch between pauses maps the wall clock to the sound). Notes carry when they were written: `Stroke.writtenAt` (JSON `"at"`, ms since the epoch) and `TextItem.times` (`[{"start", "at"}]` per converted line). The folder travels with the notebook (backups, Trash, duplicate).
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

Backup/restore was offered and not chosen at first; the owner approved it on 2026-10-28 (session 8, see "Session 8" in `docs/session-history.md`).

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
- Stickers.
- Wi-Fi transfer to a PC (backup to a file was built in session 8).
- Low-latency front-buffer rendering via Android `androidx.graphics` (only if ink latency is a problem).

---

# STATUS & HANDOFF (read this first in a new session)

**Session 4 (2026-10-27): auto-tidy was removed.** After alpha testing, the owner replaced it with a planned "convert handwriting to typed text" feature (v1.1, plan in `~/.claude/plans/shimmering-kindling-thacker.md`). Removed: `integrations/tidy/`, the toolbar `TidyToggle`, the settings `tidyEnabled`/`tidyStrength`/`slantMode`/`debugOverlay`, `Stroke.wordId` and `TidyInfo`, and the tidy pipeline files in `lib/beautify/` (`tidy_pipeline`, `transform`, `smoothing`, `word_segmenter`, `line_context`). Kept: `lib/beautify/{features,stats,resample,tidy_config}.dart` (reused by recognition) and their tests. Old saved prefs and page JSON that contain the removed keys still load (unknown keys are ignored). Notes in `docs/session-history.md` that describe tidy are historical.

_Last updated 2026-10-30 by Claude (session 14). Keep this section current: update it whenever something here changes._

The detailed notes of every session (2-11: what was built, why, the numbers, how it was checked) moved to `docs/session-history.md` on 2026-10-29 to keep this file short. Search it when a feature's details matter; add each new session's notes there (newest first) and keep only the current state here.

## Start here (state at the end of session 14)

- **v1.13.0** (pubspec `1.13.0+15`, `AppInfo`): **add words in the middle of typed text**: the lasso menu has Edit text with the pen (a writing bar under the pages; what she writes there goes in at the cursor or over the selected word) and Edit text with the keyboard; **any colour** for the pen, the highlighter and typed text (the picker starts with 40 ready colours; in portrait the tool options get their own row so nothing is off screen). Details in "Session 14, part 2" and "part 3" of `docs/session-history.md`; checklist `docs/tablet-test-1.13.md` (9 steps).
- **Previous: v1.12.0** (pubspec `1.12.0+14`, `AppInfo`), released 2026-10-30 09:15 UTC from `main` (`0c23c37`) with `release.yml` started by hand (run #14; downloaded APKs checked: versionCode 2014 / 1014, same release key as 1.11.0, no INTERNET, new permissions RECORD_AUDIO / FOREGROUND_SERVICE(_MICROPHONE) / POST_NOTIFICATIONS / WAKE_LOCK, `RecordingService` declared with type microphone, SHA-256 matches `SHA256SUMS.txt`): **record a lecture** while writing (microphone button in a notebook; foreground service, keeps going in other apps and with the screen off; Pause / Go on / Stop; a banner in the library while it records) and play it back from the headphones button: **Play**, or **Play with notes** (notes faint until the sound reaches the moment they were written; tap a note to hear that moment); **guided tours** (library, notebook, PDF notebook: one lit button at a time, once by themselves, again from ⋮ › Show me around or Settings) and plain-language **tooltips** on every button (long press or pen hover). Details in "Session 14" of `docs/session-history.md`; checklist `docs/tablet-test-1.12.md` (11 steps).
- **Previous: v1.11.0** (pubspec `1.11.0+13`, `AppInfo`), released 2026-10-29 20:47 UTC from `main` (`6a2b36a`) with `release.yml` started by hand (run #13; downloaded APKs checked: versionCode 2013 / 1013, same release key as 1.10.0, no INTERNET, SHA-256 matches `SHA256SUMS.txt`): fixes for Mariam's 1.10 answers (autocorrect catches far more misspellings and leaves British spellings and her course terms alone; one-stroke arrows found reliably and a pause at the tip no longer snaps the shaft; "Send writing samples", one tap, Auto's lines kept too; Auto keeps carrying on a box after its text was fixed). Details and numbers in "Session 13" of `docs/session-history.md`; checklist `docs/tablet-test-1.11.md` (7 steps).
- **Previous: v1.10.0** (pubspec `1.10.0+12`, `AppInfo`), released 2026-10-29 15:34 UTC from `main` (`a364fe6`) with `release.yml` started by hand (run #12; downloaded APKs checked: versionCode 2012 / 1012, same release key as 1.9.0, no INTERNET, SHA-256 matches `SHA256SUMS.txt`): fixes for the owner's 1.9.0 test (autocorrect/spelling bubble taps did nothing, arrows found 2 of 8 so the detector was rewritten, new lines joined the line above after a few lines of notes). Details in "Session 12" of `docs/session-history.md`; checklist `docs/tablet-test-1.10.md` (8 steps).
- **Previous: v1.9.0** (pubspec `1.9.0+11`, `AppInfo`), released 2026-10-29 14:21 UTC from `main` (`e78cfc3`) with `release.yml` started by hand (run #11; downloaded APK checked: versionCode 2011, release key same as 1.8.0, no INTERNET, SHA-256 matches `SHA256SUMS.txt`). New in it: Mariam's session-11 list (PDF margin notes stay in their margin on its lines, lasso Edit text, arrows → in typed text, punctuation kept, no capital when carrying on, decoder and autocorrect fixes from her samples); details in "Session 11" of `docs/session-history.md`. Previous: v1.8.0 (`1.8.0+10`, 2026-10-29 13:10 UTC: backup/restore fix, Trash, Check spelling, lasso text style, eraser on typed text, scribble tiers), v1.7.0 (`1.7.0+9`, 2026-10-29 08:24 UTC: copy/cut/paste, search handwriting, keep my corrections, share diagnostics, PDF bookmarks and forms), v1.6.0 (`1.6.0+8`, 2026-10-28 21:23 UTC: backup & restore, tips, PDF page thumbnails, scribble to delete, the fixes for Mariam's 1.5 answers), v1.5.0 (`1.5.0+7`, 2026-10-28 17:03 UTC). Download: `https://github.com/MalekBaghdadi/NeatInk/releases/latest/download/MariamsNotes.apk` (arm64, 43 MB; `MariamsNotes-armeabi-v7a.apk` and `SHA256SUMS.txt` beside it). `main` = the released code. The app is **Mariam's Notes**, used by the owner's cousin Mariam (neuroscience/psychology student) on the MatePad.
- **What the app has** (v1.0-1.13): notebooks with 7 paper types, pens/highlighter/erasers (typed words too)/lasso (edits and restyles typed text)/shapes, arrows read as → in typed text, scribble to delete, Trash, Check spelling (wavy underlines), copy/cut/paste across notebooks, text boxes and pictures, folders/tags/search (handwriting included)/PIN lock/dark mode, PDF import + margins + export, Convert to text (PP-OCRv5 line recogniser + decoder + My words), Auto-convert (delay setting, held unsure lines, joins sentences), Autocorrect with tap-to-undo, Typed text settings (even size, join lines), tidy highlighter, notebook covers, backup & restore, tips, kept corrections, diagnostics, lecture recording with Play / Play with notes, guided tours and button tooltips, a pen writing bar to add words anywhere in typed text, any colour for pen / highlighter / typed text. Details per version in `docs/session-history.md`.
- **Little has been verified on the tablet**: the device reports are Mariam's answers to steps 1-12 of the 1.5 checklist (session 8, part 2) and steps 3-13 of the 1.6 one (session 10: backup, restore, PDF page thumbnails, pressure and the late full stop failed; typed text size, Auto on one line, sentences, lists and autocorrect worked). Treat every feature as unverified on the device; the riskiest are PDF export (PdfBox-Android, margins only checked on the JVM with Apache PDFBox), ONNX Runtime speed on the Huawei device, M-Pencil pressure/palm rejection, autocorrect taps, the line-joining thresholds, the backup Save dialog (`FileSavePlugin.kt`), the scribble thresholds, the background handwriting reader's cost on the device, `PdfStructure.kt` on PdfBox-Android, and the recording service under EMUI's battery manager (an hour with the screen off).
- **Working in a cloud session** (no PC): Flutter 3.47.8 is not preinstalled; unpack it to `/opt/flutter` and call `/opt/flutter/bin/flutter` (`~/.bashrc` edits are blocked). `flutter analyze` and `flutter test --timeout 60s` run in the real project (gcc builds pdfrx's PDFium hook): **1555 pass, 2 skipped** at v1.12.0 (1531 / 2 at v1.11.0). Visual checks: render widgets to PNG in a temporary test with real fonts loaded by `FontLoader` (delete before committing); for PDF pages also fake the `plugins.flutter.io/path_provider` channel and copy `.dart_tool/hooks_runner/shared/pdfium_dart/build/*/linux-x64/libpdfium.so` to `/opt/flutter/bin/cache/artifacts/engine/linux-x64/lib/` (remove it after).
- **APKs can be built in a cloud session** (session 8): install the Android SDK to `/opt/android-sdk` (command-line tools from `dl.google.com/android/repository/commandlinetools-linux-*_latest.zip`, then `sdkmanager --sdk_root=/opt/android-sdk "platform-tools" "platforms;android-36" "build-tools;36.0.0" "ndk;28.2.13676358" "cmake;3.22.1"`, `flutter config --android-sdk /opt/android-sdk`). Maven Central answers **429** to this network's Gradle downloads: add a `~/.gradle/init.d/` script that rewrites `repo.maven.apache.org` to Google's mirror `https://maven-central.storage-download.googleapis.com/maven2/` (session 8 used one). Build in a separate `git worktree` so edits in progress do not leak into the build. Local builds are signed with the debug key (no `key.properties`): fine for checking, never for Mariam (it would not install over the release-signed app).
- **How to release from a cloud session**: the git proxy answers 403 to tag pushes, so (1) bump `version:` in pubspec.yaml and `AppInfo` (keep the build number increasing), (2) push `main`, (3) start `release.yml` by hand with the GitHub MCP tool `actions_run_trigger` (`run_workflow`, `ref: main`, `inputs: {"version": "vX.Y.Z"}`). The workflow checks the version against pubspec, builds and signs the split APKs, creates the tag with the release. From the PC, pushing a `vX.Y.Z` tag still works. Never move or delete a published tag.
- Commits from session 7 went to branch `claude/v1.4.0-mariam` first and were fast-forwarded into `main` for each release; sessions 8 to 11 did the same with `claude/backup-tips-thumbnails`, sessions 12 and 13 with `claude/autocorrect-arrows-join` (now equal to `main`). A new session works on the branch it is given (start it from `main`) and fast-forwards `main` to it for each release.
- **Waiting on**: Mariam's answers to the 1.13, 1.12 and 1.11 checklists (`docs/tablet-test-1.13.md`, `-1.12.md`, `-1.11.md`: she had not tested 1.11 or 1.12 when 1.13 came out; she reported the 1.10 and 1.9 steps working apart from autocorrect and one-stroke arrows, fixed in 1.11) and her first "Send writing samples" file; older open steps: the 1.9 one (`docs/tablet-test-1.9.md`, 9 steps; the 1.8 ones in `docs/tablet-test-1.8.md` stay open where she has not answered them), the Pointer test report (Settings > Developer > Pointer test > Copy: does the M-Pencil send pressure at all?), a screenshot + Share diagnostics if PDF page thumbnails are still blank, her "Share my corrections" file. Start there when the owner brings them; if nothing has arrived, next step 5 (tests in CI) is a small, safe task.

## Next steps (suggested at the end of session 7; updated in sessions 8 to 14)

1. **Tablet test pass with Mariam on 1.13.0.** The checklist page the owner shares with her (https://claude.ai/artifact/FVxnATseRk6FUJcyePQRch, private until shared; read it with the Artifact tool's `read` action) holds the 9 steps of `docs/tablet-test-1.13.md`, then steps 2-11 of `docs/tablet-test-1.12.md` and 2-7 of `docs/tablet-test-1.11.md` (numbered on from 10 there) since session 14 (she had answered the 1.10 + 1.9 version: all worked apart from autocorrect and one-stroke arrows; step -> code tables in the checklist files; the 1.8, 1.7, 1.6 and 1.5 steps are in `docs/tablet-test-1.8.md` / `-1.7.md` / `-1.6.md` / `-1.5.md`; the step numbers in the notes below are the 1.6 ones). When the owner pastes her answers ("N. title: ✅ Works / ❌ Problem / ⏭️ Skipped" plus notes) and step 16's samples file:
   - fix every ❌ first, starting with data loss (backup/restore steps 3-5, scribble step 2 deleting too much), PDF export (14) and anything that crashes; ask for screenshots when a note is unclear;
   - step 2 (scribble) deleting writing or drawings it should not -> tune `ToolConfig.scribble*` (`scribbleMinContentWidth`/`Height`, `scribbleMinReversals` and the `scribbleShort*` tier) from her description, and ask whether she shades drawings;
   - steps 10-11 (sentence not joined / list joined by mistake) -> tune `ConvertConfig.join*` with her samples, not by guessing;
   - step 16's file -> recognition calibration (item 3 below);
   - after the fixes, release the next version (see "How to release" above) and give her only the steps that changed.
   Fix what she finds before adding features.
2. ~~Backup & restore~~: **built in session 8**, released in 1.6.0. Still remind the owner to back up the signing keystore (`~/Documents/MariamNotes-keystore/` on the PC): without it no update can install over the current app.
3. **Calibrate recognition on Mariam's real writing.** Since 1.7.0 every line she converts from the review sheet is kept, and since 1.11.0 Auto's lines too; "Send writing samples" (notebook ⋮ menu or Settings > Writing) shares them in one file (`kind: writing-samples`, format 2 without pictures, each line with `boxTextNow`/`boxGone`, plus `settings` and `problems`; render the pictures again with the desktop pipeline; see "Session 13" in `docs/session-history.md` for how to read it). Ask the owner for that file every week or two; lines with `corrected: false` were accepted as read (likely right, not certain). Measure CER/WER on 100+ lines (desktop pipeline in the Session 6 notes of `docs/session-history.md` and in `docs/htr-model-notes.md`), then tune `ConvertConfig.autoMinConfidence`, `lowConfidenceThreshold`, the decoder weights and the join thresholds (`ConvertConfig.join*`); fine-tune the 7.8 MB recogniser on her lines only if accuracy is still short.
4. ~~Local diagnostics~~: **built in session 9** (Settings > About > Share diagnostics). Read the file she sends before guessing at a device problem.
5. **Run the tests in CI.** `release.yml` runs `flutter analyze` but not `flutter test`; add the test step (with `--timeout`) before the build so a broken version cannot be published.
6. ~~Tips screen~~: **built in session 8**, released in 1.6.0.
7. Smaller: ~~PDF export drops the source PDF's bookmarks and form fields~~ (fixed in session 9, JVM-checked only). ~~White PDF thumbnails in the page grid~~ and ~~the size slider looking active with Even size~~: fixed in session 8.

## Owner decisions so far

- **Scope**: MVP + everything in "Expanded scope" above. Backup/restore was not chosen at first, then approved on 2026-10-28 (session 8), together with the Tips screen, PDF page thumbnails and the dimmed size slider (the owner picked these from the next-steps list). Scribble to delete (iPad style) was the owner's own request in session 8, with "build and release" right after. Session 9 (2026-10-29): from the list of what was still missing, the owner picked the error log + Share diagnostics, searching handwriting (moved out of "Later"), copy and paste, keeping the PDF's bookmarks and form fields, and "Keep my corrections", then "push, build and release". Audio recording was in the same list; asked again at the end of session 11, the owner chose not now, then asked for it in session 14. Session 10: the owner's and Mariam's test lists (fixed, see "Session 10" in `docs/session-history.md`). Session 11: Mariam's samples file plus her list (PDF margins, lasso Edit, arrows, punctuation, capitals), then "build and release the APK, push to GitHub". Session 14 (2026-10-30): lecture recording with both options (just play it back, or play it with the notes appearing as written, "understandable for non-tech people", the whole menu), a step-by-step guided tour of each section with the buttons highlighted, and tooltips on long press / pen hover; then "build and push to GitHub". Later in session 14: adding words in the middle of typed text (a button for the keyboard, and a bar to write into with the stylus), and a colour picker for the highlighter, pen and the rest; then "build and push to GitHub" with the earlier steps kept for Mariam.
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
