"""Build the collie Royal Guard's base scene from the Tripo exports (background Blender).

  blender -b --factory-startup --python build_collie.py -- <tripo dir> <out.blend> [preview_dir]

<tripo dir> is references/characters/tripo/collie_guard: the textured zips
{body,tail,sword,shield}_textured__take-01.zip (Smart Mesh, 4K base colour). Run with
BLENDER_USER_RESOURCES pointing at a scratch folder (knowledge/tripo-studio.md).

1. Unpacks each zip into a temporary folder and imports it; the base colours are packed
   into the .blend.
2. Ears. Tripo modelled the folded tips of the ears as blades running forward from the
   crown, past the muzzle (14 cm in Tripo's 1 m figure): from the front they read as
   folded ears, from the side and from above as goat horns. Each blade, the part ahead of
   EAR_Y0 and above the skull (EAR_ZCUT, rising towards the crown, where the blade and
   the side of the head meet), is pressed back towards the crown to EAR_K of its length.
   Pressed, the blade's upturned tip hooked up like a horn, so the pressed part is then
   bent down over the crown (EAR_FOLD at the tip, evenly along it, about an axis across
   the head at EAR_HINGE_Z), the way a collie's ear tip folds forward. From the front the
   ears keep their place and outline, the tips a little lower.
3. The shield is thinned to SHIELD_DEPTH of Tripo's depth (13 cm on a 1 m shield). Its
   field, with the eagle, lay deep behind the rim (the rim stood 4 cm proud of it on the
   0.92 m shield): the field and the rim's inner wall are brought forward to SHIELD_FIELD
   of their depth behind the rim's face; the outer wall and the rivets stay. Tripo left
   the back open, the field a single sheet whose back showed the eagle mirrored; the
   opening, the outer wall's back edge, is closed with a flat plate in the outer wall's
   brown.
4. The body is scaled so the top of the skull (the ears not counted) stands at H, the
   Mixamo skeleton's head top as for the footman, feet at z = 0, centred, facing -Y.
   The tail, sword and shield are scaled to their sizes and parked beside him;
   rig_collie.py fits them.
5. Ear flaps. Folded, each ear still reached out and forward to beside his eyes: seen
   from the game's camera, long hanging flaps, rabbit's ears rather than a collie's. Each
   flap is drawn in towards TRIM_C, the top of the ear: the part within TRIM_G (along
   the surface) of its tip, the outermost point ahead of the ear, moves 1 - TRIM_K of
   the way at the tip and smoothly less towards TRIM_G. The ears end over his brows,
   short and folded, as in the concept.
Saves the .blend; preview_dir gets front, side and three-quarter renders.
"""
import heapq
import math
import sys
import tempfile
import zipfile
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

H = 1.82                 # top of the skull (m), the Mixamo head top
EAR_Y0 = -0.03           # Tripo units: the blade is pressed back towards this depth
EAR_ZCUT = ((-0.03, 0.968), (-0.06, 0.95), (-0.09, 0.935))   # (y, z): above it, ear
EAR_XMIN = 0.03          # the ears lie outside this
EAR_K = 0.32             # how much of the blade's length ahead of EAR_Y0 is kept
EAR_FOLD = 55            # the pressed blade bent down, degrees at the tip
EAR_HINGE_Z = 0.975      # Tripo units: the bend's axis runs across the crown at this height
SHIELD_DEPTH = 0.5
SHIELD_FIELD = 0.4       # the field's depth behind the rim's face kept
TRIM_C = (0.09, 0.0, 1.85)   # m: the top of his left ear (mirrored for the right)
TRIM_G = 0.13            # m along the surface from the tip: how much of the flap is drawn in
TRIM_K = 0.35            # the tip's distance from TRIM_C kept
ITEMS = {                # largest dimension (m) and where to park it
    "tail": (0.80, (0.0, 0.9, 0.6)),
    "sword": (1.0, (0.9, 0.0, 0.5)),
    "shield": (0.92, (-0.9, 0.0, 0.5)),
}

argv = sys.argv[sys.argv.index("--") + 1:]
tripo, out_blend = Path(argv[0]), Path(argv[1])
preview = Path(argv[2]) if len(argv) > 2 else None

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.unit_settings.system = "METRIC"
tmp = Path(tempfile.mkdtemp(prefix="collie_tripo_"))


def import_part(part, name):
    src = tripo / f"{part}_textured__take-01.zip"
    dest = tmp / part
    with zipfile.ZipFile(src) as z:
        for n in z.namelist():
            if n.startswith(("/", "\\")) or ".." in Path(n).parts or ":" in n:
                raise SystemExit(f"unsafe entry {n} in {src}")
        z.extractall(dest)
    fbx = next(dest.glob("*.fbx"))
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(fbx))
    new = [o for o in bpy.data.objects if o not in before]
    ob = next(o for o in new if o.type == "MESH")
    for o in new:
        if o is not ob:
            bpy.data.objects.remove(o)
    ob.name = ob.data.name = name
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    ob.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for slot in ob.material_slots:
        if slot.material:
            slot.material.name = f"{name}_mat"
    return ob


