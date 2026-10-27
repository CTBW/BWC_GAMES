"""Cut the painted woodland out for the game's tree, bush, fern, stump and log sprites.

The paintings in assets/terrain/woodland stand on magenta; the terrain lab
keys them in its shader (scripts/render/woodland_kit.gd). For the battlefield
they become plain RGBA sprites: keyed like the painted rocks
(rock_cutout.key), given the cast shadow the game draws for props (the
silhouette skewed down and to the right, where the paintings' light throws it)
and written as WebP at three sprite pixels per world pixel. Their light is painted from the upper left, so they carry their
own shadow (noShadow) and the game never mirrors them.

Terrain kit 2 (Higgsfield, 2026-10-24; Workspace "Terrain kit 2") adds more
trees, and stumps and logs cut from one sheet. Its originals stay out of Git
in local/workspace-originals, like the rock sheet; woodland_sources.json
records their hashes. Each is graded towards the summer battlefield's
woodland (GRADE): the same olive foliage and grey-brown bark as the pine,
beech and oak. Trees whose colour belongs to another season get their own keys
(tree_oak_autumn, tree_oak_spring) and are not placed yet; the copper beech is
also a rare summer accent among tree_oak's variants.

    python tools/props/woodland_cutout.py [--src assets/terrain/woodland]
        [--kit DIR] [--out assets/sprites/painted] [--manifest assets/sprites.json]
        [--review DIR]

Prints the sprites.json entries; with --manifest, writes them over the
tree_pine, tree_oak, bush and fern keys (adding the seasonal trees after
them) and over stump and log (adding deadwood after them), and leaves every
other key as it was. Then run tools/import.sh. The sprites' .import files
generate mipmaps, like the Blender trees': a re-run keeps them, a new sprite
needs it set.
"""

import argparse
import hashlib
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rock_cutout import key, premul_resize, write_manifest  # noqa: E402

KIT = "../../../../local/workspace-originals/2026-10-20_meridius/terrain-kit-2/originals"
# Root anchors (fractions of the painting) and the world height of the whole
# painting, as woodland_kit.gd places them in the terrain lab; for kit 2, the
# tree's height above its root is the number in the comment.
SOURCES = {
    "pine": ("lab", "tree_pine__take-01.png", (0.52, 0.94), 350.0),
    "beech": ("lab", "tree_beech__take-01.png", (0.50, 0.94), 310.0),
    "oak": ("lab", "tree_oak__take-02.png", (0.51, 0.92), 285.0),
    "shrub": ("lab", "bush_green__take-01.png", (0.46, 0.89), 87.0),
    "fern": ("lab", "undergrowth_ferns__take-01.png", (0.52, 0.88), 44.0),
    "birch": ("kit", "tree_birch__take-02.png", (0.52, 0.92), 292.0),  # 255
    "oak_young": ("kit", "tree_young_oak__take-01.png", (0.522, 0.923), 196.0),  # 160
    "spruce": ("kit", "tree_spruce__take-01.png", (0.497, 0.971), 317.0),  # 300
    "scots_pine": ("kit", "tree_scots_pine__take-01.png", (0.402, 0.95), 350.0),  # 313
    "fir_young": ("kit", "tree_fir_small__take-01.png", (0.503, 0.92), 168.0),  # 150
    "maple_red": ("kit", "tree_maple_red__take-01.png", (0.501, 0.928), 287.0),  # 246
    "aspen_gold": ("kit", "tree_aspen_gold__take-01.png", (0.509, 0.946), 296.0),  # 270
    "copper_beech": ("kit", "tree_copper_beech__take-02.png", (0.508, 0.927), 297.0),  # 255
    "blossom": ("kit", "tree_blossom__take-01.png", (0.49, 0.895), 247.0),  # 210
}
# The shrub stands in for the bush prop, a tile obstacle: 87 rather than the
# lab's 66 gives it the Blender bush's footprint (about 80 x 68 world px).
# The fern is no prop of the original: battle_draw.gd strews it over forest
# tiles for show, at the lab's size.
# Stumps and logs: one sheet of eight, each piece found by the box (sheet
# pixels) that holds its centre, with its width in world px. Upright pieces
# cast the trees' shadow; flat ones a contact shadow on the ground. A tile is
# 128 world px wide: the Blender stump was about 70, a log stays within one.
# DROP: a slate-grey cast shadow painted beside the mossy log, outside its
# outline (sheet pixels).
SHEET = ("kit", "trunks_sheet__take-02.png")
PIECES = {
    "log_fallen": ((72, 80, 1960, 1728), 135.0, "flat"),
    "log_hollow": ((1584, 216, 2912, 1552), 110.0, "flat"),
    "stump_old": ((2792, 376, 4312, 1496), 95.0, "upright"),
    "log_stack": ((4264, 312, 5344, 1256), 95.0, "flat"),
    "log_mossy": ((288, 1936, 1488, 2800), 85.0, "flat"),
    "stump_sawn": ((1640, 2000, 2560, 2840), 70.0, "upright"),
    "branch": ((2784, 1728, 4256, 2808), 90.0, "flat"),
    "stump_rotten": ((4208, 1744, 5336, 2896), 80.0, "upright"),
}
DROP = [(1350, 2255), (1600, 2255), (1600, 2750), (1120, 2750), (1100, 2600), (1100, 2497), (1200, 2447),
        (1300, 2387), (1338, 2340), (1352, 2300)]
