# Handwriting recognition notes

The app reads handwriting with **PaddleOCR PP-OCRv5 English mobile recogniser**
(Hugging Face `PaddlePaddle/en_PP-OCRv5_mobile_rec_onnx`, **Apache-2.0**,
(c) PaddlePaddle Authors), run by ONNX Runtime in `HtrPlugin.kt`. It replaced the
SimpleHTR/IAM word model of v1.1.0 (`PellelNitram/xournalpp-htr-simple-htr`),
which got about half the letters of the owner's real handwriting wrong.

Files in `assets/htr/`:

| File | Size | Used |
|---|---|---|
| `model.onnx` | 7.8 MB | yes, `inference.onnx` of the repo, unchanged |
| `charset.json` | 4 KB | yes, class table: blank, the 436 characters of `inference.yml`'s `character_dict`, space |
| `word_freq.txt` | 0.8 MB | yes, English word frequencies (SymSpell `en-80k`, first 50,000 plain-letter entries; MIT, counts from Google Books Ngrams CC BY 3.0) |
| `README.md` | 2 KB | provenance only (not in pubspec) |

The APK is about 5 MB smaller than with the old model (13 MB -> 7.8 MB asset).

## Why this model (benchmark of 2026-10-27)

Nine real word crops cut from a screenshot of the owner's handwriting on the
tablet (`Malek`, `Baghdadi` x2, `Mariam`, `Note`, `boo`, `k`, `27`, `Oct`; the
crops are personal and are not in the repo, see `htr_bench/README.md`),
desktop onnxruntime, greedy decoding, exact match ignoring case:

| Model | Exact (of 9) | Notes |
|---|---|---|
| SimpleHTR (IAM, v1.1.0) | 2 | `Malek -> Maick`, `Mariam -> Masiasn`, `Note -> Notc`, 0.9+ confidence on wrong words |
| TrOCR-small (printed/handwritten ONNX) | 3 | hallucinates real words; rejected |
| **PP-OCRv5 en mobile rec** | **5-6** | what the app uses. Remaining misses are letters that really are ambiguous (`e` written like `c`, cursive `r`) |

`docs/htr_bench/check_app_recipe.py` re-implements the app's preprocessing with
the bundled files: **5 of 9** as is, **6 of 9** with the thin-stroke stand-in
(`--thin`). `sens.py` shows the effect of the preprocessing choices:

| Variant (no padding) | Exact |
|---|---|
| as is | 5 |
| thicker strokes | 4 |
| **thinner strokes** | **6** |
| blur | 4 |
| 2x up-scaling | 6 |
| 15% white padding around the word | 5, but answers in CAPITALS |
| 30% white padding | 2-3, garbage on short words |

## Model facts (verified with onnxruntime 1.31.1)

* Input `x`, float32 `[N, 3, 48, W]`, **N and W dynamic**. Grey image, ink dark on
  white, three identical channels, value `(pixel / 255 - 0.5) / 0.5`.
* Output `[N, T, 438]` float32, **softmax probabilities** (not log); `T` is about
  `W / 8` (25 frames for a 200 px wide word).
