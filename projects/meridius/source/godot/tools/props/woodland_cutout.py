"""Cut the painted woodland out for the game's tree and bush sprites.

The paintings in assets/terrain/woodland stand on magenta; the terrain lab
keys them in its shader (scripts/render/woodland_kit.gd). For the battlefield
they become plain RGBA sprites: keyed like the painted rocks
(rock_cutout.key), given the cast shadow the game draws for props (the
silhouette skewed down and to the right, where the paintings' light throws it)
and written as WebP at three sprite pixels per world pixel. Their light is painted from the upper left, so they carry their
own shadow (noShadow) and the game never mirrors them.

    python tools/props/woodland_cutout.py [--src assets/terrain/woodland]
        [--out assets/sprites/painted] [--manifest assets/sprites.json]
        [--review DIR]

Prints the sprites.json entries for tree_pine, tree_oak and bush; with
--manifest, writes them over those three keys and leaves every other key as
it was. Then run tools/import.sh. The sprites' .import files generate mipmaps,
like the Blender trees': a re-run keeps them, a new sprite needs it set.
"""

import argparse
import hashlib
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rock_cutout import key, premul_resize, write_manifest  # noqa: E402

# Root anchors (fractions of the painting) and the world height of the whole
# painting, as woodland_kit.gd places them in the terrain lab.
SOURCES = {
    "pine": ("tree_pine__take-01.png", (0.52, 0.94), 350.0),
    "beech": ("tree_beech__take-01.png", (0.50, 0.94), 310.0),
    "oak": ("tree_oak__take-02.png", (0.51, 0.92), 285.0),
    "shrub": ("bush_green__take-01.png", (0.46, 0.89), 87.0),
}
# The shrub stands in for the bush prop, a tile obstacle: 87 rather than the
# lab's 66 gives it the Blender bush's footprint (about 80 x 68 world px).
# Sprite pixels per world pixel (the Blender trees have about 3.1).
DENSITY = 3.0
# Three variants per key, as many as the original drew: one painting at
# three sizes (the lab varies them 0.87-1.12); beech and oak share tree_oak,
# beech the more common, as in the lab.
VARIANTS = {
    "tree_pine": [("pine", 1.0), ("pine", 0.9), ("pine", 1.1)],
    "tree_oak": [("beech", 1.0), ("oak", 1.0), ("beech", 0.9)],
    "bush": [("shrub", 1.0), ("shrub", 0.85), ("shrub", 1.15)],
}
# The paintings' own colour: the game draws trees untinted (the lab grades
# them darker for its textured ground).
TINT = np.array([1.0, 1.0, 1.0], dtype=np.float32)
# Shadow alpha as the game draws it for trees and other props; its skew
# (ctx.transform(1, 0, -0.75, -0.32)); a soft edge in sprite pixels.
SHADOW = {"tree": 0.2, "shrub": 0.16}
SKEW_X, SKEW_Y = 0.75, 0.32
SHADOW_BLUR = 2.5
PAD = 8


def cut(path, anchor, world_h, shadow):
    """The painting keyed, tinted and scaled, over its cast shadow; returns
    the sprite and its root anchor."""
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
    fg, a = key(rgb)
    fg = np.clip(fg * TINT, 0, 255)
    h, w = a.shape
    r = DENSITY * world_h / h
    rgba = np.dstack([fg, a * 255]).round().astype(np.uint8)
    tree = premul_resize(Image.fromarray(rgba, "RGBA"), (round(w * r), round(h * r)))
    rx, ry = anchor[0] * tree.width, anchor[1] * tree.height
    x0, y0, x1, y1 = tree.getchannel("A").point(lambda v: 255 if v > 2 else 0).getbbox()
    # Where the shadow of the tree's corners falls, relative to the root.
    sx = [(x - rx) - SKEW_X * (y - ry) for x in (x0, x1) for y in (y0, y1)]
    sy = [-SKEW_Y * (y - ry) for y in (y0, y1)]
    left = min(x0 - rx, *sx) - PAD
    right = max(x1 - rx, *sx) + PAD
    top = min(y0 - ry, *sy) - PAD
    bottom = max(y1 - ry, *sy) + PAD
    cw, ch = int(np.ceil(right - left)), int(np.ceil(bottom - top))
    # Canvas pixel (X, Y) lies at (X + left, Y + top) from the root; the
    # point whose shadow falls there lies at dy = -sy / 0.32, dx = sx + 0.75 dy.
    k = SKEW_X / SKEW_Y
    sil = tree.getchannel("A").transform(
        (cw, ch), Image.AFFINE,
        (1.0, -k, rx + left - k * top, 0.0, -1.0 / SKEW_Y, ry - top / SKEW_Y),
        resample=Image.BILINEAR)
    sil = sil.filter(ImageFilter.GaussianBlur(SHADOW_BLUR))
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    canvas.putalpha(sil.point(lambda v: round(v * shadow)))
    canvas.alpha_composite(tree, (round(-left - rx), round(-top - ry)))
    ax = round(-left - rx) + rx
    ay = round(-top - ry) + ry
    return canvas, round(ax, 1), round(ay, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default="assets/terrain/woodland")
    ap.add_argument("--out", default="assets/sprites/painted")
    ap.add_argument("--manifest")
    ap.add_argument("--review")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    cuts, sources = {}, {"tint": TINT.tolist(), "density": DENSITY, "paintings": {}}
    for name, (file, anchor, world_h) in SOURCES.items():
        path = os.path.join(args.src, file)
        img, ax, ay = cut(path, anchor, world_h, SHADOW["shrub" if name == "shrub" else "tree"])
        out = os.path.join(args.out, f"woodland_{name}.webp")
        img.save(out, "WEBP", quality=92, alpha_quality=100, method=6)
        cuts[name] = (out, img, ax, ay, world_h)
        sources["paintings"][name] = {"file": file, "sha256": hashlib.sha256(open(path, "rb").read()).hexdigest(),
                                      "anchor": list(anchor), "worldHeight": world_h}
    entries = {}
    for k, variants in VARIANTS.items():
        entries[k] = []
        for name, size in variants:
            out, img, ax, ay, _ = cuts[name]
            entries[k].append({"file": "res://" + out.replace(os.sep, "/"), "ax": ax, "ay": ay,
                               "scale": round(size / DENSITY, 4), "w": img.width, "h": img.height,
                               "noShadow": True, "art": True})
    sources["variants"] = {k: [list(v) for v in vs] for k, vs in VARIANTS.items()}
    with open(os.path.join(args.out, "woodland_sources.json"), "w", newline="\n") as f:
        json.dump(sources, f, indent=1)
    if args.review:
        os.makedirs(args.review, exist_ok=True)
        for bg_name, bg in (("grass", (92, 120, 52)), ("grey", (128, 128, 128))):
            imgs = [c[1] for c in cuts.values()]
            tw = sum(i.width for i in imgs) + 20 * (len(imgs) + 1)
            th = max(i.height for i in imgs) + 40
            board = Image.new("RGBA", (tw, th), bg + (255,))
            x = 20
            for i in imgs:
                board.alpha_composite(i, (x, th - 20 - i.height))
                x += i.width + 20
            board.convert("RGB").save(os.path.join(args.review, f"woodland_cutout_{bg_name}.png"))
    if args.manifest:
        write_manifest(args.manifest, entries)
    print(json.dumps(entries, indent=1))


if __name__ == "__main__":
    main()
