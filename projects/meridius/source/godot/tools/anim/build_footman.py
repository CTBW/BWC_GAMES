"""Builds the footman's frame animations for the battle view.

Reads the Higgsfield keyframes in ../game/art/sprites/footman_anim (frames and
sprites.json; read only, that folder is frozen) and writes

  assets/sprites/anim/footman.png   one atlas, every frame trimmed
  assets/sprites/anim/footman.json  frame name -> six soldiers' regions and anchors

which scripts/render/soldier_anim.gd plays. The choreography (timing, per-
soldier rhythm, bob, lunges) lives there; this file only prepares pictures.

Frames, per facing (f = front, true SW; fs = mirrored true SE; b = back, true
NE; bs = mirrored true NW; the game mirrors fs and bs back):
  idle_<fac>_0..2      breathing (the generated idle loop)
  walk_<fac>_0..2      contact, passing, other foot forward, all on one upper
                       body (tools/anim/legs.py), so only the legs move
  strike_<fac>_wind    anticipation (sword back or raised)
  strike_<fac>_hit     the blow (thrust for f/b, the chop's end for fs/bs)
  death_<f|b>_kneel, death_<f|b>_down   falling; the front `down` is the body

Run with the art environment (Pillow, numpy, scipy):
  ../game/.venv-art/Scripts/python.exe -I tools/anim/build_footman.py [--review DIR] [--aseprite EXE]
then tools/import.sh. Re-running rewrites both outputs. With --aseprite, it also
writes art/footman/footman_<fac>.aseprite: each facing as an editable Aseprite
file (a layer per soldier, tags idle/walk/strike/death, the game's timing),
through Aseprite's batch mode and tools/anim/footman_aseprite.lua.
"""
import argparse
import hashlib
import json
import math
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import legs  # noqa: E402

GODOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SRC = os.path.normpath(os.path.join(GODOT, "..", "game", "art", "sprites", "footman_anim"))
OUT_DIR = os.path.join(GODOT, "assets", "sprites", "anim")
RES_PNG = "res://assets/sprites/anim/footman.png"
FACINGS = ["f", "fs", "b", "bs"]
SOLDIERS = 6
ATLAS_W = 4096
PAD = 3
ART_DIR = os.path.join(GODOT, "art", "footman")
# Frame times in the Aseprite files (ms), as soldier_anim.gd plays them.
IDLE_MS = 420
WALK_MS = 110
STRIKE_MS = [100, 190, 190, 220]
DEATH_MS = [95, 304, 551]


def load_source():
    man = json.load(open(os.path.join(SRC, "sprites.json"), encoding="utf-8"))["sprites"]
    imgs = {}
    for key, entries in man.items():
        for s, e in enumerate(entries):
            im = np.array(Image.open(os.path.join(SRC, e["file"])).convert("RGBA"))
            imgs[(key, s)] = (im, float(e["ax"]), float(e["ay"]))
    return imgs


def canvas_of(imgs):
    """One canvas size and anchor that holds every frame."""
    left = max(math.ceil(ax) for _, ax, _ in imgs.values()) + 2
    right = max(math.ceil(im.shape[1] - ax) for im, ax, _ in imgs.values()) + 2
    up = max(math.ceil(ay) for _, _, ay in imgs.values()) + 2
    down = max(math.ceil(im.shape[0] - ay) for im, _, ay in imgs.values()) + 2
    return left + right, up + down, left, up


def place(item, cw, ch, cx, cy):
    im, ax, ay = item
    c = np.zeros((ch, cw, 4), np.uint8)
    x, y = int(round(cx - ax)), int(round(cy - ay))
    c[y:y + im.shape[0], x:x + im.shape[1]] = im
    return c