# Sprite pixels per world pixel (the Blender trees have about 3.1).
DENSITY = 3.0
# Variants per key: tree_oak and tree_pine draw one in len() by the tile's
# variant number, so the counts weight them. The summer battlefield's trees:
# beech and oak five times over at slightly different sizes, birch four times,
# young oak twice and one copper beech in 17 for a rare dark red accent; pine
# three times as common as Scots pine and young fir, spruce twice. The weeping
# willow of terrain kit 2 is left out (the owner's call): its two places went
# to an oak and a beech, so every other tile keeps its tree.
VARIANTS = {
    "tree_pine": [("pine", 1.0), ("pine", 0.9), ("pine", 1.1), ("spruce", 1.0), ("scots_pine", 1.0),
                  ("fir_young", 1.0), ("spruce", 0.9)],
    "tree_oak": [("beech", 1.0), ("oak", 1.0), ("beech", 0.9), ("birch", 1.0), ("oak", 0.9),
                 ("oak_young", 1.0), ("birch", 0.9), ("oak", 1.1),
                 ("beech", 1.05), ("oak", 0.95), ("beech", 0.95), ("birch", 1.05), ("beech", 1.1),
                 ("oak_young", 1.1), ("birch", 0.95), ("oak", 1.05), ("copper_beech", 1.0)],
    "bush": [("shrub", 1.0), ("shrub", 0.85), ("shrub", 1.15)],
    "fern": [("fern", 1.0), ("fern", 0.85), ("fern", 1.2)],
    # Other seasons: red and gold leaves read as autumn on the green ground
    # (the copper beech's dark red also stands in summer, rarely); blossom is
    # spring.
    "tree_oak_autumn": [("maple_red", 1.0), ("aspen_gold", 1.0), ("copper_beech", 1.0)],
    "tree_oak_spring": [("blossom", 1.0), ("blossom", 0.9)],
}
GROUND_VARIANTS = {
    "stump": [("stump_old", 1.0), ("stump_sawn", 1.0), ("stump_rotten", 1.0)],
    "log": [("log_fallen", 1.0), ("log_hollow", 1.0), ("log_mossy", 1.0), ("log_stack", 1.0)],
    # Fallen wood at the foot of trees, for show (battle_draw.gd): the logs
    # small enough to stay on the tree's tile.
    "deadwood": [("branch", 1.0), ("log_mossy", 0.65), ("branch", 0.8), ("log_fallen", 0.6), ("log_hollow", 0.65)],
}
# The paintings' own colour: the game draws trees untinted (the lab grades
# them darker for its textured ground).
TINT = np.array([1.0, 1.0, 1.0], dtype=np.float32)
# Grades towards the summer woodland, in CIELAB, for foliage (hues 50-205)
# and bark (hues 5-50): (L scale, a scale, b scale, b shift, b shift in the
# light). The pine, beech and oak foliage averages L 28-40, b 4-24, khaki
# where lit and teal in shade; their bark L 33-45, a 5-18, b 16-24. The
# birch's leaves are lighter and limier, the spruce's and Scots pine's blue
# even where lit, the Scots pine's bark orange, the sheet's wood more orange
# and its moss limier. "vivid": the fungus keeps its colour.
GRADE = {
    "birch": {"foliage": (0.8, 0.7, 0.8, 0.0, 0.0)},
    "oak_young": {"foliage": (0.93, 1.0, 1.0, 0.0, 0.0)},
    "spruce": {"foliage": (1.0, 1.0, 1.0, 4.0, 14.0)},
    "scots_pine": {"foliage": (1.0, 1.0, 1.0, 4.0, 14.0), "bark": (0.92, 0.5, 0.8, 0.0, 0.0)},
    "sheet": {"foliage": (0.9, 1.0, 0.65, 0.0, 0.0), "bark": (0.87, 0.55, 0.8, 0.0, 0.0), "vivid": True},
}
# Shadow alpha as the game draws it for trees and other props (the fern's as
# the lab draws it); its skew (ctx.transform(1, 0, -0.75, -0.32)); a soft edge
# in sprite pixels.
SHADOW = {"tree": 0.2, "shrub": 0.16, "fern": 0.12, "upright": 0.16, "flat": 0.3}
SKEW_X, SKEW_Y = 0.75, 0.32
SHADOW_BLUR = 2.5
PAD = 8

