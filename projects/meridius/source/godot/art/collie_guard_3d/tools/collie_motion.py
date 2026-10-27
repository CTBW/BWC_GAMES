"""The collie's tail and hanging armour on his clips (background Blender).

  blender -b collie_anim.blend --python collie_motion.py -- [clip,clip...]

Overwrites the keys of the tail, tabard and tasset bones in each clip (transfer_clips.py
leaves them at rest), and saves. Run it again after the clips change.

Tail. As the succubus's (succubus_3d/tools/secondary_motion.py): each bone swings about its
own Z, TAIL_AMP degrees from the root to the tip, each TAIL_LAG later than the one before,
so the swing runs down the tail.
  idle, stand, block: a slow sway at IDLE_AMP, a whole number of times per loop
          (near IDLE_PERIOD), so it loops.
  walk:   once per stride (the clip's loop) at WALK_AMP, opposite to his hips' sideways sway;
          start and stop build it up and let it die down; lane and the turns step at it.
  run:    at RUN_AMP, the root raised RUN_LIFT so the tail streams out behind him; the
          charges run with it until the blow, then let it sink back (CHARGE_SETTLE).
  attack, hit, the stab and thrust, block_hit: a little sway, and the tail dragged: it
          points where his hips pointed a few frames before (3 frames a bone), DRAG of
          the difference, at most DRAG_MAX.
  death:  the sway dies out and the tail sinks as he falls (DEATH_DROOP, spread down its
          bones). He lands on his front, where the tail would stand up off his back, so
          once he is down it is laid on the ground beside his legs: each bone turned to
          point DRAPE_SIDE to his right of his legs (away from his shield), the first ones
          down to the ground (DRAPE_DOWN).
A ground pass then turns up, root first, any tail bone that would go under the ground.
Hanging armour (rig_collie.py). The front panel (TabardF) rides forward over whichever thigh
is furthest forward, at most PANEL_FWD; the back panel (TabardB) back with whichever is
furthest back, at most PANEL_BACK; neither goes sideways. Each tasset turns with its thigh's
swing (no twist) by TASSET_FOLLOW.
"""
import math
import sys

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
CLIPS = ["idle", "stand", "walk", "attack", "block", "hit", "block_hit", "death", "lane", "turn_90", "turn_180",
         "stop", "start", "run", "charge_hit", "attack_stab", "charge_stab", "attack_thrust", "charge_thrust"]
only = argv[0].split(",") if argv and argv[0] else [c for c in CLIPS if c in bpy.data.actions]
sc = bpy.context.scene
rig = bpy.data.objects["CollieRig"]
B = rig.data.bones
FPS = 30
TAIL = [f"Tail_{i}" for i in range(1, 7)]
TAIL_AMP = [7, 7, 6, 6, 5, 5]          # degrees per bone at amplitude 1
TAIL_LAG = math.radians(25)
IDLE_AMP, IDLE_PERIOD = 0.5, 60          # idle sway: x TAIL_AMP; frames per sway
WALK_AMP, STRIDE = 1.2, 1.33             # walking: x TAIL_AMP; seconds per stride (walk's loop)
RUN_AMP, RUN_LIFT, RUN_STRIDE = 1.0, 22.0, 0.70
CHARGE_SETTLE = 0.5                      # seconds after the blow for the run's lift to sink
DRAG, DRAG_MAX = 0.6, 14.0                # x his hips' turn over the lag (3 frames a bone), degrees
DEATH_DROOP = 55.0                       # degrees the tail sinks as he falls (spread down its bones)
DRAPE_SIDE = 35.0                        # dead: the tail lies this far to his right of his legs
DRAPE_DOWN = (0.8, 0.4, 0.1, 0.0, 0.0, 0.0)   # how steeply each tail bone aims at the ground
DRAPE_IN = (45, 85)                      # frames: from his fall to lying still
GROUND_TAIL = 0.025                      # lowest a tail bone's end may go above his soles
PANEL_FWD, PANEL_BACK = 80.0, 45.0
TASSET_FOLLOW = 0.85
LOOPS = {"idle", "stand", "walk", "block", "run"}


def rest_frame(name):
    return (rig.matrix_world.to_3x3() @ B[name].matrix_local.to_3x3()).normalized()


def world_rot(name, axis, deg):
    """A turn about a world axis (at rest), as a rotation in the bone's rest frame."""
    return Quaternion(rest_frame(name).inverted() @ Vector(axis).normalized(), math.radians(deg))


def env(t, a, b):
    """0 before a, smooth to 1 at b (or 1 to 0 if a > b)."""
    if a > b:
        return 1 - env(t, b, a)
    k = min(1.0, max(0.0, (t - a) / (b - a)))
    return k * k * (3 - 2 * k)


def key(act, name, frame, q):
    pb = rig.pose.bones[name]
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = q
    pb.keyframe_insert("rotation_quaternion", frame=frame)


def fcurves(act):
    if hasattr(act, "fcurves"):
        return list(act.fcurves)
    return [fc for layer in act.layers for strip in layer.strips for bag in strip.channelbags for fc in bag.fcurves]


