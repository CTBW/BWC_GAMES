"""Rig the succubus for Mixamo clips (background Blender; see build_succubus.py for the
BLENDER_USER_RESOURCES note).

  blender -b succubus_base.blend --factory-startup --python rig_succubus.py -- <out.blend>

Adapted from spearman_3d/tools/rig_spearman.py:
1. Recentres the body front to back on her hip joints, so she turns on the spot.
2. Builds a skeleton with the Mixamo bone names and hierarchy (no finger bones). The joints
   come from ray-cast silhouettes of the T-pose (succubus_3d/review notes, 23 Oct 2026):
   arm line z 1.47, shoulder x 0.19, elbow 0.42, wrist 0.645 (glove cuff), knee z 0.60,
   ankle z 0.14 (anklet); the toes point along her paws, 18 degrees outwards.
3. Closes the left hand into a fist round the whip's handle (her attack is left-handed);
   the whip's handle is skinned to its own bone in that hand (WhipGrip), the coil beyond
   the collar to a bone of its own (WhipCoil), and a bladed lash (built here, LASH_L long
   on LASH_N bones from the collar) waits along the handle's axis: whip_motion.py hides it
   (its first bone scaled to nothing) except in the attack, where it plays out of the
   collar while the coil rolls up.
4. Mounts the tail where Tripo's spike was (lower back, z 1.10), tilted back just enough
   that it clears her buttocks and legs, with a chain of TAIL_N bones along its centre.
5. Splits the wings, mounts each on a shoulder blade swept back WING_SWEEP degrees, with a
   root and three bones each (shoulder to wrist claw, two along the longest finger).
6. Skins the body with automatic weights (tail and wing bones excluded), gives the paw
   pads and fur tufts the weights of the skin under them, and weights the tail and the
   wings along their own chains.
7. Gives the loincloth (the front panel) its own chain of LOIN_N bones from the hips and
   takes every leg weight off it, so a leg cannot drag it aside; secondary_motion.py swings
   it over whichever thigh is furthest forward. The user chose this over the panel skinned
   with the legs after a side-by-side comparison (review/loincloth_compare, 24 Oct 2026);
   LOINCLOTH=0 builds the old way.
"""
import json
import math
import os
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, kdtree

H = 1.95
TAIL_N = 6
TAIL_Z = 1.10            # height of the tail's root on her back (where the spike was)
TAIL_TILT = 45           # least tilt back from vertical (the reference hangs at 40-45)
WING_Z = 1.38            # height of the wing roots on her shoulder blades
WING_X = 0.075
WING_SWEEP = 25.0        # wings swept back from the plane of her back (degrees)
WING_LEAN = 10.0         # and their tops leaned back
GRIP_TILT = 40.0         # whip handle tilted from the fist's axis towards the fingers
WHIP_COLLAR = 0.095      # the collar's end, along the handle from the grip centre (m)
LASH_L, LASH_N = 2.0, 16 # the attack's lash: length (m) and bones
LOINCLOTH = os.environ.get("LOINCLOTH", "1") != "0"   # 0: the panel is skinned with the body
LOIN_N = 3               # bones down the loincloth (the front panel)
LOIN_HALF = 0.068        # its half-width
argv = sys.argv[sys.argv.index("--") + 1:]
out_blend = Path(argv[0])
sc = bpy.context.scene
body = bpy.data.objects["Succubus"]
wings_src, tail, whip = (bpy.data.objects[n] for n in ("Wings", "Tail", "Whip"))
for o in (wings_src, tail, whip):
    o.location = (0, 0, 0)          # parked beside her in the base scene
me = body.data
V = np.array([v.co[:] for v in me.vertices])
assert abs(V[:, 2].max() - H) < 0.01 and abs(V[:, 2].min()) < 0.01
tagged = set()
for g in ("PawPads", "FurTufts"):
    vg = body.vertex_groups.get(g)
    if vg:
        tagged.update(v.index for v in me.vertices if any(x.group == vg.index for x in v.groups))
skin = np.array([i not in tagged for i in range(len(V))])


def slice_y(z, x0, x1, band=0.02):
    """Depth centre of the body (pads and tufts left out) at height z between x0 and x1."""
    m = skin & (np.abs(V[:, 2] - z) < band) & (V[:, 0] >= x0) & (V[:, 0] <= x1)
    if not m.any():
        return 0.0
    ys = V[m, 1]
    return float((np.percentile(ys, 3) + np.percentile(ys, 97)) / 2)


# 1. Centre on the hip joints.
dy = -(slice_y(0.90, 0.06, 0.25) + slice_y(0.90, -0.25, -0.06)) / 2
me.transform(Matrix.Translation((0, dy, 0)))
me.update()
V[:, 1] += dy
bpy.context.view_layer.update()
print("RIG_RECENTRE y by %.3f" % dy)


