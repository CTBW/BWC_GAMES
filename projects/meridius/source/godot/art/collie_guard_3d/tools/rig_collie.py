"""Rig the collie Royal Guard for the footman's clips (background Blender).

  blender -b collie_base.blend --factory-startup --python rig_collie.py -- <out.blend>

The base scene is build_collie.py's: the body at the Mixamo height (skull top 1.82 m), the
tail, sword and shield parked beside him. As footman_3d/tools/rig_footman.py, with what the
collie needs besides:

1. Joints on the mesh: the footman's proportions for the hips, spine and legs, the collie's
   own measured ones (ARM_X, NECK_Z, HEAD_Z) for his longer arms, big gauntlets and a dog's
   head. Each arm is one straight line along X through its cross-sections' middles, as the
   footman's. The armature has FootmanRig's Mixamo names, hierarchy and rolls, so the
   footman's clips carry over bone for bone (transfer_clips.py).
2. Fists. His gauntlets have five fingers, palm down. Beyond the knuckles (KNUCK, where the
   back plate ends) the fingers are rolled round the grip's axis as the footman's mittens
   were, and pressed together (PRESS) to fit the grip. The thumb hangs under the palm in
   front of the fingers: it is moved out of the grip, onto its side.
3. Skin: bone heat on the body, the loose shells it misses to the nearest bone. The raised
   collars of his pauldrons get no neck or head weight (they turned with the head).
4. The sword in the right fist, the shield strapped to the left forearm, in the footman's
   hand frames (sword along the hand's +X, shield face along -Z, long axis along -X), so
   his clips swing them as they swing the footman's. The sword's guard sits just in front of
   the thumb; the shield is raised off the forearm (SHIELD_GAP) clear of his bracer and fist.
   Its arm strap (8.) and grip (9.) ride on the hand bone with it.
5. Tail. Tripo modelled it with its root stump at its +Y end, hanging and sweeping to a white
   tip that curls up. Turned about so the stump faces his lower back, mounted under the
   belt (TAIL_Z, sunk TAIL_SINK), tilted (the least of TAIL_TILTS) to clear his legs and
   back panel, on a chain of TAIL_N bones along its centre line (slices by distance along
   the surface from the stump), weighted by distance to them, as the succubus's tail.
6. Hanging armour: the tabard's front panel (TabardF), its back panel (TabardB) and the side
   tassets (Tasset.L/.R) get bones of their own on the hips, from nothing at the belt to all
   at the hem (HANG). collie_motion.py keys them from the thighs' swing.
8. The shield's arm strap (ShieldStrap: leather, brass rivets), round the forearm STRAP_AT of
   the way from elbow to wrist. The clips hold the wrist still at the footman's lock
   (WRIST), so the forearm keeps still against the shield in every clip: the strap is fitted
   round its section as the clips hold it (STRAP_GAP off it, long faces cut where they cross
   the strap), then runs to the shield's back at both ends and is riveted there. The upper
   arm folds over the forearm's top in the guard and passes through the strap there, as it
   passes through the forearm.
9. The shield's grip (ShieldGrip): a flat iron bar bent into a staple, its middle wrapped in
   leather as thick as the sword's grip along the left fist's axis, its legs past his hand
   above and below (GRIP_GAP clear of it) and its feet riveted to the shield's back. The fist
   rides on the hand bone alone, so it stands to the shield as in the T-pose.
Saves the .blend; no actions.
"""
import heapq
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

H = 1.82                 # skull top (m), the Mixamo head top
ARM_X = {"Shoulder": 0.06, "Arm": 0.24, "ForeArm": 0.51, "Hand": 0.69}   # |x| of each joint (m)
NECK_Z, HEAD_Z = 1.50, 1.60   # the collar's top; the skull's pivot behind the jaw
KNUCK = 0.81             # |x| of the knuckle line: the gauntlet's back plate ends here
PRESS = 0.3              # the curled fingers pressed this much closer together
THUMB_Y = -0.055         # the thumb: the hand's part in front of this, short of the knuckles
SWORD_L, SHIELD_L = 1.0, 0.92
SHIELD_GAP = 0.012       # least gap between the shield's back and his forearm or fist (m)
STRAP_AT = 0.62          # the arm strap's place along the forearm, from elbow to wrist
STRAP_W, STRAP_TH = 0.045, 0.006   # its width and thickness (m)
STRAP_GAP = 0.004        # its gap to the forearm
STRAP_LEG, STRAP_TAB = 0.015, 0.03   # how far past the forearm it turns to the shield; its riveted ends
RIVET_R = 0.0055
GRIP_W, GRIP_TH = 0.022, 0.006     # the grip's iron bar: width and thickness (m)
GRIP_GAP = 0.004         # its legs' least gap to his hand
GRIP_BEND, GRIP_FOOT = 0.012, 0.045   # its bends' radius; how far its feet reach past its legs
# LeftHand's rotation in every clip: the footman's wrist lock (footman_3d/tools/retarget_clips.py)
# as transfer_clips.py carries it over to this rig. transfer_clips.py warns if the clips differ.
WRIST = Quaternion((0.99959, 0.02846, 0.00033, 0.00328))
TAIL_N = 6
TAIL_Z = 0.90            # height of the tail's root on his back, under the belt
TAIL_SINK = 0.04         # the root stump pressed this far into him
TAIL_TILTS = range(-10, 31, 5)   # + lifts the tail, - lowers it (degrees)
# Hanging armour: rest height where it starts to follow its bone and where it follows fully.
HANG = {"TabardF": (0.95, 0.70), "TabardB": (0.95, 0.70), "Tasset": (1.02, 0.80)}

