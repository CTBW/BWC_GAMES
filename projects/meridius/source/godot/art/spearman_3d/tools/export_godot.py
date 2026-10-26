"""Export the rigged spearman for the Godot 3D sandbox (background Blender).

  blender -b spearman_rig.blend --python export_godot.py -- <out.glb> [texture_px]

Set BLENDER_USER_RESOURCES to an empty folder (blender_env.sh). Works on the open copy
only (the .blend is not saved):
  * the spear moves on bones of its own: its object action per clip (<clip>__spear, from
    spear_motion.py) is baked onto "SpearGrip", a child of the right hand at the point of the
    shaft nearest the fist's centre, turned as the spear, and "SpearBone", its child, which
    only slides the shaft along its length (the butt at its origin); the spear mesh is skinned
    to SpearBone. A cross-fade between holds (the guard's fist at the butt, the carry's half a
    metre up the shaft) so turns the spear about the fist and slides it through, where one
    bone at the butt swung the shaft out of the fist;
  * the cape: glTF cannot carry the cloth's PC2 caches (cape_cache/), so they are fitted
    with cape bones. CAPE_GRID bones (columns round his back x rows down the cape, children
    of Spine2) carry the cloth with smooth bilinear weights; the pinned rows under the hood
    keep their spine weights. Per clip and frame the bone transforms are solved (rigid,
    least squares, block coordinate descent as in skinning decomposition) so that the
    skinned cape matches the baked cloth; the error is printed and written to the sidecar.
    The bind shape is the cloth hanging at idle_rest's first frame, brought back to the rest
    pose through the spine. Solidify is applied (1 cm, inwards, as in the renders);
  * the turn's rotation moves from the hips to the root, as the footman's: the body is held
    at idle's heading and `root_yaw` (degrees per frame, from the first frame) turns the
    figure in the sandbox;
  * the body's weights go out as authored: up to 6 influences per vertex (all exported;
    Godot skins with 8, while the top 4 would move vertices up to 3 cm), weights a hair
    over 1 clamped (the exporter calls such a mesh invalid);
  * textures scaled down to `texture_px` (default 1024, JPEG; the tiny steel strip stays PNG);
  * a sidecar <out>.json as the footman's (prototypes/footman_anim/art3d/footman.json): per
    clip its length, loop, frames, ground speed in Godot axes (x, z, -y of Blender; the
    model faces +Z), turn, hips drift and events (attack contact, footfalls, death
    settled), plus `roles` mapping generic orders to clips.
"""
import json
import math
import os
import struct
import sys
import time
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = Path(argv[0])
TEX = int(argv[1]) if len(argv) > 1 else 1024
FPS = 30.0
HERE = Path(bpy.data.filepath).parent
CACHE = Path(os.environ.get("CAPE_CACHE", str(HERE / "cape_cache")))
COLS, ROWS = (int(v) for v in os.environ.get("CAPE_GRID", "6x4").split("x"))
BIND_CLIP = "idle_rest"            # the cloth at this clip's first frame is the cape's bind shape
PIN_BOTTOM = 1.31                  # cape_cloth.py: free below, pinned (to the spine) above PIN_TOP
SPINE = ["Hips", "Spine", "Spine1", "Spine2", "Neck"]
LOOPS = {"idle", "idle_rest", "walk", "step_lane"}
STILL = {"idle", "idle_rest", "turn_90", "hit", "attack"}   # stand in place: no ground speed
T0 = time.time()

sc = bpy.context.scene
sc.render.fps = int(FPS)
rig = bpy.data.objects["SpearmanRig"]
body = bpy.data.objects["Spearman"]
cape = bpy.data.objects["Cape"]
spear = bpy.data.objects["Spear"]
assert rig.matrix_world == Matrix.Identity(4) and cape.matrix_world == Matrix.Identity(4)
PB = rig.pose.bones
CLIPS = [a.name for a in bpy.data.actions if "frames" in a and not a.name.endswith("__spear")]
ORDER = ["idle", "idle_rest", "walk", "step_lane", "turn_90", "attack", "hit", "death", "death_2", "death_3"]
CLIPS = [c for c in ORDER if c in CLIPS] + [c for c in CLIPS if c not in ORDER]
print("EXPORT clips", CLIPS)


def b(n):
    return PB["mixamorig:" + n]


def to_godot(v):
    # glTF / Godot: x, z, -y of Blender.
    return [round(float(v[0]), 4), round(float(v[2]), 4), round(float(-v[1]), 4)]


