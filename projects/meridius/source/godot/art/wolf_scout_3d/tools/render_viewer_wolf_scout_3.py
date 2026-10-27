"""Pose viewer frames of Wolf Scout 3's four clips (background Blender, Workbench).

  blender --background wolf_scout_3.blend --python render_viewer_wolf_scout_3.py -- <out dir> [clip,clip]

Writes <out>/<clip>_<facing>/NNN.png and <out>/render_info.json for
crossbowman_3d/tools/build_sheets.py (scale 0.8). The look, camera directions and
pixels per metre are those of render_viewer_wolf_scout_2.py, so the two scouts'
sheets compare at one scale. Each facing's frame is centred across on the area she
covers during the clip; the height and its centre are shared by the four facings, so
her feet stand level in each. The death is shown in place: the camera follows her
hips over the ground. Looping clips leave out their last frame, which repeats the
first.
"""
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

CLIPS = ("idle", "sneak", "attack", "death")
FACINGS = {"se": (.65, -1, .40), "sw": (-.65, -1, .40), "ne": (.65, 1, .40), "nw": (-.65, 1, .40)}
TARGET = Vector((0, -.1, .65))
FOLLOW = {"death"}  # clips shown in place, with the camera following her hips over the ground
PX = 1.95 / 900  # metres per pixel, as the sneak sheets
MARGIN = 0.06    # metres kept around her widest pose

argv = sys.argv[sys.argv.index("--") + 1:]
out = Path(argv[0])
clips = argv[1].split(",") if len(argv) > 1 else list(CLIPS)
sc = bpy.context.scene
rig = bpy.data.objects["WolfScout3_Rig"]
meshes = [o for o in sc.objects if o.type == "MESH" and o.name.startswith("WolfScout3_")]
for o in sc.objects:
    o.hide_render = o.type == "MESH" and o not in meshes
cam = bpy.data.objects.new("ViewerCamera", bpy.data.cameras.new("ViewerCamera"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.clip_end = 50
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light, sh.studio_light, sh.color_type = "STUDIO", "Default", "TEXTURE"
sh.show_cavity, sh.cavity_type = True, "WORLD"
sh.show_shadows = sh.show_object_outline = sh.show_xray = sh.show_backface_culling = False
sh.show_specular_highlight = False
sc.display.render_aa = "8"
sc.view_settings.view_transform, sc.view_settings.exposure = "AgX", 0.0
sc.render.resolution_percentage = 100
sc.render.film_transparent = True
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"


def facing_basis(d):
    d = Vector(d).normalized()
    q = (-d).to_track_quat("-Z", "Y")
    return d, q, q @ Vector((1, 0, 0)), q @ Vector((0, 1, 0))


def bind(name):
    a = bpy.data.actions[name]
    rig.animation_data.action = a
    rig.animation_data.action_slot = a.slots[0]
    n = int(a["frames"])
    return range(1, n if a["loop"] else n + 1)


def ground(name):
    """Her hips' place on the ground in the current frame, or the origin for a clip not followed."""
    if name not in FOLLOW:
        return Vector()
    p = rig.matrix_world @ rig.pose.bones["mixamorig:Hips"].head
    return Vector((p.x, p.y, 0))


def extent(name, frames):
    """Per facing, the range of her surface around the target along the screen's right and up axes."""
    axes = {fk: facing_basis(d)[2:] for fk, d in FACINGS.items()}
    box = {fk: [math.inf, -math.inf, math.inf, -math.inf] for fk in FACINGS}
    dg = bpy.context.evaluated_depsgraph_get()
    for f in frames:
        sc.frame_set(f)
        g = np.array(TARGET + ground(name))
        for o in meshes:
            ev = o.evaluated_get(dg)
            m = ev.to_mesh()
            co = np.empty(len(m.vertices) * 3, np.float32)
            m.vertices.foreach_get("co", co)
            ev.to_mesh_clear()
            co = co.reshape(-1, 3) @ np.array(ev.matrix_world)[:3, :3].T + np.array(ev.matrix_world)[:3, 3] - g
            for fk, (r, u) in axes.items():
                pu, pv = co @ np.array(r), co @ np.array(u)
                b = box[fk]
                b[:] = min(b[0], pu.min()), max(b[1], pu.max()), min(b[2], pv.min()), max(b[3], pv.max())
    return box


def pixels(metres):
    return max(900, 10 * math.ceil((metres + 2 * MARGIN) / PX / 10))


for name in clips:
    frames = bind(name)
    box = extent(name, frames)
    v0, v1 = min(b[2] for b in box.values()), max(b[3] for b in box.values())
    rx, ry = pixels(max(b[1] - b[0] for b in box.values())), pixels(v1 - v0)
    sc.render.resolution_x, sc.render.resolution_y = rx, ry
    cam.data.ortho_scale = PX * max(rx, ry)
    for fk, d in FACINGS.items():
        d, q, right, up = facing_basis(d)
        centre = TARGET + d * 5 + right * ((box[fk][0] + box[fk][1]) / 2) + up * ((v0 + v1) / 2)
        cam.rotation_euler = q.to_euler()
        folder = out / f"{name}_{fk}"
        folder.mkdir(parents=True, exist_ok=True)
        for i, f in enumerate(frames):
            sc.frame_set(f)
            cam.location = centre + ground(name)
            sc.render.filepath = str(folder / f"{i + 1:03d}.png")
            bpy.ops.render.render(write_still=True)
    (out / f"canvas_{name}.json").write_text(json.dumps([rx, ry]))
    print("CLIP_DONE", name, len(frames), "frames", f"{rx}x{ry}", flush=True)

# Every finished clip in the fixed order; parallel runs on separate clips each rebuild it.
info = {c: {"canvas": json.loads((out / f"canvas_{c}.json").read_text())} for c in CLIPS if (out / f"canvas_{c}.json").exists()}
(out / "render_info.json").write_text(json.dumps(info))
print("VIEWER_FRAMES_READY", out, list(info), flush=True)
