"""Paint tribal markings in dried blood on the goblin shaman's skin (background Blender).

  blender -b goblin_shaman_beak_base.blend --factory-startup --python paint_goblin_shaman.py -- <tripo dir> [<out.jpg>]

build_goblin_shaman.py paints the body this way in every build, before the mask is fitted.
Run alone, this reads Tripo's unpainted base colour from `body__take-01.zip` in the Tripo
dir and writes `textures/goblin_shaman_body_basecolor.jpg` (or <out.jpg>), which every
blend uses. Run on goblin_shaman_beak_base.blend, whose face the mask leaves as Tripo made
it, painting again gives the same texture (the horned plate's fit moves his face).
1. Each texel of the body's UV map gets the point of the T-posed body it shows: every UV
   triangle is filled with its corners' positions, mixed by barycentric weights.
2. Skin: texels of the body and the legs (the other shells are his eyes, tusks, necklace
   and belt gear) whose colour is the olive of his skin (SKIN_HUE); the leather, the
   cloth and the bone are browner, redder or greyer.
3. The markings are drawn in metres round his limbs and on his head: along each limb from
   its upper joint (the rig's joints, rig_goblin_shaman.py) and round it from its outer
   side (an arm's top in the T-pose, which faces out when it hangs) or its front (a leg).
   On each arm: three finger marks raked down the shoulder, a band round the biceps with
   blood run from it toward the elbow, a row of diamonds between two rings below the
   elbow, and fingers stained with blood. On each leg: two slashes across the outer thigh
   above the knee, chevrons down the shin, and a ring above the ankle with runs toward the
   foot. On the head: four fingers dragged from the brow over the crown to the nape, a
   band round each ear and its tip dipped, and three stripes down the throat. The runs
   go down his arms and legs as they hang; where they fall is random but fixed (DRIPS).
4. Dried blood: every line wanders and swells and thins (WOBBLE, WIDTH_VAR), with ragged
   edges, and thins or breaks off where the finger lifted (BREAKS). It lies thick, dark
   and cracked in patches and along its rims, where it dried first, and thin and rusty
   elsewhere, with chips broken off, dry-brush gaps toward its edges, thin smears past
   them (SMEAR) and a spatter of small drops round it. Its colour is multiplied by the
   skin's own shading, so Tripo's light and shade show through. Each mark is spread a
   few texels past its UV island's edge, so no green line shows along a seam.
"""
import os
import shutil
import sys
import tempfile
import time
import zipfile
from pathlib import Path

import bpy
import numpy as np

# Joints of the T-pose, the left side (+x; the right mirrors it), as rig_goblin_shaman.py J0.
SHOULDER, ELBOW, WRIST = (0.20, 0.02, 1.12), (0.44, -0.005, 1.075), (0.69, -0.11, 1.063)
HIP, KNEE, ANKLE = (0.105, -0.02, 0.645), (0.18, -0.055, 0.40), (0.222, -0.03, 0.095)
UP, FRONT = (0, 0, 1), (0, -1, 0)
# Skin: hue (degrees) of his olive skin, fading out over SKIN_SOFT, and a floor on its
# saturation and value; the leather is 5-25 degrees, the red cloth 355, the bone grey.
SKIN_HUE = (29.0, 62.0)
SKIN_SOFT = 4.0
SKIN_SAT, SKIN_VAL = 0.28, 0.10
# Dried blood (sRGB): thick and dark where it pooled and along its rims, thin and rusty
# elsewhere, and how strongly each covers.
THICK, THIN = np.array([0.19, 0.035, 0.025]), np.array([0.40, 0.10, 0.055])
COVER = (0.5, 0.97)
EDGE = 0.0006
RAGGED = 0.0015       # how far fine noise moves an edge
WIDTH_VAR = 0.0035    # how much a line swells and thins
WOBBLE = ((0.006, 0.05), (0.002, 0.012))   # how far a line wanders, over what length (m)
BREAKS = 0.006        # how far a line thins, or breaks, where the finger lifted
SMEAR = 0.005         # how far thin smears reach past a mark
SPATTER = 0.014       # how far from a mark its spatter reaches
DRIPS = 7             # seed of the runs' places and lengths
SPREAD = 8            # texels each mark is spread past its island's edge


