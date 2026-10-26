"""The Sovereign Kiss's own corrections and keys (background Blender).

  blender -b <kiss blend> --python kiss_motion.py -- [clip,clip...]
  blender -b <kiss blend> --python kiss_motion.py -- bind

Run on clips fresh from retarget_clips.py (sovereign_kiss, sovereign_kiss_source; a second
run is refused) in a blend that has kiss_rig.py's shape keys and KissSocket, and before
secondary_motion.py / whip_motion.py; then "bind" makes the file open on the kiss again
(those two leave idle bound)
(workspace/2026-10-20_meridius/sovereign-kiss/blender-handoff-fog.md, "Character and cast"):

- The whip hand stays low: her left arm (the source's free hand, which rises to her belly)
  is held in idle's first pose, relative to her chest, so the whip hangs at her side.
- The kiss reaches her lips: her hand is shorter than the mannequin's fingers and stops
  about 9 cm short, so over the contact (CONTACT) the right wrist is moved, by a two-bone
  solve on the upper arm and forearm (the elbow kept in its plane, the hand's rotation
  kept), until the hand's nearest point sits TOUCH in front of KissSocket. It comes in and
  goes out from the front (APPROACH further ahead while the contact builds and fades), so
  her claws pass in front of her chin.
- Kiss_Pucker and Exhale keyed per frame (the face action, <clip>_face, on the body's
  shape keys) and stored as act["face"] (values per frame) for the export.
- kiss_release: a pose marker and act["events"]["kiss_release"] (seconds from frame 1).
All beats are in source frames, so the retimed clip and the source-timed one share them.
"""
import json
import sys

import bpy
import numpy as np
from mathutils import Vector

TOUCH = 0.008                # the hand's nearest point ahead of KissSocket's head (m)
APPROACH = 0.05              # and this much further ahead where the contact is still 0 (m)
RELEASE = 60                 # source frame: the hand leaves the lips
# (source frame, value) knots, eased between them
CONTACT = ((22, 0.0), (31, 1.0), (59, 1.0), (68, 0.0))
FACE = {"Kiss_Pucker": ((28, 0.0), (37, 1.0), (59, 1.0), (60, 0.5), (64, 0.0)),
        "Exhale": ((59, 0.0), (60, 0.7), (64, 1.0), (70, 1.0), (79, 0.0))}
LEFT = {"mixamorig:LeftShoulder": 0.6, "mixamorig:LeftArm": 1.0, "mixamorig:LeftForeArm": 1.0,
        "mixamorig:LeftHand": 1.0}

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
bind_only = argv[:1] == ["bind"]
clips = argv[0].split(",") if argv and argv[0] and not bind_only else ["sovereign_kiss", "sovereign_kiss_source"]
sc = bpy.context.scene
rig = bpy.data.objects["SuccubusRig"]
body = bpy.data.objects["Succubus"]
pb = rig.pose.bones
bones = rig.data.bones
assert rig.matrix_world == rig.matrix_world.Identity(4), "the rig must sit at the origin"
assert "KissSocket" in bones and body.data.shape_keys and "Kiss_Pucker" in body.data.shape_keys.key_blocks, \
    "run kiss_rig.py first"


def eased(knots, x):
    if x <= knots[0][0]:
        return knots[0][1]
    for (a, va), (b, vb) in zip(knots, knots[1:]):
        if x <= b:
            t = (x - a) / (b - a)
            return va + (vb - va) * t * t * (3 - 2 * t)
    return knots[-1][1]


def rest3(n):
    return bones[n].matrix_local.to_3x3().normalized()


def basis(n, R, R_par):
    """The local rotation that gives bone n the armature-space rotation R under a parent at R_par."""
    par = bones[n].parent.name
    return ((rest3(par).inverted() @ rest3(n)).inverted() @ R_par.inverted() @ R).to_quaternion()


def key(n, q, f, prev):
    q = q.copy()
    if n in prev:
        q.make_compatible(prev[n])
    prev[n] = q
    pb[n].rotation_quaternion = q
    pb[n].keyframe_insert("rotation_quaternion", frame=f)


gi = body.vertex_groups["mixamorig:RightHand"].index
hand_v = [v.index for v in body.data.vertices if any(g.group == gi and g.weight > 0.9 for g in v.groups)]

idle = bpy.data.actions["idle"]
rig.animation_data.action = idle
sc.frame_set(1)
idle_q = {n: pb[n].rotation_quaternion.copy() for n in LEFT}

