"""Wolf Scout 3: fit the Tripo body, cloak and dagger and rig them (background Blender).

  blender -b --factory-startup --python rig_wolf_scout_3.py

Inputs: the textured Tripo takes in references/characters/tripo/wolf_scout_3/.
Output: art/wolf_scout_3d/wolf_scout_3_rig.blend with textures in ws3_textures/.

The body is scaled to 1.94 m (ear tips) with the feet centred on the origin,
facing -Y. The cloak is placed by the reference images' page ratio, centred on
the hood and pushed out of the body; below the shoulders its back is draped to
hang straight down behind her. Over her shoulders it stands a little higher and
is skinned like the body under it, so it stays draped over them in her crouch.
The hood is cut open round her ears, with room
to spare, and its painted openings are redrawn as cream hems round the holes,
so the fur at the base of her ears shows through. Joints were measured on
this mesh with plane sections (see JOINTS). Mixamo bone names keep the supplied
Wolf Scout clips usable. The tail is a plain 6-bone chain under the hips: no
constraint aims at its own child, so baked clips play the same in Godot.
"""
import bmesh, bpy, heapq, math, shutil, zipfile
import numpy as np
from pathlib import Path
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

ART = Path(__file__).resolve().parents[1]
REPO = ART.parents[5]
TAKES = REPO / 'projects/meridius/references/characters/tripo/wolf_scout_3'
TEX = ART / 'ws3_textures'
OUT = ART / 'wolf_scout_3_rig.blend'
H = 1.94            # ear tips
DAGGER_LEN = 0.55   # blade, guard and pommel size; the grip is lengthened to her fist
GUARD_GAP = 0.0005  # her little finger rests against the guard, the pommel this far clear
M = 0.014           # cloak clearance from the body

# ---------------------------------------------------------------- import
def unpack(part):
    TEX.mkdir(exist_ok=True)
    work = TEX / f'_{part}'
    if work.exists(): shutil.rmtree(work)
    with zipfile.ZipFile(TAKES / f'{part}_textured__take-01.zip') as z: z.extractall(work)
    fbx = next(work.glob('*.fbx')); jpg = next(work.glob('*.fbm/*.jpg'))
    tex = TEX / f'ws3_{part}_basecolor.jpg'; shutil.copyfile(jpg, tex)
    return work, fbx, tex

