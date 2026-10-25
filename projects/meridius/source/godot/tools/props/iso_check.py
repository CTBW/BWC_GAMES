"""Measure a painting's edges against the battlefield's 2:1 isometric grid.

The battle draws a tile 64 px across and 32 px down, so every edge that runs
along the grid (a wall's foot, an eave, a roof ridge, a road, a plank) rises
1 px for every 2 px across: a slope of 0.5. A generated painting with some
perspective has edges at 0.4 or 0.6 instead, and on the battlefield it looks
turned against the tiles, the roads and the fog's edge.

From each corner point (a wall's front corner at the foot, at the eaves, at
the ridge) this draws guides left and right at slopes 0.4 (orange), 0.5 (red)
and 0.6 (magenta) over the painting, on grey, with a 25 px grid and labels
every 100 px, and saves the crop as JPG. Read which guide each painted edge
follows; between two guides, interpolate.

    python -I tools/props/iso_check.py PAINTING OUT.jpg x0,y0,x1,y1 cx,cy [cx,cy ...]

x0,y0,x1,y1 is the crop (pixels of the painting); each cx,cy a corner. Use it
on the generated original before cutting and again on the cut sprite (the
written WebP) after SLOPE or KEYSTONE in cut_art.py. The method and the fixes:
processes/isometric-art-check.md at the workspace root.
"""

import sys

from PIL import Image, ImageDraw

GUIDES = ((0.4, (255, 140, 0)), (0.5, (255, 0, 0)), (0.6, (255, 0, 255)))


def check(path, out, box, corners):
    im = Image.open(path).convert("RGBA")
    bg = Image.new("RGBA", im.size, (110, 110, 110, 255))
    bg.alpha_composite(im)
    d = ImageDraw.Draw(bg)
    for x in range(0, im.width, 25):
        d.line([(x, 0), (x, im.height)], fill=(0, 220, 255, 255) if x % 100 == 0 else (0, 90, 120, 120))
    for y in range(0, im.height, 25):
        d.line([(0, y), (im.width, y)], fill=(0, 220, 255, 255) if y % 100 == 0 else (0, 90, 120, 120))
    reach = im.width + im.height
    for cx, cy in corners:
        for s, col in GUIDES:
            for sx in (1, -1):
                d.line([(cx, cy), (cx + sx * reach, cy - s * reach)], fill=col + (255,), width=2)
    crop = bg.crop(box)
    dc = ImageDraw.Draw(crop)
    for x in range((box[0] // 100 + 1) * 100, box[2], 100):
        dc.text((x - box[0] + 2, 2), str(x), fill=(255, 255, 0, 255))
    for y in range((box[1] // 100 + 1) * 100, box[3], 100):
        dc.text((2, y - box[1] + 2), str(y), fill=(255, 255, 0, 255))
    f = min(1.5, 900 / crop.width)
    crop.resize((int(crop.width * f), int(crop.height * f)), Image.LANCZOS).convert("RGB").save(out, quality=90)


if __name__ == "__main__":
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    check(sys.argv[1], sys.argv[2], [int(v) for v in sys.argv[3].split(",")],
          [tuple(float(v) for v in c.split(",")) for c in sys.argv[4:]])
