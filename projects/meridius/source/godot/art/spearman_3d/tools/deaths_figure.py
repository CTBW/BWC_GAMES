"""Key frames of the three deaths from one facing, one labelled row each, at one scale
(the report's img/deaths.webp; needs Pillow).

  python deaths_figure.py <WORK/renders> <out.webp> [facing, default se] [frames per row, default 7]
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

src, out = Path(sys.argv[1]), sys.argv[2]
face = sys.argv[3] if len(sys.argv) > 3 else "se"
K = int(sys.argv[4]) if len(sys.argv) > 4 else 7
ROWS = [("death", "Death 1: thrown back, lands face down"), ("death_2", "Death 2: thrown sideways"), ("death_3", "Death 3: crumples forward")]
BG = (232, 228, 220)
SCALE = 0.62

rows = []
for clip, label in ROWS:
    fs = sorted((src / f"{clip}_{face}").glob("*.png"))
    pick = [fs[round(i * (len(fs) - 1) / (K - 1))] for i in range(K)]
    rows.append((label, [Image.open(p).convert("RGBA") for p in pick]))

box = None
for _, ims in rows:
    for im in ims:
        b = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
        if b:
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
pad = 6
box = (max(0, box[0] - pad), max(0, box[1] - pad), box[2] + pad, box[3] + pad)
cw, ch = int((box[2] - box[0]) * SCALE), int((box[3] - box[1]) * SCALE)
font = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 22)
LH = 40
M = Image.new("RGB", (cw * K, (LH + ch) * len(rows)), BG)
d = ImageDraw.Draw(M)
for j, (label, ims) in enumerate(rows):
    y = j * (LH + ch)
    d.text((10, y + 6), label, fill=(40, 36, 32), font=font)
    for i, im in enumerate(ims):
        c = im.crop(box).resize((cw, ch), Image.LANCZOS)
        M.paste(c, (i * cw, y + LH), c)
M.save(out, "WEBP", quality=86, method=6)
print("DEATHS", M.size, "cell", cw, ch)