_M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]], dtype=np.float32)
_WHITE = np.array([0.9505, 1.0, 1.089], dtype=np.float32)


def to_lab(rgb):
    c = rgb / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    xyz = c @ _M.T / _WHITE
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def from_lab(lab):
    fy = (lab[..., 0] + 16) / 116
    f = np.stack([fy + lab[..., 1] / 500, fy, fy - lab[..., 2] / 200], -1)
    xyz = np.where(f > 0.2069, f ** 3, (f - 16 / 116) / 7.787) * _WHITE
    c = xyz @ np.linalg.inv(_M).T
    c = np.where(c > 0.0031308, 1.055 * np.clip(c, 0, None) ** (1 / 2.4) - 0.055, 12.92 * c)
    return np.clip(c * 255.0, 0, 255)


def band(x, lo, hi, soft):
    """1 inside [lo, hi], easing to 0 over `soft` outside it."""
    return np.clip((x - lo + soft) / soft, 0, 1) * np.clip((hi + soft - x) / soft, 0, 1)


def grade(fg, g):
    """Move the foliage and bark towards the woodland's colours (GRADE)."""
    mx, mn = fg.max(-1), fg.min(-1)
    d = mx - mn + 1e-6
    r, gr, b = fg[..., 0], fg[..., 1], fg[..., 2]
    hue = np.where(mx == r, ((gr - b) / d) % 6, np.where(mx == gr, (b - r) / d + 2, (r - gr) / d + 4)) * 60
    s = d / np.maximum(mx, 1e-3)
    sat = np.clip((s - 0.1) / 0.15, 0, 1)
    lab = to_lab(fg)
    for part, lo, hi in (("foliage", 57, 198), ("bark", 10, 45)):
        if part not in g:
            continue
        kl, ka, kb, db, lit = g[part]
        w = band(hue, lo, hi, 8) * sat
        if part == "bark" and g.get("vivid"):
            # Not the vivid accents (fungus): wood is never that pure.
            w *= np.clip((0.8 - s) / 0.1, 0, 1)
        light = np.clip((lab[..., 0] - 22) / 25, 0, 1)
        lab[..., 0] *= 1 + (kl - 1) * w
        lab[..., 1] *= 1 + (ka - 1) * w
        lab[..., 2] = lab[..., 2] * (1 + (kb - 1) * w) + (db + lit * light) * w
    return from_lab(lab)


def no_cast_shadow(rgb, a):
    """Shadows painted onto the backdrop (darker magenta) are not the prop.
    Only broad patches count: a prop's own soft edge over magenta is as dark
    but a few pixels thin."""
    mx = rgb.max(-1)
    magenta = (np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1]) > 0.35 * mx
    shade = Image.fromarray(((magenta & (mx < 215) & (a < 0.98)) * 255).astype(np.uint8))
    shade = shade.filter(ImageFilter.MinFilter(15)).filter(ImageFilter.MaxFilter(21))
    return np.where(np.asarray(shade) > 0, 0.0, a)


