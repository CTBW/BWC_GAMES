"""The captain's winged helmet, fitted to the footman's head (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python captain_helmet.py -- [glb=<out.glb>] [men=<out.glb>] [blend=<out.blend>] [keep[=men]]

The captain of every footman squad wears it: a silver barbute closed round
his head with a T cut in its face, gold trim round the T and the bottom edge,
and a pair of gold wings, no plume. His men wear the same barbute without the
wings, its trim in the company's blue (HelmetBlue). It is built here from code, in the body's
rest space, round his head as squad_looks crops it under a helmet (the hair
above the brow pulled in: `CROP`, as unit_look.gd's _crop).
  * the shell, a taut skin over the cropped head `MARGIN` clear of it, the
    same on both sides, down below his chin in front and to his nape behind,
    the faceplates and the neck flaring out at the bottom;
  * the T, the eye slit across his eyes and the slit down the middle open at
    the bottom, dark behind (HelmetDark);
  * the gold trim round the T and along the bottom edge, a silver crest from
    the brow to the nape, silver rivets round the bowl;
  * the wings, gold feathers on a gold rosette at either temple, rising up
    and back. The feathers have materials of their own (HelmetGoldFeather,
    HelmetSilverFeather): in Godot a toon outline as thick as a feather is
    long would blacken them, so they go without.
Every part faces out and takes its thickness behind it, toward his head.
`keep` leaves the captain's helmet in the open copy, `CaptainHelmet` on his
Head bone (`keep=men` the men's, `FootmanHelmet`), with the crop as the
body's shape key `HelmetCrop` (for renders and clips).
`glb=` exports the captain's helmet alone: identity root, metres, Y up, in the
same rest space as footman.glb, a mesh per material (CaptainHelmetSilver,
...Gold, ...Dark, ...GoldFeather, ...SilverFeather) with its ambient occlusion
in the vertex colour. `men=` exports the men's the same way
(FootmanHelmetSilver, ...Blue, ...Dark). `blend=` then saves the kept helmet
alone in a new file.
"""
import math
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OPT = dict(a.split("=", 1) for a in argv if "=" in a)
KEEP = "keep" in argv or "keep" in OPT
rig = bpy.data.objects["FootmanRig"]
body = bpy.data.objects["Footman"]
HEAD = "mixamorig:Head"

# squad_looks' crop of the hair under a helmet (across, and up from the rim).
CROP = (0.86, 0.6)
# Clear of the cropped head (m): over his hair, and before his face (room
# for the dark behind the T); the shell's thickness.
MARGIN, SHELL = (0.0015, 0.0045), 0.003
# The top raised (m), less down the sides, none at the eye slit.
LIFT = 0.02
# Below his cheekbones the sides draw in toward his jaw: across, this much of
# the head's width 0.2 m down.
TAPER = 0.8
# The shell's centre, between his eyes (m up from the rim): the eye slit's middle.
EYES = -0.032
# The T: the eye slit's height and how far its ends dip (m), its ends (degrees
# from his front, at the top and the bottom); the slit down the middle, its
# half width (degrees) under the eye slit and at the bottom edge.
SLIT_H, SLIT_DIP = 0.016, 0.005
SLIT_END = (50.0, 44.0)
SLIT_MID = (4.0, 6.5)
# The bottom edge (m from the eye slit's middle) by degrees from his front:
# under his chin in front, rising over the hood's collar to the nape.
EDGE = [(0.0, -0.112), (30.0, -0.111), (60.0, -0.104), (80.0, -0.088), (100.0, -0.071),
        (120.0, -0.058), (150.0, -0.053), (180.0, -0.053)]
# How far the faceplates and the neck flare out at the bottom edge (m).
FLARE = [(0.0, 0.014), (40.0, 0.010), (90.0, 0.004), (140.0, 0.004), (180.0, 0.005)]
# The gold trim round the T and along the bottom edge: width, rise (m).
TRIM = (0.0072, 0.0022)
# Silver rivets round the bowl: m above the eye slit's middle, degrees from his front.
RIVETS = (0.034, (22.0, 48.0, 72.0, 122.0, 148.0))
# The crest's height at the top (m).
CREST = 0.010
# The shell's grid: columns round (of them, half the middle slit's and to the
# eye slit's ends), rows from the top to the eye slit, in it, below it. Coarse:
# every man wears one, and his body is 5k triangles.
COLS, SLIT_COLS = 48, (1, 6)
ROWS = (12, 2, 7)
# The wings: mount (degrees from his front, m above the eye slit's middle);
# size, lean out at the top, trailing edge out, curl out toward the tips.
WING_AT = (95.0, 0.058)
WING_SCALE = 1.3
WING_SPLAY, WING_YAW, WING_CURL = 18.0, 30.0, 1.4
# A wing's flight feathers fan round FAN_AT (wing plane: back, up): by angle
# from straight up toward the back (degrees), how far out their tips reach.
FAN_AT = (-0.015, 0.085)
WING_REACH = [(15.0, 0.160), (35.0, 0.155), (55.0, 0.145), (75.0, 0.130), (95.0, 0.110), (118.0, 0.088)]
FEATHER = 0.0021
LESSER = 10
GOLD = (1.0, 0.62, 0.20)
BLUE = (0.07, 0.12, 0.32)
SILVER = (0.90, 0.91, 0.93)
DARK = (0.015, 0.015, 0.02)
# The baked occlusion only looks this far (m): the crevices, not the whole shell.
AO_DIST = 0.05


