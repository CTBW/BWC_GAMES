"""Rig the Tripo footman for Mixamo clips (run in a background Mixar or Blender).

  mixar.exe --background --factory-startup --python rig_footman.py -- <tripo dir> <out.blend> [landmarks.json]

1. Imports the Tripo character, sword and shield (FBX, 1 m tall, Y-up) and
   scales the character to the Mixamo skeleton's height (1.82 m), feet on the
   ground, facing -Y like the Mixamo clips.
2. Builds an armature with the Mixamo bone names and hierarchy (no finger
   bones: the gloves are mittens), its joints placed on the mesh: proportions
   measured from the T-pose silhouette, depth from the mesh slice at each
   joint, overridable per joint from landmarks.json.
3. Skins the body with automatic (bone heat) weights.
4. Puts the sword in the right fist and the shield on the left forearm in the
   hand frames the Mixamo sword-and-shield clips were authored with (sword
   along the hand's +X, shield face along -Z, long axis along -X), so a
   retargeted clip swings the props the way the source does.
Saves the .blend; clips are added by retarget_clips.py.
"""
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

H = 1.82  # Mixamo Y Bot head-top height

argv = sys.argv[sys.argv.index("--") + 1:]
tripo, out_blend = Path(argv[0]), Path(argv[1])
over = json.loads(Path(argv[2]).read_text()) if len(argv) > 2 and Path(argv[2]).exists() else {}

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.unit_settings.system = "METRIC"


def import_fbx(path, name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(path))
    obj = next(o for o in bpy.data.objects if o not in before and o.type == "MESH")
    obj.name = name
    obj.data.name = name
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


body = import_fbx(tripo / "fantasy_character_3d_model/fantasy_character_3d_model.fbx", "Footman")
sword = import_fbx(tripo / "medieval_sword_3d_model/medieval_sword_3d_model.fbx", "Sword")
shield = import_fbx(tripo / "medieval_shield_3d_model/medieval_shield_3d_model.fbx", "Shield")

# Scale the body to 1.82 m, feet at z = 0, centred on x/y.
V = np.array([v.co[:] for v in body.data.vertices])
zmin, zmax = V[:, 2].min(), V[:, 2].max()
k = H / (zmax - zmin)
body.data.transform(Matrix.Translation((-np.median(V[:, 0]), -np.median(V[:, 1]), -zmin)))
body.data.transform(Matrix.Scale(k, 4))
V = np.array([v.co[:] for v in body.data.vertices])


def slice_y(z, x0=None, x1=None, band=0.02):
    m = np.abs(V[:, 2] - z) < band * H
    if x0 is not None:
        m &= (V[:, 0] >= x0) & (V[:, 0] <= x1)
    return float(np.median(V[m, 1])) if m.any() else 0.0


def leg_x(z, side):
    m = (np.abs(V[:, 2] - z) < 0.02 * H) & ((V[:, 0] > 0.01) if side > 0 else (V[:, 0] < -0.01))
    return float(np.mean(V[m, 0])) if m.any() else side * 0.07 * H


# Proportions read off the T-pose (fractions of height), then measured where possible.
tip = float(V[:, 0].max())
arm_m = np.abs(V[:, 0]) > 0.3 * H
arm_z = float(np.median(V[arm_m, 2])) / H
arm_y = float(np.median(V[arm_m, 1]))
chest = np.abs(V[:, 2] - (arm_z - 0.1) * H) < 0.015 * H
torso_half = float(np.percentile(np.abs(V[chest, 0]), 97))
P = {
    "hip_z": 0.52, "spine_z": 0.585, "spine1_z": 0.65, "spine2_z": 0.715, "neck_z": arm_z + 0.035,
    "head_z": arm_z + 0.07, "top_z": 1.0, "arm_z": arm_z,
    "clav_x": 0.03, "shoulder_x": max(0.07, torso_half / H - 0.02), "elbow_x": 0.27 * tip / (0.433 * H) * 0.433 / 0.433,
    "wrist_x": 0.34, "hand_end_x": tip / H, "knee_z": 0.27, "ankle_z": 0.075, "toe_z": 0.018,
}
P["elbow_x"] = (P["shoulder_x"] + P["wrist_x"]) / 2 + 0.01
P.update(over)
for side, s in (("Left", 1), ("Right", -1)):
    P[side + "_hip_x"] = leg_x(0.36 * H, s) * 0.9
    P[side + "_ankle_x"] = leg_x(0.12 * H, s)
