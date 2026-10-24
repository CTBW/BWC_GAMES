"""Tail, wing and loincloth motion on the succubus clips (background Blender).

  blender -b succubus_anim.blend --python secondary_motion.py -- [clip,clip...] [poses <out dir>]

Overwrites the keys of the tail, wing and loincloth bones in each clip (retarget_clips.py leaves them
at rest). Values from the reference analysis of 23 Oct 2026 (review/motion_reference.md):

Wings. The reference keeps its wings folded while walking: the wrist claws up by the ears,
the membrane hanging behind. At idle they are half spread. FOLD turns the fingers in
alongside the wing's arm; HALF is part of the way from the spread rest pose to FOLD.
  walk:   a bob once per step, lowest at foot contact (about 2.5 degrees at the root, the
          fingers half as much again, no lag), and a sideways swing once per stride (about
          5 degrees at the root, the folded edge about 9), opposite to her hips' sway.
  idle:   (and the idle flourish) a slow open and close, a whole number of times per
          clip, near IDLE_PERIOD (the reference 1.75 s), about
          3 degrees at the root and 2.5 and 2 further out, each 28 degrees later.
  attack: they flare open towards HALF round the strike; hit: a short flare, settling.
  death:  from HALF they open fully as she falls back and sweep forward, so they lie open
          beside her; the tail's sway dies out and it is dragged by her hips. Afterwards a
          ground pass turns up any tail bone or lifts any wing that would go under the ground.
Tail. The reference wags once a second, the whole tail about +-30 degrees at the tip; hers
swings once per stride (1.2 s, about 20 % slower), 9, 8, 7, 6, 5, 4 degrees per bone, each
22 degrees later than the one before (the reference shows no lag; the lag makes it flow),
opposite to her hips' sideways sway. Idle: a slow sway at 40 %. Starting and stopping
walking: the swing builds up and dies down. Attack and hit: the tail is dragged by the
turn of her hips. The last three bones curl the tip up 6 degrees each.
Loincloth (skipped on a rig built with LOINCLOTH=0). Off the legs; it swings forward with whichever thigh is
furthest forward, at most LOIN_FWD, never sideways and at most LOIN_BACK back, so it keeps
covering her; the lower parts trail behind.
poses: renders the spread, HALF and FOLD wing poses for review and stops.
"""
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
sc = bpy.context.scene
rig = bpy.data.objects["SuccubusRig"]
B = rig.data.bones
FPS = 30
TAIL = [f"Tail_{i}" for i in range(1, 7)]
TAIL_AMP = [9, 8, 7, 6, 5, 4]
TAIL_LAG = math.radians(22)
TAIL_CURL = 6.0
WALK_TAIL = 1.3                # walking sway, x TAIL_AMP (the tip about +-25 degrees)
DRAG, DRAG_MAX = 0.12, 12.0    # attack/hit: the tail follows the hips' turn, capped (degrees)
HALF = 0.45                    # idle wing pose: this far from spread to folded
IDLE_PERIOD = 55               # idle sway, frames (the reference 1.75 s = 52)
DEATH_UNSWEEP = 30.0           # death: wings swept forward as she lies on her back (degrees)
GROUND_TAIL, GROUND_WING = 0.03, 0.02   # lowest a tail bone's end / a wing's membrane may go
GROUND_LOIN = 0.03                      # lowest a loincloth bone's end may go
LOIN = [f"Loincloth_{i}" for i in range(1, 4)]
LOIN_FWD, LOIN_BACK = 75.0, 5.0         # how far the loincloth may swing forward / back (degrees)
LOIN_LAG = (0, 2, 4)                    # frames each lower part trails behind
LOIN_FOLLOW = (1.0, 0.3, 0.3)           # bend towards the late swing (follow-through)
# Folded: the finger chain turned to hang alongside the arm, down and back.
FOLD_FINGER = {"Left": Vector((0.18, 0.40, -0.90)), "Right": Vector((-0.18, 0.40, -0.90))}
FOLD_SWEEP = 15.0              # and the whole wing swept further back (degrees)


def rest_frame(name):
    return (rig.matrix_world.to_3x3() @ B[name].matrix_local.to_3x3()).normalized()


