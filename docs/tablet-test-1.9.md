# Tablet test run for v1.9.0 (for Mariam)

Same format as before: the owner shares the checklist page
(https://claude.ai/artifact/FVxnATseRk6FUJcyePQRch, updated in place for 1.9
in session 11, so her link stays the same). Mariam uses a notebook called
"Test", taps Works / Problem / Skip per step with an optional note,
screenshots anything strange, and pastes the "Copy my answers" text into a
message. If she had not finished the 1.8 checklist, its steps are still in
`docs/tablet-test-1.8.md`; this page holds only what changed in 1.9 plus the
few 1.8 steps that matter most (backup, Trash, pressure report).

## The steps

1. **Get the new version.** Install `releases/latest/download/MariamsNotes.apk`
   over the old app. Expect "Version 1.9.0" at the bottom of Settings.
2. **Notes beside a PDF.** In a PDF notebook with margins, write a sentence
   in the left margin, long enough to need two lines, and convert it.
   Expect the typed text to stay in the margin (wrapping before the PDF),
   sitting on the margin's lines; same in the right margin. The line between
   the margin and the PDF is now clearly visible.
3. **Edit typed text.** Lasso some typed text: the menu has Edit text.
   Tap it, change a word with the keyboard, tap outside. Expect the change.
4. **Arrows.** Write "brain → spinal cord" (draw the arrow with the pen;
   also try holding the pen at the end so it snaps into a neat arrow) and
   convert. Expect "brain → spinal cord". A drawn arrow on its own (a
   diagram) stays a drawing.
5. **Punctuation.** Write a line with a colon, a semicolon, a question mark
   and commas ("Note: the cortex; the cerebellum, the brainstem?") and
   convert. Then, with Auto on, write a word, wait for it to be typed, and
   add ":" or "?" right after it. Expect the marks in the text, with no
   space before "?" or ":".
6. **Carrying on a sentence.** With Auto on, write half a sentence, wait for
   it to be typed, then carry on on the same line, and on the next line.
   Expect no capital letter on the first word you add.
7. **Autocorrect on unclear words.** Convert a few lines of normal notes.
   Expect fewer odd "corrections" (a word turned into a different real
   word); unclear words get the red underline instead, with spellings to
   pick.
8. **Back up, Trash and the pen report** (1.8 steps 2, 3 and 6, if not done
   yet): back up to Download; delete a notebook and bring it back from the
   Trash; Settings > Developer > Pointer test > Copy, paste into a message.
9. **Share my corrections.** After converting some pages with the Convert
   button, Settings > Writing > Share my corrections, send the file.

## Where each step lives in the code

| Step | Code to look at first |
|---|---|
| 2 margins | `integrations/convert/convert_layout.dart` (`TextColumn`, `textColumnAt`, `ranToColumnEdge`), `convert_build.dart`, `auto_convert_merge.dart` (`column`), `render/paper_painter.dart` (`pdfMarginEdgeColor`) |
| 3 edit | `erase_select/selection_menu.dart` (`_editText`), `EditorExtensions.editText`, `text_images_integration.dart` |
| 4 arrows | `recognition/arrows.dart` (`findArrows`, `ArrowConfig`), `htr_channel.dart` (`_withoutArrows`), `stroke_grouping.dart` (`_levelArrow`), `auto_convert_session.dart` |
| 5 punctuation | `recognition/word_image.dart` (`_snapDots`, `colonAlignFactor`), `auto_convert_dots.dart` (`_colonOf`), `auto_convert_merge.dart` (closing marks), `line_decoder.dart` (`_tokenPrior`) |
| 6 capitals | `convert_plan.dart` (`textBeforeLine`) |
| 7 autocorrect | `htr_channel.dart` (`weighSuggestions`), `text_polish.dart` (`PolishConfig.sureWordConfidence`, `PolishSuggestion.auto`) |
| 8-9 | see `docs/tablet-test-1.8.md` |
