"""Cut the painted rock props out of a generated sheet on magenta.

The sheet holds two rows of four props: "stones" on top, "boulders" below.
Each cell is keyed against the magenta background (alpha from how far a
pixel's red and blue stand above its green, colour unmixed from the
background), given a soft contact shadow falling down and to the right like
the props' painted light, scaled to its in-game size and written as WebP.
With --texture (the terrain's assets/terrain/rock.webp), the stone takes that
texture's colour and grain under the painted light, outline and moss.

    python tools/props/rock_cutout.py SHEET [--out assets/sprites/painted]
        [--texture assets/terrain/rock.webp] [--manifest assets/sprites.json]
        [--review DIR]
    python tools/props/rock_cutout.py --stones STONES_SHEET [the same options]

Prints the sprites.json entries for rock_small and rock_large; with
--manifest, writes them over those two keys and leaves every other key as it
was. With --stones, cuts terrain kit 2's sheet of small stones (two rows of
five) into the `stones` key instead, which battle_draw.gd strews over open
ground for show, and adds it after rock_small. Then run tools/import.sh.
"""

import argparse
import hashlib
import json
import os

import numpy as np
from PIL import Image, ImageFilter

# In-game widths of the rock itself (not its shadow) in sprite pixels; drawn
# at scale 0.5, a stones prop is about two thirds of a tile (128 px) wide and
# a boulder about a whole tile.
WIDTH = {"rock_small": 170, "rock_large": 270}
SCALE = 0.5
# The small stones in world px (sprite px at SCALE 0.5 are twice that), in the
# sheet's reading order: flat stone, river stones, leaning stone, pebbles,
# moss stone; split stone, cairn, standing stone, slate shards, moss and
# flowers. Small beside a squad of figures about 60 px tall.
STONES = [50, 45, 40, 42, 45, 48, 34, 30, 42, 38]
# The terrain texture on the rock: 2.6 sprite pixels per texture pixel, so a
# boulder face shows one slab's surface rather than the ground's rubble; grain
# finer than 3.5 px at 0.7 strength; the texture's colour (blurred 4 px) at
# 0.65; its value moved 70% of the way from the painted stone's.
TEX_DENSITY, TEX_GRAIN, TEX_DETAIL, TEX_SOFT, TEX_TINT, TEX_VALUE = 2.6, 3.5, 0.7, 4, 0.65, 0.7


def key(rgb):
    """Alpha and unmixed colour for a sheet on magenta."""
    spill = np.clip(np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1], 0, None)
    bg = spill > 120
    m = np.median(rgb[bg], axis=0)
    s_bg = float(np.median(spill[bg]))
    a = np.clip(1.0 - (spill - 12.0) / (s_bg * 0.85 - 12.0), 0.0, 1.0)
    a[a < 0.04] = 0.0
    safe = np.maximum(a, 0.05)[..., None]
    fg = (rgb - (1.0 - a[..., None]) * m) / safe
    # What magenta is left in a fringe goes too.
    s2 = np.clip(np.minimum(fg[..., 0], fg[..., 2]) - fg[..., 1], 0, None)
    fg[..., 0] -= s2
    fg[..., 2] -= s2
    return np.clip(fg, 0, 255), a


def premul_resize(rgba, size):
    """Resize RGBA without dark fringes (premultiplied while filtering)."""
    arr = np.asarray(rgba, dtype=np.float32)
    arr[..., :3] *= arr[..., 3:4] / 255.0
    small = np.asarray(Image.fromarray(arr.round().astype(np.uint8), "RGBA").resize(size, Image.LANCZOS), dtype=np.float32)
    al = small[..., 3:4] / 255.0
    small[..., :3] = np.where(al > 0.004, small[..., :3] / np.maximum(al, 0.004), 0)
    return Image.fromarray(np.clip(small, 0, 255).round().astype(np.uint8), "RGBA")


def lum(c):
    return c[..., 0] * 0.299 + c[..., 1] * 0.587 + c[..., 2] * 0.114


def blur(arr, r):
    """Gaussian blur of an RGB float array (0-1)."""
    im = Image.fromarray((np.clip(arr, 0, 1) * 255).round().astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r)), dtype=np.float32) / 255.0