def world_rot(name, axis, deg):
    """A turn about a world axis, as a rotation in the bone's rest frame."""
    return Quaternion(rest_frame(name).inverted() @ Vector(axis).normalized(), math.radians(deg))


def wing_poses():
    """Rest-relative rotations of each wing's bones, folded."""
    P = {}
    for side, s in (("Left", 1), ("Right", -1)):
        root, w1, w2, w3 = (f"Wing{side}_{k}" for k in ("Root", "1", "2", "3"))
        sweep = world_rot(root, (0, 0, 1), s * FOLD_SWEEP)
        d0 = (B[w3].tail_local - B[w2].head_local).normalized()
        turn = d0.rotation_difference(FOLD_FINGER[side].normalized())
        P[root] = sweep
        P[w1] = Quaternion()
        P[w2] = Quaternion(rest_frame(w2).inverted() @ turn.axis, turn.angle)
        P[w3] = world_rot(w3, (0, 0, 1), s * 10)
    return P


FOLD = wing_poses()


def blend_pose(k):
    """Spread (k = 0) to folded (k = 1)."""
    return {n: Quaternion().slerp(q, k) for n, q in FOLD.items()}


def gait_phase(act, n):
    """Hips' sideways sway over the clip: its phase at the clip's (n-1)-frame cycle, and
    the frames where a foot is lowest (contacts)."""
    rig.animation_data.action = act
    xs, lz, rz = [], [], []
    for f in range(1, n + 1):
        sc.frame_set(f)
        xs.append((rig.matrix_world @ rig.pose.bones["mixamorig:Hips"].head).x)
        lz.append((rig.matrix_world @ rig.pose.bones["mixamorig:LeftFoot"].head).z)
        rz.append((rig.matrix_world @ rig.pose.bones["mixamorig:RightFoot"].head).z)
    t = np.arange(n) / (n - 1) * 2 * math.pi
    x = np.array(xs) - np.mean(xs)
    phase = math.atan2(float(np.sum(x * np.cos(t))), float(np.sum(x * np.sin(t))))   # x ~ sin(t + phase)
    return phase, np.array(lz), np.array(rz)


def hips_yaw(act, n):
    rig.animation_data.action = act
    ys = []
    for f in range(1, n + 1):
        sc.frame_set(f)
        m = (rig.matrix_world @ rig.pose.bones["mixamorig:Hips"].matrix).to_3x3()
        fwd = m @ Vector((0, 0, 1))   # the hips bone's Z points forward-ish; yaw of its projection
        ys.append(math.atan2(fwd.x, -fwd.y))
    return np.unwrap(np.array(ys))


def sway_sign():
    """Which way a turn about Tail_1's own Z swings the tail (+1: towards her left, +X)."""
    pb = rig.pose.bones["Tail_1"]
    pb.rotation_mode = "QUATERNION"
    keep = pb.rotation_quaternion.copy()
    rig.animation_data.action = None
    pb.rotation_quaternion = Quaternion((0, 0, 1), math.radians(10))
    bpy.context.view_layer.update()
    x1 = (rig.matrix_world @ rig.pose.bones["Tail_6"].tail).x
    pb.rotation_quaternion = Quaternion()
    bpy.context.view_layer.update()
    x0 = (rig.matrix_world @ rig.pose.bones["Tail_6"].tail).x
    pb.rotation_quaternion = keep
    return 1.0 if x1 > x0 else -1.0


def thigh_pitches(act, n):
    """Forward swing of each thigh against her hips, per frame (degrees, rest = 0):
    the knee's direction from the hip joint, in the hips' own frame."""
    rig.animation_data.action = None
    for b in rig.pose.bones:
        b.rotation_mode = "QUATERNION"
        b.rotation_quaternion = Quaternion()
        b.location = Vector()
    bpy.context.view_layer.update()

    def pitch(side):
        hb = rig.pose.bones["mixamorig:Hips"]
        delta = (hb.matrix.to_3x3() @ hb.bone.matrix_local.to_3x3().inverted())
        d = delta.inverted() @ (rig.pose.bones[f"mixamorig:{side}Leg"].head - rig.pose.bones[f"mixamorig:{side}UpLeg"].head)
        return math.degrees(math.atan2(-d.y, -d.z))     # forward (-Y) positive

    rest = {s_: pitch(s_) for s_ in ("Left", "Right")}
    rig.animation_data.action = act
    out = []
    for f in range(1, n + 1):
        sc.frame_set(f)
        out.append({s_: pitch(s_) - rest[s_] for s_ in ("Left", "Right")})
    return out


