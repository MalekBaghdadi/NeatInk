"""How sensitive is the model to stroke thickness / padding / contrast on the real crops?

Usage: python sens.py   (HTR_CROPS = folder of `<index>_<truth>.png`, see bench.py)
"""
import glob
import os
import re

from PIL import Image, ImageFilter

import bench

crops = []
for p in sorted(glob.glob(os.path.join(bench.CROPS, "*.png"))):
    crops.append((re.sub(r"^\d+_", "", os.path.basename(p)[:-4]), Image.open(p).convert("L")))

m = bench.Paddle()
PAD = 0.0


def score(variant, fn):
    ok, outs = 0, []
    for label, im in crops:
        t, _ = m.run(fn(im), pad=PAD)
        outs.append(t)
        ok += t.lower() == label.lower()
    print(f"{variant:28} {ok}/{len(crops)}  {outs}")


for PAD in (0.0, 0.15, 0.3):
    print("--- pad", PAD)
    score("as is", lambda im: im)
    score("thicker (min filter 3)", lambda im: bench.stretch(im).filter(ImageFilter.MinFilter(3)))
    score("thinner (max filter 3)", lambda im: bench.stretch(im).filter(ImageFilter.MaxFilter(3)))
    score("blur 1", lambda im: bench.stretch(im).filter(ImageFilter.GaussianBlur(1)))
    score("2x upscale first", lambda im: im.resize((im.width * 2, im.height * 2), Image.BICUBIC))
