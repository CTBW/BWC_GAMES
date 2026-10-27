"""Make the collie guard's longsword heavier, keeping its length.

  python bulk_sword.py <collie_sword_v1.png> <out.png>

Like bulk_up.py for the guard: an edit keeps the silhouette it is given, so the shape is
changed here. Measured on collie_sword_v1.png (1536 x 2752, the sword down the middle at
x 768): the blade at rows 58-2005, the cross-guard 2005-2125, the grip 2125-2565, the
pommel 2565-2680. Each part is widened about the middle (SEGMENTS: source rows, width
factor, height factor); the guard and the pommel grow in height too, and the blade gives
up those rows so the sword keeps its length. The pommel scales evenly and stays round.
"""
import sys

import numpy as np
from PIL import Image

CX = 768.0
SEGMENTS = [  # source rows, width factor, height factor (the blade's absorbs the rest)
    ((58, 2005), 1.30, None),
    ((2005, 2125), 1.20, 1.30),
    ((2125, 2565), 1.20, 1.00),
    ((2565, 2680), 1.30, 1.30),
]

src, out = sys.argv[1], sys.argv[2]
im = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
H, W, _ = im.shape

# Output rows of each segment's ends; the blade takes what the others add.
grown = sum((b - a) * (h - 1) for (a, b), _, h in SEGMENTS[1:])
src_y = [SEGMENTS[0][0][0]]
out_y = [SEGMENTS[0][0][0]]
kx_at = []
for (a, b), kx, h in SEGMENTS:
    h = h if h is not None else ((b - a) - grown) / (b - a)
    src_y.append(b)
    out_y.append(out_y[-1] + (b - a) * h)
    kx_at.append(kx)

yo = np.arange(H, dtype=np.float32)
ys = np.interp(yo, out_y, src_y)
# The width factor per output row, eased over 12 rows at each joint.
kx = np.full(H, kx_at[0], np.float32)
for i in range(1, len(SEGMENTS)):
    t = np.clip((yo - out_y[i] + 6) / 12, 0, 1)
    kx = kx + (kx_at[i] - kx_at[i - 1]) * t * t * (3 - 2 * t)

xo = np.arange(W, dtype=np.float32)
xs = CX + (xo[None, :] - CX) / kx[:, None]
ys = np.broadcast_to(ys[:, None], xs.shape)

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
print("rows", [round(v) for v in out_y], out)
