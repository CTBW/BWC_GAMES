"""Paint the jaw plate's texture from the iron jaw in the bust (face_jaw.png), and place its
rivets where the bust has them.

  python jaw_texture.py <face_jaw.png> <plate grid .npz> <out.png> <rivets.json> [px]

The plate's grid is the one jaw_plate.py saves; the bust is the jaw guard's in
../../orc_brute/ (see its prompts.md).

The bust shows the plate from the front as a U: a cup under the chin and a bar up each side
to the ear. The U is unrolled along rays from O, a point between the bar tops: along each ray
the plate runs from its inner edge (the rolled top rim, toward the mouth) to its outer edge.
The 3D band (jaw_plate.py) runs theta -100..100 deg (u 0..1) and t 0..1 from its top edge
(v 1.0) to its bottom edge (V0); each of its columns takes the ray at the same share of the
U's length (along its middle) as the column's share of the band's length, so the painted
rims and outline land on the 3D rims and no part is stretched more than another.
The painted rivets are filled first with nearby iron (their tone matched by a membrane), as
the 3D plate carries its own domes; rivets.json gives the domes' (deg, t) at the bust's
rivets. UV layout as jaw_plate.py: the inside a dark patch INNER_BOX, the domes RIV_BOX
(centre = the dome's top, box edge = its base)."""
import json
import math
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw

src, grid_p, out, riv_out = sys.argv[1:5]
N = int(sys.argv[5]) if len(sys.argv) > 5 else 2048
V0, V1 = 0.70, 1.0
INNER_BOX = (0.03, 0.05, 0.62, 0.62)
RIV_BOX = (0.68, 0.33, 0.97, 0.62)
TH_END = 100.0
O = np.array([2045.5, 1236.0])        # between the bar tops (x, y)
DARKEN = 0.86                          # a little darker, toward the pauldrons' steel
# Painted rivet heads, true centres (x, y), radius to fill, kind: the cup's two rows and
# the three on each bar's outer edge (those stick out past the bar).
RIVETS = [(1620, 1828, 68, "cup"), (1788, 1896, 68, "cup"), (2048, 1933, 68, "cup"), (2312, 1896, 68, "cup"),
          (2477, 1827, 68, "cup"), (1607, 1994, 68, "cup"), (1777, 2109, 68, "cup"), (2052, 2156, 68, "cup"),
          (2323, 2107, 68, "cup"), (2493, 1995, 68, "cup"),
          (1470, 1405, 42, "bar"), (1475, 1565, 42, "bar"), (1490, 1725, 42, "bar"),
          (2621, 1405, 42, "bar"), (2616, 1565, 42, "bar"), (2601, 1725, 42, "bar")]

im = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)


def plate_mask(im):
    """The plate in the bust: iron (grey, unsaturated) and its rust (orange), flooded from the
    middle of the chin cup within a box round the jaw."""
    mx, mn = im.max(-1), im.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1)
    r, g = im[..., 0], im[..., 1]
    rust = (r > g * 1.25) & (r > 90) & (sat > 0.3) & (sat < 0.75) & (g > 40)
    cand = ((sat < 0.24) & (mx > 40) & (mx < 235)) | rust
    x0, x1, y0, y1 = 1300, 2800, 1100, 2400
    m = np.zeros(cand.shape, bool)
    q = deque([(2050, 2049)])
    m[2050, 2049] = True
    while q:
        y, x = q.popleft()
        for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if y0 <= yy < y1 and x0 <= xx < x1 and not m[yy, xx] and cand[yy, xx]:
                m[yy, xx] = True
                q.append((yy, xx))
    return m


mask = plate_mask(im)
H, W, _ = im.shape
dark = im.max(-1) < 75


def refine(x, y, r):
    """The rivet's centre: the middle of the dark ring round its head."""
    yy, xx = np.mgrid[y - r:y + r + 1, x - r:x + r + 1]
    m = dark[y - r:y + r + 1, x - r:x + r + 1] & (np.hypot(xx - x, yy - y) < r)
    if m.sum() < 30:
        return x, y
    return int(round(xx[m].mean())), int(round(yy[m].mean()))


RIVETS = [(*refine(x, y, r), r, k) for (x, y, r, k) in RIVETS]
for rv in RIVETS:
    print("RIVET_AT", rv)


# --- 1. Fill the painted rivets ------------------------------------------------------------
def disk(r, pad=4):
    yy, xx = np.mgrid[-r - pad:r + pad + 1, -r - pad:r + pad + 1]
    rr = np.hypot(xx, yy)
    return rr < r, (rr >= r) & (rr < r + 2), (rr >= r) & (rr < r + pad)