argv = sys.argv[sys.argv.index("--") + 1:]
out_blend = Path(argv[0])
sc = bpy.context.scene
body, tail, sword, shield = (bpy.data.objects[n] for n in ("Collie", "Tail", "Sword", "Shield"))
me = body.data


def islands(mesh):
    """Loose part of each vertex, and the parts' vertex lists."""
    adj = [[] for _ in mesh.vertices]
    for e in mesh.edges:
        a, b = e.vertices
        adj[a].append(b)
        adj[b].append(a)
    lab = [-1] * len(mesh.vertices)
    parts = []
    for v0 in range(len(mesh.vertices)):
        if lab[v0] >= 0:
            continue
        lab[v0] = len(parts)
        stack, cur = [v0], []
        while stack:
            v = stack.pop()
            cur.append(v)
            for o in adj[v]:
                if lab[o] < 0:
                    lab[o] = len(parts)
                    stack.append(o)
        parts.append(cur)
    return np.array(lab), parts


V = np.array([v.co[:] for v in me.vertices])
LAB, PARTS = islands(me)


def part_where(test):
    return [ids for ids in PARTS if test(V[ids])]


# 1. Joints -------------------------------------------------------------------------------
def slice_y(z, half_x=0.2, band=0.02):
    """The middle of the body's depth at z (a median leans to his front: the tabard, buckles and ruff)."""
    m = (np.abs(V[:, 2] - z) < band * H) & (np.abs(V[:, 0]) < half_x)
    return float(V[m, 1].min() + V[m, 1].max()) / 2


def leg_x(z, side):
    m = (np.abs(V[:, 2] - z) < 0.02 * H) & ((V[:, 0] > 0.01) if side > 0 else (V[:, 0] < -0.01))
    return float(np.mean(V[m, 0]))


# The arm's line: the middles of the forearm's cross-sections (the wrist's turn is about
# it; the upper arm's back plates would pull it behind the fist).
mids = []
for x in np.arange(0.44, 0.70, 0.02):
    for s in (1, -1):
        m = (np.abs(V[:, 0] - s * x) < 0.012) & (V[:, 2] > 1.25)
        if m.sum() > 4:
            mids.append(((V[m, 1].min() + V[m, 1].max()) / 2, (V[m, 2].min() + V[m, 2].max()) / 2))
arm_y, arm_z = (float(np.mean([p[k] for p in mids])) for k in (0, 1))
tip = float(np.abs(V[:, 0]).max())
P = {"hip_z": 0.52, "spine_z": 0.585, "spine1_z": 0.65, "spine2_z": 0.715, "knee_z": 0.27, "ankle_z": 0.075, "toe_z": 0.018}
for side, s in (("Left", 1), ("Right", -1)):
    P[side + "_hip_x"] = leg_x(0.36 * H, s) * 0.9
    P[side + "_ankle_x"] = leg_x(0.12 * H, s)
foot = V[:, 2] < 0.04 * H
toe_y = float(np.percentile(V[foot, 1], 2))
heel_y = float(np.percentile(V[foot, 1], 98))
print("RIG_LANDMARKS arm y %.3f z %.3f tip %.3f" % (arm_y, arm_z, tip), json.dumps({k: round(v, 4) for k, v in P.items()}),
      "toe_y %.3f heel_y %.3f" % (toe_y, heel_y))

J = {}
for n in ("Hips", "Spine", "Spine1", "Spine2"):
    z = P[n.lower() + "_z" if n != "Hips" else "hip_z"] * H
    J[n] = Vector((0, slice_y(z), z))
J["Neck"] = Vector((0, slice_y(NECK_Z, 0.09), NECK_Z))
J["Head"] = Vector((0, slice_y(HEAD_Z, 0.09), HEAD_Z))
J["HeadTop_End"] = Vector((0, J["Head"].y, H))
for side, s in (("Left", 1), ("Right", -1)):
    J[side + "Shoulder"] = Vector((s * ARM_X["Shoulder"], arm_y, arm_z - 0.02))
    for n in ("Arm", "ForeArm", "Hand"):
        J[side + n] = Vector((s * ARM_X[n], arm_y, arm_z))
    J[side + "HandEnd"] = Vector((s * tip * 0.98, arm_y, arm_z))
    hx, ax = P[side + "_hip_x"], P[side + "_ankle_x"]
    hz = P["hip_z"] * H
    J[side + "UpLeg"] = Vector((hx, slice_y(hz - 0.04 * H), hz - 0.03 * H))
    kx = (hx + ax) / 2
    J[side + "Leg"] = Vector((kx, slice_y(P["knee_z"] * H, 0.3) - 0.01, P["knee_z"] * H))
    J[side + "Foot"] = Vector((ax, (toe_y + heel_y) / 2 + 0.25 * (heel_y - toe_y), P["ankle_z"] * H))
    J[side + "ToeBase"] = Vector((ax, toe_y * 0.55 + heel_y * 0.45 - 0.15 * (heel_y - toe_y), P["toe_z"] * H))
    J[side + "Toe_End"] = Vector((ax, toe_y, P["toe_z"] * H))
