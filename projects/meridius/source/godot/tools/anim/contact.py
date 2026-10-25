"""One contact sheet per unit for review: every animation's frames, soldiers as rows.

  contact.py <unit> <out.png> [--soldiers 0,1,2] [--scale 0.6]

Reads assets/sprites/anim/<unit>.json and .png (the built frames, as the game
plays them: mirrored facings already mirrored) and lays out, per facing,
idle 0, walk 0 1 2, wind, hit, then the front and back falls.
"""
import argparse
import json
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.normpath(os.path.join(HERE, "..", ".."))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("unit")
    ap.add_argument("out")
    ap.add_argument("--soldiers", default="")
    ap.add_argument("--scale", type=float, default=0.6)
    a = ap.parse_args()
    doc = json.load(open(os.path.join(GODOT, "assets", "sprites", "anim", f"{a.unit}.json"), encoding="utf-8"))
    atlas = Image.open(os.path.join(GODOT, "assets", "sprites", "anim", f"{a.unit}.png")).convert("RGBA")
    frames = doc["frames"]
    n = doc["soldiers"]
    soldiers = [int(s) for s in a.soldiers.split(",")] if a.soldiers else list(range(n))
    cols = []
    for fac in doc["facings"]:
        cols += [f"idle_{fac}_0", f"walk_{fac}_0", f"walk_{fac}_1", f"walk_{fac}_2", f"strike_{fac}_wind", f"strike_{fac}_hit", None]
    cols += ["death_f_kneel", "death_f_down", None, "death_b_kneel", "death_b_down"]
    left = up = right = down = 0
    for c in cols:
        if c is None:
            continue
        for e in frames[c]:
            left, up = max(left, e["ax"]), max(up, e["ay"])
            right, down = max(right, e["region"][2] - e["ax"]), max(down, e["region"][3] - e["ay"])
    cw, ch = int(left + right + 6), int(up + down + 6)
    sheet = Image.new("RGBA", (cw * len(cols), ch * len(soldiers)), (88, 108, 58, 255))
    for r, s in enumerate(soldiers):
        for i, c in enumerate(cols):
            if c is None:
                continue
            e = frames[c][s % len(frames[c])]
            x, y, w, h = e["region"]
            im = atlas.crop((x, y, x + w, y + h))
            sheet.alpha_composite(im, (int(i * cw + left + 3 - e["ax"]), int(r * ch + up + 3 - e["ay"])))
    if a.scale != 1:
        sheet = sheet.resize((round(sheet.width * a.scale), round(sheet.height * a.scale)), Image.LANCZOS)
    sheet.save(a.out)
    print(a.out, sheet.size)


if __name__ == "__main__":
    main()
