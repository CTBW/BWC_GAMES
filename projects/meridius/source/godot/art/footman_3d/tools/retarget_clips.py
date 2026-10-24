"""Retarget Mixamo FBX clips onto the footman rig (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python retarget_clips.py -- [animations dir] [clip,clip...]

The Mixamo FBX files live in projects/meridius/Animations/ (gitignored: never
commit them); an empty first argument means that folder.

Each clip is its own action on FootmanRig (fake user, so the .blend keeps it).
Retarget by rest-pose difference, bone by bone in world space:
    R_target(t) = R_source(t) * R_source_rest^-1 * R_target_rest
so the target's bones turn exactly as the source's turn away from their own
T-pose, whatever their rolls. Converted to each bone's local rotation through
its parent's retargeted rotation (no depsgraph round trips). The hips' motion
is scaled by the hip-height ratio; loops are made in place (the drift between
their first and last frame is removed).

With "feet_ik", the ankles follow the source's own ankles instead (their path
from the clip's first frame, scaled by the same ratio, as the hips', from
where the turned legs put them on that frame: his legs are longer for his
height than the source's, so his own ground is not the source's) and the legs
are solved to reach them: for a wide stance, where the turned legs alone put
one foot through the ground and lift the other. Where a planted leg would
have to stretch past 99% of its length the hips sink until it reaches; a foot that
pushes off (5 cm up within 4 frames) leaves a little early instead.
Prints the largest miss and sink.
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

CLIPS = {
    "idle": ("Sword And Shield Idle.fbx", {"in_place": True}),
    "walk": ("Standing Walk Forward.fbx", {"in_place": True, "carry_guard": 0.85}),
    "attack": ("Sword And Shield Slash.fbx", {}),
    "block": ("Standing Block Idle.fbx", {"in_place": True}),
    "hit": ("Sword And Shield Impact defend.fbx", {}),
    "death": ("Sword And Shield Death.fbx", {}),
    "step_lane": ("Standing Walk Right.fbx", {"in_place": True, "carry_guard": 0.85}),
    "walk_spear": ("Walk - Spearmen.fbx", {"in_place": True, "carry_guard": 0.85}),
    "walk_xbow": ("Walk - Crossbowmen.fbx", {"in_place": True, "carry_guard": 0.85}),
    "turn_90": ("Turning - Footman.fbx", {"in_place": True}),
    "turn_180": ("Turning 180 degress - Footman.fbx", {"in_place": True}),
    # The charge's run (shield_charge: at least 2 tiles, then the attack).
    "run": ("Run - Footman*.fbx", {"in_place": True, "carry_guard": 0.85}),
    # The second attack: a thrust, sometimes played instead of the slash, and
    # the charge's strike off the right foot.
    "stab": ("Stab - Footmen.fbx", {}),
    # A lunge that steps in on the right foot: the charge's strike off the
    # right (charge_thrust), half a stride after the slash's. Its 1.9 m step
    # puts the front foot 8.6 cm into the ground with the legs' turns alone.
    "thrust": ("Attack thrust - Footmen.fbx", {"feet_ik": True}),
    # Keeps its travel: the hips carry him forward as he slows. The source of
    # the stop and start steps (make_transitions.py builds them from it).
    "stop_src": ("Stop Walking - Footmen.fbx", {}),
}

argv = sys.argv[sys.argv.index("--") + 1:]
# tools -> footman_3d -> art -> godot -> source -> meridius
anim_dir = Path(argv[0]) if argv and argv[0] else Path(__file__).resolve().parents[5] / "Animations"
only = argv[1].split(",") if len(argv) > 1 and argv[1] else list(CLIPS)
sc = bpy.context.scene
sc.render.fps = 30
rig = bpy.data.objects["FootmanRig"]
names = [b.name for b in rig.data.bones]
order = []  # parents first
def visit(b):
    order.append(b.name)
    for c in b.children:
        visit(c)
for b in rig.data.bones:
    if b.parent is None:
        visit(b)

LOCK = [Quaternion(rig["left_hand_lock"]) if "left_hand_lock" in rig else None]
GUARD_BONES = ("mixamorig:LeftShoulder", "mixamorig:LeftArm", "mixamorig:LeftForeArm")
T_rest = {n: (rig.matrix_world.to_3x3() @ rig.data.bones[n].matrix_local.to_3x3()).normalized() for n in names}
T_head = {n: rig.matrix_world @ rig.data.bones[n].head_local for n in names}
FEET = ("mixamorig:LeftFoot", "mixamorig:RightFoot")


def ik_leg(side, want):
    """Two-bone IK (as make_transitions.py): the ankle onto `want` (armature
    space), the knee kept in its bend plane, the foot keeping its world turn."""
    P = rig.pose.bones
    up, lo, ft = P["mixamorig:%sUpLeg" % side], P["mixamorig:%sLeg" % side], P["mixamorig:%sFoot" % side]
    foot_rot = ft.matrix.to_quaternion()
    hip = up.head.copy()
    knee = lo.head.copy()
    l1 = (knee - hip).length
    l2 = (ft.head - knee).length
    d = want - hip
    dist = min(max(d.length, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
    dn = d.normalized()
    pole = (knee - hip) - dn * (knee - hip).dot(dn)
    pole = pole.normalized() if pole.length > 1e-6 else Vector((0, -1, 0))
    a = (l1 * l1 + dist * dist - l2 * l2) / (2 * dist)
    h = math.sqrt(max(0.0, l1 * l1 - a * a))
    knee_new = hip + dn * a + pole * h
    q1 = (knee - hip).rotation_difference(knee_new - hip)
    m = (q1.to_matrix() @ up.matrix.to_3x3()).to_4x4()
    m.translation = hip
    up.matrix = m
    up.scale = (1.0, 1.0, 1.0)  # a shear leaves scale on the bone; no clip keys it, so it would hold in every clip
    bpy.context.view_layer.update()
    knee_now = lo.head.copy()
    q2 = (ft.head - knee_now).rotation_difference(hip + dn * dist - knee_now)
    m = (q2.to_matrix() @ lo.matrix.to_3x3()).to_4x4()
    m.translation = knee_now
    lo.matrix = m
    lo.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()
    m = foot_rot.to_matrix().to_4x4()
    m.translation = ft.head.copy()
    ft.matrix = m
    ft.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()
    return (ft.head - want).length


def sink_for(side, want, k=0.99):
    """How far the hips must drop for a leg to reach `want` at k of its length."""
    P = rig.pose.bones
    hip = P["mixamorig:%sUpLeg" % side].head
    knee = P["mixamorig:%sLeg" % side].head
    reach = k * ((knee - hip).length + (P["mixamorig:%sFoot" % side].head - knee).length)
    d = want - hip
    hd = Vector((d.x, d.y)).length
    if hd >= reach:
        return 0.0
    return max(0.0, -d.z - math.sqrt(reach * reach - hd * hd))

for clip in only:
    fbx, opt = CLIPS[clip]
    before = set(bpy.data.objects)
    acts_before = set(bpy.data.actions)
    if "*" in fbx:
        found = sorted(anim_dir.glob(fbx), key=lambda q: (len(q.name), q.name))
        if not found:
            print("RETARGET_SKIP", clip, "no file matches", fbx)
            continue
        fbx = found[0].name
    bpy.ops.import_scene.fbx(filepath=str(anim_dir / fbx))
    new_objs = [o for o in bpy.data.objects if o not in before]
    src = next(o for o in new_objs if o.type == "ARMATURE")
    sact = src.animation_data.action
    f0, f1 = (int(round(v)) for v in sact.frame_range)
    smw = src.matrix_world
    S_rest = {}
    for n in names:
        sb = src.data.bones.get(n)
        if sb is not None:
            S_rest[n] = (smw.to_3x3() @ sb.matrix_local.to_3x3()).normalized()
    s_hips_rest = smw @ src.data.bones["mixamorig:Hips"].head_local
    ratio = T_head["mixamorig:Hips"].z / s_hips_rest.z
    # Sample the source.
    frames = list(range(f0, f1 + 1))
    samples = []
    for f in frames:
        sc.frame_set(f)
        R = {}
        for n in names:
            if n in S_rest:
                R[n] = (smw.to_3x3() @ src.pose.bones[n].matrix.to_3x3()).normalized()
        hips = smw @ src.pose.bones["mixamorig:Hips"].head
        samples.append((R, hips.copy(), {n: (smw @ src.pose.bones[n].head).copy() for n in FEET}))
    drift = samples[-1][1] - samples[0][1] if opt.get("in_place") else Vector()
    drift.z = 0.0
    # Write the target action (replacing an earlier take of the same clip).
    for a in [a for a in bpy.data.actions if a.name == clip or (a.name.startswith(clip + ".") and a.name[len(clip) + 1:].isdigit())]:
        bpy.data.actions.remove(a)
    act = bpy.data.actions.new(clip)
    act.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = act
    prev_q = {}
    STEADY = {}
    for i, (f, (R, hips, _feet)) in enumerate(zip(frames, samples)):
        u = i / max(1, len(frames) - 1)
        Rt = {}
        for n in order:
            pb = rig.pose.bones[n]
            pb.rotation_mode = "QUATERNION"
            if n in R:
                Rt[n] = R[n] @ S_rest[n].inverted() @ T_rest[n]
            else:
                par = rig.data.bones[n].parent
                Rt[n] = (Rt[par.name] @ T_rest[par.name].inverted() @ T_rest[n]) if par else T_rest[n]
            par = rig.data.bones[n].parent
            if par is None:
                basis = T_rest[n].inverted() @ Rt[n]
            else:
                restrel = T_rest[par.name].inverted() @ T_rest[n]
                basis = restrel.inverted() @ Rt[par.name].inverted() @ Rt[n]
            q = basis.to_quaternion()
            if n in GUARD_BONES:
                # The shield arm in guard: idle's first pose is stored, and the
                # march carries the shield in it, riding with the torso.
                if clip == "idle" and i == 0:
                    rig["guard_" + n.split(":")[1]] = list(q)
                k_g = opt.get("carry_guard", 0.0)
                key = "guard_" + n.split(":")[1]
                if k_g and key in rig:
                    g = Quaternion(rig[key])
                    g.make_compatible(q)
                    q = q.slerp(g, k_g)
            if n == "mixamorig:LeftHand":
                # The shield is strapped to the forearm: the wrist holds the
                # guard's angle in every clip, so the shield turns only with the
                # forearm and the fist stays on its handle.
                if LOCK[0] is None and clip == "idle" and i == 0:
                    LOCK[0] = q.copy()
                    rig["left_hand_lock"] = list(q)
                if LOCK[0] is not None:
                    q = LOCK[0].copy()
            if n in prev_q:
                q.make_compatible(prev_q[n])
            prev_q[n] = q
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=f - f0 + 1)
        hb = rig.pose.bones["mixamorig:Hips"]
        want = T_head["mixamorig:Hips"] + (hips - s_hips_rest - drift * u) * ratio
        hb.location = T_rest["mixamorig:Hips"].inverted() @ (want - T_head["mixamorig:Hips"])
        hb.keyframe_insert("location", frame=f - f0 + 1)
    if opt.get("feet_ik"):
        # The ankles on the source's paths (world = armature space here: the rig
        # stands at the origin, unturned), the legs solved to reach them.
        miss = deep = 0.0
        sinks = []
        sc.frame_set(1)
        fk0 = {n: rig.pose.bones[n].head.copy() for n in FEET}
        hb = rig.pose.bones["mixamorig:Hips"]
        to_rig = rig.matrix_world.inverted().to_3x3()
        W = [{n: fk0[n] + to_rig @ ((feet[n] - samples[0][2][n] - drift * (i / max(1, len(frames) - 1))) * ratio) for n in FEET}
             for i, (R, hips, feet) in enumerate(samples)]
        for i, f in enumerate(frames):
            sc.frame_set(f - f0 + 1)
            want = W[i]
            drop = 0.0
            for n in FEET:
                # Planted: within 2 cm of its first-frame height over the next 4 frames, fading out by 5 cm.
                up = max(W[k][n].z for k in range(i, min(len(W), i + 5))) - fk0[n].z
                drop = max(drop, sink_for(n.split(":")[1][:-4], want[n]) * (1.0 - min(1.0, max(0.0, (up - 0.02) / 0.03))))
            sinks.append(drop)
            if drop > 0.0:
                hm = hb.matrix.copy()
                hm.translation.z -= drop
                hb.matrix = hm
                hb.scale = (1.0, 1.0, 1.0)
                bpy.context.view_layer.update()
                hb.keyframe_insert("location", frame=f - f0 + 1)
                deep = max(deep, drop)
            for n in FEET:
                miss = max(miss, ik_leg(n.split(":")[1][:-4], want[n]))
            for side in ("Left", "Right"):
                for part in ("UpLeg", "Leg", "Foot"):
                    pb = rig.pose.bones["mixamorig:%s%s" % (side, part)]
                    pb.keyframe_insert("rotation_quaternion", frame=f - f0 + 1)
        print("RETARGET_SINK cm", " ".join("%d:%.0f" % (k + 1, 100 * d) for k, d in enumerate(sinks) if d > 0.005))
        print("RETARGET_FEET %s: ankles on the source's paths, largest miss %.1f cm, hips sunk up to %.1f cm" % (clip, 100 * miss, 100 * deep))
    for fc in act.fcurves if hasattr(act, "fcurves") else []:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    act["source"] = fbx
    act["frames"] = len(frames)
    if opt.get("in_place"):
        # The ground speed the steps were made for (rig space, m/s): the game
        # moves the unit at this speed so planted feet stay put; previews use it too.
        dur = max(1, len(frames) - 1) / 30.0
        act["root_vel"] = [drift.x * ratio / dur, drift.y * ratio / dur]
    # Remove what the import brought in.
    for o in new_objs:
        bpy.data.objects.remove(o, do_unlink=True)
    for a in set(bpy.data.actions) - acts_before:
        if a is not act:
            bpy.data.actions.remove(a)
    print("RETARGET", clip, fbx, len(frames), "frames, hip ratio %.3f" % ratio)
rig.animation_data.action = bpy.data.actions.get("idle") or rig.animation_data.action
sc.frame_start = 1
sc.frame_end = int(rig.animation_data.action["frames"])
bpy.ops.wm.save_mainfile(compress=True)
print("RETARGET_SAVED", bpy.data.filepath)
