# Mariam's Notes

A handwriting notes app for Android tablets, made for Mariam. Write with a
stylus, and when you want it neat, the app reads your handwriting and retypes
it on the lines in a font you choose.

(The project and repository are called NeatInk; the app on the tablet is
**Mariam's Notes**.)

## Download

**[Download Mariam's Notes (APK)](https://github.com/MalekBaghdadi/NeatInk/releases/latest/download/MariamsNotes.apk)**

1. Open the link on the tablet and download the file (about 43 MB).
2. Open it. Android asks to allow installs from your browser or Files app; allow it.
3. Install. Updates install over the old version and keep your notebooks.

The link is the 64-bit build, which suits almost every tablet made in the last
decade. If Android says the app isn't compatible, take
`MariamsNotes-armeabi-v7a.apk` (32-bit) from the
[Releases page](https://github.com/MalekBaghdadi/NeatInk/releases/latest).
`SHA256SUMS.txt` there lets you check that a download is complete.

If the download keeps failing on a slow connection, download the file on a PC
and copy it to the tablet.

## What it does

- Notebooks with blank, lined, grid, dotted, Cornell and music pages, in white, cream or dark.
- Pen, pencil and fountain styles, highlighter, eraser (whole stroke or partial), lasso, shapes that snap straight when you hold the pen still.
- **Convert to text**: tap Convert and the app reads your handwriting a whole line at a time (on the tablet, nothing is uploaded), shows what it understood so you can fix any word, and retypes it on the lines in a font you choose (18 fonts: school-friendly, handwriting-style, serif, sans and more). One undo gives your handwriting back.
- **Spelling suggestions**: misspellings, missing apostrophes (isnt → isn't) and capitals are suggested in the review sheet; tap to accept, or switch on "Fix spelling automatically". Names you taught it are never changed.
- **Auto-convert**: switch it on and your writing turns into text by itself about a second after you lift the pen.
- **My words**: teach it names (like family names); it also learns from the words you correct.
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
