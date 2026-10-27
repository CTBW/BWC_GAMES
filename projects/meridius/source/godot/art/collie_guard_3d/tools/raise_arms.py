"""Rough T-pose paste-up of the collie guard: cut each arm off at the armpit and raise it.

  python raise_arms.py <collie_tpose_front_v2.png> <out.png> <degrees>

Nano Banana Pro kept redrawing the guard in his A-pose (references/characters/collie_guard,
prompts.md sections 4 and 7), so the arms are raised here and the joins are repainted by an
edit (section 10). The joints were measured on v2 (1792 x 2400): armpits at (645, 715) and
(1147, 715), shoulder pivots at (590, 640) and (1202, 640); 42 degrees makes the arms level.
The arm is cut along the line through the armpit across the arm's axis, and below the
armpit along the gap between the arm and the tabard; the body is laid over the raised arms
so the pauldron caps cover the joins. The canvas is widened for the arms and kept at 3:4.
"""
import sys

from PIL import Image
import numpy as np

src, out, ang = sys.argv[1], sys.argv[2], float(sys.argv[3])
im = Image.open(src).convert("RGB")
W, H = im.size
a = np.asarray(im).astype(int)
fg = a.min(axis=2) < 235
yy, xx = np.mgrid[0:H, 0:W]


def arm_mask(side):
    # side -1: image-left arm. Measured on v2: armpit (645, 715), shoulder pivot (590, 640).
    ax, ay = (645, 715) if side < 0 else (W - 645, 715)
    d = np.array([-0.75, 0.66]) if side < 0 else np.array([0.75, 0.66])
    half = ((xx - ax) * d[0] + (yy - ay) * d[1]) > 0
    upper = (yy < 720) & half
    # Below the armpit the cut follows the gap between the arm and the tabard.
    cut = np.select([yy < 770, yy < 850, yy < 950], [645, 620, 560], 500)
    lower = (yy >= 720) & (yy < 1200) & ((xx < cut) if side < 0 else (xx > W - cut))
    return fg & (upper | lower)


PAD_X = 340
CW = W + 2 * PAD_X
CH = round(CW * 4 / 3)
PAD_Y = (CH - H) // 2
canvas = Image.new("RGBA", (CW, CH), (255, 255, 255, 255))
rgba = im.convert("RGBA")
body_alpha = fg.copy()
for side in (-1, 1):
    m = arm_mask(side)
    body_alpha &= ~m
    layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    arm = rgba.copy()
    arm.putalpha(Image.fromarray((m * 255).astype(np.uint8)))
    layer.paste(arm, (PAD_X, PAD_Y))
    px = (590 if side < 0 else W - 590) + PAD_X
    py = 640 + PAD_Y
    layer = layer.rotate(-ang if side < 0 else ang, center=(px, py), resample=Image.BICUBIC)
    canvas.alpha_composite(layer)
body = rgba.copy()
body.putalpha(Image.fromarray((body_alpha * 255).astype(np.uint8)))
canvas.alpha_composite(body, (PAD_X, PAD_Y))
res = canvas.convert("RGB").resize((1800, 2400), Image.LANCZOS)
res.save(out)
print(CW, CH, res.size)
