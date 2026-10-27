"""Ground textures for the battle terrain: raw generations -> seamless tiles.

Reads the raw top-down texture generations (art/raw/terrain/<name>.png,
gitignored; their prompts and job ids are in
../../review/terrain/receipts/) and writes assets/terrain/<name>.webp.

Per texture:
  1. Downscale to SIZE (the terrain shows a repeat at about 150-250 screen px,
     so more texels are never seen).
  2. Flatten the low frequencies: a dark or bright blotch would repeat
     visibly across the field; the shader adds its own large-scale variation.
  3. Make it tileable one axis at a time: blend in the texture rolled by half
     along that axis, with a mask that is 1 at the edges and 0 at the middle
     (where the rolled copy has its seam), its boundary a narrow band bent by
     noise so no straight crossfade line shows.

  python -I tools/terrain/make_tileable.py [names...]   (from the project root)
  --preview  also writes tests/visual/out/terrain_tiles_<name>.png (2x2 tiled)
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RAW = os.path.join(ROOT, "art", "raw", "terrain")
OUT = os.path.join(ROOT, "assets", "terrain")
PREVIEW = os.path.join(ROOT, "tests", "visual", "out")
SIZE = 1024
NAMES = ["grass", "dry_grass", "dirt", "forest_floor", "rock", "mud", "flagstone"]
# How much of the low-frequency brightness to remove, per texture (1 = all).
FLATTEN = {"flagstone": 0.5, "mud": 0.6}


def _noise(shape, seed, scale):
    """Smooth value noise in [0, 1] (bicubic upsampled random grid)."""
    rng = np.random.default_rng(seed)
    h, w = shape
    small = rng.random((max(2, h // scale), max(2, w // scale))).astype(np.float32)
    img = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(img).astype(np.float32) / 255.0


def flatten(a, amount):
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    low = np.asarray(img.filter(ImageFilter.GaussianBlur(SIZE / 10))).astype(np.float32)
    mean = a.reshape(-1, 3).mean(axis=0)
    return a - amount * (low - mean)


def tile_axis(a, axis, seed):
    n = a.shape[axis]
    rolled = np.roll(a, n // 2, axis=axis)
    idx = np.abs(np.arange(n, dtype=np.float32) - (n - 1) / 2.0) / (n / 2.0)
    d = idx[:, None] if axis == 0 else idx[None, :]
    wob = (_noise(a.shape[:2], seed, 48) - 0.5) * 0.5 + (_noise(a.shape[:2], seed + 7, 12) - 0.5) * 0.12
    t = np.clip((d + wob - 0.36) / 0.1, 0.0, 1.0)
    m = (t * t * (3 - 2 * t))[..., None]
    return a * (1 - m) + rolled * m


def process(name):
    src = Image.open(os.path.join(RAW, name + ".png")).convert("RGB")
    a = np.asarray(src.resize((SIZE, SIZE), Image.LANCZOS)).astype(np.float32)
    a = flatten(a, FLATTEN.get(name, 0.75))
    a = tile_axis(a, 1, 11)
    a = tile_axis(a, 0, 23)
    out = Image.fromarray(np.clip(a + 0.5, 0, 255).astype(np.uint8))
    out.save(os.path.join(OUT, name + ".webp"), quality=92, method=6)
    b = np.asarray(out).astype(np.float32)
    seam = (np.abs(b[:, 0] - b[:, -1]).mean() + np.abs(b[0] - b[-1]).mean()) / 2
    inner = (np.abs(b[:, 1:] - b[:, :-1]).mean() + np.abs(b[1:] - b[:-1]).mean()) / 2
    print("%-13s seam %.1f, inner %.1f" % (name, seam, inner))
    return out


def main(argv):
    preview = "--preview" in argv
    names = [a for a in argv if not a.startswith("--")] or NAMES
    os.makedirs(OUT, exist_ok=True)
    for name in names:
        out = process(name)
        if preview:
            os.makedirs(PREVIEW, exist_ok=True)
            half = out.resize((SIZE // 2, SIZE // 2), Image.LANCZOS)
            sheet = Image.new("RGB", (SIZE, SIZE))
            for i in range(4):
                sheet.paste(half, ((i % 2) * SIZE // 2, (i // 2) * SIZE // 2))
            sheet.save(os.path.join(PREVIEW, "terrain_tiles_%s.png" % name))


if __name__ == "__main__":
    main(sys.argv[1:])
