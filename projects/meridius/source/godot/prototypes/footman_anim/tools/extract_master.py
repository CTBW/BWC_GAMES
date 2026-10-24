"""Cut the master footman out of the painted concept sheets (one view each).

  python -I extract_master.py <repo root> <out dir>

GrabCut inside a hand-picked box, then only the largest connected body is kept
(squadmates' boots and stones at the box edges fall away). Writes
<out>/<view>.png (RGBA, source resolution) and <out>/<view>.json (crop origin).
"""
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

# The bottom-left soldier (brown hair) of each sheet: he stands in the front
# rank, so no squadmate hides any part of him.
VIEWS = {
    "se": ("projects/meridius/references/characters/Footmen_right.png", (95, 505, 470, 985)),
    "sw": ("projects/meridius/references/characters/Footmen_front.png", (12, 498, 432, 978)),
    "ne": ("projects/meridius/references/characters/Footmen_back.png", (100, 492, 462, 938)),
}


def cut(rgb, box, extra_bg=()):
    x0, y0, x1, y1 = box
    sub = rgb[y0:y1, x0:x1].copy()
    bgr = cv2.cvtColor(sub, cv2.COLOR_RGB2BGR)
    mask = np.zeros(sub.shape[:2], np.uint8)
    rect = (4, 4, sub.shape[1] - 8, sub.shape[0] - 8)
    bgd = np.zeros((1, 65), np.float64)
    fgd = np.zeros((1, 65), np.float64)
    cv2.grabCut(bgr, mask, rect, bgd, fgd, 10, cv2.GC_INIT_WITH_RECT)
    m = np.where((mask == 1) | (mask == 3), 1, 0).astype(np.uint8)
    n, lab, stats, _ = cv2.connectedComponentsWithStats(m, connectivity=8)
    keep = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    m = (lab == keep).astype(np.uint8)
    # Close pinholes inside the body (GrabCut speckle), not real gaps: a hole is
    # filled only if it is tiny.
    inv = 1 - m
    n, lab, stats, _ = cv2.connectedComponentsWithStats(inv, connectivity=4)
    for i in range(1, n):
        if stats[i, cv2.CC_STAT_AREA] < 40:
            m[lab == i] = 1
    return sub, m


def main():
    root, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    for view, (sheet, box) in VIEWS.items():
        rgb = np.array(Image.open(root / sheet).convert("RGB"))
        sub, m = cut(rgb, box)
        rgba = np.dstack([sub, m * 255]).astype(np.uint8)
        Image.fromarray(rgba).save(out / f"{view}_cut.png")
        prev = sub.copy()
        prev[m == 0] = [255, 0, 255]
        Image.fromarray(prev).save(out / f"{view}_cut_preview.png")
        (out / f"{view}_cut.json").write_text(json.dumps({"sheet": sheet, "box": box}), encoding="utf-8")
        print(view, sub.shape, int(m.sum()))


main()