* Class 0 = CTC blank, class `i` (1..436) = `character_dict[i - 1]` (digits,
  A-Z, a-z, punctuation, then symbols: 2 of the 436 are outside the BMP), class
  437 = space `' '`. The dictionary contains `"`, `'` and `\`; `charset.json` is
  generated with PyYAML (`htr_bench/make_charset.py`) because a hand-written
  parser gets those wrong.
* Preprocessing that worked: contrast-stretched grey, resized to height 48
  keeping the aspect ratio (`W = round(48 * w / h)`, at least 16), **no white
  padding** (padding makes it answer in capitals and hurts accuracy). Thin
  strokes (about 1.5-2 px at height 48) scored slightly better than thick ones;
  blur and 2x up-scaling did not help.
* The network is over-confident on handwriting: 0.9+ on a wrong letter is
  normal, and a look-alike letter (`e` for `c`) may get less than 1e-3. That is
  why the language layer below does more than a plain dictionary lookup.

## Pipeline

`stroke_grouping.dart` (lines and words) -> `word_image.dart` (48 px high grey
image per word) -> `htr_channel.dart` -> `HtrPlugin.kt` (one ORT call per image)
-> `ctc.dart` (log with a floor, space folded into the blank) -> `rescorer.dart`
(language layer) -> `WordResult`.

### Plugin contract (`neatink/htr` MethodChannel)

| Dart -> Kotlin | arguments | reply |
|---|---|---|
| `recognize` | `{images: [{width: int 16..800, height: int (=48), pixels: Uint8List width*height}]}` | one map per image: `{timesteps: T, classes: 438, probs: Float32List T*438}` |
| `info` | none | `{classes, blank, charsetSize, inputHeight, minWidth, maxWidth, inputName}` |

Pixels are row-major grey, 0..255, white paper = 255. Each image is **one** ORT
call (no batching, no padding). Errors are `PlatformException` codes
`bad_image`, `model_missing`, `model_unreadable`, `out_of_memory`,
`htr_failed`. The Dart side sends 8 images per call (`batchSize`) to bound the
message size and report progress.

### Word image (`renderWordImage`)

* Levelled by the line's baseline slope, then the ink's bounding box is scaled so
  that it fills the 48 px height; the width follows the aspect ratio (16..800,
  longer words are squeezed horizontally). No border except half a pen width.
* Pen width: **one constant**, `wordImageStrokePx = 1.8` px (at 48 px height),
  independent of the writing size. Round-capped polylines, anti-aliased.
  `PolylineWordImageRenderer` (pure Dart) is used by the tests;
  `UiWordImageRenderer` draws with `dart:ui` on the device.
* Tiny marks (dots, commas) are not blown up: scale <= 10 px/pt, centred on
  white.
* End-to-end check done on the desktop: images rendered by the Dart code from
  the synthetic stroke font decode with the real model (`hello`, `hen`, `log`,
  `one`, `online`, also rotated 8 degrees and levelled).

### Language layer (`rescorer.dart`, `user_lexicon.dart`)

For each word the candidates are the greedy reading, the readings of a CTC
prefix beam search (width 5), English words within 1-2 edits (BK-tree) and
personal-dictionary words within 1-3 edits. Each candidate scores

    score = ln P(image | word) + lambda * ln prior(word)

with the CTC forward log-likelihood (case-insensitive) and the prior from the
word list or `userLogProb` for personal words (unknown strings sit
`oovPenalty` below the rarest listed word). Every number is in
`RescoreConfig`: `lambda` 0.6, `knownBonus` 1.5 (head start of a known greedy
word), `confusionMass` 0.08, `userLogProb` -7, `maxAlternatives` 5 ...

* **Look-alike smoothing.** Before scoring, each letter of a confusable pair
  (`e/c`, `r/s`, `a/o`, `n/u`, `i/l` ... `RescoreConfig.confusablePairs`)
  lends 8% of its probability to the other. A look-alike substitution then
  costs 2-3 nats instead of 10, so `Macck -> Malek` is possible when the
  personal dictionary knows `Malek`, while a different letter still cannot be
  overruled. Only the scoring is smoothed; `raw` is the model's own reading.
* **Capitalisation.** A personal word is written as the user typed it
  (`Malek`). Otherwise the case of the raw first letter is used (`Note`,
  `note`); a raw reading in capitals (3+ letters) is not kept unless the word is
  a known acronym (`NASA`, `USA`); single letters keep the raw case; an unknown
  word nobody replaced stays exactly as read (`XQZ`).
* **Alternatives.** Up to 5 distinct readings, best first, casing applied, the
  raw reading always among them when it was replaced.
* **Confidence.** `exp(ln P(word) / sqrt(length))` times the square root of the
  chosen candidate's share among the scored candidates: ambiguous readings and
  close calls come out low (0.05-0.2), clear ones 0.7-0.9. Uncalibrated beyond
  that; `ConvertConfig.lowConfidenceThreshold` is the knob in the UI.
* **Personal dictionary.** `UserLexicon` (`add`, `learn`, `words`,
  `contains`, `formOf`, `remove`), saved by a `UserLexiconStore`: JSON file
  `<app documents>/recognition/user_lexicon.json` with atomic writes
  (`JsonFileUserLexiconStore`) or in memory (tests). `HtrRecognizer.learn(text)`
  loads the word list, skips words it already knows and saves; the UI should
  call it with the corrected text of every word the user edits. The rescorer
  reads the dictionary live.

#### Behaviour on the bundled word list (unit tests, crisp synthetic frames)

* clear readings of 300 random listed words: 0 changed
* clearly read unlisted names (`Baghdadi`, `Malek`, `Mariam` ...): at most 1 of
  14-16 changed
* a look-alike slip with real doubt (right letter 0.2 vs wrong 0.75): about 76%
  repaired, under 2% turned into something else
* the same slip read with great confidence (0.97 vs 0.005): about 18% repaired
* a word takes 3-20 ms to rescore on a desktop (first call builds the BK-tree,
  about 0.2 s)

#### On the owner's nine crops (real model output)

| Crop | Raw | No personal words | With `Malek Mariam Baghdadi` |
|---|---|---|---|
| Malek | `Macck` | `March` | **`Malek`** (conf 0.12) |
| Baghdadi | `Baghdadi` | `Baghdadi` | `Baghdadi` |
| Mariam | `Masion` | `Marion` | **`Mariam`** (conf 0.06) |
| Baghdadi | `Baghdadi` | `Baghdadi` | `Baghdadi` |
| Note | `Note` | `Note` | `Note` |
| boo | `bge` | `be` | `be` |
| k | `K` | `K` | `K` |
| 27 | `27` | `27` | `27` |
| Oct | `Dct` | `Act` (`Oct` is the 2nd alternative) | `Act` |

5 of 9 right without personal words (no regression against the raw reading), 7
of 9 with them.

### Grouping (`stroke_grouping.dart`)

* Letter blocks are strokes that overlap horizontally. Two blocks are different
  words only if their gap is at least `max(0.6 x-height, 2.5 x the line's
  typical letter gap)` (median of its gaps below 0.6 x-height), at most 1.4
  x-heights. Lines written with wide letter spacing (no gap below 0.6 x-height)
  are split at the largest jump in their sorted gaps.
* A word that is a single narrow letter block (< 1.2 x-heights wide) is a
  fragment: it is merged into the nearer neighbour within 1.5 split thresholds.
  Not fragments: a nearly straight single stroke (`1`, `I`, `l`, `-`), a closed
  single stroke (`0`, `o`), dots, and anything next to another fragment (so
  `a b c` stays three words). Known trade-off: a lone curvy digit such as `2`
  written within 1.5 thresholds of the previous word is merged into it.
* All thresholds are in `GroupingConfig`.

## Not verified on a device

ONNX Runtime session on the tablet (input name, speed per word), the
`UiWordImageRenderer` crops, real handwriting accuracy of the whole chain (the
numbers above are from screenshots and synthetic frames), and the tuning of
`lambda` / `confusionMass` / `knownBonus` on more handwriting than nine crops.
The review sheet's "Show what the recognizer saw" section shows the 48 px images
and the raw reading for that.