def key(act, name, frame, q):
    pb = rig.pose.bones[name]
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = q
    pb.keyframe_insert("rotation_quaternion", frame=frame)


def env(t, a, b):
    """0 before a, smooth to 1 at b (or 1 to 0 if a > b)."""
    if a > b:
        return 1 - env(t, b, a)
    k = min(1.0, max(0.0, (t - a) / (b - a)))
    return k * k * (3 - 2 * k)


def animate(clip):
    act = bpy.data.actions[clip]
    n = int(act["frames"])
    cyc = n - 1                       # loops: the last frame repeats the first
    phase, lz, rz = gait_phase(act, n)
    yaw = hips_yaw(act, n)
    ssign = sway_sign()
    rig.animation_data.action = act
    walking = clip in ("walk", "walk_start", "walk_stop")
    # the flourish (played now and then from idle) sways as idle does, a whole number of
    # times, so it starts and ends where the idle loop starts
    idle_like = clip in ("idle", "idle_flourish")
    idle_cycles = max(1, round(cyc / IDLE_PERIOD))   # whole sways per loop, so it loops
    # contacts: a foot at its lowest; the bob is lowest there (two per stride)
    for f in range(1, n + 1):
        t = (f - 1) / cyc * 2 * math.pi
        sec = (f - 1) / FPS
        # tail -------------------------------------------------------------------------
        if walking:
            amp = WALK_TAIL
            if clip == "walk_start":
                amp = WALK_TAIL * env(f, 8, n * 0.6)
            elif clip == "walk_stop":
                amp = WALK_TAIL * env(f, n * 0.55, n - 2)
            w_t = 2 * math.pi * sec / 1.2          # once per stride (the walk's cycle)
            base = w_t + phase + math.pi            # opposite to the hips' sway
            if clip == "walk":
                base = t + phase + math.pi
        elif idle_like:
            amp, base = 0.4, t * idle_cycles
        elif clip == "death":
            amp, base = 0.4 * env(f, 30, 8), 2 * math.pi * sec / 1.6    # dies out as she falls
        else:
            amp, base = 0.25, 2 * math.pi * sec / 1.6
        for i, nme in enumerate(TAIL):
            ang = amp * TAIL_AMP[i] * math.sin(base - i * TAIL_LAG)
            # dragged: each bone follows the hips' turn a few frames later
            if clip in ("attack", "hit", "death"):
                lagf = max(0, f - 1 - 3 * (i + 1))
                d = math.degrees(-(yaw[lagf] - yaw[0])) * DRAG
                ang += max(-DRAG_MAX, min(DRAG_MAX, d)) * (1 if i == 0 else 0.5)
            q = Quaternion((0, 0, 1), math.radians(ang * ssign))
            if i >= 3:
                q = Quaternion((1, 0, 0), math.radians(-TAIL_CURL)) @ q
            key(act, nme, f, q)
        # wings ------------------------------------------------------------------------
        if idle_like:
            k_fold = 1 - HALF
            pose = blend_pose(1 - HALF)
        else:
            k_fold = 1.0
            if clip == "attack":
                k_fold = 1.0 - 0.55 * math.exp(-((f - 42) / 18.0) ** 2)
            elif clip == "hit":
                k_fold = 1.0 - 0.4 * math.exp(-((f - 12) / 8.0) ** 2)
            elif clip == "death":
                k_fold = (1 - HALF) * env(f, 70, 38)     # half spread, open fully as she falls
            pose = blend_pose(k_fold)
        for side, s in (("Left", 1), ("Right", -1)):
            root, w1, w2, w3 = (f"Wing{side}_{k}" for k in ("Root", "1", "2", "3"))
            extra = {root: Quaternion(), w1: Quaternion(), w2: Quaternion(), w3: Quaternion()}
            if idle_like:
                for j, (nme, a_) in enumerate(((root, 3.0), (w2, 2.5), (w3, 2.0))):
                    extra[nme] = world_rot(nme, (0, 0, 1), s * a_ * math.sin(t * idle_cycles - j * math.radians(28)))
            elif walking:
                amp = 1.0 if clip == "walk" else (env(f, 8, n * 0.6) if clip == "walk_start" else env(f, n * 0.55, n - 2))
                stride = (t if clip == "walk" else 2 * math.pi * sec / 1.2) + phase
                bob = math.cos(2 * stride)      # twice per stride, lowest at the contacts
                swing = -math.sin(stride)       # once per stride, opposite to the hips
                extra[root] = world_rot(root, (0, 1, 0), amp * (s * 2.5 * bob + 5.0 * swing))
                extra[w2] = world_rot(w2, (0, 1, 0), amp * (s * 3.75 * bob + 2.0 * swing))
                extra[w3] = world_rot(w3, (0, 1, 0), amp * 1.5 * swing)
            elif clip == "death":
                # lying on her back: swept forward out of their backward sweep, so they lie
                # open beside her instead of under her
                extra[root] = world_rot(root, (0, 0, 1), -s * DEATH_UNSWEEP * env(f, 45, 75))
            for nme in (root, w1, w2, w3):
                key(act, nme, f, extra[nme] @ pose[nme])
    # loincloth --------------------------------------------------------------------------
    # It rides over whichever thigh is furthest forward (so a striding leg never pushes
    # through it), never sideways and never far back: it keeps covering her. The lower
    # parts trail a few frames behind for a soft follow-through.
    th = thigh_pitches(act, n) if LOIN[0] in rig.pose.bones else []   # not on LOINCLOTH=0 rigs
    target = [max(-LOIN_BACK, min(LOIN_FWD, max(p["Left"], p["Right"]))) for p in th]
    rig.animation_data.action = act
    for f in range(1, n + 1 if th else 1):
        for i, nme in enumerate(LOIN):
            now = target[f - 1]
            late = target[max(0, f - 1 - LOIN_LAG[i])]
            ang = now if i == 0 else LOIN_FOLLOW[i] * (late - now)
            key(act, nme, f, world_rot(nme, (1, 0, 0), -ang))   # about her side axis; - = forward
    fixed = ground_clamp(act, n)
    for fc in getattr(act, "fcurves", []):
        if fc.data_path.startswith(('pose.bones["Tail', 'pose.bones["Wing', 'pose.bones["Loincloth')):
            for kp in fc.keyframe_points:
                kp.interpolation = "LINEAR"
    print("SECONDARY", clip, n, "frames, hip sway phase %.2f, tail sign %+d, ground fixes %d" % (phase, ssign, fixed))


