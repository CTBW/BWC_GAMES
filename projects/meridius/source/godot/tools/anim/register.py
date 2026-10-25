"""Registration check: how far each cut frame's upper body sits from the same
man's standing frame, once both are placed at their anchors. A walk or attack
frame that is off by more than a few pixels makes the man jump when his frame
changes. Prints the worst; --fix moves the anchors so the torsos line up
(walk frames only: their feet move, their torso must not).

  register.py [unit ...] [--fix] [--min 3]
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import squadgen as sg  # noqa: E402
from units import UNITS, facings  # noqa: E402


def mask(path):
    return np.array(Image.open(path).convert("RGBA"))[..., 3] > 0


def torso_band(m, ay):
    """Rows from 30% to 62% of the height above the feet (chest and hips; no raised arms, no feet)."""
    rows = np.nonzero(m.any(axis=1))[0]
    h = ay - rows[0]
    return int(ay - 0.62 * h), int(ay - 0.30 * h)


def offset(base, be, fr, fe, search=24):
    """dx (frame minus base, px) that best overlaps the torso bands, and the overlap score."""
    y0, y1 = torso_band(base, be["ay"])
    bb = base[max(0, y0):max(0, y1)]
    best, best_s = 0, -1.0
    W = 2 * (max(base.shape[1], fr.shape[1]) + search) + 8
    def place(m, ax, ay, y0, y1, dx=0):
        c = np.zeros((y1 - y0, W), bool)
        sy0, sy1 = int(y0 - (be["ay"] - ay)), int(y1 - (be["ay"] - ay))
        part = m[max(0, sy0):max(0, sy1)]
        x = int(round(W / 2 - ax)) + dx
        if part.size and x >= 0 and x + m.shape[1] <= W:
            c[:part.shape[0], x:x + m.shape[1]] = part
        return c
    cb = place(base, be["ax"], be["ay"], y0, y1)
    for dx in range(-search, search + 1):
        cf = place(fr, fe["ax"], fe["ay"], y0, y1, dx)
        inter = (cb & cf).sum()
        s = inter / max(1, (cb | cf).sum())
        if s > best_s:
            best_s, best = s, dx
    if best_s <= 0:
        return 0, 0.0
    return -best, best_s


def check(unit, fix=False, minpx=3):
    out = []
    for fac in facings(unit):
        d = sg.sdir(unit, fac)
        p = os.path.join(d, "index.json")
        index = sg.load_json(p, {})
        changed = False
        for name, e in sorted(index.items()):
            frame, s = name.rsplit("_", 1)
            if frame not in ("walk_a", "wind", "hit", "kneel"):
                continue
            be = index.get(f"base_{s}")
            if be is None:
                continue
            base = mask(os.path.join(d, f"base_{s}.png"))
            fr = mask(os.path.join(d, name + ".png"))
            dx, score = offset(base, be, fr, e)
            if abs(dx) >= minpx:
                out.append((unit, fac, name, dx, round(score, 2)))
                if fix and frame == "walk_a" and score > 0.55:
                    e["ax"] = round(e["ax"] + dx, 1)
                    changed = True
        if changed:
            sg.save_json(p, index)
    return out


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    minpx = 3
    if "--min" in sys.argv:
        minpx = int(sys.argv[sys.argv.index("--min") + 1])
        if str(minpx) in args:
            args.remove(str(minpx))
    units = args or [u for u in UNITS if UNITS[u].get("kind") != "engine" and os.path.isdir(sg.sdir(u, "f"))]
    allr = []
    for u in units:
        allr += check(u, "--fix" in sys.argv, minpx)
    allr.sort(key=lambda r: -abs(r[3]))
    by = {}
    for r in allr:
        by.setdefault((r[0], r[2].rsplit("_", 1)[0]), []).append(r[3])
    for (u, fr), v in sorted(by.items(), key=lambda kv: -max(abs(x) for x in kv[1])):
        print(f"{u:16s} {fr:7s} n={len(v):2d} worst={max(v, key=abs):+d}")
    print("frames off by >= %d px:" % minpx, len(allr))
