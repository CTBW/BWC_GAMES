"""Build the iron jaw plate on the orc's head (rest pose): one of his squad's faces.

  blender -b orc_brute_rig.blend --python jaw_plate.py -- <out.blend> <params.json> [grid.npz]

Saves the rig with the plate, `JawPlate`, skinned whole to the head. The params (jaw_plate.json)
give its outline, thickness, rims and rivets; `texture` is its base colour, a path relative to
the out file's folder (made by jaw_texture.py from the plate's grid, which `grid.npz` saves).

The plate is a chin cup with a band along each side of the jaw that rises to below the ear.
It is laid out on a grid of (theta, t): theta round the jaw from the front (0, -Y) towards
his left (+X), t from the top edge (0) to the bottom edge (1). Its inside follows the face's
outer envelope: horizontal rays towards a vertical axis give the skin's radius, and a rolling
ball of radius BALL bridges the hollows (under the chin, the crease below the lip), so the
iron spans them as a rigid plate would."""
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = Path(argv[0]).resolve()
P = json.load(open(argv[1])) if len(argv) > 1 else {}
GRID = argv[2] if len(argv) > 2 else None
MX = "mixamorig:"
YC = P.get("yc", -0.02)
TH_END = math.radians(P.get("th_end", 100.0))
BALL = P.get("ball", 0.025)
GAP = P.get("gap", 0.003)
THK = P.get("thk", 0.0045)
RIM = P.get("rim", 0.0025)
RIM_W = P.get("rim_w", 0.0035)
COLS = P.get("cols", 34)          # per side
ROWS = P.get("rows", 11)
# Outline: (deg, z) knots, mirrored to his right.
TOP = P.get("top", [[0, 1.737], [25, 1.739], [45, 1.744], [62, 1.762], [78, 1.790], [92, 1.803], [100, 1.805]])
BOT = P.get("bot", [[0, 1.674], [25, 1.679], [45, 1.689], [62, 1.703], [78, 1.718], [92, 1.733], [100, 1.742]])
END_R = P.get("end_r", 0.014)     # radius rounding the band's end (metres along the band)
RIVETS = P.get("rivets", [[0, 0.33], [16, 0.33], [32, 0.36], [0, 0.70], [16, 0.69], [32, 0.66],
                          [52, 0.50], [70, 0.50], [88, 0.50]])
RIV_R = P.get("riv_r", 0.0055)
RIV_H = P.get("riv_h", 0.0035)

body = bpy.data.objects["OrcBrute"]
rig = bpy.data.objects["OrcBruteRig"]
rig.data.pose_position = "REST"
bpy.context.view_layer.update()
ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
me = ev.to_mesh()
bm = bmesh.new()
bm.from_mesh(me)
bm.transform(body.matrix_world)
# Only the main skin: drop loose parts under 1000 verts (tusks, teeth, eyes, earrings, pauldrons, straps).
bm.verts.ensure_lookup_table()
comp = [-1] * len(bm.verts)
sizes = []
for v in bm.verts:
    if comp[v.index] >= 0:
        continue
    k = len(sizes)
    stack = [v]
    comp[v.index] = k
    n = 0
    while stack:
        a = stack.pop()
        n += 1
        for e in a.link_edges:
            o = e.other_vert(a)
            if comp[o.index] < 0:
                comp[o.index] = k
                stack.append(o)
    sizes.append(n)
drop = [v for v in bm.verts if sizes[comp[v.index]] < 1000]
bmesh.ops.delete(bm, geom=drop, context="VERTS")
skin = BVHTree.FromBMesh(bm)
full = bmesh.new()
full.from_mesh(me)
full.transform(body.matrix_world)
every = BVHTree.FromBMesh(full)
print("SKIN verts", len(bm.verts), "dropped", len(drop))


def interp(knots, deg):
    d = abs(deg)
    xs = [k[0] for k in knots]
    ys = [k[1] for k in knots]
    return float(np.interp(d, xs, ys))


