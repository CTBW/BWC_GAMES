"""Rig the spearman for Mixamo clips (background Blender; see build_spearman.py for the
BLENDER_USER_RESOURCES note).

  blender -b spearman_base.blend --factory-startup --python rig_spearman.py -- <out.blend> [landmarks.json]

Adapted from footman_3d/tools/rig_footman.py:
1. The body from spearman_base.blend is already 1.82 m tall, feet at z = 0, facing -Y.
2. Builds an armature with the Mixamo bone names and hierarchy (no finger bones), its joints
   placed on the mesh: proportions from the T-pose silhouette, depth from the mesh slice at
   each joint with the cape left out (it hangs well behind the back), overridable per joint
   from landmarks.json.
3. Bends both mitten hands into fists round the spear's shaft (radius from the Spear object).
4. Skins with automatic weights, then gives the cape and hood to the spine only (bone heat
   lets the legs and arms pull at the cape, which would tear it in the walk).
The spear stays a free object; spear_motion.py moves it per clip.
"""
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

H = 1.82
argv = sys.argv[sys.argv.index("--") + 1:]
out_blend = Path(argv[0])
over = json.loads(Path(argv[1]).read_text()) if len(argv) > 1 and Path(argv[1]).exists() else {}
sc = bpy.context.scene
body = bpy.data.objects["Spearman"]
spear = bpy.data.objects["Spear"]
V = np.array([v.co[:] for v in body.data.vertices])
assert abs(V[:, 2].max() - H) < 0.01 and abs(V[:, 2].min()) < 0.01
# build_spearman centres the bounding box, which the flared cape makes deep: centre the
# body on its hips instead (front-to-back middle of the pelvis, the cape left out), so
# turning him for the game's facings turns him on the spot.
pel = V[(np.abs(V[:, 2] - 0.52 * H) < 0.03) & (np.abs(V[:, 0]) < 0.12)]
pel = pel[pel[:, 1] < np.percentile(pel[:, 1], 3) + 0.30]
dy = -float((np.percentile(pel[:, 1], 3) + np.percentile(pel[:, 1], 97)) / 2)
body.data.transform(Matrix.Translation((0, dy, 0)))
body.data.update()
V = np.array([v.co[:] for v in body.data.vertices])
print("RIG_RECENTRE y by %.3f" % dy)

# Cape and hood: vertices close to the outermost back surface, behind the shoulder blades.
# Measured like build_spearman.py: a height map of the outermost back surface.
X0, X1, Z0, Z1, CELL = -0.40, 0.40, 0.70, 1.62, 0.01
nx, nz = int((X1 - X0) / CELL) + 1, int((Z1 - Z0) / CELL) + 1
yout = np.full((nz, nx), -1.0)
for x, y, z in V:
    if X0 <= x <= X1 and Z0 <= z <= Z1 and y > 0.03:
        i, j = int((z - Z0) / CELL), int((x - X0) / CELL)
        yout[i, j] = max(yout[i, j], y)
for _ in range(3):
    pad = np.pad(yout, 1, constant_values=-1.0)
    nb = np.max([pad[1 + di:nz + 1 + di, 1 + dj:nx + 1 + dj] for di in (-1, 0, 1) for dj in (-1, 0, 1)], axis=0)
    yout = np.where(yout < 0, nb, yout)


def is_cape(x, y, z):
    if not (-0.32 <= x <= 0.32 and Z0 <= z <= Z1 and y > 0.06):
        return False
    if z > 1.28 and abs(x) > 0.16:
        return False   # the short sleeves and the cape's drape over the shoulders follow the arms
    i, j = int((z - Z0) / CELL), int((x - X0) / CELL)
    return y > yout[i, j] - 0.032


cape = np.array([is_cape(*p) for p in V])
body_v = V[~cape]
print("RIG_CAPE vertices", int(cape.sum()), "of", len(V))


def slice_y(z, x0=-0.12, x1=0.12, band=0.02):
    """Depth centre of the body at height z: halfway between its front and back surface,
    the cape left out."""
    m = (np.abs(body_v[:, 2] - z) < band * H) & (body_v[:, 0] >= x0) & (body_v[:, 0] <= x1)
    if not m.any():
        return 0.0
    ys = body_v[m, 1]
    return float((np.percentile(ys, 3) + np.percentile(ys, 97)) / 2)


def leg_x(z, side):
    m = (np.abs(body_v[:, 2] - z) < 0.02 * H) & ((body_v[:, 0] > 0.01) if side > 0 else (body_v[:, 0] < -0.01))
    return float(np.mean(body_v[m, 0])) if m.any() else side * 0.07 * H