def import_part(part, name):
    work, fbx, tex = unpack(part)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(fbx))
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == 'MESH']
    for o in bpy.data.objects: o.select_set(False)
    for o in meshes: o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1: bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in new:
        if o != ob and o.name in bpy.data.objects: bpy.data.objects.remove(o)
    ob.name = ob.data.name = name
    mat = ob.data.materials[0]; mat.name = name + '_Mat'
    img = next(n.image for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE')
    img.filepath = bpy.path.relpath(str(tex), start=str(ART)); img.name = tex.name; img.reload()
    shutil.rmtree(work)
    return ob

def components(me):
    bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
    seen, out = set(), []
    for v in bm.verts:
        if v.index in seen: continue
        st, c = [v], []; seen.add(v.index)
        while st:
            x = st.pop(); c.append(x.index)
            for e in x.link_edges:
                o = e.other_vert(x)
                if o.index not in seen: seen.add(o.index); st.append(o)
        out.append(c)
    bm.free()
    return sorted(out, key=len, reverse=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene; sc.render.fps = 30; sc.unit_settings.system = 'METRIC'
body = import_part('body', 'WolfScout3_Body')
cloak = import_part('cloak', 'WolfScout3_Cloak')
dagger = import_part('dagger', 'WolfScout3_Dagger.Left')

# Tripo normalises each export to 1 unit on its longest side (the body's height).
k = H / max(v.co.z for v in body.data.vertices)
feet = [v.co.y for v in body.data.vertices if v.co.z < 0.03]
body.data.transform(Matrix.Scale(k, 4) @ Matrix.Translation((0, -sum(feet) / len(feet), 0)))

# ---------------------------------------------------------------- cloak fit
# wolf_nocloak_a.png and cloak_front_b_v4.png share one page: the drawn
# heights are 2009 and 1573 px and the cloak's top sits 83 px below the ears.
cz = max(v.co.z for v in cloak.data.vertices)
cloak.data.transform(Matrix.Scale(H * 1573 / 2009 / cz, 4))
top = max(v.co.z for v in cloak.data.vertices)
cloak.data.transform(Matrix.Translation((0, 0, H * (1 - 83 / 2009) - top)))
# The two flat discs on the hood are the drawn ear openings: drop them, the
# body's ears come through the hood there.
bm = bmesh.new(); bm.from_mesh(cloak.data); bm.verts.ensure_lookup_table()
discs = [c for c in components(cloak.data) if len(c) == 44 and sum(bm.verts[i].co.z for i in c) / 44 > 1.7]
hood_x = sum(bm.verts[i].co.x for c in discs for i in c) / sum(len(c) for c in discs)
bmesh.ops.delete(bm, geom=[bm.verts[i] for c in discs for i in c], context='VERTS')
bm.to_mesh(cloak.data); bm.free()
# Centre the hood on the head and set it round the skull.
cloak.data.transform(Matrix.Translation((-hood_x, 0.37, 0.05)))

parts = components(body.data)
BV = [v.co.copy() for v in body.data.vertices]
tail_part = max(parts[1:4], key=lambda c: sum(BV[i].y for i in c) / len(c))
tail_set = set(tail_part)
def is_ear(p): return all(BV[i].z > 1.84 and abs(BV[i].x) > 0.075 for i in p.vertices)
bvh_b = BVHTree.FromPolygons(BV, [list(p.vertices) for p in body.data.polygons
                                   if not set(p.vertices) & tail_set and not is_ear(p)])
bvh_t = BVHTree.FromPolygons(BV, [list(p.vertices) for p in body.data.polygons if set(p.vertices) <= tail_set])

def tail_exit(p):
    o, hits = Vector(p), []
    for _ in range(12):
        loc, _, _, _ = bvh_t.ray_cast(o, Vector((0, 1, 0)), 2.0)
        if loc is None: break
        hits.append(loc.y); o = loc + Vector((0, 1e-4, 0))
    return hits[-1] if len(hits) % 2 else None

me = cloak.data
V0 = np.array([v.co[:] for v in me.vertices]); n = len(V0)
nb = [[] for _ in range(n)]
for e in me.edges:
    a, b = e.vertices; nb[a].append(b); nb[b].append(a)
def pushes(V, tail=True):
    raw, hit = np.zeros_like(V), np.zeros(n, bool)
    for i, p in enumerate(V):
        loc, no, _, _ = bvh_b.find_nearest(Vector(p), 0.1)
        if loc is not None:
            sd = (Vector(p) - loc).dot(no)
            if sd < M: raw[i] += np.array(no) * (M - sd); hit[i] = True
        yb = tail_exit(p) if tail else None   # the cloak goes over the tail, never through it
        if yb is not None: raw[i, 1] += yb + M - p[1]; hit[i] = True
    return raw, hit
O = np.zeros_like(V0)
for it in range(70):
    raw, hit = pushes(V0 + O)
    O[hit] += raw[hit]
    if it < 60:
        for _ in range(2):
            mean = np.array([O[l].mean(0) if l else O[i] for i, l in enumerate(nb)])
            O += 0.5 * (mean - O)
raw, hit = pushes(V0 + O)
print('CLOAK_FIT contacts', int(hit.sum()), 'max offset', round(float(np.linalg.norm(O, axis=1).max()), 3))

# Drape: the cape hangs from her shoulder blades. Down each column of her back it
# falls straight until her seat pushes it out, as cloth does, instead of standing
# off her like a cone. The tail is left out: it moves, and the cloak simulation
# lays the cape over it wherever it is. The cape's own folds ride along; the
# shoulders and hood stay as fitted.
DRAPE_TOP, DRAPE_FULL, GAP = 1.52, 1.40, 0.03
V1 = V0 + O
XS, ZS = np.arange(-0.70, 0.705, 0.02), np.arange(DRAPE_TOP, 0.295, -0.01)
def rear(x, z):
    hit = bvh_b.ray_cast(Vector((x, 3, z)), Vector((0, -1, 0)), 5)[0]
    return None if hit is None else hit.y
back = V1[:, 1] > 0.05
top = back & (np.abs(V1[:, 2] - DRAPE_TOP) < 0.03)
anchor = np.array([V1[top & (np.abs(V1[:, 0] - x) < 0.03), 1].max() if (top & (np.abs(V1[:, 0] - x) < 0.03)).any()
                   else np.nan for x in XS])
ok = ~np.isnan(anchor); anchor = np.interp(XS, XS[ok], anchor[ok])
D = np.zeros((len(XS), len(ZS)))
for i, x in enumerate(XS):
    r, pts = anchor[i], [(DRAPE_TOP, anchor[i])]
    for z in ZS[1:]:
        s = rear(x, z)
        if s is not None: r = max(r, s + GAP)
        pts.append((z, r))
    hull = []   # upper hull, top down: the taut line over the supports
    for p in pts:
        while len(hull) >= 2 and ((hull[-1][0] - hull[-2][0]) * (p[1] - hull[-2][1])
                                  - (hull[-1][1] - hull[-2][1]) * (p[0] - hull[-2][0])) <= 0: hull.pop()
        hull.append(p)
    hz, hy = zip(*reversed(hull)); D[i] = np.interp(ZS, hz, hy)
k = np.exp(-0.5 * (np.arange(-4, 5) * 0.02 / 0.05) ** 2); k /= k.sum()
D = np.maximum(D, np.array([np.convolve(np.pad(D[:, j], 4, mode='edge'), k, 'valid') for j in range(len(ZS))]).T)
def drape_at(x, z):
    xi = np.clip((x - XS[0]) / 0.02, 0, len(XS) - 1.001); zi = np.clip((DRAPE_TOP - z) / 0.01, 0, len(ZS) - 1.001)
    a, b = int(xi), int(zi); fx, fz = xi - a, zi - b
    return ((1 - fx) * (1 - fz) * D[a, b] + fx * (1 - fz) * D[a + 1, b] + (1 - fx) * fz * D[a, b + 1] + fx * fz * D[a + 1, b + 1])
# Each vertex keeps its offset from the sheet's smoothed surface (its fold).
cape = np.flatnonzero(back & (V1[:, 2] < DRAPE_TOP + 0.1))
kd = KDTree(len(cape))
for j, i in enumerate(cape): kd.insert((V1[i, 0], 0, V1[i, 2]), j)
kd.balance()
dy = np.zeros(n)
for i in cape:
    if V1[i, 2] >= DRAPE_TOP: continue
    near = [(cape[j], d) for _, j, d in kd.find_range((V1[i, 0], 0, V1[i, 2]), 0.1) if abs(V1[cape[j], 1] - V1[i, 1]) < 0.1]
    w = np.array([math.exp(-0.5 * (d / 0.05) ** 2) for _, d in near])
    ref = float((w * V1[[j for j, _ in near], 1]).sum() / w.sum())
    t = min(1.0, (DRAPE_TOP - V1[i, 2]) / (DRAPE_TOP - DRAPE_FULL)); t = t * t * (3 - 2 * t)
    t *= min(1.0, (V1[i, 1] - 0.05) / 0.1)   # the cape's front edges stay put
    dy[i] = t * (drape_at(V1[i, 0], V1[i, 2]) - ref)
for _ in range(3): dy = 0.5 * dy + 0.5 * np.array([dy[l].mean() if l else dy[i] for i, l in enumerate(nb)])
V1[:, 1] += dy
O = np.zeros_like(V1)
for it in range(25):
    raw, hit = pushes(V1 + O, tail=False)
    O[hit] += raw[hit]
    if it < 20:
        mean = np.array([O[l].mean(0) if l else O[i] for i, l in enumerate(nb)]); O += 0.5 * (mean - O)
moved = np.abs(dy) > 0.01
print('CLOAK_DRAPE moved', int(moved.sum()), 'mean', round(float(dy[moved].mean()), 3), 'min', round(float(dy.min()), 3),
      'max', round(float(dy.max()), 3), 'push after', round(float(np.linalg.norm(O, axis=1).max()), 3))
print('CLOAK_DRAPE x0', [(round(float(z), 2), round(float(drape_at(0.0, z)), 3)) for z in (1.5, 1.4, 1.3, 1.2, 1.1, 1.0, 0.9, 0.8, 0.6, 0.4)])
V1 += O
for i, v in enumerate(me.vertices): v.co = Vector(V1[i])
me.update()

# ---------------------------------------------------------------- hood ear holes
# The hood's painted ear openings sit forward of where her ears come through
# it and are twice as wide as an ear. Each is redrawn round the outline where
# its ear passes through the hood: the dark inside fitted to the ear's base
# with a small gap, the cream rim drawn in as a narrow hem (texel by texel
# through the surface, so UV seams do not matter), and the old spot is filled
# with the cloth round it.
from mathutils.interpolate import poly_3d_calc
from mathutils.geometry import barycentric_transform, closest_point_on_tri, intersect_point_tri_2d
CV = [v.co.copy() for v in me.vertices]
bvh_c = BVHTree.FromPolygons(CV, [list(p.vertices) for p in me.polygons])
uvl = me.uv_layers.active.data
img = next(n.image for n in me.materials[0].node_tree.nodes if n.type == 'TEX_IMAGE')
img.filepath = str(TEX / 'ws3_cloak_basecolor.jpg'); img.reload(); IW, IH = img.size   # the blend is not saved yet
PX = np.empty(IW * IH * 4, np.float32); img.pixels.foreach_get(PX); PX = PX.reshape(IH, IW, 4)
SRC = PX.copy()
def uv_at(p):
    """UV, surface point and normal nearest p."""
    loc, nrm, fi, _ = bvh_c.find_nearest(p); poly = me.polygons[fi]
    w = poly_3d_calc([CV[i] for i in poly.vertices], loc)
    return sum((uvl[li].uv * wi for li, wi in zip(poly.loop_indices, w)), Vector((0, 0))), loc, nrm
def sample(uv):
    x = min(max(uv.x * IW - 0.5, 0), IW - 1.001); y = min(max(uv.y * IH - 0.5, 0), IH - 1.001)
    i, j = int(x), int(y); fx, fy = x - i, y - j
    return ((1 - fx) * (1 - fy) * SRC[j, i] + fx * (1 - fy) * SRC[j, i + 1] + (1 - fx) * fy * SRC[j + 1, i] + fx * fy * SRC[j + 1, i + 1])
def texels(centre, radius):
    """Every texel of the cloak within radius of centre: (row, col, surface point)."""
    out = []
    for poly in me.polygons:
        if (Vector(poly.center) - centre).length > radius + 0.1: continue
        li, vs = list(poly.loop_indices), list(poly.vertices)
        for k in range(1, len(li) - 1):
            U = [uvl[li[m]].uv.to_3d() for m in (0, k, k + 1)]; P3 = [CV[vs[m]] for m in (0, k, k + 1)]
            x0, x1 = int(min(u.x for u in U) * IW), int(max(u.x for u in U) * IW) + 1
            y0, y1 = int(min(u.y for u in U) * IH), int(max(u.y for u in U) * IH) + 1
            (ax, ay), (bx, by), (cx, cy) = [(u.x, u.y) for u in U]
            det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(det) < 1e-12: continue
            for row in range(max(y0, 0), min(y1, IH)):
                for col in range(max(x0, 0), min(x1, IW)):
                    px, py = (col + 0.5) / IW, (row + 0.5) / IH
                    l1 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / det
                    l2 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / det
                    if l1 < -1e-4 or l2 < -1e-4 or l1 + l2 > 1 + 1e-4: continue
                    p = P3[0] * l1 + P3[1] * l2 + P3[2] * (1 - l1 - l2)
                    if (p - centre).length < radius: out.append((row, col, p))
    return out
def at_uv(uv):
    """Surface point and normal of the cloak where the texture has uv."""
    uv = Vector(uv).to_3d()
    for poly in me.polygons:
        li, vs = list(poly.loop_indices), list(poly.vertices)
        for k in range(1, len(li) - 1):
            U = [uvl[li[m]].uv.to_3d() for m in (0, k, k + 1)]
            if intersect_point_tri_2d(uv, *U):
                return barycentric_transform(uv, *U, *[CV[vs[m]] for m in (0, k, k + 1)]), poly.normal.copy()
# The two painted openings in ws3_cloak_basecolor: centre and radius out to
# the edge of the cream rim, in UV.
HOLE_UV = {'Ear.L': ((0.698, 0.937), 92 / 4096), 'Ear.R': ((0.923, 0.370), 92 / 4096)}
def feather(d, r, w=0.006):
    t = min(1.0, max(0.0, (r - d) / w)); return t * t * (3 - 2 * t)

ear_parts = [c for c in parts[1:] if sum(BV[i].z for i in c) / len(c) > 1.7]   # two 47-vertex shells
EAR_GAP, HEM = 0.013, 0.016   # gap round the base of the ear (generous: it moves); width the rim is drawn to
def hull2(P):
    """Convex hull of 2D points, counter-clockwise."""
    P = sorted(P)
    def half(pts):
        h = []
        for p in pts:
            while len(h) >= 2 and (h[-1][0] - h[-2][0]) * (p[1] - h[-2][1]) - (h[-1][1] - h[-2][1]) * (p[0] - h[-2][0]) <= 0: h.pop()
            h.append(p)
        return h
    return half(P)[:-1] + half(P[::-1])[:-1]
def reach(hull, c, s):
    """Distance from the hull's inside origin to its edge in direction (c, s)."""
    best = math.inf
    for (ax, ay), (bx, by) in zip(hull, hull[1:] + hull[:1]):
        ex, ey = bx - ax, by - ay; den = c * ey - s * ex
        if abs(den) < 1e-12: continue
        t, u = (ax * ey - ay * ex) / den, (ax * s - ay * c) / den
        if t > 0 and -1e-9 <= u <= 1 + 1e-9: best = min(best, t)
    return best
def lum(uv): r, g, b, _ = sample(uv); return 0.299 * r + 0.587 * g + 0.114 * b
ANG = 72
HOLES = []   # (centre, normal, tangents, outline reach) per ear, for the cut below
for c in ear_parts:
    cs = set(c); hits = []
    for e in body.data.edges:
        a, b = e.vertices
        if a not in cs: continue
        d = BV[b] - BV[a]; h = bvh_c.ray_cast(BV[a], d.normalized(), d.length)[0]
        if h is not None: hits.append(h)
    side = 'Ear.L' if sum(BV[i].x for i in c) > 0 else 'Ear.R'
    _, E, nE = uv_at(sum(hits, Vector()) / len(hits))
    # Where the whole ear (its fur shell is part of the head; the part the body
    # skin below gives to the ear bone) passes through the hood, in the hood's
    # tangent plane: the opening is drawn round that outline.
    t1 = nE.orthogonal().normalized(); t2 = nE.cross(t1)
    def in_ear(p): return p.z > 1.80 and 0.075 < p.x * (1 if side == 'Ear.L' else -1) < 0.17 and p.y < 0.36
    cross = []
    for e in body.data.edges:
        a, b = e.vertices
        if not (in_ear(BV[a]) or in_ear(BV[b])): continue
        d = BV[b] - BV[a]; h = bvh_c.ray_cast(BV[a], d.normalized(), d.length)[0]
        if h is not None and (h - E).length < 0.1: cross.append(((h - E).dot(t1), (h - E).dot(t2)))
    hull = hull2(cross)
    cx, cy = sum(x for x, _ in hull) / len(hull), sum(y for _, y in hull) / len(hull)
    _, C, _ = uv_at(E + t1 * cx + t2 * cy); hull = [(x - cx, y - cy) for x, y in hull]
    (hu, hv), hr = HOLE_UV[side]; H, nH = at_uv((hu, hv))
    R = 0.004 + max((p - H).length for row, col, p in texels(H, 0.09)
                    if math.hypot((col + 0.5) / IW - hu, (row + 0.5) / IH - hv) < hr)
    q = nE.rotation_difference(nH); s1, s2 = q @ t1, q @ t2
    # The painted opening, direction by direction: radius of its dark inside.
    r_in = []
    for k in range(ANG):
        a = 2 * math.pi * k / ANG; dv = s1 * math.cos(a) + s2 * math.sin(a)
        prof = [(r, lum(uv_at(H + dv * r)[0])) for r in np.arange(0.0, R, 0.0015)]
        peak = max(l for _, l in prof)
        r_in.append(next(r for r, l in prof if l > (prof[0][1] + peak) / 2))
    r_in = np.array(r_in)
    # The outline's reach round the ear, smoothed so the hem runs round and not in facets.
    reach_a = np.array([reach(hull, math.cos(2 * math.pi * k / ANG), math.sin(2 * math.pi * k / ANG)) for k in range(ANG)])
    kern = np.exp(-0.5 * (np.arange(-12, 13) * 360 / ANG / 15) ** 2); kern /= kern.sum()
    reach_a = np.convolve(np.r_[reach_a[-12:], reach_a, reach_a[:12]], kern, 'valid')
    def target(p):
        """Where p falls on the painted opening: (direction, radius there), radius >= R outside it."""
        x, y = (p - C).dot(t1), (p - C).dot(t2); r = math.hypot(x, y)
        if r < 1e-6: return 0.0, 0.0
        a = math.atan2(y, x) % (2 * math.pi); A = np.arange(ANG + 1) * 2 * math.pi / ANG
        rho = float(np.interp(a, A, np.r_[reach_a, reach_a[:1]])) + EAR_GAP
        ri = float(np.interp(a, A, np.r_[r_in, r_in[:1]]))
        return a, (r / rho * ri if r <= rho else ri + (r - rho) * (R - ri) / HEM)
    # The old spot: cloth from a ring round it, blended by distance (Shepard).
    ring = []
    for k in range(48):
        a = 2 * math.pi * k / 48; u1 = nH.orthogonal().normalized(); u2 = nH.cross(u1)
        uv, loc, _ = uv_at(H + (u1 * math.cos(a) + u2 * math.sin(a)) * R * 1.12); ring.append((loc, sample(uv)))
    filled = 0
    for row, col, p in texels(H, R):
        w = np.array([1 / max((p - l).length, 1e-3) ** 2 for l, _ in ring]); col_ = (w[:, None] * np.array([c_ for _, c_ in ring])).sum(0) / w.sum()
        f = feather((p - H).length, R); PX[row, col] = PX[row, col] * (1 - f) + col_ * f; filled += 1
    # The opening redrawn round the ear: dark inside, then the rim as a hem.
    ext = float(reach_a.max()) + EAR_GAP + HEM + 0.004
    drawn = 0
    for row, col, p in texels(C, ext):
        a, rs = target(p)
        if rs >= R: continue
        f = feather(rs, R); src = H + (s1 * math.cos(a) + s2 * math.sin(a)) * rs
        PX[row, col] = PX[row, col] * (1 - f) + sample(uv_at(src)[0]) * f; drawn += 1
    ext2 = [round(reach(hull, math.cos(a), math.sin(a)), 3) for a in (0, math.pi / 2, math.pi, 3 * math.pi / 2)]
    print('EAR_HOLE', side, 'centre', [round(x, 3) for x in C], 'ear outline reach +x+y-x-y', ext2, 'crossings', len(cross),
          'painted dark radius', round(float(r_in.min()), 3), round(float(np.median(r_in)), 3), round(float(r_in.max()), 3),
          'rim edge', round(R, 3), 'moved', round((C - H).length, 3), 'texels', drawn, 'filled', filled, flush=True)
    HOLES.append((C, nE, t1, t2, reach_a))
img.pixels.foreach_set(PX.ravel()); img.update()
img.filepath_raw = str(TEX / 'ws3_cloak_basecolor.jpg'); img.file_format = 'JPEG'
try: img.save(quality=95)
except TypeError: img.save()
img.filepath = bpy.path.relpath(str(TEX / 'ws3_cloak_basecolor.jpg'), start=str(ART))

# The dark inside of each opening is cut out of the hood, so the fur round the
# base of her ears shows through; the painted rim is left as the hole's hem.
CUT_OUT = 0.0015   # past the dark edge, so the hem left is cream
def sheet(bm, C, radius):
    """The hood's vertices round C that are reached through the mesh."""
    start = min(bm.verts, key=lambda v: (v.co - C).length); seen, todo = {start}, [start]
    while todo:
        v = todo.pop()
        for e in v.link_edges:
            w = e.other_vert(v)
            if w not in seen and (w.co - C).length < radius: seen.add(w); todo.append(w)
    return seen
bm = bmesh.new(); bm.from_mesh(me)
for C, n, t1, t2, rho in HOLES:
    A, RHO = np.arange(ANG + 1) * 2 * math.pi / ANG, np.r_[rho, rho[:1]] + EAR_GAP + CUT_OUT
    def g(p):
        """Distance outside the hole's outline, in the plane the opening was drawn in."""
        d = p - C; x, y = d.dot(t1), d.dot(t2)
        return math.hypot(x, y) - float(np.interp(math.atan2(y, x) % (2 * math.pi), A, RHO))
    # The hood is coarse here (5 cm edges): its faces round the hole are cut
    # into a fine grid first, so the hole runs smoothly round the ear.
    reach_out = float(rho.max()) + EAR_GAP + CUT_OUT + 0.02
    near = sheet(bm, C, 0.16)
    region = [f for f in bm.faces if all(l.vert in near for l in f.loops) and
              min((closest_point_on_tri(C, *[l.vert.co for l in f.loops[k - 1:k + 1]], f.loops[0].vert.co) - C).length
                  for k in range(2, len(f.loops))) < reach_out]
    band = list({e for f in region for e in f.edges})
    edge_len = sum(e.calc_length() for e in band) / max(1, len(band))
    bmesh.ops.subdivide_edges(bm, edges=band, cuts=max(1, round(edge_len / 0.008) - 1), use_grid_fill=True, use_single_edge=True)
    mark = bm.verts.layers.float.new('hood_sheet')   # survives the cut, unlike the vertices themselves
    for v in sheet(bm, C, 0.12): v[mark] = 1.0
    cut = {}
    for e in bm.edges:
        a, b = e.verts
        if a[mark] < 0.5 or b[mark] < 0.5: continue
        ga = g(a.co)
        if (ga < 0) == (g(b.co) < 0): continue
        lo, hi = 0.0, 1.0   # the crossing, by bisection on the outline itself
        for _ in range(24):
            m = (lo + hi) / 2
            if (g(a.co.lerp(b.co, m)) < 0) == (ga < 0): lo = m
            else: hi = m
        cut[e] = (lo + hi) / 2
    new = bmesh.ops.subdivide_edges(bm, edges=list(cut), cuts=1, edge_percents=cut, quad_corner_type='STRAIGHT_CUT')['geom_inner']
    rim = [v for v in new if isinstance(v, bmesh.types.BMVert)]
    gone = [f for f in bm.faces if all(l.vert[mark] > 0.5 for l in f.loops) and g(f.calc_center_median()) < 0]
    bmesh.ops.delete(bm, geom=gone, context='FACES')
    print('EAR_CUT edge length', round(edge_len, 4), 'faces refined', len(region), 'cut edges', len(cut), 'faces removed', len(gone),
          'rim off outline mm', round(max(abs(g(v.co)) for v in rim) * 1000, 2) if rim else None, flush=True)
    bm.verts.layers.float.remove(mark)
bm.to_mesh(me); bm.free(); me.update()

# ---------------------------------------------------------------- dagger
# Cap the open grip tube; its ends sit inside the guard and pommel.
bm = bmesh.new(); bm.from_mesh(dagger.data); bm.verts.ensure_lookup_table()
zmax = max(v.co.z for v in bm.verts)
grip = next(c for c in components(dagger.data) if len(c) == 24)
gset = set(grip)
bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary and e.verts[0].index in gset], sides=0)
bm.to_mesh(dagger.data); bm.free()
gz = [dagger.data.vertices[i].co.z for i in grip]
gc = (min(gz) + max(gz)) / 2
# Grip centre to the origin, blade along +Z, scaled to DAGGER_LEN.
dagger.data.transform(Matrix.Scale(DAGGER_LEN / zmax, 4) @ Matrix.Translation((0, 0, -gc)))
GRIP_HALF = (max(gz) - min(gz)) * DAGGER_LEN / zmax / 2
GRIP_R = sum(Vector(dagger.data.vertices[i].co.xy).length for i in grip) / len(grip)
print('DAGGER grip length', round(2 * GRIP_HALF, 3), 'radius', round(GRIP_R, 4))