def bare_stone(tex):
    """The texture without its grass tufts and lichen: bright, saturated
    yellow and green strokes filled from the stone around them."""
    t = np.asarray(tex, dtype=np.float32) / 255.0
    mx, mn = t.max(axis=-1), t.min(axis=-1)
    sat = (mx - mn) / np.maximum(mx, 0.02)
    m = ((sat > 0.24) & (mx > 0.3) & (t[..., 2] < np.minimum(t[..., 0], t[..., 1]) * 0.85)).astype(np.float32)
    m = np.clip(blur(np.repeat(m[..., None], 3, -1), 1.2)[..., :1] * 3, 0, 1)
    keep = 1 - m
    cover = blur(np.repeat(keep, 3, -1), 7)
    fill = np.where(cover > 0.3, blur(t * keep, 7) / np.maximum(cover, 0.05), t[keep[..., 0] > 0.5].mean(axis=0))
    return Image.fromarray((np.clip(t * keep + fill * m, 0, 1) * 255).round().astype(np.uint8))


def retexture(rock, tex, cell):
    """The terrain's stone under the painted light: the painted shapes, light,
    outline and moss stay; the stone takes the texture's colour and grain."""
    arr = np.asarray(rock, dtype=np.float32) / 255.0
    rgb, a = arr[..., :3], arr[..., 3]
    h, w = a.shape
    # The texture tiled at its density, a different window for each prop.
    big = tex.resize((round(tex.width * TEX_DENSITY), round(tex.height * TEX_DENSITY)), Image.LANCZOS)
    tiled = Image.new("RGB", (big.width * (w // big.width + 2), big.height * (h // big.height + 2)))
    for i in range(0, tiled.width, big.width):
        for j in range(0, tiled.height, big.height):
            tiled.paste(big, (i, j))
    ox, oy = (cell * 397) % big.width, (cell * 241) % big.height
    t = np.asarray(tiled.crop((ox, oy, ox + w, oy + h)), dtype=np.float32) / 255.0
    grain = np.clip(lum(t) / np.maximum(lum(blur(t, TEX_GRAIN)), 0.02), 0.4, 1.8)
    soft = blur(t, TEX_SOFT)
    tint = soft / np.maximum(lum(soft)[..., None], 0.02)
    whole = np.asarray(tex, dtype=np.float32) / 255.0
    wl = lum(whole)
    t_alb = whole[wl > np.percentile(wl, 40)].mean(axis=0)
    # Moss and grass keep their painted colour; so does the dark outline.
    pl = lum(rgb)
    green = rgb[..., 1] - np.maximum(rgb[..., 0], rgb[..., 2])
    moss = np.clip(blur(np.repeat(np.clip((green - 0.01) / 0.05, 0, 1)[..., None], 3, -1), 1.5)[..., 0] * 1.4, 0, 1)
    p_alb = rgb[(a > 0.9) & (moss < 0.1) & (pl > 0.3)].mean(axis=0)
    # The painted light's warm and cool shifts stay; the stone's own colour
    # becomes the texture's, and its value moves part of the way.
    v = lum(t_alb) / lum(p_alb)
    out = rgb * (t_alb / p_alb) / v * v ** TEX_VALUE
    edge = np.clip((pl - 0.16) / 0.2, 0, 1)[..., None]
    out = out * (1 + (grain[..., None] ** TEX_DETAIL * (tint / (t_alb / lum(t_alb))) ** TEX_TINT - 1) * edge)
    arr[..., :3] = np.clip(out * (1 - moss[..., None]) + rgb * moss[..., None], 0, 1)
    return Image.fromarray((arr * 255).round().astype(np.uint8), "RGBA")


def owners(a, cols, rows, step=4):
    """Which cell each pixel's piece belongs to: pieces (connected at a
    quarter of the resolution) go to the cell holding their centre, so a prop
    reaching over a cell's edge stays whole and leaves its neighbour alone."""
    m = a[::step, ::step] > 0.02
    h, w = m.shape
    label = np.full((h, w), -1, dtype=np.int32)
    for sy, sx in zip(*np.nonzero(m)):
        if label[sy, sx] >= 0:
            continue
        stack, pts = [(sy, sx)], []
        label[sy, sx] = 0
        while stack:
            y, x = stack.pop()
            pts.append((y, x))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and label[ny, nx] < 0:
                    label[ny, nx] = 0
                    stack.append((ny, nx))
        py, px = np.array(pts).T
        cell = min(int(py.mean() * rows / h), rows - 1) * cols + min(int(px.mean() * cols / w), cols - 1)
        label[py, px] = cell
    full = np.repeat(np.repeat(label, step, axis=0), step, axis=1)
    return full[:a.shape[0], :a.shape[1]]


def cut(rgb, a, own, cell, width, tex=None):
    ca = np.where(own == cell, a, 0.0)
    ys, xs = np.nonzero(ca > 0.5)
    bx0, bx1, by0, by1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    rock = np.dstack([rgb, ca * 255.0])[by0:by1, bx0:bx1]
    rock = Image.fromarray(rock.round().astype(np.uint8), "RGBA")
    k = width / rock.width
    rock = premul_resize(rock, (width, max(1, round(rock.height * k))))
    if tex is not None:
        rock = retexture(rock, tex, cell)
    w, h = rock.size
    # Contact shadow: the rock's own mask, flattened onto the ground and
    # pushed down and to the right, soft at its edge.
    pad_r, pad_b, pad = round(w * 0.18), round(h * 0.12), 6
    canvas = Image.new("RGBA", (w + pad_r + 2 * pad, h + pad_b + 2 * pad), (0, 0, 0, 0))
    mask = rock.getchannel("A")
    sh_h = max(1, round(h * 0.32))
    flat = mask.resize((w, sh_h), Image.LANCZOS)
    shadow = Image.new("L", canvas.size, 0)
    shadow.paste(flat, (pad + round(w * 0.1), pad + h - round(sh_h * 0.72)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(w * 0.035))
    shadow = shadow.point(lambda v: round(v * 0.42))
    dark = Image.new("RGBA", canvas.size, (28, 34, 30, 0))
    dark.putalpha(shadow)
    canvas = Image.alpha_composite(canvas, dark)
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    layer.paste(rock, (pad, pad))
    canvas = Image.alpha_composite(canvas, layer)
    # The anchor: the middle of the rock's footprint, a little above its base.
    ra = np.asarray(mask, dtype=np.float32) / 255.0
    rows = ra[round(h * 0.8):]
    ax = pad + float((rows.sum(axis=0) * np.arange(w)).sum() / max(rows.sum(), 1e-6))
    ay = pad + h - 0.12 * w
    return canvas, round(ax, 1), round(ay, 1)


def write_manifest(path, entries):
    """Replace the entries' keys in sprites.json as text, so the rest of the
    file keeps its bytes; the keys must stand next to each other. Keys the
    file lacks are added after them."""
    text = open(path, encoding="utf-8", newline="").read()
    nl = "\r\n" if "\r\n" in text else "\n"
    doc = json.loads(text)
    keys = list(doc)
    old = [k for k in entries if k in doc]
    added = [k for k in entries if k not in doc]
    first = min(keys.index(k) for k in old)
    at = first + len(old)
    assert sorted(keys.index(k) for k in old) == list(range(first, at)), "keys not adjacent"
    start = text.index(f"{nl} {json.dumps(keys[first])}: [") + len(nl)
    end = text.index(f"{nl} {json.dumps(keys[at])}: [") + len(nl)
    out = ""
    for k in keys[first:at] + added:
        lines = json.dumps(entries[k], indent=1, ensure_ascii=False).split("\n")
        out += f" {json.dumps(k)}: {lines[0]}{nl}" + nl.join(" " + l for l in lines[1:]) + "," + nl
    new = text[:start] + out + text[end:]
    new_doc = json.loads(new)
    assert list(new_doc) == keys[:at] + added + keys[at:]
    assert all(new_doc[k] == doc[k] for k in keys if k not in entries)
    open(path, "w", encoding="utf-8", newline="").write(new)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet", nargs="?")
    ap.add_argument("--stones")
    ap.add_argument("--out", default="assets/sprites/painted")
    ap.add_argument("--texture")
    ap.add_argument("--manifest")
    ap.add_argument("--review")
    args = ap.parse_args()
    if args.stones:
        cut_stones(args)
        return
    src = Image.open(args.sheet).convert("RGB")
    rgb = np.asarray(src, dtype=np.float32)
    fg, a = key(rgb)
    own = owners(a, 4, 2)
    tex = bare_stone(Image.open(args.texture).convert("RGB")) if args.texture else None
    os.makedirs(args.out, exist_ok=True)
    entries = {"rock_small": [], "rock_large": []}
    sources = {"sheet": os.path.basename(args.sheet), "sha256": hashlib.sha256(open(args.sheet, "rb").read()).hexdigest(),
               "cells": "2 rows x 4: rock_small 0-3, rock_large 0-3"}
    if args.texture:
        sources["texture"] = {"file": args.texture.replace(os.sep, "/"),
                              "sha256": hashlib.sha256(open(args.texture, "rb").read()).hexdigest()}
    cells = []
    for row, name in enumerate(["rock_small", "rock_large"]):
        for col in range(4):
            img, ax, ay = cut(fg, a, own, row * 4 + col, WIDTH[name], tex)
            i = len(entries[name])
            path = os.path.join(args.out, f"{name}_{i}.webp")
            img.save(path, "WEBP", quality=92, alpha_quality=100, method=6)
            entries[name].append({"file": "res://" + path.replace(os.sep, "/"), "ax": ax, "ay": ay, "scale": SCALE,
                                  "w": img.width, "h": img.height, "noShadow": True, "art": True})
            cells.append(img)
    with open(os.path.join(args.out, "rocks_sources.json"), "w", newline="\n") as f:
        json.dump(sources, f, indent=1)
    if args.review:
        os.makedirs(args.review, exist_ok=True)
        for bg_name, bg in (("grass", (92, 120, 52)), ("grey", (128, 128, 128))):
            tw = sum(c.width for c in cells) + 20 * (len(cells) + 1)
            th = max(c.height for c in cells) + 40
            board = Image.new("RGBA", (tw, th), bg + (255,))
            x = 20
            for c in cells:
                board.alpha_composite(c, (x, th - 20 - c.height))
                x += c.width + 20
            board.convert("RGB").save(os.path.join(args.review, f"rocks_cutout_{bg_name}.png"))
    if args.manifest:
        write_manifest(args.manifest, entries)
    print(json.dumps(entries, indent=1))


def cut_stones(args):
    """The small stones: two rows of five, retextured like the rocks."""
    rgb = np.asarray(Image.open(args.stones).convert("RGB"), dtype=np.float32)
    fg, a = key(rgb)
    own = owners(a, 5, 2)
    tex = bare_stone(Image.open(args.texture).convert("RGB")) if args.texture else None
    os.makedirs(args.out, exist_ok=True)
    stones, cells = [], []
    for cell, width in enumerate(STONES):
        img, ax, ay = cut(fg, a, own, cell, round(width / SCALE), tex)
        path = os.path.join(args.out, f"stones_{cell}.webp")
        img.save(path, "WEBP", quality=92, alpha_quality=100, method=6)
        stones.append({"file": "res://" + path.replace(os.sep, "/"), "ax": ax, "ay": ay, "scale": SCALE,
                       "w": img.width, "h": img.height, "noShadow": True, "art": True})
        cells.append(img)
    sources = {"sheet": os.path.basename(args.stones), "sha256": hashlib.sha256(open(args.stones, "rb").read()).hexdigest(),
               "cells": "2 rows x 5: stones 0-9", "widths": STONES}
    if args.texture:
        sources["texture"] = {"file": args.texture.replace(os.sep, "/"),
                              "sha256": hashlib.sha256(open(args.texture, "rb").read()).hexdigest()}
    with open(os.path.join(args.out, "stones_sources.json"), "w", newline="\n") as f:
        json.dump(sources, f, indent=1)
    if args.review:
        os.makedirs(args.review, exist_ok=True)
        tw = sum(c.width for c in cells) + 20 * (len(cells) + 1)
        board = Image.new("RGBA", (tw, max(c.height for c in cells) + 40), (92, 120, 52, 255))
        x = 20
        for c in cells:
            board.alpha_composite(c, (x, board.height - 20 - c.height))
            x += c.width + 20
        board.convert("RGB").save(os.path.join(args.review, "stones_cutout.png"))
    if args.manifest:
        # The rock keys as they are, so `stones` lands after them.
        doc = json.load(open(args.manifest, encoding="utf-8"))
        write_manifest(args.manifest, {"rock_large": doc["rock_large"], "rock_small": doc["rock_small"], "stones": stones})
    print(json.dumps({"stones": stones}, indent=1))


if __name__ == "__main__":
    main()
