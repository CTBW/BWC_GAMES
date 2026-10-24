"""Review renders of the succubus rig (background Blender).

  blender -b succubus_rig.blend --python render_rig.py -- <out dir> [skeleton|poses]

skeleton: rest pose, textured, with the bones drawn in front, from the front, the side,
          the back and three-quarter views.
poses:    deformation tests (arms down, an arm overhead, a deep knee bend, head turn, the
          tail swung, the wings swept), from the front and from the game's camera.
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out = Path(argv[0])
mode = argv[1] if len(argv) > 1 else "skeleton"
out.mkdir(parents=True, exist_ok=True)
sc = bpy.context.scene
rig = bpy.data.objects["SuccubusRig"]
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light = "FLAT"
sh.color_type = "TEXTURE"
sh.show_object_outline = True
sh.object_outline_color = (0.09, 0.07, 0.07)
sh.show_cavity = True
sh.cavity_type = "WORLD"
sc.display.render_aa = "8"
sc.world = bpy.data.worlds.new("w")
sc.world.color = (0.18, 0.18, 0.2)
cam_d = bpy.data.cameras.new("cam")
cam_d.type = "ORTHO"
cam = bpy.data.objects.new("cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam


def aim(az, el, scale, target=Vector((0, 0, 1.0)), res=(700, 760)):
    a, e = math.radians(az), math.radians(el)
    d = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    cam.location = target + d * 8
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cam_d.ortho_scale = scale
    sc.render.resolution_x, sc.render.resolution_y = res


def shot(name):
    sc.render.filepath = str(out / f"{name}.png")
    bpy.ops.render.render(write_still=True)


def reset():
    for b in rig.pose.bones:
        b.rotation_mode = "QUATERNION"
        b.rotation_quaternion = Quaternion()
        b.location = Vector()


def rot(name, axis, deg):
    """Turn a bone about a world axis (in its rest frame)."""
    b = rig.pose.bones[name if name in rig.pose.bones else "mixamorig:" + name]
    b.rotation_mode = "QUATERNION"
    R = (rig.matrix_world.to_3x3() @ b.bone.matrix_local.to_3x3()).normalized()
    b.rotation_quaternion = Quaternion(R.inverted() @ Vector(axis), math.radians(deg)) @ b.rotation_quaternion


if mode == "skeleton":
    mat = bpy.data.materials.new("bone_vis")
    mat.diffuse_color = (1.0, 0.15, 0.4, 1.0)
    for bone in rig.data.bones:
        h, t = rig.matrix_world @ bone.head_local, rig.matrix_world @ bone.tail_local
        bpy.ops.mesh.primitive_cylinder_add(radius=0.008, depth=max(0.001, (t - h).length), location=(h + t) / 2)
        c = bpy.context.object
        c.rotation_euler = (t - h).to_track_quat("Z", "Y").to_euler()
        c.data.materials.append(mat)
        c.show_in_front = True
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.016, location=h)
        s = bpy.context.object
        s.data.materials.append(mat)
        s.show_in_front = True
    sh.color_type = "MATERIAL"
    for o in bpy.data.objects:
        if o.type == "MESH" and o.data.materials and o.data.materials[0] is not mat:
            for m in o.data.materials:
                if m:
                    m.diffuse_color = (0.75, 0.75, 0.75, 1)
    for nm, az, el in (("front", 0, 0), ("side", 90, 0), ("back", 180, 0), ("back34", 145, 15), ("front34", 325, 15)):
        aim(az, el, 2.6, Vector((0, 0.15, 1.0)))
        shot("skel_" + nm)
else:
    tests = [
        ("rest", []),
        ("arms_down", [("LeftArm", (0, 1, 0), 65), ("RightArm", (0, 1, 0), -65)]),
        ("arm_overhead", [("LeftArm", (0, 1, 0), -80), ("LeftForeArm", (0, 1, 0), -20), ("RightArm", (0, 1, 0), -55)]),
        ("knee_bend", [("LeftUpLeg", (1, 0, 0), -70), ("LeftLeg", (1, 0, 0), 95), ("RightUpLeg", (1, 0, 0), 25),
                       ("LeftArm", (0, 1, 0), 60), ("RightArm", (0, 1, 0), -60)]),
        ("head_turn", [("Head", (0, 0, 1), 35), ("Neck", (0, 0, 1), 10), ("Spine1", (0, 0, 1), 12),
                       ("LeftArm", (0, 1, 0), 60), ("RightArm", (0, 1, 0), -60)]),
        ("tail_wings", [("Tail_1", (0, 0, 1), 15), ("Tail_2", (0, 0, 1), 10), ("Tail_3", (0, 0, 1), 10),
                        ("Tail_4", (0, 0, 1), 10), ("WingLeft_1", (0, 0, 1), 30), ("WingRight_1", (0, 0, 1), -30),
                        ("WingLeft_2", (0, 1, 0), 15), ("WingRight_2", (0, 1, 0), -15),
                        ("LeftArm", (0, 1, 0), 60), ("RightArm", (0, 1, 0), -60)]),
    ]
    for name, rots in tests:
        reset()
        for bn, ax, deg in rots:
            rot(bn, ax, deg)
        bpy.context.view_layer.update()
        aim(0, 0, 2.6, Vector((0, 0.15, 1.0)))
        shot(f"pose_{name}_front")
        aim(135, 30, 2.8, Vector((0, 0.15, 1.0)))
        shot(f"pose_{name}_game")
print("RENDER_DONE", out)
