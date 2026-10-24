"""Cut the front spearman (bottom centre) out of references/characters/Pikemen.png.

Body: OpenCV GrabCut seeded with hand-placed boxes (full-image coordinates).
Spear: drawn as an explicit polygon, because its thin shaft crosses the
neighbours and the grass, where GrabCut loses it.
"""
import sys
import numpy as np, cv2
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

SRC, OUT = sys.argv[1], sys.argv[2]
ox, oy, ox1, oy1 = 430, 240, 790, 1100          # crop box in the sheet
full = np.array(Image.open(SRC).convert('RGB'))
im = full[oy:oy1, ox:ox1].copy()
h, w = im.shape[:2]

mask = np.full((h, w), cv2.GC_BGD, np.uint8)
def R(x0, y0, x1, y1, v):
    mask[max(0, y0-oy):max(0, y1-oy), max(0, x0-ox):max(0, x1-ox)] = v

R(440, 535, 760, 1095, cv2.GC_PR_FGD)
# Neighbours: top-centre soldier above and behind the head, his spear and boots;
# the left soldier's boot and tabard.
R(430, 240, 790, 538, cv2.GC_BGD)
R(660, 538, 790, 598, cv2.GC_BGD)
R(740, 560, 790, 720, cv2.GC_BGD)
R(430, 538, 545, 605, cv2.GC_BGD)
R(430, 700, 452, 840, cv2.GC_BGD)
# Ground between and below the boots.
g = np.array([(560, 937), (646, 937), (662, 985), (688, 1100), (430, 1100), (430, 1008), (532, 1008), (556, 962)], np.int32)
cv2.fillPoly(mask, [g - [ox, oy]], cv2.GC_BGD)
# Sure figure: hair and face, scarf, torso, tabard, trousers, boots.
R(600, 560, 650, 640, cv2.GC_FGD)
R(560, 650, 690, 690, cv2.GC_FGD)
R(575, 700, 670, 780, cv2.GC_FGD)
R(585, 810, 630, 910, cv2.GC_FGD)
R(680, 880, 720, 940, cv2.GC_FGD)
R(722, 1020, 748, 1070, cv2.GC_FGD)
R(462, 955, 498, 995, cv2.GC_FGD)

bgd = np.zeros((1, 65), np.float64); fgd = np.zeros((1, 65), np.float64)
cv2.grabCut(cv2.cvtColor(im, cv2.COLOR_RGB2BGR), mask, None, bgd, fgd, 10, cv2.GC_INIT_WITH_MASK)
body = (mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD)

# The spear, in sheet coordinates: a leaf blade, the wrapped socket, a straight shaft and the steel butt cap.
sp = Image.new('L', (w, h), 0)
d = ImageDraw.Draw(sp)
P = lambda pts: [(x - ox, y - oy) for x, y in pts]
d.polygon(P([(479, 254), (489, 290), (501, 352), (497, 376), (494, 383), (472, 383), (468, 376), (460, 360), (470, 300)]), fill=255)
d.polygon(P([(469, 380), (498, 380), (498, 442), (469, 442)]), fill=255)
cx = lambda y: 486 + 0.0539 * (y - 440)
d.polygon(P([(cx(440) - 9.5, 440), (cx(440) + 10, 440), (cx(1052) + 10, 1052), (cx(1052) - 9.5, 1052)]), fill=255)
d.ellipse(P([(cx(1052) - 10, 1044), (cx(1052) + 10, 1061)]), fill=255)
spear = np.array(sp) > 127
# Grass and dirt that the shaft's outline band caught at its edges (greenish or pale olive, not the brown wood).
r, g, b = (im[..., i].astype(int) for i in range(3))
spear &= ~(~body & (g > 0.8 * r) & (b < 0.7 * g))

a = body | spear
lab, n = ndi.label(a)
if n > 1:
    sizes = ndi.sum(a, lab, range(1, n + 1))
    a = lab == (1 + int(np.argmax(sizes)))
holes = ndi.binary_fill_holes(a) & ~a
hl, hn = ndi.label(holes)
for i, sz in enumerate(ndi.sum(holes, hl, range(1, hn + 1)) if hn else [], 1):
    if sz <= 60:
        a[hl == i] = True
np.save(OUT + '/mask.npy', a)
alpha = ndi.gaussian_filter(a.astype(float), 0.6)
alpha = np.clip((alpha - 0.15) / 0.7, 0, 1)
rgba = np.dstack([im, (alpha * 255).astype(np.uint8)])
Image.fromarray(rgba).save(OUT + '/cut.png')
v = Image.new('RGBA', (w, h), (255, 0, 255, 255)); v.alpha_composite(Image.fromarray(rgba))
v.resize((w * 2, h * 2), Image.NEAREST).save(OUT + '/cut_view.png')
print('components', n, 'pixels', int(a.sum()))