print("RIG_JOINTS", json.dumps({k: [round(c, 3) for c in v] for k, v in J.items()}))


# 2. Sword measures (the grip's radius sets the fist) -------------------------------------
def fit_prop(obj, length):
    """Scale a prop (long axis Z, pommel or point down) to `length`, its bottom at z = 0."""
    vv = np.array([v.co[:] for v in obj.data.vertices])
    obj.data.transform(Matrix.Translation((-np.median(vv[:, 0]), -np.median(vv[:, 1]), -vv[:, 2].min())))
    obj.data.transform(Matrix.Scale(length / np.ptp(vv[:, 2]), 4))
    obj.location = (0, 0, 0)
    return np.array([v.co[:] for v in obj.data.vertices])


sv = fit_prop(sword, SWORD_L)
zs = np.linspace(0.0, 0.4 * SWORD_L, 81)
wid = np.array([np.ptp(sv[np.abs(sv[:, 2] - z) < 0.006, 0]) if (np.abs(sv[:, 2] - z) < 0.006).any() else 0.0 for z in zs])
guard_lo = float(zs[np.argmax(wid > 0.6 * wid.max())])          # the guard's face towards the pommel
gs = sv[(sv[:, 2] > 0.35 * guard_lo) & (sv[:, 2] < 0.85 * guard_lo)]
GRIP_R = 0.5 * float(np.median([np.ptp(gs[np.abs(gs[:, 2] - z) < 0.006, 0]) for z in np.linspace(0.4, 0.8, 5) * guard_lo
                                if (np.abs(gs[:, 2] - z) < 0.006).sum() > 2]))
print("RIG_SWORD guard face %.3f m above the pommel, grip radius %.4f" % (guard_lo, GRIP_R))


# 3. Fists --------------------------------------------------------------------------------
FIST = {}


def make_fist(side, s):
    hand = max(part_where(lambda p: (p[:, 0] * s).max() > tip - 0.02), key=len)
    co = V[hand]
    tipx = float((co[:, 0] * s).max())
    thumb = (co[:, 1] < THUMB_Y) & (co[:, 0] * s < KNUCK + 0.02)
    kn = co[(np.abs(co[:, 0] * s - KNUCK) < 0.015) & ~thumb]
    palm_z = float(kn[:, 2].min())
    yc = float(np.median(kn[:, 1]))
    Rr = GRIP_R + 0.002
    comp = min(1.0, math.radians(290) * Rr / (tipx - KNUCK))
    u = Vector((s, 0, 0))   # along the fingers
    w = Vector((0, 0, 1))   # the back of the hand
    K = Vector((s * KNUCK, yc, palm_z))
    O = K - w * Rr
    for i, is_thumb in zip(hand, thumb):
        p = me.vertices[i].co
        d = (p.x - K.x) * s
        if is_thumb or d <= 0:
            continue
        hgt = (p - K).dot(w)
        phi = d * comp / Rr
        rho = Rr + max(0.0, hgt) * 0.72 + min(0.0, hgt)
        lateral = Vector((0, (p.y - yc) * (1.0 - PRESS * min(1.0, phi / math.pi)), 0))
        me.vertices[i].co = O + u * (rho * math.sin(phi)) + w * (rho * math.cos(phi)) + lateral
    # The thumb: pushed out of the grip, away from its axis, until it lies on its side.
    th = [i for i, t in zip(hand, thumb) if t]
    tc = np.array([me.vertices[i].co[:] for i in th])
    rel = tc[:, [0, 2]] - np.array([O.x, O.z])
    out = rel.mean(0) / np.linalg.norm(rel.mean(0))
    need = max(0.0, float((Rr + 0.004 - rel @ out).max()))
    for i in th:
        me.vertices[i].co += Vector((out[0], 0, out[1])) * need
    front = float(min(me.vertices[i].co.y for i in th))
    FIST[side] = {"axis": O.copy(), "radius": Rr, "thumb_front": front}
    print("RIG_FIST", side, "fingers x%.2f, thumb moved %.1f cm, front y %.3f, grip axis" % (comp, 100 * need, front),
          [round(c, 3) for c in O])


make_fist("Right", -1)
make_fist("Left", 1)
me.update()
V = np.array([v.co[:] for v in me.vertices])

# 4. Tail ---------------------------------------------------------------------------------
TV = np.array([v.co[:] for v in tail.data.vertices])
tail.data.transform(Matrix.Rotation(math.pi, 4, "Z"))      # the stump towards -Y: his back
tail.location = (0, 0, 0)
TV = np.array([v.co[:] for v in tail.data.vertices])
stump = TV[TV[:, 1] < TV[:, 1].min() + 0.03].mean(0)
ok, back_pt, _, _ = body.ray_cast(Vector((0, 1.0, TAIL_Z)), Vector((0, -1, 0)))
assert ok, "no back surface at the tail's root"
root = back_pt + Vector((0, -TAIL_SINK, 0))
probe = TV[np.linalg.norm(TV - stump, axis=1) > 0.15][::3]
dg = bpy.context.evaluated_depsgraph_get()