def mesh_points(ob):
    """World positions of an object's evaluated (skinned) vertices."""
    ev = ob.evaluated_get(bpy.context.evaluated_depsgraph_get())
    m = ev.to_mesh()
    co = np.empty(len(m.vertices) * 3)
    m.vertices.foreach_get("co", co)
    ev.to_mesh_clear()
    M = np.array(ob.matrix_world)
    return co.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]


def lift_bone(pb, angle, axis):
    """Turn a pose bone about a world axis through its head (armature space, no scale)."""
    from mathutils import Matrix
    m = pb.matrix.copy()
    head = m.translation.copy()
    R = Matrix.Rotation(angle, 4, rig.matrix_world.to_3x3().inverted() @ axis)
    pb.matrix = Matrix.Translation(head) @ R @ Matrix.Translation(-head) @ m
    bpy.context.view_layer.update()


def ground_clamp(act, n):
    """Keep the tail, the loincloth and the wings above the ground: a tail or loincloth
    bone whose end dips too low is turned up about the horizontal through its head just
    enough; a wing
    whose membrane dips below GROUND_WING is lifted at its root, a little at a time.
    Clips that never come near the ground keep their keys."""
    rig.animation_data.action = act
    tail_ob = bpy.data.objects["Tail"]
    wings = {"Left": bpy.data.objects["WingLeft"], "Right": bpy.data.objects["WingRight"]}
    fixed = 0
    loin = [nme for nme in LOIN if nme in rig.pose.bones]
    for f in range(1, n + 1):
        sc.frame_set(f)
        if mesh_points(tail_ob)[:, 2].min() > GROUND_TAIL and                 min(mesh_points(w)[:, 2].min() for w in wings.values()) > GROUND_WING and                 all((rig.matrix_world @ rig.pose.bones[nme].tail).z > GROUND_LOIN for nme in loin):
            continue
        for nme in TAIL + loin:
            pb = rig.pose.bones[nme]
            h, t_ = rig.matrix_world @ pb.head, rig.matrix_world @ pb.tail
            # the tail is about 6 cm thick round its bones; the loincloth is a thin panel
            need = (GROUND_TAIL + 0.03 if nme in TAIL else GROUND_LOIN) - t_.z
            if need > 0:
                d = (t_ - h).normalized()
                axis = d.cross(Vector((0, 0, 1)))
                if axis.length < 1e-4:
                    continue
                new_dz = max(-1.0, min(1.0, d.z + need / (t_ - h).length))
                lift_bone(pb, math.asin(new_dz) - math.asin(max(-1.0, min(1.0, d.z))), axis.normalized())
                fixed += 1
        for side, w in wings.items():
            root = rig.pose.bones[f"Wing{side}_Root"]
            for _ in range(8):
                z = mesh_points(w)[:, 2].min()
                if z > GROUND_WING:
                    break
                k = rig.matrix_world @ root.head
                span = (rig.matrix_world @ rig.pose.bones[f"Wing{side}_3"].tail) - k
                axis = span.cross(Vector((0, 0, 1)))
                if axis.length < 1e-4:
                    break
                lift_bone(root, (GROUND_WING - z + 0.01) / max(0.3, span.length), axis.normalized())
                fixed += 1
        for nme in TAIL + loin + [f"Wing{s_}_Root" for s_ in wings]:
            rig.pose.bones[nme].keyframe_insert("rotation_quaternion", frame=f)
    return fixed


