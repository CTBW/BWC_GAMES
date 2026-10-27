"""Retarget Mixamo FBX clips onto the spearman rig (background Blender).

  blender -b <rig.blend> --python retarget_clips.py -- <animations dir> [clip,clip...]

Same method as footman_3d/tools/retarget_clips.py: each clip is its own action on
SpearmanRig (fake user), retargeted by rest-pose difference bone by bone in world space,
    R_target(t) = R_source(t) * R_source_rest^-1 * R_target_rest,
the hips' motion scaled by the hip-height ratio. Options per clip:
  range      (first, last) source frames to keep
  in_place   remove the drift between the first and last frame (loops, walks)
  loop_blend ease the last N frames back to the first pose so the loop has no pop
  blend_in   (clip, n): start from that clip's first pose and ease into this one over n frames
  blend_out  (clip, n): ease back into that clip's first pose over the last n frames
             (hit, deaths and the turn come from other units' clips, which start in another
             stance: blended from and to the guard, the game can cut between them without a jump)
  turned     the blend_out's pose is turned with the hips (a turn ends in the guard facing
             the new way), its hips where the guard has them: the sandbox turns the figure
             about that point (export_godot.py `pivot`)
  reverse    the clip played backwards, blends and all (turn_90_r: the left turn backwards
             starts and ends in the guard; a mirror image would swap his staggered feet)
  yaw        turn the whole clip about the vertical (degrees, + = to his left), for a
             source whose main action is not aimed along -Y (none needs it now: the
             bayonet strike's thrust already goes straight ahead)
  ground     lift the hips wherever his skinned body dips below the ground, smoothed: the
             deaths sank him 12-17 cm in; the boots may still roll GROUND_BOOT_SINK into
             it, as they do in every walk. Needs the cape off the body (cape_cloth.py setup)
Several deaths are kept (death, death_2, ...) so the game can vary them per figure.
The spear is moved per clip afterwards by spear_motion.py.
"""
import sys
from pathlib import Path

import math

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

GROUND_BOOT_Z = 0.15       # rest height below which vertices belong to the boots
GROUND_BOOT_SINK = 0.03    # how far the boots may roll into the ground

CLIPS = {
    # The guard hold at the end of the bayonet strike: spear levelled in both hands.
    "idle": ("Attack - Spearmen.fbx", {"range": (57, 99), "in_place": True, "loop_blend": 10}),
    "idle_rest": ("Idle - Crossbowmen.fbx", {"in_place": True, "loop_blend": 12}),
    "walk": ("Walk - Spearmen.fbx", {"in_place": True}),
    "attack": ("Attack - Spearmen.fbx", {"range": (1, 64)}),
    "hit": ("Hit - Crossbowmen.fbx", {"blend_in": ("idle", 8), "blend_out": ("idle", 10)}),
    "death": ("Death - Crossbowmen.fbx", {"blend_in": ("idle", 8), "ground": True}),
    "death_2": ("Death_2 - Crossbowmen.fbx", {"blend_in": ("idle", 8), "ground": True}),
    "death_3": ("Sword And Shield Death.fbx", {"blend_in": ("idle", 8), "ground": True}),
    "turn_90": ("Turning - Footman.fbx", {"in_place": True, "blend_in": ("idle", 6), "blend_out": ("idle", 8), "turned": True}),
    "turn_90_r": ("Turning - Footman.fbx", {"in_place": True, "blend_in": ("idle", 6), "blend_out": ("idle", 8), "turned": True,
                                            "reverse": True}),
    "turn_180": ("Turning 180 degress - Footman.fbx", {"in_place": True, "blend_in": ("idle", 6), "blend_out": ("idle", 8),
                                                      "turned": True}),
    "step_lane": ("Standing Walk Right.fbx", {"in_place": True}),
}

