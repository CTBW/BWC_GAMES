"""Audit sheet: every unit's standing soldier as the battle view shows him in each of
the four facings (SW, SE, NE, NW, the game's mirroring applied), to check that
each drawing looks the way the squad faces.

  headings.py <out.png> [unit ...]
"""
import json
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.normpath(os.path.join(HERE, "..", ".."))
ANIM = os.path.join(GODOT, "assets", "sprites", "anim")


def shown(doc, atlas, facing, soldier=0):
    """(image, ax, ay) of idle frame 0 as soldier_anim.gd draws it at a facing."""
    shield = "fs" in doc.get("facings", ["f", "fs", "b", "bs"])
    flip = facing in (0, 2)
    fac = ("f" if facing in (0, 1) else "b") + ("s" if flip and shield else "")
    if doc.get("engine"):
        name = "idle_" + fac[0]
    else:
        name = f"idle_{fac}_0"
    e = doc["frames"][name][soldier % len(doc["frames"][name])]
    x, y, w, h = e["region"]
    im = atlas.crop((x, y, x + w, y + h))
    ax = e["ax"]
    if flip:
        im, ax = im.transpose(Image.FLIP_LEFT_RIGHT), w - ax
    return im, ax, e["ay"]


def main():
    out = sys.argv[1]
    units = sys.argv[2:] or sorted(f[:-5] for f in os.listdir(ANIM) if f.endswith(".json"))
    cw, ch = 260, 300
    sheet = Image.new("RGBA", (cw * 4 + 150, ch * len(units)), (88, 108, 58, 255))
    d = ImageDraw.Draw(sheet)
    for r, u in enumerate(units):
        doc = json.load(open(os.path.join(ANIM, f"{u}.json"), encoding="utf-8"))
        atlas = Image.open(os.path.join(ANIM, f"{u}.png")).convert("RGBA")
        d.text((6, r * ch + 8), u, fill=(255, 255, 255, 255))
        for c, (facing, label) in enumerate([(1, "SW"), (0, "SE"), (3, "NE"), (2, "NW")]):
            im, ax, ay = shown(doc, atlas, facing)
            k = min(1.0, (ch - 30) / im.height, (cw - 10) / im.width)
            im = im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)
            sheet.alpha_composite(im, (int(150 + c * cw + cw / 2 - ax * k), int(r * ch + ch - 10 - ay * k)))
            d.text((150 + c * cw + 6, r * ch + 8), label, fill=(255, 230, 120, 255))
    sheet.save(out)
    print(out, sheet.size)


if __name__ == "__main__":
    main()