def membrane(d, inside, edge):
    m = d.copy()
    m[inside] = d[edge].mean(0)
    for _ in range(900):
        avg = 0.25 * (np.roll(m, 1, 0) + np.roll(m, -1, 0) + np.roll(m, 1, 1) + np.roll(m, -1, 1))
        m[inside] = avg[inside]
    return m


def patch(img, x, y, r, pad=4):
    return img[y - r - pad:y + r + pad + 1, x - r - pad:x + r + pad + 1]


filled = im.copy()
todo = list(RIVETS)

# The cup's rims, per column, to keep the cup's sources off them.
CUP_X = np.arange(1560, 2532)
cup_top = np.array([np.nonzero(mask[1500:2450, x])[0].min() + 1500 for x in CUP_X], float)
cup_bot = np.array([np.nonzero(mask[1500:2450, x])[0].max() + 1500 for x in CUP_X], float)


def cup_clear(sx, sy, r):
    i0, i1 = sx - r - CUP_X[0], sx + r - CUP_X[0]
    if i0 < 0 or i1 >= len(CUP_X):
        return False
    return sy - r >= cup_top[i0:i1 + 1].max() + 45 and sy + r <= cup_bot[i0:i1 + 1].min() - 15


def free_of_rivets(sx, sy, r, me):
    return all(np.hypot(sx - a, sy - b) >= r + rb + 6 for (a, b, rb, _) in todo if (a, b) != me[:2]) and \
        np.hypot(sx - me[0], sy - me[1]) >= 2 * r + 6


def fill(rv, mirror_ok):
    x, y, r, kind = rv
    inside, edge, ring = disk(r)
    t = patch(filled, x, y, r)
    best = None
    if kind == "cup":
        cands = [(dx, dy) for dx in list(range(-360, -80, 6)) + list(range(84, 366, 6)) for dy in range(-60, 61, 12)]
    else:
        # Along the bar, between its rivets.
        cands = [(dx, dy) for dx in (-6, 0, 6) for dy in list(range(-96, -71, 4)) + list(range(72, 97, 4))]
    own = mask[y - r:y + r + 1:3, x - r:x + r + 1:3].mean()
    for dx, dy in cands:
        sx, sy = x + dx, y + dy
        if not free_of_rivets(sx, sy, r, rv):
            continue
        cover = mask[sy - r:sy + r + 1:3, sx - r:sx + r + 1:3].mean()
        if (kind == "cup" and (cover < 0.97 or not cup_clear(sx, sy, r))) or (kind == "bar" and cover < own - 0.12):
            continue
        s = patch(filled, sx, sy, r)
        dd = s[ring] - t[ring]
        err = float(((dd - dd.mean(0)) ** 2).mean()) + 0.002 * (dx * dx + dy * dy)
        if best is None or err < best[0]:
            best = (err, sx, sy)
    if best is None:
        if not mirror_ok:
            return False
        # None near (the rust, the cup's corners): the plate is nearly symmetric, so its
        # mirror image, filled already.
        sx, sy = int(round(2 * O[0] - x)), y
        s = patch(filled, sx, sy, r)[:, ::-1]
        best = (-1.0, sx, sy)
    else:
        _, sx, sy = best
        s = patch(filled, sx, sy, r)
    d = np.zeros_like(t)
    d[edge] = (t - s)[edge]
    out_p = t.copy()
    out_p[inside] = (s + membrane(d, inside, edge))[inside]
    filled[y - r - 4:y + r + 5, x - r - 4:x + r + 5] = out_p
    todo.remove(rv)
    print("FILL (%d, %d) from (%d, %d) err %.0f" % (x, y, sx, sy, best[0]))
    return True


deferred = [rv for rv in RIVETS if not fill(rv, False)]
for rv in deferred:
    fill(rv, True)
assert not todo, todo
filled *= DARKEN


# --- 2. Unroll the U ------------------------------------------------------------------------
def bilinear(img, x, y):
    x0 = np.clip(np.floor(x).astype(int), 0, W - 2)
    y0 = np.clip(np.floor(y).astype(int), 0, H - 2)
    u, v = (x - x0)[..., None], (y - y0)[..., None]
    a = img[y0, x0] * (1 - u) + img[y0, x0 + 1] * u
    b = img[y0 + 1, x0] * (1 - u) + img[y0 + 1, x0 + 1] * u
    return a * (1 - v) + b * v


# The plate's silhouette with its holes (rust, highlights) filled: everything the outside
# cannot reach without crossing the plate, found at half size in the jaw's box.
X0, X1, Y0, Y1 = 1300, 2800, 1100, 2450
m2 = mask[Y0:Y1:2, X0:X1:2]
outside = np.zeros_like(m2)
outside[0, :] = outside[-1, :] = outside[:, 0] = outside[:, -1] = True
outside &= ~m2
while True:
    grown = outside.copy()
    grown[1:] |= outside[:-1]
    grown[:-1] |= outside[1:]
    grown[:, 1:] |= outside[:, :-1]
    grown[:, :-1] |= outside[:, 1:]
    grown &= ~m2
    if (grown == outside).all():
        break
    outside = grown
