"""Painterly post-process for rendered sprites (Kuwahara brush patches,
mild posterisation, canvas grain), preserving the alpha channel.

Usage: python paint.py <in.png> <out.png> [radius] [levels]
"""
import sys

import numpy as np
from PIL import Image
from scipy import ndimage


def kuwahara(rgb, alpha, r):
    """Classic 4-quadrant Kuwahara filter on premultiplied colour."""
    a = alpha[..., None]
    pm = rgb * a
    lum = (0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]) * alpha
    size = r + 1
    # Box means over (r+1)x(r+1) windows, then shift to the four quadrants.
    mean_c = np.stack([ndimage.uniform_filter(pm[..., i], size=size, mode='nearest') for i in range(3)], -1)
    mean_a = ndimage.uniform_filter(alpha, size=size, mode='nearest')
    mean_l = ndimage.uniform_filter(lum, size=size, mode='nearest')
    mean_l2 = ndimage.uniform_filter(lum * lum, size=size, mode='nearest')
    var = mean_l2 - mean_l * mean_l
    h, w = alpha.shape
    best_var = np.full((h, w), np.inf)
    out_c = np.zeros_like(pm)
    out_a = np.zeros_like(alpha)
    half = r // 2
    for dy in (-half, half):
        for dx in (-half, half):
            v = np.roll(np.roll(var, dy, 0), dx, 1)
            c = np.roll(np.roll(mean_c, dy, 0), dx, 1)
            al = np.roll(np.roll(mean_a, dy, 0), dx, 1)
            m = v < best_var
            best_var = np.where(m, v, best_var)
            out_c = np.where(m[..., None], c, out_c)
            out_a = np.where(m, al, out_a)
    col = out_c / np.maximum(out_a[..., None], 1e-4)
    return np.clip(col, 0, 1)


def paint(src, dst, radius=6, levels=28, grain=0.035, seed=1):
    im = Image.open(src).convert('RGBA')
    arr = np.asarray(im).astype(np.float32) / 255.0
    rgb, alpha = arr[..., :3], arr[..., 3]
    out = kuwahara(rgb, alpha, radius)
    # Keep the original where the sprite is nearly transparent (shadow edges).
    solid = (alpha > 0.6)[..., None]
    out = np.where(solid, out, rgb)
    # Mild posterisation for flat painted planes.
    out = np.round(out * levels) / levels
    # Canvas grain, stronger in mid tones.
    rng = np.random.default_rng(seed)
    n = ndimage.gaussian_filter(rng.standard_normal(alpha.shape), 0.8)
    lum = out.mean(-1, keepdims=True)
    out = out + (n[..., None] * grain) * (1 - np.abs(lum - 0.5) * 1.4)
    # Slight warm saturation lift.
    mean = out.mean(-1, keepdims=True)
    out = mean + (out - mean) * 1.28
    res = np.concatenate([np.clip(out, 0, 1), alpha[..., None]], -1)
    Image.fromarray((res * 255).astype(np.uint8), 'RGBA').save(dst)


if __name__ == '__main__':
    r = int(sys.argv[3]) if len(sys.argv) > 3 else 6
    lv = int(sys.argv[4]) if len(sys.argv) > 4 else 28
    paint(sys.argv[1], sys.argv[2], r, lv)
    print('painted', sys.argv[2])
