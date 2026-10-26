"""The shaman's bird skull mask, built from code round his face (background Blender).

Imported by build_goblin_shaman.py (MASK=beak): build_mask(body) returns the mask object.
The skull is a signed distance field (metres, in the base scene's space, from his eyes):
  * the cranium, a bulging dome over his brow and forehead;
  * two large round eye sockets over his eyes with thick rims, a hole through each (HOLE)
    down to his eye;
  * cheek bars from below the sockets to the beak's base, a small dark opening each side;
  * the beak, from between the sockets forward and down, hooked at its tip, a ridge along
    its top, two nostril slits near its base;
his face (dilated by GAP) carved out of it, so it rests on him, cut behind at CUT.
Its zero level is meshed with surface nets on a GRID grid, smoothed onto the surface and
decimated to FACES. The band and the feathers are as coarse: the mask is low-poly like the
footman's helmet, sharp where its faces meet at 50 degrees or more.
"""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

GRID = 0.0025
# Where each part lies in the texture: the skull in SKULL_UV (u, v boxes), the band across
# BAND_UV, the feathers' three patterns side by side in FEATHER_UV; QUILL of each feather bare.
SKULL_UV = ((0.0, 0.0), (0.70, 0.70))
BAND_UV = (0.71, 0.75)
FEATHER_UV = ((0.76, 0.84), (0.84, 0.92), (0.92, 1.0))
QUILL = 0.16
GAP = 0.003
# Triangles in the skull: about half his body's 6k, as coarse as the footman's helmet.
FACES = 3000
# All from the middle of his eyes (x, y: negative ahead, z).
CRANIUM = ((0.0, 0.100, 0.030), (0.140, 0.165, 0.130))
ORBIT = ((0.076, -0.040, 0.006), (0.058, 0.040, 0.060))
SOCKET = ((0.076, -0.078, 0.006), (0.040, 0.032, 0.043))
# The hole through each socket to his eye: half-width, half-height, how far back it goes
# (y from his eyes; it starts 4 cm before the socket's middle).
HOLE = (0.029, 0.031, 0.0)
RIM = ((0.076, -0.068, 0.006), (0.30, -1.0, 0.0), 0.042, 0.007)
CHEEK = ((0.105, -0.040, -0.030), (0.030, -0.095, -0.050), 0.010)
MAXILLA = ((0.0, -0.075, -0.030), (0.052, 0.048, 0.042))
FENESTRA = ((0.060, -0.088, -0.050), (0.014, 0.020, 0.011))
BEAK = ((0.0, -0.080, -0.028), (0.0, -0.185, -0.075), (0.0, -0.270, -0.185))
BEAK_W, BEAK_H, BEAK_TIP, TAPER = 0.050, 0.042, 0.003, 0.7
RIDGE = 0.35
NOSTRIL = (0.06, 0.34, 0.55, 0.62, 0.009)   # t from, t to, across, up (of the section), radius
LOW = -0.078          # the skull (not the beak) ends this far below his eyes
CUT = ((0.066, -0.081), (0.116, 0.139))   # the back cut: (y, z) of two points on it
# The red band round his head over the skull's top edge: (y, z) from his eyes of its middle
# at the front and the back, its width, thickness and gap; the skull ends TOP above its middle.
BAND = ((-0.031, 0.101), (0.209, 0.059))
BAND_W, BAND_T, BAND_GAP = 0.036, 0.006, 0.002
TOP = 0.010
# The feather crest along the band's front: how many, how far round from the front (deg),
# length in the middle and at the ends, half-width, how far the end ones lean out and all
# lean back (deg), how far each bends back along its length, thickness, seed. Each rises
# from the band and turns out to its lean between BEND (of its length); every other one
# stands LAYER behind the others and BACK_ROW longer, a second row.
FEATHERS, CREST = 23, 80.0
FEATHER_L = (0.215, 0.145)
FEATHER_W = 0.022
SPLAY, LEAN, CURL = 72.0, 12.0, 0.030
LAYER, BACK_ROW = (0.0025, -0.0025), 0.017
BEND = (0.04, 0.38)
FEATHER_T = 0.0022
SEED = 3


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b + (a - b) * h - k * h * (1 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def ellipsoid(P, c, r):
    q = (P - c) / r
    k0 = np.linalg.norm(q, axis=1)
    k1 = np.linalg.norm(q / r, axis=1)
    return k0 * (k0 - 1) / np.maximum(k1, 1e-9)


def capsule(P, a, b, r):
    a, b = np.asarray(a, float), np.asarray(b, float)
    ab = b - a
    t = np.clip((P - a) @ ab / (ab @ ab), 0, 1)
    return np.linalg.norm(P - a - t[:, None] * ab, axis=1) - r


def torus(P, c, n, R, r):
    n = np.asarray(n, float) / np.linalg.norm(n)
    q = P - c
    h = q @ n
    rho = np.linalg.norm(q - h[:, None] * n, axis=1)
    return np.hypot(rho - R, h) - r


def bezier(t, p0, p1, p2):
    t = np.asarray(t)[..., None]
    return (1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t * t * p2


class Skull:
    def __init__(self, E, body=None):
        self.E = np.asarray(E, float)
        self.head = Body(body) if body else None
        self.ring = Ring(self.E)
        n = 32
        self.ts = np.linspace(0, 1, n + 1)
        self.spine = bezier(self.ts, *(self.E + np.array(p) for p in BEAK))

    def at(self, off, side=1):
        return self.E + np.array(off) * (side, 1, 1)

    def on_beak(self, t, across, up):
        """A point in the beak's section at t along it, as fractions of its half-width and height."""
        p = bezier(t, *(self.E + np.array(q) for q in BEAK))
        e = bezier(min(t + 0.01, 1), *(self.E + np.array(q) for q in BEAK)) - p
        e /= np.linalg.norm(e)
        side = np.cross(e, (0.0, 0.0, 1.0))
        side /= np.linalg.norm(side)
        taper = (1 - t) ** TAPER
        ha = BEAK_TIP + (BEAK_W - BEAK_TIP) * taper
        hb = BEAK_TIP + (BEAK_H - BEAK_TIP) * taper
        return p + side * across * ha + np.cross(side, e) * up * hb

    def beak(self, P):
        """A tapered tube of elliptical section along the spine, its top drawn to a ridge."""
        d = np.full(len(P), 1.0)
        up = np.array((0.0, 0.0, 1.0))
        for k in range(len(self.ts) - 1):
            a, b = self.spine[k], self.spine[k + 1]
            e = b - a
            L = np.linalg.norm(e)
            e /= L
            side = np.cross(e, up)
            side /= np.linalg.norm(side)
            w_ax = np.cross(side, e)
            q = P - a
            along = q @ e
            u = np.clip(along, 0, L)
            over = np.abs(along - u)
            t = self.ts[k] + (self.ts[k + 1] - self.ts[k]) * u / L
            r = q - u[:, None] * e
            v, w = r @ side, r @ w_ax
            taper = (1 - t) ** TAPER
            ha = BEAK_TIP + (BEAK_W - BEAK_TIP) * taper
            hb = BEAK_TIP + (BEAK_H - BEAK_TIP) * taper
            ha = ha * (1 - RIDGE * np.clip(w / hb, 0, 1))
            dd = (np.hypot(v / ha, w / hb) - 1) * np.minimum(ha, hb)
            # Past either end of the segment, the distance along it counts too.
            dd = np.where(over > 0, np.hypot(np.maximum(dd, 0), over), dd)
            d = np.minimum(d, dd)
        return d

    def shape(self, P, hollows=True):
        """The skull before his face is carved out of it (and without its hollows, if not
        `hollows`)."""
        E = self.E
        rel = P - E
        s = ellipsoid(P, E + CRANIUM[0], CRANIUM[1])
        s = smin(s, ellipsoid(P, E + MAXILLA[0], MAXILLA[1]), 0.02)
        for side in (1, -1):
            s = smin(s, ellipsoid(P, self.at(ORBIT[0], side), ORBIT[1]), 0.015)
            s = smin(s, torus(P, self.at(RIM[0], side), np.array(RIM[1]) * (side, 1, 1), RIM[2], RIM[3]), 0.012)
            s = smin(s, capsule(P, self.at(CHEEK[0], side), self.at(CHEEK[1], side), CHEEK[2]), 0.012)
        s = smax(s, (E[2] + LOW) - P[:, 2], 0.01)
        s = smin(s, self.beak(P), 0.015)
        if hollows:
            s = smax(s, -self.eyes(P), 0.004)
        for side in (1, -1) if hollows else ():
            s = smax(s, -ellipsoid(P, self.at(FENESTRA[0], side), FENESTRA[1]), 0.003)
            a, b = (self.on_beak(t, side * NOSTRIL[2], NOSTRIL[3]) for t in NOSTRIL[:2])
            s = smax(s, -capsule(P, a, b, NOSTRIL[4]), 0.003)
        (y0, z0), (y1, z1) = CUT
        cut = (rel[:, 1] - y0 - (y1 - y0) * (rel[:, 2] - z0) / (z1 - z0)) * 0.95
        s = smax(s, cut, 0.004)
        top = (P - self.ring.c) @ self.ring.n - TOP
        return smax(s, top, 0.003)

    def eyes(self, P):
        """Distance from the eye sockets and the holes through them, negative in them."""
        d = np.full(len(P), 1.0)
        for side in (1, -1):
            c = self.at(SOCKET[0], side)
            q = P - c
            tube = (np.hypot(q[:, 0] / HOLE[0], q[:, 2] / HOLE[1]) - 1) * min(HOLE[:2])
            hole = np.maximum(tube, np.maximum(P[:, 1] - self.E[1] - HOLE[2], c[1] - 0.04 - P[:, 1]))
            d = np.minimum(d, np.minimum(ellipsoid(P, c, SOCKET[1]), hole))
        return d

    def carves(self, P):
        """Distance from the hollows cut into it (sockets, openings, nostrils), negative in them."""
        d = self.eyes(P)
        for side in (1, -1):
            d = np.minimum(d, ellipsoid(P, self.at(FENESTRA[0], side), FENESTRA[1]))
            a, b = (self.on_beak(t, side * NOSTRIL[2], NOSTRIL[3]) for t in NOSTRIL[:2])
            d = np.minimum(d, capsule(P, a, b, NOSTRIL[4]))
        return d

    def field(self, P):
        s = self.shape(P)
        near = s < GAP + 0.01
        if near.any():
            h = self.head(P[near])
            s[near] = smax(s[near], GAP - h, 0.0015)
        return s


class Ring:
    """The band's plane: through its middle at the front and the back (BAND), level across;
    `f` ahead in it, `s` to his left (+x), `n` out of it (up and back)."""

    def __init__(self, E):
        (y0, z0), (y1, z1) = BAND
        a, b = E + (0, y0, z0), E + (0, y1, z1)
        self.c = (a + b) / 2
        self.f = (a - b) / np.linalg.norm(a - b)
        self.s = np.array((1.0, 0.0, 0.0))
        self.n = np.cross(self.f, self.s)

    def d(self, phi):
        """Out from the middle at `phi` (radians) round from the front toward +x."""
        phi = np.asarray(phi)[..., None]
        return np.cos(phi) * self.f + np.sin(phi) * self.s

    def fit(self, pts, phis):
        """How far out the band's inside lies at each angle: round the convex hull of the
        points within its width, as a band drawn tight lies."""
        q = pts - self.c
        h = q @ self.n
        q = q[np.abs(h) < BAND_W / 2 + 0.008]
        uv = np.stack([q @ self.f, q @ self.s], 1)
        H = hull2d(uv)
        e = np.roll(H, -1, 0) - H
        m = np.stack([e[:, 1], -e[:, 0]], 1)
        m /= np.linalg.norm(m, axis=1)[:, None]
        o = (m * H).sum(1)
        D = np.stack([np.cos(phis), np.sin(phis)], 1)
        dot = D @ m.T
        return np.where(dot > 1e-9, o[None] / np.maximum(dot, 1e-9), np.inf).min(1)


def hull2d(P):
    """The convex hull, counterclockwise (monotone chain)."""
    P = P[np.lexsort((P[:, 1], P[:, 0]))]

    def half(points):
        out = []
        for p in points:
            while len(out) >= 2 and np.cross(out[-1] - out[-2], p - out[-2]) <= 0:
                out.pop()
            out.append(p)
        return out
    lo, hi = half(P), half(P[::-1])
    return np.array(lo[:-1] + hi[:-1])


class Body:
    """Signed distance from his body (negative inside), the sign taken from the nearest
    triangle's normal, or at its edges and corners from the normals round them weighted
    by angle, so it holds near a sharp point such as a tusk's tip."""

    def __init__(self, body):
        V = np.array([v.co[:] for v in body.data.vertices])
        tri = np.array([(f[0], f[k], f[k + 1]) for f in (list(p.vertices) for p in body.data.polygons)
                        for k in range(1, len(f) - 1)])
        a, b, c = (V[tri[:, k]] for k in range(3))
        n = np.cross(b - a, c - a)
        self.fn = n / np.maximum(np.linalg.norm(n, axis=1), 1e-12)[:, None]
        vn = np.zeros_like(V)
        for k in range(3):
            p, q, r = (V[tri[:, (k + j) % 3]] for j in range(3))
            u, w = q - p, r - p
            ang = np.arctan2(np.linalg.norm(np.cross(u, w), axis=1), (u * w).sum(1))
            np.add.at(vn, tri[:, k], ang[:, None] * self.fn)
        self.vn = vn
        e = np.sort(np.stack([tri[:, [k, (k + 1) % 3]] for k in range(3)], 1), 2)
        _, inv = np.unique(e.reshape(-1, 2), axis=0, return_inverse=True)
        en = np.zeros((inv.max() + 1, 3))
        np.add.at(en, inv.ravel(), np.repeat(self.fn, 3, 0))
        self.en, self.edge = en, inv.reshape(-1, 3)
        self.V, self.tri = V, tri
        self.tree = BVHTree.FromPolygons([Vector(p) for p in V], tri.tolist())

    def __call__(self, P, far=0.2):
        loc = np.zeros_like(P)
        idx = np.zeros(len(P), int)
        out = np.full(len(P), far)
        hit = np.zeros(len(P), bool)
        for i, p in enumerate(P):
            l, _, k, dist = self.tree.find_nearest(Vector(p), far)
            if l is not None:
                loc[i], idx[i], out[i], hit[i] = l, k, dist, True
        t = self.tri[idx]
        a, b, c = (self.V[t[:, k]] for k in range(3))
        # Barycentric weights of the nearest point.
        v0, v1, v2 = b - a, c - a, loc - a
        d00, d01, d11 = (v0 * v0).sum(1), (v0 * v1).sum(1), (v1 * v1).sum(1)
        d20, d21 = (v2 * v0).sum(1), (v2 * v1).sum(1)
        den = np.maximum(d00 * d11 - d01 * d01, 1e-20)
        w1 = (d11 * d20 - d01 * d21) / den
        w2 = (d00 * d21 - d01 * d20) / den
        w = np.stack([1 - w1 - w2, w1, w2], 1)
        n = self.fn[idx].copy()
        tol = 1e-4
        for j in range(3):
            # On the edge opposite corner j.
            on = w[:, j] < tol
            n[on] = self.en[self.edge[idx[on], (j + 1) % 3]]
        for j in range(3):
            # On corner j.
            on = w[:, j] > 1 - tol
            n[on] = self.vn[t[on, j]]
        inside = hit & (((P - loc) * n).sum(1) < 0)
        return np.where(inside, -out, out)


def surface_nets(F, origin, h):
    """Vertices and quads on the zero level of F, sampled on a grid `h` apart from `origin`."""
    shape = np.array(F.shape)
    cells = tuple(shape - 1)
    inside = F < 0
    count = np.zeros(cells, np.int8)
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                count += inside[dx:dx + cells[0], dy:dy + cells[1], dz:dz + cells[2]]
    acc = np.zeros(cells + (3,))
    cnt = np.zeros(cells)
    edges = []
    for ax in range(3):
        lo = [slice(None)] * 3
        hi = [slice(None)] * 3
        lo[ax], hi[ax] = slice(0, -1), slice(1, None)
        f0, f1 = F[tuple(lo)], F[tuple(hi)]
        cross = (f0 < 0) != (f1 < 0)
        ii = np.nonzero(cross)
        t = f0[ii] / (f0[ii] - f1[ii])
        pos = np.stack(ii, 1).astype(float)
        pos[:, ax] += t
        b, c = [(1, 2), (2, 0), (0, 1)][ax]
        for db in (0, -1):
            for dc in (0, -1):
                cell = list(ii)
                cell[b] = cell[b] + db
                cell[c] = cell[c] + dc
                ok = (cell[b] >= 0) & (cell[b] < cells[b]) & (cell[c] >= 0) & (cell[c] < cells[c])
                cc = tuple(x[ok] for x in cell)
                np.add.at(acc, cc, pos[ok])
                np.add.at(cnt, cc, 1)
        edges.append((ax, ii, f0[ii] < 0))
    active = cnt > 0
    index = -np.ones(cells, np.int64)
    index[active] = np.arange(active.sum())
    verts = origin + acc[active] / cnt[active][:, None] * h
    quads = []
    for ax, ii, neg in edges:
        b, c = [(1, 2), (2, 0), (0, 1)][ax]
        corner = []
        for db, dc in ((-1, -1), (0, -1), (0, 0), (-1, 0)):
            cell = list(ii)
            cell[b] = cell[b] + db
            cell[c] = cell[c] + dc
            corner.append(cell)
        ok = np.ones(len(ii[0]), bool)
        for cell in corner:
            for a in range(3):
                ok &= (cell[a] >= 0) & (cell[a] < cells[a])
        q = np.stack([index[tuple(x[ok] for x in cell)] for cell in corner], 1)
        q = np.where(neg[ok][:, None], q, q[:, ::-1])
        quads.append(q)
    quads = np.concatenate(quads)
    quads = quads[(quads >= 0).all(1)]
    return verts, quads


def build_mask(body, name="MaskPlate"):
    V = np.array([v.co[:] for v in body.data.vertices])
    parts = part_labels(body)
    eyes = [V[parts == p] for p in np.unique(parts)
            if len(np.nonzero(parts == p)[0]) < 100 and 1.28 < V[parts == p][:, 2].min()
            and V[parts == p][:, 1].mean() < -0.15 and np.ptp(V[parts == p][:, 0]) < 0.08]
    assert len(eyes) == 2, len(eyes)
    E = np.array((0.0, np.mean([e[:, 1].mean() for e in eyes]), np.mean([e[:, 2].mean() for e in eyes])))
    sk = Skull(E, body)
    lo = E + (-0.17, -0.34, -0.21)
    hi = E + (0.17, 0.16, 0.19)
    xs, ys, zs = (np.arange(lo[a], hi[a] + GRID, GRID) for a in range(3))
    F = np.empty((len(xs), len(ys), len(zs)))
    for i, x in enumerate(xs):
        Y, Z = np.meshgrid(ys, zs, indexing="ij")
        P = np.stack([np.full(Y.size, x), Y.ravel(), Z.ravel()], 1)
        F[i] = sk.field(P).reshape(Y.shape)
    verts, quads = surface_nets(F, lo, GRID)
    bm = bmesh.new()
    bv = [bm.verts.new(p) for p in verts]
    for q in quads:
        try:
            bm.faces.new([bv[i] for i in q])
        except ValueError:
            pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    # Only the skull itself: slivers of it left between his face and the cut go.
    bm.faces.ensure_lookup_table()
    seen, pieces = set(), []
    for f in bm.faces:
        if f.index in seen:
            continue
        piece, stack = [], [f]
        seen.add(f.index)
        while stack:
            g = stack.pop()
            piece.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        pieces.append(piece)
    pieces.sort(key=len, reverse=True)
    drop = [f for p in pieces[1:] for f in p]
    print("BEAK_MASK pieces", [len(p) for p in pieces[:6]], "dropped", len(drop), "faces")
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    # Smooth the grid's steps away, each time back onto the surface.
    for _ in range(3):
        bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=0.6, use_axis_x=True, use_axis_y=True, use_axis_z=True)
        P = np.array([v.co[:] for v in bm.verts])
        P = project(sk, P)
        for v, p in zip(bm.verts, P):
            v.co = p
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if FACES and len(me.polygons) > FACES:
        m = ob.modifiers.new("Decimate", "DECIMATE")
        m.ratio = FACES / (2 * len(me.polygons))
        dg = bpy.context.evaluated_depsgraph_get()
        new = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
        ob.modifiers.clear()
        old = ob.data
        ob.data = new
        new.name = name
        bpy.data.meshes.remove(old)
    clear(ob, sk, body)
    ob.data.materials.append(material("MaskBone", (0.80, 0.72, 0.55)))
    unwrap(ob)
    skull = ob
    head = V[(parts == np.bincount(parts).argmax()) & (np.abs(V[:, 0]) < 0.12)]
    band, ring = build_band(sk, skull, head)
    feathers = build_feathers(sk, ring)
    for o in [skull, band] + feathers:
        P = np.array([v.co[:] for v in o.data.vertices])
        print("BEAK_MASK %s nearest his body %.1f mm" % (o.name, sk.head(P).min() * 1000))
    ob = join([skull, band] + feathers, name)
    col = bpy.data.collections.get("Props")
    if col and ob.name not in col.objects:
        for c in ob.users_collection:
            c.objects.unlink(ob)
        col.objects.link(ob)
    ob["eyes"] = [float(c) for c in E]
    P = np.array([v.co[:] for v in ob.data.vertices])
    h = sk.head(P)
    print("BEAK_MASK nearest at", P[h.argmin()].round(3), "eyes at", E.round(3))
    print("BEAK_MASK %d verts, %d faces; x %.3f to %.3f, y %.3f to %.3f, z %.3f to %.3f; nearest his body %.1f mm" % (
        len(P), len(ob.data.polygons), *[f for a in range(3) for f in (P[:, a].min(), P[:, a].max())], h.min() * 1000))
    return ob


def clear(ob, sk, body, step=0.0005, passes=20):
    """The decimation's long triangles can cut his face where the skull runs close to it:
    the corners of each skull face that cuts one of his are moved away from him, `step` at a
    time, until none does."""
    bt = BVHTree.FromPolygons([v.co.copy() for v in body.data.vertices], [list(p.vertices) for p in body.data.polygons])
    me = ob.data
    faces = [list(p.vertices) for p in me.polygons]
    P0 = np.array([v.co[:] for v in me.vertices])
    P = P0.copy()
    for k in range(passes):
        mt = BVHTree.FromPolygons([Vector(p) for p in P], faces)
        hit = sorted({i for a, _ in mt.overlap(bt) for i in faces[a]})
        if not hit:
            break
        Q = P[hit]
        g = np.zeros_like(Q)
        for a in range(3):
            d = np.zeros(3)
            d[a] = 0.0005
            g[:, a] = sk.head(Q + d) - sk.head(Q - d)
        P[hit] = Q + step * g / np.maximum(np.linalg.norm(g, axis=1), 1e-9)[:, None]
    else:
        raise RuntimeError("the skull still cuts his face after %d passes" % passes)
    me.vertices.foreach_set("co", P.astype(np.float32).ravel())
    me.update()
    moved = np.linalg.norm(P - P0, axis=1)
    print("BEAK_MASK cleared his face: %d vertices moved, up to %.1f mm, %d passes" % (
        (moved > 0).sum(), moved.max() * 1000, k))


def unwrap(ob):
    """The skull's UVs: Blender's smart projection, into SKULL_UV."""
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=np.radians(60), island_margin=0.004, scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    uv = ob.data.uv_layers.active
    uv.name = "UVMap"
    a = np.empty(len(uv.data) * 2, np.float32)
    uv.data.foreach_get("uv", a)
    (u0, v0), (u1, v1) = SKULL_UV
    a = a.reshape(-1, 2) * (u1 - u0, v1 - v0) + (u0, v0)
    uv.data.foreach_set("uv", a.ravel())


def material(name, rgb, rough=0.7):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    m.diffuse_color = (*rgb, 1.0)
    return m


def mesh_obj(name, verts, faces, uvs, mat):
    """An object from vertices, faces and each face's corners' UVs."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [list(f) for f in faces])
    uv = me.uv_layers.new(name="UVMap")
    uv.data.foreach_set("uv", np.array([c for f in uvs for c in f], np.float32).ravel())
    me.materials.append(mat)
    me.validate()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def build_band(sk, skull, head):
    """A cloth band round his head over the skull's top edge, drawn tight round both."""
    R = sk.ring
    n_phi = 64
    phis = np.linspace(-np.pi, np.pi, n_phi, endpoint=False)
    pts = np.concatenate([np.array([v.co[:] for v in skull.data.vertices]), head])
    r = R.fit(pts, phis) + BAND_GAP
    prof = band_profile()
    m = len(prof)
    W2 = BAND_W / 2
    rng = np.random.default_rng(SEED)
    wav = sum(rng.uniform(-1, 1) * np.sin(k * phis + rng.uniform(0, 6.3)) / k for k in range(2, 7))
    per = np.r_[0, np.cumsum(np.linalg.norm(np.roll(prof, -1, 0) - prof, axis=1))]

    def make(r):
        verts = []
        for i, ph in enumerate(phis):
            d = R.d(ph)
            for h, o in prof:
                # The cloth puckers a little along its edges.
                bulge = 0.0008 * wav[i] * (abs(h) / W2) ** 2 * (o > 0.001)
                verts.append(R.c + d * (r[i] + o + bulge) + R.n * (h + 0.0012 * wav[i]))
        return np.array(verts)
    # The hull is of his vertices: where a face of his bulges past them, out a little more.
    verts = make(r)
    near = sk.head(verts).reshape(n_phi, m).min(1)
    need = np.maximum(0.0, BAND_GAP - near)
    need = np.max([np.roll(need, k) for k in range(-3, 4)], 0)
    r = r + need
    verts = make(r)
    print("BEAK_MASK band pushed out up to %.1f mm" % (need.max() * 1000))
    faces, uvs = [], []
    for i in range(n_phi):
        j = (i + 1) % n_phi
        v0, v1 = i / n_phi, (i + 1) / n_phi
        for k in range(m):
            k2 = (k + 1) % m
            faces.append((i * m + k, i * m + k2, j * m + k2, j * m + k))
            u0, u1 = per[k] / per[-1], per[k + 1] / per[-1]
            uvs.append([(BAND_UV[0] + (BAND_UV[1] - BAND_UV[0]) * u, v) for u, v in ((u0, v0), (u1, v0), (u1, v1), (u0, v1))])
    ob = mesh_obj("MaskBand", verts, faces, uvs, material("MaskBand", (0.45, 0.06, 0.04)))
    orient_out(ob, R)
    return ob, (phis, r)


def band_profile(rc=0.0022):
    """The band's section, a flat strip with its edges bevelled: (along n, out) round it."""
    prof = []
    W2 = BAND_W / 2
    for cx, cy, a0 in ((W2 - rc, BAND_T - rc, 0), (-W2 + rc, BAND_T - rc, 90), (-W2 + rc, rc, 180), (W2 - rc, rc, 270)):
        for k in range(2):
            a = np.radians(a0 + 90 * k)
            prof.append((cx + rc * np.cos(a), cy + rc * np.sin(a)))
    return np.array(prof)


def orient_out(ob, R):
    """Turn the faces out of the band (away from its middle line)."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    bad = 0
    for f in bm.faces:
        c = np.array(f.calc_center_median()[:]) - R.c
        c -= R.n * (c @ R.n)
        bad += f.normal.dot(Vector(c)) < 0
    if bad * 2 > len(bm.faces):
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()


def feather_shape(L, W, nl=8, nw=2):
    """A feather in its own frame: (along, across, out) for rows from root to tip, and each
    point's (across 0-1, along 0-1). A bare quill to QUILL, then the vane, rounded to its tip."""
    rows, tex = [], []
    # The quill one segment, the vane the rest, its rows closer toward the tip to round it.
    for s in [0.0] + [QUILL + (1 - QUILL) * (1 - (1 - a / (nl - 1)) ** 1.4) for a in range(nl)]:
        hw = max(0.0016, W * feather_hw(s))
        row, trow = [], []
        for b in range(nw + 1):
            q = b / nw * 2 - 1
            # The leading vane narrower, the vanes cupped back from the shaft.
            y = hw * q * (0.8 if q < 0 else 1.0)
            z = -0.10 * hw * q * q
            row.append((s * L, y, z))
            trow.append(((y / W + 1) / 2, s))
        rows.append(row)
        tex.append(trow)
    return rows, tex


def feather_hw(s):
    """A feather's half-width at `s` along it, of its widest: none on the quill (s < QUILL)."""
    v = np.clip((np.asarray(s, float) - QUILL) / (1 - QUILL), 0, 1)
    grow = np.minimum(1.0, v / 0.15) ** 0.7
    tip = np.where(v < 0.5, 1.0, np.maximum(0.0, 1 - ((v - 0.5) / 0.5) ** 1.7) ** 0.75)
    return np.where(np.asarray(s) <= QUILL, 0.0, (0.5 + 0.5 * grow) * tip)


def build_feathers(sk, ring):
    """The crest: FEATHERS tucked into the band along its front, fanned out and back."""
    R = sk.ring
    phis, r = ring
    rng = np.random.default_rng(SEED + 1)
    obs = []
    for i in range(FEATHERS):
        t = i / (FEATHERS - 1) * 2 - 1
        ph = np.radians(CREST) * t + rng.uniform(-0.02, 0.02)
        k = np.argmin(np.abs((phis - ph + np.pi) % (2 * np.pi) - np.pi))
        d = R.d(ph)
        back = i % 2
        root = R.c + d * (r[k] + BAND_T * 0.5) - R.n * BAND_W * 0.2
        sp = np.radians(SPLAY * t + rng.uniform(-3, 3))
        lean = np.radians(LEAN + rng.uniform(-3, 3))
        rise, splay, fan = (lean_x(v, lean) for v in (R.n, R.n * np.cos(sp) + R.s * np.sin(sp), R.f))

        def way(x):
            w = float(np.clip((x - BEND[0]) / (BEND[1] - BEND[0]), 0, 1))
            w = w * w * (3 - 2 * w)
            v = rise * (1 - w) + splay * w
            return v / np.linalg.norm(v)
        L = FEATHER_L[0] + (FEATHER_L[1] - FEATHER_L[0]) * abs(t) ** 1.5 + BACK_ROW * back + rng.uniform(-0.008, 0.008)
        rows, tex = feather_shape(L, FEATHER_W)
        var = int(rng.integers(0, 3))
        verts, faces, uvs = [], [], []
        nw = len(rows[0])
        xs = [row[0][0] / L for row in rows]
        at = [root]
        for a in range(1, len(xs)):
            at.append(at[-1] + way((xs[a - 1] + xs[a]) / 2) * (xs[a] - xs[a - 1]) * L)
        for a, row in enumerate(rows):
            v = way(xs[a])
            # Its face toward the front of the fan, its width across it.
            out = fan - v * (fan @ v)
            out /= np.linalg.norm(out)
            across = np.cross(out, v) * (1 if t >= 0 else -1)
            lay = LAYER[back] * min(1.0, xs[a] / QUILL)
            for x, y, z in row:
                verts.append(at[a] + across * y + out * (z - CURL * xs[a] ** 2 + lay))
        for a in range(len(rows) - 1):
            for b in range(nw - 1):
                faces.append((a * nw + b, a * nw + b + 1, (a + 1) * nw + b + 1, (a + 1) * nw + b))
                uvs.append([feather_uv(var, *tex[aa][bb]) for aa, bb in ((a, b), (a, b + 1), (a + 1, b + 1), (a + 1, b))])
        ob = mesh_obj("MaskFeather", verts, faces, uvs, material("MaskFeather", (0.42, 0.30, 0.20)))
        # Faces toward the front of the fan, then thickness behind them.
        me = ob.data
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.normal_update()
        if sum(f.normal.dot(Vector(fan)) for f in bm.faces) < 0:
            bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
        bm.to_mesh(me)
        bm.free()
        mod = ob.modifiers.new("Solidify", "SOLIDIFY")
        mod.thickness = FEATHER_T
        mod.offset = -1.0
        mod.use_even_offset = True
        bake_mods(ob)
        obs.append(ob)
    return obs


def lean_x(v, a):
    """`v` leant back (toward +y) by `a` radians about x."""
    c, s = np.cos(a), np.sin(a)
    return np.array((v[0], v[1] * c + v[2] * s, -v[1] * s + v[2] * c))


def feather_uv(var, u, v):
    a, b = FEATHER_UV[var]
    return (a + (b - a) * u, v)


def bake_mods(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    bpy.data.meshes.remove(old)


def join(parts, name):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = ob.data.name = name
    ob.data.shade_smooth()
    ob.data.set_sharp_from_angle(angle=np.radians(50))
    return ob


def project(sk, P, steps=2):
    for _ in range(steps):
        f = sk.field(P)
        g = np.zeros_like(P)
        e = 0.0005
        for a in range(3):
            d = np.zeros(3)
            d[a] = e
            g[:, a] = (sk.field(P + d) - sk.field(P - d)) / (2 * e)
        n2 = np.maximum((g * g).sum(1), 1e-6)
        P = P - (f / n2)[:, None] * g
    return P


def part_labels(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    lab = -np.ones(len(bm.verts), int)
    n = 0
    for v in bm.verts:
        if lab[v.index] >= 0:
            continue
        stack = [v]
        while stack:
            w = stack.pop()
            if lab[w.index] >= 0:
                continue
            lab[w.index] = n
            stack.extend(e.other_vert(w) for e in w.link_edges)
        n += 1
    bm.free()
    return lab