def skewed_shadow(tree, rx, ry, shadow):
    """The canvas with the sprite over its cast shadow, and the root's place in
    it: the silhouette skewed down and to the right like the game's."""
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
    return canvas, round(-left - rx) + rx, round(-top - ry) + ry


def contact_shadow(piece, shadow):
    """A piece lying on the ground: its own mask, nudged down and to the
    right and softened, beneath it."""
    w, h = piece.size
    dx, dy, blur = round(w * 0.04), round(w * 0.05), w * 0.03
    pad = PAD + round(blur * 2)
    canvas = Image.new("RGBA", (w + dx + 2 * pad, h + dy + 2 * pad), (0, 0, 0, 0))
    sil = Image.new("L", canvas.size, 0)
    sil.paste(piece.getchannel("A"), (pad + dx, pad + dy))
    sil = sil.filter(ImageFilter.GaussianBlur(blur))
    canvas.putalpha(sil.point(lambda v: round(v * shadow)))
    canvas.alpha_composite(piece, (pad, pad))
    return canvas, pad


def cut(path, anchor, world_h, shadow, g=None):
    """The painting keyed, tinted and scaled, over its cast shadow; returns
    the sprite and its root anchor."""
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
    fg, a = key(rgb)
    fg = np.clip(fg * TINT, 0, 255)
    if g:
        fg = grade(fg, g)
    h, w = a.shape
    r = DENSITY * world_h / h
    rgba = np.dstack([fg, a * 255]).round().astype(np.uint8)
    tree = premul_resize(Image.fromarray(rgba, "RGBA"), (round(w * r), round(h * r)))
    canvas, ax, ay = skewed_shadow(tree, anchor[0] * tree.width, anchor[1] * tree.height, shadow)
    return canvas, round(ax, 1), round(ay, 1)


def pieces(path):
    """The sheet's pieces: keyed, cast shadows dropped, each piece the parts
    whose centre lies in its box (connected at a quarter of the resolution)."""
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
    fg, a = key(rgb)
    a = no_cast_shadow(rgb, a)
    drop = Image.new("L", (a.shape[1], a.shape[0]), 0)
    ImageDraw.Draw(drop).polygon(DROP, fill=255)
    a = np.where(np.asarray(drop) > 0, 0.0, a)
    fg = grade(np.clip(fg * TINT, 0, 255), GRADE["sheet"])
    step = 4
    m = a[::step, ::step] > 0.02
    sh, sw = m.shape
    label = np.full((sh, sw), -1, dtype=np.int32)
    names = list(PIECES)
    for sy, sx in zip(*np.nonzero(m)):
        if label[sy, sx] != -1:
            continue
        stack, pts = [(sy, sx)], []
        label[sy, sx] = -2
        while stack:
            y, x = stack.pop()
            pts.append((y, x))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < sh and 0 <= nx < sw and m[ny, nx] and label[ny, nx] == -1:
                    label[ny, nx] = -2
                    stack.append((ny, nx))
        py, px = np.array(pts).T
        cy, cx = py.mean() * step, px.mean() * step
        owner = next((i for i, n in enumerate(names)
                      if PIECES[n][0][0] <= cx < PIECES[n][0][2] and PIECES[n][0][1] <= cy < PIECES[n][0][3]), -3)
        label[py, px] = owner
    full = np.repeat(np.repeat(label, step, axis=0), step, axis=1)[:a.shape[0], :a.shape[1]]
    out = {}
    for i, n in enumerate(names):
        pa = np.where(full == i, a, 0.0)
        ys, xs = np.nonzero(pa > 0.5)
        x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
        out[n] = Image.fromarray(np.dstack([fg, pa * 255.0])[y0:y1, x0:x1].round().astype(np.uint8), "RGBA")
    return out


