# Mariam's Notes

A handwriting notes app for Android tablets, made for Mariam. Write with a
stylus, and the app gently tidies each word a moment after you finish it:
it straightens the line, evens out size and spacing, and keeps it your own
handwriting.

(The project and repository are called NeatInk; the app on the tablet is
**Mariam's Notes**.)

## Download

**[Download Mariam's Notes (APK)](https://github.com/MalekBaghdadi/NeatInk/releases/latest/download/MariamsNotes.apk)**

1. Open the link on the tablet and download the file.
2. Open it. Android asks to allow installs from your browser or Files app; allow it.
3. Install. Updates install over the old version and keep your notebooks.

Smaller downloads for specific tablets are on the
[Releases page](https://github.com/MalekBaghdadi/NeatInk/releases/latest)
(`arm64-v8a` suits almost every modern tablet).

## What it does

- Notebooks with blank, lined, grid, dotted, Cornell and music pages, in white, cream or dark.
- Pen, pencil and fountain styles, highlighter, eraser (whole stroke or partial), lasso, shapes that snap straight when you hold the pen still.
- **Convert to text**: tap Convert and the app reads your handwriting (on the tablet, nothing is uploaded), shows what it understood so you can fix any word, and retypes it on the lines in a font you choose (18 fonts: school-friendly, handwriting-style, serif, sans and more). One undo gives your handwriting back.
- Text boxes and pictures on any page.
- Import a PDF, write on it, and export a new PDF with your writing on it.
- Folders, tags, favourites, search, dark mode and an optional PIN lock.

## Private by design

It works fully offline. The app has no internet permission, no accounts, no
tracking and no ads. Your notebooks never leave the tablet.

## For developers

- Flutter (Android only), Dart 3, Riverpod. Project brief and status: [CLAUDE.md](CLAUDE.md); the removed auto-tidy algorithm (kept for reference): [docs/beautify-spec.md](docs/beautify-spec.md).
- `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build apk --release`.
- Release signing reads `android/key.properties` (git-ignored). Without it, release builds use the debug key.
- Pushing a tag like `v1.0.0` builds and publishes the signed APKs through `.github/workflows/release.yml`.
