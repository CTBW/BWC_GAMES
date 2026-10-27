"""Remove cloak B's two long front flaps by hand: interior fill above the hem, white below."""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGB')
a = np.asarray(im).astype(np.float32)
H, W = a.shape[:2]

L = [(470,100),(450,300),(420,450),(380,560),(350,690),(300,790),(250,890),(195,1045),(200,1120),(240,1200),(270,1240),(290,1300),(330,1350),(370,1390),(430,1440),(515,1505),(490,1420),(505,1300),(500,1200),(515,1080),(530,950),(550,800),(575,600),(605,400),(640,250),(660,100)]
R = [(140,135),(140,300),(180,500),(220,700),(250,900),(265,1100),(275,1300),(290,1450),(285,1500),(360,1410),(380,1380),(400,1350),(410,1300),(430,1310),(450,1250),(445,1200),(425,1050),(405,900),(385,700),(350,500),(300,300),(255,135)]
m = Image.new('L', (W, H), 0)
d = ImageDraw.Draw(m)
d.polygon([(x+300, y+450) for x, y in L], fill=255)
d.polygon([(x+950, y+450) for x, y in R], fill=255)
m = m.filter(ImageFilter.MaxFilter(9))          # take the flaps' own outlines too
mask = np.asarray(m) > 0

# ragged hem line continuing the back panel's hem
rng = np.random.default_rng(7)
xs = np.arange(W)
hem = 1556 + 10*np.sin(xs/23.0) + 7*np.sin(xs/9.0+1.3)
x0 = 440
while x0 < 1460:                                 # torn teeth
    w = int(rng.integers(18, 46)); h = float(rng.integers(10, 38))
    t = np.abs(np.linspace(-1, 1, w))
    hem[x0:x0+w] -= h*(1-t)
    x0 += w + int(rng.integers(0, 20))
yy = np.arange(H)[:, None]
below = yy >= hem[None, :]

zone = np.zeros((H, W), bool)                    # everything of the flaps under the hem
zone[:, 465:905] = True
zone[:, 1178:1425] = True
white = (mask | zone) & below
fill = mask & ~below

# interior colour per row, from the dark centre between the flaps
band = a[:, 960:1090, :]
lum = band.mean(axis=2)
row = np.zeros((H, 3), np.float32)
for y in range(H):
    sel = band[y][(lum[y] > 40) & (lum[y] < 120)]
    row[y] = sel.mean(axis=0) if len(sel) else (row[y-1] if y else (70, 62, 50))
row = np.asarray(Image.fromarray(row[None].astype(np.uint8)).filter(ImageFilter.GaussianBlur(6)))[0].astype(np.float32)
row = np.asarray([np.convolve(row[:, c], np.ones(41)/41, mode='same') for c in range(3)]).T
folds = 1.0 + 0.10*np.sin(xs/31.0) + 0.06*np.sin(xs/13.0+0.7)
shade = row[:, None, :] * folds[None, :, None] * 0.92

b = a.copy()
b[fill] = shade[fill]
b[white] = 255.0

# dark outline round the new hem and along the new front edges
ink = np.array([38, 24, 20], np.float32)
cloth = ~(white) & (b.mean(axis=2) < 235)
mi = Image.fromarray((white*255).astype(np.uint8)).filter(ImageFilter.MaxFilter(9))
edge = (np.asarray(mi) > 0) & cloth & (fill | zone)
fm = Image.fromarray((fill*255).astype(np.uint8))
edge2 = (np.asarray(fm.filter(ImageFilter.MaxFilter(7))) > 0) & ~fill & cloth & (b.mean(axis=2) > 70)
b[edge | edge2] = ink

res = Image.fromarray(np.clip(b, 0, 255).astype(np.uint8))
res = Image.composite(res.filter(ImageFilter.GaussianBlur(0.8)), res,
                      Image.fromarray(((white | fill | edge | edge2)*255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5)))
res.save(out)
