"""Empirical check of assets/htr/model.onnx (run: python -I htr_check.py <assets/htr dir>)."""
import json
import site
import sys

sys.path.append(site.getusersitepackages())  # -I disables the user site

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageDraw, ImageFont

assets = sys.argv[1]
fonts_dir = 'C:/Windows/Fonts/'
cfg = json.load(open(assets + '/config.json'))
charset = cfg['charset']
sess = ort.InferenceSession(assets + '/model.onnx', providers=['CPUExecutionProvider'])
for i in sess.get_inputs():
    print('input', i.name, i.shape, i.type)
for o in sess.get_outputs():
    print('output', o.name, o.shape, o.type)
in_name = sess.get_inputs()[0].name


def render(word, font_file, size=64, stroke_w=0, h=32, w=128, margin=2):
    font = ImageFont.truetype(fonts_dir + font_file, size)
    probe = Image.new('L', (800, 200), 255)
    d = ImageDraw.Draw(probe)
    d.text((20, 20), word, font=font, fill=0, stroke_width=stroke_w)
    arr = np.array(probe)
    ys, xs = np.where(arr < 128)
    crop = probe.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    scale = min((w - 2 * margin) / crop.width, (h - 2 * margin) / crop.height)
    nw, nh = max(1, round(crop.width * scale)), max(1, round(crop.height * scale))
    crop = crop.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new('L', (w, h), 255)
    canvas.paste(crop, ((w - nw) // 2, (h - nh) // 2))
    return np.array(canvas, dtype=np.uint8)


def run(img, invert=False, transpose=False, norm='half'):
    x = img.astype(np.float32)
    if invert:
        x = 255 - x
    x = x / 255.0 - 0.5 if norm == 'half' else x / 255.0
    if transpose:
        x = x.T
    x = x[None, None]
    return sess.run(None, {in_name: x})[0]


def greedy(out, blank):
    # out: (T, C) after layout resolved
    ids = out.argmax(axis=1)
    s, prev = [], -1
    for i in ids:
        if i != prev and i != blank:
            s.append(charset[i])
        prev = i
    return ''.join(s)


words = ['hello', 'world', 'the', 'Notes', 'Mariam', 'because', 'quick', 'tomorrow']
fonts = ['Inkfree.ttf', 'BRADHITC.TTF', 'comic.ttf', 'LHANDW.TTF', 'arial.ttf']

img = render('hello', 'Inkfree.ttf')
o = run(img)
print('output array shape', o.shape, 'dtype', o.dtype)
a = o[0] if o.ndim == 3 and o.shape[0] == 1 else o
print('sum of exp over class axis (first rows):')
for ax in (0, 1, 2):
    if o.ndim == 3 and o.shape[ax] == 79:
        print(' class axis', ax, np.exp(o).sum(axis=ax).ravel()[:4])
print('value range', float(o.min()), float(o.max()))

# Resolve layout: find which axis has 79 classes and which is T.
cls_axis = [ax for ax in range(o.ndim) if o.shape[ax] == 79][0]
print('class axis', cls_axis)
for layout in ('TN', 'NT'):
    pass


def to_tc(o):
    # returns (T, C) for a single image
    if o.shape[0] == 1 and o.shape[1] != 1:
        return o[0]  # N, T, C
    if o.shape[1] == 1:
        return o[:, 0, :]  # T, N, C
    raise RuntimeError(o.shape)


tc = to_tc(o)
print('T x C', tc.shape)
# Which index is the blank? Count how often each index is the argmax.
ids = tc.argmax(axis=1)
print('argmax ids', ids.tolist())
print('softmax-normalised?', bool(np.allclose(np.exp(tc).sum(axis=1), 1, atol=1e-3)),
      '; raw logits sum-to-one?', bool(np.allclose(tc.sum(axis=1), 1, atol=1e-3)))

blank = 78 if (ids == 78).sum() > (ids == 0).sum() else 0
print('blank guess', blank)

total = ok = 0
for f in fonts:
    for wd in words:
        img = render(wd, f)
        tc = to_tc(run(img))
        got = greedy(tc, 78)
        total += 1
        ok += got == wd
        print(f'{f:14s} {wd:10s} -> {got}')
print(f'exact: {ok}/{total}')

print('--- variants (Inkfree, hello world words) ---')
for name, kw in [('invert (white ink on black)', dict(invert=True)),
                 ('norm x/255 only', dict(norm='unit'))]:
    r = []
    for wd in words:
        r.append(greedy(to_tc(run(render(wd, 'Inkfree.ttf'), **kw)), 78))
    print(name, r)

print('--- batching and stroke width ---')
import time
imgs = [render(wd, 'Inkfree.ttf') for wd in words]
xb = np.stack([(i.astype(np.float32) / 255.0 - 0.5) for i in imgs])[:, None]
t0 = time.time()
ob = sess.run(None, {in_name: xb})[0]
print('batch output', ob.shape, 'ms', round((time.time() - t0) * 1000))
print('batched', [greedy(ob[:, k, :], 78) for k in range(len(words))])
single = to_tc(run(imgs[0]))
print('batch==single', bool(np.allclose(single, ob[:, 0, :], atol=1e-4)))
for sw in (0, 1, 2):
    print('bold stroke_width', sw, [greedy(to_tc(run(render(wd, 'arial.ttf', size=64, stroke_w=sw))), 78) for wd in words])
