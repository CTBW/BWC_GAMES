"""Review renders of the Sovereign Kiss's fog heart (background Blender; saves nothing).

  blender -b <kiss blend> --python render_kiss_heart.py -- <out dir> [views] [stand-in .glb] [px per m] [first,last]

After kiss_heart.py. From the game's camera (orthographic, 30 degrees down) for each view,
named for her facing as in render_clips.py ("ne": up-right, the player's side; "sw": down-left
towards the camera; "se", "nw"), in EEVEE on grass, with the sun from the upper left of the
picture and a stand-in at SK_Target facing her (the footman's GLB by default, holding its
idle; it stays local, and without it the target is left empty). The picture frames her, the
target and the heart's whole path. Writes <out>/<view>/<frame>.png for the scene's range.
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out = Path(argv[0])
views = (argv[1] if len(argv) > 1 and argv[1] else "ne,sw").split(",")
STAND_IN = argv[2] if len(argv) > 2 and argv[2] else str(
    Path(__file__).resolve().parents[3] / "prototypes/footman_anim/art3d/footman.glb")
PX_M = float(argv[3]) if len(argv) > 3 and argv[3] else 120.0     # pixels per metre
SPAN = [int(x) for x in argv[4].split(",")] if len(argv) > 4 else None
YAW = {"se": 45, "sw": -45, "ne": 135, "nw": -135}
GRASS = (0.20, 0.42, 0.10, 1.0)                    # linear; a lush, bright green

sc = bpy.context.scene
coll = bpy.data.collections["SK_FogHeart"]
cam = bpy.data.objects["SK_Camera"]
tgt = bpy.data.objects["SK_Target"]
heart = bpy.data.objects["SK_Heart"]

sc.render.engine = "BLENDER_EEVEE"
sc.eevee.taa_render_samples = 16
sc.view_settings.view_transform = "Standard"
sc.view_settings.look = "None"
sc.render.film_transparent = False
world = bpy.data.worlds.new("SK_Review")
world.use_nodes = True
bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
bg.inputs["Color"].default_value = (0.55, 0.62, 0.75, 1.0)
bg.inputs["Strength"].default_value = 0.9
sc.world = world

ground = bpy.data.objects.new("SK_Ground", bpy.data.meshes.new("SK_Ground"))
ground.data.from_pydata([(-40, -40, 0), (40, -40, 0), (40, 40, 0), (-40, 40, 0)], [], [(0, 1, 2, 3)])
gm = bpy.data.materials.new("SK_Grass")
gm.use_nodes = True
bsdf = next(n for n in gm.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
bsdf.inputs["Base Color"].default_value = GRASS
bsdf.inputs["Roughness"].default_value = 1.0
ground.data.materials.append(gm)
sc.collection.objects.link(ground)

sun = bpy.data.objects.new("SK_Sun", bpy.data.lights.new("SK_Sun", "SUN"))
sun.data.energy = 3.2
sun.data.angle = math.radians(4)
sun.data.use_shadow = True
sc.collection.objects.link(sun)

# the stand-in, facing her, holding its idle
if Path(STAND_IN).is_file():
    before = set(bpy.data.objects)
    acts = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=STAND_IN)
    new = [o for o in bpy.data.objects if o not in before]
    root = next(o for o in new if o.parent is None and o.type == "ARMATURE")
    root.location = tgt.location
    root.rotation_euler = tgt.rotation_euler
    idle = next((a for a in bpy.data.actions if a not in acts and a.name.split(".")[0] == "idle"), None)
    if idle is not None:
        root.animation_data_create()
        root.animation_data.action = idle
        if idle.slots:
            root.animation_data.action_slot = idle.slots[0]
    for o in new:
        if o.type == "MESH":
            o.visible_shadow = True
else:
    print("NO STAND-IN", STAND_IN)

rig = bpy.data.objects["SuccubusRig"]
frames = range(sc.frame_start, sc.frame_end + 1)
# what the picture must hold: her, the target, the heart's path with its width
pts = [Vector((x, y, z)) for x in (-0.6, 0.6) for y in (-0.6, 0.6) for z in (0.0, 2.1)]
pts += [tgt.location + Vector((x, y, z)) for x in (-0.6, 0.6) for y in (-0.6, 0.6) for z in (0.0, 2.4)]
for f in frames:
    sc.frame_set(f)
    if not heart.hide_render:
        w = heart.scale.x * 0.5
        pts += [heart.location + Vector((0, 0, dz)) for dz in (-w, w)]
        pts += [heart.location + Vector((dx, dy, 0)) for dx in (-w, w) for dy in (-w, w)]

for view in views:
    yaw = math.radians(YAW[view])
    d = Matrix.Rotation(-yaw, 3, "Z") @ Vector((0, -math.cos(math.radians(30)), math.sin(math.radians(30))))
    rot = (-d).to_track_quat("-Z", "Y")
    R = rot.to_matrix()
    right, upv = R.col[0], R.col[1]
    xs = [p.dot(right) for p in pts]
    ys = [p.dot(upv) for p in pts]
    w_m, h_m = max(xs) - min(xs) + 0.6, max(ys) - min(ys) + 0.6
    mid = right * (max(xs) + min(xs)) / 2 + upv * (max(ys) + min(ys)) / 2
    sc.render.resolution_x = int(round(w_m * PX_M / 2)) * 2
    sc.render.resolution_y = int(round(h_m * PX_M / 2)) * 2
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(w_m, h_m)
    cam.data.sensor_fit = "AUTO"
    cam.location = mid + d * 30
    cam.rotation_euler = rot.to_euler()
    cam.data.clip_end = 100
    # the sun from the upper left of the picture, a little behind the camera
    to_sun = (-right * 0.55 + Vector((0, 0, 0.8)) + Vector((d.x, d.y, 0)).normalized() * 0.35).normalized()
    sun.rotation_euler = (-to_sun).to_track_quat("-Z", "Y").to_euler()
    (out / view).mkdir(parents=True, exist_ok=True)
    sc.render.filepath = str(out / view) + "/"
    sc.render.image_settings.file_format = "PNG"
    if SPAN:
        sc.frame_start, sc.frame_end = SPAN
    bpy.ops.render.render(animation=True)
    print("RENDERED", view, sc.render.resolution_x, sc.render.resolution_y,
          sc.frame_end - sc.frame_start + 1, "frames")