def build_frames(imgs):
    cw, ch, cx, cy = canvas_of(imgs)
    get = lambda key, s: place(imgs[(key, s)], cw, ch, cx, cy)
    frames = {}
    for fac in FACINGS:
        back = fac.startswith("b")
        for i in range(3):
            frames[f"idle_{fac}_{i}"] = [get(f"footman_idle_{fac}_{i:02d}", s) for s in range(SOLDIERS)]
        keys = [legs.walk_keys(get(f"footman_walk_{fac}_00", s), get(f"footman_walk_{fac}_01", s), cx, cy, back) for s in range(SOLDIERS)]
        for i in range(3):
            frames[f"walk_{fac}_{i}"] = [k[i] for k in keys]
        frames[f"strike_{fac}_wind"] = [get(f"footman_strike_{fac}_01", s) for s in range(SOLDIERS)]
        frames[f"strike_{fac}_hit"] = [get(f"footman_strike_{fac}_02", s) for s in range(SOLDIERS)]
    for fac in ["f", "b"]:
        frames[f"death_{fac}_kneel"] = [get(f"footman_death_{fac}_01", s) for s in range(SOLDIERS)]
        frames[f"death_{fac}_down"] = [get(f"footman_death_{fac}_02", s) for s in range(SOLDIERS)]
    return frames, (cx, cy)


def trim(c):
    a = c[..., 3] > 0
    ys = np.nonzero(a.any(axis=1))[0]
    xs = np.nonzero(a.any(axis=0))[0]
    return c[ys[0]:ys[-1] + 1, xs[0]:xs[-1] + 1], int(xs[0]), int(ys[0])


def pack(frames, anchor):
    """Shelf-pack the unique trimmed frames; returns (atlas, table)."""
    cx, cy = anchor
    unique = {}
    refs = {}
    for name, per in frames.items():
        refs[name] = []
        for c in per:
            t, x0, y0 = trim(c)
            h = hashlib.sha1(t.tobytes() + bytes(str(t.shape), "ascii")).hexdigest()
            unique.setdefault(h, t)
            refs[name].append((h, cx - x0, cy - y0))
    order = sorted(unique, key=lambda h: (-unique[h].shape[0], -unique[h].shape[1]))
    pos = {}
    x = y = PAD
    row = 0
    for h in order:
        t = unique[h]
        if x + t.shape[1] + PAD > ATLAS_W:
            x = PAD
            y += row + PAD
            row = 0
        pos[h] = (x, y)
        x += t.shape[1] + PAD
        row = max(row, t.shape[0])
    height = 1 << max(8, math.ceil(math.log2(y + row + PAD)))
    atlas = np.zeros((height, ATLAS_W, 4), np.uint8)
    for h, (px, py) in pos.items():
        t = unique[h]
        atlas[py:py + t.shape[0], px:px + t.shape[1]] = t
    table = {}
    for name, rs in refs.items():
        table[name] = []
        for h, ax, ay in rs:
            px, py = pos[h]
            t = unique[h]
            table[name].append({"region": [px, py, t.shape[1], t.shape[0]], "ax": ax, "ay": ay})
    return atlas, table, len(unique)


def match_scale(frames, anchor):
    """World px per source px so a footman stands as tall as the drawn figure
    he replaces (assets/sprites.json footman_idle_f, measured opaque height)."""
    man = json.load(open(os.path.join(GODOT, "assets", "sprites.json"), encoding="utf-8"))
    fig = np.array(Image.open(os.path.join(GODOT, "assets", "sprites", "baked", "fig_footman.png")).convert("RGBA"))
    old = []
    for e in man["footman_idle_f"]:
        x, y, w, h = e["region"]
        rows = np.nonzero((fig[y:y + h, x:x + w, 3] > 128).any(axis=1))[0]
        old.append((e["ay"] - rows[0]) * e["scale"])
    cy = anchor[1]
    new = []
    for c in frames["idle_f_0"]:
        rows = np.nonzero((c[..., 3] > 128).any(axis=1))[0]
        new.append(cy - rows[0])
    return float(np.median(old) / np.median(new))


