"""Cape before (skinned) and after (cloth): per clip, one labelled row each, same crop
(the report's img/cape_cloth.webp; needs Pillow).

  python cape_figure.py <before dir> <after dir> <out.webp> walk_nw attack_sw ...

Each dir holds <clip>_<facing>/*.png renders. The report used every 8th frame of walk nw
and every 12th of attack sw, rendered with CLIP_SCALE=2.6 CLIP_Z=1.0:
  render_preview.py -- <dir> clip walk 8 nw
The before frames came from a scratch copy of the rig with the old skinned cape
(rig_tw.blend), which is not kept in the repo.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

before, after, out = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
clips = sys.argv[4:]
NAMES = {"walk": "March", "attack": "Thrust", "idle": "Guard", "step_lane": "Step into lane"}
FACE = {"se": "south-east", "sw": "south-west", "ne": "north-east", "nw": "north-west"}
BG = (232, 228, 220)
SCALE = 0.55
font = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 22)
LH = 38

blocks = []
for key in clips:
    rows = []
    for tag, d in (("skinned to the spine (before)", before), ("cloth (after)", after)):
        rows.append((tag, [Image.open(p).convert("RGBA") for p in sorted((d / key).glob("*.png"))]))
    box = None
    for _, ims in rows:
        for im in ims:
            b = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
            if b:
                box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    box = (max(0, box[0] - 6), max(0, box[1] - 6), box[2] + 6, box[3] + 6)
    clip, face = key.rsplit("_", 1)
    blocks.append((f"{NAMES.get(clip, clip)}, {FACE[face]}", rows, box))

cw = max(int((b[2] - b[0]) * SCALE) for _, _, b in blocks)
cols = max(len(ims) for _, rows, _ in blocks for _, ims in rows)
H = sum(2 * (LH + int((b[3] - b[1]) * SCALE)) for _, _, b in blocks)
M = Image.new("RGB", (cw * cols, H), BG)
d = ImageDraw.Draw(M)
y = 0
for title, rows, box in blocks:
    w, h = int((box[2] - box[0]) * SCALE), int((box[3] - box[1]) * SCALE)
    for tag, ims in rows:
        d.text((10, y + 6), f"{title}: {tag}", fill=(40, 36, 32), font=font)
        for i, im in enumerate(ims):
            c = im.crop(box).resize((w, h), Image.LANCZOS)
            M.paste(c, (i * cw + (cw - w) // 2, y + LH), c)
        y += LH + h
M.save(out, "WEBP", quality=86, method=6)
print("CAPEBA", M.size)