def leg_centre(z, s):
    """x centre of the leg's silhouette (seen from the front) at height z."""
    hits = []
    for x in np.arange(0.06, 0.5, 0.004):
        ok, *_ = body.ray_cast(Vector((s * x, -2, z)), Vector((0, 1, 0)))
        if ok:
            hits.append(x)
    runs, cur = [], []
    for x in hits:
        if cur and x - cur[-1] > 0.006:
            runs.append(cur)
            cur = []
        cur.append(x)
    if cur:
        runs.append(cur)
    r = max(runs, key=lambda r: r[-1] - r[0])
    return s * (r[0] + r[-1]) / 2


# 2. Joints.
J = {}
for n, z in (("Hips", 0.98), ("Spine", 1.08), ("Spine1", 1.20), ("Spine2", 1.33)):
    J[n] = Vector((0, slice_y(z, -0.10, 0.10), z))
J["Neck"] = Vector((0, slice_y(1.53, -0.05, 0.05), 1.53))
J["Head"] = Vector((0, slice_y(1.62, -0.05, 0.05), 1.62))
J["HeadTop_End"] = Vector((0, J["Head"].y, 1.86))
arm = skin & (np.abs(V[:, 0]) > 0.3) & (np.abs(V[:, 0]) < 0.6) & (np.abs(V[:, 2] - 1.47) < 0.06)
ARM_Y, ARM_Z = float(np.median(V[arm, 1])), 1.472
TOE_OUT = math.radians(18)
for side, s in (("Left", 1), ("Right", -1)):
    J[side + "Shoulder"] = Vector((s * 0.035, ARM_Y, ARM_Z - 0.017))
    J[side + "Arm"] = Vector((s * 0.19, ARM_Y, ARM_Z))
    J[side + "ForeArm"] = Vector((s * 0.42, ARM_Y, ARM_Z))
    J[side + "Hand"] = Vector((s * 0.645, ARM_Y, ARM_Z))
    J[side + "HandEnd"] = Vector((s * 0.80, ARM_Y, ARM_Z))
    J[side + "UpLeg"] = Vector((s * 0.115, slice_y(0.90, min(0, s * 0.25), max(0, s * 0.25)), 0.92))
    kx = leg_centre(0.60, s)
    J[side + "Leg"] = Vector((kx, slice_y(0.60, kx - 0.06, kx + 0.06) - 0.01, 0.60))
    ax = leg_centre(0.14, s)
    J[side + "Foot"] = Vector((ax, slice_y(0.14, ax - 0.05, ax + 0.05), 0.14))
    d = Vector((s * math.sin(TOE_OUT), -math.cos(TOE_OUT), 0))
    J[side + "ToeBase"] = Vector((J[side + "Foot"].x, J[side + "Foot"].y, 0.035)) + d * 0.10
    J[side + "Toe_End"] = J[side + "ToeBase"] + d * 0.055 + Vector((0, 0, -0.01))

# 3. Left fist round the whip's handle. The handle: the whip's straight part above the coil.
WV = np.array([v.co[:] for v in whip.data.vertices])
zmax = WV[:, 2].max()
handle = WV[(WV[:, 2] > zmax - 0.23) & (WV[:, 2] < zmax - 0.03)]
HC = Vector(handle.mean(0))
GRIP_R = float((np.percentile(handle[:, 0], 97) - np.percentile(handle[:, 0], 3)) / 2)
print("RIG_WHIP handle centre", [round(c, 3) for c in HC], "radius %.4f" % GRIP_R)
FIST = {}


def make_fist(side, s, grip_r):
    """As rig_spearman.make_fist: fingers past the knuckles wrap round an axis along Y
    under the palm; the thumb folds across."""
    wx = abs(J[side + "Hand"].x)
    tipx = abs(J[side + "HandEnd"].x) / 0.98 + 0.02
    co = np.array([v.co[:] for v in me.vertices])
    az, ay = J[side + "Hand"].z, J[side + "Hand"].y
    near = (np.abs(co[:, 2] - az) < 0.09) & (np.abs(co[:, 1] - ay) < 0.09) & (co[:, 0] * s > wx - 0.01)
    hand = co[near]
    knuck = wx + 0.38 * (tipx - wx)
    knuck_pts = hand[np.abs(np.abs(hand[:, 0]) - knuck) < 0.015]
    palm_z = float(knuck_pts[:, 2].min()) if len(knuck_pts) else az - 0.02
    yc = float(np.median(knuck_pts[:, 1])) if len(knuck_pts) else ay
    Rr = grip_r + 0.002
    comp = min(1.0, math.radians(290) * Rr / (tipx - knuck))
    slim = 0.72
    u, w = Vector((s, 0, 0)), Vector((0, 0, 1))
    K = Vector((s * knuck, yc, palm_z))
    O = K - w * Rr
    thumb_y = yc - 0.03
    for v in me.vertices:
        p = v.co
        if abs(p.z - az) > 0.09 or abs(p.y - ay) > 0.09 or p.x * s < wx - 0.01:
            continue
        d = (p.x - K.x) * s
        if p.y < thumb_y and -0.05 < d < 0.03 and p.z < az:
            rel = p - Vector((p.x, O.y, O.z))
            ca, sa = math.cos(math.radians(70)), math.sin(math.radians(70))
            v.co = Vector((p.x, O.y + (rel.y * ca - rel.z * sa) * 0.8, O.z + (rel.y * sa + rel.z * ca) * 0.8))
            continue
        if d <= 0 or abs(p.x) > tipx + 0.02:
            continue
        hgt = (p - K).dot(w)
        phi = d * comp / Rr
        rho = Rr + max(0.0, hgt) * slim + min(0.0, hgt)
        lateral = Vector((0, (p.y - K.y) * (1.0 - 0.18 * min(1.0, phi / math.pi)), 0))
        v.co = O + u * (rho * math.sin(phi)) + w * (rho * math.cos(phi)) + lateral
    me.update()
    FIST[side] = O.copy()
    print("RIG_FIST", side, "knuckles x %.3f" % knuck, "grip axis", [round(c, 3) for c in O])


