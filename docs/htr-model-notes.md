# Handwriting recognition model notes

Model: `PellelNitram/xournalpp-htr-simple-htr` on Hugging Face (MIT licence,
SimpleHTR CNN + BiLSTM + CTC, trained on the IAM handwriting database, so
research/non-commercial data: fine for this personal app, credit it on the
licences page). Files live in `assets/htr/`:

| File | Size | Used |
|---|---|---|
| `model.onnx` | 13 MB | yes, run by `HtrPlugin.kt` (ONNX Runtime Android) |
| `config.json` | 1 KB | yes, charset (78 chars) and input size |
| `README.md` | 3 KB | licence/provenance only (not in pubspec assets) |
| `word_freq.txt` | 0.8 MB | yes, English word frequencies for `lib/recognition/lexicon.dart` |

## Verified empirically (`docs/htr_check.py`, onnxruntime 1.31.1 on CPU)

* Input: name `image`, shape `[batch, 1, 32, 128]`, float32, NCHW. Dynamic
  batch (batch of 8 gives the same logits as 8 single runs, ~10 ms for 8).
* Image: height 32 x width 128, **ink dark on a white background**.
  Inverted images (white on black) give garbage.
* Normalisation: `x / 255 - 0.5`. Plain `x / 255` also works (the net is
  insensitive to the shift) but the documented one is used.
* Output: name `log_probs`, shape `[T=32, batch, 79]` (**time first**, then
  batch, then class). Values are **log-softmax** (exp sums to 1 over the
  class axis; max 0, min about -46). No further softmax is needed.
* Classes: 79 = 78 charset characters + blank. **Blank is the last index
  (78)**, charset index i maps to `config.json` `charset[i]`
  (`!"#&'()*+,-./0-9:;?A-Za-z`).
* Greedy CTC decoding of word renderings (Ink Free, Bradley Hand, Comic Sans,
  Lucida Handwriting, Arial; black on white, aspect preserved and centred on a
  white 128x32 canvas, 2 px margin): 35 of 40 exact. Misses were
  `Notes -> Motes`, `Mariam -> Mariamn / Mariann`, `hello -> helto`: letter
  confusions in rare/fancy fonts, as expected for a 5.6% CER model.
  Inked-bolder renderings (stroke width 0-2 px at 64 px font size, scaled
  down to 32 px) all decode fine, so stroke thickness is not critical.

Example output of the check script:

```
input image ['batch', 1, 32, 128] tensor(float)
output log_probs ['LogSoftmaxlog_probs_dim_0', 'batch', 79] tensor(float)
Inkfree.ttf    hello      -> hello
Inkfree.ttf    Mariam     -> Mariam
Inkfree.ttf    tomorrow   -> tomorrow
invert (white ink on black) ['DIEDDED', 'TL', 'ELAED', ...]
exact: 35/40
```

Run it with (needs `pip install --user onnxruntime numpy pillow`):

```
python -I docs/htr_check.py assets/htr
```

End-to-end check of the Dart renderer: the images produced by
`renderWordImage` (pure-Dart rasteriser, synthetic stroke font, one word
rotated 8 degrees and deskewed) were fed to the real model: `hello`,
`online`, `hen` (rotated), `Eli` decoded exactly; `log` gave `bog` (crude
synthetic g).

## Vocabulary decision

The repository's `vocabulary.txt` (5 MB, 472,717 lines) is **not** usable: a
plain alphabetical, mixed-case word list (Webster's-style, with many rare
words such as "Aalii", "Abacinate") plus IAM tokens in capitals, with **no
frequencies** and no stated licence. It was deleted from `assets/`.

Replacement: SymSpell's `en-80k.txt`
(`github.com/wolfgarbe/SymSpell`, `SymSpell.FrequencyDictionary/`), MIT
licence (repository `LICENSE`, (c) 2018 Wolf Garbe). Its README says the
counts come from the Google Books Ngram dataset (CC BY 3.0) intersected with
hunspell wordlists. It is lowercase, one `word count` per line, descending.
`assets/htr/word_freq.txt` is the first 50,000 entries that match
`[a-z]+('[a-z]+)?` (814 KB). Credit "SymSpell frequency dictionary (MIT), word
counts derived from Google Books Ngrams (CC BY 3.0)" on the licences page.

## Preprocessing contract used by the app

Dart renders each word to 128x32 (ink black, background white, aspect kept,
centred, small margin), sends 4096 bytes (row-major, 0..255, white 255) per
word; Kotlin converts to float `x/255 - 0.5` and returns the `[32, 79]`
log-probabilities per image.
