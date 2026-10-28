# Tablet test run for v1.6.0 (for Mariam)

Same format as the 1.5 run (`docs/tablet-test-1.5.md`): the owner shares the
checklist page with Mariam (the 1.5 page,
https://claude.ai/artifact/FVxnATseRk6FUJcyePQRch, was updated in place for
1.6 in session 8, so the link she has stays the same). She uses a notebook
called "Test", taps Works / Problem / Skip per step with an optional note,
screenshots anything strange (Power + Volume down), and pastes the "Copy my
answers" text into a message:

```
Mariam's Notes 1.6 test
1. Get the new version: ✅ Works
2. Scribble to delete: ❌ Problem
   it deleted the circle I was shading
...
```

## The steps

Each step: what she does, then what should happen.

1. **Get the new version.** Open `releases/latest/download/MariamsNotes.apk`
   on the tablet and install it over the old app. Expect the Tips to open
   once (Got it closes them, they do not come back on the next start;
   Settings > About > Tips opens them), "Version 1.6.0" at the bottom of
   Settings, all notebooks still there.
2. **Scribble to delete** (new). In "Test", write a few words, then scribble
   quickly back and forth over one word with the pen. Expect the word gone
   (the scribble too); Undo brings it back. Same over typed text: only the
   words under the scribble go. Scribble on empty paper, and shade inside a
   circle you drew: those stay as ink. Settings > Writing > Scribble to
   delete off: a scribble stays ink.
3. **Back up.** Settings > Back up all notebooks. Expect a progress dialog,
   then the Save dialog; save to Download. Her note: how long it took and
   the file size. "Last backup: just now" appears under the button.
4. **Restore.** Settings > Restore from a backup, pick that file. Expect
   "already on this tablet" for everything and Restore greyed out. Edit
   "Test", restore again: it comes back as "Test (from backup)" and the
   edited one is untouched.
5. **Restore a deleted notebook.** Delete a test notebook (one with a
   picture or a PDF), restore: it comes back in its folder with its pages,
   pictures and PDF.
6. **Pages of a PDF notebook.** Open a PDF notebook, tap Pages. Expect the
   thumbnails to show the PDF pages under the writing (they were white).
7. **Typed text size slider.** Typed text sheet: the size slider is faint
   with Even size and Match my handwriting, bright with Custom.
8. **Hand on the screen, pen pressure** (1.5 step 2 again). Write with the
   hand resting on the screen and move to the next line: the page stays
   still. Press harder: the line gets thicker. If not: Settings > Developer
   > Pointer test, write lightly then firmly, and send the `pressure`
   numbers.
9. **Auto on the same line** (1.5 step 5 again). Auto on, write a few words,
   wait for the text, carry on on the same line: one box, no gap.
10. **A sentence over two or three lines.** Auto on, a sentence that stops
    before the page edge, also with a line skipped between: one box, the
    same size throughout, wrapped lines on the ruled lines, nothing
    overlapping.
11. **A short list.** One word per line (brain / neurons / synapse): stays a
    list.
12. **Autocorrect.** Write "nuerons", "joming", "itworked", "I a not":
    fixed and underlined; tap to get her word back.
13. **Late dots.** Write a word with an i or t, wait for it to be typed,
    then dot the i / cross the t / add a full stop: no stray marks, the full
    stop appears in the text.
14. **Saving the slides as a PDF** (1.5 step 13, her answer was cut off).
    Menu > Export PDF > Save to device; open it in another app; select some
    slide text. Expect writing, lined margins and slides in place.
15. **A long notebook** (1.5 step 14). Scroll 30+ pages: smooth, no long
    freezes.
16. **Help the app learn her handwriting** (1.5 step 15). A page of normal
    notes, Convert, fix every line to exactly what she wrote, "Share samples
    for improving recognition" before converting, send the file.

## Where each step lives in the code

| Step | Code to look at first |
|---|---|
| 1 tips | `features/tips/` (`TipsOnce`, `appTips`), `AppSettings.tipsSeen` |
| 2 scribble | `tools/scribble.dart` (`isScribbleShape`, `planScribble`, `ToolConfig.scribble*`), `integrations/scribble/`, `EditorExtensions.strokeGestures` in `canvas/ink_tool_handler.dart` |
| 3-5 backup | `storage/backup/`, `settings/backup_service.dart`, `settings/widgets/backup_settings.dart`, `android/.../FileSavePlugin.kt` |
| 6 PDF thumbnails | `integrations/pages/page_thumbnail.dart`, `integrations/pdf/pdf_background.dart` |
| 7 slider | `integrations/convert/convert_style_controls.dart` |
| 8 palm, pressure | `canvas/input_router.dart`, `canvas/document_view.dart`, `render/stroke_outline.dart` |
| 9-11 Auto, joining | `auto_convert_session.dart`, `auto_convert_merge.dart` (`planMerge`), `convert_layout.dart` (`continuesOnNextLine`), `convert_overlap.dart`, `ConvertConfig.join*` / `merge*` |
| 12 autocorrect | `recognition/text_polish.dart`, `recognition/lexicon.dart` (`handwritingDistance`) |
| 13 late dots | `integrations/convert/auto_convert_dots.dart` |
| 14-16 | see `docs/tablet-test-1.5.md` |