solid = np.zeros_like(mask)
solid[Y0:Y1, X0:X1] = np.repeat(np.repeat(~outside, 2, 0), 2, 1)[:Y1 - Y0, :X1 - X0]
print("SOLID px", int(solid.sum()), "mask px", int(mask[Y0:Y1, X0:X1].sum()))

# Rays from O, from the left bar's top (phi ~181 deg, image y down) round the cup to the right
# bar's top (~-1 deg): the first plate pixel and the end of that run (gaps under 6 px bridged).
PHI = np.radians(np.linspace(200.0, -20.0, 2201))
r_in = np.full(len(PHI), np.nan)
r_out = np.full(len(PHI), np.nan)
rs = np.arange(60, 1300, 1.0)
for i, ph in enumerate(PHI):
    d = np.array([math.cos(ph), math.sin(ph)])
    pts = O[None, :] + rs[:, None] * d[None, :]
    ok = (pts[:, 0] >= 0) & (pts[:, 0] < W) & (pts[:, 1] >= 0) & (pts[:, 1] < H)
    hit = np.zeros(len(rs), bool)
    hit[ok] = solid[pts[ok, 1].astype(int), pts[ok, 0].astype(int)]
    idx = np.nonzero(hit)[0]
    if len(idx) == 0:
        continue
    a = b = idx[0]
    while b + 1 < len(rs) and hit[b + 1:b + 7].any():
        b += 1
    r_in[i], r_out[i] = rs[a], rs[b]
got = ~np.isnan(r_in)
# Only the rays that cross the bar fully (the bar tops are rounded: drop the grazing rays).
width = r_out - r_in
core = np.nanmedian(width[got])
keep = got & (width > 0.35 * core)
first, last = np.nonzero(keep)[0][[0, -1]]
PHI, r_in, r_out = PHI[first:last + 1], r_in[first:last + 1], r_out[first:last + 1]
bad = np.isnan(r_in) | (r_out - r_in < 0.35 * core)
for arr in (r_in, r_out):
    arr[bad] = np.interp(np.nonzero(bad)[0], np.nonzero(~bad)[0], arr[~bad])


def smooth(a, n):
    w = np.ones(n) / n
    return np.convolve(np.pad(a, n // 2, mode="edge"), w, "valid")


def median(a, n):
    p = np.pad(a, n // 2, mode="edge")
    return np.array([np.median(p[i:i + n]) for i in range(len(a))])


# The bar rivets bulge past the bars' outer edge (filled with plain bar now): a running
# median over 12 deg of rays takes the bulges out.
# Then snap it to the plate's outline: coming in from the brown skin outside, the first
# pixels that are not skin (in the filled image, whose bars have straight edges again).
r_in = smooth(r_in, 9)
guess = smooth(median(r_out, 121), 61)
fmx = filled.max(-1)
fsat = (fmx - filled.min(-1)) / np.maximum(fmx, 1)
skin = ((fsat > 0.28) & (fmx > 60 * DARKEN) & (filled[..., 0] > filled[..., 2] + 20)) |     ((fmx > 200 * DARKEN) & (fsat < 0.15))     # or the white background past the bar tops
for i, ph in enumerate(PHI):
    d = np.array([math.cos(ph), math.sin(ph)])
    rr_ = np.arange(guess[i] + 45, guess[i] - 80, -1.0)
    q = (O[None, :] + rr_[:, None] * d[None, :]).astype(int)
    sk = skin[q[:, 1], q[:, 0]]
    k = next((j for j in range(len(rr_) - 3) if not sk[j:j + 3].any()), None)
    r_out[i] = rr_[k] - 2 if k is not None and abs(rr_[k] - guess[i]) < 35 else guess[i]
r_out = smooth(median(r_out, 31), 15)
dirs = np.stack([np.cos(PHI), np.sin(PHI)], 1)
mid = O[None, :] + dirs * ((r_in + r_out) / 2)[:, None]
S = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(mid, axis=0), axis=1))])
S /= S[-1]
print("U rays %d, phi %.1f..%.1f deg, width median %.0f px" % (len(PHI), math.degrees(PHI[0]), math.degrees(PHI[-1]), core))

# The 3D band's length along its middle row, per column.
g = np.load(grid_p)
cols, inner = g["cols"], g["inner"]
midrow = inner[:, inner.shape[1] // 2]
A = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(midrow, axis=0), axis=1))])
A /= A[-1]
IDX = np.arange(len(PHI))


