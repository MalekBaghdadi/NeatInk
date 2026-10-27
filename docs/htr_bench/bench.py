"""Compare handwriting recognizers on real word crops cut from a tablet screenshot.

Usage: python bench.py [paddle] [simplehtr] [trocr]

* paddle     the bundled PP-OCRv5 model (assets/htr/model.onnx + charset.json): default
* simplehtr  the model that shipped in v1.1.0 (needs SIMPLEHTR_DIR with model.onnx + config.json)
* trocr      TrOCR-small ONNX (needs TROCR_DIR); rejected, it hallucinates real words

The crops are personal handwriting and are NOT in the repository. Put them in
a folder of PNG files named `<index>_<truth>.png` (for example `00_Malek.png`)
and pass it as HTR_CROPS (default: the folder next to this script named crops).
See README.md in this folder.

Needs: pip install --user onnxruntime numpy pillow
"""
import glob
import json
import math
import os
import re
import sys

import numpy as np
import onnxruntime as ort
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.normpath(os.path.join(HERE, "..", ".."))
CROPS = os.environ.get("HTR_CROPS", os.path.join(HERE, "crops"))

so = ort.SessionOptions()
so.log_severity_level = 3


def load_crops():
    out = []
    for p in sorted(glob.glob(os.path.join(CROPS, "*.png"))):
        label = re.sub(r"^\d+_", "", os.path.basename(p)[:-4])
        out.append((label, Image.open(p).convert("L")))
    if not out:
        sys.exit(f"no crops in {CROPS} (set HTR_CROPS)")
    return out


def stretch(img):
    """Normalise contrast: darkest -> 0, paper -> 255."""
    a = np.asarray(img, dtype=np.float32)
    lo, hi = np.percentile(a, 1), np.percentile(a, 90)
    a = np.clip((a - lo) / max(hi - lo, 1), 0, 1) * 255
    return Image.fromarray(a.astype(np.uint8))


# ------------------------------------------------------------------- Paddle
class Paddle:
    """PP-OCRv5 English mobile recognizer with the app's preprocessing."""

    def __init__(self):
        d = os.path.join(PROJECT, "assets", "htr")
        self.s = ort.InferenceSession(os.path.join(d, "model.onnx"), so)
        with open(os.path.join(d, "charset.json"), encoding="utf-8") as f:
            table = json.load(f)
        self.chars = table["charset"]  # index 0 = blank (""), last = space
        self.blank = table.get("blank", 0)

    def probs(self, img, pad=0.0):
        """Softmax probabilities [T, 438] for a grey word image."""
        img = stretch(img)
        if pad:
            from PIL import ImageOps

            w, h = img.size
            img = ImageOps.expand(img, border=(int(w * pad), int(h * pad)), fill=255)
        w, h = img.size
        nw = max(16, min(800, int(round(48 * w / h))))
        r = img.resize((nw, 48), Image.BICUBIC).convert("RGB")
        a = (np.asarray(r, np.float32) / 255 - 0.5) / 0.5
        return self.s.run(None, {"x": a.transpose(2, 0, 1)[None]})[0][0]

    def decode(self, out):
        idx = out.argmax(1)
        text, conf, prev = "", [], self.blank
        for t, i in enumerate(idx):
            if i != prev and i != self.blank:
                text += self.chars[i]
                conf.append(float(out[t, i]))
            prev = i
        return text, float(np.mean(conf)) if conf else 0.0

    def run(self, img, pad=0.0):
        return self.decode(self.probs(img, pad))


# ---------------------------------------------------------------- SimpleHTR
class SimpleHtr:
    def __init__(self):
        d = os.environ["SIMPLEHTR_DIR"]
        self.s = ort.InferenceSession(os.path.join(d, "model.onnx"), so)
        self.charset = json.load(open(os.path.join(d, "config.json")))["charset"]

    def run(self, img):
        img = stretch(img)
        w, h = img.size
        scale = min(128 / w, 32 / h)
        nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
        r = img.resize((nw, nh), Image.LANCZOS)
        canvas = Image.new("L", (128, 32), 255)
        canvas.paste(r, ((128 - nw) // 2, (32 - nh) // 2))
        x = (np.asarray(canvas, np.float32) / 255 - 0.5)[None, None]
        lp = self.s.run(None, {"image": x})[0][:, 0, :]  # T x 79, log-softmax
        idx = lp.argmax(1)
        text, conf, prev = "", [], 78
        for t, i in enumerate(idx):
            if i != prev and i != 78:
                text += self.charset[i]
                conf.append(math.exp(lp[t, i]))
            prev = i
        return text, float(np.mean(conf)) if conf else 0.0


# ------------------------------------------------------------------- TrOCR
class TrOcr:
    def __init__(self):
        from tokenizers import Tokenizer

        d = os.environ["TROCR_DIR"]
        self.enc = ort.InferenceSession(d + "/onnx/encoder_model_quantized.onnx", so)
        self.dec = ort.InferenceSession(d + "/onnx/decoder_model_quantized.onnx", so)
        self.tok = Tokenizer.from_file(d + "/tokenizer.json")
        cfg = json.load(open(d + "/generation_config.json"))
        self.start = cfg["decoder_start_token_id"]
        self.eos = cfg["eos_token_id"]
        self.in_names = [i.name for i in self.dec.get_inputs()]

    def run(self, img):
        img = stretch(img).convert("RGB").resize((384, 384), Image.BICUBIC)
        a = (np.asarray(img, np.float32) / 255 - 0.5) / 0.5
        px = a.transpose(2, 0, 1)[None]
        hid = self.enc.run(None, {"pixel_values": px})[0]
        ids = [self.start]
        logp = 0.0
        for _ in range(24):
            feeds = {"input_ids": np.array([ids], np.int64), "encoder_hidden_states": hid}
            if "encoder_attention_mask" in self.in_names:
                feeds["encoder_attention_mask"] = np.ones(hid.shape[:2], np.int64)
            logits = self.dec.run(None, feeds)[0][0, -1]
            p = np.exp(logits - logits.max())
            p /= p.sum()
            nxt = int(p.argmax())
            logp += math.log(p[nxt])
            if nxt == self.eos:
                break
            ids.append(nxt)
        text = self.tok.decode(ids[1:], skip_special_tokens=True).strip()
        return text, math.exp(logp / max(1, len(ids)))


def main():
    which = sys.argv[1:] or ["paddle"]
    crops = load_crops()
    results = {}
    for name in which:
        m = {"simplehtr": SimpleHtr, "paddle": Paddle, "trocr": TrOcr}[name]()
        rows = []
        for label, img in crops:
            if name == "paddle":
                rows.append((label, m.run(img), m.run(img, pad=0.15)))
            else:
                rows.append((label, m.run(img)))
        results[name] = rows
    print(f"{'truth':10}", *[f"{n:28}" for n in which])
    for i, (label, _) in enumerate(crops):
        cells = []
        for n in which:
            r = results[n][i]
            if n == "paddle":
                cells.append(f"{r[1][0]!r}/{r[2][0]!r}")
            else:
                cells.append(f"{r[1][0]!r} {r[1][1]:.2f}")
        print(f"{label:10}", *[f"{c:28}" for c in cells])
    # exact-match score (case-insensitive), words only
    for n in which:
        ok = 0
        for i, (label, _) in enumerate(crops):
            ok += results[n][i][1][0].lower() == label.lower()
        print(n, "exact:", ok, "/", len(crops))


if __name__ == "__main__":
    main()