def frames_of(act):
    return list(range(1, int(act["frames"]) + 1))


def hips_yaw():
    # Facing of the hips about Z, from the hip line (his right is -X at rest, he faces -Y).
    r = b("RightUpLeg").head - b("LeftUpLeg").head
    fwd = Vector((0, 0, 1)).cross(r)
    return math.degrees(math.atan2(fwd.x, -fwd.y))


def set_clip(name):
    rig.animation_data.action = bpy.data.actions[name]
    sp = bpy.data.actions.get(name + "__spear")
    if spear.animation_data is not None and sp is not None:
        spear.animation_data.action = sp


# No clip keys scale, nor location below the hips (spear_motion.py clear_unkeyed).
for pb in PB:
    pb.scale = (1, 1, 1)
    if pb.name != "mixamorig:Hips":
        pb.location = (0, 0, 0)
# The cloth's helpers stay out of the export.
for o in list(bpy.data.objects):
    if o.name.startswith("CapeCollider_") or o.name == "CapeGround":
        bpy.data.objects.remove(o, do_unlink=True)

# The spear's tip: its butt is at the origin and the tip along +Z (build_spear.py).
sv = np.array([v.co[:] for v in spear.data.vertices])
TIP_IDX = int(np.argmax(sv[:, 2]))
TIP_LOCAL = Vector(sv[TIP_IDX])
print("SPEAR tip local", tuple(round(x, 3) for x in TIP_LOCAL))
# The right fist's centre in the hand's frame (rig_spearman.py records it in the rest pose).
FIST_R = rig.data.bones["mixamorig:RightHand"].matrix_local.inverted() @ Vector(rig["fist_right"])


def grip_along(spear_m, fist):
    """Metres from the butt along the shaft (+Z) to the point nearest the fist's centre."""
    z = spear_m.to_3x3().normalized() @ Vector((0, 0, 1))
    return min(max((fist - spear_m.translation).dot(z), 0.0), TIP_LOCAL.z)

# 1. Sample every clip: the spine's skin matrices (cape fit), the spear's matrix, and what
# the sidecar measures.
cape_groups = {g.name: g.index for g in cape.vertex_groups}
NV = len(cape.data.vertices)
P = np.array([v.co[:] for v in cape.data.vertices])
A0 = np.zeros((NV, len(SPINE)))
PW = np.zeros(NV)
for v in cape.data.vertices:
    for g in v.groups:
        n = cape.vertex_groups[g.group].name
        if n == "pin":
            PW[v.index] = g.weight
        elif n.startswith("mixamorig:") and n[10:] in SPINE:
            A0[v.index, SPINE.index(n[10:])] = g.weight
A0 /= np.maximum(A0.sum(1, keepdims=True), 1e-9)
REST = {n: np.array(b(n).bone.matrix_local) for n in SPINE}
samp = {}
head_mesh_top = None
for name in CLIPS:
    act = bpy.data.actions[name]
    set_clip(name)
    fr = frames_of(act)
    d = {"S": [], "spear": [], "grip": [], "hips": [], "yaw": [], "tip": [], "ank": {"Left": [], "Right": []},
         "foot": {"Left": [], "Right": []}, "lead": [], "head": []}
    for f in fr:
        sc.frame_set(f)
        d["S"].append([np.array(b(n).matrix) @ np.linalg.inv(REST[n]) for n in SPINE])
        d["spear"].append(spear.matrix_world.copy())
        d["grip"].append(grip_along(spear.matrix_world, b("RightHand").matrix @ FIST_R))
        d["hips"].append(rig.matrix_world @ b("Hips").head)
        d["yaw"].append(hips_yaw())
        d["tip"].append(spear.matrix_world @ TIP_LOCAL)
        for s in ("Left", "Right"):
            p = rig.matrix_world @ b(s + "Foot").head
            d["ank"][s].append(p.z)
            d["foot"][s].append(p.copy())
        d["lead"].append(max(-(rig.matrix_world @ b(n).head).y for n in ("Hips", "LeftToe_End", "RightToe_End")))
        d["head"].append((rig.matrix_world @ b("HeadTop_End").head).z)
    d["S"] = np.array(d["S"])
    samp[name] = d
    if name == "idle":
        sc.frame_set(1)
        ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
        head_mesh_top = max((ev.matrix_world @ v.co).z for v in ev.data.vertices)
