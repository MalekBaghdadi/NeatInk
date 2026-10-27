"""The model on stitched line images (a rough stand-in for real line renders).

Usage: python lines.py   (crops 00..08 as in bench.py; writes line_*.png to HTR_OUT or here)
"""
import glob
import os
import re

from PIL import Image

import bench

OUT = os.environ.get("HTR_OUT", os.path.dirname(os.path.abspath(__file__)))
crops = {}
for p in sorted(glob.glob(os.path.join(bench.CROPS, "*.png"))):
    i = int(os.path.basename(p)[:2])
    crops[i] = bench.stretch(Image.open(p).convert("L"))


def stitch(idx, gap=18, height=48, joins=()):
    parts = []
    for i in idx:
        im = crops[i]
        w, h = im.size
        parts.append(im.resize((max(8, int(w * height / h)), height), Image.BICUBIC))
    total = sum(p.width for p in parts) + gap * (len(parts) - 1)
    out = Image.new("L", (total, height), 255)
    x = 0
    for n, p in enumerate(parts):
        out.paste(p, (x, 0))
        x += p.width + (4 if n in joins else gap)
    return out


lines = {
    "Malek Baghdadi": stitch([0, 1]),
    "Mariam Baghdadi": stitch([2, 3]),
    "Notebook 27 Oct": stitch([4, 5, 6, 7, 8], joins=(1,)),
}
m = bench.Paddle()
for truth, img in lines.items():
    img.save(os.path.join(OUT, "line_" + re.sub(r"\W", "_", truth) + ".png"))
    for pad in (0.0, 0.1, 0.25):
        t, c = m.run(img, pad=pad)
        print(f"{truth:18} pad={pad:<4} -> {t!r} {c:.2f}")