# ---------------------------------------------------------------- skeleton
# Left side (+X); the right side mirrors it. Measured with plane sections:
# arm centre y 0.2 z 1.47, elbow x 0.38, wrist x 0.655, knuckles x 0.805;
# knee z 0.61, ankle z 0.12, ball of the paw y 0.0.
JOINTS = {
    'mixamorig:Hips': (None, (0, 0.13, 0.99), (0, 0.11, 1.10)),
    'mixamorig:Spine': ('mixamorig:Hips', (0, 0.11, 1.10), (0, 0.085, 1.25)),
    'mixamorig:Spine1': ('mixamorig:Spine', (0, 0.085, 1.25), (0, 0.10, 1.40)),
    'mixamorig:Spine2': ('mixamorig:Spine1', (0, 0.10, 1.40), (0, 0.11, 1.575)),
    'mixamorig:Neck': ('mixamorig:Spine2', (0, 0.11, 1.575), (0, 0.12, 1.665)),
    'mixamorig:Head': ('mixamorig:Neck', (0, 0.12, 1.665), (0, 0.12, 1.93)),
    'Ear.L': ('mixamorig:Head', (0.10, 0.10, 1.80), (0.135, 0.08, 1.935)),
    'mixamorig:LeftShoulder': ('mixamorig:Spine2', (0.035, 0.11, 1.50), (0.175, 0.20, 1.505)),
    'mixamorig:LeftArm': ('mixamorig:LeftShoulder', (0.175, 0.20, 1.505), (0.38, 0.215, 1.466)),
    'mixamorig:LeftForeArm': ('mixamorig:LeftArm', (0.38, 0.215, 1.466), (0.655, 0.173, 1.47)),
    'mixamorig:LeftHand': ('mixamorig:LeftForeArm', (0.655, 0.173, 1.47), (0.79, 0.15, 1.458)),
    'mixamorig:LeftUpLeg': ('mixamorig:Hips', (0.10, 0.12, 0.99), (0.195, 0.08, 0.61)),
    'mixamorig:LeftLeg': ('mixamorig:LeftUpLeg', (0.195, 0.08, 0.61), (0.30, 0.16, 0.12)),
    'mixamorig:LeftFoot': ('mixamorig:LeftLeg', (0.30, 0.16, 0.12), (0.33, 0.0, 0.035)),
    'mixamorig:LeftToeBase': ('mixamorig:LeftFoot', (0.33, 0.0, 0.035), (0.335, -0.07, 0.03)),
}
FINGERS = {  # knuckle to tip, measured from a top view of the left hand
    'Thumb': [(0.735, 0.115, 1.448), (0.765, 0.095, 1.449), (0.79, 0.083, 1.451), (0.815, 0.07, 1.453)],
    'Index': [(0.805, 0.118, 1.462), (0.84, 0.116, 1.462), (0.872, 0.114, 1.462), (0.906, 0.112, 1.462)],
    'Middle': [(0.81, 0.15, 1.463), (0.846, 0.15, 1.463), (0.881, 0.149, 1.463), (0.917, 0.149, 1.463)],
    'Ring': [(0.805, 0.185, 1.462), (0.839, 0.186, 1.462), (0.872, 0.186, 1.462), (0.906, 0.187, 1.462)],
    'Pinky': [(0.795, 0.22, 1.46), (0.822, 0.222, 1.46), (0.848, 0.224, 1.46), (0.875, 0.226, 1.46)],
}
# Those heights are on the palm side; centre each point in its finger's cross
# section so the knuckles bend about the middle of the finger.
MAIN_BV = [BV[i] for i in parts[0]]
def centred(p):
    zs = [q.z for q in MAIN_BV if abs(q.x - p[0]) < 0.004 and abs(q.y - p[1]) < 0.01 and abs(q.z - p[2]) < 0.035]
    return (p[0], p[1], (min(zs) + max(zs)) / 2) if len(zs) > 3 else p