print("SAMPLED %d clips in %.1fs" % (len(CLIPS), time.time() - T0))


# 2. The cape: bind shape, weights and the per-frame fit against the baked cloth.
def read_pc2(path):
    with open(path, "rb") as fh:
        h = struct.unpack("<12siiffi", fh.read(32))
    return np.fromfile(path, dtype="<f4", offset=32).reshape(h[5], h[2], 3).astype(np.float64)


def lbs(S, W, X):
    """Linear blend skinning: S (J,4,4) skin matrices, W (V,J), X (V,3) -> (V,3)."""
    M = np.einsum("vj,jab->vab", W, S[:, :3, :])
    return np.einsum("vab,vb->va", M[:, :, :3], X) + M[:, :, 3]


Q = {}
for name in CLIPS:
    Q[name] = read_pc2(CACHE / f"{name}.pc2")
    assert Q[name].shape == (len(samp[name]["S"]), NV, 3), (name, Q[name].shape)

# Bind: the cloth at BIND_CLIP's first frame, each vertex brought back to the rest pose
# through its spine weights; the pinned rows are their own rest positions.
S0 = samp[BIND_CLIP]["S"][0]
M0 = np.einsum("vj,jab->vab", A0, S0)
q0 = Q[BIND_CLIP][0]
B = np.einsum("vab,vb->va", np.linalg.inv(M0)[:, :3, :3], q0 - M0[:, :3, 3])
pinned = PW >= 0.999
pin_err = np.linalg.norm(lbs(S0, A0[pinned], P[pinned]) - q0[pinned], axis=1)
print("CAPE pinned rows vs cache at the bind frame: max %.2f mm" % (1000 * pin_err.max()))
B[pinned] = P[pinned]

# Weights: bilinear hat functions over (angle round his back, height) of the rest cape.
U = np.degrees(np.arctan2(P[:, 0], P[:, 1] + 0.03))
u_k = np.linspace(np.percentile(U, 1), np.percentile(U, 99), COLS)
z_k = np.linspace(P[:, 2].min() + 0.02, PIN_BOTTOM, ROWS)


def hats(x, knots):
    x = np.clip(x, knots[0], knots[-1])
    w = np.zeros((len(x), len(knots)))
    i = np.clip(np.searchsorted(knots, x) - 1, 0, len(knots) - 2)
    t = (x - knots[i]) / (knots[i + 1] - knots[i])
    w[np.arange(len(x)), i] = 1 - t
    w[np.arange(len(x)), i + 1] = t
    return w


WU, WZ = hats(U, u_k), hats(P[:, 2], z_k)
K = COLS * ROWS
CW = np.einsum("vr,vc->vrc", WZ, WU).reshape(NV, K) * (1 - PW)[:, None]   # cape bones
AW = A0 * PW[:, None]                                                     # spine bones
CAPE_BONES = [f"Cape_{r}_{c}" for r in range(ROWS) for c in range(COLS)]   # row 0 = the hem
SUP = [np.nonzero(CW[:, k] > 0.02)[0] for k in range(K)]
keep_k = [k for k in range(K) if len(SUP[k]) >= 4]
assert len(keep_k) == K, "a cape bone has no vertices: " + str([CAPE_BONES[k] for k in range(K) if k not in keep_k])
B_head = [(CW[:, k:k + 1] * B).sum(0) / CW[:, k].sum() for k in range(K)]


def kabsch(X, Y, w):
    sw = w.sum()
    mx = (w[:, None] * X).sum(0) / sw
    my = (w[:, None] * Y).sum(0) / sw
    H = ((X - mx) * w[:, None]).T @ (Y - my)
    U_, _, Vt = np.linalg.svd(H)
    d = np.sign(np.linalg.det(Vt.T @ U_.T))
    R = Vt.T @ np.diag([1.0, 1.0, d]) @ U_.T
    return R, my - R @ mx


