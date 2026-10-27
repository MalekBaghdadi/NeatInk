# Recognizer benchmark and desktop checks

Scripts used to choose and verify the handwriting recognition model (see
`../htr-model-notes.md`). They need `pip install --user onnxruntime numpy pillow`
(`pyyaml` for `make_charset.py`).

| Script | What it does |
|---|---|
| `bench.py` | Runs the bundled model (`paddle`, default), the old SimpleHTR (`SIMPLEHTR_DIR`) or TrOCR-small (`TROCR_DIR`) on the benchmark crops; prints each word and the exact-match count. |
| `sens.py` | How the PP-OCRv5 model reacts to stroke thickness, blur, up-scaling and white padding around the word. |
| `lines.py` | The model on several crops stitched into one line image. |
| `check_app_recipe.py` | Re-implements the app's preprocessing (height 48, no padding, `(v/255-0.5)/0.5`, space folded into the blank, greedy CTC) with the bundled `assets/htr/model.onnx` + `charset.json` and fails (exit 1) when fewer than 5 of 9 crops decode. `--thin` approximates the app's thin strokes, `--dump f.json` writes the probability matrices. |
| `make_charset.py` | Builds `assets/htr/charset.json` from the model's `inference.yml`. |

## The crops are not in the repository

They are cut from a screenshot of the owner's real handwriting on the tablet
(personal data), so they stay out of git. Nine files named `<index>_<truth>.png`
(`00_Malek`, `01_Baghdadi`, `02_Mariam`, `03_Baghdadi`, `04_Note`, `05_boo`,
`06_k`, `07_27`, `08_Oct`); `boo` and `k` are the pieces the old grouping cut
`Notebook` into.

Where they live on the development PC (session scratchpad):

    C:/Users/MALEKB~1/AppData/Local/Temp/claude/C--Users-Malek-Baghdadi/086d4d13-b02e-4c0b-ac3c-7f830349bd63/scratchpad/bench/crops/

Point the scripts at a folder with `HTR_CROPS=<folder>` (or pass `--crops` to
`check_app_recipe.py`), for example:

    HTR_CROPS=/path/to/crops python docs/htr_bench/bench.py
    python docs/htr_bench/check_app_recipe.py --crops /path/to/crops --thin

Use `python -I` only for scripts that read untrusted files and do not need the
user site packages; these scripts import `onnxruntime` from the user site, so
run them with plain `python` from a folder you control.