def texel_map(me, size):
    """(texel index, point, shell) of every texel a UV triangle of `me` covers."""
    me.calc_loop_triangles()
    n = len(me.loop_triangles)
    loops = np.empty(n * 3, np.int32)
    me.loop_triangles.foreach_get("loops", loops)
    tv = np.empty(n * 3, np.int32)
    me.loop_triangles.foreach_get("vertices", tv)
    tv = tv.reshape(n, 3)
    uv = np.empty(len(me.loops) * 2, np.float32)
    me.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)[loops].reshape(n, 3, 2) * size - 0.5
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    idx, pos, tri = [], [], []
    for k in range(n):
        p = uv[k]
        x0, y0 = np.maximum(np.floor(p.min(0)).astype(int), 0)
        x1, y1 = np.minimum(np.ceil(p.max(0)).astype(int), size - 1)
        a, b, c = p
        d = (b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])
        if x1 < x0 or y1 < y0 or abs(d) < 1e-9:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        w1 = ((xs - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (ys - a[1])) / d
        w2 = ((b[0] - a[0]) * (ys - a[1]) - (xs - a[0]) * (b[1] - a[1])) / d
        w0 = 1 - w1 - w2
        m = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if m.any():
            idx.append(ys[m] * size + xs[m])
            pos.append(np.stack([w0[m], w1[m], w2[m]], 1) @ co[tv[k]])
            tri.append(np.full(int(m.sum()), k, np.int32))
    idx, pos, tri = np.concatenate(idx), np.concatenate(pos), np.concatenate(tri)
    # Shells, largest first: 0 the body (head, arms, torso, skirt), 1 and 2 the legs.
    parent = np.arange(len(me.vertices))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    ev = np.empty(len(me.edges) * 2, np.int32)
    me.edges.foreach_get("vertices", ev)
    for a, b in ev.reshape(-1, 2):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    root = np.array([find(i) for i in range(len(parent))])
    ids, counts = np.unique(root, return_counts=True)
    rank = np.empty(root.max() + 1, int)
    rank[ids[np.argsort(-counts)]] = np.arange(len(ids))
    return idx, pos, rank[root[tv[tri, 0]]]


def hsv(rgb):
    mx, mn = rgb.max(1), rgb.min(1)
    dm = np.maximum(mx - mn, 1e-6)
    r, g, b = rgb.T
    h = np.where(mx == r, ((g - b) / dm) % 6, np.where(mx == g, (b - r) / dm + 2, (r - g) / dm + 4)) * 60
    return h, np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0), mx


