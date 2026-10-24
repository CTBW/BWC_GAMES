"""The three Amberfeld soldiers side by side in their idle poses (background Blender).

  blender -b --factory-startup --python lineup.py -- <out_dir> <footman.blend> <crossbowman.blend> <spearman.blend> [cape_cache dir]

Set BLENDER_USER_RESOURCES to a scratch folder first (see blender_env.sh). Other sessions own
the footman and crossbowman rigs (art/footman_3d/footman_rig.blend,
art/crossbowman_3d/crossbowman_rig.blend): pass copies. With a cape_cache dir the cloth cape
plays its idle.pc2. Writes front.png, back.png and battle_se.png on a transparent background;
lineup_compose.py puts them side by side for the report's img/lineup.webp.
"""
import bpy, math, sys
from pathlib import Path
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out = Path(argv[0]); out.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
units = [("Footman", argv[1], "FootmanRig", -1.25), ("Crossbowman", argv[2], "CrossbowmanRig", 0.0), ("Spearman", argv[3], "SpearmanRig", 1.25)]
for name, path, rig_name, x in units:
    with bpy.data.libraries.load(path, link=False) as (src, dst):
        dst.objects = list(src.objects)
    new = [o for o in dst.objects if o is not None]
    for o in new:
        sc.collection.objects.link(o)
    # The appended rig keeps the action it was saved with; the report's lineup used them as saved.
    rig = next(o for o in new if o.name.startswith(rig_name))
    rig.animation_data_create()
    cape = next((o for o in new if o.type == "MESH" and o.name.startswith("Cape") and "Cloth" in o.modifiers), None)
    if cape and len(argv) > 4:
        # The cloth cape plays its idle cache, as in the clip renders.
        for m in cape.modifiers:
            if m.type in ("ARMATURE", "CLOTH"):
                m.show_viewport = m.show_render = False
        mc = cape.modifiers.new("CapeCache", "MESH_CACHE")
        cape.modifiers.move(cape.modifiers.find(mc.name), 0)
        mc.cache_format = "PC2"; mc.filepath = str(Path(argv[4]) / "idle.pc2")
        mc.play_mode = "SCENE"; mc.time_mode = "FRAME"; mc.frame_start = 1.0
        mc.forward_axis, mc.up_axis = "POS_Y", "POS_Z"
    for o in new:
        if o.name.startswith(("CapeCollider", "CapeGround")):
            o.hide_render = True
    for o in new:
        if o.parent is None:
            o.location.x += x
    print("UNIT", name, [o.name for o in new], "action", rig.animation_data.action.name if rig.animation_data.action else None)
sc.frame_set(1)
for o in sc.objects:
    if o.type == "MESH":
        for m in o.data.materials:
            if m and m.use_nodes:
                ims = [n for n in m.node_tree.nodes if n.type == "TEX_IMAGE"]
                if ims:
                    m.node_tree.nodes.active = ims[0]
sc.render.engine = "BLENDER_WORKBENCH"
sc.render.film_transparent = True   # AgX like the clip sheets; composited onto paper later
sh = sc.display.shading
sh.light = "FLAT"; sh.color_type = "TEXTURE"; sh.show_object_outline = True
sh.object_outline_color = (0.09, 0.07, 0.07); sh.show_cavity = True; sh.cavity_type = "WORLD"
sc.display.render_aa = "16"
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.86, 0.84, 0.8)
cd = bpy.data.cameras.new("c"); cd.type = "ORTHO"
cam = bpy.data.objects.new("c", cd); sc.collection.objects.link(cam); sc.camera = cam


def shot(name, yaw, elev, size, res, z=1.15):
    sc.render.resolution_x, sc.render.resolution_y = res
    cd.ortho_scale = size
    a, e = math.radians(yaw), math.radians(elev)
    d = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    cam.location = Vector((0, 0, z)) + d * 14
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = str(out / f"{name}.png"); bpy.ops.render.render(write_still=True)


shot("front", 0, 6, 4.6, (1500, 1100))
shot("battle_se", 30, 30, 4.8, (1500, 1100))
shot("back", 180, 6, 4.6, (1500, 1100))
print("DONE")