def ss(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def interp(table, x):
    """Piecewise linear in a [(x, y)] table."""
    t = sorted(table)
    if x <= t[0][0]:
        return t[0][1]
    for (x0, y0), (x1, y1) in zip(t, t[1:]):
        if x <= x1:
            return lerp(y0, y1, (x - x0) / (x1 - x0))
    return t[-1][1]


def wrap180(phi):
    return ((phi + 180.0) % 360.0) - 180.0


# --- The head --------------------------------------------------------------------

def fit_head():
    """squad_looks' _head_fit on his rest mesh, the mesh with the crop, the
    cropped body's surfaces and the cropped head's points."""
    me = body.data
    gi = {g.name: g.index for g in body.vertex_groups}
    skull = {gi[n] for n in ("mixamorig:Head", "mixamorig:HeadTop_End") if n in gi}
    w = [sum(g.weight for g in v.groups if g.group in skull) for v in me.vertices]
    pts = [v.co for v, x in zip(me.vertices, w) if x > 0.6]
    lo, hi = min(p.z for p in pts), max(p.z for p in pts)
    rim = (lo + hi) / 2
    up = [p for p in pts if p.z >= rim - 0.01]
    x0, x1 = min(p.x for p in up), max(p.x for p in up)
    y0, y1 = min(p.y for p in up), max(p.y for p in up)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    co = []
    for v, wv in zip(me.vertices, w):
        p = v.co.copy()
        if p.z > rim - 0.02 and wv > 0:
            k = ss(rim - 0.02, rim + 0.025, p.z) * min(1.0, wv)
            f = lerp(1.0, CROP[0], k)
            z = rim + (p.z - rim) * lerp(1.0, CROP[1], k) if p.z > rim else p.z
            p = Vector((cx + (p.x - cx) * f, cy + (p.y - cy) * f, z))
        co.append(p)
    crown = max(co[i].z for i, wv in enumerate(w) if wv > 0.6)
    bvh = BVHTree.FromPolygons(co, [tuple(p.vertices) for p in me.polygons])
    head = [p for p, wv in zip(co, w) if wv > 0.3]
    return {"lo": lo, "hi": hi, "rim": rim, "cx": cx, "cy": cy, "crown": crown}, co, bvh, head


def outer(bvh, at, d, far=0.4):
    """How far out from `at` along `d` the outermost surface is (0 if none)."""
    hit = bvh.ray_cast(at + d * far, -d, far)
    return far - hit[3] if hit[0] is not None else 0.0


def ring(phi):
    """Horizontal direction round his head: 0 his front (-Y), 90 his left (+X)."""
    a = math.radians(phi)
    return Vector((math.sin(a), -math.cos(a), 0.0))


# --- Mesh helpers ----------------------------------------------------------------

def grid_obj(name, rows, mat, wrap=False, pole=None):
    """A mesh of quads from rows of points; `wrap` joins each row's ends,
    `pole` closes the last row in one point."""
    bm = bmesh.new()
    V = [[bm.verts.new(p) for p in r] for r in rows]
    n = len(rows[0])
    for j in range(len(rows) - 1):
        for i in range(n if wrap else n - 1):
            bm.faces.new([V[j][i], V[j][(i + 1) % n], V[j + 1][(i + 1) % n], V[j + 1][i]])
    if pole is not None:
        pv = bm.verts.new(pole)
        for i in range(n if wrap else n - 1):
            bm.faces.new([V[-1][i], V[-1][(i + 1) % n], pv])
    return to_obj(name, bm, mat)


def to_obj(name, bm, mat):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(mat)
    return ob


def orient(ob, want):
    """Turn the faces to look the way `want(centre)` says (out of the part)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.normal_update()
    flip = [f for f in bm.faces if f.normal.dot(want(f.calc_center_median())) < 0]
    if len(flip) * 2 > len(bm.faces):
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def thicken(ob, t):
    """Thickness `t` behind its faces."""
    m = ob.modifiers.new("Solidify", "SOLIDIFY")
    m.thickness = t
    m.offset = -1.0
    m.use_even_offset = True
    m.use_quality_normals = True
    return ob


def away_from(path):
    """`orient`'s want: out from the nearest point of `path`."""
    kd = KDTree(len(path))
    for k, p in enumerate(path):
        kd.insert(p, k)
    kd.balance()
    return lambda c: c - kd.find(c)[0]


def sweep_obj(name, path, normals, profile, mat, caps=True, scale=None):
    """A profile [(across, out)] (or one per point, `profile(k)`) swept along
    `path`, `out` along `normals`, scaled by `scale` per point."""
    rows = []
    for k, p in enumerate(path):
        t = (path[min(k + 1, len(path) - 1)] - path[max(k - 1, 0)]).normalized()
        nrm = (normals[k] - t * normals[k].dot(t)).normalized()
        side = t.cross(nrm)
        f = scale[k] if scale else 1.0
        prof = profile(k) if callable(profile) else profile
        rows.append([p + side * s * f + nrm * o * f for s, o in prof])
    ob = grid_obj(name, rows, mat)
    if caps:
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.verts.ensure_lookup_table()
        m, last = len(rows[0]), len(path) - 1
        bm.faces.new([bm.verts[i] for i in range(m)][::-1])
        bm.faces.new([bm.verts[last * m + i] for i in range(m)])
        bm.to_mesh(ob.data)
        bm.free()
    return orient(ob, away_from(path))


def loop_sweep(name, path, normals, profile, mat, into):
    """A closed profile [(across, out)] swept round a closed `path`, across
    toward the path's `into` side (+1 or -1), out along `normals`; the
    corners mitred."""
    n = len(path)
    rows = []
    for k in range(n):
        p, nrm = path[k], normals[k]
        e1, e2 = p - path[k - 1], path[(k + 1) % n] - p
        e1 = (e1 - nrm * e1.dot(nrm)).normalized()
        e2 = (e2 - nrm * e2.dot(nrm)).normalized()
        t = (e1 + e2).normalized()
        miter = 1.0 / max(0.5, t.dot(e1))
        side = t.cross(nrm) * into
        rows.append([p + side * a * miter + nrm * o for a, o in profile])
    bm = bmesh.new()
    V = [[bm.verts.new(q) for q in r] for r in rows]
    m = len(profile)
    for k in range(n):
        for s in range(m):
            bm.faces.new([V[k][s], V[k][(s + 1) % m], V[(k + 1) % n][(s + 1) % m], V[(k + 1) % n][s]])
    return orient(to_obj(name, bm, mat), away_from(path))


def stud(at, nrm, r, h, mat, name="Stud", seg=12):
    """A low dome (a rivet, a boss) on a surface."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=max(6, seg // 2), radius=r)
    for v in bm.verts:
        v.co.z *= (h / r) if v.co.z > 0 else 0.1
    M = Matrix.Translation(at) @ nrm.to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    return to_obj(name, bm, mat)


def bake_mods(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    bpy.data.meshes.remove(old)


def material(name, rgb, rough):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Metallic"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = rough
    m.diffuse_color = (*rgb, 1.0)
    return m


# --- The shell -------------------------------------------------------------------

def relax(r):
    """Each point to the mean of its neighbours round and up and down; the
    first row is the top (one point), the last row's lower neighbour itself."""
    a = np.empty_like(r)
    a[1:-1] = (np.roll(r[1:-1], 1, 1) + np.roll(r[1:-1], -1, 1) + r[:-2] + r[2:]) / 4
    a[-1] = (np.roll(r[-1], 1) + np.roll(r[-1], -1) + r[-2] + r[-1]) / 4
    a[0] = r[1].mean()
    return a


def hull(pts):
    """The convex hull of the points as planes: (outward normals, offsets)."""
    bm = bmesh.new()
    for p in pts:
        bm.verts.new(p)
    geom = bmesh.ops.convex_hull(bm, input=bm.verts[:])["geom"]
    mid = sum(pts, Vector()) / len(pts)
    N, D = [], []
    for f in geom:
        if isinstance(f, bmesh.types.BMFace):
            n = f.normal.copy()
            if n.length < 0.5:
                continue
            n = n if n.dot(f.calc_center_median() - mid) > 0 else -n
            N.append(n)
            D.append(n.dot(f.verts[0].co))
    bm.free()
    return np.array(N), np.array(D)


class Shell:
    """The helmet's outer surface by direction from a centre between his eyes
    (phi round from his front, theta up from level): the convex hull of the
    cropped head, made the same on both sides, its face and jaw carried down
    (the faceplates hang on below the chin, the sides drawing in), MARGIN +
    SHELL out from it, rounded, and its top raised. From the eye slit down it
    flares out, most at the bottom edge."""
    STEP = 2.0
    SMOOTH = 10

    def __init__(self, fit, head):
        self.c = c = Vector((fit["cx"], fit["cy"], fit["rim"] + EYES))
        pts = head + [Vector((2 * c.x - p.x, p.y, p.z)) for p in head]
        pts += [Vector((c.x + (p.x - c.x) * TAPER, p.y, c.z - 0.2)) for p in pts if p.z < c.z - 0.03]
        N, D = hull(pts)
        s = self.STEP
        self.n_phi, self.n_th = int(360 / s), int(170 / s) + 1
        ph = np.radians(np.arange(self.n_phi) * s)[None, :]
        th = np.radians(90.0 - np.arange(self.n_th) * s)[:, None]
        U = np.stack([np.sin(ph) * np.cos(th), -np.cos(ph) * np.cos(th), np.sin(th) + 0 * ph], -1)
        face = np.clip((-N[:, 1] - 0.3) / 0.4, 0.0, 1.0)
        lift = D + MARGIN[0] + (MARGIN[1] - MARGIN[0]) * face + SHELL - N @ np.array(c)
        un = U @ N.T
        r0 = np.where(un > 1e-9, lift / np.maximum(un, 1e-9), np.inf).min(-1)
        # Rounded, never more than 0.8 mm in from the hull's offset.
        r = r0
        for _ in range(self.SMOOTH):
            r = np.maximum(r0 - 0.0008, relax(r))
        self.r = r
        self._rows = {}

    def dir(self, phi, th):
        a, t = math.radians(phi), math.radians(th)
        return Vector((math.sin(a) * math.cos(t), -math.cos(a) * math.cos(t), math.sin(t)))

    def radius(self, phi, th):
        x = (phi % 360.0) / self.STEP
        y = min(max((90.0 - th) / self.STEP, 0.0), self.n_th - 1.001)
        i0, j0 = int(x) % self.n_phi, int(y)
        i1, fx, fy = (i0 + 1) % self.n_phi, x - int(x), y - j0
        r = self.r
        return float(lerp(lerp(r[j0, i0], r[j0, i1], fx), lerp(r[j0 + 1, i0], r[j0 + 1, i1], fx), fy))

    def base(self, phi, th):
        return self.c + self.dir(phi, th) * self.radius(phi, th)

    def theta_at(self, phi, z):
        """Where the skin is at height `z`, on the side `phi`."""
        lo, hi = -85.0, 89.9
        for _ in range(40):
            m = (lo + hi) / 2
            if self.base(phi, m).z > z:
                hi = m
            else:
                lo = m
        return (lo + hi) / 2

    def rows(self, phi):
        """The eye slit's top and bottom and the bottom edge (theta) at `phi`."""
        key = round(phi, 5)
        if key not in self._rows:
            a = abs(wrap180(phi))
            dip = SLIT_DIP * (min(a, SLIT_END[0]) / SLIT_END[0]) ** 2
            z = self.c.z
            self._rows[key] = (self.theta_at(phi, z + SLIT_H / 2 - dip), self.theta_at(phi, z - SLIT_H / 2 - dip),
                               self.theta_at(phi, z + interp(EDGE, a)))
        return self._rows[key]

    def surf(self, phi, th):
        """The outer surface, the top raised and the bottom flared (straight
        up, and out at its height)."""
        _, t2, tb = self.rows(phi)
        t = min(1.0, max(0.0, (t2 - th) / (t2 - tb)))
        up = LIFT * max(0.0, math.sin(math.radians(th))) ** 2
        return self.base(phi, th) + ring(phi) * interp(FLARE, abs(wrap180(phi))) * t ** 1.8 + Vector((0, 0, up))

    def normal(self, phi, th, e=0.3):
        if th > 89.0:
            return Vector((0.0, 0.0, 1.0))
        a = self.surf(phi + e, th) - self.surf(phi - e, th)
        b = self.surf(phi, th + e) - self.surf(phi, th - e)
        n = a.cross(b).normalized()
        return n if n.dot(self.dir(phi, th)) > 0 else -n


class Grid:
    """The shell's grid: COLS columns round (i, his front in the middle) and
    rows down (j) from the top (0, one point) to the bottom edge (M). Rows J1
    and J2 run along the eye slit's top and bottom, the columns either side
    of the middle along the slit down the middle and the eye slit's ends."""

    def __init__(self, S):
        self.S = S
        self.N = COLS
        self.J1 = ROWS[0]
        self.J2 = self.J1 + ROWS[1]
        self.M = self.J2 + ROWS[2]
        self.mid = COLS // 2
        self.c0, self.c1 = SLIT_COLS
        self._at = {}

    def param(self, i, j):
        """(phi, theta) of the grid point."""
        i %= self.N
        if (i, j) in self._at:
            return self._at[(i, j)]
        J1, J2, M = self.J1, self.J2, self.M
        u = -1.0 + 2.0 * i / self.N
        a = SLIT_MID[0] if j <= J2 else lerp(SLIT_MID[0], SLIT_MID[1], (j - J2) / (M - J2))
        b = SLIT_END[0] if j <= J1 else SLIT_END[1] if j >= J2 else lerp(SLIT_END[0], SLIT_END[1], (j - J1) / (J2 - J1))
        knots = [(0.0, 0.0), (2.0 * self.c0 / self.N, a), (2.0 * self.c1 / self.N, b), (1.0, 180.0)]
        phi = math.copysign(interp(knots, abs(u)), u)
        t1, t2, tb = self.S.rows(phi)
        if j <= J1:
            th = lerp(90.0, t1, j / J1)
        elif j <= J2:
            th = lerp(t1, t2, (j - J1) / (J2 - J1))
        else:
            th = lerp(t2, tb, (j - J2) / (M - J2))
        self._at[(i, j)] = (phi, th)
        return phi, th

    def point(self, i, j):
        return self.S.surf(*self.param(i, j))

    def normal(self, i, j):
        return self.S.normal(*self.param(i, j))

    def hole(self, i, j):
        """Is the cell right of column i, below row j, in the T?"""
        if self.J1 <= j < self.J2 and self.mid - self.c1 <= i < self.mid + self.c1:
            return True
        return j >= self.J2 and self.mid - self.c0 <= i < self.mid + self.c0

    def mesh(self, name, cells, mat, inset=0.0):
        """The cells (i, j) as quads (row 0's as triangles to the top), `inset`
        in behind the surface."""
        bm = bmesh.new()
        V = {}

        def vert(i, j):
            k = (i % self.N, j)
            if k not in V:
                V[k] = bm.verts.new(self.point(*k) - self.normal(*k) * inset)
            return V[k]

        top = None
        for i, j in cells:
            if j == 0:
                top = top or bm.verts.new(self.S.surf(0.0, 90.0) - Vector((0, 0, inset)))
                bm.faces.new([top, vert(i + 1, 1), vert(i, 1)])
            else:
                bm.faces.new([vert(i, j), vert(i + 1, j), vert(i + 1, j + 1), vert(i, j + 1)])
        return orient(to_obj(name, bm, mat), lambda c: c - self.S.c)

    def boundary(self):
        """The shell's one edge, round the bottom from the right of the middle
        slit to its left, up it, round the eye slit, down its right side; and
        the corners (indices into it)."""
        N, mid, c0, c1, J1, J2, M = self.N, self.mid, self.c0, self.c1, self.J1, self.J2, self.M
        ia_l, ia_r, ib_l, ib_r = mid - c0, mid + c0, mid - c1, mid + c1
        loop = [(k % N, M) for k in range(ia_r, ia_l + N + 1)]
        loop += [(ia_l, j) for j in range(M - 1, J2 - 1, -1)]
        loop += [(i, J2) for i in range(ia_l - 1, ib_l - 1, -1)]
        loop += [(ib_l, j) for j in range(J2 - 1, J1 - 1, -1)]
        loop += [(i, J1) for i in range(ib_l + 1, ib_r + 1)]
        loop += [(ib_r, j) for j in range(J1 + 1, J2 + 1)]
        loop += [(i, J2) for i in range(ib_r - 1, ia_r - 1, -1)]
        loop += [(ia_r, j) for j in range(J2 + 1, M)]
        corners = [(ia_r, M), (ia_l, M), (ia_l, J2), (ib_l, J2), (ib_l, J1), (ib_r, J1), (ib_r, J2), (ia_r, J2)]
        return loop, [loop.index(c) for c in corners]


def build_shell(G, silver, dark):
    """The shell with the T cut out, thickness behind; and the dark behind the
    T, just inside the shell and a cell past the T's edges."""
    cells = [(i, j) for j in range(G.M) for i in range(G.N) if not G.hole(i, j)]
    shell = thicken(G.mesh("Shell", cells, silver), SHELL)
    mid, c0, c1 = G.mid, G.c0, G.c1
    back = [(i, j) for j in range(G.J1 - 1, G.J2 + 1) for i in range(mid - c1 - 1, mid + c1 + 1)]
    back += [(i, j) for j in range(G.J2 + 1, G.M) for i in range(mid - c0 - 1, mid + c0 + 1)]
    return [shell, G.mesh("Visor", back, dark, SHELL + 0.0012)]


def build_trim(G, gold):
    """Gold trim along the shell's edge, round the T and the bottom: a flat
    band on the plate, rolled over the edge and under it."""
    loop, corners = G.boundary()
    W, h = TRIM
    pts = [G.point(*q) for q in loop]
    # Only the corners themselves within a trim's width of a corner: a mitre.
    keep = [k for k, p in enumerate(pts)
            if k in corners or min((p - pts[c]).length for c in corners) > W * 1.1]
    path = [pts[k] for k in keep]
    nrms = [G.normal(*loop[k]) for k in keep]
    # Into the plate: at the back, up from the bottom edge.
    k0 = keep.index(loop.index((0, G.M)))
    t = (path[k0 + 1] - path[k0 - 1]).normalized()
    into = 1.0 if t.cross(nrms[k0]).dot(G.point(0, G.M - 2) - path[k0]) > 0 else -1.0
    lip, under = 0.0014, SHELL + 0.0008
    prof = [(W, -0.0006), (W, h * 0.45), (W * 0.82, h), (W * 0.25, h), (-lip * 0.4, h * 0.75), (-lip, h * 0.25),
            (-lip, -under * 0.5), (-lip * 0.6, -under), (W * 0.35, -under)]
    return [loop_sweep("Trim", path, nrms, prof, gold, into)]


def build_crest(G, silver):
    """A silver ridge along his middle from above the eye slit's trim over the
    top to the nape, highest over the crown."""
    S = G.S
    t0 = S.theta_at(0.0, S.c.z + SLIT_H / 2 + TRIM[0] + 0.005)
    t1 = S.theta_at(180.0, S.c.z - 0.004)
    total = (90.0 - t0) + (90.0 - t1)
    path, nrms, along = [], [], []
    n = G.N * 2 // 3
    for k in range(n + 1):
        a = total * k / n
        phi, th = (0.0, t0 + a) if a < 90.0 - t0 else (180.0, 90.0 - (a - (90.0 - t0)))
        p = S.surf(phi, th)
        if path and (p - path[-1]).length < 1e-4:
            continue
        path.append(p)
        nrms.append(S.normal(phi, th))
        along.append(k / n)
    w = 0.0075

    def prof(k):
        hh = 0.0025 + CREST * math.sin(math.pi * along[k]) ** 0.8
        return [(-w, -0.002), (-w * 0.95, 0.0), (-w * 0.6, hh * 0.55), (-w * 0.25, hh * 0.92), (0.0, hh),
                (w * 0.25, hh * 0.92), (w * 0.6, hh * 0.55), (w * 0.95, 0.0), (w, -0.002)]
    return sweep_obj("Crest", path, nrms, prof, silver)


def build_rivets(G, silver):
    S = G.S
    out = []
    for a in RIVETS[1]:
        for side in (1, -1):
            phi = side * a
            th = S.theta_at(phi, S.c.z + RIVETS[0])
            n = S.normal(phi, th)
            out.append(stud(S.surf(phi, th) - n * 0.0004, n, 0.0058, 0.0032, silver, "Rivet"))
    return out


def check_fit(G, bvh):
    """How close the shell's inside comes to his cropped head, and how far the
    body (his hood's collar) comes out past it below the eye slit, at rest."""
    S = G.S
    near = min((bvh.find_nearest(G.point(i, j))[3] - SHELL, i, j) for j in range(1, G.J2 + 1) for i in range(G.N))
    print("HELMET inside %.1f mm from his head at the closest (phi %.0f, z %.3f)"
          % (near[0] * 1000, G.param(near[1], near[2])[0], G.point(near[1], near[2]).z))
    vis = min(bvh.find_nearest(G.point(i, j) - G.normal(i, j) * (SHELL + 0.0012))[3]
              for j in range(G.J1, G.M + 1) for i in range(G.mid - G.c1, G.mid + G.c1 + 1))
    print("HELMET the dark behind the T %.1f mm from his face at the closest" % (vis * 1000))
    worst = []
    for j in range(G.J2, G.M + 1):
        for i in range(G.N):
            phi, th = G.param(i, j)
            p = S.surf(phi, th)
            r = (p - S.c).to_2d().length - SHELL
            o = outer(bvh, Vector((S.c.x, S.c.y, p.z)), ring(phi))
            if o > r:
                worst.append((o - r, phi, p.z))
    worst.sort(reverse=True)
    print("HELMET body past the shell's inside at rest (mm, phi, z):",
          ", ".join("%.1f %.0f %.3f" % (d * 1000, phi, z) for d, phi, z in worst[:6]) or "none")


# --- Wings -----------------------------------------------------------------------

def feather_rows(L, W, kind, nl=6, nw=2):
    """A feather in its own plane: x along it, y across (the trailing side +),
    z out of the wing (a low cup, a shaft down the middle)."""
    flight = kind == "flight"
    sweep, cup = (0.12, 0.10) if flight else (0.0, 0.08)
    rows = []
    for a in range(nl + 1):
        # The rows closer toward the tip, to round it.
        s = 1 - (1 - a / nl) ** 1.5
        if flight:
            base, st, e1, e2 = lerp(0.5, 1.0, ss(0.0, 0.2, s)), 0.6, 2.0, 0.5
        else:
            base, st, e1, e2 = lerp(0.6, 1.0, ss(0.0, 0.3, s)), 0.35, 2.0, 0.5
        tip = 1.0 if s < st else max(0.0, 1 - ((s - st) / (1 - st)) ** e1) ** e2
        hw = W * base * tip
        row = []
        for b in range(nw + 1):
            q = b / nw * 2 - 1
            # The leading vane narrower than the trailing one.
            y = hw * q * (0.62 if q < 0 else 1.0) - 0.12 * W
            z = -cup * W * q * q + 0.0009 * max(0.0, 1 - abs(q) / 0.25) * (1 - s)
            row.append((s * L, y + sweep * s * s * L, z))
        rows.append(row)
    return rows


class Wing:
    """A wing's frame: from its mount on the shell, `back` and `up` in its
    plane and `n` out of it."""

    def __init__(self, S, side):
        phi = side * WING_AT[0]
        th = S.theta_at(phi, S.c.z + WING_AT[1])
        self.mount, self.mount_n = S.surf(phi, th), S.normal(phi, th)
        out = Vector((side, 0, 0))
        sp, yw = math.radians(WING_SPLAY), math.radians(WING_YAW)
        up = Vector((0, 0, 1)) * math.cos(sp) + out * math.sin(sp)
        back = Vector((0, 1, 0)) * math.cos(yw) + out * math.sin(yw)
        n = back.cross(up).normalized()
        self.n = n if n.dot(out) > 0 else -n
        self.up = up
        self.back = (back - up * back.dot(up)).normalized()
        self.origin = self.mount + self.mount_n * 0.002

    def to3d(self, u, v, w):
        u, v = u * WING_SCALE, v * WING_SCALE
        # The wing curls out toward its tips.
        w2 = w + WING_CURL * (0.6 * v * v + 0.4 * max(0.0, u) ** 2)
        return self.origin + self.back * u + self.up * v + self.n * w2


def bezier(p0, p1, p2, t):
    return (1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t * t * p2


def wing_layout():
    """[(root (u, v), angle from up toward back (deg), length, half-width,
    kind, layer out of the wing)], the lowest layer first. The flight
    feathers leave the arm (the leading edge) and reach WING_REACH round
    FAN_AT; two rows of rounded coverts lie over their roots."""
    A0, A1, A2 = Vector((0.0, 0.0)), Vector((-0.032, 0.075)), Vector((-0.004, 0.125))
    arm = lambda t: bezier(A0, A1, A2, t)
    F = Vector(FAN_AT)

    def reach(root, ang):
        d = Vector((math.sin(math.radians(ang)), math.cos(math.radians(ang))))
        return interp(WING_REACH, ang) + (F - root).dot(d)

    fan = [(0.0, 118.0), (0.5, 80.0), (0.55, 70.0), (1.0, 15.0)]
    out = []
    # Secondaries: low on the arm, back along the helmet.
    for k in range(7):
        t = lerp(0.04, 0.50, k / 6)
        ang = interp(fan, t)
        out.append((arm(t), ang, reach(arm(t), ang), 0.0175, "flight", k * 0.0006))
    # Primaries: from the wrist up, fanning from the back to nearly straight up.
    for k in range(8):
        t = lerp(0.55, 1.0, k / 7)
        ang = interp(fan, t)
        out.append((arm(t), ang, reach(arm(t), ang), 0.0170, "flight", 0.0045 + k * 0.0006))
    # Greater coverts, then lesser: short rounded feathers along the arm.
    for k in range(9):
        t = lerp(0.03, 0.97, k / 8)
        out.append((arm(t) + Vector((0.004, 0.0)), interp(fan, t) + 4.0, 0.058, 0.0170, "covert", 0.0098 + (8 - k) * 0.0005))
    for k in range(LESSER):
        t = lerp(0.0, 1.0, k / (LESSER - 1))
        out.append((arm(t) + Vector((-0.003, 0.0)), interp(fan, t) + 8.0, 0.032, 0.0135, "covert", 0.0148 + (9 - k) * 0.0005))
    return out


def build_wing(S, side, gold, silver, gold_f, silver_f):
    W = Wing(S, side)
    obs = []
    lay = wing_layout()
    for n, (root, ang, L, wid, kind, layer) in enumerate(lay):
        a = math.radians(ang)
        ax, cr = Vector((math.sin(a), math.cos(a))), Vector((math.cos(a), -math.sin(a)))
        pts = []
        for r in feather_rows(L, wid, kind):
            pts.append([W.to3d(*(root + ax * x + cr * y), layer + z) for x, y, z in r])
        # The lesser coverts (the last row, along the leading edge) silver.
        ob = orient(grid_obj("Feather", pts, silver_f if n >= len(lay) - LESSER else gold_f), lambda c: W.n)
        obs.append(thicken(ob, FEATHER))
    # The rosette over the root: a scalloped gold disc on a stem, a silver boss.
    c = W.to3d(0.002, 0.004, 0.0225)
    n = W.n
    t1 = n.cross(Vector((0, 0, 1))).normalized()
    t2 = n.cross(t1).normalized()
    rows = []
    R = 0.024
    for j in range(5):
        v = j / 4
        row = []
        for i in range(48):
            a = 2 * math.pi * i / 48
            rr = R * (1.0 + 0.11 * math.cos(8 * a)) * (1 - v) + 0.0005
            row.append(c + (t1 * math.cos(a) + t2 * math.sin(a)) * rr + n * (0.0042 * math.sin(math.pi / 2 * v)))
        rows.append(row)
    disc = grid_obj("Rosette", rows, gold, wrap=True, pole=c + n * 0.0046)
    obs.append(thicken(orient(disc, lambda q: n), 0.004))
    stem = []
    for j in range(2):
        cc = W.mount - W.mount_n * 0.004 if j == 0 else c
        stem.append([cc + (t1 * math.cos(2 * math.pi * i / 24) + t2 * math.sin(2 * math.pi * i / 24)) * 0.012 for i in range(24)])
    obs.append(orient(grid_obj("Stem", stem, gold, wrap=True), lambda q: q - (c + W.mount) * 0.5 - n * (q - (c + W.mount) * 0.5).dot(n)))
    obs.append(stud(c + n * 0.0042, n, 0.0068, 0.0045, silver, "Boss", 16))
    return obs


# --- Build -----------------------------------------------------------------------

def join(parts, name):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    helm = bpy.context.view_layer.objects.active
    helm.name = helm.data.name = name
    me = helm.data
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(50))
    print("HELMET %s %d verts, %d tris" % (name, len(me.vertices), sum(len(p.vertices) - 2 for p in me.polygons)))
    return helm


def build():
    """The captain's helmet and his men's (the same without the wings, the
    trim blue)."""
    for ob in [o for o in bpy.data.objects if o.name.startswith(("CaptainHelmet", "FootmanHelmet"))]:
        bpy.data.objects.remove(ob)
    silver = material("HelmetSilver", SILVER, 0.18)
    gold = material("HelmetGold", GOLD, 0.30)
    blue = material("HelmetBlue", BLUE, 0.30)
    dark = material("HelmetDark", DARK, 0.6)
    gold_f = material("HelmetGoldFeather", GOLD, 0.30)
    silver_f = material("HelmetSilverFeather", SILVER, 0.18)
    fit, co, bvh, head = fit_head()
    S = Shell(fit, head)

    def shell(G, trim):
        parts = build_shell(G, silver, dark)
        parts += build_trim(G, trim)
        parts.append(build_crest(G, silver))
        parts += build_rivets(G, silver)
        check_fit(G, bvh)
        for ob in parts:
            bake_mods(ob)
        return parts
    G = Grid(S)
    parts = shell(G, gold)
    men = shell(G, blue)
    for side in (1, -1):
        for ob in build_wing(S, side, gold, silver, gold_f, silver_f):
            bake_mods(ob)
            parts.append(ob)
    return join(parts, "CaptainHelmet"), join(men, "FootmanHelmet"), fit, co


def crop_key(co):
    if not body.data.shape_keys:
        body.shape_key_add(name="Basis")
    kb = body.data.shape_keys.key_blocks.get("HelmetCrop") or body.shape_key_add(name="HelmetCrop")
    for i, p in enumerate(co):
        kb.data[i].co = p
    kb.value = 1.0


def ride_head(helm):
    b = rig.data.bones[HEAD]
    helm.parent = rig
    helm.parent_type = "BONE"
    helm.parent_bone = HEAD
    helm.matrix_parent_inverse = (rig.matrix_world @ b.matrix_local @ Matrix.Translation((0, b.length, 0))).inverted()


def bake_ao(helm):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 64
    if sc.world is None:
        sc.world = bpy.data.worlds.new("Bake")
    sc.world.light_settings.distance = AO_DIST
    hidden = [ob for ob in bpy.data.objects if ob is not helm and not ob.hide_render]
    for ob in hidden:
        ob.hide_render = True
    me = helm.data
    ca = me.color_attributes.get("AO") or me.color_attributes.new("AO", "BYTE_COLOR", "POINT")
    me.color_attributes.active_color = ca
    bpy.ops.object.select_all(action="DESELECT")
    helm.select_set(True)
    bpy.context.view_layer.objects.active = helm
    sc.render.bake.target = "VERTEX_COLORS"
    bpy.ops.object.bake(type="AO")
    for ob in hidden:
        ob.hide_render = False


def export_glb(helm, path):
    # A mesh per material: with two, the exporter keeps the vertex colour on
    # the first only (it maps the second to the attribute's name, not COLOR_0)
    # and writes white for the second.
    parts = []
    for i, m in enumerate(helm.data.materials):
        me = helm.data.copy()
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index != i], context="FACES")
        bm.to_mesh(me)
        bm.free()
        me.materials.clear()
        me.materials.append(m)
        ob = bpy.data.objects.new(helm.name + m.name.removeprefix("Helmet"), me)
        ob.data.name = ob.name
        bpy.context.scene.collection.objects.link(ob)
        parts.append(ob)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
        export_vertex_color="ACTIVE", export_animations=False, export_skins=False, export_morph=False,
        export_extras=False, export_cameras=False, export_lights=False)
    for ob in parts:
        me = ob.data
        bpy.data.objects.remove(ob)
        bpy.data.meshes.remove(me)
    print("HELMET exported", path)


helm, men, fit, co = build()
if "glb" in OPT:
    bake_ao(helm)
    export_glb(helm, OPT["glb"])
if "men" in OPT:
    bake_ao(men)
    export_glb(men, OPT["men"])
helm, other = (men, helm) if OPT.get("keep") == "men" else (helm, men)
bpy.data.objects.remove(other)
if KEEP:
    crop_key(co)
    ride_head(helm)
if "blend" in OPT:
    for ob in [o for o in bpy.data.objects if o is not helm]:
        bpy.data.objects.remove(ob)
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=OPT["blend"])
    print("HELMET saved", OPT["blend"])