def fit_clip(name):
    S, QQ = samp[name]["S"], Q[name]
    F = len(S)
    Rs = np.zeros((F, K, 3, 3)); ts = np.zeros((F, K, 3))
    err = np.zeros((F, NV)); base_err = np.zeros((F, NV))
    R = np.array([np.eye(3)] * K); t = np.zeros((K, 3))
    for f in range(F):
        q = QQ[f]
        base = lbs(S[f], AW, B)
        if f == 0:
            for k in range(K):
                R[k], t[k] = kabsch(B[SUP[k]], q[SUP[k]], CW[SUP[k], k])
        Y = np.einsum("kab,vb->kva", R, B) + t[:, None, :]
        tot = base + np.einsum("vk,kva->va", CW, Y)
        for _ in range(15 if f == 0 else 4):
            for k in range(K):
                s = SUP[k]
                ck = CW[s, k]
                r = q[s] - (tot[s] - ck[:, None] * Y[k, s])
                R[k], t[k] = kabsch(B[s], r / ck[:, None], ck * ck)
                Yn = B @ R[k].T + t[k]
                tot += CW[:, k:k + 1] * (Yn - Y[k])
                Y[k] = Yn
        Rs[f], ts[f] = R, t
        err[f] = np.linalg.norm(tot - q, axis=1)
        base_err[f] = np.linalg.norm(lbs(S[f], A0, B) - q, axis=1)
    return Rs, ts, err, base_err


FIT = {}
cape_fit = {}
for name in CLIPS:
    Rs, ts, err, base_err = fit_clip(name)
    FIT[name] = (Rs, ts)
    cape_fit[name] = {"mean_cm": round(100 * float(err.mean()), 2), "p95_cm": round(100 * float(np.percentile(err, 95)), 2),
                      "max_cm": round(100 * float(err.max()), 2),
                      "spine_only_mean_cm": round(100 * float(base_err.mean()), 2)}
    print("CAPE_FIT", name, json.dumps(cape_fit[name]))
print("CAPE fitted in %.1fs" % (time.time() - T0))

# 3. The armature: the spear's bone and the cape bones.
for o in bpy.data.objects:
    o.select_set(False)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
SPEAR_REST = samp["idle"]["spear"][0].copy()
GRIP_REST = samp["idle"]["grip"][0]


def grip_matrix(spear_m, t):
    return spear_m @ Matrix.Translation((0, 0, t))


bpy.ops.object.mode_set(mode="EDIT")
# Not "Spear": Godot makes node names unique and would rename a bone that shares the mesh's name.
SPEAR_BONE, GRIP_BONE = "SpearBone", "SpearGrip"
eg = rig.data.edit_bones.new(GRIP_BONE)
eg.head, eg.tail = (0, 0, 0), (0, 0.3, 0)
eg.matrix = grip_matrix(SPEAR_REST, GRIP_REST)
eg.parent = rig.data.edit_bones["mixamorig:RightHand"]
eg.use_deform = False
eb = rig.data.edit_bones.new(SPEAR_BONE)
eb.head, eb.tail = (0, 0, 0), (0, 0.3, 0)
eb.matrix = SPEAR_REST
eb.parent = eg
eb.use_deform = True
for k, n in enumerate(CAPE_BONES):
    eb = rig.data.edit_bones.new(n)
    h = Vector(B_head[k])
    eb.head, eb.tail, eb.roll = h, h + Vector((0, 0, -0.06)), 0.0
    eb.parent = rig.data.edit_bones["mixamorig:Spine2"]
    eb.use_deform = True
bpy.ops.object.mode_set(mode="OBJECT")
NEW = [GRIP_BONE, SPEAR_BONE] + CAPE_BONES
for n in NEW:
    PB[n].rotation_mode = "QUATERNION"
print("SPEAR grip at rest %.3f m up the shaft" % GRIP_REST)

# The spear mesh in its bind pose (idle's first frame), skinned to its bone.
spear.data.transform(SPEAR_REST)
spear.animation_data_clear()
spear.matrix_world = Matrix.Identity(4)
g = spear.vertex_groups.new(name=SPEAR_BONE)
g.add(list(range(len(spear.data.vertices))), 1.0, "REPLACE")
spear.modifiers.new("Armature", "ARMATURE").object = rig

# The cape mesh: bind shape, weights, Solidify applied, skinned.
for v, co in zip(cape.data.vertices, B):
    v.co = co
for gname in ("pin", "pinned"):
    if gname in cape.vertex_groups:
        cape.vertex_groups.remove(cape.vertex_groups[gname])
for j, n in enumerate(SPINE):
    grp = cape.vertex_groups["mixamorig:" + n]
    for i in range(NV):
        if AW[i, j] > 1e-4:
            grp.add([i], float(AW[i, j]), "REPLACE")
        else:
            grp.remove([i])
for k, n in enumerate(CAPE_BONES):
    grp = cape.vertex_groups.new(name=n)
    for i in SUP[k]:
        grp.add([int(i)], float(CW[i, k]), "REPLACE")
