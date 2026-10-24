# Tile PNG frames into a contact sheet: python contact.py <dir> <out.png> [cols] [width] [start] [count]
import sys, glob, os
from PIL import Image, ImageDraw
d, out = sys.argv[1], sys.argv[2]
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 4
w = int(sys.argv[4]) if len(sys.argv) > 4 else 480
start = int(sys.argv[5]) if len(sys.argv) > 5 else 0
count = int(sys.argv[6]) if len(sys.argv) > 6 else 999
files = sorted(glob.glob(os.path.join(d, '*.png')))[start:start + count]
ims = [Image.open(f).convert('RGB') for f in files]
h = int(ims[0].height * w / ims[0].width)
rows = (len(ims) + cols - 1) // cols
sheet = Image.new('RGB', (cols * w, rows * h), (20, 15, 10))
dr = ImageDraw.Draw(sheet)
for i, (im, f) in enumerate(zip(ims, files)):
    x, y = (i % cols) * w, (i // cols) * h
    sheet.paste(im.resize((w, h), Image.LANCZOS), (x, y))
    dr.text((x + 6, y + 4), os.path.basename(f)[:22], fill=(255, 230, 150))
sheet.save(out)
print(out, sheet.size)