tip = float(V[:, 0].max())
arm_m = np.abs(V[:, 0]) > 0.3 * H
arm_z = float(np.median(V[arm_m, 2])) / H
arm_y = float(np.median(V[arm_m, 1]))
P = {
    "hip_z": 0.52, "spine_z": 0.585, "spine1_z": 0.65, "spine2_z": 0.715, "neck_z": arm_z + 0.035,
    "head_z": arm_z + 0.07, "top_z": 1.0, "arm_z": arm_z,
    "clav_x": 0.03, "shoulder_x": 0.105, "wrist_x": 0.34, "hand_end_x": tip / H,
    "knee_z": 0.27, "ankle_z": 0.075, "toe_z": 0.018,
}
P["elbow_x"] = (P["shoulder_x"] + P["wrist_x"]) / 2 + 0.01
P.update(over)
for side, s in (("Left", 1), ("Right", -1)):
    P[side + "_hip_x"] = leg_x(0.36 * H, s) * 0.9
    P[side + "_ankle_x"] = leg_x(0.12 * H, s)
foot = V[:, 2] < 0.04 * H
toe_y = float(np.percentile(V[foot, 1], 2))
heel_y = float(np.percentile(V[foot, 1], 98))
print("RIG_LANDMARKS", json.dumps({k: round(v, 4) for k, v in P.items()}), "tip", round(tip, 3),
      "toe_y", round(toe_y, 3), "heel_y", round(heel_y, 3))

J = {}
for n, key in (("Hips", "hip_z"), ("Spine", "spine_z"), ("Spine1", "spine1_z"), ("Spine2", "spine2_z")):
    J[n] = Vector((0, slice_y(P[key] * H), P[key] * H))
J["Neck"] = Vector((0, slice_y(P["neck_z"] * H, -0.05 * H, 0.05 * H), P["neck_z"] * H))
J["Head"] = Vector((0, slice_y(P["head_z"] * H, -0.05 * H, 0.05 * H), P["head_z"] * H))
J["HeadTop_End"] = Vector((0, J["Head"].y, P["top_z"] * H))
for side, s in (("Left", 1), ("Right", -1)):
    az = P["arm_z"] * H
    J[side + "Shoulder"] = Vector((s * P["clav_x"] * H, arm_y, az - 0.01 * H))
    J[side + "Arm"] = Vector((s * P["shoulder_x"] * H, arm_y, az))
    J[side + "ForeArm"] = Vector((s * P["elbow_x"] * H, arm_y, az))
    J[side + "Hand"] = Vector((s * P["wrist_x"] * H, arm_y, az))
    J[side + "HandEnd"] = Vector((s * P["hand_end_x"] * H * 0.98, arm_y, az))
    hx, ax = P[side + "_hip_x"], P[side + "_ankle_x"]
    J[side + "UpLeg"] = Vector((hx, slice_y(P["hip_z"] * H - 0.04 * H, min(0, hx * 2), max(0, hx * 2)), P["hip_z"] * H - 0.03 * H))
    kx = (hx + ax) / 2
    J[side + "Leg"] = Vector((kx, slice_y(P["knee_z"] * H, min(0, kx * 2), max(0, kx * 2)) - 0.01, P["knee_z"] * H))
    J[side + "Foot"] = Vector((ax, (toe_y + heel_y) / 2 + 0.25 * (heel_y - toe_y), P["ankle_z"] * H))
    J[side + "ToeBase"] = Vector((ax, toe_y * 0.55 + heel_y * 0.45 - 0.15 * (heel_y - toe_y), P["toe_z"] * H))
    J[side + "Toe_End"] = Vector((ax, toe_y, P["toe_z"] * H))

# Fists round the shaft (as rig_footman.make_fist, with the spear's shaft radius).
GRIP_R = float(spear.get("shaft_r", 0.020))   # the shaft is one long quad strip: no mid-shaft vertices to measure
print("RIG_GRIP radius %.4f" % GRIP_R)
FIST = {}