FINGERS = {f: [centred(p) for p in pts] for f, pts in FINGERS.items()}
print('FINGERS', {f: [round(p[2], 3) for p in pts] for f, pts in FINGERS.items()})
for f, pts in FINGERS.items():
    for i in range(3):
        JOINTS[f'mixamorig:LeftHand{f}{i+1}'] = (f'mixamorig:LeftHand{f}{i}' if i else 'mixamorig:LeftHand', pts[i], pts[i + 1])
# Tail: the chain follows the geodesic centreline from the open root loop,
# then curls with the tuft to her left.
TAIL = [(0, 0.25, 1.09), (0, 0.355, 0.97), (0, 0.40, 0.80), (-0.02, 0.42, 0.63),
        (0.03, 0.52, 0.47), (0.25, 0.62, 0.38), (0.48, 0.74, 0.38)]
for i in range(6):
    JOINTS[f'Tail.0{i+1}'] = (f'Tail.0{i}' if i else 'mixamorig:Hips', TAIL[i], TAIL[i + 1])
# Cloak: five chains down the draped back sheet, at z 1.45, 1.10, 0.75, 0.45.
CZ = [1.45, 1.10, 0.75, 0.45]
def sheet_y(x, z):
    """The back sheet's outer surface at (x, z)."""
    for w in (0.04, 0.07, 0.12):
        m = (V1[:, 1] > 0.1) & (np.abs(V1[:, 0] - x) < w) & (np.abs(V1[:, 2] - z) < w)
        if m.any(): return round(float(V1[m, 1].max()), 3)
