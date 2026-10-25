"""Build the goblin rabble base scene from the Tripo exports (run in a background Blender).

  blender -b --factory-startup --python build_rabble.py -- <tripo dir> <out.blend>

1. Imports the textured body and the five props from `<model>__take-01.zip` in
   the Tripo dir and copies each base colour to `textures/` next to the .blend.
2. Scales the body to H (1.26 m), feet on the ground, centred, facing -Y like
   the Mixamo clips.
3. Re-hangs the collar chain. Tripo modelled its seven links rigid, sticking
   out forward and down at about 50 degrees. They are turned about the top
   link to hang straight down, and any link that would sink into the chest or
   the collar is moved out in front of it. The links get the vertex group
   `Chain`.
4. Scales each prop to its length and puts its origin at the grip (weapons) or
   at the middle of the back (shields): long axis Z, front facing -Y as in the
   Tripo front view. The props stand beside the body in a `Props` collection.
"""
import math
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

# Height of a rabble goblin: the footman's 1.82 m times the battle view's figure
# heights, 34 px for the rabble against 49 for a man (squad_view.gd).
H = 1.26
# Prop lengths in metres along the long axis (shields: height), read off concept B
# against the goblin's height and kept chunky like the footman's sword and kite.
PROPS = {
    "knife": ("Knife", 0.46),
    "hatchet": ("Hatchet", 0.50),
    "cleaver": ("Cleaver", 0.44),
    "shield_barrel": ("ShieldBarrel", 0.50),
    "shield_plank": ("ShieldPlank", 0.64),
}
GAP = 0.004  # chain links clear the chest and the collar by 4 mm

argv = sys.argv[sys.argv.index("--") + 1:]
tripo, out_blend = Path(argv[0]), Path(argv[1]).resolve()
tex_dir = out_blend.parent / "textures"
tex_dir.mkdir(parents=True, exist_ok=True)
unzip = Path(tempfile.mkdtemp(prefix="rabble_"))

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.unit_settings.system = "METRIC"


def import_model(asset, name):
    """Import `<asset>__take-01.zip`; return the mesh with its transforms applied."""
    folder = unzip / asset
    with zipfile.ZipFile(tripo / f"{asset}__take-01.zip") as z:
        z.extractall(folder)
    fbx = next(folder.glob("*.fbx"))
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(fbx))
    new = [o for o in bpy.data.objects if o not in before]
    obj = next(o for o in new if o.type == "MESH")
    for o in new:
        if o is not obj:
            bpy.data.objects.remove(o)
    obj.name = obj.data.name = name
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mat = obj.data.materials[0]
    mat.name = name
    for node in mat.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image:
            src = Path(bpy.path.abspath(node.image.filepath))
            dst = tex_dir / f"goblin_rabble_{asset}_basecolor{src.suffix}"
            shutil.copyfile(src, dst)
            node.image.name = dst.stem
            node.image.filepath = str(dst)
            node.image.reload()
    return obj


def verts(obj):
    return np.array([v.co[:] for v in obj.data.vertices])