if len(argv) > 1 and argv[1] == "poses":
    out = Path(argv[2])
    out.mkdir(parents=True, exist_ok=True)
    rig.animation_data.action = None
    for b in rig.pose.bones:
        b.rotation_mode = "QUATERNION"
        b.rotation_quaternion = Quaternion()
    # arms down, as in the clips
    for side, s in (("Left", 1), ("Right", -1)):
        pb = rig.pose.bones[f"mixamorig:{side}Arm"]
        pb.rotation_quaternion = world_rot(pb.name, (0, 1, 0), s * 65)
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light = "FLAT"; sh.color_type = "TEXTURE"; sh.show_object_outline = True
    sh.object_outline_color = (0.09, 0.07, 0.07)
    sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.18, 0.18, 0.2)
    cam_d = bpy.data.cameras.new("c"); cam_d.type = "ORTHO"; cam_d.ortho_scale = 2.8
    cam = bpy.data.objects.new("c", cam_d); sc.collection.objects.link(cam); sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = 520, 560
    for label, k in (("spread", 0.0), ("half", 1 - HALF), ("fold", 1.0)):
        for nme, q in blend_pose(k).items():
            rig.pose.bones[nme].rotation_quaternion = q
        bpy.context.view_layer.update()
        for view, az, el in (("front", 0, 0), ("side", 90, 0), ("back34", 150, 15), ("game", 45, 30)):
            a, e = math.radians(az), math.radians(el)
            d = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
            cam.location = Vector((0, 0.15, 1.05)) + d * 8
            cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
            sc.render.filepath = str(out / f"{label}_{view}.png")
            bpy.ops.render.render(write_still=True)
    print("POSES_DONE")
    sys.exit(0)

clips = argv[0].split(",") if argv and argv[0] else [a.name for a in bpy.data.actions if "frames" in a]
for c in clips:
    animate(c)
rig.animation_data.action = bpy.data.actions.get("idle")
bpy.ops.wm.save_mainfile(compress=True)
print("SECONDARY_SAVED", bpy.data.filepath)
