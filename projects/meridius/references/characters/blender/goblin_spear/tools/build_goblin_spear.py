"""Build the goblin spearman base scene from the Tripo exports (run in a background Blender).

  blender -b --factory-startup --python build_goblin_spear.py -- <tripo dir> <out.blend>

1. Imports the textured body and the spear from `<model>__take-01.zip` in the
   Tripo dir and copies each base colour to `textures/` next to the .blend.
2. Scales the body to H (1.486 m to the top of his head), feet on the ground,
   facing -Y like the Mixamo clips, centred on his mirror plane (Tripo's model is a
   few centimetres off it) and on the middle of his pelvis front to back.
3. Scales the spear to LENGTH, long axis Z with the head up, the leaf's flat face
   toward -Y as in the Tripo front view, and thins the shaft below the red rag to
   SHAFT_D so a goblin's hand closes round it (the butt cap and the leather grip
   are thinned with it; the rag, the socket and the head keep Tripo's size). Its
   origin is on the shaft's axis at the middle of the leather grip. It stands
   beside the body in a `Props` collection.
"""
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

# Height of a spearman goblin: the footman's 1.82 m times the battle view's figure
# heights, 40 px for a small unit against 49 for a man (squad_view.gd), as for the
# goblin archer.
H = 1.82 * 40 / 49
# The spear, butt to tip: about 1.2 times his height, as in the concept sheet
# (`../../Goblin spearmen.png`, the middle goblin).
LENGTH = 1.80
# Shaft diameter: the human spearman's 4 cm (art/spearman_3d) scaled to the goblin's
# height. Tripo's shaft is 5.5 cm at this length, too thick for his fingers to close.
SHAFT_D = 0.034
# Shares of the spear's length, read off the Tripo mesh's profile (vertex rings per
# slice along its length): the bare shaft, the leather grip and where the red rag
# starts. Below RAG the mesh is shaft, knots, grip and butt cap only.
BARE = (0.08, 0.37)
GRIP = (0.375, 0.52)
RAG = 0.565

argv = sys.argv[sys.argv.index("--") + 1:]
tripo, out_blend = Path(argv[0]), Path(argv[1]).resolve()
tex_dir = out_blend.parent / "textures"
tex_dir.mkdir(parents=True, exist_ok=True)
unzip = Path(tempfile.mkdtemp(prefix="goblin_spear_"))

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
            dst = tex_dir / f"goblin_spear_{asset}_basecolor{src.suffix}"
            shutil.copyfile(src, dst)
            node.image.name = dst.stem
            node.image.filepath = str(dst)
            node.image.reload()
    return obj


def verts(obj):
    return np.array([v.co[:] for v in obj.data.vertices])


def set_verts(obj, P):
    obj.data.vertices.foreach_set("co", P.astype(np.float32).ravel())
    obj.data.update()


def islands(obj):
    """The mesh's separate parts (vertex index lists), largest first."""
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
    return sorted(out, key=len, reverse=True)


def axis_centre(P, z0, z1):
    """Middle of the cross-section between heights z0 and z1 (3rd to 97th percentile)."""
    q = P[(P[:, 2] >= z0) & (P[:, 2] <= z1)]
    return (float((np.percentile(q[:, 0], 3) + np.percentile(q[:, 0], 97)) / 2),
            float((np.percentile(q[:, 1], 3) + np.percentile(q[:, 1], 97)) / 2))


# --- Body -------------------------------------------------------------------
body = import_model("body", "GoblinSpearman")
V = verts(body)
k = H / (V[:, 2].max() - V[:, 2].min())
body.data.transform(Matrix.Translation((-np.median(V[:, 0]), -np.median(V[:, 1]), -V[:, 2].min())))
body.data.transform(Matrix.Scale(k, 4))
V = verts(body)
# Centre him on his mirror plane, which the median misses by a few centimetres: the
# middle of each pair of small mirrored parts (bracer studs, eyes, horns, rivets), the
# median of those. Front to back, centre him on the middle of his pelvis (the cape left
# out), so he turns on the spot.
cents = []
for part in islands(body)[1:]:
    cents.append((len(part), *V[part].mean(0)))