def review(frames, anchor, out_dir, scale):
    """Strips (one row per soldier, frames in playing order) at native size and
    at the battle camera's largest zoom, on grass."""
    os.makedirs(out_dir, exist_ok=True)
    cx, cy = anchor
    seqs = {}
    for fac in FACINGS:
        seqs[f"idle_{fac}"] = [f"idle_{fac}_{i}" for i in (0, 1, 2, 1)]
        seqs[f"walk_{fac}"] = [f"walk_{fac}_{i}" for i in (0, 1, 2, 1)]
        seqs[f"strike_{fac}"] = [f"idle_{fac}_0", f"strike_{fac}_wind", f"strike_{fac}_hit", f"idle_{fac}_0"]
    for fac in ["f", "b"]:
        seqs[f"death_{fac}"] = [f"idle_{fac}_0", f"death_{fac}_kneel", f"death_{fac}_down"]
    for name, seq in seqs.items():
        ch, cw = frames[seq[0]][0].shape[:2]
        sheet = Image.new("RGBA", (cw * len(seq), ch * SOLDIERS), (88, 108, 58, 255))
        for s in range(SOLDIERS):
            for i, fr in enumerate(seq):
                sheet.alpha_composite(Image.fromarray(frames[fr][s]), (i * cw, s * ch))
        sheet.save(os.path.join(out_dir, f"{name}.png"))
        k = scale * 0.52 * 1.6
        sheet.resize((round(sheet.width * k), round(sheet.height * k)), Image.LANCZOS).save(os.path.join(out_dir, f"{name}_game.png"))


def aseprite(frames, exe):
    """One .aseprite file per facing, built in Aseprite's batch mode."""
    os.makedirs(ART_DIR, exist_ok=True)
    lua = os.path.join(HERE, "footman_aseprite.lua")
    ch, cw = frames["idle_f_0"][0].shape[:2]
    with tempfile.TemporaryDirectory() as tmp:
        for fac in FACINGS:
            death = "f" if fac.startswith("f") else "b"
            seq = [("idle", IDLE_MS, f"idle_{fac}_{i}") for i in (0, 1, 2, 1)]
            seq += [("walk", WALK_MS, f"walk_{fac}_{i}") for i in (0, 1, 2, 1)]
            seq += [("strike", ms, n) for ms, n in zip(STRIKE_MS, [f"idle_{fac}_0", f"strike_{fac}_wind", f"strike_{fac}_hit", f"idle_{fac}_0"])]
            seq += [("death", ms, n) for ms, n in zip(DEATH_MS, [f"idle_{fac}_0", f"death_{death}_kneel", f"death_{death}_down"])]
            lines = [f"{cw} {ch} {SOLDIERS}"]
            for i, (tag, ms, name) in enumerate(seq):
                files = []
                for sol in range(SOLDIERS):
                    f = os.path.join(tmp, f"{fac}_{i:02d}_{sol}.png")
                    Image.fromarray(frames[name][sol]).save(f)
                    files.append(f.replace("\\", "/"))
                lines.append("|".join([tag, str(ms)] + files))
            manifest = os.path.join(tmp, f"{fac}.txt")
            with open(manifest, "w", encoding="utf-8", newline="\n") as f:
                f.write("\n".join(lines) + "\n")
            out = os.path.join(ART_DIR, f"footman_{fac}.aseprite")
            r = subprocess.run([exe, "-b", "--script-param", f"list={manifest}", "--script-param", f"out={out}", "--script", lua], capture_output=True, text=True)
            print((r.stdout or r.stderr).strip())
            if r.returncode != 0:
                raise SystemExit(f"aseprite failed for {fac}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--review", help="write review strips to this folder")
    ap.add_argument("--aseprite", help="Aseprite executable: also write the editable art/footman/*.aseprite files")
    args = ap.parse_args()
    imgs = load_source()
    frames, anchor = build_frames(imgs)
    scale = match_scale(frames, anchor)
    atlas, table, n = pack(frames, anchor)
    os.makedirs(OUT_DIR, exist_ok=True)
    Image.fromarray(atlas).save(os.path.join(OUT_DIR, "footman.png"), optimize=True)
    doc = {
        "source": "../game/art/sprites/footman_anim (Higgsfield keyframes), built by tools/anim/build_footman.py",
        "file": RES_PNG,
        "scale": round(scale, 5),
        "soldiers": SOLDIERS,
        "frames": table,
    }
    with open(os.path.join(OUT_DIR, "footman.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, indent=1)
        f.write("\n")
    print(f"{len(table)} frames x {SOLDIERS} soldiers, {n} unique images, atlas {atlas.shape[1]}x{atlas.shape[0]}, scale {scale:.5f}")
    if args.review:
        review(frames, anchor, args.review, scale)
        print("review strips in", args.review)
    if args.aseprite:
        aseprite(frames, args.aseprite)


if __name__ == "__main__":
    main()