CLOAK = {nm: (x, [sheet_y(x, z) for z in CZ]) for nm, x in
         (('Edge.R', -0.33), ('Back.R', -0.15), ('Back.C', 0.0), ('Back.L', 0.15), ('Edge.L', 0.33))}
print('CLOAK_CHAINS', CLOAK)
for nm, (x, ys) in CLOAK.items():
    for i in range(3):
        JOINTS[f'Cloak.{nm}.{i+1}'] = (f'Cloak.{nm}.{i}' if i else 'mixamorig:Spine2', (x, ys[i], CZ[i]), (x, ys[i + 1], CZ[i + 1]))

def mirror(name):
    for a, b in (('Left', 'Right'), ('.L', '.R')):
        if a in name: return name.replace(a, b)
    return None
for name in list(JOINTS):
    m = mirror(name)
    if m and m not in JOINTS and not name.startswith('Cloak.'):
        parent, h, t = JOINTS[name]
        JOINTS[m] = (mirror(parent) or parent, (-h[0], h[1], h[2]), (-t[0], t[1], t[2]))

arm = bpy.data.armatures.new('WolfScout3_Rig'); rig = bpy.data.objects.new('WolfScout3_Rig', arm)
sc.collection.objects.link(rig); arm.display_type = 'STICK'; rig.show_in_front = True
bpy.context.view_layer.objects.active = rig; rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.edit_bones
root = eb.new('ROOT'); root.head = (0, 0, 0); root.tail = (0, 0, 0.18); root.use_deform = False
def roll_axis(name):
    if 'Hand' in name and any(f in name for f in FINGERS): return Vector((0, 0, -1))  # curl about local X
    if name.startswith(('Tail', 'Cloak')): return Vector((1, 0, 0))
    return Vector((0, -1, 0))   # front: elbows, knees and spine flex about local X
order = []
def place(name):
    if name in order: return
    parent = JOINTS[name][0]
    if parent: place(parent)
    order.append(name)
for name in JOINTS: place(name)
for name in order:
    parent, h, t = JOINTS[name]
    b = eb.new(name); b.head = h; b.tail = t
    b.parent = eb[parent] if parent else root
    b.use_connect = bool(parent) and (Vector(eb[parent].tail) - Vector(h)).length < 1e-4
    b.align_roll(roll_axis(name))
for side, s in (('Left', 1), ('Right', -1)):
    hand = eb[f'mixamorig:{side}Hand']
    sock = eb.new(f'DaggerSocket.{side}')
    sock.head = (s * 0.80, 0.15, 1.425); sock.tail = (s * 0.80, 0.20, 1.425)  # reverse grip: blade back
    sock.parent = hand; sock.use_deform = False; sock.align_roll(Vector((0, 0, 1)))
bpy.ops.object.mode_set(mode='OBJECT')
print('BONES', len(arm.bones), 'deform', sum(b.use_deform for b in arm.bones))

# ---------------------------------------------------------------- body skin
def only_deform(names):
    for b in arm.bones: b.use_deform = b.name in names
def auto_weights(ob):
    for o in bpy.data.objects: o.select_set(False)
    ob.select_set(True); rig.select_set(True); bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')

# Split the body into its loose parts: heat weights for the main body and the
# tail, then the small parts (claws, pouch, ear linings) copy from the body.
def keep_only(ob, keep):
    bm = bmesh.new(); bm.from_mesh(ob.data); bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index not in keep], context='VERTS')
    bm.to_mesh(ob.data); bm.free()
def split_copy(name, keep):
    ob = body.copy(); ob.data = body.data.copy(); ob.name = name
    sc.collection.objects.link(ob); keep_only(ob, keep); return ob
main_set = set(parts[0])
tail_ob = split_copy('WS3_tail', tail_set)
bits = split_copy('WS3_bits', set(range(len(BV))) - main_set - tail_set)
keep_only(body, main_set)

body_bones = {b.name for b in arm.bones if b.name.startswith('mixamorig:') or b.name.startswith('Ear.')}
only_deform(body_bones); auto_weights(body)
only_deform({b.name for b in arm.bones if b.name.startswith('Tail.')}); auto_weights(tail_ob)
only_deform(body_bones)
bits.parent = rig
for g in body.vertex_groups: bits.vertex_groups.new(name=g.name)
dt = bits.modifiers.new('copy', 'DATA_TRANSFER'); dt.object = body
dt.use_vert_data = True; dt.data_types_verts = {'VGROUP_WEIGHTS'}
dt.vert_mapping = 'POLYINTERP_NEAREST'; dt.layers_vgroup_select_src = 'ALL'; dt.layers_vgroup_select_dst = 'NAME'
bpy.context.view_layer.objects.active = bits; bpy.ops.object.modifier_apply(modifier='copy')
for o in (tail_ob, bits):
    for md in list(o.modifiers): o.modifiers.remove(md)
