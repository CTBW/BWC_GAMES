"""Where the cape lies relative to his torso in a clip (background Blender), e.g. how he and
the cape end up in the deaths.

  CLIP=death CAPE_CACHE=<dir> FRAMES=40,50,60,72 blender -b spearman_rig.blend --python cape_inspect.py -- <out dir>

Prints per frame: chest facing (rest -Y through Spine2's pose), Spine2 height, cape centroid
height and lowest point, and the cape's offset along the chest normal (negative = behind his
back, as it should be). Renders a level side view and a top view, cape in flat red.
"""
import bpy, math, os, sys
import numpy as np
from mathutils import Vector, Euler
from pathlib import Path

out = Path(sys.argv[sys.argv.index("--") + 1]); out.mkdir(parents=True, exist_ok=True)
CLIP = os.environ.get("CLIP", "death")
FRAMES = [int(f) for f in os.environ.get("FRAMES", "1").split(",")]
sc = bpy.context.scene
rig = bpy.data.objects["SpearmanRig"]; cape = bpy.data.objects["Cape"]
rig.animation_data.action = bpy.data.actions[CLIP]
sp = bpy.data.objects.get("Spear")
if sp:
    sp.animation_data_create(); sp.animation_data.action = bpy.data.actions.get(CLIP + "__spear")
for m in cape.modifiers:
    if m.type in ("ARMATURE", "CLOTH", "SURFACE_DEFORM"): m.show_viewport = m.show_render = False
mc = cape.modifiers.new("CapeCache", "MESH_CACHE"); cape.modifiers.move(cape.modifiers.find(mc.name), 0)
mc.cache_format = "PC2"; mc.filepath = os.path.join(os.environ["CAPE_CACHE"], CLIP + ".pc2")
mc.play_mode = "SCENE"; mc.time_mode = "FRAME"; mc.frame_start = 1.0
mc.forward_axis, mc.up_axis = "POS_Y", "POS_Z"
for o in bpy.data.objects:
    if o.name.startswith("Cape") and o is not cape: o.hide_render = True

sc.render.engine = "BLENDER_WORKBENCH"; sh = sc.display.shading
sh.light = "STUDIO"; sh.color_type = "OBJECT"; sh.show_object_outline = True
for o in bpy.data.objects:
    o.color = (0.85, 0.12, 0.12, 1) if o is cape else (0.75, 0.75, 0.72, 1)
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.95, 0.95, 0.95)
sc.render.resolution_x, sc.render.resolution_y = 520, 400
cd = bpy.data.cameras.new("c"); cd.type = "ORTHO"; cd.ortho_scale = 2.4
cam = bpy.data.objects.new("c", cd); sc.collection.objects.link(cam); sc.camera = cam

pb = rig.pose.bones["mixamorig:Spine2"]
for f in FRAMES:
    sc.frame_set(f)
    M = rig.matrix_world @ pb.matrix
    fwd = (M.to_3x3() @ (pb.bone.matrix_local.to_3x3().inverted() @ Vector((0, -1, 0)))).normalized()
    chest = M.translation
    dg = bpy.context.evaluated_depsgraph_get()
    ev = cape.evaluated_get(dg)
    P = np.array([(cape.matrix_world @ v.co)[:] for v in ev.data.vertices])
    c = P.mean(axis=0)
    off = (P - np.array(chest[:])) @ np.array(fwd[:])
    print("INSPECT %s f%d chest-facing (%.2f %.2f %.2f) spine2 z %.2f | cape centroid z %.2f lowest %.2f | along chest normal: median %.2f, %d%% in front" %
          (CLIP, f, fwd.x, fwd.y, fwd.z, chest.z, c[2], P[:, 2].min(), np.median(off), 100 * (off > 0.02).mean()))
    side = Vector((fwd.y, -fwd.x, 0)).normalized() if abs(fwd.z) < 0.95 else Vector((1, 0, 0))
    tgt = Vector((chest.x, chest.y, 0.35))
    for tag, d in (("side", side), ("top", Vector((0, 0, 1)))):
        cam.location = tgt + d * 10
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y" if tag == "side" else "Y").to_euler()
        sc.render.filepath = str(out / f"{CLIP}_{f:03d}_{tag}.png"); bpy.ops.render.render(write_still=True)
print("INSPECT_DONE")
