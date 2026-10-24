"""Contact sheet for reviewing renders, one row per spec, each row cropped to the union of its
frames' alpha boxes and labelled with frame numbers (needs Pillow).

  python contact_strip.py <out.jpg> <cell height px> <dir>:<i0>:<i1>:<step> [...]

<dir> is a folder of PNG frames, e.g. WORK/renders/death_se; i0/i1 are 0-based, labels 1-based.
From Git Bash pass <dir> as a Windows path (cygpath -m): MSYS rewrites /c/...:a:b arguments.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw
out, CH = sys.argv[1], int(sys.argv[2])
rows = []
for spec in sys.argv[3:]:
    d, a, b, s = spec.rsplit(":", 3)
    fs = sorted(Path(d).glob("*.png"))[int(a):int(b) + 1:int(s)]
    ims = [(f.stem, Image.open(f).convert("RGBA")) for f in fs]
    box = None
    for _, im in ims:
        bb = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
        if bb: box = bb if box is None else (min(box[0], bb[0]), min(box[1], bb[1]), max(box[2], bb[2]), max(box[3], bb[3]))
    box = (box[0] - 4, box[1] - 4, box[2] + 4, box[3] + 4)
    k = CH / (box[3] - box[1])
    rows.append([(n, im.crop(box).resize((int((box[2] - box[0]) * k), CH), Image.LANCZOS)) for n, im in ims])
W = max(sum(im.width for _, im in r) for r in rows)
M = Image.new("RGB", (W, CH * len(rows)), (225, 220, 205)); dr = ImageDraw.Draw(M)
for j, r in enumerate(rows):
    x = 0
    for n, im in r:
        M.paste(im, (x, j * CH), im); dr.text((x + 4, j * CH + 4), str(int(n) + 1), fill=(0, 0, 0)); x += im.width
M.save(out, quality=88); print(M.size)