def cut_piece(img, width, kind):
    """A stump or log at its world width, over its shadow, and its anchor: an
    upright piece's root is the middle of its base; a flat piece's is the
    middle of its footprint, a little below its centre."""
    k = DENSITY * width / img.width
    piece = premul_resize(img, (round(img.width * k), max(1, round(img.height * k))))
    w, h = piece.size
    al = np.asarray(piece.getchannel("A"), dtype=np.float32) / 255.0
    if kind == "upright":
        rows = al[round(h * 0.82):]
        rx = float((rows.sum(axis=0) * np.arange(w)).sum() / max(rows.sum(), 1e-6))
        canvas, ax, ay = skewed_shadow(piece, rx, h - 0.06 * w, SHADOW["upright"])
    else:
        canvas, pad = contact_shadow(piece, SHADOW["flat"])
        ys, xs = np.nonzero(al > 0.5)
        ax, ay = pad + float(xs.mean()), pad + float(ys.mean()) + 0.08 * w
    return canvas, round(ax, 1), round(ay, 1)


def entry(out, img, ax, ay, size):
    return {"file": "res://" + out.replace(os.sep, "/"), "ax": ax, "ay": ay,
            "scale": round(size / DENSITY, 4), "w": img.width, "h": img.height,
            "noShadow": True, "art": True}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default="assets/terrain/woodland")
    ap.add_argument("--kit", default=KIT)
    ap.add_argument("--out", default="assets/sprites/painted")
    ap.add_argument("--manifest")
    ap.add_argument("--review")
    args = ap.parse_args()
    roots = {"lab": args.src, "kit": args.kit}
    os.makedirs(args.out, exist_ok=True)
    cuts, sources = {}, {"tint": TINT.tolist(), "density": DENSITY, "grade": GRADE, "paintings": {}}

    def record(name, path, **kw):
        sources["paintings"][name] = {"file": os.path.basename(path),
                                      "sha256": hashlib.sha256(open(path, "rb").read()).hexdigest(), **kw}

    for name, (root, file, anchor, world_h) in SOURCES.items():
        path = os.path.join(roots[root], file)
        img, ax, ay = cut(path, anchor, world_h, SHADOW.get(name, SHADOW["tree"]), GRADE.get(name))
        out = os.path.join(args.out, f"woodland_{name}.webp")
        img.save(out, "WEBP", quality=92, alpha_quality=100, method=6)
        cuts[name] = (out, img, ax, ay)
        record(name, path, anchor=list(anchor), worldHeight=world_h)
    sheet = os.path.join(roots[SHEET[0]], SHEET[1])
    for name, img in pieces(sheet).items():
        box, width, kind = PIECES[name]
        img, ax, ay = cut_piece(img, width, kind)
        out = os.path.join(args.out, f"woodland_{name}.webp")
        img.save(out, "WEBP", quality=92, alpha_quality=100, method=6)
        cuts[name] = (out, img, ax, ay)
    record("sheet", sheet, pieces={n: {"box": list(b), "worldWidth": wd, "kind": kd} for n, (b, wd, kd) in PIECES.items()})
    groups = []
    for variants in (VARIANTS, GROUND_VARIANTS):
        entries = {}
        for k, vs in variants.items():
            entries[k] = [entry(cuts[n][0], cuts[n][1], cuts[n][2], cuts[n][3], size) for n, size in vs]
        groups.append(entries)
    sources["variants"] = {k: [list(v) for v in vs] for k, vs in {**VARIANTS, **GROUND_VARIANTS}.items()}
    with open(os.path.join(args.out, "woodland_sources.json"), "w", newline="\n") as f:
        json.dump(sources, f, indent=1)
    if args.review:
        os.makedirs(args.review, exist_ok=True)
        for bg_name, bg in (("grass", (92, 120, 52)), ("grey", (128, 128, 128))):
            imgs = [c[1].resize((c[1].width // 2, c[1].height // 2), Image.LANCZOS) for c in cuts.values()]
            tw = sum(i.width for i in imgs) + 20 * (len(imgs) + 1)
            th = max(i.height for i in imgs) + 40
            board = Image.new("RGBA", (tw, th), bg + (255,))
            x = 20
            for i in imgs:
                board.alpha_composite(i, (x, th - 20 - i.height))
                x += i.width + 20
            board.convert("RGB").save(os.path.join(args.review, f"woodland_cutout_{bg_name}.png"))
    if args.manifest:
        for entries in groups:
            write_manifest(args.manifest, entries)
    print(json.dumps({**groups[0], **groups[1]}, indent=1))


if __name__ == "__main__":
    main()