for m in list(cape.modifiers):
    if m.type in ("CLOTH", "ARMATURE", "MESH_CACHE"):
        cape.modifiers.remove(m)
sol = cape.modifiers.get("Solidify")
if sol is not None:
    sol.show_viewport = True
    with bpy.context.temp_override(object=cape, active_object=cape):
        bpy.ops.object.modifier_apply(modifier=sol.name)
assert np.allclose(np.array([v.co[:] for v in cape.data.vertices[:NV]]), B, atol=1e-5), "Solidify moved the outer layer"
cape.modifiers.new("Armature", "ARMATURE").object = rig
print("CAPE mesh", len(cape.data.vertices), "verts after Solidify")

# 4. Key the spear and cape bones in every clip.
for name in CLIPS:
    set_clip(name)
    Rs, ts = FIT[name]
    rest = {n: rig.data.bones[n].matrix_local.copy() for n in NEW}
    prev = {}
    for i, f in enumerate(frames_of(bpy.data.actions[name])):
        sc.frame_set(f)
        t = samp[name]["grip"][i]
        targets = {GRIP_BONE: grip_matrix(samp[name]["spear"][i], t)}
        # The shaft only slides on the grip: SpearBone's rest is GRIP_REST below it, along +Z.
        PB[SPEAR_BONE].rotation_quaternion = (1, 0, 0, 0)
        PB[SPEAR_BONE].location = (0, 0, GRIP_REST - t)
        PB[SPEAR_BONE].keyframe_insert("rotation_quaternion", frame=f)
        PB[SPEAR_BONE].keyframe_insert("location", frame=f)
        for k, n in enumerate(CAPE_BONES):
            T = Matrix.Identity(4)
            for r in range(3):
                for c in range(3):
                    T[r][c] = Rs[i, k, r, c]
                T[r][3] = ts[i, k, r]
            targets[n] = T @ rest[n]
        for n, M in targets.items():
            pb = PB[n]
            pb.matrix = M
            q = pb.rotation_quaternion.copy()
            if n in prev and q.dot(prev[n]) < 0:
                q.negate()
                pb.rotation_quaternion = q
            prev[n] = q
            pb.scale = (1, 1, 1)
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("location", frame=f)
print("KEYED spear and cape bones in %.1fs" % (time.time() - T0))

