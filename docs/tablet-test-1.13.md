# Tablet test run for v1.13.0

New in this version (session 14, part 2): **add words in the middle of typed
text** (with the pen, in a writing bar, or with the keyboard), and **any
colour** for the pen, the highlighter and typed text. Mariam had not tested
1.12 and 1.11 yet, so the checklist page holds these steps first, then the
1.12 steps (`docs/tablet-test-1.12.md`, step 1 replaced by this one) and the
1.11 steps (`docs/tablet-test-1.11.md`, without its step 1). Report each
step as "N. title: ✅ Works / ❌ Problem / ⏭️ Skipped" plus a note.

## The steps

1. **Get the new version.** Install `releases/latest/download/MariamsNotes.apk`
   over the old app. Expect "Version 1.13.0" at the bottom of Settings
   (the tours start by themselves first: they are steps 2-3 of 1.12).
2. **Add a word in the middle of a typed sentence.** Lasso a typed
   sentence, tap the pencil (Edit text with the pen). Tap in the text just
   where a word is missing, then write the word in the bar at the bottom.
   Expect it in the sentence right there, with spaces around it, after a
   moment, and "Added “word”" with Take back.
3. **Replace a wrong word.** In the same edit, tap a wrong word twice
   (it gets selected), then write the right word in the bar. Expect the
   wrong word replaced.
4. **The small buttons.** Use ◀ ▶ to move the cursor a letter, Space, and
   ⌫ to delete a letter. Then Done: expect the sentence saved, and Undo
   (top) to take the whole edit back in one go.
5. **With the keyboard.** Lasso typed text, tap the keyboard button (Edit
   text with the keyboard). Expect the keyboard; type a word in the middle.
   "Write with the pen" in the bar goes back to the writing bar.
6. **Any pen colour.** Pen: tap the rainbow circle after the colours. Tap
   one of the ready colours, Use colour, and write. Then mix your own in
   the big square and the rainbow bar. Expect the pen in those colours, and
   the colour you mixed under Recent next time.
7. **Any highlighter colour.** Highlighter: same rainbow circle. Expect
   the highlight see-through in the colour you chose.
8. **Typed text colour.** The slider button next to Auto (Typed text
   settings) › Colour › rainbow circle. Expect converted text in that colour.
9. **Portrait.** Turn the tablet upright with the pen chosen. Expect the
   colours, the rainbow circle and the thickness dots all visible on the
   second row, without sliding it.

## Where each step lives in the code

| Step | Code to look at first |
|---|---|
| 2-5 editing typed text | `integrations/text_images/text_write_bar.dart` (`TextWriteBar`, `insertWritten`, `WriteBarConfig.readAfter`), `text_editor.dart` (`TextEditSession.keyboard`, `useKeyboard`, `returnTool`), `text_overlay.dart` (`readOnly`), `erase_select/selection_menu.dart` (`selection-edit`, `selection-edit-keyboard`), `convert/convert_integration.dart` (`readHandwriting`) |
| 6-8 colours | `toolbar/color_picker_dialog.dart` (`pickerPalette`), `toolbar/tool_options.dart` (`pickCustomPenColor`, `pickCustomHighlighterColor`), `convert/convert_style_controls.dart` (`convert-colour-custom`) |
| 9 portrait | `toolbar/editor_tool_row.dart` (`twoRowBreakpoint` 1000) |
