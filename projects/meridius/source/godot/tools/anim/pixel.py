"""Snap generated pixel art to a true pixel grid and cut out its flat background.

Copied from ../game/scripts/art/pixelize.py (the footman pipeline; that folder
is frozen), unchanged in behaviour:
  block_median  reduces an image by whole blocks (per-channel median, so block
                edges do not blend), onto the art's own pixel grid;
  cut_out       clears the flat border colour wherever it connects to the
                border, plus enclosed pockets of exactly that colour, and
                quantizes without dithering. shadows=False keeps neutral greys
                next to the background (grey hair, steel) solid: the edits are
                drawn without shadows.
"""
import numpy as np
from PIL import Image
from scipy import ndimage


def block_median(a, f):
    """Reduce an RGB array by an integer block size f (per-channel median)."""
    h, w, c = a.shape
    by, bx = h // f, w // f
    a = a[: by * f, : bx * f].reshape(by, f, bx, f, c).transpose(0, 2, 1, 3, 4).reshape(by, bx, f * f, c)
    return np.median(a, axis=2).astype(np.uint8)


def cut_out(small, bg_tol=22.0, shadow_max=0.45, colors=64, shadows=True):
    """Return (RGBA array, background colour, shadow mask) for a reduced image."""
    rgb = small.astype(np.int16)
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    bg = np.median(border, axis=0)
    lum = rgb.mean(axis=2)
    bg_lum = bg.mean()
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    dist = np.sqrt(((rgb - bg) ** 2).sum(axis=2))
    near_bg = dist < bg_tol
    shadowish = (sat < 20) & (lum < bg_lum - 6) & (lum > bg_lum - 110) & shadows

    labels, _ = ndimage.label(near_bg | shadowish)
    edge = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    outside = np.isin(labels, edge[edge > 0])
    pockets, n = ndimage.label(dist < 10)
    sizes = ndimage.sum(np.ones_like(dist), pockets, range(1, n + 1))
    big = np.nonzero(sizes >= 20)[0] + 1
    clear = (outside & near_bg) | np.isin(pockets, big)

    alpha = np.full(lum.shape, 255, np.uint8)
    alpha[clear] = 0
    touching, _ = ndimage.label(shadowish | clear)
    shadow = shadowish & np.isin(touching, np.unique(touching[clear])) & ~clear
    depth = np.clip((bg_lum - lum) / 110.0, 0, 1)
    alpha[shadow] = (np.round(shadow_max * np.sqrt(depth[shadow]) * 4) / 4 * 255).astype(np.uint8)

    q = Image.fromarray(small).quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    out = np.dstack([np.array(q.convert('RGB')), alpha])
    out[shadow, :3] = 0
    out[clear, :3] = 0
    return out, bg, shadow
