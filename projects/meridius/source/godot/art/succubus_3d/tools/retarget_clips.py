"""Retarget Mixamo FBX clips onto the succubus rig (background Blender).

  blender -b succubus_rig.blend --python retarget_clips.py -- <animations dir> [out.blend] [clip,clip...]

Same method as spearman_3d/tools/retarget_clips.py (rest-pose difference bone by bone in
world space, the hips' motion scaled by the hip-height ratio), with one change: her rest
pose stands wide (the legs splay about 12 degrees) and her paws turn out 18 degrees, so each
bone is first turned from her rest direction onto the source's rest direction,
    R_target(t) = R_source(t) * R_source_rest^-1 * A * R_target_rest,
A the shortest turn between the two rest directions. Without it she would walk with her
rest splay. Bones that are not in the source (tail, wings, whip grip, forearm twists) keep
their rest pose relative to their parents; secondary_motion.py animates the tail and wings.
Options per clip:
  range      (first, last) source frames to keep
  in_place   remove the drift between the first and last frame (loops)
  loop_blend ease the last N frames back to the first pose so the loop has no pop
  blend_in   (clip, n): start from that clip's first pose and ease into this one over n frames
  blend_out  (clip, n): ease back into that clip's first pose over the last n frames
  yaw        turn the whole clip about the vertical (degrees, + = to her left)
  loop       override the loop flag (in_place and loop_blend otherwise mark a loop)
  ground     lift the hips wherever her skinned body dips below the ground, smoothed (the
             death sank her 15-27 cm in: she is bulkier than Mixamo's mannequin); the paws
             may still sink GROUND_PAW_SINK
  mirror     left for right: each bone takes its mirror twin's motion, mirrored across her
             middle (the kiss: the source blows it with the left hand, her whip hand)
  retime     ((frame, source frame), ...): the clip's frames sampled from the source at
             those times, linearly between them (fractions allowed)
  lower      a clip name: her hips and legs held in its first pose for the whole clip, the
             rest following the source in world space (feet planted, no slide)
  local      built only when named on the command line, never by default: the clip goes
             into a local blend, not succubus_anim.blend (see README, Sovereign Kiss)
Clips that keep their travel (walk_start, walk_stop) store it in the hips' location.
"""
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

GROUND_PAW_Z = 0.15        # rest height below which vertices belong to the paws
GROUND_PAW_SINK = 0.02     # how far the paws may roll into the ground

CLIPS = {
    # Her standing idle (added 24 Oct 2026) loops; the bending idle that came first is now
    # a one-off flourish, played now and then from idle (per unit, at random intervals),
    # easing out of and back into the standing idle's first pose.
    "idle": ("Idle standing - Succubus-German Shepherd.fbx", {"in_place": True, "loop_blend": 15}),
    "idle_flourish": ("Idle - Succubus-German Shepherd.fbx",
                      {"in_place": True, "blend_in": ("idle", 12), "blend_out": ("idle", 15), "loop": False}),
    # Her hit stands turned to her right (hips about 41 degrees, shoulders 35): turned back.
    "walk": ("Walking - Succubus-German Shepherd.fbx", {"in_place": True}),
    "walk_start": ("Start Walking - Succubus-German Shepherd.fbx", {}),
    "walk_stop": ("Stop Walking - Succubus-German Shepherd.fbx", {}),
    "attack": ("Attack - Succubus-German Shepherd.fbx", {}),
    "hit": ("Hit - Succubus-German Shepherd.fbx", {"blend_in": ("idle", 8), "blend_out": ("idle", 10), "yaw": 38}),
    "death": ("Death - Succubus-German Shepherd.fbx", {"blend_in": ("idle", 8), "ground": True}),
    # The Sovereign Kiss cast (26 Oct 2026). The source blows the kiss with her left hand;
    # the handoff wants the free right one, so it is mirrored. sovereign_kiss is retimed to
    # the handoff's beats (48 frames: hand up 1-12, at the lips 13-21, kiss_release at 22,
    # open palm 29-36, back to idle by 48); sovereign_kiss_source keeps the source's own
    # timing (the hand leaves the lips at source frame 60), for comparison.
    "sovereign_kiss": ("Blow A Kiss - Succubus-German Shepherd girl.fbx",
                       {"mirror": True, "lower": "idle", "blend_in": ("idle", 8), "blend_out": ("idle", 10),
                        "retime": ((1, 7), (12, 28), (18, 37), (21, 40), (22, 60), (28, 72), (36, 85), (48, 119)),
                        "loop": False, "local": True}),
    "sovereign_kiss_source": ("Blow A Kiss - Succubus-German Shepherd girl.fbx",
                              {"mirror": True, "lower": "idle", "blend_in": ("idle", 8), "blend_out": ("idle", 10),
                               "range": (7, 125), "loop": False, "local": True}),
}
MIRROR = Matrix.Scale(-1, 3, (1, 0, 0))