# End to end: the skinned cape and spear against the cache and the spear's object action.
check = {}
for name in CLIPS:
    set_clip(name)
    fr = frames_of(bpy.data.actions[name])
    worst, tipw = 0.0, 0.0
    for i in sorted({0, len(fr) // 3, 2 * len(fr) // 3, len(fr) - 1}):
        sc.frame_set(fr[i])
        dg = bpy.context.evaluated_depsgraph_get()
        ev = cape.evaluated_get(dg)
        co = np.array([v.co[:] for v in ev.data.vertices[:NV]])
        worst = max(worst, float(np.percentile(np.linalg.norm(co - Q[name][i], axis=1), 95)))
        evs = spear.evaluated_get(dg)
        tipw = max(tipw, (evs.matrix_world @ evs.data.vertices[TIP_IDX].co - samp[name]["tip"][i]).length)
    check[name] = (round(100 * worst, 2), round(1000 * tipw, 2))
print("CHECK skinned cape p95 cm / spear tip mm", json.dumps(check))

# 5. Measure the clips for the sidecar (on the poses as authored, before the turn moves
# to the root).
sc.frame_set(1)
set_clip("idle")
sc.frame_set(1)
IDLE_YAW = samp["idle"]["yaw"][0]


def footlock_speed(d):
    """Ground speed of an in-place walk: its planted foot slides back at the speed the
    clip walked (the travel removed from the hips), m/s along his forward (-Y)."""
    vs = []
    F = len(d["hips"])
    for k in range(F - 1):
        s = min(("Left", "Right"), key=lambda s_: d["ank"][s_][k])
        z = np.array(d["ank"][s])
        if d["ank"][s][k] < z.min() + 0.02:
            vs.append((d["foot"][s][k + 1] - d["foot"][s][k]).y * FPS)   # backwards is +Y
    return float(np.median(vs)) if vs else 0.0


clips = {}
for name in CLIPS:
    act = bpy.data.actions[name]
    d = samp[name]
    fr = frames_of(act)
    t = lambda f: round((f - fr[0]) / FPS, 4)
    vel = Vector(tuple(act["root_vel"]) + (0.0,)) if "root_vel" in act and name not in STILL else Vector()
    info = {
        "anim": name,
        "length": t(fr[-1]),
        "loop": name in LOOPS,
        "frames": len(fr),
        "root_vel": to_godot(vel),
        "root_motion": name.startswith("death"),
        "turn_deg": round(((d["yaw"][-1] - d["yaw"][0] + 180) % 360) - 180, 1),
        "hips_drift": to_godot(d["hips"][-1] - d["hips"][0]),
        "events": {},
    }
    if name in ("walk", "step_lane"):
        info["speed_mps"] = round(vel.length, 4)
        if name == "walk":
            info["speed_footlock_mps"] = round(footlock_speed(d), 4)   # a check of root_vel
        steps = []
        for s, z in d["ank"].items():
            z = np.array(z)
            gnd = z < z.min() + 0.03
            for k in range(1, len(gnd)):
                if gnd[k] and not gnd[k - 1]:
                    steps.append([t(fr[k]), s])
        info["events"]["steps"] = sorted(steps)
    if name == "attack":
        tips = d["tip"]
        reach = [-(p.y) for p in tips]  # forward is -Y
        speed = [0.0] + [(tips[k] - tips[k - 1]).length * FPS for k in range(1, len(tips))]
        k = next(j for j, r in enumerate(reach) if r >= max(reach) - 0.015)
        info["events"]["contact"] = t(fr[k])
        top = max(speed)
        swing = [fr[k2] for k2, v in enumerate(speed) if v > 0.5 * top]
        info["events"]["swing"] = [t(swing[0]), t(swing[-1])]
        info["tip_reach_m"] = round(max(reach), 3)
        info["lead_m"] = round(d["lead"][k], 3)
        print("REACH", name, [round(r, 2) for r in reach])
    if name.startswith("death"):
        hips = d["hips"]
        still = len(fr) - 1
        while still > 1 and (hips[still] - hips[still - 1]).length < 0.004:
            still -= 1
        info["events"]["settled"] = t(fr[still])
        spa = bpy.data.actions.get(name + "__spear")
        if spa is not None and "release_frame" in spa:
            info["events"]["spear_release"] = t(int(spa["release_frame"]))
    if name in LOOPS:
        set_clip(name)
        sc.frame_set(fr[0])
        a = {pb.name: pb.matrix.copy() for pb in PB if not pb.name.startswith("Cape_")}
        sc.frame_set(fr[-1])
        info["loop_seam_cm"] = round(100 * max((PB[n].matrix.translation - a[n].translation).length for n in a), 2)
    info["cape_fit"] = cape_fit[name]
    clips[name] = info
    print("CLIP", name, json.dumps(info))

# 6. The turn: moved from the hips to the root (footman's export_godot.py). The body is
# held at idle's heading and the sandbox turns the figure by `root_yaw`.
for name in [c for c in CLIPS if c.startswith("turn")]:
    act = bpy.data.actions[name]
    set_clip(name)
    fr = frames_of(act)
    ys, hm = [], []
    for f in fr:
        sc.frame_set(f)
        ys.append(hips_yaw())
        hm.append(b("Hips").matrix.copy())
    ys = np.degrees(np.unwrap(np.radians(ys)))
    d0 = ((ys[0] - IDLE_YAW + 180.0) % 360.0) - 180.0
    held = ys - ys[0] + d0
    ys = ys - ys[0]
    for f, y, m in zip(fr, held, hm):
        sc.frame_set(f)
        b("Hips").matrix = Matrix.Rotation(math.radians(-y), 4, "Z") @ m
        bpy.context.view_layer.update()
        b("Hips").keyframe_insert("rotation_quaternion", frame=f)
        b("Hips").keyframe_insert("location", frame=f)
    left = []
    for f in fr:
        sc.frame_set(f)
        left.append(hips_yaw())
    clips[name]["root_yaw"] = [round(float(y), 2) for y in ys]
    print("ROOT_YAW", name, round(float(ys[-1]), 1), "hips held at idle's heading within",
          round(max(abs(((v - IDLE_YAW + 180) % 360) - 180) for v in left), 1))

# 7. Only the clips go out (the spear's object actions are baked onto its bone).
for act in list(bpy.data.actions):
    if act.name not in clips:
        bpy.data.actions.remove(act)
for a in bpy.data.actions:
    a.use_frame_range = True
    a.frame_range = (1, int(a["frames"]))
# Weights a hair over 1 (up to 1.0004 on the body) make the exporter call the mesh invalid.
for o in bpy.data.objects:
    if o.type == "MESH":
        for v in o.data.vertices:
            for g in v.groups:
                if g.weight > 1.0:
                    g.weight = 1.0
set_clip("idle")
sc.frame_set(1)
textures = {}
for img in bpy.data.images:
    if img.size[0] == 0:
        continue
    if img.size[0] > TEX:
        img.scale(TEX, TEX)
        img.file_format = "JPEG"
    textures[img.name] = list(img.size)
    print("TEXTURE", img.name, tuple(img.size), img.file_format)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
tris = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes}
print("TRIANGLES", tris, sum(tris.values()))
for o in bpy.data.objects:
    o.select_set(o is rig or o in meshes)
OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=str(OUT), export_format="GLB", export_yup=True, export_apply=False,
    export_image_format="AUTO", export_jpeg_quality=88,
    export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True,
    export_frame_range=False, export_anim_slide_to_zero=True, export_anim_single_armature=True, export_reset_pose_bones=True,
    export_def_bones=False, export_optimize_animation_size=False, export_bake_animation=False,
    export_all_influences=True, export_extras=False, export_cameras=False, export_lights=False, use_selection=True,
)