def tail_xform(tilt):
    R = Matrix.Rotation(math.radians(tilt), 3, "X")         # + lifts the far end
    return lambda p: root + R @ (Vector(p) - Vector(stump)), R


def inside(p):
    ok_, loc, nrm, _ = body.closest_point_on_mesh(p)
    return ok_ and (p - loc).dot(nrm) < -0.015


best = min(((sum(inside(tail_xform(t)[0](p)) for p in probe), abs(t), t) for t in TAIL_TILTS))
tilt = best[2]
f, RT = tail_xform(tilt)
print("RIG_TAIL tilt", tilt, "probe points inside him", best[0], "of", len(probe))
tail.data.transform(Matrix.Translation(-Vector(stump)))
tail.data.transform(RT.to_4x4())
tail.data.transform(Matrix.Translation(root))
tail.data.update()
# Centre line: the tail sliced by distance along its surface from the stump.
TW = np.array([v.co[:] for v in tail.data.vertices])
tlab, tparts = islands(tail.data)
main = max(tparts, key=len)
edges = {}
for e in tail.data.edges:
    a, b = e.vertices
    d = float(np.linalg.norm(TW[a] - TW[b]))
    edges.setdefault(a, []).append((b, d))
    edges.setdefault(b, []).append((a, d))
dist = np.full(len(TW), np.inf)
seeds = [i for i in main if np.linalg.norm(TW[i] - np.array(root)) < 0.05]
heap = [(0.0, i) for i in seeds]
for i in seeds:
    dist[i] = 0.0
while heap:
    d, i = heapq.heappop(heap)
    if d > dist[i]:
        continue
    for j, w_ in edges.get(i, []):
        if d + w_ < dist[j]:
            dist[j] = d + w_
            heapq.heappush(heap, (d + w_, j))
reach = np.isfinite(dist)
bins = np.linspace(0, dist[reach].max(), 24)
cl = [Vector(root)]
for a, b in zip(bins, bins[1:]):
    m = reach & (dist >= a) & (dist < b)
    if m.sum() > 3:
        cl.append(Vector(TW[m].mean(0)))
cl.append(Vector(TW[reach][np.argsort(dist[reach])[-6:]].mean(0)))
cl = [cl[0]] + [sum(cl[max(0, i - 1):i + 2], Vector()) / len(cl[max(0, i - 1):i + 2]) for i in range(1, len(cl) - 1)] + [cl[-1]]
seg = np.cumsum([0] + [(cl[i + 1] - cl[i]).length for i in range(len(cl) - 1)])
TAIL_PTS = []
for t in np.linspace(0, seg[-1], TAIL_N + 1):
    i = min(int(np.searchsorted(seg, t, side="right")) - 1, len(cl) - 2)
    k = (t - seg[i]) / max(1e-9, seg[i + 1] - seg[i])
    TAIL_PTS.append(cl[i].lerp(cl[i + 1], k))
print("RIG_TAIL root", [round(c, 3) for c in root], "centre line %.3f m" % seg[-1], "tip", [round(c, 3) for c in TAIL_PTS[-1]])

# 5. Armature -----------------------------------------------------------------------------
arm_data = bpy.data.armatures.new("CollieRig")
rig = bpy.data.objects.new("CollieRig", arm_data)
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
        b.use_connect = not name.endswith(("Shoulder", "UpLeg")) and (b.head - b.parent.tail).length < 1e-4
for b in EB:
    if "Arm" in b.name or "Hand" in b.name or "Shoulder" in b.name:
        b.align_roll(Vector((0, 0, -1)))
    else:
        b.align_roll(Vector((0, -1, 0)))
EXTRA = []
# Tail chain: bone Y along the tail, Z in his middle plane square to it (a sideways wag is
# a turn about Z, a curl about X).
prev = EB["mixamorig:Hips"]
for i in range(TAIL_N):
    b = EB.new(f"Tail_{i + 1}")
    b.head, b.tail = TAIL_PTS[i], TAIL_PTS[i + 1]
    b.parent = prev
    b.use_connect = i > 0
    b.align_roll(Vector((1, 0, 0)).cross(b.tail - b.head))
    EXTRA.append(b.name)
    prev = b
# Hanging armour: the panels turn about the line through his hip joints, the tassets about
# their own hip joint (with the thigh, as the footman's skirt bones).
hip_mid = (J["LeftUpLeg"] + J["RightUpLeg"]) / 2
for n in ("TabardF", "TabardB"):
    b = EB.new(n)
    b.head, b.tail = hip_mid, hip_mid + Vector((0, 0, -0.3))
    b.align_roll(Vector((0, -1, 0)))
    b.parent = EB["mixamorig:Hips"]
    EXTRA.append(n)
