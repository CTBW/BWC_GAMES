"""Front, back and battle-camera lineup renders (transparent, from lineup.py) cropped to
content, side by side on paper with labels, 680 px high (needs Pillow).

  python lineup_compose.py <lineup.py out dir> <out.webp>
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
src, out = Path(sys.argv[1]), sys.argv[2]
BG = (232, 228, 220)
views = [("front", "Front"), ("back", "Back"), ("battle_se", "Battle camera, south-east")]
crops = []
for key, label in views:
    im = Image.open(src / f"{key}.png").convert("RGBA")
    box = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    p = 24
    crops.append((label, im.crop((max(0, box[0] - p), max(0, box[1] - p), min(im.width, box[2] + p), min(im.height, box[3] + p)))))
LH = 50
H = max(c.height for _, c in crops) + LH
W = sum(c.width for _, c in crops)
M = Image.new("RGB", (W, H), BG); d = ImageDraw.Draw(M)
font = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 30)
x = 0
for label, c in crops:
    M.paste(c, (x, H - c.height), c); d.text((x + 16, 10), label, fill=(40, 36, 32), font=font); x += c.width
k = 680 / H
M = M.resize((int(W * k), 680), Image.LANCZOS)
M.save(out, "WEBP", quality=86, method=6); print("LINEUP", M.size)
