"""Bulk up the collie guard's T-pose drawing before the clean-up edit.

  python bulk_up.py <collie_tpose_front_v4.png> <out.png> [k]

Nano Banana Pro would not make him bulkier in an edit (references/characters/collie_guard,
prompts.md sections 7 and 10): it keeps the silhouette it is given. So the silhouette is
widened here; the result (v5) was clean enough to use without another edit. Measured on
v4 (1792 x 2400):
centre x 896, the neck at y 600-680, the pauldrons out to 270 px from the centre, the
arms' axis at y 795.
- Below the neck everything within the pauldrons (torso, legs, paws) is k times as wide;
  the arms and the tail beyond them only move out with it, so the arms keep their length.
- The arms (more than 250 px from the centre) are k times as thick about their axis, in a
  band of rows round it.
- The head is untouched.
"""
import sys

import numpy as np
from PIL import Image

src, out = sys.argv[1], sys.argv[2]
K = float(sys.argv[3]) if len(sys.argv) > 3 else 1.12
CX, R, ARM_Y = 896.0, 270.0, 795.0

im = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
H, W, _ = im.shape
yo, xo = np.mgrid[0:H, 0:W].astype(np.float32)


def smooth(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


# Horizontal: the widening fades in over the neck (rows 600-680).
k = 1 + (K - 1) * smooth((yo - 600) / 80)
d = xo - CX
core = np.abs(d) <= k * R
d_src = np.where(core, d / k, d - (k - 1) * R * np.sign(d))
xs = CX + d_src
# Vertical: arms only (past 250 px, fully past 290), in rows within 100 px of the axis,
# fading out by 220 px.
w = smooth((np.abs(xs - CX) - 250) / 40) * (1 - smooth((np.abs(yo - ARM_Y) - 100) / 120))
ys = yo - (1 - 1 / K) * (yo - ARM_Y) * w

# Bilinear sampling, white outside.
x0 = np.floor(xs).astype(int)
y0 = np.floor(ys).astype(int)
fx = (xs - x0)[..., None]
fy = (ys - y0)[..., None]


def at(yy, xx):
    ok = (xx >= 0) & (xx < W) & (yy >= 0) & (yy < H)
    v = im[np.clip(yy, 0, H - 1), np.clip(xx, 0, W - 1)]
    v[~ok] = 255
    return v


res = (at(y0, x0) * (1 - fx) * (1 - fy) + at(y0, x0 + 1) * fx * (1 - fy)
       + at(y0 + 1, x0) * (1 - fx) * fy + at(y0 + 1, x0 + 1) * fx * fy)
Image.fromarray(np.clip(res, 0, 255).astype(np.uint8)).save(out)
print("bulked", K, out)