for side, s in (("Left", "L"), ("Right", "R")):
    thigh = EB[f"mixamorig:{side}UpLeg"]
    b = EB.new(f"Tasset.{s}")
    b.head = thigh.head
    b.tail = thigh.head + (thigh.tail - thigh.head).normalized() * 0.14
    b.align_roll(thigh.z_axis)
    b.parent = EB["mixamorig:Hips"]
    EXTRA.append(b.name)
bpy.ops.object.mode_set(mode="OBJECT")
for b in arm_data.bones:
    b.use_deform = not b.name.endswith(("HeadTop_End", "Toe_End")) and b.name not in EXTRA

# 6. Skin ---------------------------------------------------------------------------------
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
segs = [(b.name, Vector(b.head_local), Vector(b.tail_local)) for b in arm_data.bones if b.use_deform]


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(1e-9, ab.length_squared)))
    return (p - (a + ab * t)).length


unweighted = [v.index for v in me.vertices if not any(g.weight > 1e-3 for g in v.groups)]
for vi in unweighted:
    p = me.vertices[vi].co
    name = min(segs, key=lambda s_: seg_dist(p, s_[1], s_[2]))[0]
    (body.vertex_groups.get(name) or body.vertex_groups.new(name=name)).add([vi], 1.0, "REPLACE")
print("RIG_SKIN groups", len(body.vertex_groups), "bone heat missed", len(unweighted), "vertices (now on the nearest bone)")
for b in EXTRA:
    arm_data.bones[b].use_deform = True


def set_weights(vi, ws):
    """Replace a vertex's weights (a dict, normalised here)."""
    for g in list(me.vertices[vi].groups):
        body.vertex_groups[g.group].remove([vi])
    tot = sum(ws.values())
    for n, w_ in ws.items():
        if w_ > 1e-4:
            (body.vertex_groups.get(n) or body.vertex_groups.new(name=n)).add([vi], w_ / tot, "REPLACE")


def weights(vi):
    return {body.vertex_groups[g.group].name: g.weight for g in me.vertices[vi].groups if g.weight > 1e-4}


# The pauldrons' raised collars stand by his head: they keep to the shoulder and arm.
collars = part_where(lambda p: np.abs(p[:, 0].mean()) > 0.12 and p[:, 2].min() > 1.3 and p[:, 2].max() > 1.6)
for ids in collars:
    for vi in ids:
        ws = {n: w_ for n, w_ in weights(vi).items() if not n.endswith(("Neck", "Head"))}
        if ws:
            set_weights(vi, ws)
print("RIG_COLLARS", len(collars), "parts kept off the neck and head")


