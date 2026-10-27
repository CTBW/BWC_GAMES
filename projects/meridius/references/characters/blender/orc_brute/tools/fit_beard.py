"""Fit the Tripo beard to the orc's face (rest pose): one of his squad's faces.

  blender -b orc_brute_faces.blend --python fit_beard.py -- <beard__take-01.zip> <out.blend>

Saves the open scene with the beard, `Beard` (replacing one already there), skinned to the
head and to the skin it lies on, and copies its base colour to `textures/orc_brute_beard_basecolor.jpg` next to the out file.

1. Imports the beard and drops Tripo's stray arc, a thin loose sliver (68 vertices)
   floating in front of the mouth.
2. Sizes it from the bust (face_beard.png): from the sideburns' tops, level with the
   earrings, to the tip of the middle braid it spans 0.36 of the eyes' spacing over
   0.089 m, so its Tripo height of 1 becomes SCALE. Its top centre goes under the lower
   lip; the fit then searches its pitch about that point and the point's depth and height
   against the body's surface: nothing inside the body (skin, pauldrons, straps), and the
   open inner rim, the edge that meets the face along the jaw and up the cheeks, close to
   the skin.
3. Hangs it: the hair below the chin swings back about a hinge under it, the bend growing
   over RAMP, until the nearest braid lies REST_GAP off the chest (the strap ring).
4. Bends it onto the body: a vertex closer than GAP to the body is pushed out along the
   surface's normal, and the push is spread to its neighbours so the hair bends rather
   than dents; the inner rim is drawn in to the skin the same way.
5. Weights: the hair on the face rides the head. Below the chin each vertex takes the
   weights of the skin nearest it, so the braids move with the chest they lie on and the
   beard folds against the chest instead of swinging into it as the head drops. The two
   blend over CHIN, and the weights are smoothed along the hair so it bends, not tears."""
import math
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
ZIP, OUT = Path(argv[0]), Path(argv[1]).resolve()
SCALE = 0.36           # Tripo units to metres (see 2.)
TOP_Z = 1.737          # the beard's top centre: just under the lower lip
GAP = 0.004            # hair to body (m)
RIM_GAP = 0.003        # inner rim to skin (m)
RIM_BELOW = 0.12       # the rim on the face: within this of the top centre (Tripo units)
BRAID_Z = 0.30         # the braids: below this (Tripo units)
REST_GAP = 0.006       # the nearest braid to the chest (m)
HINGE_Z, RAMP = 1.69, 0.06
CHIN = (1.69, 1.73)    # the skin's weights below, all head above
SMOOTH = 4
MX = "mixamorig:"

body = bpy.data.objects["OrcBrute"]
rig = bpy.data.objects["OrcBruteRig"]
rig.data.pose_position = "REST"
bpy.context.view_layer.update()
ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
me = ev.to_mesh()
full = bmesh.new()
full.from_mesh(me)
full.transform(body.matrix_world)
every = BVHTree.FromBMesh(full)


def loose_parts(bm):
    bm.verts.ensure_lookup_table()
    comp = [-1] * len(bm.verts)
    parts = []
    for v in bm.verts:
        if comp[v.index] >= 0:
            continue
        k = len(parts)
        stack = [v]
        comp[v.index] = k
        idx = []
        while stack:
            a = stack.pop()
            idx.append(a.index)
            for e in a.link_edges:
                o = e.other_vert(a)
                if comp[o.index] < 0:
                    comp[o.index] = k
                    stack.append(o)
        parts.append(idx)
    return parts


# The skin alone: drop the loose parts under 1000 vertices (eyes, teeth, tusks, earrings,
# pauldrons, straps).
skin_bm = full.copy()
drop = [i for part in loose_parts(skin_bm) if len(part) < 1000 for i in part]
skin_bm.verts.ensure_lookup_table()
bmesh.ops.delete(skin_bm, geom=[skin_bm.verts[i] for i in drop], context="VERTS")
skin = BVHTree.FromBMesh(skin_bm)

# 1. Import.
if "Beard" in bpy.data.objects:
    bpy.data.objects.remove(bpy.data.objects["Beard"])
folder = Path(tempfile.mkdtemp(prefix="orc_brute_beard_"))
with zipfile.ZipFile(ZIP) as z:
    z.extractall(folder)
before = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=str(next(folder.glob("*.fbx"))))
new = [o for o in bpy.data.objects if o not in before]
beard = next(o for o in new if o.type == "MESH")
for o in new:
    if o is not beard:
        bpy.data.objects.remove(o)
beard.name = beard.data.name = "Beard"
bpy.ops.object.select_all(action="DESELECT")
beard.select_set(True)
bpy.context.view_layer.objects.active = beard
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mat = beard.data.materials[0]
mat.name = "Beard"
tex_dir = OUT.parent / "textures"
for n in mat.node_tree.nodes:
    if n.type == "TEX_IMAGE" and n.image:
        src = Path(bpy.path.abspath(n.image.filepath))
        dst = tex_dir / f"orc_brute_beard_basecolor{src.suffix}"
        shutil.copyfile(src, dst)
        n.image.name = dst.stem
        n.image.filepath = str(dst)
        n.image.reload()
    if n.type == "BSDF_PRINCIPLED":
        n.inputs["Metallic"].default_value = 0.0
        n.inputs["Roughness"].default_value = 0.9

