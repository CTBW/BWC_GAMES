"""Leg rigs for the back views: a figure walking away from the camera.

The back-view walk keys the generator drew barely move their legs, and the
mirrored-leg key cut the hems apart (art/squads/<unit>/b, bs). So on the march
away from the camera the game draws the standing figure as a small mesh and
walks its legs itself (scripts/render/soldier_anim.gd legs(), battle_draw
_blit_rig): above the hips the body is carried whole; below them each side
follows its own foot, the planted one held on the ground and the other swung
forward and lifted, the hem and the boot together, as cloth over a leg moves.

All a figure needs for that is where its feet stand and the seam between them.
measure() finds them in the figure's lowest rows: the boots are the solid
blobs there (thin ones are a spear butt or a blade's tip, not feet).

    python -I tools/anim/rig.py <unit> [b|bs] [--sheet out.png]

prints the measures and with --sheet draws them over the figures for review.
squadgen's build stores them with the standing back-view frames ("rig").
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

# The band the feet are looked for in, as a share of the figure's height.
BAND = 0.075
# Narrower blobs in it are no feet (source px).
MIN_FOOT = 5


def measure(img, ax, ay):
    """{"seam", "feet": [left, right], "span": [left, right]} in source px from
    the anchor (x - ax) for a standing figure, or None when it has no feet."""
    a = img[..., 3] > 128
    ys = np.nonzero(a.any(axis=1))[0]
    if not len(ys):
        return None
    top, bottom = int(ys[0]), int(ys[-1])
    h = bottom - top + 1
    band = a.copy()
    band[: int(bottom - BAND * h)] = False
    lab, n = ndimage.label(band)
    blobs = []
    for i in range(1, n + 1):
        yy, xx = np.nonzero(lab == i)
        if xx.max() - xx.min() + 1 < MIN_FOOT:
            continue
        # Feet stand under the body: a blob far off the anchor is something carried.
        if abs(xx.mean() - ax) > 0.45 * h:
            continue
        blobs.append((len(xx), float(xx.min()), float(xx.max()), float(xx.mean())))
    if not blobs:
        return None
    blobs = sorted(sorted(blobs, reverse=True)[:2], key=lambda b: b[3])
    if len(blobs) == 2 and blobs[1][1] > blobs[0][2]:
        l, r = blobs
        seam = (l[2] + r[1]) / 2
        feet = [l[3], r[3]]
        span = [l[1], r[2]]
    else:
        # The feet touch (or a robe hides one): split the blob down its middle.
        lo = min(b[1] for b in blobs)
        hi = max(b[2] for b in blobs)
        seam = (lo + hi) / 2
        feet = [(lo + seam) / 2, (seam + hi) / 2]
        span = [lo, hi]
    rel = lambda x: round(float(x - ax), 1)
    return {"seam": rel(seam), "feet": [rel(f) for f in feet], "span": [rel(s) for s in span]}


def _sheet(unit, fac, path):
    import squadgen
    n = squadgen.count(unit)
    index = squadgen.load_json(squadgen.sdir(unit, fac, "index.json"), {})
    tiles = []
    for s in range(n):
        e = index.get(f"base_{s}")
        if e is None:
            continue
        im = Image.open(squadgen.sdir(unit, fac, f"base_{s}.png")).convert("RGBA")
        r = measure(np.array(im), e["ax"], e["ay"])
        print(f"{unit} {fac} {s}:", r)
        bg = Image.new("RGBA", im.size, (90, 120, 70, 255))
        bg.alpha_composite(im)
        if r:
            d = ImageDraw.Draw(bg)
            x = e["ax"] + r["seam"]
            d.line([(x, 0), (x, im.size[1])], fill=(255, 255, 0, 255))
            for f in r["feet"]:
                d.ellipse([e["ax"] + f - 2, e["ay"] - 2, e["ax"] + f + 2, e["ay"] + 2], fill=(255, 0, 0, 255))
            for sp in r["span"]:
                d.line([(e["ax"] + sp, im.size[1] - 12), (e["ax"] + sp, im.size[1])], fill=(0, 255, 255, 255))
        tiles.append(bg)
    if tiles:
        w = sum(t.size[0] for t in tiles)
        h = max(t.size[1] for t in tiles)
        out = Image.new("RGBA", (w, h), (90, 120, 70, 255))
        x = 0
        for t in tiles:
            out.alpha_composite(t, (x, h - t.size[1]))
            x += t.size[0]
        out.resize((w * 2, h * 2), Image.NEAREST).save(path)


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    sheet = sys.argv[sys.argv.index("--sheet") + 1] if "--sheet" in sys.argv else None
    unit = args[0]
    fac = args[1] if len(args) > 1 else "b"
    if sheet:
        _sheet(unit, fac, sheet)
    else:
        import squadgen
        index = squadgen.load_json(squadgen.sdir(unit, fac, "index.json"), {})
        for s in range(squadgen.count(unit)):
            e = index.get(f"base_{s}")
            if e:
                im = np.array(Image.open(squadgen.sdir(unit, fac, f"base_{s}.png")).convert("RGBA"))
                print(s, measure(im, e["ax"], e["ay"]))