def smooth(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def hang(ids, bone, top, hem):
    for vi in ids:
        t = smooth((top - me.vertices[vi].co.z) / (top - hem))
        set_weights(vi, {"mixamorig:Hips": 1.0 - t, bone: t})


panel_f = part_where(lambda p: abs(p[:, 0].mean()) < 0.02 and p[:, 1].max() < -0.1 and p[:, 2].min() < 0.7)
panel_b = part_where(lambda p: abs(p[:, 0].mean()) < 0.02 and p[:, 1].min() > 0.1 and p[:, 2].min() < 0.7)
assert len(panel_f) == 1 and len(panel_b) == 1, "expected one front and one back panel"
hang(panel_f[0], "TabardF", *HANG["TabardF"])
hang(panel_b[0], "TabardB", *HANG["TabardB"])
for s, sgn in (("L", 1), ("R", -1)):
    tas = part_where(lambda p: p[:, 0].mean() * sgn > 0.12 and 0.7 < p[:, 2].min() < 0.8 and 1.0 < p[:, 2].max() < 1.2 and len(p) > 50)
    assert len(tas) == 1, f"expected one tasset on side {s}, found {len(tas)}"
    hang(tas[0], f"Tasset.{s}", *HANG["Tasset"])
print("RIG_HANG front panel %d, back panel %d vertices, tassets" % (len(panel_f[0]), len(panel_b[0])))

# Tail: by distance to its chain, the two nearest bones (as the succubus's).
names = [f"Tail_{i + 1}" for i in range(TAIL_N)]
tb = [(n, Vector(arm_data.bones[n].head_local), Vector(arm_data.bones[n].tail_local)) for n in names]
for n in names:
    tail.vertex_groups.new(name=n)
for v in tail.data.vertices:
    ds = sorted((seg_dist(v.co, h, t_), n) for n, h, t_ in tb)[:2]
    ws = [math.exp(-(d / 0.07) ** 2) for d, _ in ds]
    tot = sum(ws)
    if tot < 1e-6 or ws[0] / tot > 0.98:
        tail.vertex_groups[ds[0][1]].add([v.index], 1.0, "REPLACE")
        continue
    for (d, n), w_ in zip(ds, ws):
        tail.vertex_groups[n].add([v.index], w_ / tot, "REPLACE")
tail.modifiers.new("Armature", "ARMATURE").object = rig
tail.parent = rig

# 7. Props in the footman's hand frames ---------------------------------------------------
def hand_frame(side):
    """Mixamo's rest frame of the hand (world), at this rig's hand joint."""
    if side == "Right":
        x, y, z = Vector((0, -1, 0)), Vector((-1, 0, 0)), Vector((0, 0, -1))
    else:
        x, y, z = Vector((0, 1, 0)), Vector((1, 0, 0)), Vector((0, 0, -1))
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = J[side + "Hand"]
    return m


# Sword: the grip along the fist's axis, the guard's lower face just in front of the thumb.
sword.data.transform(Matrix.Translation((0, 0, -guard_lo)))
hr = hand_frame("Right")
O = FIST["Right"]["axis"]
g = hr.inverted() @ Vector((O.x, FIST["Right"]["thumb_front"] - 0.005, O.z))
sword.matrix_world = hr @ Matrix(((0, 0, 1, g.x), (1, 0, 0, g.y), (0, 1, 0, g.z), (0, 0, 0, 1)))
# Shield: as the footman's, strapped to the back of the forearm and hung low, then raised
# along its face until it clears the forearm, the bracer and the fist.
fit_prop(shield, SHIELD_L)
shield.data.transform(Matrix.Translation((0, 0, -0.5 * SHIELD_L)))
hl = hand_frame("Left")
fore = (J["LeftHand"] - J["LeftForeArm"]).length
up = (hl.to_3x3() @ Vector((-1, 0, 0))).normalized()
out = (hl.to_3x3() @ Vector((0, 0, -1))).normalized()
side_v = (-out).cross(up).normalized()
Ms = Matrix((side_v, -out, up)).transposed().to_4x4()
Ms.translation = J["LeftHand"] + (hl.to_3x3() @ Vector((0.13, -fore * 0.3, -0.05)))
shield.matrix_world = Ms
bpy.context.view_layer.update()
sh_world = [shield.matrix_world @ v.co for v in shield.data.vertices]
bvh = BVHTree.FromPolygons(sh_world, [p.vertices[:] for p in shield.data.polygons])
arm_pts = [Vector(p) for p in V if p[0] > ARM_X["ForeArm"] + 0.02 and p[2] > 1.25]   # the forearm and fist
lift = 0.0
for p in arm_pts:
    hit = bvh.ray_cast(p - out * 1.0, out)              # from under the arm, along the face
    if hit[0] is not None:
        lift = max(lift, (p - hit[0]).dot(out) + SHIELD_GAP)
Ms.translation += out * lift
shield.matrix_world = Ms
print("RIG_SHIELD raised %.1f cm off the forearm" % (100 * lift))
for obj, bone in ((sword, "RightHand"), (shield, "LeftHand")):
    mw = obj.matrix_world.copy()
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = "mixamorig:" + bone
    obj.matrix_world = mw


# 8. The shield's arm strap ---------------------------------------------------------------
def hull2(pts):
    """Convex hull of 2D points, counter-clockwise, as indices into pts."""
    order = sorted(range(len(pts)), key=lambda i: (pts[i][0], pts[i][1]))

    def cross(o, a, b):
        return (pts[a][0] - pts[o][0]) * (pts[b][1] - pts[o][1]) - (pts[a][1] - pts[o][1]) * (pts[b][0] - pts[o][0])
    lo, hi = [], []
    for i in order:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], i) <= 0:
            lo.pop()
        lo.append(i)
    for i in reversed(order):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], i) <= 0:
            hi.pop()
        hi.append(i)
    return lo[:-1] + hi[:-1]


def flat_material(name, rgb, metallic, roughness):
    m = bpy.data.materials.new(name)
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    m.diffuse_color = (*rgb, 1)          # the workbench renders (pose viewer) show this
    return m


def band(bm, path, x0, width, thick):
    """A flat band, `width` along x and `thick`, along `path` ((y, z) points in the shield's
    frame at x = x0) in even steps of about 4 mm, keeping its corners. Its middle line and length."""
    seg = np.r_[0, np.cumsum(np.hypot(*np.diff(path, axis=0).T))]
    s_ = np.unique(np.r_[np.linspace(0, seg[-1], max(8, int(seg[-1] / 0.004))), seg])
    Q = np.c_[np.interp(s_, seg, path[:, 0]), np.interp(s_, seg, path[:, 1])]
    T = np.gradient(Q, axis=0)
    T /= np.linalg.norm(T, axis=1)[:, None]
    rows = []
    for (y, z), (ny, nz) in zip(Q, np.c_[T[:, 1], -T[:, 0]]):
        rows.append([bm.verts.new(S @ Vector((x0 + sx * width / 2, y + sn * ny * thick / 2, z + sn * nz * thick / 2)))
                     for sx, sn in ((-1, 1), (1, 1), (1, -1), (-1, -1))])
    for r0, r1 in zip(rows, rows[1:]):
        for k in range(4):
            bm.faces.new((r0[k], r0[(k + 1) % 4], r1[(k + 1) % 4], r1[k]))
    bm.faces.new(rows[0][::-1])
    bm.faces.new(rows[-1])
    return Q, seg[-1]


def rivet(bm, p, mat):
    """A domed rivet head centred at p (the shield's frame), material index `mat`."""
    ret = bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=6, radius=RIVET_R)
    bmesh.ops.transform(bm, verts=ret["verts"], matrix=S @ Matrix.Translation(p) @ Matrix.Diagonal((1, 0.55, 1, 1)))
    for f in {f for v in ret["verts"] for f in v.link_faces}:
        f.material_index = mat