bm = bmesh.new()
bm.from_mesh(beard.data)
stray = []
for part in loose_parts(bm):
    co = np.array([bm.verts[i].co[:] for i in part])
    if len(part) < 100 and np.ptp(co[:, 2]) < 0.03 and np.abs(co[:, 0]).max() < 0.08:
        stray.append(part)
        print("STRAY verts %d x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f" % (
            len(part), co[:, 0].min(), co[:, 0].max(), co[:, 1].min(), co[:, 1].max(), co[:, 2].min(), co[:, 2].max()))
assert len(stray) == 1, stray
bmesh.ops.delete(bm, geom=[bm.verts[i] for i in stray[0]], context="VERTS")
bm.verts.ensure_lookup_table()
bm.to_mesh(beard.data)
N = len(bm.verts)
V0 = np.array([v.co[:] for v in bm.verts])
rim = np.array(sorted({v.index for e in bm.edges if e.is_boundary for v in e.verts}))
nbr = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
bm.free()

# The top centre: the highest point within 2 cm of the middle, at the front.
mid = np.abs(V0[:, 0]) < 0.02
za = V0[mid, 2].max()
A0 = np.array([0.0, V0[mid & (V0[:, 2] > za - 0.02), 1].min(), za])
rim_face = rim[V0[rim, 2] > za - RIM_BELOW]
low = np.nonzero(V0[:, 2] < BRAID_Z)[0]
print("BEARD verts", N, "rim", len(rim), "on the face", len(rim_face), "braids", len(low), "top centre", A0.round(4))


def place(x):
    pitch, ay, az = x
    q = (V0 - A0) * SCALE
    c, s = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    return np.stack([q[:, 0], q[:, 1] * c - q[:, 2] * s + ay, q[:, 1] * s + q[:, 2] * c + az], 1)


def sdist(p, loc, n, d):
    """Signed distance to the nearest surface point: inside only when the point lies behind
    that face, not merely past an open edge of a thin shell (a pauldron's rim)."""
    dot = (p - loc).dot(n)
    return -d if dot < 0 and -dot > 0.5 * d else d


def signed(W, tree=every, idx=None):
    idx = range(len(W)) if idx is None else idx
    out = np.empty(len(idx))
    for k, i in enumerate(idx):
        p = Vector(W[i])
        loc, n, _, d = tree.find_nearest(p)
        out[k] = sdist(p, loc, n, d)
    return out


def cost(x, report=False):
    W = place(x)
    d = signed(W)
    dr = signed(W, skin, rim_face)
    pen = np.sum(np.maximum(0, GAP - d) ** 2)
    far = np.mean(np.maximum(0, dr - RIM_GAP) ** 2)
    rest = (d[low].min() - REST_GAP) ** 2
    c = 50 * pen + 1000 * far + 100 * rest
    if report:
        print("FIT cost %.6f inside %d (deepest %.4f) rim median %.4f max %.4f braids %.4f x %s" % (
            c, int((d < 0).sum()), d.min(), np.median(dr), dr.max(), d[low].min(), np.round(x, 4)))
    return c


# 2. Place: pitch (degrees), then the top centre's depth and height; coordinate descent.
fy = skin.ray_cast(Vector((0, -0.5, TOP_Z)), Vector((0, 1, 0)))[0].y
x = np.array([0.0, fy - 0.004, TOP_Z])
step = np.array([4.0, 0.006, 0.006])
lo = np.array([-30, fy - 0.03, TOP_Z - 0.012])
hi = np.array([30, fy + 0.03, TOP_Z + 0.012])
best = cost(x, True)
for _ in range(5):
    improved = True
    while improved:
        improved = False
        for j in range(3):
            for sgn in (1, -1):
                y = x.copy()
                y[j] = np.clip(y[j] + sgn * step[j], lo[j], hi[j])
                c = cost(y)
                if c < best - 1e-9:
                    best, x, improved = c, y, True
                    break
    step /= 2
cost(x, True)


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


# 3. Hang the hair below the chin on the chest.
W = place(x)
YH = float(np.median(W[np.abs(W[:, 2] - HINGE_Z) < 0.01, 1]))


def hang(W, deg):
    a = np.radians(deg) * smooth((HINGE_Z - W[:, 2]) / RAMP)
    dy, dz = W[:, 1] - YH, W[:, 2] - HINGE_Z
    return np.stack([W[:, 0], YH + dy * np.cos(a) - dz * np.sin(a), HINGE_Z + dy * np.sin(a) + dz * np.cos(a)], 1)


best_deg, best_c = 0.0, None
for deg in np.arange(0, 30.1, 0.5):
    d = signed(hang(W, deg))
    c = (d[low].min() - REST_GAP) ** 2 + 0.2 * np.sum(np.maximum(0, -d[low]) ** 2)
    if best_c is None or c < best_c:
        best_deg, best_c = deg, c