make_fist("Left", 1, GRIP_R)

# Her skin alone (no paw pads, no fur tufts): bone heat fails on those loose pieces (it gave
# up for most of her with them in), and the tail's clearance test is fooled by the spikes.
clean = body.copy()
clean.data = body.data.copy()
clean.name = clean.data.name = "SuccubusSkin"
sc.collection.objects.link(clean)
bm = bmesh.new()
bm.from_mesh(clean.data)
bm.verts.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index in tagged], context="VERTS")
bm.to_mesh(clean.data)
bm.free()
for g in list(clean.vertex_groups):
    clean.vertex_groups.remove(g)
bpy.context.view_layer.update()

# The whip: handle centre on the grip axis, the handle along the fist's axis (Y) tilted
# GRIP_TILT towards the fingers, pommel back, the coil flat in the plane of the hand.
O = FIST["Left"]
a = math.radians(GRIP_TILT)
hdir = Vector((math.sin(a), -math.cos(a), 0)).normalized()     # from pommel to collar
side_dir = Vector((0, 0, 1)).cross(-hdir).normalized()          # in the hand's plane
Rw = Matrix((side_dir, Vector((0, 0, 1)), -hdir)).transposed()  # whip local x, y, z -> world
whip.data.transform(Matrix.Translation(-HC))
whip.data.transform(Rw.to_4x4())
whip.data.transform(Matrix.Translation(O))
whip.data.update()
# Handle: pommel to collar, within 4 cm of its axis. Everything else is the coil.
WC = np.array([v.co[:] for v in whip.data.vertices]) - np.array(O)
t_ax = WC @ np.array(hdir)
r_ax = np.linalg.norm(WC - np.outer(t_ax, np.array(hdir)), axis=1)
COIL = np.nonzero((t_ax > WHIP_COLLAR) | (r_ax > 0.04))[0].tolist()
COLLAR = O + hdir * WHIP_COLLAR
print("RIG_WHIP handle vertices", len(WC) - len(COIL), "coil", len(COIL))

# 4. Tail. Its local frame: the root stump at the top (z max), the S-curve in x-z.
TV = np.array([v.co[:] for v in tail.data.vertices])
top = TV[TV[:, 2] > TV[:, 2].max() - 0.04].mean(0)
ok, back_pt, _, _ = body.ray_cast(Vector((0, 1.0, TAIL_Z)), Vector((0, -1, 0)))
assert ok, "no back surface at the tail's root"
root = back_pt + Vector((0, -0.02, 0))   # sunk 2 cm into her back
probe = TV[np.linalg.norm(TV - top, axis=1) > 0.22][::3]   # the bushy root may sit in her


def tail_xform(mirror, tilt):
    """Local tail -> world: x (the S-curve's side) to -/+Y, tilted back about X."""
    M = Matrix(((0, mirror, 0), (-mirror, 0, 0), (0, 0, 1)))   # a rotation either way
    R = Matrix.Rotation(math.radians(tilt), 3, "X") @ M        # + tilt: the tip swings back (+Y)
    return lambda p: root + R @ (Vector(p) - Vector(top)), R


def inside(p):
    ok_, loc, nrm, _ = clean.closest_point_on_mesh(p)
    return ok_ and (p - loc).dot(nrm) < -0.015     # more than 1.5 cm into her


# The reference tail hangs 40-45 degrees back from vertical: start there, and tilt further
# only if the bushy tail still cuts into her.
best = None
for mirror in (1, -1):
    for tilt in range(TAIL_TILT, 76, 5):
        f, _ = tail_xform(mirror, tilt)
        n_in = sum(inside(f(p)) for p in probe)
        if best is None or (n_in, tilt) < (best[0], best[2]):
            best = (n_in, mirror, tilt)
        if n_in == 0:
            break