foot = V[:, 2] < 0.04 * H
toe_y = float(np.percentile(V[foot, 1], 2))
heel_y = float(np.percentile(V[foot, 1], 98))
print("RIG_LANDMARKS", json.dumps({k2: round(v, 4) for k2, v in P.items()}), "tip", round(tip, 3), "toe_y", round(toe_y, 3), "heel_y", round(heel_y, 3))

J = {}
J["Hips"] = Vector((0, slice_y(P["hip_z"] * H), P["hip_z"] * H))
J["Spine"] = Vector((0, slice_y(P["spine_z"] * H), P["spine_z"] * H))
J["Spine1"] = Vector((0, slice_y(P["spine1_z"] * H), P["spine1_z"] * H))
J["Spine2"] = Vector((0, slice_y(P["spine2_z"] * H), P["spine2_z"] * H))
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

# Fists: the mitten hands are bent into fists before skinning (they always
# hold something). The fingers beyond the knuckle line roll toward the palm
# around an axis across the palm, like a bend deformer; that axis is where the
# sword's grip and the shield's handle sit.
FIST = {}
THICK = 1.5  # blade and guard drawn 50% thicker than Tripo's; the grip keeps its size so the fist closes on it
_sv = np.array([v.co[:] for v in sword.data.vertices])
_sv = _sv - [np.median(_sv[:, 0]), np.median(_sv[:, 1]), _sv[:, 2].min()]
_sv = _sv * (1.0 / np.ptp(_sv[:, 2]))
_zs = np.linspace(0.0, 0.35, 70)
_wd = [np.ptp(_sv[np.abs(_sv[:, 2] - z) < 0.006, 0]) if (np.abs(_sv[:, 2] - z) < 0.006).any() else 0 for z in _zs]
_gz = float(_zs[int(np.argmax(_wd))]) * 0.5
_gs = _sv[np.abs(_sv[:, 2] - _gz) < 0.012]
GRIP_R = 0.5 * max(np.ptp(_gs[:, 0]), np.ptp(_gs[:, 1])) if len(_gs) else 0.02
print("RIG_GRIP radius %.4f" % GRIP_R)


def make_fist(side, s):
    wx = abs(J[side + "Hand"].x)
    tipx = abs(J[side + "HandEnd"].x) / 0.98
    me = body.data
    co = np.array([v.co[:] for v in me.vertices])
    az = J[side + "Hand"].z
    ay = J[side + "Hand"].y
    near = (np.abs(co[:, 2] - az) < 0.09) & (np.abs(co[:, 1] - ay) < 0.09) & (co[:, 0] * s > wx - 0.01)
    hand = co[near]
    if not len(hand):
        return
    # A tight fist: the palm's surface wraps the grip (curl radius = grip
    # radius), the fingers are shortened so even the longest wraps at most 290
    # degrees, and they are made a little slimmer, so they read as a closed
    # fist rather than long fingers hooked round the hilt.
    knuck = wx + 0.30 * (tipx - wx)
    knuck_pts = hand[np.abs(np.abs(hand[:, 0]) - knuck) < 0.015]
    palm_z = float(knuck_pts[:, 2].min()) if len(knuck_pts) else az - 0.02
    yc = float(np.median(knuck_pts[:, 1])) if len(knuck_pts) else ay
    Rr = GRIP_R + 0.002
    Lmax = tipx - knuck
    comp = min(1.0, math.radians(290) * Rr / Lmax)
    slim = 0.72
    u = Vector((s, 0, 0))   # along the fingers
    w = Vector((0, 0, 1))   # back of the hand (palm faces down in the T-pose)
    K = Vector((s * knuck, yc, palm_z))
    O = K - w * Rr
    # The thumb sticks out sideways near the wrist (toward the body's front):
    # it is folded across the grip from the other side.
    thumb_y = yc - 0.035
    for v in me.vertices:
        p = v.co
        if abs(p.z - az) > 0.09 or abs(p.y - ay) > 0.09:
            continue
        d = (p.x - K.x) * s
        if p.y < thumb_y and -0.04 < d < 0.03:
            # Thumb: swing it down round the grip axis.
            rel = p - Vector((p.x, O.y, O.z))
            ang = math.radians(70)
            ca, sa = math.cos(ang), math.sin(ang)
            ny = rel.y * ca - rel.z * sa
            nz = rel.y * sa + rel.z * ca
            v.co = Vector((p.x, O.y + ny * 0.8, O.z + nz * 0.8))
            continue
        if d <= 0 or abs(p.x) > tipx + 0.01:
            continue
        hgt = (p - K).dot(w)
        phi = d * comp / Rr
        rho = Rr + max(0.0, hgt) * slim + min(0.0, hgt)
        # The curled fingers press together into one closed fist.
        lateral = Vector((0, (p.y - K.y) * (1.0 - 0.18 * min(1.0, phi / math.pi)), 0))
        v.co = O + u * (rho * math.sin(phi)) + w * (rho * math.cos(phi)) + lateral
    FIST[side] = {"axis_point": O.copy(), "radius": Rr}
    print("RIG_FIST", side, "knuckles x %.3f" % knuck, "curl radius %.3f" % Rr, "finger length x%.2f" % comp, "grip axis", [round(c, 3) for c in O])