def islands(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    seen, out = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, part = [v], []
        while stack:
            w = stack.pop()
            if w.index in seen:
                continue
            seen.add(w.index)
            part.append(w.index)
            stack.extend(e.other_vert(w) for e in w.link_edges)
        out.append(part)
    bm.free()
    return out


# --- Body -------------------------------------------------------------------
body = import_model("body", "GoblinRabble")
V = verts(body)
k = H / (V[:, 2].max() - V[:, 2].min())
body.data.transform(Matrix.Translation((-np.median(V[:, 0]), -np.median(V[:, 1]), -V[:, 2].min())))
body.data.transform(Matrix.Scale(k, 4))
V = verts(body)

# --- Chain ------------------------------------------------------------------
# The links: small islands on the centre line, in front of the neck, between
# the collar and the chest.
links = []
for part in islands(body):
    P = V[part]
    lo, hi = P.min(0), P.max(0)
    if len(part) < 80 and hi[0] - lo[0] < 0.05 and abs(P[:, 0].mean()) < 0.02 \
            and hi[1] < -0.01 and lo[2] > 0.60 * H and hi[2] < 0.78 * H:
        links.append(part)
links.sort(key=lambda p: -V[p, 2].max())  # top link first
assert len(links) >= 5, f"expected the chain's links, found {len(links)}"
chain = sorted(i for p in links for i in p)
top = links[0]
pivot = Vector(V[top][np.argmax(V[top, 2])])
pivot.x = 0.0
axis = Vector(V[links[-1]].mean(0)) - Vector(V[top].mean(0))
axis.x = 0.0
tilt = math.degrees(axis.angle(Vector((0, 0, -1))))
rot = axis.rotation_difference(Vector((0, 0, -1))).to_matrix()
for i in chain:
    v = body.data.vertices[i]
    v.co = pivot + rot @ (v.co - pivot)

# Clear the chest and the collar: cast from in front of each link vertex back
# toward the body (+Y) and move the link forward to GAP in front of the hit.
others = [p for p in body.data.polygons if not any(i in set(chain) for i in p.vertices)]
tree = BVHTree.FromPolygons([v.co.copy() for v in body.data.vertices], [list(p.vertices) for p in others])
pushes = []
for n, part in enumerate(links):
    need = 0.0
    if n > 0:  # the top link passes through the collar's ring
        for i in part:
            co = body.data.vertices[i].co
            hit = tree.ray_cast(Vector((co.x, co.y - 0.5, co.z)), Vector((0, 1, 0)), 0.6)
            if hit[0] is not None:
                need = max(need, co.y - (hit[0].y - GAP))
    # A hanging chain rests on the link above it: never further back than that one.
    need = max(need, pushes[-1] if pushes else 0.0)
    pushes.append(need)
    for i in part:
        body.data.vertices[i].co.y -= need
vg = body.vertex_groups.new(name="Chain")
vg.add(chain, 1.0, "REPLACE")
CV = np.array([body.data.vertices[i].co[:] for i in chain])
print("RABBLE_CHAIN links", len(links), "tilt was", round(tilt, 1), "deg; pushes (mm)",
      [round(p * 1000, 1) for p in pushes], "now z", round(CV[:, 2].min(), 3), "-", round(CV[:, 2].max(), 3),
      "y", round(CV[:, 1].min(), 3), "-", round(CV[:, 1].max(), 3))


# --- Props ------------------------------------------------------------------
def width_profile(P, length, n=200):
    zs = np.linspace(0, length, n)
    w = np.array([np.ptp(P[np.abs(P[:, 2] - z) < length / n, 0]) if (np.abs(P[:, 2] - z) < length / n).any() else 0.0
                  for z in zs])
    return zs, w


col = bpy.data.collections.new("Props")
sc.collection.children.link(col)
x_at = 0.95
for asset, (name, length) in PROPS.items():
    obj = import_model(asset, name)
    P = verts(obj)
    s = length / (P[:, 2].max() - P[:, 2].min())
    obj.data.transform(Matrix.Translation((-(P[:, 0].min() + P[:, 0].max()) / 2,
                                           -(P[:, 1].min() + P[:, 1].max()) / 2, -P[:, 2].min())))
    obj.data.transform(Matrix.Scale(s, 4))
    P = verts(obj)
    zs, w = width_profile(P, length)
    if asset == "knife":
        # Guard: the widest slice in the lower half; the grip halfway between it and the pommel.
        lower = zs < 0.5 * length
        guard = float(zs[lower][np.argmax(w[lower])])
        origin = Vector((0, 0, guard * 0.5))
    elif asset == "cleaver":
        # The blade starts where the width first passes 60% of the widest; the grip is halfway below.
        blade = float(zs[np.argmax(w > 0.6 * w.max())])
        origin = Vector((0, 0, blade * 0.5))
    elif asset == "hatchet":
        # Held low on the haft, at the middle of its leather wrap.
        origin = Vector((0, 0, 0.17 * length))
    else:
        # Shields: the middle of the back, where the arm and the grip go.
        tree_p = BVHTree.FromPolygons([v.co.copy() for v in obj.data.vertices],
                                      [list(p.vertices) for p in obj.data.polygons])
        hit = tree_p.ray_cast(Vector((0, 1.0, length / 2)), Vector((0, -1, 0)), 2.0)
        origin = Vector((0, hit[0].y if hit[0] else float(P[:, 1].max()), length / 2))
    obj.data.transform(Matrix.Translation(-origin))
    for c in obj.users_collection:
        c.objects.unlink(obj)
    col.objects.link(obj)
    P = verts(obj)
    obj.location = (x_at + (P[:, 0].max() - P[:, 0].min()) / 2, 0.0, -P[:, 2].min())
    x_at += (P[:, 0].max() - P[:, 0].min()) + 0.12
    print("RABBLE_PROP", name, "length", length, "width", round(float(np.ptp(P[:, 0])), 3),
          "depth", round(float(np.ptp(P[:, 1])), 3), "origin above the bottom", round(float(-P[:, 2].min()), 3))

bpy.ops.file.make_paths_relative()
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend), relative_remap=True)
shutil.rmtree(unzip, ignore_errors=True)
print("RABBLE_SAVED", out_blend)