body = import_part("body", "Collie")
parts = {k: import_part(k, k.capitalize()) for k in ITEMS}


# 2. Ears ------------------------------------------------------------------------------
def zcut(y):
    ys = [p[0] for p in EAR_ZCUT][::-1]
    zs = [p[1] for p in EAR_ZCUT][::-1]
    return float(np.interp(y, ys, zs))


me = body.data
bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
# The head's own part: the loose piece that reaches highest at the middle of the face.
isl = [-1] * len(bm.verts)
k = 0
for v in bm.verts:
    if isl[v.index] >= 0:
        continue
    st = [v]
    isl[v.index] = k
    while st:
        x = st.pop()
        for e in x.link_edges:
            w = e.other_vert(x)
            if isl[w.index] < 0:
                isl[w.index] = k
                st.append(w)
    k += 1
bm.free()
head = isl[max(range(len(me.vertices)), key=lambda i: me.vertices[i].co.z if abs(me.vertices[i].co.x) < 0.01 else -1)]
ear = [i for i, v in enumerate(me.vertices)
       if isl[i] == head and v.co.y < EAR_Y0 and abs(v.co.x) > EAR_XMIN and v.co.z > zcut(v.co.y)]
tip_before = min(me.vertices[i].co.y for i in ear)
d_tip = (EAR_Y0 - tip_before) * EAR_K
kappa = math.radians(EAR_FOLD) / d_tip if EAR_FOLD > 0 else 0.0
for i in ear:
    co = me.vertices[i].co
    d = (EAR_Y0 - co.y) * EAR_K          # pressed: its distance ahead of the hinge
    h = co.z - EAR_HINGE_Z
    if kappa:
        r = 1.0 / kappa                  # bend about a centre r below the hinge
        phi = d * kappa
        co.y = EAR_Y0 - (r + h) * math.sin(phi)
        co.z = EAR_HINGE_Z - r + (r + h) * math.cos(phi)
    else:
        co.y = EAR_Y0 - d
me.update()
skull = [v.co.z for i, v in enumerate(me.vertices) if isl[i] == head and abs(v.co.x) < 0.02]
print("BUILD_EARS vertices", len(ear), "tip y %.3f -> %.3f" % (tip_before, min(me.vertices[i].co.y for i in ear)),
      "muzzle y %.3f" % min(v.co.y for i, v in enumerate(me.vertices) if isl[i] == head and abs(v.co.x) < 0.02))

# 3. Shield ---------------------------------------------------------------------------
sh = parts["shield"].data
sh.transform(Matrix.Diagonal((1.0, SHIELD_DEPTH, 1.0, 1.0)))
bm = bmesh.new()
bm.from_mesh(sh)
piece = {}                                 # loose parts: the shield's body and its rivets
for v in bm.verts:
    if v in piece:
        continue
    piece[v] = v.index
    st = [v]
    while st:
        x = st.pop()
        for e in x.link_edges:
            w = e.other_vert(x)
            if w not in piece:
                piece[w] = v.index
                st.append(w)
count = {}
for v, k in piece.items():
    count[k] = count.get(k, 0) + 1
main = max(count, key=count.get)
back = [e for e in bm.edges if e.is_boundary and piece[e.verts[0]] == main]    # the outer wall's back edge
outline = [(e.verts[0].co.xz, e.verts[1].co.xz) for e in back]
width = max(v.co.x for v in bm.verts) - min(v.co.x for v in bm.verts)


def to_outline(p):
    best = 1e9
    for a, b in outline:
        ab = b - a
        t = 0.0 if ab.length_squared == 0 else min(1.0, max(0.0, (p - a).dot(ab) / ab.length_squared))
        best = min(best, (p - (a + ab * t)).length)
    return best


inner = [v for v in bm.verts if piece[v] == main and to_outline(v.co.xz) > 0.02 * width]   # not the outer wall
face_y = min(v.co.y for v in bm.verts if piece[v] == main)            # the rim's face
field_y = max(v.co.y for v in inner)                                   # the field, deepest
for v in inner:
    v.co.y = face_y + (v.co.y - face_y) * SHIELD_FIELD
wall = max((e.link_faces[0] for e in back), key=lambda f: f.calc_area())
uv = bm.loops.layers.uv.active
brown = sum((lp[uv].uv for lp in wall.loops), Vector((0, 0))) / len(wall.loops)
plate = bmesh.ops.holes_fill(bm, edges=back, sides=0)["faces"]
plate = bmesh.ops.triangulate(bm, faces=plate, quad_method="BEAUTY", ngon_method="BEAUTY")["faces"]
bm.normal_update()
if sum(f.normal.y * f.calc_area() for f in plate) < 0:
    bmesh.ops.reverse_faces(bm, faces=plate)
for f in plate:
    for lp in f.loops:
        lp[uv].uv = brown