make_fist("Right", -1)
make_fist("Left", 1)
V = np.array([v.co[:] for v in body.data.vertices])

# Armature: Mixamo names and parents.
arm_data = bpy.data.armatures.new("FootmanRig")
rig = bpy.data.objects.new("FootmanRig", arm_data)
sc.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
EB = arm_data.edit_bones
CHAIN = [
    ("Hips", None, "Spine"), ("Spine", "Hips", "Spine1"), ("Spine1", "Spine", "Spine2"), ("Spine2", "Spine1", "Neck"),
    ("Neck", "Spine2", "Head"), ("Head", "Neck", "HeadTop_End"), ("HeadTop_End", "Head", None),
]
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
        b.use_connect = name not in ("Hips",) and not name.endswith(("Shoulder", "UpLeg")) and (b.head - b.parent.tail).length < 1e-4
for b in EB:
    # Limbs roll so their Z axis points the same way as the Mixamo rest (up for arms, forward for legs).
    if "Arm" in b.name or "Hand" in b.name or "Shoulder" in b.name:
        b.align_roll(Vector((0, 0, -1)))
    else:
        b.align_roll(Vector((0, -1, 0)))
bpy.ops.object.mode_set(mode="OBJECT")
# Deform bones only where skin follows (no end bones).
for b in arm_data.bones:
    b.use_deform = not b.name.endswith(("HeadTop_End", "Toe_End"))

# Skin: automatic weights.
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
groups = {g.index: g.name for g in body.vertex_groups}
unweighted = [v.index for v in body.data.vertices if not any(g.weight > 1e-3 for g in v.groups)]
# Bone heat leaves loose shells (pouches, buckles) unweighted: give each such
# vertex to the deforming bone whose segment is nearest.
segs = [(b.name, Vector(b.head_local), Vector(b.tail_local)) for b in arm_data.bones if b.use_deform]


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(1e-9, ab.length_squared)))
    return (p - (a + ab * t)).length


for vi in unweighted:
    p = body.data.vertices[vi].co
    name = min(segs, key=lambda s: seg_dist(p, s[1], s[2]))[0]
    vg = body.vertex_groups.get(name) or body.vertex_groups.new(name=name)
    vg.add([vi], 1.0, "REPLACE")
left = sum(1 for v in body.data.vertices if not any(g.weight > 1e-3 for g in v.groups))
print("RIG_SKIN groups", len(body.vertex_groups), "unweighted", len(unweighted), "-> after nearest-bone fill", left, "of", len(body.data.vertices))


def fit_prop(obj, length):
    """Scale a prop (1 m Tripo bounds, long axis Z) to `length` metres."""
    vv = np.array([v.co[:] for v in obj.data.vertices])
    s = length / (vv[:, 2].max() - vv[:, 2].min())
    obj.data.transform(Matrix.Translation((-np.median(vv[:, 0]), -np.median(vv[:, 1]), -vv[:, 2].min())))
    obj.data.transform(Matrix.Scale(s, 4))
    return np.array([v.co[:] for v in obj.data.vertices])