def make_fist(side, s):
    wx = abs(J[side + "Hand"].x)
    tipx = abs(J[side + "HandEnd"].x) / 0.98
    me = body.data
    co = np.array([v.co[:] for v in me.vertices])
    az, ay = J[side + "Hand"].z, J[side + "Hand"].y
    near = (np.abs(co[:, 2] - az) < 0.09) & (np.abs(co[:, 1] - ay) < 0.09) & (co[:, 0] * s > wx - 0.01)
    hand = co[near]
    if not len(hand):
        return
    knuck = wx + 0.30 * (tipx - wx)
    knuck_pts = hand[np.abs(np.abs(hand[:, 0]) - knuck) < 0.015]
    palm_z = float(knuck_pts[:, 2].min()) if len(knuck_pts) else az - 0.02
    yc = float(np.median(knuck_pts[:, 1])) if len(knuck_pts) else ay
    Rr = GRIP_R + 0.002
    comp = min(1.0, math.radians(290) * Rr / (tipx - knuck))
    slim = 0.72
    u, w = Vector((s, 0, 0)), Vector((0, 0, 1))
    K = Vector((s * knuck, yc, palm_z))
    O = K - w * Rr
    thumb_y = yc - 0.035
    for v in me.vertices:
        p = v.co
        if abs(p.z - az) > 0.09 or abs(p.y - ay) > 0.09:
            continue
        d = (p.x - K.x) * s
        if p.y < thumb_y and -0.04 < d < 0.03:
            rel = p - Vector((p.x, O.y, O.z))
            ca, sa = math.cos(math.radians(70)), math.sin(math.radians(70))
            v.co = Vector((p.x, O.y + (rel.y * ca - rel.z * sa) * 0.8, O.z + (rel.y * sa + rel.z * ca) * 0.8))
            continue
        if d <= 0 or abs(p.x) > tipx + 0.01:
            continue
        hgt = (p - K).dot(w)
        phi = d * comp / Rr
        rho = Rr + max(0.0, hgt) * slim + min(0.0, hgt)
        lateral = Vector((0, (p.y - K.y) * (1.0 - 0.18 * min(1.0, phi / math.pi)), 0))
        v.co = O + u * (rho * math.sin(phi)) + w * (rho * math.cos(phi)) + lateral
    FIST[side] = O.copy()
    print("RIG_FIST", side, "knuckles x %.3f" % knuck, "grip axis", [round(c, 3) for c in O])


make_fist("Right", -1)
make_fist("Left", 1)

# Armature: Mixamo names and parents.
arm_data = bpy.data.armatures.new("SpearmanRig")
rig = bpy.data.objects.new("SpearmanRig", arm_data)
sc.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
EB = arm_data.edit_bones
CHAIN = [("Hips", None, "Spine"), ("Spine", "Hips", "Spine1"), ("Spine1", "Spine", "Spine2"), ("Spine2", "Spine1", "Neck"),
         ("Neck", "Spine2", "Head"), ("Head", "Neck", "HeadTop_End"), ("HeadTop_End", "Head", None)]
for side in ("Left", "Right"):
    CHAIN += [(side + "Shoulder", "Spine2", side + "Arm"), (side + "Arm", side + "Shoulder", side + "ForeArm"),
              (side + "ForeArm", side + "Arm", side + "Hand"), (side + "Hand", side + "ForeArm", side + "HandEnd"),
              (side + "UpLeg", "Hips", side + "Leg"), (side + "Leg", side + "UpLeg", side + "Foot"),
              (side + "Foot", side + "Leg", side + "ToeBase"), (side + "ToeBase", side + "Foot", side + "Toe_End"),
              (side + "Toe_End", side + "ToeBase", None)]
for name, parent, tail in CHAIN:
    b = EB.new("mixamorig:" + name)
    b.head = J[name]
    if tail:
        b.tail = J[tail]
    else:
        prev = J[name] - J[parent]
        b.tail = J[name] + prev.normalized() * max(0.03, prev.length * 0.5)
    if parent:
        b.parent = EB["mixamorig:" + parent]
        b.use_connect = name != "Hips" and not name.endswith(("Shoulder", "UpLeg")) and (b.head - b.parent.tail).length < 1e-4
# Forearm twist bones (not in the Mixamo set): the wrist half of each forearm, rolling with
# the hand, so a hand turned on its forearm twists the round bracer instead of wringing the
# wrist (the Mixamo skeleton has no twist bones, and the spear holds roll the hand a lot).
for side in ("Left", "Right"):
    tb = EB.new(side + "ForeArmTwist")
    tb.head = J[side + "ForeArm"].lerp(J[side + "Hand"], 0.45)
    tb.tail = J[side + "Hand"]
    tb.parent = EB["mixamorig:" + side + "ForeArm"]
for b in EB:
    b.align_roll(Vector((0, 0, -1)) if ("Arm" in b.name or "Hand" in b.name or "Shoulder" in b.name) else Vector((0, -1, 0)))
bpy.ops.object.mode_set(mode="OBJECT")
for b in arm_data.bones:
    b.use_deform = not b.name.endswith(("HeadTop_End", "Toe_End"))

bpy.ops.object.select_all(action="DESELECT")
body.select_set(True); rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
segs = [(b.name, Vector(b.head_local), Vector(b.tail_local)) for b in arm_data.bones if b.use_deform]


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(1e-9, ab.length_squared)))
    return (p - (a + ab * t)).length


