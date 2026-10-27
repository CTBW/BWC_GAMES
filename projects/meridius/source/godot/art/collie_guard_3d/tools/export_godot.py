"""Export the collie Royal Guard for the Godot sandbox (background Blender).

  blender -b collie_anim.blend --python export_godot.py -- <out.glb> [texture_px]

collie_anim.blend: CollieRig with the footman's clips (transfer_clips.py) and his own
tail and hanging armour on them (collie_motion.py). His clips are the footman's, so
they go out as footman_3d/tools/export_godot.py sends the footman's, and this is that
script with the collie's names. Works on the open copy only (the .blend is not saved):
  * textures scaled down to `texture_px` (default 2048: four 4K Tripo atlases, his
    face and the shield's eagle hold up in the sandbox's close views);
  * the clips the sandbox plays, plus `turn_90_r`: the left turn played
    backwards (it starts and ends in his idle stance; a mirror would not);
  * a sidecar <out>.json with, per clip: length, loop, ground speed (Godot
    axes: the model faces +Z), turn angle, and event times (attack contact,
    footfalls, death settled);
  * the game's names for his idles: the standing idle (the .blend's "stand")
    goes out as "idle", what he plays at rest, and the guard idle (the .blend's
    "idle", whose first frame every clip starts and ends on) as "idle_guard",
    played now and then from it (the sidecar's variants.idle);
  * the figure raised onto the ground: his soles' depth under it on the guard is
    the armature's height (the sidecar's ground_lift_m).
"""
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = Path(argv[0])
TEX = int(argv[1]) if len(argv) > 1 else 2048
KEEP = ["idle", "stand", "walk", "attack", "block", "hit", "block_hit", "death", "lane", "turn_90", "turn_180", "stop", "start", "run", "charge_hit", "attack_stab", "charge_stab", "attack_thrust", "charge_thrust"]
KEEP = [n for n in KEEP if n in bpy.data.actions]
LOOPS = {"idle", "stand", "walk", "block", "run"}
FPS = 30.0
sc = bpy.context.scene
rig = bpy.data.objects["CollieRig"]
rig.location = (0, 0, 0)
rig.rotation_euler = (0, 0, 0)
rig.animation_data_create()
PB = rig.pose.bones
sword = bpy.data.objects["Sword"]


def b(n):
    return PB["mixamorig:" + n]


def to_godot(v):
    # glTF / Godot: x, z, -y of Blender.
    return [round(float(v[0]), 4), round(float(v[2]), 4), round(float(-v[1]), 4)]


def frames_of(act):
    f0, f1 = (int(v) for v in act.frame_range)
    return list(range(f0, f1 + 1))


def hips_yaw():
    # Facing of the hips about Z, from the hip line (his right is -X at rest, he faces -Y).
    r = b("RightUpLeg").head - b("LeftUpLeg").head
    fwd = Vector((0, 0, 1)).cross(r)
    return math.degrees(math.atan2(fwd.x, -fwd.y))


# No clip keys scale, so a pose bone's scale holds in every clip: a tool that left
# one (a shear turned into scale) would stretch the sword and fist everywhere.
stray = [pb.name.split(":")[-1] for pb in PB if any(abs(v - 1.0) > 1e-4 for v in pb.scale)]
for pb in PB:
    pb.scale = (1.0, 1.0, 1.0)
if stray:
    print("EXPORT reset a stray scale on", ", ".join(stray))

# The sword tip: the vertex farthest from the grip (the RightHand bone head) at rest.
rig.animation_data.action = bpy.data.actions["idle"]
sc.frame_set(1)
hand = rig.matrix_world @ b("RightHand").head
tip_local = max((v.co for v in sword.data.vertices), key=lambda co: ((sword.matrix_world @ co) - hand).length).copy()


def tip_world():
    return sword.matrix_world @ tip_local


# 1. The right turn: the left turn played backwards. Its first and last
# frames are the left turn's last and first, both his idle stance, so it
# starts and ends where idle is. (A mirror image would swap his staggered feet.)
src = bpy.data.actions["turn_90"]
rig.animation_data.action = src
fr = frames_of(src)
samples = []
for f in fr:
    sc.frame_set(f)
    samples.append(({pb.name: pb.rotation_quaternion.copy() for pb in PB}, b("Hips").location.copy()))
right = bpy.data.actions.new("turn_90_r")
right.use_fake_user = True
right["source"] = "turn_90 played backwards"
rig.animation_data.action = right
for i, f in enumerate(fr):
    rot, loc = samples[len(fr) - 1 - i]
    for pb in PB:
        pb.rotation_quaternion = rot[pb.name]
        pb.keyframe_insert("rotation_quaternion", frame=f)
    b("Hips").location = loc
    b("Hips").keyframe_insert("location", frame=f)
