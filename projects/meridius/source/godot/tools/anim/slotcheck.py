"""Find cut frames whose figure is another soldier of the squad (the generator
swapped two figures' places): each frame's colour histogram is compared with every
standing figure of its facing; a frame closer to another man than to its own is
reported.

  slotcheck.py [unit ...] [--fix]     --fix swaps such pairs back in the index
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import squadgen as sg  # noqa: E402
from units import UNITS, facings  # noqa: E402


def hist(path):
    a = np.array(Image.open(path).convert("RGBA"))
    m = a[..., 3] > 0
    rows = np.nonzero(m.any(axis=1))[0]
    if not len(rows):
        return np.zeros(512)
    # The upper half carries the individual: head, hair, headgear.
    top = rows[0] + (rows[-1] - rows[0]) // 2
    px = a[rows[0]:top][m[rows[0]:top]][:, :3] // 32
    h = np.bincount(px[:, 0] * 64 + px[:, 1] * 8 + px[:, 2], minlength=512).astype(float)
    return h / max(1.0, h.sum())


def check(unit, fix=False):
    n = sg.count(unit)
    bad = []
    for fac in facings(unit):
        d = sg.sdir(unit, fac)
        index = sg.load_json(os.path.join(d, "index.json"), {})
        if f"base_{n - 1}" not in index:
            continue
        base = [hist(os.path.join(d, f"base_{s}.png")) for s in range(n)]
        frames = sorted({k.rsplit("_", 1)[0] for k in index} - {"base"})
        for fr in frames:
            if fr in ("down", "slump"):
                continue
            cur = [hist(os.path.join(d, f"{fr}_{s}.png")) if f"{fr}_{s}" in index else None for s in range(n)]
            for s in range(n):
                if cur[s] is None:
                    continue
                dist = [np.abs(cur[s] - b).sum() for b in base]
                best = int(np.argmin(dist))
                if best != s and dist[best] < 0.8 * dist[s]:
                    bad.append((fac, fr, s, best))
                    print(f"{unit} {fac} {fr}_{s} looks like soldier {best} ({dist[best]:.2f} vs own {dist[s]:.2f})")
        if fix:
            done = set()
            for f2, fr, s, best in bad:
                if f2 != fac or (fr, min(s, best)) in done:
                    continue
                if (fac, fr, best, s) in bad:
                    done.add((fr, min(s, best)))
                    a, b = f"{fr}_{s}", f"{fr}_{best}"
                    tmp = os.path.join(d, "_swap.png")
                    os.replace(os.path.join(d, a + ".png"), tmp)
                    os.replace(os.path.join(d, b + ".png"), os.path.join(d, a + ".png"))
                    os.replace(tmp, os.path.join(d, b + ".png"))
                    index[a], index[b] = index[b], index[a]
                    print(f"  swapped {a} <-> {b}")
            sg.save_json(os.path.join(d, "index.json"), index)
    return bad


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    fix = "--fix" in sys.argv
    units = args or [u for u in UNITS if os.path.isdir(sg.sdir(u, "f"))]
    total = 0
    for u in units:
        if UNITS[u].get("kind") == "engine":
            continue
        total += len(check(u, fix))
    print("suspect frames:", total)