argv = sys.argv[sys.argv.index("--") + 1:]
anim_dir = Path(argv[0])
out_blend = Path(argv[1]) if len(argv) > 1 and argv[1] else None
only = argv[2].split(",") if len(argv) > 2 and argv[2] else [c for c in CLIPS if not CLIPS[c][1].get("local")]
sc = bpy.context.scene
sc.render.fps = 30
rig = bpy.data.objects["SuccubusRig"]
names = [b.name for b in rig.data.bones]
order = []  # parents first


def visit(b):
    order.append(b.name)
    for c in b.children:
        visit(c)


for b in rig.data.bones:
    if b.parent is None:
        visit(b)

def ground_lift(n):
    """Per frame of the rig's current action: how far to raise the hips so the skinned body
    stays on the ground; widened by two frames each way and then averaged, so the lift
    never pops."""
    body = bpy.data.objects["Succubus"]
    me = body.data
    rest = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", rest)
    floor = np.where(rest[2::3] < GROUND_PAW_Z, -GROUND_PAW_SINK, 0.0)
    need = []
    for f in range(1, n + 1):
        sc.frame_set(f)
        ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
        m = ev.to_mesh()
        co = np.empty(len(m.vertices) * 3)
        m.vertices.foreach_get("co", co)
        ev.to_mesh_clear()
        need.append(max(0.0, float(np.max(floor - co[2::3]))))
    wide = [max(need[max(0, i - 2):i + 3]) for i in range(n)]
    return [sum(wide[max(0, i - 2):i + 3]) / len(wide[max(0, i - 2):i + 3]) for i in range(n)]


T_rest = {n: (rig.matrix_world.to_3x3() @ rig.data.bones[n].matrix_local.to_3x3()).normalized() for n in names}
T_head = {n: rig.matrix_world @ rig.data.bones[n].head_local for n in names}
T_dir = {n: (T_rest[n] @ Vector((0, 1, 0))).normalized() for n in names}

