# Tablet test run for v1.5.0 (for Mariam)

The owner sends Mariam a checklist page made in session 7:
https://claude.ai/artifact/FVxnATseRk6FUJcyePQRch (private to the owner until
shared from the page's Share menu; a Claude session can read it with the
Artifact tool's `read` action). This file holds the same 15 steps, so the
test can be followed up without the page.

She uses a new notebook called "Test" so her real notes stay safe, taps
Works / Problem / Skip per step with an optional note, and screenshots
anything strange (Power + Volume down).

## What she sends back

The page's "Copy my answers" button gives text like this, which she pastes
into a message to the owner:

```
Mariam's Notes 1.5 test
1. Get the new version: ✅ Works
4. The Convert button: ❌ Problem
   3 words wrong out of 20, "neurons" became "nerves"
7. A short list: ⏭️ Skipped
...
```

Each line is `<step>. <title>: ✅ Works | ❌ Problem | ⏭️ Skipped | not done`,
with her note on the next line when she wrote one. Step 15 also comes with a
samples file (`mariams-notes-samples-*.json`, format 2).

## The 15 steps

Each step: what she does, then what should happen.

1. **Get the new version.** Open `releases/latest/download/MariamsNotes.apk`
   on the tablet, install it over the old app (allow installs from the
   browser if asked). Settings (gear on the home screen), bottom of the list:
   "Version 1.5.0", and all notebooks still there.
2. **Writing with the pen.** New notebook "Test", lined paper; write a
   sentence; press hard then softly; rest the hand on the screen while
   writing; scroll with one finger, zoom with two. Expect smooth writing,
   thicker lines with more pressure, no stray marks from the hand.
3. **Your writing is saved.** Write, swipe the app away from recent apps,
   reopen. Expect the writing still there.
4. **The Convert button.** Write 2-3 lines, tap Convert, fix wrong words in
   the list, tap "Convert … lines", then Undo. Expect typed text on the
   lines and Undo bringing the handwriting back. Her note: roughly how many
   words were wrong.
5. **Auto.** Turn Auto on, write a short sentence and stop, then keep
   writing on the same line after the typed text. Expect typed text ~2 s
   after stopping, and the addition joining the same sentence without a gap.
6. **A long sentence over two lines.** With Auto on, write one sentence
   that carries on to the next line; again with bigger and smaller
   handwriting. Expect one typed sentence (may wrap at the page edge), all
   typed text the same size, sitting on the lines.
7. **A short list.** With Auto on, one word per line, no full stops (brain,
   neurons, synapse). Expect each word on its own line, NOT joined.
8. **Autocorrect.** Write "nuerons" or "isnt"; tap the corrected word, tap
   the word in the bubble; on another corrected word tap the tick. Expect a
   dotted blue underline, the bubble bringing back her word, the tick
   keeping the correction and removing the underline.
9. **Typed text settings.** Sliders button next to Auto (also on an empty
   page); change font or colour, write again; look at "Join lines into
   sentences" and the size choices. Expect a live preview and new text in
   the chosen look.
10. **Highlighter.** Highlight a line messily. Expect a neat straight band.
11. **Notebook covers.** Home screen, three dots on a notebook, Cover…,
    pick a science picture, "Use this cover"; also "Choose a picture…" with
    a photo. Expect the new cover on the home screen.
12. **Writing beside lecture slides.** Import PDF, choose Narrow margins,
    Import; write in the margins and on a slide; menu > PDF margins… > Wide,
    then Undo. Expect lined space on both sides and notes staying with
    their slide.
13. **Saving the slides as a PDF.** Menu > Export PDF > Save to device;
    open it in another app (Files, WPS); select some slide text. Expect
    writing, lined margins and slides in place, and selectable slide text.
14. **A long notebook.** Scroll 30+ pages. Expect smooth scrolling, no long
    freezes.
15. **Help the app learn her handwriting** (most useful). Write a whole page
    of normal notes, Convert, fix every line to exactly what she wrote (own
    spelling kept; Undo any "Fixed: … · Undo" chip), then at the bottom of
    the list tap "Share samples for improving recognition" BEFORE
    converting, and send the file.

## Where each step lives in the code

| Step | Code to look at first |
|---|---|
| 2 pressure, palm | `canvas/input_router.dart`, `canvas/document_view.dart`, settings "Draw with finger" |
| 3 saving | `storage/autosave.dart`, `editor_controller.dart` (flush on pause) |
| 4 Convert | `integrations/convert/convert_sheet.dart`, `convert_session.dart`, `lib/recognition/` |
| 5-7 Auto, joining, lists | `auto_convert_session.dart`, `auto_convert_merge.dart`, `convert_layout.dart` (`continuesOnNextLine`, `ConvertConfig.join*`) |
| 6 sizes | `convert_layout.dart` (`evenFontSize`, `ConvertConfig.evenSizeOfRuling`) |
| 8 autocorrect | `integrations/autocorrect/`, `recognition/text_polish.dart`, `TextItem.corrections` |
| 9 typed text sheet | `convert_style_sheet.dart`, `convert_style_controls.dart`, `settings/convert_style_prefs.dart` |
| 10 highlighter | `tools/highlight_tidy.dart`, `integrations/highlight/` |
| 11 covers | `library/dialogs/cover_picker.dart`, `render/cover_painter.dart` |
| 12-13 PDF margins/export | `document/pdf_margins.dart`, `integrations/pdf/`, `pdf/export_builder.dart`, `android/.../PdfMargins.kt`, `PdfExportPlugin.kt` |
| 14 speed | `canvas/page_view.dart`, `pdf/pdf_page_cache.dart` |
| 15 samples | `sample_export.dart`, desktop pipeline in `docs/htr-model-notes.md` |