print("RIG_TAIL mirror", best[1], "tilt", best[2], "probe points inside her", best[0])
f, RT = tail_xform(best[1], best[2])
tail.data.transform(Matrix.Translation(-Vector(top)))
tail.data.transform(RT.to_4x4())
tail.data.transform(Matrix.Translation(root))
tail.data.update()
# Centre line: slice the tail along its own height, then even spacing by arc length.
zs = np.linspace(TV[:, 2].max() - 0.01, TV[:, 2].min() + 0.01, 40)
cl = [f(top)]
for z in zs[1:]:
    m = np.abs(TV[:, 2] - z) < 0.02
    if m.any():
        cl.append(f(TV[m].mean(0)))
cl.append(f(TV[TV[:, 2] < TV[:, 2].min() + 0.02].mean(0)))
# smooth the slice centres (a slice through a bend can jump between the two sides)
cl = [cl[0]] + [sum(cl[max(0, i - 2):i + 3], Vector()) / len(cl[max(0, i - 2):i + 3])
                 for i in range(1, len(cl) - 1)] + [cl[-1]]
seg = np.cumsum([0] + [(cl[i + 1] - cl[i]).length for i in range(len(cl) - 1)])
TAIL_PTS = []
for t in np.linspace(0, seg[-1], TAIL_N + 1):
    i = min(int(np.searchsorted(seg, t, side="right")) - 1, len(cl) - 2)
    k = (t - seg[i]) / max(1e-9, seg[i + 1] - seg[i])
    TAIL_PTS.append(cl[i].lerp(cl[i + 1], k))
print("RIG_TAIL length %.3f" % seg[-1])

# 5. Wings: split, mount on the shoulder blades, swept back.
WINGS = {}
for side, s in (("Left", 1), ("Right", -1)):
    ob = wings_src.copy()
    ob.data = wings_src.data.copy()
    ob.name = ob.data.name = "Wing" + side
    sc.collection.objects.link(ob)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.x * s < 0], context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
    WV2 = np.array([v.co[:] for v in ob.data.vertices])
    ax_ = np.abs(WV2[:, 0])
    knob = WV2[ax_ < ax_.min() + 0.10].mean(0)
    wrist = WV2[np.argmax(WV2[:, 2])]
    tipv = WV2[np.argmax(ax_)]
    ok, bp, _, _ = body.ray_cast(Vector((s * WING_X, 1.0, WING_Z)), Vector((0, -1, 0)))
    assert ok
    mount = bp + Vector((0, 0.025, 0))
    R = Matrix.Rotation(math.radians(s * WING_SWEEP), 3, "Z") @ Matrix.Rotation(-math.radians(WING_LEAN), 3, "X")
    fw = (lambda R_, k_, m_: (lambda p: m_ + R_ @ (Vector(p) - Vector(k_))))(R, knob, mount)
    ob.data.transform(Matrix.Translation(-Vector(knob)))
    ob.data.transform(R.to_4x4())
    ob.data.transform(Matrix.Translation(mount))
    ob.data.update()
    WINGS[side] = {"ob": ob, "knob": fw(knob), "wrist": fw(wrist), "tip": fw(tipv)}
    print("RIG_WING", side, "knob", [round(c, 3) for c in fw(knob)], "wrist", [round(c, 3) for c in fw(wrist)],
          "tip", [round(c, 3) for c in fw(tipv)])
bpy.data.objects.remove(wings_src)

# 5b. Loincloth: the front panel (a thin slab about 12 cm wide hanging from the lower belly,
# free below the crotch at z 0.76). Its vertices: within LOIN_HALF of the middle, in front of
# y -0.09 and below z 0.92 (her thighs bulge forward only beyond x 0.07).
PANEL = [v.index for v in me.vertices if v.index not in tagged and abs(v.co.x) <= LOIN_HALF
         and v.co.y < -0.09 and v.co.z < 0.92] if LOINCLOTH else []
if PANEL:
    PZ = [me.vertices[i].co.z for i in PANEL]
    PY = sum(me.vertices[i].co.y for i in PANEL) / len(PANEL)
    LOIN_PTS = [Vector((0, PY, max(PZ) - (max(PZ) - min(PZ)) * k / LOIN_N)) for k in range(LOIN_N + 1)]
    print("RIG_LOINCLOTH vertices", len(PANEL), "z %.2f-%.2f" % (min(PZ), max(PZ)))

# Armature.
arm_data = bpy.data.armatures.new("SuccubusRig")
rig = bpy.data.objects.new("SuccubusRig", arm_data)
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
for name, parent, tl in CHAIN:
    b = EB.new("mixamorig:" + name)
    b.head = J[name]
    if tl:
        b.tail = J[tl]
    else:
        prev = J[name] - J[parent]
        b.tail = J[name] + prev.normalized() * max(0.03, prev.length * 0.5)
    if parent:
        b.parent = EB["mixamorig:" + parent]
        b.use_connect = name != "Hips" and not name.endswith(("Shoulder", "UpLeg")) and (b.head - b.parent.tail).length < 1e-4