# 1. The skin's radius on a fine (theta, z) grid.
TH_F = np.radians(np.arange(-110, 111, 1.0))
Z_F = np.arange(1.60, 1.86, 0.001)
R = np.full((len(TH_F), len(Z_F)), np.nan)
for i, th in enumerate(TH_F):
    d = Vector((math.sin(th), -math.cos(th), 0.0))
    for j, z in enumerate(Z_F):
        c = Vector((0.0, YC, z))
        hit = skin.ray_cast(c + d * 0.6, -d, 0.6)
        if hit[0] is not None:
            R[i, j] = math.hypot(hit[0].x - c.x, hit[0].y - c.y)
miss = np.isnan(R)
print("RAYS", R.size, "missed", int(miss.sum()))
R = np.where(miss, 0.0, R)
# 2. Rolling-ball envelope in (arc, z): max over a disk of (r - sag).
rmean = 0.11
dth = 1.0 * math.pi / 180
ENV = R.copy()
nth = int(BALL / (rmean * dth)) + 1
nz = int(BALL / 0.001) + 1
for a in range(-nth, nth + 1):
    for b in range(-nz, nz + 1):
        dd = (a * dth * rmean) ** 2 + (b * 0.001) ** 2
        if dd >= BALL * BALL or (a == 0 and b == 0):
            continue
        sag = BALL - math.sqrt(BALL * BALL - dd)
        sh = np.roll(np.roll(R, -a, 0), -b, 1) - sag
        ENV = np.maximum(ENV, sh)
# Smooth it (beaten iron, not skin): a separable Gaussian, BLUR_TH degrees by BLUR_Z metres.
BLUR_TH, BLUR_Z = P.get("blur_th", 3.0), P.get("blur_z", 0.004)


def gauss(n_sigma):
    k = int(3 * n_sigma) + 1
    x = np.arange(-k, k + 1)
    w = np.exp(-0.5 * (x / n_sigma) ** 2)
    return w / w.sum()