for clip in only:
    fbx, opt = CLIPS[clip]
    before = set(bpy.data.objects)
    acts_before = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=str(anim_dir / fbx))
    new_objs = [o for o in bpy.data.objects if o not in before]
    src = next(o for o in new_objs if o.type == "ARMATURE")
    sact = src.animation_data.action
    f0, f1 = (int(round(v)) for v in sact.frame_range)
    if "range" in opt:
        f0, f1 = max(f0, opt["range"][0]), min(f1, opt["range"][1])
    smw = src.matrix_world
    S_rest = {n: (smw.to_3x3() @ src.data.bones[n].matrix_local.to_3x3()).normalized()
              for n in names if src.data.bones.get(n) is not None}
    # A: her rest direction onto the source's (the shortest turn)
    A = {n: T_dir[n].rotation_difference((S_rest[n] @ Vector((0, 1, 0))).normalized()).to_matrix() for n in S_rest}
    s_hips_rest = smw @ src.data.bones["mixamorig:Hips"].head_local
    ratio = T_head["mixamorig:Hips"].z / s_hips_rest.z
    frames = list(range(f0, f1 + 1))
    if "retime" in opt:
        tk = opt["retime"]
        frames = [float(np.interp(i, [a for a, _ in tk], [b for _, b in tk])) for i in range(tk[0][0], tk[-1][0] + 1)]
        f0, f1 = tk[0][1], tk[-1][1]
    twin = (lambda n: n.replace("Left", "\0").replace("Right", "Left").replace("\0", "Right")) if opt.get("mirror") else (lambda n: n)
    if opt.get("mirror"):
        s_hips_rest = MIRROR @ s_hips_rest
    samples = []
    for f in frames:
        sc.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
        # each bone's turn from its rest pose, in world space (mirrored: its twin's, mirrored)
        D = {n: (smw.to_3x3() @ src.pose.bones[twin(n)].matrix.to_3x3()).normalized() @ S_rest[twin(n)].inverted()
             for n in names if n in S_rest and twin(n) in S_rest}
        h = (smw @ src.pose.bones["mixamorig:Hips"].head).copy()
        if opt.get("mirror"):
            D = {n: MIRROR @ d @ MIRROR for n, d in D.items()}
            h = MIRROR @ h
        samples.append((D, h))
    drift = samples[-1][1] - samples[0][1] if opt.get("in_place") else Vector()
    drift.z = 0.0
    held = {}
    if opt.get("lower") in bpy.data.actions:
        # her hips and legs as in that clip's first frame (world rotations), the hips there too
        rig.animation_data_create()
        rig.animation_data.action = bpy.data.actions[opt["lower"]]
        sc.frame_set(1)
        held = {n: (rig.matrix_world.to_3x3() @ rig.pose.bones[n].matrix.to_3x3()).normalized() for n in names
                if n == "mixamorig:Hips" or any(k in n for k in ("UpLeg", "Leg", "Foot", "Toe"))}
        held_h = T_rest["mixamorig:Hips"] @ rig.pose.bones["mixamorig:Hips"].location
    local = []
    for R, _ in samples:
        Rt, q_of = {}, {}
        for n in order:
            par = rig.data.bones[n].parent
            if n in held:
                Rt[n] = held[n]
            elif n in R:
                Rt[n] = R[n] @ A[n] @ T_rest[n]
            else:
                Rt[n] = (Rt[par.name] @ T_rest[par.name].inverted() @ T_rest[n]) if par else T_rest[n]
            if par is None:
                basis = T_rest[n].inverted() @ Rt[n]
            else:
                basis = (T_rest[par.name].inverted() @ T_rest[n]).inverted() @ Rt[par.name].inverted() @ Rt[n]
            q_of[n] = basis.to_quaternion()
        local.append(q_of)
    hips_off = [(h - s_hips_rest - drift * (i / max(1, len(frames) - 1))) * ratio for i, (_, h) in enumerate(samples)]
    if held:
        hips_off = [held_h.copy() for _ in samples]
    if opt.get("yaw"):
        Rz = Matrix.Rotation(math.radians(opt["yaw"]), 3, "Z")
        hn = "mixamorig:Hips"
        for i in range(len(local)):
            Rw = T_rest[hn] @ local[i][hn].to_matrix()        # the hips' world rotation
            local[i][hn] = (T_rest[hn].inverted() @ Rz @ Rw).to_quaternion()
            hips_off[i] = Rz @ hips_off[i]
    nb = opt.get("loop_blend", 0)
    if nb:
        n_fr = len(frames)
        for k in range(nb):
            i = n_fr - nb + k
            w = (k + 1) / nb
            w = w * w * (3 - 2 * w)
            for n in order:
                a, b = local[i][n], local[0][n].copy()
                b.make_compatible(a)
                local[i][n] = a.slerp(b, w)
            hips_off[i] = hips_off[i].lerp(hips_off[0], w)
    smooth = lambda w: w * w * (3 - 2 * w)
    for key, at_start in (("blend_in", True), ("blend_out", False)):
        if key not in opt or opt[key][0] not in bpy.data.actions:
            continue
        ref_name, nbl = opt[key]
        rig.animation_data_create()
        rig.animation_data.action = bpy.data.actions[ref_name]
        sc.frame_set(1)
        ref_q = {n: rig.pose.bones[n].rotation_quaternion.copy() for n in order}
        ref_h = T_rest["mixamorig:Hips"] @ rig.pose.bones["mixamorig:Hips"].location
        for k in range(min(nbl, len(local))):
            i = k if at_start else len(local) - 1 - k
            w = smooth(1.0 - (k + 1) / (nbl + 1))
            for n in order:
                b = ref_q[n].copy()
                b.make_compatible(local[i][n])
                local[i][n] = local[i][n].slerp(b, w)
            hips_off[i] = hips_off[i].lerp(ref_h, w)
    for a in [a for a in bpy.data.actions if a.name == clip or (a.name.startswith(clip + ".") and a.name[len(clip) + 1:].isdigit())]:
        bpy.data.actions.remove(a)
    act = bpy.data.actions.new(clip)
    act.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = act
    prev_q = {}
    for i, f in enumerate(frames):
        for n in order:
            pb = rig.pose.bones[n]
            pb.rotation_mode = "QUATERNION"
            q = local[i][n]
            if n in prev_q:
                q.make_compatible(prev_q[n])
            prev_q[n] = q
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=i + 1)
        hb = rig.pose.bones["mixamorig:Hips"]
        hb.location = T_rest["mixamorig:Hips"].inverted() @ hips_off[i]
        hb.keyframe_insert("location", frame=i + 1)
    if opt.get("ground"):
        lift = ground_lift(len(frames))
        hb = rig.pose.bones["mixamorig:Hips"]
        for i in range(len(frames)):
            hb.location = T_rest["mixamorig:Hips"].inverted() @ (hips_off[i] + Vector((0, 0, lift[i])))
            hb.keyframe_insert("location", frame=i + 1)
        print("RETARGET_GROUND", clip, "lifted up to %.3f m" % max(lift))
    for fc in getattr(act, "fcurves", []):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    act["source"] = fbx
    act["source_range"] = [f0, f1]
    act["frames"] = len(frames)
    act["fps"] = 30
    act["loop"] = bool(opt.get("loop", opt.get("in_place") or opt.get("loop_blend")))
    if opt.get("in_place") and act["loop"]:
        dur = max(1, len(frames) - 1) / 30.0
        act["root_vel"] = [drift.x * ratio / dur, drift.y * ratio / dur]
    elif not opt.get("in_place") and not held:
        act["root_motion"] = True
    if "retime" in opt:
        act["retime"] = [list(k) for k in opt["retime"]]
    if opt.get("mirror"):
        act["mirrored"] = True
    for o in new_objs:
        bpy.data.objects.remove(o, do_unlink=True)
    for a in set(bpy.data.actions) - acts_before:
        if a is not act:
            bpy.data.actions.remove(a)
    print("RETARGET", clip, fbx, f"{f0}-{f1}", len(frames), "frames, hip ratio %.3f" % ratio)
rig.animation_data.action = bpy.data.actions.get("idle") or rig.animation_data.action
sc.frame_start = 1
sc.frame_end = int(rig.animation_data.action["frames"])
if out_blend:
    bpy.ops.wm.save_as_mainfile(filepath=str(out_blend), compress=True)
else:
    bpy.ops.wm.save_mainfile(compress=True)
print("RETARGET_SAVED", bpy.data.filepath)