for o in bpy.data.objects: o.select_set(False)
for o in (body, tail_ob, bits): o.select_set(True)
bpy.context.view_layer.objects.active = body; bpy.ops.object.join()
for md in list(body.modifiers): body.modifiers.remove(md)
body.parent = rig
mod = body.modifiers.new('Armature', 'ARMATURE'); mod.object = rig

# Hair and face follow the head only; ears belong to their ear bones.
G = {g.name: g for g in body.vertex_groups}
def set_weights(v, w):
    tot = sum(w.values())
    for g in list(v.groups): body.vertex_groups[g.group].remove([v.index])
    for nm, x in w.items():
        if x > 0: G[nm].add([v.index], x / tot, 'REPLACE')
def weights(v): return {body.vertex_groups[g.group].name: g.weight for g in v.groups if g.weight > 1e-4}
for v in body.data.vertices:
    p = v.co; w = weights(v)
    if p.z > 1.62 and abs(p.x) < 0.17 and p.y < 0.36:
        keep = {nm: x for nm, x in w.items() if nm in ('mixamorig:Head', 'mixamorig:Neck', 'Ear.L', 'Ear.R')}
        if p.z > 1.70: keep.pop('mixamorig:Neck', None)
        if not keep: keep = {'mixamorig:Head': 1}
        set_weights(v, keep)
    if p.z > 1.84 and abs(p.x) > 0.075:
        side = 'Ear.L' if p.x > 0 else 'Ear.R'
        t = min(1, max(0, (p.z - 1.80) / 0.05))
        set_weights(v, {side: t, 'mixamorig:Head': 1 - t})
# Game limit: four influences, normalised. Blender's Normalize All passes over
# groups of bones flagged non-deform at the time, so this is done by hand.
def tidy(ob, limit=4, floor=0.01):
    for v in ob.data.vertices:
        w = sorted(((g.group, g.weight) for g in v.groups), key=lambda gw: -gw[1])
        keep = [(i, x) for i, x in w[:limit] if x >= floor] or w[:1]
        s = sum(x for _, x in keep)
        for g in list(v.groups): ob.vertex_groups[g.group].remove([v.index])
        for i, x in keep: ob.vertex_groups[i].add([v.index], x / s, 'REPLACE')
tidy(body)

# ---------------------------------------------------------------- cloak skin
# Inverse-distance weights to the bones that carry the cloak; the hood rides
# on the head, the collar on the upper chest and shoulders.
segs = {b.name: (rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local) for b in arm.bones}
cloak_bones = [b for b in segs if b.startswith('Cloak.')] + ['mixamorig:Spine2', 'mixamorig:Neck',
               'mixamorig:LeftShoulder', 'mixamorig:RightShoulder', 'mixamorig:LeftArm', 'mixamorig:RightArm']
def seg_dist(p, a, b):
    ab = b - a; t = max(0, min(1, (p - a).dot(ab) / ab.length_squared)); return (p - (a + ab * t)).length
cloak.parent = rig
for nm in cloak_bones + ['mixamorig:Head']: cloak.vertex_groups.new(name=nm)
CG = {g.name: g for g in cloak.vertex_groups}
for v in cloak.data.vertices:
    p = v.co
    if p.z > 1.62:
        w = {'mixamorig:Head': 1.0}
    else:
        d = {nm: seg_dist(p, *segs[nm]) for nm in cloak_bones}
        if p.z < 1.40: d = {nm: x for nm, x in d.items() if not nm.endswith('Arm')}
        w = dict(sorted(((nm, 1 / max(x, 0.02) ** 4) for nm, x in d.items()), key=lambda kv: -kv[1])[:4])
        if p.z > 1.56:   # neckline blends into the hood
            t = (p.z - 1.56) / 0.06; s = sum(w.values())
            w = {nm: x / s * (1 - t) for nm, x in w.items()}; w['mixamorig:Head'] = t
    s = sum(w.values())
    for nm, x in w.items():
        if x / s > 0.01: CG[nm].add([v.index], x / s, 'REPLACE')
# Her shoulders hunch up and forward in the crouch. Over them and her upper
# arms the cloak is lifted to stand a little further off, and takes the skin of
# the body under it, so it rides up with them and drapes over them instead of
# letting them through. The back of the cape stays on its chains, the hood on
# her head. Where the hood's lower edge lies on her shoulders it follows them
# too, not her head, so her shoulders cannot come up through it when she bows.
LIFT, SH_TOP = 0.03, 1.68
TRUNK = {'mixamorig:' + nm for nm in ('Spine', 'Spine1', 'Spine2', 'Neck', 'LeftShoulder', 'RightShoulder',
                                      'LeftArm', 'RightArm', 'LeftForeArm', 'RightForeArm')}
SHOULDER = {'mixamorig:' + nm for nm in ('LeftShoulder', 'RightShoulder', 'LeftArm', 'RightArm')}
BW = [weights(v) for v in body.data.vertices]; BCO = [v.co.copy() for v in body.data.vertices]
trunk_polys = [list(p.vertices) for p in body.data.polygons if all(BW[i] and max(BW[i], key=BW[i].get) in TRUNK for i in p.vertices)]
bvh_s = BVHTree.FromPolygons(BCO, trunk_polys)
CV = np.array([v.co[:] for v in cloak.data.vertices]); cn = len(CV)
cnb = [[] for _ in range(cn)]
for e in cloak.data.edges:
    a, b = e.vertices; cnb[a].append(b); cnb[b].append(a)
under, tw, need = [None] * cn, np.zeros(cn), np.zeros((cn, 3))
for i, p in enumerate(CV):
    if p[2] > SH_TOP: continue
    loc, no, fi, d = bvh_s.find_nearest(Vector(p), 0.10)
    if loc is None: continue
    ids = trunk_polys[fi]; ws = np.array([1 / max((BCO[k] - loc).length, 1e-4) for k in ids]); ws /= ws.sum()
    w = {}
    for k, x in zip(ids, ws):
        for nm, y in BW[k].items(): w[nm] = w.get(nm, 0) + x * y
    share = sum(x for nm, x in w.items() if nm in SHOULDER)
    tw[i] = min(1, share / 0.4) * min(1, (0.10 - d) / 0.04) * min(1, (SH_TOP - p[2]) / 0.04)
    under[i] = w; need[i] = np.array(no) * max(0, LIFT - (Vector(p) - loc).dot(no))
for _ in range(4): tw = 0.5 * tw + 0.5 * np.array([tw[l].mean() if l else tw[i] for i, l in enumerate(cnb)])
tw[[u is None for u in under]] = 0
# The lift is the largest one needed within 3 cm, so both faces of the cloth move together.
ckd = KDTree(cn)
for i, p in enumerate(CV): ckd.insert(p, i)
ckd.balance()
lift = np.zeros((cn, 3))
for i, p in enumerate(CV):
    if tw[i] > 0:
        near = [j for _, j, _ in ckd.find_range(p, 0.03)]
        lift[i] = tw[i] * need[near][np.argmax(np.linalg.norm(need[near], axis=1))]
for _ in range(3): lift = 0.5 * lift + 0.5 * np.array([lift[l].mean(0) if l else lift[i] for i, l in enumerate(cnb)])
for i, v in enumerate(cloak.data.vertices): v.co += Vector(lift[i])
cloak.data.update()
for i, v in enumerate(cloak.data.vertices):
    if tw[i] <= 0: continue
    w = {cloak.vertex_groups[g.group].name: g.weight * (1 - tw[i]) for g in v.groups}
    for nm, x in under[i].items(): w[nm] = w.get(nm, 0) + x * tw[i]
    for g in list(v.groups): cloak.vertex_groups[g.group].remove([v.index])
    for nm, x in w.items():
        if x > 1e-4: (CG.get(nm) or CG.setdefault(nm, cloak.vertex_groups.new(name=nm))).add([v.index], x, 'REPLACE')