W = hang(W, best_deg)
print("HANG %.1f deg about z %.3f y %.4f, braids %.4f off the body" % (best_deg, HINGE_Z, YH, signed(W)[low].min()))


# 4. Bend onto the body.
def spread(D, rounds=4):
    """Spread per-vertex offsets to the neighbours (each takes 0.8 of its largest
    neighbour's), then smooth them as often."""
    D = D.copy()
    mag = np.linalg.norm(D, axis=1)
    for _ in range(rounds):
        new, nm = D.copy(), mag.copy()
        for i in range(N):
            for j in nbr[i]:
                if mag[j] * 0.8 > nm[i]:
                    nm[i] = mag[j] * 0.8
                    new[i] = D[j] * 0.8
        D, mag = new, nm
    for _ in range(rounds):
        D = np.array([(D[i] + D[nbr[i]].mean(0)) / 2 if nbr[i] else D[i] for i in range(N)])
    return D


for _ in range(8):
    off = np.zeros_like(W)
    for i in range(N):
        p = Vector(W[i])
        loc, n, _, d = every.find_nearest(p)
        sd = sdist(p, loc, n, d)
        if sd < GAP:
            off[i] = np.array(n) * (GAP - sd)
    for i in rim_face:
        p = Vector(W[i])
        loc, n, _, d = skin.find_nearest(p)
        sd = sdist(p, loc, n, d)
        if sd > RIM_GAP:
            off[i] = -np.array(n) * (sd - RIM_GAP) * 0.8
    if not off.any():
        break
    W = W + spread(off)
d = signed(W)
dr = signed(W, skin, rim_face)
print("BENT inside %d, nearest %.4f, under %.1f mm %d; rim to skin median %.4f max %.4f" % (
    int((d < 0).sum()), d.min(), (GAP - 0.001) * 1000, int((d < GAP - 0.001).sum()), np.median(dr), dr.max()))
for i, v in enumerate(beard.data.vertices):
    v.co = W[i]
beard.data.update()
print("EXTENT x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f" % (
    W[:, 0].min(), W[:, 0].max(), W[:, 1].min(), W[:, 1].max(), W[:, 2].min(), W[:, 2].max()))

# 5. Weights: the skin's nearest (its polygon's vertices by inverse distance), the head
# above the chin, smoothed along the hair.
assert len(me.vertices) == len(body.data.vertices)
keep = np.zeros(len(full.verts), bool)
for part in loose_parts(full):
    if len(part) >= 1000:
        keep[part] = True
sk_co = [v.co.copy() for v in full.verts]
polys = [p.vertices[:] for p in me.polygons if keep[p.vertices[0]]]
on_skin = BVHTree.FromPolygons(sk_co, polys)
deform = {b.name for b in rig.data.bones if b.use_deform}
names = [g.name for g in body.vertex_groups]
groups = sorted({names[g.group] for v in body.data.vertices for g in v.groups if names[g.group] in deform})
gi = {n: k for k, n in enumerate(groups)}
BW = np.zeros((len(body.data.vertices), len(groups)))
for v in body.data.vertices:
    for g in v.groups:
        if names[g.group] in gi:
            BW[v.index, gi[names[g.group]]] = g.weight
BW /= np.maximum(BW.sum(1, keepdims=True), 1e-9)
TW = np.zeros((N, len(groups)))
for i in range(N):
    loc, _, fi, _ = on_skin.find_nearest(Vector(W[i]))
    vs = list(polys[fi])
    k = 1 / np.maximum([(sk_co[j] - loc).length for j in vs], 1e-6)
    TW[i] = (BW[vs] * k[:, None]).sum(0) / k.sum()
head = smooth((W[:, 2] - CHIN[0]) / (CHIN[1] - CHIN[0]))
TW *= (1 - head)[:, None]
TW[:, gi[MX + "Head"]] += head
for _ in range(SMOOTH):
    TW = np.array([(TW[i] + TW[nbr[i]].mean(0)) / 2 if nbr[i] else TW[i] for i in range(N)])
TW[TW < 0.01] = 0
TW /= TW.sum(1, keepdims=True)
for name in groups:
    w = TW[:, gi[name]]
    if (w > 0).any():
        vg = beard.vertex_groups.new(name=name)
        for i in np.nonzero(w)[0]:
            vg.add([int(i)], float(w[i]), "REPLACE")
print("WEIGHTS", {g.name.replace(MX, ""): round(float(TW[:, gi[g.name]].sum() / N), 3) for g in beard.vertex_groups})
beard.parent = rig
beard.modifiers.new("Armature", "ARMATURE").object = rig
print("BEARD tris", sum(len(p.vertices) - 2 for p in beard.data.polygons))
rig.data.pose_position = "POSE"
bpy.ops.wm.save_as_mainfile(filepath=str(OUT), relative_remap=True)
print("SAVED", OUT)