def hand_prop(name, bm, mats):
    """An object of bm (world, at rest) with `mats`, riding on the left hand bone as the shield."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = bpy.data.objects.new(name, bpy.data.meshes.new(name))
    bm.to_mesh(obj.data)
    bm.free()
    for m in mats:
        obj.data.materials.append(m)
    sc.collection.objects.link(obj)
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = "mixamorig:LeftHand"
    obj.matrix_world = Matrix.Identity(4)
    return obj


leather = flat_material("ShieldStrap_leather", (0.07, 0.025, 0.018), 0.0, 0.8)   # as his belts
brass = flat_material("ShieldStrap_rivet", (0.40, 0.21, 0.05), 0.9, 0.4)         # as the shield's rivets
# All in the shield's frame (x across it, y off its back towards him, z up it). The clips turn
# the wrist by WRIST, so the forearm and the skin that follows it or the hand alone stand
# turned back by it, seen from the shield.
S = shield.matrix_world
Si = S.inverted()
hand_rest = rig.matrix_world @ rig.data.bones["mixamorig:LeftHand"].matrix_local
to_clip = Si @ hand_rest @ WRIST.to_matrix().to_4x4().inverted() @ hand_rest.inverted()
el, wr = to_clip @ J["LeftForeArm"], to_clip @ J["LeftHand"]
x0 = el.x + STRAP_AT * (wr.x - el.x)
c = el.lerp(wr, STRAP_AT)
m4 = to_clip @ body.matrix_world
co = np.array([v.co[:] for v in me.vertices]) @ np.array(m4.to_3x3()).T + np.array(m4.translation)
gname = {g.index: g.name for g in body.vertex_groups}
rigid = np.array([sum(g.weight for g in v.groups if gname[g.group] in ("mixamorig:LeftForeArm", "mixamorig:LeftHand"))
                  for v in me.vertices]) > 0.999
# The forearm's section under the strap: its vertices there, and where its edges cross the
# strap's sides and middle (a long low-poly face can span the strap with no vertex in it).
half = STRAP_W / 2 + 0.003
ed = np.array([e.vertices[:] for e in me.edges])
ed = ed[rigid[ed[:, 0]] & rigid[ed[:, 1]]]
a, b = co[ed[:, 0]], co[ed[:, 1]]
dx = np.where(np.abs(b[:, 0] - a[:, 0]) < 1e-9, 1e-9, b[:, 0] - a[:, 0])
sec = [co[rigid & (np.abs(co[:, 0] - x0) <= half)]]
for xp in (x0 - half, x0, x0 + half):
    t = (xp - a[:, 0]) / dx
    ok = (t >= 0) & (t <= 1)
    sec.append(a[ok] + t[ok, None] * (b[ok] - a[ok]))
sec = np.vstack(sec)[:, 1:]
sec = sec[np.hypot(sec[:, 0] - c.y, sec[:, 1] - c.z) < 0.15]
# The strap's middle line: STRAP_GAP and half its thickness round that section, past it by
# STRAP_LEG at the top and the bottom, and down to the shield's back there.
r = STRAP_GAP + STRAP_TH / 2
ring = [(y + r * math.cos(t), z + r * math.sin(t)) for y, z in sec for t in np.linspace(0, 2 * math.pi, 16, endpoint=False)]
sh_bvh = BVHTree.FromPolygons([v.co for v in shield.data.vertices], [p.vertices[:] for p in shield.data.polygons])
zs = [q[1] for q in ring]
ends = []
for z in (max(zs) + STRAP_LEG, min(zs) - STRAP_LEG):
    hit = sh_bvh.ray_cast(Vector((x0, c.y, z)), Vector((0, -1, 0)))
    assert hit[0] is not None, "no shield under the strap's end"
    ends.append((hit[0].y + STRAP_TH / 2 + 0.0005, z))
pts = ring + ends
hl2 = hull2(pts)
i, j = hl2.index(len(pts) - 2), hl2.index(len(pts) - 1)
# From the top end to the bottom one the long way round: over the forearm, away from the shield.
way_a = [hl2[(i + k) % len(hl2)] for k in range((j - i) % len(hl2) + 1)]
way_b = [hl2[(i - k) % len(hl2)] for k in range((i - j) % len(hl2) + 1)]
arc = max(way_a, way_b, key=lambda w: max(pts[k][0] for k in w))
path = np.array([(ends[0][0], ends[0][1] + STRAP_TAB)] + [pts[k] for k in arc] + [(ends[1][0], ends[1][1] - STRAP_TAB)])
bm = bmesh.new()
Q, length = band(bm, path, x0, STRAP_W, STRAP_TH)
# Two rivets through each end, domed on the strap.
for (y, z), sgn in ((Q[0], 1), (Q[-1], -1)):
    for sx in (-0.25, 0.25):
        rivet(bm, (x0 + sx * STRAP_W, y + STRAP_TH / 2, z - sgn * STRAP_TAB / 2), 1)
hand_prop("ShieldStrap", bm, (leather, brass))
print("RIG_STRAP %.0f %% along the forearm: %d section points, %.1f cm of leather, riveted %.1f cm apart" % (
    100 * STRAP_AT, len(sec), 100 * length, 100 * (ends[0][1] - ends[1][1])))


# 9. The shield's grip --------------------------------------------------------------------
def box(lo, hi):
    """A box's BVH, corners lo and hi."""
    vs = [Vector((x, y, z)) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
    return BVHTree.FromPolygons(vs, [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)])