unweighted = [v.index for v in body.data.vertices if not any(g.weight > 1e-3 for g in v.groups)]
for vi in unweighted:
    p = body.data.vertices[vi].co
    name = min(segs, key=lambda s: seg_dist(p, s[1], s[2]))[0]
    (body.vertex_groups.get(name) or body.vertex_groups.new(name=name)).add([vi], 1.0, "REPLACE")

# Cape and hood: spine and hips only, by height (smooth blend between neighbours).
SPINE = [("mixamorig:Hips", J["Hips"].z), ("mixamorig:Spine", J["Spine"].z), ("mixamorig:Spine1", J["Spine1"].z),
         ("mixamorig:Spine2", J["Spine2"].z), ("mixamorig:Neck", J["Neck"].z)]
vg = {g.name: g for g in body.vertex_groups}
for n, _ in SPINE:
    vg.setdefault(n, body.vertex_groups.new(name=n))
cape_idx = [i for i, c in enumerate(cape) if c]
for g in body.vertex_groups:
    g.remove(cape_idx)
for i in cape_idx:
    z = V[i, 2]
    if z <= SPINE[0][1]:
        vg[SPINE[0][0]].add([i], 1.0, "REPLACE"); continue
    if z >= SPINE[-1][1]:
        vg[SPINE[-1][0]].add([i], 1.0, "REPLACE"); continue
    for (na, za), (nb_, zb) in zip(SPINE, SPINE[1:]):
        if za <= z <= zb:
            t = (z - za) / (zb - za)
            vg[na].add([i], 1.0 - t, "REPLACE"); vg[nb_].add([i], t, "REPLACE")
            break
left = sum(1 for v in body.data.vertices if not any(g.weight > 1e-3 for g in v.groups))
print("RIG_SKIN groups", len(body.vertex_groups), "filled", len(unweighted), "cape to spine", len(cape_idx), "unweighted", left)


def smooth_step(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


# The wrist half of the forearm moves onto its twist bone: from none at 30% of the way
# from the elbow to all of it at 90%. Weights only move from the forearm to its twist bone.
moved = 0
for side in ("Left", "Right"):
    fg = body.vertex_groups["mixamorig:" + side + "ForeArm"]
    tg = body.vertex_groups.get(side + "ForeArmTwist") or body.vertex_groups.new(name=side + "ForeArmTwist")
    e, w = J[side + "ForeArm"], J[side + "Hand"]
    ax = w - e
    for v in body.data.vertices:
        wf = next((g.weight for g in v.groups if g.group == fg.index), 0.0)
        if wf <= 1e-4:
            continue
        t = (v.co - e).dot(ax) / ax.length_squared
        k = smooth_step((t - 0.3) / 0.6)
        if k > 0:
            fg.add([v.index], wf * (1 - k), "REPLACE")
            tg.add([v.index], wf * k, "REPLACE")
            moved += 1
# The fists are rigid (as on the crossbowman): vertices more than 2.5 cm past the wrist
# that are mostly on the hand follow only the hand, so a bent wrist does not fold the fist.
rigid = 0
for side, s_ in (("Left", 1), ("Right", -1)):
    hg = body.vertex_groups["mixamorig:" + side + "Hand"]
    wx = abs(J[side + "Hand"].x)
    for v in body.data.vertices:
        if v.co.x * s_ - wx < 0.025:
            continue
        tot = sum(g.weight for g in v.groups) or 1.0
        hw = sum(g.weight for g in v.groups if g.group == hg.index) / tot
        if 0.5 <= hw < 0.999:
            for g in list(v.groups):
                if g.group != hg.index:
                    body.vertex_groups[g.group].remove([v.index])
            hg.add([v.index], 1.0, "REPLACE")
            rigid += 1
# Each twist bone copies its hand's roll about the forearm.
for side in ("Left", "Right"):
    pb = rig.pose.bones[side + "ForeArmTwist"]
    c = pb.constraints.new("COPY_ROTATION")
    c.target = rig; c.subtarget = "mixamorig:" + side + "Hand"
    c.use_x = c.use_z = False; c.use_y = True
    c.target_space = c.owner_space = "LOCAL"
    c.influence = 0.85
print("RIG_WRISTS forearm vertices on twist bones", moved, "fist vertices made rigid", rigid)

rig["landmarks"] = json.dumps({k: list(v) for k, v in J.items()})
rig["fist_right"] = list(FIST.get("Right", J["RightHand"]))
rig["fist_left"] = list(FIST.get("Left", J["LeftHand"]))
rig["grip_r"] = GRIP_R
out_blend.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend), compress=True)
print("RIG_SAVED", out_blend)