print('CLOAK_SHOULDERS skinned from the body', int((tw > 0.5).sum()), 'blended', int(((tw > 0) & (tw <= 0.5)).sum()),
      'lift max mm', round(float(np.linalg.norm(lift, axis=1).max()) * 1000, 1))
cm = cloak.modifiers.new('Armature', 'ARMATURE'); cm.object = rig
tidy(cloak)

# ---------------------------------------------------------------- grip
# Reverse grip, blade out of the little-finger side. The grip lies across the
# finger roots, pressed up against the palm. Each finger wraps it: its three
# joint angles are searched together for the pose whose segments all rest on
# the grip without sinking in, and the spot under the palm that wraps best
# wins. The thumb closes over the index finger the same way. Then the dagger
# slides along its axis until the underside of the guard rests on the top of
# her little finger, and the grip is lengthened, if needed, until the pommel
# clears her index finger and thumb (both found by casting along the axis from
# the closed fist to the real dagger). The finger rotations go on the rig as
# GripPose (bone -> local quaternion).
TO_SOCK = {'Left': Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1))),   # blade +Z to socket +Y
           'Right': Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))}  # turned half a turn
NAMES = {g.index: g.name for g in body.vertex_groups}
MAIN = set(components(body.data)[0])
DOM = [NAMES[max(v.groups, key=lambda g: g.weight).group] if len(v.groups) else '' for v in body.data.vertices]
CO = np.array([v.co[:] for v in body.data.vertices])

def rot(axis, deg):
    """Batch of 4x4 turns about local X or Z."""
    t = np.radians(np.atleast_1d(np.asarray(deg, float))); c, s = np.cos(t), np.sin(t)
    i, j, k = (1, 2, 0) if axis == 'X' else (0, 1, 2)
    R = np.zeros((len(t), 4, 4)); R[:, 3, 3] = 1; R[:, k, k] = 1
    R[:, i, i] = c; R[:, i, j] = -s; R[:, j, i] = s; R[:, j, j] = c
    return R
def about(bone, R):
    """Armature-space matrices for local turns R of a bone about its head."""
    M = np.array(arm.bones[bone].matrix_local); return M @ R @ np.linalg.inv(M)

def chain(side, f):
    """The vertices one finger moves: rest positions, weights to its three bones, segment of each."""
    names = [f'mixamorig:{side}Hand{f}{i}' for i in (1, 2, 3)]
    col = {n: k for k, n in enumerate(names)}
    rows, W = [], []
    for v in body.data.vertices:
        if v.index not in MAIN: continue
        w = [0.0] * 3
        for g in v.groups:
            k = col.get(NAMES[g.group])
            if k is not None: w[k] = g.weight
        if sum(w) > 0.05: rows.append(v.index); W.append(w)
    return names, CO[rows], np.array(W), np.array([col.get(DOM[i], -1) for i in rows])

def skin(P0, W, M1, M2, M3):
    """Positions for every combination: M1 (a,4,4), M2 (a,b,4,4), M3 (a,b,c,4,4) -> (a,b,c,n,3)."""
    D1 = np.einsum('aij,nj->ani', M1[..., :3, :3], P0) + M1[:, None, :3, 3]
    D2 = np.einsum('abij,nj->abni', M2[..., :3, :3], P0) + M2[:, :, None, :3, 3]
    D3 = np.einsum('abcij,nj->abcni', M3[..., :3, :3], P0) + M3[:, :, :, None, :3, 3]
    return (P0 + W[:, 0:1] * (D1[:, None, None] - P0) + W[:, 1:2] * (D2[:, :, None] - P0)
            + W[:, 2:3] * (D3 - P0))

def solve_finger(side, f, gx, gz, g1, g2, g3):
    """Best joint angles from the given ranges: every segment resting on the grip,
    nothing more than 1.5 mm into it, a closed hand as the tie-break."""
    names, P0, W, seg = chain(side, f)
    L = [about(n, rot('X', g)) for n, g in zip(names, (g1, g2, g3))]
    M2 = L[0][:, None] @ L[1][None]; M3 = M2[:, :, None] @ L[2][None, None]
    P = skin(P0, W, L[0], M2, M3)
    sd = np.hypot(P[..., 0] - gx, P[..., 2] - gz) - GRIP_R
    cost = 20 * np.maximum(-sd.min(-1) - 0.0015, 0) - 2e-6 * (g1[:, None, None] + g2[None, :, None] + g3[None, None, :])
    for k in range(3):
        if (seg == k).any(): cost = cost + np.maximum(sd[..., seg == k].min(-1), 0)
    i = np.unravel_index(np.argmin(cost), cost.shape)
    ang = (float(g1[i[0]]), float(g2[i[1]]), float(g3[i[2]]))
    gaps = [round(float(sd[i][seg == k].min()), 4) if (seg == k).any() else None for k in range(3)]
    return float(cost[i]), names, ang, gaps, round(float(sd[i].min()), 4)

def finger_pose(side, gx, gz):
    out, total = {}, 0.0
    for f in ('Index', 'Middle', 'Ring', 'Pinky'):
        c, names, ang, gaps, low = solve_finger(side, f, gx, gz, np.arange(0, 91, 5.0), np.arange(0, 106, 5.0), np.arange(0, 81, 5.0))
        fine = [np.clip(np.arange(a - 4, a + 5), 0, None) for a in ang]
        c, names, ang, gaps, low = solve_finger(side, f, gx, gz, *fine)
        out[f] = (names, ang, gaps, low); total += c
    return out, total

def grip_for(side, dx):
    """Grip axis under the finger roots (shifted dx towards the fingertips), touching the palm."""
    s = 1 if side == 'Left' else -1
    roots = [Vector(arm.bones[f'mixamorig:{side}Hand{f}1'].head_local) for f in ('Index', 'Middle', 'Ring', 'Pinky')]
    gx = s * (sum(abs(r.x) for r in roots) / 4 + dx)
    ys = [r.y for r in roots]
    under = [p[2] for i, p in enumerate(CO) if i in MAIN and DOM[i].startswith(f'mixamorig:{side}Hand')
             and abs(p[0] - gx) < GRIP_R and min(ys) - 0.01 < p[1] < max(ys) + 0.01]
    return gx, min(under) - GRIP_R - 0.001

