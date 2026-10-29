# Tablet test run for v1.7.0 (for Mariam)

Same format as before: the owner shares the checklist page
(https://claude.ai/artifact/FVxnATseRk6FUJcyePQRch, updated in place for 1.7
in session 9, so her link stays the same). Mariam uses a notebook called
"Test", taps Works / Problem / Skip per step with an optional note,
screenshots anything strange, and pastes the "Copy my answers" text into a
message. If she had not finished the 1.6 checklist, its unanswered steps that
are still relevant are folded in below (scribble, backup, pressure).

## The steps

1. **Get the new version.** Install `releases/latest/download/MariamsNotes.apk`
   over the old app. Expect "Version 1.7.0" at the bottom of Settings, all
   notebooks there, and the tips list (Settings > About > Tips) showing
   "Search your handwriting" and "Copy and paste".
2. **Copy and paste.** Select some writing with the lasso, tap Copy. Tap an
   empty spot with the lasso: a Paste bubble appears; tap it. Then Cut
   something, open another notebook, More (three dots) > Paste. Expect the
   copy where she tapped (selected, ready to move), Cut removing it, and the
   paste in the other notebook, pictures included. Undo removes a paste.
3. **Copy typed text to another app.** Select a typed text box, Copy, open
   another app (WhatsApp, Notes) and paste. Expect the text.
4. **Search handwriting.** Open a notebook with handwriting (not converted),
   leave it alone for about 10 seconds, go back, search a word she wrote.
   Expect a "Handwriting" result that opens the right page. Note how long it
   took and whether the app felt slow while it was open.
5. **Keep my corrections.** Convert a few lines with the Convert button, fix
   a word, convert. Settings > Writing: "Share my corrections" says how many
   lines are kept; tap it and send the file to Malek (this is the samples
   file for improving recognition: the more pages over the next weeks, the
   better).
6. **Share diagnostics.** Settings > About > Share diagnostics: the share
   sheet opens with a text file; send it to Malek (even if nothing went
   wrong, it says "None recorded").
7. **PDF bookmarks and forms.** Import a PDF that has bookmarks (a lecture
   handout or a book chapter; a form if she has one), write on it, Export
   PDF, open the export in another app. Expect the bookmarks list to work
   and form fields to keep what was typed in them.
8. **Scribble to delete** (new in 1.6). Scribble back and forth over a
   written word: it disappears, Undo brings it back; over empty paper or
   inside a drawn circle it stays ink.
9. **Back up and restore** (new in 1.6). Settings > Back up all notebooks,
   save to Download; Restore from that file: nothing to add; note the time
   and file size.
10. **Pen pressure and palm** (1.6 step 8). Writing with the hand on the
    screen keeps the page still; pressing harder makes thicker lines. If
    not, send the Pointer test pressure numbers (Settings > Developer).

## Where each step lives in the code

| Step | Code to look at first |
|---|---|
| 2-3 copy/paste | `integrations/erase_select/clipboard.dart`, `lasso_handler.dart` (`copySelected`, `cutSelected`, `pasteAt`), `paste_bubble.dart`, `selection_menu.dart`, `EditorExtensions.paste` |
| 4 search | `integrations/search_index/handwriting_indexer.dart`, `storage/search_data.dart` (`ink`, `inkKey`), `storage/search_engine.dart` |
| 5 corrections | `integrations/convert/kept_corrections.dart`, `settings/widgets/kept_corrections_settings.dart` |
| 6 diagnostics | `app/diagnostics.dart`, `settings/widgets/diagnostics_tile.dart`, `app/bootstrap.dart` |
| 7 PDF | `android/.../PdfStructure.kt`, `docs/pdf_structure_check/` |
| 8-10 | see `docs/tablet-test-1.6.md` |