cents = np.array(cents)
mids = [(a[1] + b[1]) / 2 for i, a in enumerate(cents) for b in cents[i + 1:]
        if a[0] == b[0] and abs(a[2] - b[2]) < 0.005 and abs(a[3] - b[3]) < 0.005 and abs(a[1] - b[1]) > 0.02]
assert len(mids) >= 4, f"only {len(mids)} mirrored pairs"
dx = -float(np.median(mids))
pel = V[(np.abs(V[:, 2] - 0.42 * H) < 0.03) & (np.abs(V[:, 0] + dx) < 0.12) & (V[:, 1] < 0.18)]
dy = -float((np.percentile(pel[:, 1], 3) + np.percentile(pel[:, 1], 97)) / 2)
body.data.transform(Matrix.Translation((dx, dy, 0)))
V = verts(body)
print("SPEAR_CENTRE %d mirrored pairs, moved x %+.4f (spread %.4f), y %+.4f" % (
    len(mids), dx, float(np.ptp(mids)), dy))
print("SPEAR_BODY height %.3f, x %.3f to %.3f, y %.3f to %.3f, %d vertices, %d faces" % (
    np.ptp(V[:, 2]), V[:, 0].min(), V[:, 0].max(), V[:, 1].min(), V[:, 1].max(),
    len(V), len(body.data.polygons)))

# --- Spear ------------------------------------------------------------------
spear = import_model("spear", "Spear")
P = verts(spear)
L0 = P[:, 2].max() - P[:, 2].min()
P -= (0.0, 0.0, P[:, 2].min())
P *= LENGTH / L0
L = LENGTH
# The shaft's axis, on the bare shaft, where each ring is a plain circle.
x0, y0 = axis_centre(P, BARE[0] * L, BARE[1] * L)
P -= (x0, y0, 0.0)
# Its diameter: the median width of the rings there, 1 cm slices (a knot is one of them).
rings = [P[(P[:, 2] >= z) & (P[:, 2] < z + 0.01)] for z in np.arange(BARE[0] * L, BARE[1] * L, 0.01)]
d0 = float(np.median([np.ptp(q[:, 0]) for q in rings if len(q) >= 6]))
s = SHAFT_D / d0
low = P[:, 2] < RAG * L
P[low, :2] *= s
# The origin: the middle of the leather grip, on the axis.
P -= (0.0, 0.0, (GRIP[0] + GRIP[1]) / 2 * L)
set_verts(spear, P)
head = P[P[:, 2] > (0.79 - (GRIP[0] + GRIP[1]) / 2) * L]
print("SPEAR_PROP length %.3f, shaft %.4f thinned to %.4f (x%.3f), grip at %.3f from the butt, "
      "head %.3f wide and %.3f deep" % (L, d0, SHAFT_D, s, (GRIP[0] + GRIP[1]) / 2 * L,
                                        np.ptp(head[:, 0]), np.ptp(head[:, 1])))
spear["length"] = L
spear["shaft_r"] = SHAFT_D / 2
spear["grip"] = ((GRIP[0] - (GRIP[0] + GRIP[1]) / 2) * L, (GRIP[1] - (GRIP[0] + GRIP[1]) / 2) * L)
col = bpy.data.collections.new("Props")
sc.collection.children.link(col)
for c in spear.users_collection:
    c.objects.unlink(spear)
col.objects.link(spear)
spear.location = (0.55, 0.0, -P[:, 2].min())

# Each image's path is a fixed-size buffer too: fill it, then write the path relative
# to the .blend (the textures are next to it), so neither the unzip folder nor the
# absolute path stays behind it.
for img in bpy.data.images:
    if img.filepath_raw:
        rel = "//" + Path(img.filepath_raw).resolve().relative_to(out_blend.parent).as_posix()
        img.filepath_raw = "//" + "_" * 700
        img.filepath_raw = rel
# Every screen's File Browser keeps the folder it last showed (the user's Documents
# folder by default) in a fixed-size buffer: fill it before shortening it, so no
# bytes of the old path stay in the file.
for screen in bpy.data.screens:
    for area in screen.areas:
        for space in area.spaces:
            if space.type == "FILE_BROWSER" and space.params is not None:
                space.params.directory = b"//" + b"_" * 700
                space.params.directory = b"//"
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend), relative_remap=True, compress=True)
shutil.rmtree(unzip, ignore_errors=True)
print("SPEAR_SAVED", out_blend)