# At ease is his idle; the guard is his ready stance in a fight and, now and then, a shift of
# position in the idle (variants: every_s apart, held hold_s, blended over blend_s).
roles = {"idle": "idle_rest", "ready": "idle", "walk": "walk", "attack": ["attack"], "hit": "hit",
         "death": [c for c in CLIPS if c.startswith("death")],
         "extra": [c for c in ("idle", "step_lane", "turn_90") if c in clips]}
variants = {"idle": {"clips": ["idle"], "every_s": [10.0, 20.0], "hold_s": [1.4, 2.8], "blend_s": 0.6}}
notes = [
    "Cape: glTF cannot carry the cloth's PC2 caches, so the baked cloth of every clip is fitted with "
    f"{K} cape bones ({COLS} columns round his back x {ROWS} rows, Cape_<row>_<col>, row 0 at the hem, children "
    "of mixamorig:Spine2; bilinear weights; the pinned rows under the hood keep their spine weights). Their "
    "keys reproduce cape_cache/<clip>.pc2 (errors per clip in clips.<clip>.cape_fit; spine_only_mean_cm is the "
    "error of the cape skinned to the spine alone). No new cloth bake. Solidify (1 cm, inwards) is applied.",
    "Spear: the per-clip object actions (<clip>__spear) are baked onto the bones 'SpearGrip' (child of "
    "mixamorig:RightHand, at the point of the shaft nearest the right fist's centre) and 'SpearBone' (its child, "
    "the butt; it only slides along the shaft), so cross-fades turn the spear about the fist and slide it through; "
    "the spear mesh is skinned to SpearBone. In the deaths it leaves the hand at spear_release.",
    "Locomotion is in place. walk and step_lane move the figure by root_vel (m/s, Godot axes); idle, idle_rest "
    "and turn_90 stand still (their small source drift was removed by retarget_clips.py). Deaths keep their "
    "authored travel on the hips (root_motion true, hips_drift); do not add it again.",
    "turn_90: the turn is moved to the root as in the footman's export: the body stays at idle's heading and "
    "root_yaw (degrees per frame from the first frame) turns the figure.",
    "Godot imports every clip with loop mode none; set it from clips.<clip>.loop. Animation names equal the clip "
    "names (clips.<clip>.anim).",
]
meta = {"fps": FPS, "source": "art/spearman_3d/spearman_rig.blend", "forward": [0, 0, 1],
        "height_m": round(float(head_mesh_top), 3),
        "height_rest_m": round(float(max(v.co.z for v in body.data.vertices)), 3),
        "roles": roles, "variants": variants, "notes": notes,
        "objects": sorted(o.name for o in meshes), "bones": len(rig.data.bones), "triangles": sum(tris.values()),
        "texture_px": max([s[0] for s in textures.values()] or [0]),
        "cape_bones": CAPE_BONES, "clips": clips}
OUT.with_suffix(".json").write_text(json.dumps(meta, indent=1))
print("EXPORT_DONE", OUT, OUT.stat().st_size, "in %.1fs" % (time.time() - T0))