def thumb_pose(side, gx, gz, fingers):
    """The thumb closes over the index and middle fingers (as capsules) and the grip, and keeps out
    of the pommel, a 3 cm cylinder on the grip axis past the index finger."""
    caps = []
    for f in ('Index', 'Middle'):
        names, ang, _, _ = fingers[f]; M = np.eye(4)
        for n, g in zip(names, ang):
            M = M @ about(n, rot('X', g))[0]; b = arm.bones[n]
            h, t = np.array(b.head_local), np.array(b.tail_local); u = (t - h) / b.length
            r = np.median([np.linalg.norm(np.cross(CO[i] - h, u)) for i in range(len(CO)) if DOM[i] == n])
            caps.append(((M @ np.array([*h, 1]))[:3], (M @ np.array([*t, 1]))[:3], r))
    end = min(min(h[1], t[1]) - r for h, t, r in caps[:3])
    names, P0, W, seg = chain(side, 'Thumb')
    g1, g2, g3 = np.arange(-20, 51, 5.0), np.arange(0, 81, 5.0), np.arange(0, 81, 5.0)
    best = None
    for spread in range(-40, 41, 10):
        L1 = about(names[0], rot('Z', spread)[0] @ rot('X', g1))
        L2 = about(names[1], rot('X', g2)); L3 = about(names[2], rot('X', g3))
        M2 = L1[:, None] @ L2[None]; M3 = M2[:, :, None] @ L3[None, None]
        P = skin(P0, W, L1, M2, M3)
        # sd: what the thumb may rest on (the fingers, the grip inside the fist); clash adds the pommel.
        rad = np.hypot(P[..., 0] - gx, P[..., 2] - gz); past = P[..., 1] < end
        sd = np.where(past, 1.0, rad - GRIP_R)
        for h, t, r in caps:
            ab = t - h; u = np.clip(((P - h) @ ab) / (ab @ ab), 0, 1)
            sd = np.minimum(sd, np.linalg.norm(P - (h + u[..., None] * ab), axis=-1) - r)
        clash = np.minimum(sd, np.where(past, rad - 0.03, 1.0))
        cost = 20 * np.maximum(-clash.min(-1) - 0.0015, 0) + np.maximum(sd[..., seg == 2].min(-1), 0) \
            + 0.5 * np.maximum(sd[..., seg == 1].min(-1), 0)
        i = np.unravel_index(np.argmin(cost), cost.shape)
        if best is None or cost[i] < best[0]:
            best = (float(cost[i]), spread, (float(g1[i[0]]), float(g2[i[1]]), float(g3[i[2]])), round(float(clash[i].min()), 4))
    return names, best

def hand_points(side, quats):
    """Hand vertices with the fingers turned (hand at rest)."""
    Ms = {}
    for f in ('Thumb', 'Index', 'Middle', 'Ring', 'Pinky'):
        M = np.eye(4)
        for i in (1, 2, 3):
            n = f'mixamorig:{side}Hand{f}{i}'
            M = M @ about(n, np.array(Quaternion(quats[n]).to_matrix().to_4x4())[None])[0]; Ms[n] = M
    out = []
    for i in range(len(CO)):
        if i not in MAIN or not DOM[i].startswith(f'mixamorig:{side}Hand'): continue
        p = np.array([*CO[i], 1]); q = np.zeros(3); tot = 0.0
        for g in body.data.vertices[i].groups:
            M = Ms.get(NAMES[g.group])
            q += g.weight * ((M @ p)[:3] if M is not None else CO[i]); tot += g.weight
        out.append(q / tot)
    return np.array(out)

GRIP_POSE, SOCKETS, HANDS = {}, {}, {}
for side in ('Left', 'Right'):
    best = None
    for dx in (-0.03, -0.02, -0.01, 0.0):
        gx, gz = grip_for(side, dx)
        fingers, cost = finger_pose(side, gx, gz)
        print('GRIP', side, 'dx', dx, 'cost', round(cost, 4),
              {f: (tuple(int(a) for a in v[1]), v[2], v[3]) for f, v in fingers.items()}, flush=True)
        if best is None or cost < best[0]: best = (cost, gx, gz, fingers)
    _, gx, gz, fingers = best
    quats = {}
    for f, (names, ang, _, _) in fingers.items():
        for n, g in zip(names, ang): quats[n] = list(Quaternion((1, 0, 0), math.radians(g)))
    names, (tc, spread, tang, tmin) = thumb_pose(side, gx, gz, fingers)
    print('THUMB', side, 'spread', spread, 'curl', tang, 'lowest', tmin, flush=True)
    quats[names[0]] = list(Quaternion((0, 0, 1), math.radians(spread)) @ Quaternion((1, 0, 0), math.radians(tang[0])))
    for n, g in zip(names[1:], tang[1:]): quats[n] = list(Quaternion((1, 0, 0), math.radians(g)))
    HANDS[side] = (gx, gz, hand_points(side, quats)); GRIP_POSE.update(quats)
rig['GripPose'] = GRIP_POSE

def fit(side):
    """Socket y range along the blade: the guard on the fist (lowest), the pommel clear of it (highest),
    and the hand part that holds the guard."""
    gx, gz, pts = HANDS[side]
    bvh = BVHTree.FromPolygons([TO_SOCK[side].to_3x3() @ v.co for v in dagger.data.vertices],
                               [tuple(p.vertices) for p in dagger.data.polygons])
    parts = [DOM[i] for i in range(len(CO)) if i in MAIN and DOM[i].startswith(f'mixamorig:{side}Hand')]
    lo, hi, who = -1.0, 1.0, ''
    for p, part in zip(pts, parts):
        # Points on the grip itself would only hit the inside of its tube.
        x, z = p[0] - gx, p[2] - gz
        if not GRIP_R + 0.0015 < math.hypot(x, z) < 0.1: continue
        hit = bvh.ray_cast(Vector((x, GRIP_HALF - 0.02, z)), Vector((0, 1, 0)), 0.3)[0]
        if hit is not None and p[1] - hit.y + GUARD_GAP > lo: lo, who = p[1] - hit.y + GUARD_GAP, part
        hit = bvh.ray_cast(Vector((x, -GRIP_HALF + 0.02, z)), Vector((0, -1, 0)), 0.3)[0]
        if hit is not None: hi = min(hi, p[1] - hit.y - GUARD_GAP)
    return lo, hi, who.split(':')[-1]

# Lengthen the grip (pommel end) until every fist fits between guard and pommel.
short = max(fit(side)[0] - fit(side)[1] for side in HANDS)
if short > 0:
    for v in dagger.data.vertices:
        if v.co.z < -GRIP_HALF + 0.003 or (v.index in gset and v.co.z < 0): v.co.z -= short + 0.002
print('DAGGER grip lengthened by', round(max(short + 0.002, 0), 4), flush=True)
for side in HANDS:
    lo, hi, who = fit(side)
    SOCKETS[side] = Vector((HANDS[side][0], lo, HANDS[side][1]))
    print('SOCKET', side, [round(c, 4) for c in SOCKETS[side]], 'guard on', who, 'pommel room', round(hi - lo, 4), flush=True)
bpy.context.view_layer.objects.active = rig; bpy.ops.object.mode_set(mode='EDIT')
for side, head in SOCKETS.items():
    sb = arm.edit_bones[f'DaggerSocket.{side}']; sb.head = head; sb.tail = head + Vector((0, 0.05, 0)); sb.align_roll(Vector((0, 0, 1)))
bpy.ops.object.mode_set(mode='OBJECT')

# ---------------------------------------------------------------- daggers
for b in arm.bones: b.use_deform = not (b.name == 'ROOT' or b.name.startswith('DaggerSocket'))
right = dagger.copy(); right.data = dagger.data.copy(); right.name = right.data.name = 'WolfScout3_Dagger.Right'
sc.collection.objects.link(right)
for ob, side in ((dagger, 'Left'), (right, 'Right')):
    sock = arm.bones[f'DaggerSocket.{side}']
    # Socket +Y is the blade (back, out of the pinky side), +Z up; the dagger's
    # blade is +Z and its flat is XZ. Proper rotations, no mirror.
    ob.data.transform(rig.matrix_world @ sock.matrix_local @ TO_SOCK[side])
    ob.data.update(); ob.parent = rig
    g = ob.vertex_groups.new(name=f'mixamorig:{side}Hand'); g.add(list(range(len(ob.data.vertices))), 1.0, 'REPLACE')
    md = ob.modifiers.new('Armature', 'ARMATURE'); md.object = rig

rig['Grip_Left'] = 0.0; rig['Grip_Right'] = 0.0
# The factory Shading workspace's file browser holds the user's Documents
# folder; the rig scene is public, so it goes.
bpy.data.batch_remove([w for w in bpy.data.workspaces
                       if any(sp.type == 'FILE_BROWSER' for s in w.screens for a in s.areas for sp in a.spaces)])
bpy.ops.wm.save_as_mainfile(filepath=str(OUT), relative_remap=True)
print('SAVED', OUT)
