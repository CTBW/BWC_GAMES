"""Renders and data for the whip-slash schematic (slash_schematic.py draws it).

  blender -b art/succubus_3d/succubus_anim.blend --factory-startup \\
      --python art/succubus_3d/tools/slash_schematic_blend.py -- <out dir>

Writes in <out dir>:
  data.json     the attack's lash (17 points: the 16 bone heads and the tip) at 1/8-frame
                steps over frames 17-71, the coil's and Lash_1's scale per frame, and the
                clip's events
  whip_<f>.png  the whip straight (rest pose) with its coil and lash scaled as at attack
                frame f, side-on, the lash along +x (WHIP_FRAMES)
  her_<f>.png   her at attack frame f from the game camera for facing SE: orthographic,
                30 degrees down, from her front right (HER_SHOTS)
  view.json     the projections, so the drawing can put lines on the renders
"""
import bpy, json, math, os, sys
from mathutils import Matrix, Vector

out = sys.argv[sys.argv.index("--") + 1]
os.makedirs(out, exist_ok=True)
sc = bpy.context.scene
rig = bpy.data.objects["SuccubusRig"]
PB = rig.pose.bones
act = bpy.data.actions["attack"]
LASH = [f"Lash_{i + 1}" for i in range(16)]
WHIP_FRAMES = (16, 18, 20, 22)
WHIP_PPM = 440
# shot name: (frame, screen centre x, y (m), width, height (m)); one scale for all
HER_SHOTS = {"27": (27, 0.2, 0.45, 4.4, 4.6), "52": (52, 0.2, 0.6, 4.4, 4.6)}
HER_PPM = 200
EL, AZ = math.radians(30), math.radians(45)
BACK = Vector((-math.sin(AZ) * math.cos(EL), -math.cos(AZ) * math.cos(EL), math.sin(EL)))  # towards the camera
RIGHT = (-BACK).cross(Vector((0, 0, 1))).normalized()
UP = RIGHT.cross(-BACK)

sh = sc.display.shading
sc.render.engine = "BLENDER_WORKBENCH"
sh.light = "STUDIO"
sh.color_type = "TEXTURE"
sh.show_object_outline = True
sh.object_outline_color = (0.09, 0.07, 0.07)
sc.render.film_transparent = True
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
cam_d = bpy.data.cameras.new("schematic")
cam_d.type = "ORTHO"
cam_d.clip_end = 100.0
cam = bpy.data.objects.new("schematic", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam


def shoot(path, x_axis, look, centre, w, h, ppm):
    """Orthographic, looking along `look`, with x_axis to the right."""
    z = -look.normalized()
    y = z.cross(x_axis).normalized()
    x = y.cross(z)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = centre + z * 20
    cam.matrix_world = m
    sc.render.resolution_x, sc.render.resolution_y = int(w * ppm), int(h * ppm)
    cam_d.ortho_scale = max(w, h)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


# --- data ---------------------------------------------------------------------
rig.animation_data.action = act
n = int(act["frames"])
data = {"events": json.loads(act.get("events", "{}")), "fps": sc.render.fps, "scales": [], "sub": []}
for f in range(1, n + 1):
    sc.frame_set(f)
    data["scales"].append([PB["WhipCoil"].scale[0], PB[LASH[0]].scale[0]])
for f in range(17, 72):
    for s in range(8):
        sc.frame_set(f, subframe=s / 8)
        M = rig.matrix_world
        data["sub"].append({"f": f + s / 8, "lash": [list(M @ PB[x].head) for x in LASH] + [list(M @ PB[LASH[-1]].tail)]})
json.dump(data, open(os.path.join(out, "data.json"), "w"))

view = {"se": {"right": list(RIGHT), "up": list(UP), "back": list(BACK), "ppm": HER_PPM, "shots": {}}}

# --- her from the game camera ---------------------------------------------------
for name, (f, cx, cy, w, h) in HER_SHOTS.items():
    sc.frame_set(f)
    shoot(os.path.join(out, f"her_{name}.png"), RIGHT, -BACK, RIGHT * cx + UP * cy, w, h, HER_PPM)
    view["se"]["shots"][name] = {"frame": f, "cx": cx, "cy": cy, "w": w, "h": h}

# --- the whip, straight ----------------------------------------------------------
for o in bpy.data.objects:
    if o.type == "MESH":
        o.hide_render = o.name not in ("Whip", "WhipLash")
rig.animation_data.action = None
for pb in PB:
    pb.location = (0, 0, 0)
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.rotation_euler = (0, 0, 0)
    pb.scale = (1, 1, 1)
bpy.context.view_layer.update()
M = rig.matrix_world
collar = M @ PB["WhipCoil"].head
tip = M @ PB[LASH[-1]].tail
axis = (tip - collar).normalized()
look = (Vector((0.25, -1.0, 0.35)) - axis * axis.dot(Vector((0.25, -1.0, 0.35)))).normalized()
up = (-look).cross(axis).normalized()
ticks = [axis.dot(M @ PB[x].head - collar) for x in LASH] + [axis.dot(tip - collar)]
dg = bpy.context.evaluated_depsgraph_get()
ev = bpy.data.objects["Whip"].evaluated_get(dg)
pts = [ev.matrix_world @ v.co for v in ev.data.vertices]
lo = min(axis.dot(p - collar) for p in pts)
side = [up.dot(p - collar) for p in pts]
x0, x1 = lo - 0.04, ticks[-1] + 0.06
y0, y1 = min(side) - 0.04, max(side) + 0.04
centre = collar + axis * (x0 + x1) / 2 + up * (y0 + y1) / 2
view["whip"] = {"ppm": WHIP_PPM, "x0": x0, "x1": x1, "y0": y0, "y1": y1, "ticks": ticks, "frames": {}}
for f in WHIP_FRAMES:
    c, g = data["scales"][f - 1]
    PB["WhipCoil"].scale = (c,) * 3
    PB[LASH[0]].scale = (g,) * 3
    shoot(os.path.join(out, f"whip_{f}.png"), axis, look, centre, x1 - x0, y1 - y0, WHIP_PPM)
    view["whip"]["frames"][str(f)] = {"coil": c, "lash": g}
json.dump(view, open(os.path.join(out, "view.json"), "w"), indent=1)
print("SCHEMATIC_RENDERS", out)
