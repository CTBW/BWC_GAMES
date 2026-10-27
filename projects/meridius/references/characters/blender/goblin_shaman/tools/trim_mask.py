"""Trim the goblin shaman's Tripo skull mask to a face plate (run in a background Blender).

  blender -b --factory-startup --python trim_mask.py -- <tripo dir> <out.blend>

Tripo built the horned mask as a whole skull shell open underneath, with a strap band
round the head and a dark brown back it had to invent, because the input image
(`../../goblin_shaman/mask_horned_front.png`) shows only the front. The user asked for
a face plate on 26 October 2026.

1. Imports `mask__take-01.zip` from the Tripo dir and copies its base colour to
   `textures/` next to the .blend.
2. Cuts the shell with a vertical plane KEEP of its depth behind the front (-Y) and
   deletes everything behind it: the cranium, the back and the strap band with its
   pegs. The user asked on 26 October 2026 for the cut just behind the horns: their
   bases end 0.30-0.32 of the depth from the front and the strap begins at 0.35 (read
   off side and top views of the shell with candidate planes).
3. Closes each cut loop with its own cap facing back (+Y), so the plate is solid. The
   shell is thick, so its section is one horseshoe-shaped loop; any part that pierces
   the shell, such as the strap pegs of an earlier, deeper cut, leaves a small loop
   that overlaps it, which is why the loops are filled one at a time. Each cap triangle
   takes one flat colour, the UV centre of the nearest outside face on the cut, so the
   rim shows bone without streaks across the texture atlas.
The plate stays in Tripo's frame (front -Y, Z up); the character build scales it.
"""
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

# Share of the shell's front-to-back depth kept, measured from the front: just behind
# the horn bases, 0.013 in Tripo's units (the mask is 1 high) behind the nearer one.
KEEP = 0.33

argv = sys.argv[sys.argv.index("--") + 1:]
tripo, out_blend = Path(argv[0]), Path(argv[1]).resolve()
tex_dir = out_blend.parent / "textures"
tex_dir.mkdir(parents=True, exist_ok=True)
unzip = Path(tempfile.mkdtemp(prefix="goblin_shaman_mask_"))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.unit_settings.system = "METRIC"

with zipfile.ZipFile(tripo / "mask__take-01.zip") as z:
    z.extractall(unzip)
fbx = next(unzip.glob("*.fbx"))
before = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=str(fbx))
new = [o for o in bpy.data.objects if o not in before]
obj = next(o for o in new if o.type == "MESH")
for o in new:
    if o is not obj:
        bpy.data.objects.remove(o)
obj.name = obj.data.name = "MaskPlate"
bpy.ops.object.select_all(action="DESELECT")
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mat = obj.data.materials[0]
mat.name = "MaskPlate"
for node in mat.node_tree.nodes:
    if node.type == "TEX_IMAGE" and node.image:
        src = Path(bpy.path.abspath(node.image.filepath))
        dst = tex_dir / f"goblin_shaman_mask_basecolor{src.suffix}"
        shutil.copyfile(src, dst)
        node.image.filepath = str(dst)
        node.image.name = dst.name
        node.image.reload()

me = obj.data
ys = [v.co.y for v in me.vertices]
y_cut = min(ys) + KEEP * (max(ys) - min(ys))
faces_before = len(me.polygons)

bm = bmesh.new()
bm.from_mesh(me)
uv = bm.loops.layers.uv.active
res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6,
                             plane_co=(0, y_cut, 0), plane_no=(0, 1, 0), clear_outer=True)
cut_edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge) and e.is_valid and e.is_boundary]

# Split the cut into its closed loops.
loops, seen = [], set()
for start in cut_edges:
    if start in seen:
        continue
    loop, stack = [], [start]
    while stack:
        e = stack.pop()
        if e in seen:
            continue
        seen.add(e)
        loop.append(e)
        stack += [n for v in e.verts for n in v.link_edges if n.is_boundary and n not in seen]
    loops.append(loop)
shell = max(loops, key=len)
zs = [v.co.z for e in shell for v in e.verts]
centre = Vector((0, y_cut, (min(zs) + max(zs)) / 2))


def outside(f):
    c = f.calc_center_median()
    return f.normal.dot(Vector((c.x - centre.x, 0, c.z - centre.z))) > 0


def uv_centre(f):
    return sum((l[uv].uv for l in f.loops), Vector((0, 0))) / len(f.loops)


cap_faces = []
for loop in loops:
    ring = {f for e in loop for f in e.link_faces}
    sources = [(f.calc_center_median(), uv_centre(f)) for f in ring if outside(f)] or \
              [(f.calc_center_median(), uv_centre(f)) for f in ring]
    filled = bmesh.ops.triangle_fill(bm, use_beauty=True, use_dissolve=False, edges=loop,
                                     normal=Vector((0, 1, 0)))["geom"]
    for f in (g for g in filled if isinstance(g, bmesh.types.BMFace)):
        f.normal_update()
        if f.normal.y < 0:
            f.normal_flip()
        f.material_index = 0
        f.smooth = False
        c = f.calc_center_median()
        flat = min(sources, key=lambda s: (s[0] - c).length)[1]
        for l in f.loops:
            l[uv].uv = flat
        cap_faces.append(f)
bm.normal_update()
open_edges = sum(1 for e in bm.edges if e.is_boundary)
non_manifold = sum(1 for e in bm.edges if not e.is_manifold and not e.is_boundary)
bm.to_mesh(me)
bm.free()
me.update()

ys = [v.co.y for v in me.vertices]
print("TRIM", {"y_cut": round(y_cut, 4), "faces_before": faces_before, "faces_after": len(me.polygons),
               "cap_faces": len(cap_faces), "cut_edges": len(cut_edges), "cut_loops": len(loops),
               "open_edges": open_edges,
               "non_manifold_edges": non_manifold, "depth_after": round(max(ys) - min(ys), 4)})

# Save once to give the file a home, then store the texture path relative to it.
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend))
bpy.ops.file.make_paths_relative()
bpy.ops.wm.save_mainfile()
shutil.rmtree(unzip, ignore_errors=True)
print("SAVED", out_blend.name)
