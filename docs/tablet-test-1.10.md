# Tablet test run for v1.10.0

Fixes for the owner's 1.9.0 test (session 12): autocorrect bubbles could not
be tapped, arrows were found 2 times of 8, and with Auto on new lines joined
the line above after a few lines of notes. Only these changed; the 1.9 steps
still open are in `docs/tablet-test-1.9.md`. Report each step as
"N. title: ✅ Works / ❌ Problem / ⏭️ Skipped" plus a note.

## The steps

1. **Get the new version.** Install `releases/latest/download/MariamsNotes.apk`
   over the old app. Expect "Version 1.10.0" at the bottom of Settings.
2. **Tap an autocorrected word.** With Autocorrect on, convert a line with a
   misspelt word (write "Nuerons are cells"). Tap the underlined word, then
   tap the bubble with the **pen**: expect your written word back. Do it
   again and tap the tick: the correction stays and the underline goes.
   Repeat both with a **finger**. Nothing is drawn where you tapped.
3. **Pick a spelling.** With Check spelling on, tap a word with a red wavy
   underline and tap one of the spellings (pen, then finger). Expect the word
   replaced; "Add to My words" works too.
4. **A page of notes with Auto on.** Fill most of a page with notes the way
   you normally write them: headings, short lines, lines starting in
   lowercase, no full stops. Expect every line you start on a new line to
   stay its own line, also near the bottom of the page.
5. **A sentence that does go on.** With Auto on, write a sentence that
   reaches the right edge of the page and finish it on the next line
   (starting in lowercase). Then one that ends with "the", "and" or a comma
   before the line break. Expect each to become one sentence.
6. **Arrows.** Write "brain → spinal cord" 8 times, drawing the arrow
   differently each time: one stroke, the head as its own stroke, the two
   barbs as two strokes, short and long, big and small heads, the next word
   close to the tip. Convert. Expect → each time. Note any that fail (a
   screenshot of the handwriting before converting helps). If you saw the
   shaft straighten by itself before you drew the head, say so.
7. **No false arrows.** Write a few lines with "the", "it", "E", "+", "="
   and a dash ("brain - cord"). Expect no → anywhere.
8. **Share samples** of a page with arrows (Convert sheet > Share samples),
   if any arrow failed.

## Where each step lives in the code

| Step | Code to look at first |
|---|---|
| 2-3 bubble taps | `canvas/overlay_hit_area.dart`, `canvas/input_router.dart` (`claimForOverlay`), `canvas/document_view.dart` (`_onPointerDown`), `integrations/autocorrect/autocorrect_integration.dart` |
| 4-5 joining | `integrations/convert/convert_layout.dart` (`continuesOnNextLine`, `sentenceWraps`, `textCarriesOn`), `auto_convert_merge.dart` (`planMerge`, `dropBelow`), `ConvertConfig.join*` |
| 6-8 arrows | `recognition/arrows.dart` (`findArrows`, `ArrowConfig`, `typedArrows`), `htr_channel.dart` (`_withoutArrows`, `_lineResult`), `stroke_grouping.dart` (`_levelArrow`) |
