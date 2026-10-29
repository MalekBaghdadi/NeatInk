# Tablet test run for v1.11.0

Fixes for Mariam's 1.10 answers (session 13): autocorrect missed most wrong
words, one-stroke arrows were found only sometimes, and sharing data had to
be one tap. Only these changed; report each step as
"N. title: ✅ Works / ❌ Problem / ⏭️ Skipped" plus a note.

## The steps

1. **Get the new version.** Install `releases/latest/download/MariamsNotes.apk`
   over the old app. Expect "Version 1.11.0" at the bottom of Settings.
2. **Misspelt words, with Auto on.** Write a few lines with words spelt
   wrong on purpose: "teh", "taht", "recieve", "finaly", "happend",
   "begining", "nuerons", "thier", "seperate". Expect each typed correctly,
   with a dotted underline you can tap to get your spelling back.
3. **Words it should leave alone.** Write course words and British
   spellings: "behaviour", "depolarised", "centre", "interoception",
   "amygdala", "Broca", your own name. Expect them typed as written.
4. **Unclear words.** Where a word can't be fixed with confidence it gets a
   red wavy line; tap it and pick the right spelling.
5. **Arrows in one stroke.** Write "brain → spinal cord" 8 times, drawing
   the shaft and then the head without lifting the pen, in different ways
   (back over the first barb, a closed head, big and small heads). Expect →
   every time. Once, rest the pen at the tip before drawing the head: the
   head must still be drawn, and the arrow found.
6. **No false arrows.** Write "x - c", "a - e", "the", "E", "+", "=" and
   convert. Expect no →.
7. **Send writing samples.** In a notebook, tap ⋮ › Send writing samples,
   pick WhatsApp and send the file to Malek. (Same button in Settings ›
   Writing.)

## Where each step lives in the code

| Step | Code to look at first |
|---|---|
| 2-4 autocorrect | `recognition/text_polish.dart` (`_spelling`, `_formSlips`, `_shortSwap`, `commonMisspellings`, `_variants`, `isTypoShaped`, `PolishConfig`), `htr_channel.dart` (`weighSuggestions`), `assets/htr/subject_words.txt` (`docs/htr_bench/make_subject_words.py`) |
| 5-6 arrows | `recognition/arrows.dart` (`ArrowConfig`, `_straight`, `_headAt`, `_isHead`), `integrations/shapes/hold_snap_hook.dart` (`_turn`, `_unsnap`) |
| 7 samples | `integrations/convert/send_writing_samples.dart`, `writing_samples.dart`, `kept_corrections.dart`, `auto_convert_session.dart` (`onConverted`) |
