"""Snap a generated pixel-art image to a true pixel grid and cut out its background.

Usage: python pixelize.py <input.png> <out_dir> <name> [--native 512] [--scale 2] [--colors 64]

The generator draws "pixel art" whose pixels are blurred and not aligned to any
grid. This script:
  1. reduces the image to the native grid (default 512 pixels wide), taking
     the per-channel median of each block so block edges do not blend;
  2. finds the flat background (the median border colour) wherever it is
     connected to the image border, plus enclosed pockets of exactly that
     colour, and turns neutral grey contact shadows next to it into
     semi-transparent black, so alpha is hard everywhere else;
  3. quantizes to an adaptive palette without dithering (crisp clusters);
     this runs after step 2 so background greys cannot merge with steel;
  4. writes <name>_<native>.png (native) and <name>.png (enlarged with
     nearest-neighbour scaling, default 2x).
squad.py imports block_median() and cut_out() for turnaround sheets.
"""
import argparse
import os

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
    """Return (RGBA array, background colour, shadow mask) for a reduced image.

    shadows=False keeps neutral greys next to the background (grey hair,
    steel) as solid, for images drawn without shadows.
    """
    rgb = small.astype(np.int16)
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    bg = np.median(border, axis=0)
    lum = rgb.mean(axis=2)
    bg_lum = bg.mean()
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    dist = np.sqrt(((rgb - bg) ** 2).sum(axis=2))
    near_bg = dist < bg_tol
    shadowish = (sat < 20) & (lum < bg_lum - 6) & (lum > bg_lum - 110) & shadows

    # Background and shadows count only where they connect to the image border.
    labels, _ = ndimage.label(near_bg | shadowish)
    edge = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    outside = np.isin(labels, edge[edge > 0])
    # Enclosed gaps (between legs, behind cloaks) keep the exact background colour.
    pockets, n = ndimage.label(dist < 10)
    sizes = ndimage.sum(np.ones_like(dist), pockets, range(1, n + 1))
    big = np.nonzero(sizes >= 20)[0] + 1
    clear = (outside & near_bg) | np.isin(pockets, big)

    alpha = np.full(lum.shape, 255, np.uint8)
    alpha[clear] = 0
    # Shadows touching any cleared area, including enclosed pockets.
    touching, _ = ndimage.label(shadowish | clear)
    shadow = shadowish & np.isin(touching, np.unique(touching[clear])) & ~clear
    depth = np.clip((bg_lum - lum) / 110.0, 0, 1)
    # A few alpha steps keep the shadow banded like the rest of the pixel art.
    alpha[shadow] = (np.round(shadow_max * np.sqrt(depth[shadow]) * 4) / 4 * 255).astype(np.uint8)

    q = Image.fromarray(small).quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    out = np.dstack([np.array(q.convert('RGB')), alpha])
    out[shadow, :3] = 0
    out[clear, :3] = 0
    return out, bg, shadow


def main():
    p = argparse.ArgumentParser()
    p.add_argument('input')
    p.add_argument('out_dir')
    p.add_argument('name')
    p.add_argument('--native', type=int, default=512)
    p.add_argument('--scale', type=int, default=2)
    p.add_argument('--colors', type=int, default=64)
    p.add_argument('--bg_tol', type=float, default=22.0, help='RGB distance still counted as background')
    p.add_argument('--shadow_max', type=float, default=0.45, help='alpha of the darkest contact shadow')
    args = p.parse_args()

    src = np.array(Image.open(args.input).convert('RGB'))
    small = block_median(src, src.shape[1] // args.native)
    out, bg, shadow = cut_out(small, args.bg_tol, args.shadow_max, args.colors)

    os.makedirs(args.out_dir, exist_ok=True)
    native = Image.fromarray(out, 'RGBA')
    native.save(os.path.join(args.out_dir, f'{args.name}_{args.native}.png'))
    big = native.resize((native.width * args.scale, native.height * args.scale), Image.Resampling.NEAREST)
    big.save(os.path.join(args.out_dir, f'{args.name}.png'))
    print(f'{args.name}: bg {bg.astype(int).tolist()}, transparent {int((out[:, :, 3] == 0).mean() * 100)}%, shadow px {int(shadow.sum())}')


if __name__ == '__main__':
    main()