# Sword: 1.0 m. Its grip centre (between pommel and guard) goes into the fist.
sv = fit_prop(sword, 1.0)
_zg = np.linspace(0.0, 0.35, 70)
_wg = [np.ptp(sv[np.abs(sv[:, 2] - z) < 0.006, 0]) if (np.abs(sv[:, 2] - z) < 0.006).any() else 0 for z in _zg]
_guard0 = float(_zg[int(np.argmax(_wg))])
for v in sword.data.vertices:
    # Blade and guard 50% wider and thicker, the grip and pommel unchanged,
    # blended over 2 cm under the guard.
    t = min(1.0, max(0.0, (v.co.z - (_guard0 - 0.035)) / 0.02))
    k = 1.0 + (THICK - 1.0) * t
    v.co.x *= k
    v.co.y *= k
sv = np.array([v.co[:] for v in sword.data.vertices])
# Guard: the widest slice in the lower third; grip centre halfway to the pommel.
zs = np.linspace(0.0, 0.35, 70)
widths = [np.ptp(sv[np.abs(sv[:, 2] - z) < 0.006, 0]) if (np.abs(sv[:, 2] - z) < 0.006).any() else 0 for z in zs]
guard_z = float(zs[int(np.argmax(widths))])
grip_z = guard_z * 0.5 + 0.012
sword.data.transform(Matrix.Translation((0, 0, -grip_z)))
# Shield: 0.95 m tall kite.
hv = fit_prop(shield, 0.95)
shield.data.transform(Matrix.Translation((0, 0, -0.5 * 0.95)))
# Shield face: Tripo exports it facing -Y (its front view), long axis Z.

def hand_frame(side):
    """Mixamo's rest frame of the hand (world), at this rig's hand joint."""
    if side == "Right":
        x, y, z = Vector((0, -1, 0)), Vector((-1, 0, 0)), Vector((0, 0, -1))
    else:
        x, y, z = Vector((0, 1, 0)), Vector((1, 0, 0)), Vector((0, 0, -1))
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = J[side + "Hand"]
    return m


# Sword local frame in the right hand: blade along +X, grip in the palm (a
# little toward the fingers and below the knuckles), flat of the blade facing Y.
hr = hand_frame("Right")
palm = (J["RightHandEnd"] - J["RightHand"]).length * 0.42
# Rows: hand X = blade (mesh Z), hand Y = guard span (mesh X), hand Z = flat (mesh Y);
# the grip sits toward the fingers and inside the fist (hand +Z is the palm side).
sword_local = Matrix(((0, 0, 1, 0), (1, 0, 0, palm), (0, 1, 0, 0.035), (0, 0, 0, 1)))
if "Right" in FIST:
    # The grip runs along the fist's curl axis: the fingers wrap the hilt.
    g = hr.inverted() @ FIST["Right"]["axis_point"]
    sword_local[0][3], sword_local[1][3], sword_local[2][3] = g.x, g.y, g.z
sword.matrix_world = hr @ sword_local
# Shield on the left forearm: long axis along the hand's -X, face (the mesh's
# -Y side) along the hand's -Z, centred a little up the forearm and in front of it.
hl = hand_frame("Left")
fore = (J["LeftHand"] - J["LeftForeArm"]).length
up = (hl.to_3x3() @ Vector((-1, 0, 0))).normalized()
out = (hl.to_3x3() @ Vector((0, 0, -1))).normalized()
back = -out
side_v = back.cross(up).normalized()
Ms = Matrix((side_v, back, up)).transposed().to_4x4()
# Strapped on: tight against the back of the forearm (5 cm out) and hung low,
# so the forearm crosses the shield's upper part and the fist holds the handle.
Ms.translation = J["LeftHand"] + (hl.to_3x3() @ Vector((0.13, -fore * 0.3, -0.05)))
shield.matrix_world = Ms
for obj, bone in ((sword, "RightHand"), (shield, "LeftHand")):
    mw = obj.matrix_world.copy()
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = "mixamorig:" + bone
    obj.matrix_world = mw

rig["landmarks"] = json.dumps({k2: list(v) for k2, v in J.items()})
out_blend.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend), compress=True)
print("RIG_SAVED", out_blend)
