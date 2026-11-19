# Tablet test run for v1.14.0

New in this version (session 15): a **Get the newest version** button,
**highlight shapes** (square, round, slanted), and **arrow finding that no
longer takes her letters for arrows** (from her writing samples). The 1.13.1
steps (`docs/tablet-test-1.13.1.md`: the keyboard staying up) and the older
open checklists stay open. Report each step as "N. title: ✅ Works /
❌ Problem / ⏭️ Skipped" plus a note.

## The steps

1. **Get the new version.** Install `releases/latest/download/MariamsNotes.apk`
   over the old app (this one time by hand). Expect "Version 1.14.0" at the
   bottom of Settings.
2. **The update button.** Settings › About › Get the newest version ›
   Download. Expect the browser to open and download the app (about 43 MB);
   tapping the file offers to update. (It downloads the same version now:
   that is fine, cancel the install.)
3. **Round highlights.** Highlighter: tap the first button in its row ›
   Round ends. Highlight a line of typed text and a line of handwriting.
   Expect pills with half-circle ends over the words; Slanted ends: ends cut
   like a marker tip; Square ends: as before. Old highlights stay as they
   were.
4. **Highlights in the PDF.** Export a page with round and slanted
   highlights as PDF. Expect the same shapes in the PDF.
5. **No more false arrows.** With Auto on, write words with a long e-tail or
   long t-bars ("increase", "Compare", "with", "time", "mortality",
   "develop"). Expect no ← or → in the typed text and the whole word typed.
6. **Real arrows still work.** Write a long arrow "⟶" (one stroke, line then
   head) before a word, like "→ higher". Expect → in the typed text.
7. **Send writing samples again** in a week or two (notebook ⋮ › Send writing
   samples), after writing with this version.

## Where each step lives in the code

| Step | Code to look at first |
|---|---|
| 2 update button | `features/settings/widgets/update_tile.dart` (`linkOpenerProvider`, `AppInfo.downloadUrl`) |
| 3-4 highlight ends | `render/stroke_outline.dart` (`_slantedOutline`, `slantedEndAngleDeg`), `ink/stroke.dart` (`HighlightEnds`), `toolbar/tool_options.dart` (`HighlightEndsMenu`), `tools/highlight_tidy.dart` (`roundInset`) |
| 5-6 arrows | `recognition/arrows.dart` (`ArrowConfig`: `tailSlack`, `tailFlat`, `tailShare`, `headShare`, `crossSlack`, `leftHeadShare`, `leftCrossSlack`, `oneStrokeMinLength`); `test/recognition/sample_arrows_test.dart` on a samples file |