argv = sys.argv[sys.argv.index("--") + 1:]
anim_dir = Path(argv[0])
only = argv[1].split(",") if len(argv) > 1 and argv[1] else list(CLIPS)
sc = bpy.context.scene
sc.render.fps = 30
rig = bpy.data.objects["SpearmanRig"]
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
    stays on the ground, the boots allowed GROUND_BOOT_SINK; widened by two frames each way
    and then averaged, so the lift never pops. The cape must be off the body already
    (cape_cloth.py setup): skinned, its flared hem swings half a metre under the floor."""
    assert "Cape" in bpy.data.objects, "run cape_cloth.py setup before the ground check"
    body = bpy.data.objects["Spearman"]
    me = body.data
    rest = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", rest)
    floor = np.where(rest[2::3] < GROUND_BOOT_Z, -GROUND_BOOT_SINK, 0.0)
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
    s_hips_rest = smw @ src.data.bones["mixamorig:Hips"].head_local
    ratio = T_head["mixamorig:Hips"].z / s_hips_rest.z
    frames = list(range(f0, f1 + 1))
    samples = []
    for f in frames:
        sc.frame_set(f)
        R = {n: (smw.to_3x3() @ src.pose.bones[n].matrix.to_3x3()).normalized() for n in names if n in S_rest}
        samples.append((R, (smw @ src.pose.bones["mixamorig:Hips"].head).copy()))
    drift = samples[-1][1] - samples[0][1] if opt.get("in_place") else Vector()
    drift.z = 0.0
    # Local rotations per frame.
    local = []
    for R, _ in samples:
        Rt, q_of = {}, {}
        for n in order:
            par = rig.data.bones[n].parent
            if n in R:
                Rt[n] = R[n] @ S_rest[n].inverted() @ T_rest[n]
            else:
                Rt[n] = (Rt[par.name] @ T_rest[par.name].inverted() @ T_rest[n]) if par else T_rest[n]
            if par is None:
                basis = T_rest[n].inverted() @ Rt[n]
            else:
                basis = (T_rest[par.name].inverted() @ T_rest[n]).inverted() @ Rt[par.name].inverted() @ Rt[n]
            q_of[n] = basis.to_quaternion()
        local.append(q_of)
    hips_off = [(h - s_hips_rest - drift * (i / max(1, len(frames) - 1))) * ratio for i, (_, h) in enumerate(samples)]
    if opt.get("yaw"):
        Rz = Matrix.Rotation(math.radians(opt["yaw"]), 3, "Z")
        hn = "mixamorig:Hips"
        for i in range(len(local)):
            Rw = T_rest[hn] @ local[i][hn].to_matrix()        # the hips' world rotation
            local[i][hn] = (T_rest[hn].inverted() @ Rz @ Rw).to_quaternion()
            hips_off[i] = Rz @ hips_off[i]
    nb = opt.get("loop_blend", 0)
    if nb:
        # Ease the tail back into the first pose (rotations and hips offset).
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
        hn = "mixamorig:Hips"
        ref_hw = T_rest[hn] @ ref_q[hn].to_matrix()            # the hips' world rotation in it
        for k in range(min(nbl, len(local))):
            i = k if at_start else len(local) - 1 - k
            w = smooth(1.0 - (k + 1) / (nbl + 1))       # 1 at the joint with the other clip, easing to 0
            to = dict(ref_q)
            if opt.get("turned") and not at_start:
                # The pose turned about the vertical as far as the hips are turned from it.
                R = T_rest[hn] @ local[i][hn].to_matrix() @ ref_hw.inverted()
                Rz = Matrix.Rotation(math.atan2(R[1][0], R[0][0]), 3, "Z")
                to[hn] = (T_rest[hn].inverted() @ Rz @ ref_hw).to_quaternion()
            for n in order:
                b = to[n].copy()
                b.make_compatible(local[i][n])
                local[i][n] = local[i][n].slerp(b, w)
            hips_off[i] = hips_off[i].lerp(ref_h, w)
    if opt.get("reverse"):
        local.reverse()
        hips_off.reverse()
        drift = -drift
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
    act["source"] = fbx + (" played backwards" if opt.get("reverse") else "")
    act["source_range"] = [f0, f1]
    act["frames"] = len(frames)
    if opt.get("in_place"):
        dur = max(1, len(frames) - 1) / 30.0
        act["root_vel"] = [drift.x * ratio / dur, drift.y * ratio / dur]
    for o in new_objs:
        bpy.data.objects.remove(o, do_unlink=True)
    for a in set(bpy.data.actions) - acts_before:
        if a is not act:
            bpy.data.actions.remove(a)
    print("RETARGET", clip, fbx, f"{f0}-{f1}", len(frames), "frames, hip ratio %.3f" % ratio)
rig.animation_data.action = bpy.data.actions.get("idle") or rig.animation_data.action
sc.frame_start = 1
sc.frame_end = int(rig.animation_data.action["frames"])
bpy.ops.wm.save_mainfile(compress=True)
print("RETARGET_SAVED", bpy.data.filepath)
