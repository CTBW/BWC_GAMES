# Compose sprites on a grass background for review: python compose.py <out.png> <h> <files...>
import sys
from PIL import Image
out, H = sys.argv[1], int(sys.argv[2])
ims = [Image.open(f).convert('RGBA') for f in sys.argv[3:]]
row = []
for im in ims:
    s = min(1.0, H / im.height)
    row.append(im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS))
W = sum(i.width for i in row) + 20 * len(row)
sheet = Image.new('RGBA', (W, H + 20), (126, 160, 62, 255))
x = 10
for im in row:
    sheet.alpha_composite(im, (x, H + 10 - im.height))
    x += im.width + 20
sheet.save(out)
print(out, sheet.size)