def smooth(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def noise(P, cell, seed):
    """Smooth value noise, -1 to 1, on a lattice `cell` metres apart."""
    Q = P / cell + seed * 17.31
    i = np.floor(Q).astype(np.int64)
    f = Q - i
    f = f * f * (3 - 2 * f)

    def h(dx, dy, dz):
        k = ((i[:, 0] + dx) * 73856093) ^ ((i[:, 1] + dy) * 19349663) ^ ((i[:, 2] + dz) * 83492791) ^ (seed * 2654435761)
        k = (k ^ (k >> 13)) * 1274126177
        return ((k >> 8) & 0xFFFF) / 32767.5 - 1

    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                out = out + w * h(dx, dy, dz)
    return out


def fbm(P, cell, seed, octaves=3):
    return sum(noise(P, cell / 2 ** o, seed + o) / 2 ** o for o in range(octaves)) / (2 - 2 ** (1 - octaves))


def limb(P, s, a, b, ref):
    """Along (metres from joint a), round (radians from `ref`, positive toward the front
    on an arm and toward the outside on a leg) and the distance from the limb's axis."""
    a = np.array(a) * (s, 1, 1)
    b = np.array(b) * (s, 1, 1)
    e = (b - a) / np.linalg.norm(b - a)
    r = np.array(ref, float)
    r = r - (r @ e) * e
    r /= np.linalg.norm(r)
    q = P - a
    u = q @ e
    q = q - u[:, None] * e
    th = np.arctan2(q @ np.cross(e, r), q @ r)
    # An arm's cross(e, up) is the front on the left and the back on the right; a leg's
    # cross(down, front) is -x, the inside on the left.
    th = th * (s if ref == UP else -s)
    return u, th, np.linalg.norm(q, axis=1)


def seg_dist(P, a, b):
    """Distance of each point from the segment a-b and how far along it (0-1)."""
    a, b = np.array(a), np.array(b)
    t = np.clip(((P - a) @ (b - a)) / ((b - a) @ (b - a)), 0, 1)
    return np.linalg.norm(P - a - t[:, None] * (b - a), axis=1), t


def band(u, lo, hi):
    return np.maximum(lo - u, u - hi)


def stroke(x, y, p, q, w):
    """A brush stroke from p to q (x, y in metres), w wide in its middle, tapering to
    points at both ends."""
    p, q = np.array(p), np.array(q)
    d = q - p
    t = np.clip(((x - p[0]) * d[0] + (y - p[1]) * d[1]) / (d @ d), 0, 1)
    dist = np.hypot(x - p[0] - t * d[0], y - p[1] - t * d[1])
    return dist - w / 2 * np.sqrt(np.sin(np.pi * t))


def periodic(th, n):
    """Distance round the limb from the nearest of n evenly spaced places (radians)."""
    k = th * n / (2 * np.pi)
    return (k - np.round(k)) * 2 * np.pi / n


def zigzag(t, period):
    """A triangle wave, 0 at every multiple of `period` and 1 halfway between."""
    k = t / period
    return 2 * np.abs(k - np.floor(k + 0.5))


def turn(th, th0):
    """Angle from th0 to th, -pi to pi."""
    return (th - th0 + np.pi) % (2 * np.pi) - np.pi


def drips(rng, n, length, width, at=(-2.2, 2.2)):
    """n random places round a limb (radians from its outer side or front, within `at`;
    its inside is hidden), with lengths and widths drawn from these ranges."""
    return rng.uniform(*at, n), rng.uniform(*length, n), rng.uniform(*width, n)


def runs(u, th, R0, u0, at, length, width):
    """Runs of blood from u0 down the limb (increasing u), one from each angle in `at`
    with its length and width, each narrowing to a bead at its end."""
    k = np.full(len(u), 1.0)
    for th0, L, w in zip(at, length, width):
        a = turn(th, th0) * R0
        f = np.clip((u - u0) / L, 0, 1)
        k = np.minimum(k, np.hypot(a, u - u0 - f * L) - w / 2 * (1 - 0.5 * f))
        k = np.minimum(k, np.hypot(a, u - u0 - L) - 0.6 * w)
    return k


def marks(P, shell):
    """Signed distance (metres, negative inside) of each point from the nearest marking."""
    d = np.full(len(P), 1.0)
    x, y, z = P.T
    for s in (1, -1):
        rng = np.random.default_rng(DRIPS + (s > 0))
        side = (x * s) > 0
        # Arms: the body's shell beside the shoulders.
        arm = side & (shell == 0) & (np.abs(x) > 0.17) & (z > 0.9) & (z < 1.22)
        da, _ = seg_dist(P, np.array(SHOULDER) * (s, 1, 1), np.array(ELBOW) * (s, 1, 1))
        df, _ = seg_dist(P, np.array(ELBOW) * (s, 1, 1), np.array(WRIST) * (s, 1, 1))
        m = arm & (da <= df)
        if m.any():
            u, th, rad = limb(P[m], s, SHOULDER, ELBOW, UP)
            R0 = 0.05
            a = th * R0
            # Three finger marks raked down the outside of the shoulder.
            k = np.full(m.sum(), 1.0)
            for j in (-1, 0, 1):
                k = np.minimum(k, stroke(u, a, (0.006, j * 0.026 + 0.020), (0.125, j * 0.026 - 0.020), 0.013))
            # A band round the biceps, blood run from it toward the elbow, a thin ring above.
            k = np.minimum(k, band(u, 0.146, 0.170))
            k = np.minimum(k, runs(u, th, R0, 0.166, *drips(rng, 6, (0.018, 0.060), (0.006, 0.011))))
            k = np.minimum(k, band(u, 0.128, 0.135))
            d[m] = np.minimum(d[m], k)
        m = arm & (da > df)
        if m.any():
            u, th, rad = limb(P[m], s, ELBOW, WRIST, UP)
            R0 = 0.042
            # Two rings below the elbow with a row of diamonds between them, and short runs.
            g = periodic(th + np.pi / 6, 6) * R0
            k = np.minimum(band(u, 0.018, 0.027), band(u, 0.093, 0.102))
            k = np.minimum(k, (np.abs(u - 0.060) / 0.024 + np.abs(g) / (np.pi * R0 / 6 * 0.85) - 1) * 0.012)
            k = np.minimum(k, runs(u, th, R0, 0.100, *drips(rng, 3, (0.008, 0.022), (0.005, 0.008))))
            # His fingers, stained with the blood he painted with, unevenly past the knuckles.
            Q = P[m]
            hand = np.abs(Q[:, 0]) > 0.66
            k = np.minimum(k, np.where(hand, 0.797 + 0.012 * fbm(Q, 0.02, 91, 2) - np.abs(Q[:, 0]), 1.0))
            d[m] = np.minimum(d[m], k)
        # Legs: the shells of their own.
        leg = side & ((shell == 1) | (shell == 2))
        dt, _ = seg_dist(P, np.array(HIP) * (s, 1, 1), np.array(KNEE) * (s, 1, 1))
        ds, _ = seg_dist(P, np.array(KNEE) * (s, 1, 1), np.array(ANKLE) * (s, 1, 1))
        m = leg & (dt <= ds)
        if m.any():
            u, th, rad = limb(P[m], s, HIP, KNEE, FRONT)
            R0 = 0.075
            # Two slashes across the outside of the thigh above the knee, a run from each.
            k = np.minimum(stroke(th * R0, u, (-0.022, 0.168), (0.112, 0.181), 0.017),
                           stroke(th * R0, u, (-0.012, 0.198), (0.106, 0.209), 0.015))
            k = np.minimum(k, runs(u, th, R0, 0.178, (0.53,), (0.020,), (0.007,)))
            k = np.minimum(k, runs(u, th, R0, 0.204, (0.80,), (0.032,), (0.007,)))
            d[m] = np.minimum(d[m], k)
        m = leg & (dt > ds)
        if m.any():
            u, th, rad = limb(P[m], s, KNEE, ANKLE, FRONT)
            R0 = 0.05
            a = th * R0
            # Chevrons down the front of the shin, pointing down.
            k = np.full(m.sum(), 1.0)
            for c in (0.070, 0.113, 0.156):
                for sa in (-1, 1):
                    k = np.minimum(k, stroke(a, u, (sa * 0.038, c - 0.027), (0.0, c), 0.012))
            # A ring above the ankle and runs from it toward the foot.
            k = np.minimum(k, band(u, 0.232, 0.247))
            k = np.minimum(k, runs(u, th, R0, 0.244, *drips(rng, 5, (0.010, 0.040), (0.006, 0.009), (-1.2, 2.8))))
            d[m] = np.minimum(d[m], k)
    # The head: above the shoulders, clear of the arms.
    head = (shell == 0) & (z > 1.17) & (np.abs(x) < 0.30)
    for s in (1, -1):
        da, _ = seg_dist(P, np.array(SHOULDER) * (s, 1, 1), np.array(ELBOW) * (s, 1, 1))
        head &= da > 0.085
    if head.any():
        Q = P[head]
        hx, hy, hz = Q.T
        ax = np.abs(hx)
        # The angle from straight up (0) round to behind (90): the crown is -30 to 15 and the
        # back of his skull 15 to 90, down to the nape at 100, where the vest's collar is.
        C = np.array((0.0, -0.10, 1.30))
        back = np.degrees(np.arctan2(hy - C[1], hz - C[2]))
        # Four fingers dragged from the brow over the crown, drawing a little together
        # toward the nape and wavering, each as wide as it pressed and running dry at its
        # own place.
        k = np.full(len(Q), 1.0)
        for fx, end, w, ph in ((-0.033, 78, 0.0062, 0.0), (-0.011, 99, 0.0082, 2.1),
                               (0.011, 91, 0.0076, 4.0), (0.033, 72, 0.0058, 5.3)):
            cx = fx * (1 - 0.18 * np.clip(back / 100, 0, 1)) + 0.0025 * np.sin(np.radians(back) * 3 + ph)
            hw = w * np.clip((end - back) / 22, 0, 1) ** 0.6
            k = np.minimum(k, np.maximum(np.abs(hx - cx) - hw, -(back + 60) * 0.001))
        # A band round each ear and its tip dipped in blood.
        ear = (ax > 0.11) & (hz > 1.26)
        k = np.minimum(k, np.where(ear, np.minimum(band(ax, 0.164, 0.175), band(ax, 0.191, 0.40)), 1.0))
        # Three stripes down the throat, under the mask.
        throat = (hy < C[1]) & (hz < 1.21)
        for sx in (-0.022, 0.0, 0.022):
            k = np.minimum(k, np.where(throat, np.abs(hx - sx) - 0.0045, 1.0))
        d[head] = np.minimum(d[head], k)
    return d


def paint_body(body, src, dst):
    """Paint `src` (Tripo's base colour) for `body` (T-posed) and save it as `dst`."""
    t0 = time.time()
    img = bpy.data.images.load(str(src))
    size = img.size[0]
    assert img.size[0] == img.size[1]
    px = np.empty(size * size * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    px = px.reshape(-1, 4)
    idx, P, shell = texel_map(body.data, size)
    rgb = px[idx, :3]
    h, s, v = hsv(rgb)
    skin = (smooth(h, SKIN_HUE[0] - SKIN_SOFT, SKIN_HUE[0]) * (1 - smooth(h, SKIN_HUE[1], SKIN_HUE[1] + SKIN_SOFT))
            * smooth(s, SKIN_SAT - 0.06, SKIN_SAT) * smooth(v, SKIN_VAL - 0.05, SKIN_VAL) * (shell <= 2))
    # The markings, wandering, swelling and thinning as a line drawn by hand does.
    d = np.full(len(P), 1.0)
    cand = skin > 0
    Pc = P[cand]
    warp = sum(amp * np.stack([fbm(Pc, cell, 41 + 3 * j + i, 2) for i in range(3)], 1)
               for j, (amp, cell) in enumerate(WOBBLE))
    d[cand] = marks(Pc + warp, shell[cand])
    near = d < SPATTER + 0.004
    Pn = P[near]
    dn = (d[near] + WIDTH_VAR * fbm(Pn, 0.02, 81, 2) + RAGGED * fbm(Pn, 0.0025, 3)
          + BREAKS * smooth(fbm(Pn, 0.03, 97, 2), 0.35, 0.65))
    # How thick it lies: in patches and along its rims, where it dried first.
    rim = np.exp(np.minimum(dn, 0) / 0.0012)
    thick = np.clip(0.4 + 0.8 * fbm(Pn, 0.012, 51, 3) + 0.35 * rim, 0, 1)
    # Dry-brush gaps toward the edges; where it lies thick it has cracked, and chips of
    # it have broken off.
    core = np.clip(-dn / 0.0025, 0, 1)
    dry = np.clip(0.55 + 1.3 * fbm(Pn, 0.0018, 11), 0, 1)
    crack = 1 - smooth(np.abs(noise(Pn, 0.006, 61)), 0.015, 0.045)
    chip = smooth(noise(Pn, 0.005, 63), 0.5, 0.58)
    a = (np.clip(0.5 - dn / EDGE, 0, 1) * (core + (1 - core) * dry)
         * (1 - 0.6 * crack * thick) * (1 - 0.9 * chip)
         * (COVER[0] + (COVER[1] - COVER[0]) * thick))
    # Thin smears past its edges, where it was wiped.
    out = dn > 0
    a = np.maximum(a, 0.35 * np.clip(1 - dn / SMEAR, 0, 1) * smooth(fbm(Pn, 0.008, 95, 2), 0.0, 0.4) * out)
    thick = np.where(out, 0.15, thick)
    # A spatter of small drops round each mark, fewer and smaller farther from it.
    far = np.clip(dn / SPATTER, 0, 1)
    sp = (smooth(noise(Pn, 0.0026, 71), 0.62 + 0.25 * far, 0.72 + 0.25 * far)
          * smooth(fbm(Pn, 0.02, 73, 2), -0.1, 0.2) * (dn > 0) * (dn < SPATTER))
    a = np.maximum(a, 0.85 * sp)
    thick = np.maximum(thick, sp)
    alpha = np.zeros(len(P), np.float32)
    alpha[near] = a * skin[near]
    # Its colour, times the skin's own shading.
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722])
    ref = np.median(lum[skin > 0.5])
    shade = np.clip(lum[near] / ref, 0.3, 1.35) ** 0.75
    red = np.zeros((len(P), 3), np.float32)
    red[near] = np.clip((THIN + (THICK - THIN) * thick[:, None]) * shade[:, None], 0, 1)
    # Into the whole image, then spread past the islands' edges.
    A = np.zeros(size * size, np.float32)
    A[idx] = alpha
    C = px[:, :3].copy()
    C[idx[near]] = red[near]
    covered = np.zeros(size * size, bool)
    covered[idx] = True
    A, C, covered = A.reshape(size, size), C.reshape(size, size, 3), covered.reshape(size, size)
    for _ in range(SPREAD):
        best_a = A.copy()
        best_c = C.copy()
        for ax, sh in ((0, 1), (0, -1), (1, 1), (1, -1)):
            na = np.roll(A, sh, ax)
            nc = np.roll(C, sh, ax)
            take = ~covered & (na > best_a)
            best_a[take] = na[take]
            best_c[take] = nc[take]
        grown = ~covered & (best_a > A)
        A[grown], C[grown] = best_a[grown], best_c[grown]
        covered = covered | grown
    base = px[:, :3].reshape(size, size, 3)
    out = base * (1 - A[..., None]) + C * A[..., None]
    new = bpy.data.images.new("paint_out", size, size)
    full = np.ones((size * size, 4), np.float32)
    full[:, :3] = out.reshape(-1, 3)
    new.pixels.foreach_set(full.ravel())
    new.filepath_raw = str(dst)
    new.file_format = "JPEG"
    new.save(quality=92)
    bpy.data.images.remove(new)
    for im in bpy.data.images:
        if Path(bpy.path.abspath(im.filepath)).resolve() == Path(dst).resolve():
            im.reload()
    print("SHAMAN_PAINT %d texels painted (%.1f%% of his skin), %d skin texels; %.0f s -> %s" % (
        int((alpha > 0.05).sum()), 100 * (alpha > 0.05).sum() / max((skin > 0.5).sum(), 1),
        int((skin > 0.5).sum()), time.time() - t0, dst))
    if os.environ.get("PAINT_DEBUG"):
        dbg = px[:, :3].copy()
        dbg[idx] = dbg[idx] * (1 - skin[:, None] * 0.6) + np.array([0.9, 0.0, 0.9]) * skin[:, None] * 0.6
        dbg[idx[near]] = np.where((alpha[near] > 0.05)[:, None], np.array([0.0, 0.9, 1.0]), dbg[idx[near]])
        dimg = bpy.data.images.new("paint_dbg", size, size)
        full[:, :3] = dbg
        dimg.pixels.foreach_set(full.ravel())
        dimg.filepath_raw = os.environ["PAINT_DEBUG"]
        dimg.file_format = "JPEG"
        dimg.save(quality=90)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    tripo = Path(argv[0])
    blend = Path(bpy.data.filepath)
    dst = Path(argv[1]) if len(argv) > 1 else blend.parent / "textures" / "goblin_shaman_body_basecolor.jpg"
    tmp = Path(tempfile.mkdtemp(prefix="goblin_shaman_paint_"))
    with zipfile.ZipFile(tripo / "body__take-01.zip") as z:
        name = next(n for n in z.namelist() if n.endswith("_basecolor.jpg"))
        z.extract(name, tmp)
    paint_body(bpy.data.objects["GoblinShaman"], tmp / name, dst)
    shutil.rmtree(tmp, ignore_errors=True)