for side in ("Left", "Right"):
    tb = EB.new(side + "ForeArmTwist")
    tb.head = J[side + "ForeArm"].lerp(J[side + "Hand"], 0.45)
    tb.tail = J[side + "Hand"]
    tb.parent = EB["mixamorig:" + side + "ForeArm"]
for b in EB:
    b.align_roll(Vector((0, 0, -1)) if ("Arm" in b.name or "Hand" in b.name or "Shoulder" in b.name) else Vector((0, -1, 0)))
# Whip grip (not deforming): on the grip axis, along the handle.
wb = EB.new("WhipGrip")
wb.head = O
wb.tail = O + hdir * 0.08
wb.parent = EB["mixamorig:LeftHand"]
wb.align_roll(Vector((0, 0, 1)))
cb = EB.new("WhipCoil")              # the coil, from the collar
cb.head, cb.tail = COLLAR, COLLAR + hdir * 0.06
cb.parent = wb
cb.align_roll(Vector((0, 0, 1)))
prev = wb
for i in range(LASH_N):              # the lash, straight out along the handle
    b = EB.new(f"Lash_{i + 1}")
    b.head = COLLAR + hdir * (LASH_L * i / LASH_N)
    b.tail = COLLAR + hdir * (LASH_L * (i + 1) / LASH_N)
    b.parent = prev
    b.use_connect = i > 0
    b.align_roll(Vector((0, 0, 1)))
    prev = b
# Tail chain: bone Y along the tail, Z backwards, so a sideways sway is a turn about Z.
prev = EB["mixamorig:Hips"]
for i in range(TAIL_N):
    b = EB.new(f"Tail_{i + 1}")
    b.head, b.tail = TAIL_PTS[i], TAIL_PTS[i + 1]
    b.parent = prev
    b.use_connect = i > 0
    b.align_roll(Vector((0, 1, 0)))
    prev = b
# Wings: root on the shoulder blade, then shoulder to wrist claw, then the longest finger.
for side, s in (("Left", 1), ("Right", -1)):
    W = WINGS[side]
    k, wr, tp = W["knob"], W["wrist"], W["tip"]
    mid = wr.lerp(tp, 0.5)
    pts = [("Wing%s_Root" % side, k - (wr - k).normalized() * 0.06, k),
           ("Wing%s_1" % side, k, wr), ("Wing%s_2" % side, wr, mid), ("Wing%s_3" % side, mid, tp)]
    prev = EB["mixamorig:Spine2"]
    for i, (n, h, t) in enumerate(pts):
        b = EB.new(n)
        b.head, b.tail = h, t
        b.parent = prev
        b.use_connect = i > 0
        b.align_roll(Vector((0, 1, 0)))
        prev = b
# Loincloth: a chain down the front panel from the hips (bone Y down the panel, Z forward).
prev = EB["mixamorig:Hips"]
for i in range(LOIN_N if PANEL else 0):
    b = EB.new(f"Loincloth_{i + 1}")
    b.head, b.tail = LOIN_PTS[i], LOIN_PTS[i + 1]
    b.parent = prev
    b.use_connect = i > 0
    b.align_roll(Vector((0, -1, 0)))
    prev = b
bpy.ops.object.mode_set(mode="OBJECT")
EXTRA = [b.name for b in arm_data.bones if b.name.startswith(("Tail_", "Wing", "Whip", "Lash_", "Loincloth_"))]
for b in arm_data.bones:
    b.use_deform = not b.name.endswith(("HeadTop_End", "Toe_End")) and b.name not in EXTRA

# 6. Skin the body: automatic weights on her skin alone, copied back by position.
bpy.ops.object.select_all(action="DESELECT")
clean.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
body.parent = rig
body.modifiers.new("Armature", "ARMATURE").object = rig
kd_c = kdtree.KDTree(len(clean.data.vertices))
for v in clean.data.vertices:
    kd_c.insert(v.co, v.index)
kd_c.balance()
cg = {g.index: g.name for g in clean.vertex_groups}
far = 0
for v in me.vertices:
    if v.index in tagged:
        continue
    _, ci, dist = kd_c.find(v.co)
    far += dist > 1e-4
    for g in clean.data.vertices[ci].groups:
        if g.weight > 1e-4:
            (body.vertex_groups.get(cg[g.group]) or body.vertex_groups.new(name=cg[g.group])).add([v.index], g.weight, "REPLACE")
print("RIG_SKIN copied from her skin copy, vertices not matched exactly", far)
bpy.data.objects.remove(clean)
segs = [(b.name, Vector(b.head_local), Vector(b.tail_local)) for b in arm_data.bones if b.use_deform]


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(1e-9, ab.length_squared)))
    return (p - (a + ab * t)).length