def bust_xy(theta_rad, t):
    a = np.interp(theta_rad, cols, A)
    k = np.interp(a, S, IDX)
    ph = np.interp(k, IDX, PHI)
    ri = np.interp(k, IDX, r_in)
    ro = np.interp(k, IDX, r_out)
    r = ri + t * (ro - ri)
    return O[0] + np.cos(ph) * r, O[1] + np.sin(ph) * r


tex = np.zeros((N, N, 3), np.float32)
v_rows = 1.0 - (np.arange(N) + 0.5) / N
r_idx = np.nonzero((v_rows >= V0 - 0.004) & (v_rows <= V1))[0]
u = (np.arange(N) + 0.5) / N
theta = np.radians((u * 2 - 1) * TH_END)
t = np.clip((V1 - v_rows[r_idx]) / (V1 - V0), 0, 1)
TT, TH = np.meshgrid(t, theta, indexing="ij")
bx, by = bust_xy(TH, TT)
tex[r_idx] = bilinear(filled, bx, by)


# --- 3. The inside, the rivet head ----------------------------------------------------------
def box_px(box):
    x0, y0, x1, y1 = box
    return int(x0 * N), int((1 - y1) * N), int(x1 * N), int((1 - y0) * N)


ix0, iy0, ix1, iy1 = box_px(INNER_BOX)
band_img = Image.fromarray(np.clip(tex[r_idx], 0, 255).astype(np.uint8))
inner_px = np.asarray(band_img.resize((ix1 - ix0 + 16, iy1 - iy0 + 16), Image.BILINEAR)).astype(np.float32)
grey = inner_px.mean(-1, keepdims=True)
tex[iy0 - 8:iy1 + 8, ix0 - 8:ix1 + 8] = (inner_px * 0.4 + grey * 0.6) * 0.38
rx, ry, rad = RIVETS[2][0], RIVETS[2][1], 58
crop = Image.fromarray(np.clip(im[ry - rad:ry + rad, rx - rad:rx + rad] * DARKEN, 0, 255).astype(np.uint8))
x0, y0, x1, y1 = box_px(RIV_BOX)
tex[y0 - 8:y1 + 8, x0 - 8:x1 + 8] = np.asarray(crop.resize((x1 - x0 + 16, y1 - y0 + 16), Image.BICUBIC)).astype(np.float32)
empty = tex.sum(-1) == 0
tex[empty] = np.array([48, 48, 52], np.float32)
Image.fromarray(np.clip(tex, 0, 255).astype(np.uint8)).save(out)

# --- 4. The domes at the bust's rivets: (deg, t) by inverting the unroll --------------------
TH_F = np.radians(np.linspace(-TH_END, TH_END, 2001))
A_F = np.interp(TH_F, cols, A)
domes = []
for (x, y, r, kind) in RIVETS:
    p = np.array([x, y], float) - O
    ph = math.atan2(p[1], p[0])
    if ph < PHI[-1] - 0.5:
        ph += 2 * math.pi
    k = np.interp(-ph, -PHI, IDX)     # PHI decreases
    a = np.interp(k, IDX, S)
    th = float(np.interp(a, A_F, TH_F))
    ri = np.interp(k, IDX, r_in)
    ro = np.interp(k, IDX, r_out)
    tt = float((np.linalg.norm(p) - ri) / (ro - ri))
    domes.append([round(math.degrees(th), 1), round(tt, 3), kind])
print("DOMES", domes)
json.dump(domes, open(riv_out, "w"))
# Checks, next to the rivets file: the U's inner and outer edges on the bust, and the bust
# with its painted rivets filled.
dbg = Image.fromarray(np.clip(filled, 0, 255).astype(np.uint8))
dr = ImageDraw.Draw(dbg)
pi = O[None, :] + dirs * r_in[:, None]
po = O[None, :] + dirs * r_out[:, None]
dr.line([tuple(q) for q in pi], fill=(0, 255, 0), width=5)
dr.line([tuple(q) for q in po], fill=(255, 0, 255), width=5)
for k in range(0, len(PHI), 60):
    dr.line([tuple(pi[k]), tuple(po[k])], fill=(255, 255, 0), width=2)
stem = riv_out[:-5] if riv_out.endswith(".json") else riv_out
dbg.crop((1300, 1100, 2800, 2450)).resize((750, 675)).save(stem + "_contours.png")
check = Image.fromarray(np.clip(filled, 0, 255).astype(np.uint8)).crop((1380, 1180, 2720, 2350))
check.resize((670, 585)).save(stem + "_fill_check.png")
print("TEXTURE", out, N)