right.frame_range = src.frame_range

# Idle's first frame: the stance every clip leaves from and returns to.
rig.animation_data.action = bpy.data.actions["idle"]
sc.frame_set(1)
IDLE_YAW = hips_yaw()
MATCH = ["Hips", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]
IDLE_AT = {n: b(n).head.copy() for n in MATCH}

# 2. Measure every clip for the sidecar.
clips = {}
for name in KEEP + ["turn_90_r"]:
    act = bpy.data.actions[name]
    rig.animation_data.action = act
    fr = frames_of(act)
    vel = Vector(tuple(act["root_vel"]) + (0.0,)) if "root_vel" in act else Vector()
    hips, yaw, tips, ank, lead = [], [], [], {"Left": [], "Right": []}, []
    for f in fr:
        sc.frame_set(f)
        hips.append(rig.matrix_world @ b("Hips").head)
        yaw.append(hips_yaw())
        tips.append(tip_world())
        for s in ank:
            ank[s].append((rig.matrix_world @ b(s + "Foot").head).z)
        # His body's front: the hips or a toe, whichever is farthest forward.
        lead.append(max(-(rig.matrix_world @ b(n).head).y for n in ("Hips", "LeftToe_End", "RightToe_End")))
    t = lambda f: round((f - fr[0]) / FPS, 4)
    info = {
        "length": t(fr[-1]),
        "loop": name in LOOPS,
        "frames": len(fr),
        "root_vel": to_godot(vel),
        "turn_deg": round(((yaw[-1] - yaw[0] + 180) % 360) - 180, 1),
        "hips_drift": to_godot(hips[-1] - hips[0]),
        "events": {},
    }
    if name in ("attack", "attack_stab", "attack_thrust"):
        reach = [-(p.y) for p in tips]  # forward is -Y
        speed = [0.0] + [(tips[k] - tips[k - 1]).length * FPS for k in range(1, len(tips))]
        # Contact: the first frame within 1.5 cm of the farthest reach (a thrust holds it).
        k = next(j for j, r in enumerate(reach) if r >= max(reach) - 0.015)
        info["events"]["contact"] = t(fr[k])
        top = max(speed)
        swing = [fr[k2] for k2, v in enumerate(speed) if v > 0.5 * top]
        info["events"]["swing"] = [t(swing[0]), t(swing[-1])]
        info["tip_reach_m"] = round(max(reach), 3)
    if "root_path" in act:
        # Travel carried by the root (footman_3d's make_transitions.py, make_lane.py), Godot axes, from the first frame.
        rp = list(act["root_path"])
        info["root_path"] = [to_godot((rp[2 * k], rp[2 * k + 1], 0.0))[0::2] for k in range(len(rp) // 2)]
        for key in ("enter_walk_t", "exit_walk_t", "lane_m", "enter_run_t"):
            if key in act:
                info[key] = round(float(act[key]), 4)
    if "contact_t" in act:
        # A charge strike (footman_3d's make_charge.py): the attack's contact, carried over, and
        # the tip's reach then from where it ends (it stands still from the landing).
        info["events"]["contact"] = round(float(act["contact_t"]), 4)
        k = min(len(tips) - 1, int(round(float(act["contact_t"]) * FPS)))
        info["tip_reach_m"] = round(-tips[k].y, 3)
    if "contact" in info["events"]:
        # How far ahead of where the clip stands his body reaches at the blow
        # (a charge strike stands still from its landing): the lunge's front foot.
        info["lead_m"] = round(lead[min(len(lead) - 1, int(round(info["events"]["contact"] * FPS)))], 3)
    if name in ("walk", "step_lane", "run"):
        # The frame of the cycle nearest his idle stance: where the walk starts from a standstill.
        best, bt = 1e9, 0.0
        for f in fr[:-1]:
            sc.frame_set(f)
            dmax = max((b(n).head - IDLE_AT[n]).length for n in MATCH)
            if dmax < best:
                best, bt = dmax, t(f)
        info["start_from_idle"] = bt
        info["start_gap_cm"] = round(100 * best, 1)
        steps = []
        for s, z in ank.items():
            z = np.array(z)
            g = z < z.min() + 0.03
            for k in range(1, len(g)):
                if g[k] and not g[k - 1]:
                    steps.append([t(fr[k]), s])
        info["events"]["steps"] = sorted(steps)
    if name == "death":
        still = len(fr) - 1
        while still > 1 and (hips[still] - hips[still - 1]).length < 0.004:
            still -= 1
        info["events"]["settled"] = t(fr[still])
    if name in LOOPS:
        rig.animation_data.action = act
        sc.frame_set(fr[0])
        a = {pb.name: pb.matrix.copy() for pb in PB}
        sc.frame_set(fr[-1])
        gap = max((PB[n].matrix.translation - a[n].translation).length for n in a)
        info["loop_seam_cm"] = round(100 * gap, 2)
    clips[name] = info
    print("CLIP", name, json.dumps(info))

# 3. Turns: the turn is moved from the hips to the root. The body is held at
# idle's heading throughout and the sandbox turns the whole figure by
# `root_yaw` (degrees per frame, from the first frame), so a turn cross-fades
# into and out of idle without the body swinging.
for name in ("turn_90", "turn_180", "turn_90_r"):
    act = bpy.data.actions[name]
    rig.animation_data.action = act
    fr = frames_of(act)
    ys, hm = [], []
    for f in fr:
        sc.frame_set(f)
        ys.append(hips_yaw())
        hm.append(b("Hips").matrix.copy())
    ys = np.degrees(np.unwrap(np.radians(ys)))
    d0 = ((ys[0] - IDLE_YAW + 180.0) % 360.0) - 180.0
    held = ys - ys[0] + d0
    ys = ys - ys[0]
    for f, y, m in zip(fr, held, hm):
        sc.frame_set(f)
        b("Hips").matrix = Matrix.Rotation(math.radians(-y), 4, "Z") @ m
        bpy.context.view_layer.update()
        b("Hips").keyframe_insert("rotation_quaternion", frame=f)
        b("Hips").keyframe_insert("location", frame=f)
    left = []
    for f in fr:
        sc.frame_set(f)
        left.append(hips_yaw())
    clips[name]["root_yaw"] = [round(float(y), 2) for y in ys]
    print("ROOT_YAW", name, round(float(ys[-1]), 1), "hips held at idle's heading within", round(max(abs(((v - IDLE_YAW + 180) % 360) - 180) for v in left), 1))

# 4. The game's names: at rest he stands ("idle"); the guard idle plays now and
# then from it, once, each unit after its own random wait.
variants = {}
if "stand" in clips:
    bpy.data.actions["idle"].name = "idle_guard"
    bpy.data.actions["stand"].name = "idle"
    clips = {{"idle": "idle_guard", "stand": "idle"}.get(k, k): v for k, v in clips.items()}
    clips["idle_guard"]["loop"] = False
    variants = {"idle": {"clips": ["idle_guard"], "every_s": [9.0, 22.0]}}

# 5. Only the sandbox's clips go out.
for act in list(bpy.data.actions):
    if act.name not in clips:
        bpy.data.actions.remove(act)
rig.animation_data.action = bpy.data.actions["idle"]
sc.frame_set(1)

# 6. On the ground: the clips drop his hips into the guard (idle's first frame,
# every clip's start) without grounding his soles, which may stand under the
# rig's ground there. The whole figure is raised by their depth (the armature's
# place), so every clip plays on the ground. His height is taken first, on the
# rig's own ground: the sandbox's scale is set by it (sandbox3d.gd SOLDIER_PX).
height = round(float(max((rig.matrix_world @ b("HeadTop_End").head).z, 1.7)), 3)
dg = bpy.context.evaluated_depsgraph_get()
body = bpy.data.objects["Collie"].evaluated_get(dg)
low = min((body.matrix_world @ v.co).z for v in body.to_mesh().vertices)
body.to_mesh_clear()
lift = round(max(0.0, -low), 4)
rig.location = (0, 0, lift)
bpy.context.view_layer.update()
print("GROUND_LIFT", lift)
for img in bpy.data.images:
    if img.size[0] > TEX:
        img.scale(TEX, TEX)
OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=str(OUT), export_format="GLB", export_yup=True, export_apply=False,
    export_image_format="JPEG", export_jpeg_quality=88,
    export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True,
    export_frame_range=False, export_anim_slide_to_zero=True, export_anim_single_armature=True, export_reset_pose_bones=True,
    export_def_bones=False, export_optimize_animation_size=False, export_bake_animation=False,
    export_extras=False, export_cameras=False, export_lights=False,
)
meta = {"fps": FPS, "source": "art/collie_guard_3d/collie_anim.blend", "forward": [0, 0, 1], "variants": variants,
        "ground_lift_m": lift, "height_m": height, "clips": clips}
OUT.with_suffix(".json").write_text(json.dumps(meta, indent=1))
print("EXPORT_DONE", OUT, OUT.stat().st_size)