unweighted = [v.index for v in me.vertices if v.index not in tagged and not any(g.weight > 1e-3 for g in v.groups)]
for vi in unweighted:
    p = me.vertices[vi].co
    name = min(segs, key=lambda s_: seg_dist(p, s_[1], s_[2]))[0]
    (body.vertex_groups.get(name) or body.vertex_groups.new(name=name)).add([vi], 1.0, "REPLACE")
# Pads and tufts: the weights of the nearest skin vertex.
kd = kdtree.KDTree(int(skin.sum()))
for i in np.nonzero(skin)[0]:
    kd.insert(me.vertices[int(i)].co, int(i))
kd.balance()
bone_groups = {g.index for g in body.vertex_groups if g.name in arm_data.bones}
copied = 0
for vi in tagged:
    _, src, _ = kd.find(me.vertices[vi].co)
    for g in list(me.vertices[vi].groups):
        if g.group in bone_groups:
            body.vertex_groups[g.group].remove([vi])
    for g in me.vertices[src].groups:
        if g.group in bone_groups:
            body.vertex_groups[g.group].add([vi], g.weight, "REPLACE")
    copied += 1
print("RIG_SKIN groups", len(body.vertex_groups), "filled", len(unweighted), "pads and tufts copied", copied)


def smooth_step(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


for side in ("Left", "Right"):
    fg = body.vertex_groups["mixamorig:" + side + "ForeArm"]
    tg = body.vertex_groups.get(side + "ForeArmTwist") or body.vertex_groups.new(name=side + "ForeArmTwist")
    e, w = J[side + "ForeArm"], J[side + "Hand"]
    axv = w - e
    for v in me.vertices:
        wf = next((g.weight for g in v.groups if g.group == fg.index), 0.0)
        if wf <= 1e-4:
            continue
        k = smooth_step(((v.co - e).dot(axv) / axv.length_squared - 0.3) / 0.6)
        if k > 0:
            fg.add([v.index], wf * (1 - k), "REPLACE")
            tg.add([v.index], wf * k, "REPLACE")
# The fist is rigid: past 2.5 cm beyond the wrist, mostly-hand vertices follow only the hand.
hg = body.vertex_groups["mixamorig:LeftHand"]
wxl = abs(J["LeftHand"].x)
rigid = 0
for v in me.vertices:
    if v.co.x - wxl < 0.025:
        continue
    tot = sum(g.weight for g in v.groups if g.group in bone_groups) or 1.0
    hw = sum(g.weight for g in v.groups if g.group == hg.index) / tot
    if 0.5 <= hw < 0.999:
        for g in list(v.groups):
            if g.group in bone_groups and g.group != hg.index:
                body.vertex_groups[g.group].remove([v.index])
        hg.add([v.index], 1.0, "REPLACE")
        rigid += 1
for side in ("Left", "Right"):
    pb = rig.pose.bones[side + "ForeArmTwist"]
    c = pb.constraints.new("COPY_ROTATION")
    c.target = rig
    c.subtarget = "mixamorig:" + side + "Hand"
    c.use_x = c.use_z = False
    c.use_y = True
    c.target_space = c.owner_space = "LOCAL"
    c.influence = 0.85
print("RIG_FIST rigid vertices", rigid)


LASH_RGB = {  # sRGB: steel and pink as the coil's texture (medians), the core a shade darker
    "core": (0.35, 0.30, 0.37), "steel": (0.42, 0.35, 0.43), "pink": (0.94, 0.37, 0.69), "gold": (0.80, 0.60, 0.27)}


def lash_material():
    """A 64 px texture: the bottom half the core's dark steel (left) and gold (right), the
    top half a ramp from steel to pink for the blades (steel at the core, pink at the edge)."""
    img = bpy.data.images.new("WhipLash_tex", 64, 64)
    px = np.zeros((64, 64, 4))
    px[:, :, 3] = 1
    px[:32, :32, :3] = LASH_RGB["core"]
    px[:32, 32:, :3] = LASH_RGB["gold"]
    ramp = np.clip((np.arange(64) - 8) / 48.0, 0, 1)[:, None]
    px[32:, :, :3] = (np.array(LASH_RGB["steel"]) * (1 - ramp) + np.array(LASH_RGB["pink"]) * ramp)[None]
    img.pixels = px.ravel()
    img.pack()
    mat = bpy.data.materials.new("WhipLash")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.6
    return mat


def lash_normals_out(mesh):
    """Every face of the lash facing out (its rings were built turning the wrong way round,
    which Blender's viewport hides and Godot's back-face culling does not)."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def build_lash(C, d):
    """The attack's lash, straight out of the collar along d: a tapering eight-sided core,
    scale-like blades in pairs, three pairs per bone, pointing back towards the handle (each
    pair turned 40 degrees further round, so some always face the camera), a gold ferrule near the end
    and a hooked blade at the tip, as the concept. Each vertex is skinned by its distance
    along the lash: the core blends across the joints, a blade sits rigidly on its bone.
    Twice as thick as a real whip (its root as wide as the collar): at the game's zoom a
    true-to-life lash drew a one-pixel line (Godot sandbox, 24 Oct 2026)."""
    up = Vector((0, 0, 1))
    side = d.cross(up).normalized()
    up = side.cross(d).normalized()
    seg = LASH_L / LASH_N
    tip_len = 0.13
    core_end = LASH_L - tip_len
    radius = lambda u: 0.016 + 0.016 * (1 - u / LASH_L) ** 0.7
    UV = {"core": (0.25, 0.25), "gold": (0.75, 0.25)}
    ramp = lambda k: (0.1 + 0.8 * k, 0.75)
    verts, faces, fuv, along = [], [], [], []

    def add(p, u_along):
        verts.append(p)
        along.append(u_along)
        return len(verts) - 1

    def ring(u, r):
        return [add(C + d * u + (side * math.cos(a) + up * math.sin(a)) * r, u)
                for a in (2 * math.pi * k / 8 for k in range(8))]

    def tube(us, rs, uv):
        rings = [ring(u, r) for u, r in zip(us, rs)]
        for ra, rb in zip(rings, rings[1:]):
            for k in range(8):
                faces.append((ra[k], ra[(k + 1) % 8], rb[(k + 1) % 8], rb[k]))
                fuv.append([uv] * 4)
        return rings

    us = [core_end * k / (2 * LASH_N) for k in range(2 * LASH_N + 1)]
    rings = tube(us, [radius(u) for u in us], UV["core"])
    faces.append(tuple(reversed(rings[0])))
    fuv.append([UV["core"]] * 8)
    uf = 0.86 * LASH_L                                  # the gold ferrule
    tube([uf - 0.03, uf - 0.02, uf + 0.02, uf + 0.03],
         [radius(uf) * 1.2, radius(uf) * 1.9, radius(uf) * 1.9, radius(uf) * 1.2], UV["gold"])

    def blade(pts, ks, at, e, w0):
        """A flat blade: an outline in the (along d, out along e) plane, given thickness;
        ks: 0 at the core (steel) to 1 at the edge (pink), which also thins it."""
        n_ = d.cross(e).normalized()
        top = [add(C + d * u + e * h + n_ * (w0 * (1 - k) + 0.001), at) for (u, h), k in zip(pts, ks)]
        bot = [add(C + d * u + e * h - n_ * (w0 * (1 - k) + 0.001), at) for (u, h), k in zip(pts, ks)]
        m = len(pts)
        faces.append(tuple(top))
        fuv.append([ramp(k) for k in ks])
        faces.append(tuple(reversed(bot)))
        fuv.append([ramp(k) for k in reversed(ks)])
        for i in range(m):
            j = (i + 1) % m
            faces.append((top[j], top[i], bot[i], bot[j]))
            fuv.append([ramp(ks[j]), ramp(ks[i]), ramp(ks[i]), ramp(ks[j])])

    sp = seg / 3
    for i in range(3 * (LASH_N - 1)):
        u0 = i * sp + 0.45 * sp
        u1 = u0 + 0.8 * sp
        r = radius(u0)
        h = 0.022 + 0.030 * (1 - u0 / LASH_L)
        for half in (0, math.pi):
            a = math.radians(40 * i) + half
            e = side * math.cos(a) + up * math.sin(a)
            pts = [(u1, 0.5 * r), (u0 + 0.5 * (u1 - u0), r + 0.55 * h), (u0 - 0.45 * sp, r + h), (u0, 0.5 * r)]
            blade(pts, [0.0, 0.6, 1.0, 0.0], (u0 + u1) / 2, e, 0.005)
    # the hooked tip: a leaf from the core's end, its point curving back into a barb
    rt = radius(core_end)
    hook = [(0.0, rt), (0.03, 0.045), (0.07, 0.052), (0.105, 0.028), (tip_len, -0.010),
            (0.10, -0.038), (0.075, -0.058), (0.06, -0.028), (0.03, -0.024), (0.0, -rt)]
    blade([(core_end + u, h) for u, h in hook], [0.0, 0.5, 0.7, 0.85, 1.0, 0.9, 1.0, 0.6, 0.4, 0.0],
          core_end, up, 0.007)
    faces.append(tuple(rings[-1]))
    fuv.append([UV["core"]] * 8)
    me_l = bpy.data.meshes.new("WhipLash")
    me_l.from_pydata([v[:] for v in verts], [], faces)
    uvl = me_l.uv_layers.new(name="UVMap")
    for poly, uvs in zip(me_l.polygons, fuv):
        for li, uv in zip(poly.loop_indices, uvs):
            uvl.data[li].uv = uv
    me_l.validate()
    lash_normals_out(me_l)
    me_l.materials.append(lash_material())
    ob = bpy.data.objects.new("WhipLash", me_l)
    sc.collection.objects.link(ob)
    names = [f"Lash_{i + 1}" for i in range(LASH_N)]
    for n_ in names:
        ob.vertex_groups.new(name=n_)
    for vi, u in enumerate(along):
        x = min(max(u / seg - 0.5, 0.0), LASH_N - 1.0)
        k0 = min(int(x), LASH_N - 2)
        f_ = x - k0
        ob.vertex_groups[names[k0]].add([vi], 1 - f_, "REPLACE")
        if f_ > 1e-3:
            ob.vertex_groups[names[k0 + 1]].add([vi], f_, "REPLACE")
    ob.modifiers.new("Armature", "ARMATURE").object = rig
    ob.parent = rig
    return ob


def chain_weights(ob, names, sigma):
    """Weights by distance to the bones of one chain: a Gaussian falloff, the two nearest."""
    bones = [(n, Vector(arm_data.bones[n].head_local), Vector(arm_data.bones[n].tail_local)) for n in names]
    for n in names:
        if n not in ob.vertex_groups:
            ob.vertex_groups.new(name=n)
    for v in ob.data.vertices:
        ds = sorted(((seg_dist(v.co, h, t), n) for n, h, t in bones))[:2]
        ws = [math.exp(-(d / sigma) ** 2) for d, _ in ds]
        tot = sum(ws) or 1.0
        if ws[0] / tot > 0.98 or tot < 1e-6:
            ob.vertex_groups[ds[0][1]].add([v.index], 1.0, "REPLACE")
            continue
        for (d, n), w_ in zip(ds, ws):
            ob.vertex_groups[n].add([v.index], w_ / tot, "REPLACE")
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    ob.parent = rig


for b in EXTRA:
    if b.startswith(("Tail_", "Wing", "Loincloth_")):
        arm_data.bones[b].use_deform = True
# The loincloth: no leg weights at all (a leg dragged it aside); its own chain, the top
# blending into the hips. Same falloff as the tail and wings, by height along the panel.
segs_l = ([("mixamorig:Hips", LOIN_PTS[0] + Vector((0, 0, 0.10)), LOIN_PTS[0])] +
          [(f"Loincloth_{i + 1}", LOIN_PTS[i], LOIN_PTS[i + 1]) for i in range(LOIN_N)]) if PANEL else []
for n_, _, _ in segs_l:
    if n_ not in body.vertex_groups:
        body.vertex_groups.new(name=n_)
for vi in PANEL:
    p = me.vertices[vi].co
    for g in list(me.vertices[vi].groups):
        if g.group in bone_groups:
            body.vertex_groups[g.group].remove([vi])
    ds = sorted((seg_dist(p, h, t), n_) for n_, h, t in segs_l)[:2]
    ws = [math.exp(-(d / 0.05) ** 2) for d, _ in ds]
    tot = sum(ws) or 1.0
    for (d, n_), w_ in zip(ds, ws):
        body.vertex_groups[n_].add([vi], max(w_ / tot, 1e-3) if tot > 1e-6 else (1.0 if d == ds[0][0] else 0.0), "REPLACE")
if PANEL:
    print("RIG_LOINCLOTH reweighted", len(PANEL))
chain_weights(tail, [f"Tail_{i + 1}" for i in range(TAIL_N)], 0.07)
for side in ("Left", "Right"):
    chain_weights(WINGS[side]["ob"], ["Wing%s_%s" % (side, k) for k in ("Root", "1", "2", "3")], 0.12)
# The whip: rigid on two bones, the handle on WhipGrip and the coil on WhipCoil.
for b in EXTRA:
    if b.startswith(("Whip", "Lash_")):
        arm_data.bones[b].use_deform = True
coil_set = set(COIL)
whip.vertex_groups.new(name="WhipGrip").add([i for i in range(len(whip.data.vertices)) if i not in coil_set], 1.0, "REPLACE")
whip.vertex_groups.new(name="WhipCoil").add(COIL, 1.0, "REPLACE")
whip.modifiers.new("Armature", "ARMATURE").object = rig
whip.parent = rig
lash = build_lash(COLLAR, hdir)
print("RIG_LASH", len(lash.data.vertices), "vertices on", LASH_N, "bones,", LASH_L, "m")

rig["landmarks"] = json.dumps({k: list(v) for k, v in J.items()})
rig["tail_points"] = json.dumps([list(p) for p in TAIL_PTS])
rig["grip_r"] = GRIP_R
rig["whip_collar"] = list(COLLAR)
rig["lash"] = json.dumps({"length": LASH_L, "bones": LASH_N})
out_blend.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend), compress=True)
print("RIG_SAVED", out_blend)