if BLUR_TH > 0:
    w = gauss(BLUR_TH / 1.0)
    ENV = np.apply_along_axis(lambda a: np.convolve(np.pad(a, len(w) // 2, mode="edge"), w, "valid"), 0, ENV)
if BLUR_Z > 0:
    w = gauss(BLUR_Z / 0.001)
    ENV = np.apply_along_axis(lambda a: np.convolve(np.pad(a, len(w) // 2, mode="edge"), w, "valid"), 1, ENV)
print("ENV lift max %.4f mean %.4f" % (float((ENV - R).max()), float((ENV - R).mean())))


def env_at(th, z):
    fi = (math.degrees(th) + 110) / 1.0
    fj = (z - 1.60) / 0.001
    i0, j0 = int(math.floor(fi)), int(math.floor(fj))
    u, v = fi - i0, fj - j0
    i0 = min(max(i0, 0), len(TH_F) - 2)
    j0 = min(max(j0, 0), len(Z_F) - 2)
    a = ENV[i0, j0] * (1 - u) + ENV[i0 + 1, j0] * u
    b = ENV[i0, j0 + 1] * (1 - u) + ENV[i0 + 1, j0 + 1] * u
    return a * (1 - v) + b * v


def surf(th, z, off):
    r = env_at(th, z) + off
    return Vector((math.sin(th) * r, YC - math.cos(th) * r, z))


# 3. The grid. Columns denser towards the band's end (for its rounded end).
cols = np.concatenate([np.linspace(-TH_END, 0, COLS + 1)[:-1], np.linspace(0, TH_END, COLS + 1)])
# Arc length along the band at mid height, to round the end in metres.
mid_arc = [0.0]
for a, b in zip(cols[:-1], cols[1:]):
    zm = 0.5 * (interp(TOP, math.degrees(a)) + interp(BOT, math.degrees(a)))
    mid_arc.append(mid_arc[-1] + (surf(b, zm, GAP) - surf(a, zm, GAP)).length)
mid_arc = np.array(mid_arc)
L = mid_arc[-1]


def zrange(ci):
    th = cols[ci]
    zt, zb = interp(TOP, math.degrees(th)), interp(BOT, math.degrees(th))
    # Round the band's ends: shrink the height towards the end over END_R.
    e = min(mid_arc[ci], L - mid_arc[ci])
    if e < END_R:
        h = zt - zb
        k = math.sqrt(max(0.0, 1 - ((END_R - e) / END_R) ** 2))
        mid = 0.5 * (zt + zb)
        zt, zb = mid + 0.5 * h * max(k, 0.18), mid - 0.5 * h * max(k, 0.18)
    return zt, zb


NC, NR = len(cols), ROWS + 1
ts = np.linspace(0.0, 1.0, NR)
inner = np.zeros((NC, NR, 3))
for ci in range(NC):
    zt, zb = zrange(ci)
    for ri, t in enumerate(ts):
        inner[ci, ri] = surf(cols[ci], zt + (zb - zt) * t, GAP)
# Normals of the inner surface (outward = away from the axis).
nrm = np.zeros_like(inner)
for ci in range(NC):
    for ri in range(NR):
        a = inner[min(ci + 1, NC - 1), ri] - inner[max(ci - 1, 0), ri]
        b = inner[ci, min(ri + 1, NR - 1)] - inner[ci, max(ri - 1, 0)]
        n = np.cross(b, a)
        radial = inner[ci, ri] - np.array([0.0, YC, inner[ci, ri][2]])
        if np.dot(n, radial) < 0:
            n = -n
        nrm[ci, ri] = n / np.linalg.norm(n)
# Distance to the nearest edge (metres, roughly) for the rolled rim.
edge_d = np.zeros((NC, NR))
for ci in range(NC):
    zt, zb = zrange(ci)
    for ri, t in enumerate(ts):
        h = abs(zt - zb)
        edge_d[ci, ri] = min(t * h, (1 - t) * h, mid_arc[ci], L - mid_arc[ci])
thick = THK + RIM * np.exp(-(edge_d / RIM_W) ** 2)
outer = inner + nrm * thick[..., None]

# 4. Keep the inside off the skin: push out any inner point closer than GAP/2 to the head.
pushed = 0
for ci in range(NC):
    for ri in range(NR):
        p = Vector(inner[ci, ri])
        loc, n, _, dist = every.find_nearest(p)
        if loc is None:
            continue
        inside = (p - loc).dot(n) < 0
        if inside or dist < GAP * 0.5:
            need = (GAP * 0.5 + (dist if inside else -dist))
            inner[ci, ri] += nrm[ci, ri] * need
            outer[ci, ri] += nrm[ci, ri] * need
            pushed += 1
print("PUSHED", pushed, "of", NC * NR)

# 5. Mesh: outer, inner, and the rim strip joining their boundaries.
mesh = bpy.data.meshes.new("JawPlate")
bmp = bmesh.new()
uvl = bmp.loops.layers.uv.new("UVMap")
vo = [[bmp.verts.new(outer[c, r]) for r in range(NR)] for c in range(NC)]
vi = [[bmp.verts.new(inner[c, r]) for r in range(NR)] for c in range(NC)]
# UV: the outer surface fills u 0..1, v V0..1 by (theta, t); the inside a dark patch; the
# rivets their own patch (as jaw_texture.py paints them).
V0, V1 = 0.70, 1.0


def uv_outer(ci, ri):
    return ((cols[ci] + TH_END) / (2 * TH_END), V1 - (V1 - V0) * ts[ri])


def uv_patch(ci, ri, box):
    x0, y0, x1, y1 = box
    return (x0 + (x1 - x0) * ci / (NC - 1), y0 + (y1 - y0) * ri / (NR - 1))


INNER_BOX = (0.03, 0.05, 0.62, 0.62)
faces = {"outer": [], "inner": [], "rim": []}
for c in range(NC - 1):
    for r in range(NR - 1):
        f = bmp.faces.new((vo[c][r], vo[c][r + 1], vo[c + 1][r + 1], vo[c + 1][r]))
        for loop, (cc, rr) in zip(f.loops, ((c, r), (c, r + 1), (c + 1, r + 1), (c + 1, r))):
            loop[uvl].uv = uv_outer(cc, rr)
        f.smooth = True
        faces["outer"].append(f)
        g = bmp.faces.new((vi[c + 1][r], vi[c + 1][r + 1], vi[c][r + 1], vi[c][r]))
        for loop, (cc, rr) in zip(g.loops, ((c + 1, r), (c + 1, r + 1), (c, r + 1), (c, r))):
            loop[uvl].uv = uv_patch(cc, rr, INNER_BOX)
        g.smooth = True
        faces["inner"].append(g)
# Rim strip round the boundary: walk the boundary of the (c, r) grid.
ring = [(c, 0) for c in range(NC)] + [(NC - 1, r) for r in range(1, NR)] + \
       [(c, NR - 1) for c in range(NC - 2, -1, -1)] + [(0, r) for r in range(NR - 2, 0, -1)]
for k in range(len(ring)):
    a, b = ring[k], ring[(k + 1) % len(ring)]
    f = bmp.faces.new((vo[a[0]][a[1]], vo[b[0]][b[1]], vi[b[0]][b[1]], vi[a[0]][a[1]]))
    # The rim's paint: the outer edge's own texels (the painted rim), squeezed.
    for loop, (cc, rr) in zip(f.loops, (a, b, b, a)):
        u, v = uv_outer(cc, rr)
        loop[uvl].uv = (u, v)
    f.smooth = False
    faces["rim"].append(f)
bmp.normal_update()
# Outward check: outer faces should face away from the axis.
bad = 0
for f in faces["outer"]:
    c = f.calc_center_median()
    if f.normal.dot(Vector((c.x, c.y - YC, 0))) < 0:
        bad += 1
print("OUTER faces", len(faces["outer"]), "facing in", bad)
if bad > len(faces["outer"]) // 2:
    bmesh.ops.reverse_faces(bmp, faces=bmp.faces[:])

# 6. Rivets: low domes on the outer surface.
RIV_BOX = (0.68, 0.33, 0.97, 0.62)


def outer_at(deg, t):
    th = math.radians(deg)
    # Column interpolation.
    fc = np.interp(th, cols, np.arange(NC))
    c0 = min(int(fc), NC - 2)
    u = fc - c0
    fr = t * (NR - 1)
    r0 = min(int(fr), NR - 2)
    v = fr - r0
    def bil(arr):
        a = arr[c0, r0] * (1 - u) + arr[c0 + 1, r0] * u
        b = arr[c0, r0 + 1] * (1 - u) + arr[c0 + 1, r0 + 1] * u
        return a * (1 - v) + b * v
    p = bil(outer)
    n = bil(nrm)
    return Vector(p), Vector(n / np.linalg.norm(n))


riv_pts = []
# Explicit rivets [deg, t, radius] (both sides given), else RIVETS mirrored to his right.
EXPLICIT = P.get("rivets_explicit")
todo_r = EXPLICIT if EXPLICIT else [[d * s_, t_, RIV_R] for d, t_ in RIVETS for s_ in ((1, -1) if d else (1,))]
for deg, t, RIV_R in todo_r:
    RIV_H = RIV_R * P.get("riv_h_ratio", 0.6)
    p, n = outer_at(deg, t)
    riv_pts.append((p, n))
    # Local frame.
    tz = Vector((0, 0, 1))
    tx = n.cross(tz).normalized()
    ty = n.cross(tx).normalized()
    segs, rings = 10, 3
    top = None
    rows_v = []
    for k in range(rings + 1):
        a = (math.pi / 2) * k / rings          # 0 at the base, pi/2 at the top
        rr = RIV_R * math.cos(a)
        hh = RIV_H * math.sin(a) - 0.001
        if k == rings:
            top = bmp.verts.new(p + n * hh)
            break
        rows_v.append([bmp.verts.new(p + n * hh + (tx * math.cos(2 * math.pi * q / segs) + ty * math.sin(2 * math.pi * q / segs)) * rr)
                       for q in range(segs)])

    def ruv(k, q):
        a = (math.pi / 2) * k / rings
        rr = math.cos(a) * 0.5
        x0, y0, x1, y1 = RIV_BOX
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        return (cx + (x1 - x0) * rr * math.cos(2 * math.pi * q / segs), cy + (y1 - y0) * rr * math.sin(2 * math.pi * q / segs))
    for k in range(len(rows_v) - 1):
        for q in range(segs):
            q2 = (q + 1) % segs
            f = bmp.faces.new((rows_v[k][q], rows_v[k][q2], rows_v[k + 1][q2], rows_v[k + 1][q]))
            for loop, (kk, qq) in zip(f.loops, ((k, q), (k, q2), (k + 1, q2), (k + 1, q))):
                loop[uvl].uv = ruv(kk, qq)
            f.smooth = True
    k = len(rows_v) - 1
    for q in range(segs):
        q2 = (q + 1) % segs
        f = bmp.faces.new((rows_v[k][q], rows_v[k][q2], top))
        for loop, (kk, qq) in zip(f.loops, ((k, q), (k, q2), (rings, 0))):
            loop[uvl].uv = ruv(kk, qq) if kk < rings else ((RIV_BOX[0] + RIV_BOX[2]) / 2, (RIV_BOX[1] + RIV_BOX[3]) / 2)
        f.smooth = True
bmp.normal_update()
bmp.to_mesh(mesh)
bmp.free()
plate = bpy.data.objects.new("JawPlate", mesh)
bpy.context.scene.collection.objects.link(plate)
TEXTURE = P.get("texture")
if TEXTURE and not (OUT.parent / TEXTURE).exists():
    print("TEXTURE missing (paint it with jaw_texture.py, then run this again):", OUT.parent / TEXTURE)
    TEXTURE = None
if TEXTURE:
    mat = bpy.data.materials.new("JawPlate")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    img = bpy.data.images.load(str(OUT.parent / TEXTURE))
    img.name = Path(TEXTURE).stem
    tn = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tn.image = img
    mat.node_tree.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.6
    bsdf.inputs["Roughness"].default_value = 0.55
    mesh.materials.append(mat)
# Strapped to the jaw: the head carries it whole.
vg = plate.vertex_groups.new(name=MX + "Head")
vg.add(list(range(len(mesh.vertices))), 1.0, "REPLACE")
plate.parent = rig
plate.modifiers.new("Armature", "ARMATURE").object = rig
print("PLATE verts", len(mesh.vertices), "faces", len(mesh.polygons),
      "tris", sum(len(p.vertices) - 2 for p in mesh.polygons), "rivets", len(riv_pts))

# 7. Clearance report: inner surface to the skin, and to the pauldrons and straps.
dmin = 1.0
for c in range(NC):
    for r in range(NR):
        loc, n, _, dist = every.find_nearest(Vector(inner[c, r]))
        dmin = min(dmin, dist)
print("CLEAR inner->body min %.4f" % dmin)
xs = outer[..., 0]
print("EXTENT x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f" % (xs.min(), xs.max(), outer[..., 1].min(), outer[..., 1].max(),
                                                    outer[..., 2].min(), outer[..., 2].max()))
if GRID:
    np.savez(GRID, inner=inner, outer=outer, cols=cols, ts=ts, nrm=nrm)
rig.data.pose_position = "POSE"
bpy.ops.wm.save_as_mainfile(filepath=str(OUT), relative_remap=True)
print("SAVED", OUT)