def fillet(pts, r):
    """A polyline with its corners rounded, from r before each to r after it."""
    out = [np.array(pts[0])]
    for p0, p1, p2 in zip(pts, pts[1:], pts[2:]):
        p0, p1, p2 = (np.array(p) for p in (p0, p1, p2))
        a = p1 + (p0 - p1) / np.linalg.norm(p0 - p1) * r
        b = p1 + (p2 - p1) / np.linalg.norm(p2 - p1) * r
        out += [(1 - t) ** 2 * a + 2 * (1 - t) * t * p1 + t * t * b for t in np.linspace(0, 1, 7)]
    return np.array(out + [np.array(pts[-1])])


# The fist rides on the hand bone as the shield does: it stands to the shield as at rest, its
# axis along the shield's z. The grip's legs pass his hand (the faces the hand bone moves)
# above and below, from the shield's back to that axis.
ax = Si @ FIST["Left"]["axis"]
assert abs((Si.to_3x3() @ Vector((0, 1, 0))).normalized().z) > 0.999, "the fist's axis is not along the shield's z"
wh = np.array([sum(g.weight for g in v.groups if gname[g.group] == "mixamorig:LeftHand") for v in me.vertices])
mh = Si @ body.matrix_world
hand_bvh = BVHTree.FromPolygons([mh @ v.co for v in me.vertices],
                                [p.vertices[:] for p in me.polygons if wh[list(p.vertices)].max() > 0.01])


def back_y(z):
    hit = sh_bvh.ray_cast(Vector((ax.x, ax.y, z)), Vector((0, -1, 0)))
    assert hit[0] is not None, "no shield under the grip"
    return hit[0].y


back0 = back_y(ax.z)


def leg_clear(z):
    return not box((ax.x - GRIP_W / 2 - GRIP_GAP, back0 + GRIP_TH, z - GRIP_TH / 2 - GRIP_GAP),
                   (ax.x + GRIP_W / 2 + GRIP_GAP, ax.y + GRIP_TH / 2 + GRIP_GAP, z + GRIP_TH / 2 + GRIP_GAP)).overlap(hand_bvh)


steps = np.arange(0.0, 0.25, 0.002)
top = ax.z + max(d for d in steps if not leg_clear(ax.z + d)) + 0.002
bot = ax.z - max(d for d in steps if not leg_clear(ax.z - d)) - 0.002
feet = [(back_y(z) + GRIP_TH / 2 + 0.0005, z) for z in (top, bot)]
for (_, z), sgn in zip(feet, (1, -1)):
    back_y(z + sgn * GRIP_FOOT)
bm = bmesh.new()
_, length = band(bm, fillet([(feet[0][0], top + GRIP_FOOT), feet[0], (ax.y, top), (ax.y, bot), feet[1],
                             (feet[1][0], bot - GRIP_FOOT)], GRIP_BEND), ax.x, GRIP_W, GRIP_TH)
# The leather round the bar's straight middle, as thick as the sword's grip (the fist fits it).
z0, z1 = bot + GRIP_BEND + 0.002, top - GRIP_BEND - 0.002
ret = bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=GRIP_R, radius2=GRIP_R, depth=z1 - z0,
                            matrix=S @ Matrix.Translation((ax.x, ax.y, (z0 + z1) / 2)))
for f in {f for v in ret["verts"] for f in v.link_faces}:
    f.material_index = 1
    f.smooth = len(f.verts) == 4
# Two rivets along each foot.
for (y, z), sgn in zip(feet, (1, -1)):
    for k in (0.27, 0.73):
        rivet(bm, (ax.x, y + GRIP_TH / 2, z + sgn * (GRIP_BEND + k * (GRIP_FOOT - GRIP_BEND))), 2)
hand_prop("ShieldGrip", bm, (flat_material("ShieldGrip_iron", (0.09, 0.09, 0.095), 0.8, 0.55), leather, brass))
print("RIG_GRIP legs %.1f cm apart, %.1f cm long (the fist's axis off the shield's back), %.1f cm of iron, %.1f cm of leather" % (
    100 * (top - bot), 100 * (ax.y - feet[0][0]), 100 * length, 100 * (z1 - z0)))

rig["landmarks"] = json.dumps({k: list(v) for k, v in J.items()})
rig["tail_points"] = json.dumps([list(p) for p in TAIL_PTS])
rig["grip_r"] = GRIP_R
rig["strap_wrist"] = list(WRIST)
# The scene is public: no file browser holding the user's Documents folder.
bpy.data.batch_remove([w for w in bpy.data.workspaces
                       if any(sp.type == "FILE_BROWSER" for s in w.screens for a in s.areas for sp in a.spaces)])
out_blend.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend), compress=True)
print("RIG_SAVED", out_blend)