def at_rest():
    rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    bpy.context.view_layer.update()


def hips_delta():
    hb = rig.pose.bones["mixamorig:Hips"]
    return hb.matrix.to_3x3() @ hb.bone.matrix_local.to_3x3().inverted()


def thigh(side):
    P = rig.pose.bones
    return hips_delta().inverted() @ (P[f"mixamorig:{side}Leg"].head - P[f"mixamorig:{side}UpLeg"].head)


at_rest()
THIGH0 = {s: thigh(s) for s in ("Left", "Right")}


def pitch(d):
    return math.degrees(math.atan2(-d.y, -d.z))     # forward (-Y) positive


def sample(act, n):
    """Per frame: the hips' x and yaw, each thigh's direction in the hips' frame."""
    rig.animation_data.action = act
    xs, yaw, th = [], [], []
    for f in range(1, n + 1):
        sc.frame_set(f)
        hb = rig.pose.bones["mixamorig:Hips"]
        xs.append((rig.matrix_world @ hb.head).x)
        fwd = (rig.matrix_world @ hb.matrix).to_3x3() @ Vector((0, 0, 1))
        yaw.append(math.atan2(fwd.x, -fwd.y))
        th.append({s: thigh(s) for s in ("Left", "Right")})
    t = np.arange(n) / max(1, n - 1) * 2 * math.pi
    x = np.array(xs) - np.mean(xs)
    phase = math.atan2(float(np.sum(x * np.cos(t))), float(np.sum(x * np.sin(t))))   # x ~ sin(t + phase)
    return phase, np.unwrap(np.array(yaw)), th


def sway_sign():
    """Which way a turn about Tail_1's own Z swings the tail (+1: towards his left, +X)."""
    at_rest()
    pb = rig.pose.bones["Tail_1"]
    pb.rotation_quaternion = Quaternion((0, 0, 1), math.radians(10))
    bpy.context.view_layer.update()
    x1 = (rig.matrix_world @ rig.pose.bones["Tail_6"].tail).x
    pb.rotation_quaternion = Quaternion()
    bpy.context.view_layer.update()
    return 1.0 if x1 > (rig.matrix_world @ rig.pose.bones["Tail_6"].tail).x else -1.0


SSIGN = sway_sign()


def lift_axis(name):
    """The axis in Tail bone's rest frame about which + raises it (towards world up)."""
    R = rest_frame(name)
    along = R @ Vector((0, 1, 0))
    ax = along.cross(Vector((0, 0, 1)))
    return (R.inverted() @ ax).normalized() if ax.length > 1e-6 else Vector((1, 0, 0))


def tail_keys(clip, act, n, phase, yaw):
    loop = clip in LOOPS
    cyc = n - 1 if loop else n
    contact = float(act.get("contact_t", 0.0)) * FPS + 1
    for f in range(1, n + 1):
        t = (f - 1) / cyc * 2 * math.pi
        sec = (f - 1) / FPS
        lift, droop = 0.0, 0.0
        if clip in ("idle", "stand", "block"):
            amp, base = IDLE_AMP, t * max(1, round(cyc / IDLE_PERIOD))
        elif clip == "walk":
            amp, base = WALK_AMP, t + phase + math.pi
        elif clip == "run":
            amp, base, lift = RUN_AMP, t + phase + math.pi, RUN_LIFT
        elif clip == "start":
            amp, base = WALK_AMP * env(f, 6, n * 0.6), 2 * math.pi * sec / STRIDE
        elif clip == "stop":
            amp, base = WALK_AMP * env(f, n * 0.55, n - 2), 2 * math.pi * sec / STRIDE
        elif clip in ("lane", "turn_90", "turn_180"):
            amp, base = 0.7 * env(f, 1, 6) * env(f, n, n - 8), 2 * math.pi * sec / STRIDE
        elif clip.startswith("charge_"):
            k = env(f, contact + CHARGE_SETTLE * FPS, contact)
            amp, base, lift = 0.3 + (RUN_AMP - 0.3) * k, 2 * math.pi * sec / RUN_STRIDE, RUN_LIFT * k * env(f, 1, 8)
        elif clip == "death":
            amp, base = IDLE_AMP * env(f, 30, 8), 2 * math.pi * sec / 1.6
            droop = DEATH_DROOP * env(f, 20, 60)
        else:
            amp, base = 0.3 * env(f, n, n - 8), 2 * math.pi * sec / 1.6
        for i, nme in enumerate(TAIL):
            ang = amp * TAIL_AMP[i] * math.sin(base - i * TAIL_LAG)
            if clip in ("attack", "attack_stab", "attack_thrust", "hit", "block_hit", "death") or clip.startswith("charge_"):
                lagf = max(0, f - 1 - 3 * (i + 1))
                d = math.degrees(yaw[f - 1] - yaw[lagf]) * DRAG    # held back: + is towards +X
                ang += max(-DRAG_MAX, min(DRAG_MAX, d)) * (1 if i == 0 else 0.5)
            q = Quaternion((0, 0, 1), math.radians(ang * SSIGN))
            up = (lift if i == 0 else lift * 0.15) - droop / len(TAIL)
            if up:
                q = Quaternion(lift_axis(nme), math.radians(up)) @ q
            key(act, nme, f, q)


