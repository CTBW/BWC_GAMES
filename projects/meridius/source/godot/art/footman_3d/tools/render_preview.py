"""Preview renders of the rigged footman (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python render_preview.py -- <out dir> <mode> [action] [step] [facings]

mode "stress": rest pose with the skeleton drawn in, then deformation tests
               (arms down, arm overhead, deep knee bend, head turn), front and 3/4.
mode "clip":   frames of an action from the game's battle camera (orthographic,
               30 degree elevation) for each facing (se,sw,ne,nw), every `step` frames.
Flat-lit textures with an outline, close to the game's cel look.
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out = Path(argv[0])
mode = argv[1]
out.mkdir(parents=True, exist_ok=True)
sc = bpy.context.scene
rig = bpy.data.objects["FootmanRig"]
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light = "FLAT"
sh.color_type = "TEXTURE"
sh.show_object_outline = True
sh.object_outline_color = (0.09, 0.07, 0.07)
sh.show_cavity = True
sh.cavity_type = "WORLD"
sc.display.render_aa = "8"
sc.render.film_transparent = True
sc.render.resolution_x = 520
sc.render.resolution_y = 560
cam_data = bpy.data.cameras.new("PreviewCam")
cam_data.type = "ORTHO"
cam = bpy.data.objects.new("PreviewCam", cam_data)
sc.collection.objects.link(cam)
sc.camera = cam


def aim(az_deg, elev_deg, scale, target=Vector((0, 0, 0.95)), dist=8.0):
    az, el = math.radians(az_deg), math.radians(elev_deg)
    d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    cam.location = target + d * dist
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cam_data.ortho_scale = scale


def shot(path):
    sc.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def pb(name):
    return rig.pose.bones["mixamorig:" + name]


def reset():
    for b in rig.pose.bones:
        b.rotation_mode = "QUATERNION"
        b.rotation_quaternion = Quaternion()
        b.location = Vector()


def rot(name, axis, deg):
    b = pb(name)
    b.rotation_mode = "QUATERNION"
    # Rotate about a world axis, expressed in the bone's rest frame.
    bone = b.bone
    R = (rig.matrix_world.to_3x3() @ bone.matrix_local.to_3x3()).normalized()
    ax_local = R.inverted() @ Vector(axis)
    b.rotation_quaternion = Quaternion(ax_local, math.radians(deg)) @ b.rotation_quaternion


if mode == "stress":
    # Skeleton drawn as thin sticks, in front (X-ray) for the rest-pose check.
    mat = bpy.data.materials.new("bone_vis")
    mat.diffuse_color = (1.0, 0.15, 0.4, 1.0)
    sticks = []
    for bone in rig.data.bones:
        h = rig.matrix_world @ bone.head_local
        t = rig.matrix_world @ bone.tail_local
        bpy.ops.mesh.primitive_cylinder_add(radius=0.012, depth=(t - h).length, location=(h + t) / 2)
        c = bpy.context.object
        c.rotation_euler = (t - h).to_track_quat("Z", "Y").to_euler()
        c.data.materials.append(mat)
        c.show_in_front = True
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.022, location=h)
        s = bpy.context.object
        s.data.materials.append(mat)
        s.show_in_front = True
        sticks += [c, s]
    sh.color_type = "MATERIAL"
    body = bpy.data.objects["Footman"]
    reset()
    aim(0, 0, 2.1, Vector((0, 0, 0.92)))
    shot(out / "00_skeleton_front.png")
    aim(90, 0, 2.1, Vector((0, 0, 0.92)))
    shot(out / "01_skeleton_side.png")
    for o in sticks:
        bpy.data.objects.remove(o)
    sh.color_type = "TEXTURE"
    tests = [
        ("02_rest", []),
        ("03_arms_down", [("LeftArm", (0, 1, 0), 62), ("RightArm", (0, 1, 0), -62)]),
        ("04_arm_overhead", [("RightArm", (0, 1, 0), 80), ("RightForeArm", (0, 1, 0), 20), ("LeftArm", (0, 1, 0), 55)]),
        ("05_knee_bend", [("LeftUpLeg", (1, 0, 0), -70), ("LeftLeg", (1, 0, 0), 95), ("RightUpLeg", (1, 0, 0), 25),
                          ("LeftArm", (0, 1, 0), 60), ("RightArm", (0, 1, 0), -60)]),
        ("06_head_turn", [("Head", (0, 0, 1), 35), ("Neck", (0, 0, 1), 10), ("LeftArm", (0, 1, 0), 60), ("RightArm", (0, 1, 0), -60),
                          ("Spine1", (0, 0, 1), 12)]),
    ]
    for name, rots in tests:
        reset()
        for bn, ax, deg in rots:
            rot(bn, ax, deg)
        bpy.context.view_layer.update()
        aim(0, 0, 2.2, Vector((0, 0, 0.92)))
        shot(out / f"{name}_front.png")
        aim(-45, 30, 2.2, Vector((0, 0, 0.92)))
        shot(out / f"{name}_iso.png")
else:
    action = bpy.data.actions[argv[2]]
    step = int(argv[3]) if len(argv) > 3 else 2
    facings = (argv[4] if len(argv) > 4 else "se,sw,ne,nw").split(",")
    travel = len(argv) > 5 and argv[5] == "travel"
    rig.animation_data_create()
    rig.animation_data.action = action
    f0, f1 = (int(v) for v in action.frame_range)
    # Game facings: the character faces -Y; the camera looks from the screen's
    # bottom at 30 degrees. SE = turned 45 degrees to the camera's right, etc.
    yaw = {"se": 45, "sw": -45, "ne": 135, "nw": -135}
    vel = Vector(tuple(action["root_vel"]) + (0.0,)) if "root_vel" in action and travel else None
    for fk in facings:
        rig.rotation_euler = Euler((0, 0, math.radians(yaw[fk])))
        if vel is not None:
            # Walk with his ground speed: the camera stays still, the feet plant.
            R = rig.rotation_euler.to_matrix()
            dur = (f1 - f0) / 30.0
            path = R @ (vel * dur)
            aim(0, 30, 2.6 + path.length * 0.9, Vector((0, 0, 0.9)) + path * 0.5)
        else:
            aim(0, 30, 2.6, Vector((0, 0, 0.9)))
        d = out / f"{argv[2]}_{fk}"
        d.mkdir(parents=True, exist_ok=True)
        for i, f in enumerate(range(f0, f1 + 1, step)):
            sc.frame_set(f)
            if vel is not None:
                rig.location = rig.rotation_euler.to_matrix() @ (vel * ((f - f0) / 30.0))
            shot(d / f"{i:04d}.png")
        rig.location = Vector()
    rig.rotation_euler = Euler((0, 0, 0))
print("PREVIEW_DONE", out)
