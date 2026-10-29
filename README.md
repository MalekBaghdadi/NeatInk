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
- Pen, pencil and fountain styles, highlighter, eraser (whole stroke or partial; it erases typed words too), lasso, shapes that snap straight when you hold the pen still.
- **Lasso** circles a word or a few letters of handwriting, or a phrase of typed text; selected typed text can be edited (Edit text) and restyled (font, size, bold, italic, underline, colour).
- **Scribble to delete**, like on an iPad: scribble back and forth over handwriting or typed text with the pen and it disappears (one undo brings it back). Scribbling on empty paper, or shading inside a drawn circle, stays ink. Switch it off in Settings.
- **Tidy highlighter**: a wobbly highlight over a line of writing, typed text or PDF text becomes a neat straight band over that line (switch it off in Settings; "Restore original" in the lasso menu brings the drawn one back).
- **Convert to text**: tap Convert and the app reads your handwriting a whole line at a time (on the tablet, nothing is uploaded), shows what it understood so you can fix any word, and retypes it on the lines in a font you choose (18 fonts: school-friendly, handwriting-style, serif, sans and more). Punctuation comes along (full stops, commas, colons, semicolons, question marks), and an arrow drawn between words becomes →. One undo gives your handwriting back.
- **Autocorrect**, like on an iPad: misspellings (swapped, missing or doubled letters: teh, recieve, finaly, happend), missing apostrophes (isnt → isn't), capitals and small grammar slips (a/an, "could of", "their is", repeated words) are fixed as handwriting becomes text. British and American spellings are both fine. Corrected words get a dotted underline: tap one and tap the bubble to get your word back (it is then learned, so it is not corrected again), or tick to keep it. Switch it off in Settings to only get suggestions in the review sheet. Names you taught it are never changed.
- **Check spelling**, like in Word: in typed text a red wavy line marks a word the app does not know, an amber one a word that may be a slip (wong for wrong). Tap it for spellings to choose from, or add the word to My words.
- **Auto-convert**: switch it on and your writing turns into text by itself a moment after you lift the pen (you choose how long, 1 to 10 seconds, so you can pause mid-sentence). A line it can't read stays handwriting, and a small note offers to review it. Writing more after the typed text carries on the same sentence, right beside it. A new line stays a new line, unless the sentence clearly goes on (it ran out of room, or ended on a comma or a word like "the").
- **Typed text settings** (the slider button next to Auto, or Settings > Typed text), open any time: font, bold/italic, colour and size. The size is **even** by default: every line the same size, chosen to sit on the page's lines; "Match my handwriting" and a custom size are there too. **Join lines into sentences** (on by default): a sentence that runs over to the next line becomes one line of text that wraps at the page edge.
- **Knows your subjects**: neuroscience, psychology, biology, physics and chemistry terms and acronyms (OCD, ADHD, GABA) are part of its word list.
- **My words**: teach it names (like family names); it also learns from the words you correct.
- Text boxes and pictures on any page. The page grid shows every page, PDF pages included.
- **Copy and paste** with the lasso: Copy or Cut, then tap an empty spot (on any page, in any notebook) and Paste. Copied typed text can be pasted into other apps too.
- Import a PDF, write on it, and export a new PDF with your writing on it. Add lined **margins** beside the PDF pages for notes (when importing, or later from the editor menu); typed notes stay in their margin, on its lines; exports keep them, the PDF's text stays selectable, and its bookmarks and form fields are kept.
- **Covers**: 16 colours, patterns, science pictures (brain, neuron, DNA, cell, atom, periodic table, planets, galaxy and more) or your own photo.
- Folders, tags, favourites, dark mode and an optional PIN lock.
- **Search** over titles, tags, folders, typed text, PDF text and **your handwriting**: the app reads a notebook's writing in the background while it is open and you pause (switch it off in Settings).
- **Trash**: deleted notebooks wait in the Trash (bottom of the side menu) for 30 days, to bring back or delete for good.
- **Backup & restore** (Settings > Backup): all notebooks, folders, settings and My words in one file you save wherever you like (Downloads, a USB stick, a PC). Restoring only adds: notebooks already on the tablet are left alone, changed ones come back as copies.
- **Tips** open once after installing or updating, and any time from Settings > About.
- **Writing samples**: lines typed from your handwriting (Convert or Auto) are kept on the tablet with what you changed afterwards, so recognition can be improved for your writing; ⋮ › Send writing samples (or Settings › Writing) shares them in one file when you choose.
- **Share diagnostics** (Settings > About): problems the app ran into are kept on the tablet, to send when something goes wrong.

## Private by design

It works fully offline. The app has no internet permission, no accounts, no
tracking and no ads. Your notebooks, writing samples and diagnostics leave the
tablet only when you export, back up or share them yourself.

## For developers

- Flutter (Android only), Dart 3, Riverpod. Project brief and status: [CLAUDE.md](CLAUDE.md); the removed auto-tidy algorithm (kept for reference): [docs/beautify-spec.md](docs/beautify-spec.md).
- `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build apk --release`.
- Release signing reads `android/key.properties` (git-ignored). Without it, release builds use the debug key.
- Pushing a tag like `v1.0.0` builds and publishes the signed APKs through `.github/workflows/release.yml`.