def panel_keys(act, n, th):
    for f in range(1, n + 1):
        p = {s: pitch(th[f - 1][s]) - pitch(THIGH0[s]) for s in th[f - 1]}
        fwd = max(0.0, min(PANEL_FWD, max(p.values())))
        back = max(0.0, min(PANEL_BACK, -min(p.values())))
        key(act, "TabardF", f, world_rot("TabardF", (1, 0, 0), -fwd))
        key(act, "TabardB", f, world_rot("TabardB", (1, 0, 0), back))
        for side, s in (("Left", "L"), ("Right", "R")):
            swing = THIGH0[side].rotation_difference(th[f - 1][side])
            S = Quaternion().slerp(swing, TASSET_FOLLOW)
            R = rest_frame(f"Tasset.{s}").to_quaternion()
            key(act, f"Tasset.{s}", f, R.inverted() @ S @ R)


def turn_bone(pb, q):
    """Turn a posed bone about its head by q (armature space)."""
    head = pb.head.copy()
    pb.matrix = Matrix.Translation(head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head) @ pb.matrix
    pb.location = Vector()                 # only its turn is keyed: no stray offset or scale
    pb.scale = Vector((1, 1, 1))
    bpy.context.view_layer.update()


def drape(act, n):
    """Death: lay the tail on the ground beside his legs once he is down."""
    rig.animation_data.action = act
    P = rig.pose.bones
    for f in range(1, n + 1):
        w = env(f, *DRAPE_IN)
        if w <= 0:
            continue
        sc.frame_set(f)
        legs = (P["mixamorig:LeftFoot"].head + P["mixamorig:RightFoot"].head) / 2 - P["mixamorig:Hips"].head
        legs.z = 0
        right = P["mixamorig:Hips"].matrix.to_3x3() @ Vector((-1, 0, 0))
        side = max((Quaternion((0, 0, 1), math.radians(a)) @ legs.normalized() for a in (DRAPE_SIDE, -DRAPE_SIDE)),
                   key=lambda g: g.dot(right))
        for i, nme in enumerate(TAIL):
            pb = P[nme]
            aim = (side + Vector((0, 0, -DRAPE_DOWN[i]))).normalized()
            turn_bone(pb, Quaternion().slerp((pb.tail - pb.head).normalized().rotation_difference(aim), w))
            pb.keyframe_insert("rotation_quaternion", frame=f)


def ground_level():
    """His soles' height on idle's first frame: the ground the export stands him on."""
    rig.animation_data.action = bpy.data.actions["idle"]
    sc.frame_set(1)
    ev = bpy.data.objects["Collie"].evaluated_get(bpy.context.evaluated_depsgraph_get())
    m = ev.to_mesh()
    z = min(v.co.z for v in m.vertices)
    ev.to_mesh_clear()
    return z


def tail_points():
    ev = bpy.data.objects["Tail"].evaluated_get(bpy.context.evaluated_depsgraph_get())
    m = ev.to_mesh()
    co = np.empty(len(m.vertices) * 3)
    m.vertices.foreach_get("co", co)
    ev.to_mesh_clear()
    M = np.array(bpy.data.objects["Tail"].matrix_world)
    return co.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]


def ground_clamp(act, n, floor):
    """Turn up, root first, any tail bone whose part of the tail dips under the ground."""
    rig.animation_data.action = act
    fixed = 0
    for f in range(1, n + 1):
        sc.frame_set(f)
        if tail_points()[:, 2].min() > floor + GROUND_TAIL:
            continue
        for nme in TAIL:
            pb = rig.pose.bones[nme]
            for _ in range(12):
                low = min((rig.matrix_world @ rig.pose.bones[k].tail).z for k in TAIL[TAIL.index(nme):])
                if low > floor + GROUND_TAIL + 0.04:
                    break
                ax = (pb.tail - pb.head).normalized().cross(Vector((0, 0, 1)))
                if ax.length < 1e-6:
                    break
                turn_bone(pb, Quaternion(ax.normalized(), math.radians(8)))
            pb.keyframe_insert("rotation_quaternion", frame=f)
        fixed += 1
    return fixed


floor = ground_level()
for clip in only:
    act = bpy.data.actions[clip]
    n = int(act["frames"])
    phase, yaw, th = sample(act, n)
    rig.animation_data.action = act
    tail_keys(clip, act, n, phase, yaw)
    panel_keys(act, n, th)
    if clip == "death":
        drape(act, n)
    fixed = ground_clamp(act, n, floor)
    for fc in fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    act["motion"] = "collie_motion.py"
    print("MOTION", clip, n, "frames, hip sway phase %.2f, tail sign %+d, ground fixes %d" % (phase, SSIGN, fixed))
rig.animation_data.action = bpy.data.actions.get("idle")
bpy.ops.wm.save_mainfile(compress=True)
print("MOTION_SAVED", bpy.data.filepath, "ground %.3f" % floor)
