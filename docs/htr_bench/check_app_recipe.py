"""Does the app's preprocessing recipe still read the benchmark crops?

Re-implements, in numpy/PIL, what `lib/recognition/word_image.dart` +
`android/.../HtrPlugin.kt` + `lib/recognition/ctc.dart` do, and decodes the
crops with the bundled assets/htr/model.onnx and charset.json:

  grey image, ink dark on white, contrast stretched
  -> resized to height 48, width = round(48 * w / h) clamped to 16..800,
     NO white padding around the word
  -> (v / 255 - 0.5) / 0.5 in three identical channels, shape [1, 3, 48, W]
  -> softmax probabilities [T, 438]; the space class is folded into the blank
  -> greedy CTC decoding (class 0 = blank)

The Dart renderer draws thin strokes itself; a raster crop cannot be thinned
exactly, so `--thin` applies a 3x3 max filter (about one pixel thinner) as the
closest stand-in.

Usage: python check_app_recipe.py [--crops DIR] [--thin] [--min-exact N] [--dump FILE]

Exit code 1 when fewer than --min-exact crops (default 5 of 9) decode to the
word in their file name, ignoring case.
"""
import argparse
import glob
import json
import os
import re
import sys

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.normpath(os.path.join(HERE, "..", ".."))
HEIGHT, MIN_WIDTH, MAX_WIDTH = 48, 16, 800


def stretch(img):
    a = np.asarray(img, dtype=np.float32)
    lo, hi = np.percentile(a, 1), np.percentile(a, 90)
    a = np.clip((a - lo) / max(hi - lo, 1), 0, 1) * 255
    return Image.fromarray(a.astype(np.uint8))


def word_image(img, thin=False):
    img = stretch(img)
    if thin:
        # Thinner ink, then full black again (the app draws pure black strokes).
        img = stretch(img.filter(ImageFilter.MaxFilter(3)))
    w, h = img.size
    width = max(MIN_WIDTH, min(MAX_WIDTH, int(round(HEIGHT * w / h))))
    return img.resize((width, HEIGHT), Image.BICUBIC)


def to_tensor(img):
    a = (np.asarray(img.convert("RGB"), np.float32) / 255 - 0.5) / 0.5
    return a.transpose(2, 0, 1)[None]


def greedy(probs, chars, blank=0, space=None):
    probs = probs.copy()
    if space is not None:  # a word image holds no spaces
        probs[:, blank] += probs[:, space]
        probs[:, space] = 0
    idx = probs.argmax(1)
    text, prev = "", -1
    for i in idx:
        if i != prev and i != blank:
            text += chars[i]
        prev = i
    return text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--crops", default=os.environ.get("HTR_CROPS", os.path.join(HERE, "crops")))
    ap.add_argument("--thin", action="store_true")
    ap.add_argument("--min-exact", type=int, default=5)
    ap.add_argument("--dump", help="write the probability matrices to this JSON file")
    args = ap.parse_args()

    assets = os.path.join(PROJECT, "assets", "htr")
    so = ort.SessionOptions()
    so.log_severity_level = 3
    session = ort.InferenceSession(os.path.join(assets, "model.onnx"), so)
    with open(os.path.join(assets, "charset.json"), encoding="utf-8") as f:
        table = json.load(f)
    chars, blank, space = table["charset"], table["blank"], table["space"]
    assert len(chars) == table["classes"] == session.get_outputs()[0].shape[2] == 438

    paths = sorted(glob.glob(os.path.join(args.crops, "*.png")))
    if not paths:
        sys.exit(f"no crops in {args.crops} (see README.md)")
    ok, dump = 0, {}
    for p in paths:
        truth = re.sub(r"^\d+_", "", os.path.basename(p)[:-4])
        img = word_image(Image.open(p).convert("L"), thin=args.thin)
        probs = session.run(None, {"x": to_tensor(img)})[0][0]
        text = greedy(probs, chars, blank, space)
        hit = text.lower() == truth.lower()
        ok += hit
        dump[os.path.basename(p)] = {"T": probs.shape[0], "C": probs.shape[1], "probs": probs.round(7).reshape(-1).tolist()}
        print(f"{truth:10} -> {text!r:14} {'ok' if hit else ''}  (image {img.size[0]}x{img.size[1]}, T={probs.shape[0]})")
    print(f"exact: {ok} / {len(paths)}  (thin={args.thin})")
    if args.dump:
        with open(args.dump, "w") as f:
            json.dump(dump, f)
    sys.exit(0 if ok >= args.min_exact else 1)


if __name__ == "__main__":
    main()