bm.to_mesh(sh)
bm.free()
print("BUILD_SHIELD field %.3f -> %.3f behind the rim's face (Tripo units), back closed with %d triangles, %d rivets"
      % (field_y - face_y, (field_y - face_y) * SHIELD_FIELD, len(plate), len(count) - 1))

# 4. Scale ----------------------------------------------------------------------------
V = np.array([v.co[:] for v in me.vertices])
skull_top = max(skull)
k = H / (skull_top - V[:, 2].min())
me.transform(Matrix.Translation((-np.median(V[:, 0]), -np.median(V[:, 1]), -V[:, 2].min())))
me.transform(Matrix.Scale(k, 4))
V = np.array([v.co[:] for v in me.vertices])
print("BUILD_BODY skull top %.3f (Tripo units), scale %.3f, height with ears %.3f m, width %.3f, depth %.3f"
      % (skull_top, k, V[:, 2].max(), np.ptp(V[:, 0]), np.ptp(V[:, 1])))

# 5. Ear flaps --------------------------------------------------------------------------
vs = me.vertices
near = {}
for e in me.edges:
    a, b = e.vertices
    if isl[a] == head:
        near.setdefault(a, []).append(b)
        near.setdefault(b, []).append(a)
for s in (1, -1):
    tip = max((i for i in near if vs[i].co.z > 1.75 and vs[i].co.x * s > 0),
              key=lambda i: vs[i].co.x * s - vs[i].co.y)
    dist, todo = {tip: 0.0}, [(0.0, tip)]
    while todo:                          # along the surface from the tip, out to TRIM_G
        d, i = heapq.heappop(todo)
        if d > dist[i]:
            continue
        for j in near[i]:
            dj = d + (vs[i].co - vs[j].co).length
            if dj <= TRIM_G and dj < dist.get(j, TRIM_G + 1):
                dist[j] = dj
                heapq.heappush(todo, (dj, j))
    c = Vector((TRIM_C[0] * s, TRIM_C[1], TRIM_C[2]))
    before = vs[tip].co.copy()
    moved = {}
    for i, d in dist.items():
        t = 1 - d / TRIM_G
        moved[i] = vs[i].co + (c - vs[i].co) * (t * t * (3 - 2 * t) * (1 - TRIM_K))
    for i, p in moved.items():
        vs[i].co = p
    print("BUILD_EAR_TRIM", "left" if s > 0 else "right", len(dist), "vertices, tip",
          tuple(round(v, 3) for v in before), "->", tuple(round(v, 3) for v in vs[tip].co))
me.update()
for name, (size, park) in ITEMS.items():
    ob = parts[name]
    pv = np.array([v.co[:] for v in ob.data.vertices])
    lo, hi = pv.min(0), pv.max(0)
    ob.data.transform(Matrix.Translation(Vector(-(lo + hi) / 2)))
    ob.data.transform(Matrix.Scale(size / max(hi - lo), 4))
    ob.location = park
    print("BUILD_PART", name, "size %.2f m" % size, "verts", len(ob.data.vertices))

bpy.ops.file.pack_all()
# The scene is public: the packed images go under their own file names instead of the
# temp folder they were imported from, and the factory Shading workspace's file
# browser (the user's Documents folder) goes.
for img in bpy.data.images:
    if img.packed_file:
        data = img.packed_file.data
        img.unpack(method="REMOVE")
        img.filepath_raw = "//" + Path(img.filepath_raw.replace("\\", "/")).name
        img.pack(data=data, data_len=len(data))
bpy.data.batch_remove([w for w in bpy.data.workspaces
                       if any(sp.type == "FILE_BROWSER" for s in w.screens for a in s.areas for sp in a.spaces)])
out_blend.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend), compress=True)
print("BUILD_SAVED", out_blend)

if preview:
    preview.mkdir(parents=True, exist_ok=True)
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_object_outline = True
    sc.render.resolution_x, sc.render.resolution_y = 800, 1000
    sc.world = bpy.data.worlds.new("Preview")
    sc.world.color = (0.18, 0.18, 0.2)
    cam_d = bpy.data.cameras.new("Preview")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = 2.3
    cam = bpy.data.objects.new("Preview", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    for view, d in (("front", (0, -1, 0)), ("side", (1, 0, 0)), ("q", (0.7, -0.7, 0.3)), ("head", (0.8, -0.5, 0.25))):
        d = Vector(d).normalized()
        x = Vector((0, 0, 1)).cross(d).normalized()
        y = d.cross(x)
        c = Vector((0, 0, 1.62 if view == "head" else 0.95))
        cam_d.ortho_scale = 0.6 if view == "head" else 2.3
        cam.matrix_world = Matrix((x, y, d)).transposed().to_4x4()
        cam.location = c + d * 5
        sc.render.filepath = str(preview / f"base_{view}.png")
        bpy.ops.render.render(write_still=True)
    print("BUILD_PREVIEW", preview)