for clip in [] if bind_only else clips:
    act = bpy.data.actions[clip]
    if act.get("kiss_motion"):
        raise SystemExit(f"{clip}: kiss_motion.py has run on it already; retarget it afresh")
    rig.animation_data.action = act
    n = int(act["frames"])
    if "retime" in act:
        tk = [tuple(k) for k in act["retime"]]
        src = lambda i: float(np.interp(i, [a for a, _ in tk], [b for _, b in tk]))
    else:
        f0 = act["source_range"][0]
        src = lambda i: i + f0 - 1.0
    s = [src(i) for i in range(1, n + 1)]
    release = next(i for i in range(1, n + 1) if s[i - 1] >= RELEASE)

    # the whip hand stays low
    prev = {}
    for f in range(1, n + 1):
        sc.frame_set(f)
        for b, w in LEFT.items():
            q = pb[b].rotation_quaternion.copy()
            t = idle_q[b].copy()
            t.make_compatible(q)
            key(b, q.slerp(t, w), f, prev)

    # the hand's point that touches: the one nearest her lips where the source comes closest
    i_close = max(range(1, n + 1), key=lambda i: (eased(CONTACT, s[i - 1]), -abs(s[i - 1] - 38)))
    sc.frame_set(i_close)
    ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = ev.to_mesh()
    lips = pb["KissSocket"].head.copy()
    tip_w = min((me.vertices[i].co.copy() for i in hand_v), key=lambda c: (c - lips).length)
    ev.to_mesh_clear()
    tip_h = pb["mixamorig:RightHand"].matrix.inverted() @ tip_w

    # the kiss reaches her lips
    prev, report = {}, []
    arm, fore, hand = "mixamorig:RightArm", "mixamorig:RightForeArm", "mixamorig:RightHand"
    for f in range(1, n + 1):
        w = eased(CONTACT, s[f - 1])
        if w <= 0.0:
            continue
        sc.frame_set(f)
        M = {b: pb[b].matrix.copy() for b in ("mixamorig:RightShoulder", arm, fore, hand, "KissSocket")}
        sock = M["KissSocket"]
        target = sock.translation + sock.to_3x3().col[1].normalized() * (TOUCH + APPROACH * (1 - w))
        tip = M[hand] @ tip_h
        S, E, Wr = M[arm].translation, M[fore].translation, M[hand].translation
        W2 = Wr + (target - tip) * w
        L1, L2 = (E - S).length, (Wr - E).length
        u = W2 - S
        d = min(max(u.length, abs(L1 - L2) + 1e-4), L1 + L2 - 1e-4)
        u.normalize()
        v = (E - S) - u * (E - S).dot(u)
        v.normalize()
        a = (L1 * L1 - L2 * L2 + d * d) / (2 * d)
        E2 = S + u * a + v * max(0.0, L1 * L1 - a * a) ** 0.5
        Q1 = (E - S).rotation_difference(E2 - S).to_matrix()
        Q2 = (Q1 @ (Wr - E)).rotation_difference(S + u * d - E2).to_matrix()
        R_arm = Q1 @ M[arm].to_3x3()
        R_fore = Q2 @ Q1 @ M[fore].to_3x3()
        R_hand = M[hand].to_3x3()
        key(arm, basis(arm, R_arm, M["mixamorig:RightShoulder"].to_3x3()), f, prev)
        key(fore, basis(fore, R_fore, R_arm), f, prev)
        key(hand, basis(hand, R_hand, R_fore), f, prev)
        report.append((f, w, (target - tip).length, (S + u * d - W2).length))

    # her face
    key_d = body.data.shape_keys
    key_d.animation_data_create()
    face_name = clip + "_face"
    old = bpy.data.actions.get(face_name)
    if old is not None:
        bpy.data.actions.remove(old)
    face = bpy.data.actions.new(face_name)
    face.use_fake_user = True
    key_d.animation_data.action = face
    values = {}
    for name, knots in FACE.items():
        kb = key_d.key_blocks[name]
        values[name] = [round(eased(knots, x), 3) for x in s]
        for f, val in enumerate(values[name], 1):
            kb.value = val
            kb.keyframe_insert("value", frame=f)
    face["face_of"] = clip     # no "frames": the rig's tools take actions with frames as clips
    act["face"] = json.dumps(values)
    act["face_action"] = face_name

    # the release
    for m in [m for m in act.pose_markers if m.name == "kiss_release"]:
        act.pose_markers.remove(m)
    act.pose_markers.new("kiss_release").frame = release
    ev_d = json.loads(act.get("events", "{}"))
    ev_d["kiss_release"] = round((release - 1) / 30.0, 4)
    act["events"] = json.dumps(ev_d)
    act["kiss_motion"] = True
    worst = max(report, key=lambda r: r[2] * r[1]) if report else None
    print("KISS_MOTION %s: %d frames, release at %d (%.3f s), contact over %d frames, touch point %s; "
          "largest correction %.3f m at frame %d; out of reach by up to %.3f m" % (
              clip, n, release, (release - 1) / 30.0, len(report), tuple(round(c, 3) for c in tip_h),
              max(r[2] for r in report), worst[0], max(r[3] for r in report)))

# the file opens on the kiss, its face action bound to the shape keys
act = bpy.data.actions[clips[0]]
rig.animation_data.action = act
body.data.shape_keys.animation_data.action = bpy.data.actions[act["face_action"]]
sc.frame_start, sc.frame_end = 1, int(act["frames"])
sc.render.fps = 30
sc.frame_set(1)
bpy.ops.wm.save_mainfile(compress=True)
print("KISS_MOTION_SAVED", bpy.data.filepath)
