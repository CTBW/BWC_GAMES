"""Defect scan of the cut frames (art/squads/<unit>/<facing>/<frame>_<soldier>.png).

  audit.py [unit ...] [--json out.json]

Per frame it reports:
  specks     opaque pixels with no opaque neighbour (8-connected), and loose pieces
             under 30 px that are not part of the figure
  pieces     separate parts of 30 px or more away from the main body (disjointed)
  holes      enclosed transparent pixels inside the body (pinholes, 1-4 px)
  height     standing frames (walk, wind, hit) more than 12% taller or shorter
             than the same man's standing frame (warped or rescaled)
  feet       walk frames whose feet drift more than 6 px from the standing anchor
             (the man would jump when the frame changes)
  haze       pale grey, nearly colourless pixels (left-over generator haze)
The counts go to stdout, worst first, and with --json to a file for fix.py.
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import squadgen as sg  # noqa: E402
from units import UNITS, facings  # noqa: E402

STAND = ("walk_a", "wind", "hit")


def scan(path, base_h=None, base_ax=None, e=None, frame=""):
    a = np.array(Image.open(path).convert("RGBA"))
    op = a[..., 3] > 0
    out = {}
    if not op.any():
        return {"empty": 1}
    # Isolated pixels.
    nb = ndimage.convolve(op.astype(np.uint8), np.ones((3, 3), np.uint8), mode="constant") - op
    out["specks"] = int((op & (nb == 0)).sum())
    lab, n = ndimage.label(op, structure=np.ones((3, 3)))
    if n > 1:
        sizes = ndimage.sum(op, lab, range(1, n + 1))
        main = int(np.argmax(sizes)) + 1
        small = [s for i, s in enumerate(sizes, 1) if i != main and s < 30]
        big = [s for i, s in enumerate(sizes, 1) if i != main and s >= 30]
        out["specks"] += int(sum(small))
        out["pieces"] = len(big)
    # Pinholes: transparent components fully enclosed, 1-4 px.
    tr = ~op
    tl, tn = ndimage.label(tr)
    border = set(np.unique(np.concatenate([tl[0], tl[-1], tl[:, 0], tl[:, -1]])))
    if tn:
        ts = ndimage.sum(tr, tl, range(1, tn + 1))
        out["holes"] = int(sum(1 for i, s in enumerate(ts, 1) if i not in border and s <= 4))
    rows = np.nonzero(op.any(axis=1))[0]
    if base_h and frame in STAND and e is not None:
        h = e["ay"] - rows[0]
        r = h / base_h
        if r > 1.12 or r < 0.88:
            out["height"] = round(float(r), 2)
    if base_ax is not None and frame == "walk_a" and e is not None:
        feet = op[max(0, rows[-1] - 6):rows[-1] + 1]
        fx = float(np.nonzero(feet)[1].mean())
        if abs(fx - e["ax"]) > 6 + 0.25 * abs(base_ax):
            out["feet"] = round(fx - e["ax"], 1)
    rgb = a[..., :3].astype(int)
    mx, mn = rgb.max(2), rgb.min(2)
    haze = op & (mn > 165) & (mx - mn < 14)
    out["haze"] = int(haze.sum())
    return {k: v for k, v in out.items() if v}


def audit(unit):
    found = []
    for fac in facings(unit):
        d = sg.sdir(unit, fac)
        index = sg.load_json(os.path.join(d, "index.json"), {})
        for name, e in sorted(index.items()):
            frame, s = name.rsplit("_", 1)
            base = index.get(f"base_{s}")
            base_h = None
            if base is not None:
                ba = np.array(Image.open(os.path.join(d, f"base_{s}.png")).convert("RGBA"))[..., 3] > 0
                base_h = base["ay"] - np.nonzero(ba.any(axis=1))[0][0]
            r = scan(os.path.join(d, name + ".png"), base_h, 0.0, e, frame)
            if r:
                found.append({"unit": unit, "fac": fac, "frame": name, **r})
    return found


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    out = sys.argv[sys.argv.index("--json") + 1] if "--json" in sys.argv else None
    if out in args:
        args.remove(out)
    units = args or [u for u in UNITS if os.path.isdir(sg.sdir(u, facings(u)[0]))]
    allf = []
    for u in units:
        f = audit(u)
        allf += f
        tot = {}
        for r in f:
            for k, v in r.items():
                if k not in ("unit", "fac", "frame"):
                    tot[k] = tot.get(k, 0) + (1 if k in ("height", "feet") else v)
        print(f"{u}: {len(f)} frames with findings {tot}")
    if out:
        with open(out, "w", encoding="utf-8") as fh:
            json.dump(allf, fh, indent=1)


if __name__ == "__main__":
    main()
