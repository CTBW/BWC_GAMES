"""Pixel-art squads for the battle view: from generated sheets to game frames.

The footman route (knowledge/higgsfield-setup.md, tools/anim/build_footman.py)
for every figure type in tools/anim/units.py. Per type and facing, one 2K sheet
holds the squad's six (or three, or four) individuals, one per grid cell:

  base     standing, the reference every other sheet of the facing is an edit of
  walk_a, walk_b   the two contact steps (each foot forward)
  wind, hit        the attack's anticipation and its blow (or shot, or spell)
  kneel            struck down, sinking to the knees (front and back facings)
  down / slump     lying dead (front) / slumped (back), an edit of the kneeling
                   frames re-laid with room to fall

Facings: f (front, true south-west) and b (back, true north-east); shield types
also fs and bs, drawn as true south-east and north-west and stored mirrored
(the game mirrors them back; battle_view.pose_key).

Commands (run with the art venv: ../game/.venv-art/Scripts/python.exe -I):
  refs <unit>                       reference sheets to upload (art/raw/<unit>/ref_*.png)
  prompt <unit> <fac> <frame>       the prompt, aspect ratio and input files, in order
  mirror <unit> <fac>               input for fs (from f) or bs (from b): the base mirrored
  cut <unit> <fac> <frame> <raw> [--keep-y] [--split x0,y0,x1,y1]...
                                    cut a generated sheet into registered soldiers
  relay <unit> <fac>                lay the kneeling frames out with room to fall (input for down/slump)
  status <unit>                     which frames exist
  build <unit> [--review DIR]       assets/sprites/anim/<unit>.png and .json for soldier_anim.gd

Raw sheets and inputs: art/raw/<unit>/ (not committed). Cut frames, the
editable masters: art/squads/<unit>/<fac>/<frame>_<soldier>.png with index.json.
"""
import argparse
import hashlib
import json
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pixel import block_median, cut_out  # noqa: E402
from units import UNITS, facings  # noqa: E402
import prompts  # noqa: E402
import legs  # noqa: E402
import rig as legrig  # noqa: E402

GODOT = os.path.normpath(os.path.join(HERE, "..", ".."))
REFS = os.path.normpath(os.path.join(GODOT, "..", "..", "references", "characters"))
FOOTMAN = os.path.normpath(os.path.join(GODOT, "..", "game", "art", "sprites", "footman_anim"))
RAW = os.path.join(GODOT, "art", "raw")
SQUADS = os.path.join(GODOT, "art", "squads")
OUT_DIR = os.path.join(GODOT, "assets", "sprites", "anim")
K = 4  # raw pixels per pixel-art pixel
BG = (200, 200, 200)
CANVAS = {"1:1": (2048, 2048), "16:9": (2752, 1536), "3:2": (2508, 1672)}
MIN_PART = 150  # native pixels; smaller loose parts are specks
FRAMES = ["base", "walk_a", "walk_b", "wind", "hit", "kneel", "down", "slump"]
RELAY_CELL = 900  # raw pixels per cell of a falling sheet
RELAY_BASE = 230  # raw pixels from a falling cell's bottom to the kneeling feet
ATLAS_W = 4096
PAD = 3


def udir(unit, *p):
    return os.path.join(RAW, unit, *p)


def sdir(unit, fac, *p):
    return os.path.join(SQUADS, unit, fac, *p)


def count(unit):
    c, r = UNITS[unit]["grid"]
    return c * r


def load_json(path, default=None):
    if not os.path.exists(path):
        return default
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=1)
        f.write("\n")


# ---------------------------------------------------------------- references

def _cells(unit, size):
    cols, rows = UNITS[unit]["grid"]
    w, h = size
    cw, ch = w // cols, h // rows
    return [(c * cw, r * ch, cw, ch) for r in range(rows) for c in range(cols)]


def _sheet(unit, figures, size, foot=0.1):
    """Figures (PIL RGBA, already at raw scale, with feet anchor) laid one per cell."""
    canvas = Image.new("RGBA", size, BG + (255,))
    for (x, y, cw, ch), (im, ax, ay) in zip(_cells(unit, size), figures):
        fx, fy = x + cw // 2, y + ch - int(ch * foot)
        canvas.alpha_composite(im, (int(fx - ax), int(fy - ay)))
    return canvas.convert("RGB")


ENGINE_STATES = ["idle_f", "atk_f", "idle_b", "atk_b"]


