"""Close-up of one frame from the battle camera, with and without the cape, to see what the
cape hides or lets through.

  CLIP=walk F=5 YAW=-45 ORTHO=0.9 CAPE_CACHE=<dir> blender -b spearman_rig.blend --python cape_peek.py -- <out dir>

Writes <out>/with.png and <out>/without.png. YAW turns the rig (45 / -45 / 135 / -135 are the
four facings, as in cape_poke.py); ORTHO is the orthographic scale.
"""
import bpy, math, sys, os
from mathutils import Vector, Euler

out = sys.argv[sys.argv.index("--") + 1]; CLIP = os.environ.get("CLIP", "walk"); F = int(os.environ.get("F", "1")); YAW = float(os.environ.get("YAW", "-135"))
sc = bpy.context.scene; rig = bpy.data.objects["SpearmanRig"]; cape = bpy.data.objects["Cape"]
rig.animation_data.action = bpy.data.actions[CLIP]
sp = bpy.data.objects.get("Spear")
if sp:
    sp.animation_data_create(); sp.animation_data.action = bpy.data.actions.get(CLIP + "__spear")
for m in cape.modifiers:
    if m.type in ("ARMATURE", "CLOTH"): m.show_viewport = m.show_render = False
mc = cape.modifiers.new("CapeCache", "MESH_CACHE"); cape.modifiers.move(cape.modifiers.find(mc.name), 0)
mc.cache_format = "PC2"; mc.filepath = os.path.join(os.environ["CAPE_CACHE"], CLIP + ".pc2"); mc.play_mode = "SCENE"; mc.time_mode = "FRAME"; mc.frame_start = 1.0
mc.forward_axis, mc.up_axis = "POS_Y", "POS_Z"
for o in bpy.data.objects:
    if o.name.startswith("Cape") and o is not cape: o.hide_render = True
rig.rotation_euler = Euler((0, 0, math.radians(YAW)))
sc.frame_set(F)
sc.render.engine = "BLENDER_WORKBENCH"; sh = sc.display.shading; sh.light = "FLAT"; sh.color_type = "TEXTURE"
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.85, 0.85, 0.85)
sc.render.resolution_x, sc.render.resolution_y = 600, 600
cd = bpy.data.cameras.new("c"); cd.type = "ORTHO"; cd.ortho_scale = float(os.environ.get("ORTHO", "0.9"))
cam = bpy.data.objects.new("c", cd); sc.collection.objects.link(cam); sc.camera = cam
e = math.radians(30); d = Vector((0, -math.cos(e), math.sin(e)))
cam.location = Vector((0, 0, 1.05)) + d * 10; cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
sc.render.filepath = f"{out}/with.png"; bpy.ops.render.render(write_still=True)
cape.hide_render = True
sc.render.filepath = f"{out}/without.png"; bpy.ops.render.render(write_still=True)
print("PEEK_DONE")
