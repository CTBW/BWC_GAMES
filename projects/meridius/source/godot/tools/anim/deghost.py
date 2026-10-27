"""Remove a pale ghost blade the generator copied into one soldier's frames
(the orc brutes' soldier 1: a faint white sword beside the club).

  deghost.py <unit> <soldier> [--min 120] [--maxx 0.45]

In every cut frame of that soldier: nearly colourless, light pieces (HLS
lightness > 0.6, saturation < 0.12) of at least --min px whose centre lies in
the left --maxx of the frame are cleared, with their pale fringe (lightness
> 0.42, saturation < 0.15) within 2 px; then loose specks left behind go too.
"""
import glob
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import squadgen as sg  # noqa: E402


def hls(a):
    rgb = a[..., :3] / 255.0
    mx, mn = rgb.max(2), rgb.min(2)
    l = (mx + mn) / 2
    d = mx - mn
    s = np.where(d == 0, 0, np.where(l <= 0.5, d / np.maximum(mx + mn, 1e-6), d / np.maximum(2 - mx - mn, 1e-6)))
    return l, s


def deghost(path, min_px, maxx):
    a = np.array(Image.open(path).convert("RGBA"))
    op = a[..., 3] > 0
    l, s = hls(a.astype(float))
    pale = op & (l > 0.6) & (s < 0.12)
    lab, n = ndimage.label(pale, structure=np.ones((3, 3)))
    kill = np.zeros_like(op)
    for i in range(1, n + 1):
        m = lab == i
        if m.sum() >= min_px and np.nonzero(m)[1].mean() < maxx * a.shape[1]:
            kill |= m
    if not kill.any():
        return 0
    fringe = op & (l > 0.42) & (s < 0.15)
    kill |= ndimage.binary_dilation(kill, iterations=2) & fringe
    a[kill] = 0
    # Specks cut loose by the removal.
    op = a[..., 3] > 0
    lab, n = ndimage.label(op, structure=np.ones((3, 3)))
    if n > 1:
        sizes = ndimage.sum(op, lab, range(1, n + 1))
        for i, sz in enumerate(sizes, 1):
            if sz < 40:
                a[lab == i] = 0
    Image.fromarray(a).save(path)
    return int(kill.sum())


if __name__ == "__main__":
    unit, soldier = sys.argv[1], int(sys.argv[2])
    min_px = int(sys.argv[sys.argv.index("--min") + 1]) if "--min" in sys.argv else 120
    maxx = float(sys.argv[sys.argv.index("--maxx") + 1]) if "--maxx" in sys.argv else 0.45
    for f in sorted(glob.glob(os.path.join(sg.SQUADS, unit, "*", f"*_{soldier}.png"))):
        if "__" in f:
            continue
        n = deghost(f, min_px, maxx)
        if n:
            print(os.path.relpath(f, sg.SQUADS), n)
