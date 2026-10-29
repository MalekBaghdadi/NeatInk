# Tablet test run for v1.8.0 (for Mariam)

Same format as before: the owner shares the checklist page
(https://claude.ai/artifact/FVxnATseRk6FUJcyePQRch, updated in place for 1.8
in session 10, so her link stays the same). Mariam uses a notebook called
"Test", taps Works / Problem / Skip per step with an optional note,
screenshots anything strange, and pastes the "Copy my answers" text into a
message. It holds what changed in 1.8, the 1.6 steps she marked as a problem
(backup, restore, PDF pages, pressure, full stop) and three 1.7 steps she has
not answered yet (copy and paste, search handwriting, share corrections).

## The steps

1. **Get the new version.** Install `releases/latest/download/MariamsNotes.apk`
   over the old app. Expect "Version 1.8.0" at the bottom of Settings and all
   notebooks there.
2. **Back up** (was a problem). Settings > Back up all notebooks, save to
   Download. Expect a progress dialog, the system Save dialog, then "Last
   backup: just now". Note how long it took and the file size.
3. **Trash** (new, her request). Delete the "Test" notebook: it says it moves
   to the Trash; tap Undo in the message at the bottom: it is back. Delete it
   again, open the side menu (or the left panel), Trash at the bottom: it is
   there with "30 days left"; Bring back.
4. **Restore from the backup** (was a problem). Delete a notebook, then in
   the Trash "Delete for good". Settings > Restore from a backup, pick the
   file from step 2: the summary offers that notebook; Restore. Expect it
   back with its pages and pictures.
5. **Pages of a PDF notebook** (was a problem). In a PDF notebook, open Pages
   (the grid). Expect the PDF pages in the thumbnails, under the writing. If
   not: a screenshot, then Settings > About > Share diagnostics.
6. **Pen pressure** (was a problem). Settings > Developer > Pointer test:
   write lightly, then press hard, tap Copy and paste the report into the
   message to Malek. (Her M-Pencil has no eraser end: that is the pen, not
   the app.)
7. **Full stop after typed text** (was a problem). With Auto on, write a
   sentence, wait for it to be typed, then write a full stop right after the
   last word. Expect the full stop in the typed text and no dot left over.
8. **Lasso.** Circle one handwritten word, then just two or three letters:
   each is selected. Circle a phrase of typed text: Text style changes its
   font, size, bold, italic and underline; Colour its colour.
9. **Eraser on typed text.** Rub the eraser over a typed word: it goes; Undo
   brings it back.
10. **Scribble.** Scribble over a written word, also a short, tall scribble
    (up and down): it goes. Writing an "A", "M" or "W" stays writing.
11. **Check spelling** (new). Convert a line with a misspelt word (write
    "sensoy" or "wong"). Expect a red (or amber) wavy line under it; tap it:
    spellings to choose; one tap fixes it. On a word you know is right, the
    bookmark button adds it to My words and the line goes.
12. **Sentences over several lines** (Auto on). Write a sentence over two or
    three lines, pausing at the end of each line (for example "I wrote this
    so I can / test my app"). Expect one box, the second line not given a
    capital and not placed somewhere else.
13. **Names.** Write "Mariam Baghdadi". Expect it typed right without adding
    it to My words.
14. **Copy and paste** (1.7). Lasso some writing, Copy; lasso-tap an empty
    spot, Paste. Cut something, open another notebook, More > Paste. Expect
    the copy where she tapped, and Undo removing a paste.
15. **Search handwriting** (1.7). Leave a notebook with (not converted)
    writing open for about 10 seconds, go back, search a word from it.
    Expect a "Handwriting" result that opens the right page.
16. **Share my corrections** (1.7). After converting a few pages with the
    Convert button (fixing words in the sheet), Settings > Writing > Share my
    corrections, send the file to Malek. This is what recognition gets
    better from: please send one every week or two.

## Where each step lives in the code

| Step | Code to look at first |
|---|---|
| 2, 4 backup | `features/settings/backup_service.dart` (`runWithProgress`), `storage/backup/notebook_backup.dart`, `FileSavePlugin.kt` |
| 3 trash | `storage/file_notebook_repository.dart` (`trashNotebook`...), `features/library/trash_screen.dart`, `library_controller.dart` (`moveToTrash`, `trashKeep`) |
| 5 PDF pages | `integrations/pdf/` (`pageThumbnailBackgroundBuilder`), `PageThumbnail` |
| 6 pressure | `canvas/input_router.dart` (`normalizePressure`), `features/debug/pointer_debug_log.dart` (`report`) |
| 7 full stop | `integrations/convert/auto_convert_dots.dart` (`_markOf`) |
| 8 lasso | `tools/lasso.dart` (`lassoStroke*Fraction`, word boxes), `erase_select/selection_menu.dart`, `lasso_handler.dart` (`restyleTexts`) |
| 9 eraser | `tools/text_eraser.dart`, `erase_select/eraser_handler.dart` |
| 10 scribble | `tools/scribble.dart` (`scribbleShapeOf`, `ToolConfig.scribble*`) |
| 11 spelling | `recognition/spell_check.dart`, `text_polish.dart` (`isKnownSpelling`, `spellingSuggestions`, `suspectsFor`), `integrations/autocorrect/`, `text_images/text_layer.dart` |
| 12 joining | `integrations/convert/convert_plan.dart` (`textBeforeLine`), `auto_convert_merge.dart` |
| 13 names | `docs/htr_bench/make_subject_words.py` (`NAMES`) |
| 14-16 | see `docs/tablet-test-1.7.md` |