def _engine_refs(unit):
    """The war machine's four drawings (ready and loosing, front and back), 2 x 2."""
    u = UNITS[unit]
    size = CANVAS[u["aspect"]]
    spr = load_json(os.path.join(GODOT, "assets", "sprites.json"))
    figs = []
    for st in ENGINE_STATES:
        e = spr[f"{unit}_{st}"][0]
        im = Image.open(e["file"].replace("res://", GODOT + "/")).convert("RGBA")
        x, y, w, h = e["region"]
        im = im.crop((x, y, x + w, y + h))
        k = min(size[0] / 2 * 0.86 / w, size[1] / 2 * 0.8 / h)
        figs.append((im.resize((round(w * k), round(h * k)), Image.LANCZOS), w * k / 2, e["ay"] * k))
    _sheet(unit, figs, size, foot=0.12).save(udir(unit, "ref_game_e.png"))


def cmd_refs(unit):
    u = UNITS[unit]
    n = count(unit)
    size = CANVAS[u["aspect"]]
    os.makedirs(udir(unit), exist_ok=True)
    if u.get("kind") == "engine":
        _engine_refs(unit)
        man = load_json(os.path.join(FOOTMAN, "sprites.json"))["sprites"]
        figs = []
        for s in range(6):
            e = man["footman_idle_f_00"][s]
            im = Image.open(os.path.join(FOOTMAN, e["file"])).convert("RGBA")
            figs.append((im.resize((im.width * K, im.height * K), Image.NEAREST), im.width * K / 2, e["ay"] * K))
        cols, rows = 3, 2
        canvas = Image.new("RGBA", (2048, 2048), BG + (255,))
        for s, (im, ax, ay) in enumerate(figs):
            canvas.alpha_composite(im, (int((s % 3) * 682 + 341 - ax), int((s // 3) * 1024 + 920 - ay)))
        canvas.convert("RGB").save(udir(unit, "ref_style_f.png"))
        print(f"{unit}: engine refs in {udir(unit)}")
        return
    # Style and layout: the finished footmen, at the art's own pixel size.
    man = load_json(os.path.join(FOOTMAN, "sprites.json"))["sprites"]
    for fac in ("f", "b"):
        figs = []
        for s in range(n):
            e = man[f"footman_idle_{fac}_00"][s % 6]
            im = Image.open(os.path.join(FOOTMAN, e["file"])).convert("RGBA")
            # Centred in its cell by width, so a raised blade stays inside it.
            figs.append((im.resize((im.width * K, im.height * K), Image.NEAREST), im.width * K / 2, e["ay"] * K))
        _sheet(unit, figs, size).save(udir(unit, f"ref_style_{fac}.png"))
    # Design: the unit as the game draws it now.
    spr = load_json(os.path.join(GODOT, "assets", "sprites.json"))
    atlases = {}
    for fac in ("f", "b"):
        key = f"{unit}_idle_{fac}"
        figs = []
        for s in range(n):
            e = spr[key][s % len(spr[key])]
            path = e["file"].replace("res://", GODOT + "/")
            if path not in atlases:
                atlases[path] = Image.open(path).convert("RGBA")
            x, y, w, h = e["region"]
            im = atlases[path].crop((x, y, x + w, y + h))
            a = np.array(im)[..., 3] > 128
            top = np.nonzero(a.any(axis=1))[0][0]
            k = u["height"] * K / max(1, e["ay"] - top)
            figs.append((im.resize((round(w * k), round(h * k)), Image.LANCZOS), e["ax"] * k, e["ay"] * k))
        _sheet(unit, figs, size).save(udir(unit, f"ref_game_{fac}.png"))
    print(f"{unit}: refs in {udir(unit)} ({size[0]}x{size[1]}, {n} figures)")


def cmd_prompt(unit, fac, frame):
    u = UNITS[unit]
    if u.get("kind") == "engine":
        text = prompts.engine(unit)
        inputs = [udir(unit, "ref_game_e.png"), udir(unit, "ref_style_f.png")]
    elif fac == "f" and frame == "base":
        text = prompts.base_front(unit)
        inputs = [udir(unit, "ref_style_f.png"), udir(unit, "ref_game_f.png")]
        if u["sheet"]:
            inputs.append(os.path.join(REFS, u["sheet"]))
        if u.get("kin"):
            inputs.append(udir(u["kin"], "f_base.png"))
    elif fac == "b" and frame == "base_t":
        text = prompts.base_back_turned(unit)
        inputs = [udir(unit, "f_base.png"), os.path.join(RAW, "_refs", "angle_n.png"), os.path.join(RAW, "_refs", "angle_w.png")]
    elif fac == "b" and frame == "base_l":
        text = prompts.base_back_left(unit)
        inputs = [udir(unit, "f_base.png")]
    elif fac == "b" and frame == "base":
        text = prompts.base_back(unit)
        inputs = [udir(unit, "f_base.png"), udir(unit, "ref_style_b.png")]
    elif frame == "base":
        text = prompts.swap_hands(unit, fac)
        inputs = [udir(unit, f"in_{fac}_swap.png")]
    elif frame in ("down", "slump"):
        text = prompts.action(unit, fac, frame)
        inputs = [udir(unit, f"in_{fac}_{frame}.png")]
    elif frame == "clean":
        text = prompts.clean(unit)
        inputs = [udir(unit, f"{fac}_base.png")]
    elif frame == "walk_b":
        text = prompts.swap_legs(unit, fac)
        inputs = [udir(unit, f"{fac}_walk_a.png")]
    else:
        text = prompts.action(unit, fac, frame)
        inputs = [udir(unit, f"{fac}_base.png")]
    aspect = _relay_aspect(unit) if frame in ("down", "slump") else u["aspect"]
    print(json.dumps({"unit": unit, "facing": fac, "frame": frame, "aspect": aspect, "resolution": "2k",
                      "inputs": inputs, "out": udir(unit, f"{fac}_{frame}.png"), "prompt": text}, indent=1))


def cmd_mirror(unit, fac):
    src = {"fs": "f", "bs": "b"}[fac]
    Image.open(udir(unit, f"{src}_base.png")).transpose(Image.FLIP_LEFT_RIGHT).save(udir(unit, f"in_{fac}_swap.png"))
    print(f"{unit}: in_{fac}_swap.png from {src}_base.png")


# ---------------------------------------------------------------- cutting

def _native(raw_path, size=None):
    raw = Image.open(raw_path).convert("RGB")
    if size is not None and raw.size != tuple(size):
        raw = raw.resize(tuple(size), Image.LANCZOS)
    a = np.array(raw)
    small = block_median(a, K)
    out, _, _ = cut_out(small, shadows=False)
    return small, out


def _parts(out, splits=()):
    solid = out[..., 3] == 255
    joined = ndimage.binary_dilation(solid, iterations=2)
    for x0, y0, x1, y1 in splits:
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for t in np.linspace(0, 1, n * 2):
            joined[int(round(y0 + (y1 - y0) * t)), int(round(x0 + (x1 - x0) * t))] = False
    labels, n = ndimage.label(joined)
    labels[~solid] = 0
    sizes = ndimage.sum(solid, labels, range(1, n + 1))
    return solid, labels, sizes


def _foot_x(m):
    ys = np.nonzero(m.any(axis=1))[0]
    feet = m[max(0, ys[-1] - 8): ys[-1] + 1]
    return float(np.nonzero(feet)[1].mean())


def _figure_masks(solid, labels, sizes, centres):
    """One mask per slot: each part goes to the slot whose centre is nearest;
    a part that spans two slots (a blade touching a neighbour) is split between
    them pixel by pixel."""
    n = len(centres)
    cxy = np.array(centres, dtype=float)
    H, W = solid.shape
    yy, xx = np.mgrid[0:H, 0:W]
    masks = [np.zeros_like(solid) for _ in range(n)]
    for j, size in enumerate(sizes, start=1):
        if size < MIN_PART:
            continue
        part = labels == j
        ys, xs = np.nonzero(part)
        d = (xs[:, None] - cxy[None, :, 0]) ** 2 + ((ys[:, None] - cxy[None, :, 1]) * 0.8) ** 2
        own = d.argmin(axis=1)
        counts = np.bincount(own, minlength=n)
        if (counts > 0.2 * counts.sum()).sum() >= 2:
            for k in range(n):
                masks[k][ys[own == k], xs[own == k]] = True
        else:
            masks[int(np.bincount(own).argmax())] |= part
    return masks


def _no_ground_line(m):
    """Drop a drawn ground line or streak under the feet: rows near the bottom
    whose pixels belong to no vertical run of three (a sole is thicker)."""
    if not m.any():
        return m
    ys = np.nonzero(m.any(axis=1))[0]
    lo = max(0, ys[-1] - 5)
    band = m[lo:].copy()
    kept = ndimage.binary_opening(np.pad(band, ((2, 2), (0, 0))), structure=np.ones((3, 1)))[2:-2]
    out = m.copy()
    out[lo:] = band & kept
    return out


def _attached(m, reach=10, share=0.12):
    """The figure's main body and what belongs to it: parts within `reach` px of
    it or at least `share` of its size (a weapon lying beside a body). Specks and
    smears the generator left floating nearby are dropped."""
    lab, n = ndimage.label(m, structure=np.ones((3, 3)))
    if n <= 1:
        return m
    sizes = ndimage.sum(m, lab, range(1, n + 1))
    main = lab == (int(np.argmax(sizes)) + 1)
    near = ndimage.binary_dilation(main, iterations=reach)
    keep = main.copy()
    for i, size in enumerate(sizes, start=1):
        part = lab == i
        if (part & near).any() or size >= share * sizes.max():
            keep |= part
    return keep


def cmd_cut(unit, fac, frame, raw_path, keep_y=False, splits=()):
    n = count(unit)
    index_path = sdir(unit, fac, "index.json")
    index = load_json(index_path, {})
    if frame == "base":
        small, out = _native(raw_path)
        solid, labels, sizes = _parts(out, splits)
        order = np.argsort(-sizes)[:n] + 1
        if len(order) < n or sizes[order[-1] - 1] < 0.25 * sizes[order[0] - 1]:
            raise SystemExit(f"expected {n} figures; sizes {sorted(sizes.astype(int), reverse=True)[:n + 2]}")
        boxes = []
        for j in order:
            ys, xs = np.nonzero(labels == j)
            boxes.append(((ys.min() + ys.max()) / 2, (xs.min() + xs.max()) / 2, j))
        cols, rows = UNITS[unit]["grid"]
        boxes.sort()
        grid = []
        for r in range(rows):
            grid += sorted(boxes[r * cols:(r + 1) * cols], key=lambda b: b[1])
        centres = [(b[1], b[0]) for b in grid]
        masks = _figure_masks(solid, labels, sizes, centres)
        slots = []
        for m in masks:
            ys, xs = np.nonzero(m)
            slots.append({"ax": round(_foot_x(m), 1), "ay": int(ys.max()), "cx": float(xs.mean()), "cy": float(ys.mean()),
                          "top": int(ys.min()), "h": int(ys.max() - ys.min() + 1)})
        save_json(sdir(unit, fac, "slots.json"), {"size": list(Image.open(raw_path).size), "slots": slots})
        anchor_slots = slots
    else:
        meta = load_json(sdir(unit, fac, "relay.json" if frame in ("down", "slump") else "slots.json"))
        if meta is None:
            raise SystemExit("cut the base sheet first" if frame not in ("down", "slump") else "run relay first")
        small, out = _native(raw_path, meta["size"])
        solid, labels, sizes = _parts(out, splits)
        anchor_slots = meta["slots"]
        masks = _figure_masks(solid, labels, sizes, [(s["cx"], s["cy"]) for s in anchor_slots])
    os.makedirs(sdir(unit, fac), exist_ok=True)
    masks = [_attached(_no_ground_line(m)) for m in masks]
    for s, (m, slot) in enumerate(zip(masks, anchor_slots)):
        if not m.any():
            raise SystemExit(f"slot {s} is empty: the figures touch or one is missing; add --split lines")
        ys, xs = np.nonzero(m)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        rgba = np.dstack([small[y0:y1, x0:x1], np.where(m[y0:y1, x0:x1], 255, 0).astype(np.uint8)])
        # Standing frames keep their feet on the base's ground line (edits drift a few pixels).
        drift = int(y1 - 1 - slot["ay"])
        dy = 0 if (keep_y or frame in ("kneel", "down", "slump") or abs(drift) > 24) else -drift
        name = f"{frame}_{s}"
        Image.fromarray(rgba, "RGBA").save(sdir(unit, fac, f"{name}.png"))
        index[name] = {"ax": round(slot["ax"] - x0, 1), "ay": int(slot["ay"] - (y0 + dy)), "h": int(y1 - y0)}
        print(f"{unit} {fac} {name}: {x1 - x0}x{y1 - y0}, drift {drift}")
    save_json(index_path, index)


def _relay_aspect(unit):
    cols, rows = UNITS[unit]["grid"]
    return "16:9" if rows == 1 else ("1:1" if cols == rows else "3:2")


def cmd_relay(unit, fac, src="kneel"):
    """Lay the kneeling frames out with room to fall, as the input for down/slump,
    on a canvas of the aspect the sheet is generated at."""
    cols, rows = UNITS[unit]["grid"]
    w = cols * RELAY_CELL
    size = (w, round(w * {"16:9": 9 / 16, "1:1": 1.0, "3:2": 2 / 3}[_relay_aspect(unit)]))
    index = load_json(sdir(unit, fac, "index.json"), {})
    canvas = Image.new("RGB", size, BG)
    slots = []
    for s in range(count(unit)):
        e = index[f"{src}_{s}"]
        im = Image.open(sdir(unit, fac, f"{src}_{s}.png")).convert("RGBA")
        im = im.resize((im.width * K, im.height * K), Image.NEAREST)
        c, r = s % cols, s // cols
        cell_h = size[1] // rows
        fx, fy = c * RELAY_CELL + RELAY_CELL // 2, r * cell_h + cell_h - RELAY_BASE
        canvas.paste(im, (int(fx - e["ax"] * K), int(fy - e["ay"] * K)), im)
        slots.append({"ax": fx / K, "ay": fy / K, "cx": fx / K, "cy": fy / K - 30, "top": 0, "h": 0})
    for frame in ("down", "slump"):
        canvas.save(udir(unit, f"in_{fac}_{frame}.png"))
    save_json(sdir(unit, fac, "relay.json"), {"size": list(size), "slots": slots})
    print(f"{unit} {fac}: relay sheet {size[0]}x{size[1]}")


def cmd_recut(unit):
    """Cut every raw sheet of the unit again (base first; falls only where their
    re-laid input exists), e.g. after an index lost entries."""
    for fac in facings(unit):
        for frame in FRAMES:
            raw = udir(unit, f"{fac}_{frame}.png")
            if not os.path.exists(raw) or frame == "walk_b":
                continue
            if frame in ("down", "slump") and not os.path.exists(sdir(unit, fac, "relay.json")):
                continue
            try:
                cmd_cut(unit, fac, frame, raw)
            except SystemExit as e:
                print(f"{unit} {fac}:{frame}: cut failed: {e}")


def cmd_status(unit):
    for fac in facings(unit):
        index = load_json(sdir(unit, fac, "index.json"), {})
        have = sorted({k.rsplit("_", 1)[0] for k in index})
        raws = [f for f in FRAMES if os.path.exists(udir(unit, f"{fac}_{f}.png"))]
        print(f"{unit} {fac}: cut {have}; raw {raws}")


# ---------------------------------------------------------------- build

CHEST = 0.42  # breathing rows drop at this fraction of the height, from the top


def _breathe(rgba, p):
    if p == 0:
        return rgba
    seam = int(rgba.shape[0] * CHEST)
    out = np.zeros_like(rgba)
    out[seam:] = rgba[seam:]
    out[p: seam + p] = np.where(rgba[:seam, :, 3:] > 0, rgba[:seam], out[p: seam + p])
    return out


def _grade_skin(rgba, sat):
    """Lift green skin tones to saturation `sat` (hue kept, other colours untouched):
    the sage-green goblin sheets read as grey at battle zoom on grass."""
    rgb = rgba[..., :3].astype(np.float32) / 255.0
    mx, mn = rgb.max(axis=2), rgb.min(axis=2)
    d = mx - mn
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    dd = np.maximum(d, 1e-6)
    h = np.where(mx == r, ((g - b) / dd) % 6, np.where(mx == g, (b - r) / dd + 2, (r - g) / dd + 4)) / 6
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0)
    skin = (rgba[..., 3] > 0) & (h > 0.17) & (h < 0.45) & (s > 0.1) & (s < sat) & (mx > 0.12)
    if not skin.any():
        return rgba
    # Scale the chroma around the value, so shading and highlights keep their order.
    k = np.where(skin, sat / np.maximum(s, 1e-6), 1.0)[..., None]
    k = np.minimum(k, 1.8)
    v = mx[..., None]
    out = rgba.copy()
    out[..., :3] = np.clip((v - (v - rgb) * k) * 255.0 + 0.5, 0, 255).astype(np.uint8)
    return out


def _palette(images, colors=64):
    px = np.concatenate([im[im[..., 3] > 0][:, :3] for im in images])
    side = int(math.ceil(math.sqrt(len(px))))
    pad = np.zeros((side * side, 3), np.uint8)
    pad[: len(px)] = px
    pad[len(px):] = px[0]
    return Image.fromarray(pad.reshape(side, side, 3)).quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)


def _to_palette(rgba, pal):
    out = rgba.copy()
    q = Image.fromarray(np.ascontiguousarray(rgba[..., :3])).quantize(palette=pal, dither=Image.Dither.NONE)
    out[..., :3] = np.array(q.convert("RGB"))
    return out


def _game_height(unit):
    """World px of the drawn figure this one replaces (opaque height × its scale)."""
    spr = load_json(os.path.join(GODOT, "assets", "sprites.json"))
    hs = []
    for e in spr[f"{unit}_idle_f"]:
        path = e["file"].replace("res://", GODOT + "/")
        im = np.array(Image.open(path).convert("RGBA"))
        x, y, w, h = e["region"]
        rows = np.nonzero((im[y:y + h, x:x + w, 3] > 128).any(axis=1))[0]
        hs.append((e["ay"] - rows[0]) * e["scale"])
    return float(np.median(hs))


def _build_engine(unit):
    """A war machine's four states as frames idle_f, atk_f, idle_b, atk_b (one variant)."""
    index = load_json(sdir(unit, "e", "index.json"), {})
    frames = {}
    for s, st in enumerate(ENGINE_STATES):
        e = index[f"base_{s}"]
        frames[st] = [(np.array(Image.open(sdir(unit, "e", f"base_{s}.png")).convert("RGBA")), e["ax"], e["ay"])]
    pal = _palette([im for v in frames.values() for im, _, _ in v])
    frames = {k: [(_to_palette(im, pal), ax, ay) for im, ax, ay in v] for k, v in frames.items()}
    scale = _game_height(unit) / float(frames["idle_f"][0][2])
    atlas, table, uniq = _pack(frames)
    Image.fromarray(atlas).save(os.path.join(OUT_DIR, f"{unit}.png"), optimize=True)
    _import_settings(os.path.join(OUT_DIR, f"{unit}.png"))
    save_json(os.path.join(OUT_DIR, f"{unit}.json"), {
        "source": f"art/squads/{unit} (Higgsfield sheet), built by tools/anim/squadgen.py",
        "file": f"res://assets/sprites/anim/{unit}.png", "scale": round(scale, 5), "soldiers": 1,
        "facings": ["f", "b"], "engine": True, "frames": table})
    print(f"{unit}: engine, {uniq} images, scale {scale:.5f}")


def cmd_build(unit, review=None):
    if UNITS[unit].get("kind") == "engine":
        _build_engine(unit)
        return
    n = count(unit)
    facs = facings(unit)
    frames = {}  # name -> [(rgba, ax, ay)] per soldier
    heights = {}

    def raw(fac, frame, s):
        index = load_json(sdir(unit, fac, "index.json"), {})
        e = index.get(f"{frame}_{s}")
        if e is None:
            return None
        im = np.array(Image.open(sdir(unit, fac, f"{frame}_{s}.png")).convert("RGBA"))
        if UNITS[unit].get("skin_sat"):
            im = _grade_skin(im, UNITS[unit]["skin_sat"])
        return (im, e["ax"], e["ay"])

    # One palette for the unit, from its standing figures; every frame is mapped
    # to it as it loads (the leg colours below are exact palette colours).
    stands = [raw(fac, "base", s) for fac in facs for s in range(n)]
    if any(b is None for b in stands):
        raise SystemExit(f"{unit}: base frames missing")
    pal = _palette([im for im, _, _ in stands])

    def load(fac, frame, s):
        f = raw(fac, frame, s)
        return None if f is None else (_to_palette(f[0], pal), f[1], f[2])

    for fac in facs:
        base = [load(fac, "base", s) for s in range(n)]
        heights[fac] = float(np.median([b[2] for b in base]))
        get = lambda frame: [load(fac, frame, s) or base[s] for s in range(n)]
        for i, p in enumerate((0, 1, 2)):
            frames[f"idle_{fac}_{i}"] = [(_breathe(b[0], p), b[1], b[2]) for b in base]
        # The walk: the generator leads with the same leg whatever it is asked, so
        # both contacts and the passing step share the step frame's upper body and
        # only the legs change (tools/anim/legs.py).
        cols = legs.leg_colours(base)
        walk = [[], [], []]
        for s, step in enumerate(get("walk_a")):
            if step is base[s]:
                keys = [(base[s][0], base[s][1], base[s][2])] * 3
            else:
                (cs, ci), (cx, cy) = _common([step, base[s]])
                keys = [(k, cx, cy) for k in legs.walk_keys_any(cs, ci, cx, cy, cols)]
            for i in range(3):
                walk[i].append(keys[i])
        for i in range(3):
            frames[f"walk_{fac}_{i}"] = walk[i]
        frames[f"strike_{fac}_wind"] = get("wind")
        frames[f"strike_{fac}_hit"] = get("hit")
    for fac in ("f", "b"):
        frames[f"death_{fac}_kneel"] = [load(fac, "kneel", s) or frames[f"idle_{fac}_0"][s] for s in range(n)]
        last = "down" if fac == "f" else "slump"
        frames[f"death_{fac}_down"] = [load(fac, last, s) or frames[f"death_{fac}_kneel"][s] for s in range(n)]
    # The drawn south-east and north-west are stored mirrored (the game mirrors them back).
    for name in list(frames):
        if "_fs_" in name or "_bs_" in name or name.endswith("_fs") or name.endswith("_bs"):
            frames[name] = [(im[:, ::-1].copy(), im.shape[1] - ax, ay) for im, ax, ay in frames[name]]
    # A height relative to another figure (goblins: two thirds of an orc warrior), else the figure it replaces.
    rel = UNITS[unit].get("rel")
    target = _game_height(rel[0]) * rel[1] if rel else _game_height(unit)
    scale = target / heights["f"]
    atlas, table, uniq = _pack(frames)
    # Where the feet stand in the standing back views: walking away from the
    # camera, the game walks the legs itself (tools/anim/rig.py).
    for fac in ("b", "bs"):
        name = f"idle_{fac}_0"
        for i, (im, ax, ay) in enumerate(frames.get(name, [])):
            r = legrig.measure(im, ax, ay)
            if r:
                table[name][i]["rig"] = r
    # Each facing drawn a little larger or smaller than the front is brought to its height.
    for name, entries in table.items():
        fac = name.split("_")[1]
        k = heights["f"] / heights.get(fac, heights["f"])
        if abs(k - 1) > 0.01:
            for e in entries:
                e["k"] = round(k, 4)
    os.makedirs(OUT_DIR, exist_ok=True)
    Image.fromarray(atlas).save(os.path.join(OUT_DIR, f"{unit}.png"), optimize=True)
    _import_settings(os.path.join(OUT_DIR, f"{unit}.png"))
    save_json(os.path.join(OUT_DIR, f"{unit}.json"), {
        "source": f"art/squads/{unit} (Higgsfield sheets), built by tools/anim/squadgen.py",
        "file": f"res://assets/sprites/anim/{unit}.png", "scale": round(scale, 5), "soldiers": n,
        "facings": facs, "frames": table})
    print(f"{unit}: {len(table)} frames x {n}, {uniq} images, atlas {atlas.shape[1]}x{atlas.shape[0]}, scale {scale:.5f}, heights {heights}")
    if review:
        _review(unit, frames, review, scale)


def _import_settings(png):
    """Godot import settings for a new atlas: lossless with mipmaps, like the
    figure atlases (soldiers draw at about a quarter of their pixels). Godot
    keeps these [params] when it imports the file (tools/import.sh)."""
    path = png + ".import"
    if os.path.exists(path):
        return
    lines = ["[remap]", "", 'importer="texture"', 'type="CompressedTexture2D"', "", "[params]", "",
             "compress/mode=0", "mipmaps/generate=true", "mipmaps/limit=-1", "process/fix_alpha_border=true",
             "process/premult_alpha=false", "detect_3d/compress_to=0", ""]
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def _common(figs):
    """Figures (rgba, ax, ay) placed on one canvas at one anchor: ([canvas...], (cx, cy))."""
    left = int(math.ceil(max(ax for _, ax, _ in figs))) + 4
    right = int(math.ceil(max(im.shape[1] - ax for im, ax, _ in figs))) + 4
    up = int(math.ceil(max(ay for _, _, ay in figs))) + 4
    down = int(math.ceil(max(im.shape[0] - ay for im, _, ay in figs))) + 4
    out = []
    for im, ax, ay in figs:
        c = np.zeros((up + down, left + right, 4), np.uint8)
        x, y = int(round(left - ax)), int(round(up - ay))
        c[y:y + im.shape[0], x:x + im.shape[1]] = im
        out.append(c)
    return out, (left, up)


def _pack(frames):
    unique, refs = {}, {}
    for name, per in frames.items():
        refs[name] = []
        for im, ax, ay in per:
            a = im[..., 3] > 0
            ys, xs = np.nonzero(a.any(axis=1))[0], np.nonzero(a.any(axis=0))[0]
            t = im[ys[0]:ys[-1] + 1, xs[0]:xs[-1] + 1]
            h = hashlib.sha1(t.tobytes() + bytes(str(t.shape), "ascii")).hexdigest()
            unique.setdefault(h, t)
            refs[name].append((h, round(float(ax - xs[0]), 1), round(float(ay - ys[0]), 1)))
    order = sorted(unique, key=lambda h: (-unique[h].shape[0], -unique[h].shape[1]))
    pos, x, y, row = {}, PAD, PAD, 0
    for h in order:
        t = unique[h]
        if x + t.shape[1] + PAD > ATLAS_W:
            x, y, row = PAD, y + row + PAD, 0
        pos[h] = (x, y)
        x += t.shape[1] + PAD
        row = max(row, t.shape[0])
    height = 1 << max(8, math.ceil(math.log2(y + row + PAD)))
    atlas = np.zeros((height, ATLAS_W, 4), np.uint8)
    for h, (px, py) in pos.items():
        t = unique[h]
        atlas[py:py + t.shape[0], px:px + t.shape[1]] = t
    table = {name: [{"region": [pos[h][0], pos[h][1], unique[h].shape[1], unique[h].shape[0]], "ax": ax, "ay": ay} for h, ax, ay in rs]
             for name, rs in refs.items()}
    return atlas, table, len(unique)


def _review(unit, frames, out_dir, scale):
    os.makedirs(out_dir, exist_ok=True)
    seqs = {}
    for fac in facings(unit):
        seqs[f"walk_{fac}"] = [f"walk_{fac}_{i}" for i in (0, 1, 2, 1)]
        seqs[f"strike_{fac}"] = [f"idle_{fac}_0", f"strike_{fac}_wind", f"strike_{fac}_hit"]
    for fac in ("f", "b"):
        seqs[f"death_{fac}"] = [f"idle_{fac}_0", f"death_{fac}_kneel", f"death_{fac}_down"]
    for name, seq in seqs.items():
        cells = [[frames[fr][s] for fr in seq] for s in range(len(frames[seq[0]]))]
        left = max(ax for row in cells for _, ax, _ in row) + 4
        right = max(im.shape[1] - ax for row in cells for im, ax, _ in row) + 4
        up = max(ay for row in cells for _, _, ay in row) + 4
        down = max(im.shape[0] - ay for row in cells for im, _, ay in row) + 4
        cw, ch = int(left + right), int(up + down)
        sheet = Image.new("RGBA", (cw * len(seq), ch * len(cells)), (88, 108, 58, 255))
        for s, row in enumerate(cells):
            for i, (im, ax, ay) in enumerate(row):
                sheet.alpha_composite(Image.fromarray(im), (int(i * cw + left - ax), int(s * ch + up - ay)))
        sheet.save(os.path.join(out_dir, f"{unit}_{name}.png"))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    for c in ("refs", "status", "recut"):
        sub.add_parser(c).add_argument("unit")
    p = sub.add_parser("prompt")
    p.add_argument("unit"); p.add_argument("fac"); p.add_argument("frame")
    p = sub.add_parser("mirror")
    p.add_argument("unit"); p.add_argument("fac")
    p = sub.add_parser("relay")
    p.add_argument("unit"); p.add_argument("fac")
    p = sub.add_parser("cut")
    p.add_argument("unit"); p.add_argument("fac"); p.add_argument("frame"); p.add_argument("raw")
    p.add_argument("--keep-y", action="store_true")
    p.add_argument("--split", action="append", default=[], help="x0,y0,x1,y1 in native sheet pixels")
    p = sub.add_parser("build")
    p.add_argument("unit"); p.add_argument("--review")
    a = ap.parse_args()
    if a.cmd == "refs":
        cmd_refs(a.unit)
    elif a.cmd == "status":
        cmd_status(a.unit)
    elif a.cmd == "recut":
        cmd_recut(a.unit)
    elif a.cmd == "prompt":
        cmd_prompt(a.unit, a.fac, a.frame)
    elif a.cmd == "mirror":
        cmd_mirror(a.unit, a.fac)
    elif a.cmd == "relay":
        cmd_relay(a.unit, a.fac)
    elif a.cmd == "cut":
        cmd_cut(a.unit, a.fac, a.frame, a.raw, a.keep_y, [tuple(int(v) for v in s.split(",")) for s in a.split])
    elif a.cmd == "build":
        cmd_build(a.unit, a.review)


if __name__ == "__main__":
    main()
