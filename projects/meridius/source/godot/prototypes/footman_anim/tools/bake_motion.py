"""Retarget the sampled Mixamo clips onto the 2D cut-out rig, per facing.

  python -I bake_motion.py <prototype dir> [--preview <dir>] [--only clip,clip] [--facings se,sw]

Pipeline per facing and clip
  1. Mixamo joints (Blender: -Y forward, -X right, Z up) -> character frame
     (fwd, right, up) -> the game's ground grid for the facing (SE = grid +x,
     right hand toward grid +y) -> the battle camera: 2:1 dimetric, 30 deg
     elevation (screen x = (gx - gy)/sqrt2, y = (gx + gy)/(2 sqrt2) - 0.866 z).
  2. Root motion is stripped (constant ground velocity removed from the hips);
     the measured velocity is kept so the march speed matches foot contact.
  3. Upper body: each 2D bone's screen angle is the projected Mixamo segment's
     angle plus the drawn-vs-reference offset weighted by the clip's pose
     weight w(t): w = 1 keeps the painted pose and adds Mixamo's motion on top
     (idle, block), w = 0 is Mixamo's absolute pose (the swing and the cut), so
     the blow lands where the source lands it. Limbs are stretched along their
     axis by the projected length ratio (clamped) for foreshortening.
  4. Legs: two-bone IK onto foot targets = drawn foot + scaled Mixamo foot
     motion, so a planted Mixamo foot is a planted 2D foot.
  5. Polish (clips.json): time warp (anticipation holds, fast contact, eased
     recovery), gains per bone group, squash and stretch on the body, blade
     stretch on the fastest frames, events (impact, footsteps).
Writes motion/<facing>.json: per clip frames of local bone transforms, part z
order, events and QA traces (foot and blade positions).
"""
import json
import math
import sys
from pathlib import Path

import numpy as np

SQ2 = math.sqrt(2.0)
VZ = math.cos(math.radians(30))
FPS = 30.0

# Facing -> grid forward vector (Formation.GRID_DIRS) and the drawn view used.
FACINGS = {
    "se": {"grid": (1, 0), "view": "se", "mirror": False, "swap": False},
    "sw": {"grid": (0, 1), "view": "sw", "mirror": False, "swap": False},
    "nw": {"grid": (-1, 0), "view": "ne", "mirror": True, "swap": True},
    "ne": {"grid": (0, -1), "view": "ne", "mirror": False, "swap": False},
}

# 2D bones: name, parent, joint, direction joint, Mixamo segment (from, to), group.
BONES = [
    ("hips", None, "hip_c", "waist", ("Hips", "Spine1"), "body"),
    ("spine", "hips", "waist", "chest_top", ("Spine1", "Neck"), "body"),
    ("head", "spine", "neck", "head_top", ("Neck", "HeadTop_End"), "head"),
    ("upper_r", "spine", "shoulder_r", "elbow_r", ("RightArm", "RightForeArm"), "arm_r"),
    ("fore_r", "upper_r", "elbow_r", "wrist_r", ("RightForeArm", "RightHand"), "arm_r"),
    ("hand_r", "fore_r", "wrist_r", "grip_r", ("RightHand", "RightHandMiddle1"), "arm_r"),
    ("sword", "hand_r", "grip_r", "sword_tip", None, "sword"),
    ("upper_l", "spine", "shoulder_l", "elbow_l", ("LeftArm", "LeftForeArm"), "arm_l"),
    ("fore_l", "upper_l", "elbow_l", "grip_l", ("LeftForeArm", "LeftHand"), "arm_l"),
    ("hand_l", "fore_l", "grip_l", None, None, "arm_l"),
    ("shield", "hand_l", "grip_l", None, None, "shield"),
    ("thigh_r", "hips", "hip_r", "knee_r", ("RightUpLeg", "RightLeg"), "leg"),
    ("shin_r", "thigh_r", "knee_r", "ankle_r", ("RightLeg", "RightFoot"), "leg"),
    ("foot_r", "shin_r", "ankle_r", "toe_r", ("RightFoot", "RightToeBase"), "leg"),
    ("thigh_l", "hips", "hip_l", "knee_l", ("LeftUpLeg", "LeftLeg"), "leg"),
    ("shin_l", "thigh_l", "knee_l", "ankle_l", ("LeftLeg", "LeftFoot"), "leg"),
    ("foot_l", "shin_l", "ankle_l", "toe_l", ("LeftFoot", "LeftToeBase"), "leg"),
]
BONE = {b[0]: b for b in BONES}
STRETCH = {"upper_r": (0.92, 1.04), "fore_r": (0.86, 1.05), "upper_l": (0.92, 1.04), "fore_l": (0.86, 1.05),
           "sword": (0.82, 1.06)}


def load_clip(path):
    doc = json.loads(Path(path).read_text(encoding="utf-8"))
    names = list(doc["frames"][0]["joints"].keys())
    J = {n: np.array([f["joints"][n] for f in doc["frames"]], float) for n in names}
    # character frame: fwd = -Y, right = -X, up = Z
    for n in J:
        v = J[n]
        J[n] = np.stack([-v[:, 1], -v[:, 0], v[:, 2]], -1)
    hands = {}
    for side in ("RightHand", "LeftHand"):
        M = np.array([f["matrices"][side] for f in doc["frames"]], float)[:, :3, :3]
        cols = []
        for c in range(3):
            v = M[:, :, c]
            v = np.stack([-v[:, 1], -v[:, 0], v[:, 2]], -1)
            cols.append(v / np.linalg.norm(v, axis=1, keepdims=True))
        hands[side] = cols
    return doc, J, hands


def project(p, grid):
    """Character frame points (..., 3) -> screen (..., 2) at a facing, metres."""
    fx, fy = grid
    rx, ry = -fy, fx
    gx = p[..., 0] * fx + p[..., 1] * rx
    gy = p[..., 0] * fy + p[..., 1] * ry
    sx = (gx - gy) / SQ2
    sy = (gx + gy) / (2 * SQ2) - p[..., 2] * VZ
    return np.stack([sx, sy], -1)


def depth(p, grid):
    """Toward the camera (bigger = nearer)."""
    fx, fy = grid
    rx, ry = -fy, fx
    gx = p[..., 0] * fx + p[..., 1] * rx
    gy = p[..., 0] * fy + p[..., 1] * ry
    return (gx + gy) / SQ2 * 0.5 + p[..., 2] * VZ


def ang(v):
    return np.arctan2(v[..., 1], v[..., 0])


def wrap(a):
    return (a + np.pi) % (2 * np.pi) - np.pi


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / max(1e-6, e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def curve(t, keys):
    """Piecewise smooth curve through [[t, v], ...]."""
    keys = sorted(keys)
    out = np.full_like(np.asarray(t, float), keys[0][1], dtype=float)
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        m = (t >= t0) & (t <= t1)
        out[m] = v0 + (v1 - v0) * smoothstep(t0, t1, t[m])
    out[t > keys[-1][0]] = keys[-1][1]
    return out


def time_warp(n_out, warp, n_src):
    """Output frame -> fractional source frame. warp = [[src, out_sec], ...]."""
    if not warp:
        return np.arange(n_out, dtype=float)
    ws = np.array(warp, float)
    t_out = np.arange(n_out) / FPS
    # Monotone cubic-ish: piecewise linear in out-time with smoothstep easing
    # inside each segment keeps holds (anticipation) and snaps (contact).
    from scipy.interpolate import PchipInterpolator
    src = PchipInterpolator(ws[:, 1], ws[:, 0])(np.clip(t_out, ws[0, 1], ws[-1, 1]))
    return np.clip(src, 0, n_src - 1)


def sample(arr, f):
    i0 = np.floor(f).astype(int)
    i1 = np.minimum(i0 + 1, arr.shape[0] - 1)
    a = (f - i0)[..., None] if arr.ndim > 1 else (f - i0)
    return arr[i0] * (1 - a) + arr[i1] * a


def two_bone_ik(a, target, l1, l2, bend_sign, stretch_max=1.06):
    """Joint positions (knee, foot) for a hip at `a`. bend_sign picks the side."""
    d = target - a
    dist = np.linalg.norm(d, axis=-1, keepdims=True)
    reach = (l1 + l2)
    s = np.clip(dist / reach, 1.0, stretch_max)
    l1s, l2s = l1 * s[..., 0], l2 * s[..., 0]
    dist_c = np.clip(dist[..., 0], abs(l1s - l2s) + 1e-3, l1s + l2s - 1e-4)
    u = d / np.maximum(dist, 1e-6)
    cos_a = (l1s ** 2 + dist_c ** 2 - l2s ** 2) / (2 * l1s * dist_c)
    alpha = np.arccos(np.clip(cos_a, -1, 1)) * bend_sign
    ca, sa = np.cos(alpha), np.sin(alpha)
    dirk = np.stack([u[..., 0] * ca - u[..., 1] * sa, u[..., 0] * sa + u[..., 1] * ca], -1)
    knee = a + dirk * l1s[..., None]
    foot = a + u * dist_c[..., None]
    return knee, foot, s[..., 0]


LIMB = ("shoulder", "elbow", "wrist", "grip", "hip", "knee", "ankle", "toe", "heel")


class ViewRig:
    """A drawn view as the rig of one facing. For NW (mirror + swap) the NE
    drawing is shown flipped: its near limbs become the character's left
    ones, and the props change hands so the sword stays in the right hand. The
    sword and shield art move with their new hands (part_shift)."""

    def __init__(self, proto: Path, view: str, mirror: bool, swap: bool):
        meta = json.loads((proto / "art_src/parts" / view / "parts.json").read_text(encoding="utf-8"))
        self.view = view
        self.size = meta["size"]
        self.parts = meta["parts"]
        J = {k: np.array(v, float) for k, v in meta["joints"].items()}
        self.part_shift = {}
        if swap:
            old = dict(J)
            for k, v in old.items():
                base, _, side = k.rpartition("_")
                if base in LIMB and side in ("r", "l"):
                    J[base + "_" + ("l" if side == "r" else "r")] = v
            d_sword = J["grip_r"] - old["grip_r"]
            d_shield = J["grip_l"] - old["grip_l"]
            for k in ("sword_tip", "sword_pommel"):
                J[k] = old[k] + d_sword
            J["shield_center"] = old["shield_center"] + d_shield
            self.part_shift = {"sword": d_sword.tolist(), "shield": d_shield.tolist()}
        self.J = J
        self.mirror = mirror
        self.swap = swap


def bone_rest(J):
    out = {}
    for name, parent, joint, dirj, seg, group in BONES:
        p = J[joint]
        d = J[dirj] - p if dirj and dirj in J else None
        out[name] = {"pos": p, "dir": d, "len": float(np.linalg.norm(d)) if d is not None else 0.0,
                     "ang": float(math.atan2(d[1], d[0])) if d is not None else 0.0}
    return out


def bake_clip(cfg, clip_doc, J3, hands, rest, facing, ref, scale_body, scale_leg, shield_dir):
    grid = FACINGS[facing]["grid"]
    mirror = FACINGS[facing]["mirror"]
    n_src = clip_doc["frames"].__len__()
    rng = cfg.get("range", [0, n_src - 1])
    span = rng[1] - rng[0]
    speed = cfg.get("speed", 1.0)
    warp = cfg.get("warp")
    if warp:
        n_out = int(round(warp[-1][1] * FPS)) + (0 if cfg.get("loop") else 1)
        fsrc = time_warp(n_out, [[w[0], w[1]] for w in warp], n_src)
    else:
        dur = span / FPS / speed
        n_out = int(round(dur * FPS)) + (0 if cfg.get("loop") else 1)
        fsrc = rng[0] + np.arange(n_out) * speed
        if cfg.get("loop"):
            fsrc = rng[0] + np.arange(n_out) * (span / n_out)
    t = np.arange(n_out) / FPS
    P = {k: sample(v, fsrc) for k, v in J3.items()}
    H = {k: [sample(c, fsrc) for c in v] for k, v in hands.items()}
    # Root motion: remove the hips' average ground velocity over the clip.
    root_v = np.zeros(3)
    if cfg.get("root_motion") == "strip":
        hips = P["Hips"]
        total = J3["Hips"][rng[1]] - J3["Hips"][rng[0]]
        root_v = np.array([total[0], total[1], 0.0]) / (span / FPS / speed)
        for k in P:
            P[k] = P[k] - root_v[None, :] * t[:, None]
    elif cfg.get("root_motion") == "hold":
        # Keep the body over its start point (deaths, hits): ground travel scaled.
        k_keep = float(cfg.get("travel_keep", 0.35))
        hips0 = J3["Hips"][rng[0]]
        drift = P["Hips"] - hips0
        drift[:, 2] = 0
        for k in P:
            P[k] = P[k] - drift * (1 - k_keep)
    # Authoring in 3D, before projection (character frame: fwd, right, up).
    hips_now = P["Hips"].copy()
    g_lat = float(cfg.get("lateral_gain", 1.0))
    if g_lat != 1.0:
        # Keep the blade in the soldier's own lane: the arm's sideways travel is
        # compressed about the shoulder (an overhead chop, not a wide sweep).
        sh = P["RightArm"][:, 1:2].copy()
        for k in ("RightForeArm", "RightHand", "RightHandMiddle1"):
            P[k][:, 1:2] = sh + (P[k][:, 1:2] - sh) * g_lat
        ax = H["RightHand"][0].copy()
        ax[:, 1] *= g_lat
        H["RightHand"][0] = ax / np.linalg.norm(ax, axis=1, keepdims=True)
    aim = cfg.get("aim")
    if aim:
        # Drive the cut forward: the sword arm turns up about the shoulder
        # (around the body's right axis) so contact lands ahead at chest
        # height instead of low and across.
        phi = -curve(t, aim)  # negative pitch raises the arm forward
        sh = P["RightArm"].copy()
        c_a, s_a = np.cos(phi), np.sin(phi)
        for k in ("RightForeArm", "RightHand", "RightHandMiddle1"):
            d = P[k] - sh
            f2 = d[:, 0] * c_a + d[:, 2] * s_a
            u2 = -d[:, 0] * s_a + d[:, 2] * c_a
            P[k] = sh + np.stack([f2, d[:, 1], u2], -1)
        for ci in range(3):
            v = H["RightHand"][ci]
            H["RightHand"][ci] = np.stack([v[:, 0] * c_a + v[:, 2] * s_a, v[:, 1], -v[:, 0] * s_a + v[:, 2] * c_a], -1)
    narrow = float(cfg.get("stance_narrow", 1.0))
    if narrow != 1.0:
        # Feet closer under the body (no crab walk): sideways offset from the hips scaled.
        for side in ("Left", "Right"):
            for k in (side + "Leg", side + "Foot", side + "ToeBase", side + "Toe_End"):
                P[k][:, 1] = hips_now[:, 1] + (P[k][:, 1] - hips_now[:, 1]) * narrow
    g_stride = float(cfg.get("stride_gain", 1.0))
    g_lift = float(cfg.get("lift_gain", 1.0))
    if g_stride != 1.0 or g_lift != 1.0:
        for side in ("Left", "Right"):
            for k, lift_w in ((side + "Leg", 0.5), (side + "Foot", 1.0), (side + "ToeBase", 1.0), (side + "Toe_End", 1.0)):
                P[k][:, 0] = hips_now[:, 0] + (P[k][:, 0] - hips_now[:, 0]) * g_stride
                floor = float(np.min(J3[side + "ToeBase"][:, 2]))
                P[k][:, 2] = floor + (P[k][:, 2] - floor) * (1 + (g_lift - 1) * lift_w)
        root_v = root_v * g_stride
    lean = math.radians(float(cfg.get("lean_deg", 0.0)))
    if lean:
        c_l, s_l = math.cos(lean), math.sin(lean)
        for k in P:
            if k in ("Hips",) or "Leg" in k or "Foot" in k or "Toe" in k:
                continue
            d = P[k] - hips_now
            f2 = d[:, 0] * c_l + d[:, 2] * s_l
            u2 = -d[:, 0] * s_l + d[:, 2] * c_l
            P[k] = hips_now + np.stack([f2, d[:, 1], u2], -1)
        for side in ("RightHand", "LeftHand"):
            for ci in range(3):
                v = H[side][ci]
                H[side][ci] = np.stack([v[:, 0] * c_l + v[:, 2] * s_l, v[:, 1], -v[:, 0] * s_l + v[:, 2] * c_l], -1)
    # Blade samples in the ground frame of the soldier (metres, relative to the
    # clip's start hips) for the neighbour collision checks.
    ax_c = H["RightHand"][0].copy()
    paint = cfg.get("_sword_rest3d")
    if paint is not None:
        # What is drawn: the painted guard rotates Mixamo's blade by the same
        # offset the 2D angles use, weighted by the clip's pose weight.
        a_ref = ref["hands"]["RightHand"][0] / np.linalg.norm(ref["hands"]["RightHand"][0])
        b_p = np.array(paint, float) / np.linalg.norm(paint)
        axis = np.cross(a_ref, b_p)
        sn = np.linalg.norm(axis)
        full = math.atan2(sn, float(np.dot(a_ref, b_p)))
        if sn > 1e-6:
            axis = axis / sn
            wcfg = cfg.get("w", {})
            w_s = curve(np.arange(n_out) / FPS, wcfg.get("sword", wcfg.get("all", [[0, 1.0]])))
            for i in range(n_out):
                ang_i = full * w_s[i]
                v = ax_c[i]
                ax_c[i] = v * math.cos(ang_i) + np.cross(axis, v) * math.sin(ang_i) + axis * np.dot(axis, v) * (1 - math.cos(ang_i))
    blade = np.stack([P["RightHand"] + ax_c * d for d in (0.0, 0.3, 0.6, 0.9)], 1)
    blade_rel = blade - np.concatenate([hips_now[:1, :2], np.zeros((1, 1))], 1)[None]
    S = {k: project(v, grid) for k, v in P.items()}
    D = {k: depth(v, grid) for k, v in P.items()}
    R = {k: project(v[None], grid)[0] for k, v in ref["J"].items()}
    if mirror:
        for dct in (S, R):
            for k in dct:
                dct[k] = dct[k] * np.array([-1.0, 1.0])
    # Pose weight curves per group (1 = painted pose + motion, 0 = Mixamo absolute).
    wkeys = cfg.get("w", {})
    gains = cfg.get("gain", {})
    out_rot = {}
    out_scale = {}
    glob = {}
    for name, parent, joint, dirj, seg, group in BONES:
        rb = rest[name]
        if group == "leg" or seg is None and name not in ("sword",):
            continue
        if name == "sword":
            ax = H["RightHand"][0]
            ax_ref = ref["hands"]["RightHand"][0]
            base = P["RightHand"]
            tip = project(base + ax * 0.9, grid)
            root = project(base, grid)
            tip_ref = project(ref["J"]["RightHand"] + ax_ref * 0.9, grid)
            root_ref = project(ref["J"]["RightHand"], grid)
            v = tip - root
            v_ref = tip_ref - root_ref
            if mirror:
                v = v * np.array([-1.0, 1.0])
                v_ref = v_ref * np.array([-1.0, 1.0])
        else:
            a, b = seg
            v = S[b] - S[a]
            v_ref = R[b] - R[a]
        if mirror:
            pass
        th = np.unwrap(ang(v))
        th_ref = float(ang(v_ref))
        g = float(gains.get(group, gains.get(name, 1.0)))
        w = curve(t, wkeys.get(group, wkeys.get("all", [[0, 1.0]])))
        drawn = rb["ang"]
        offset = float(wrap(drawn - th_ref))
        delta_motion = wrap(th - th_ref)
        # Painted pose plus motion (w=1) or Mixamo absolute (w=0), both with gain on the motion part.
        th_abs = th_ref + offset * w + (th - th_ref)
        th_abs = drawn + g * (th_abs - drawn)
        glob[name] = np.unwrap(th_abs)
        L = np.linalg.norm(v, axis=-1)
        L_ref = np.linalg.norm(v_ref)
        lo, hi = STRETCH.get(name, (1.0, 1.0))
        ratio = np.clip(L / max(1e-6, L_ref), lo, hi) if L_ref > 1e-6 else np.ones(n_out)
        # Foreshortening only once the limb leaves the painted pose.
        out_scale[name] = 1.0 + (ratio - 1.0) * (1.0 - 0.6 * w)
    # Shield: rides the left forearm, calmer than the arm.
    glob["hand_l"] = glob.get("fore_l", np.zeros(n_out))
    glob["shield"] = rest["shield"]["ang"] + 0.45 * (glob.get("fore_l", np.zeros(n_out)) - rest["fore_l"]["ang"])
    glob["hand_r"] = glob.get("hand_r", np.full(n_out, rest["hand_r"]["ang"]))
    # Hips translation (scaled by the leg scale), body squash.
    hip_ref = R["Hips"]
    hip_d = (S["Hips"] - hip_ref[None]) * scale_leg
    hip_d *= np.array(cfg.get("hip_gain", [1.0, 1.0]))[None]
    # Body positions in view px.
    frames = []
    # Forward kinematics for the upper body with rigid drawn lengths.
    def rot(v, a):
        c, s = np.cos(a), np.sin(a)
        return np.stack([v[..., 0] * c - v[..., 1] * s, v[..., 0] * s + v[..., 1] * c], -1)
    pos = {}
    gdelta = {}
    for name, parent, joint, dirj, seg, group in BONES:
        rb = rest[name]
        if name == "hips":
            pos[name] = rb["pos"][None] + hip_d
            gdelta[name] = glob["hips"] - rb["ang"]
            continue
        prb = rest[parent]
        off = rb["pos"] - prb["pos"]
        if group == "leg":
            continue
        # Parent's stretch moves the child along the parent's axis.
        par_scale = out_scale.get(parent, np.ones(n_out))
        if prb["dir"] is not None and prb["len"] > 0:
            u = prb["dir"] / prb["len"]
            along = off @ u
            off_s = off[None] + (par_scale - 1.0)[:, None] * (along * u)[None]
        else:
            off_s = np.repeat(off[None], n_out, 0)
        pos[name] = pos[parent] + rot(off_s, gdelta[parent])
        gdelta[name] = (glob[name] - rb["ang"]) if name in glob else gdelta[parent]
    # Legs: IK from the moved hips to the foot targets. Two passes: the first
    # measures how far a planted foot is beyond the leg's reach; the body is
    # moved toward it (smoothly) and the second pass solves for real.
    reach_fix = np.zeros((n_out, 2))
    for leg_pass in (0, 1):
        if leg_pass == 1 and np.abs(reach_fix).max() > 0.01:
            k = np.array([1, 3, 5, 3, 1], float) / 13.0
            for ax_i in (0, 1):
                col = np.pad(reach_fix[:, ax_i], 2, mode="edge")
                reach_fix[:, ax_i] = np.convolve(col, k, mode="valid")
            for name_b, parent_b, joint_b, dirj_b, seg_b, group_b in BONES:
                if group_b != "leg" and name_b in pos:
                    pos[name_b] = pos[name_b] + reach_fix
        elif leg_pass == 1:
            break
        need = np.zeros((n_out, 2))
        for side, mix in (("r", "Right"), ("l", "Left")):
            hip_rest = rest["thigh_" + side]["pos"]
            hip_p = pos["hips"] + rot((hip_rest - rest["hips"]["pos"])[None].repeat(n_out, 0), gdelta["hips"])
            ank_ref = R[mix + "Foot"]
            if cfg.get("stance_mode") == "mixamo":
                # The feet under the body as the source walks, measured from the hips
                # (the painted wide fighting stance is for standing, not marching).
                drawn_drop = (rest["shin_" + side]["pos"] + rest["shin_" + side]["dir"])[1] - rest["hips"]["pos"][1]
                rel = (S[mix + "Foot"] - S["Hips"]) * scale_leg
                rel_ref = (ank_ref - R["Hips"]) * scale_leg
                rel[:, 1] += drawn_drop - rel_ref[1]
                ank = pos["hips"] + rel
            else:
                ank = rest["shin_" + side]["pos"][None] + rest["shin_" + side]["dir"][None] + (S[mix + "Foot"] - ank_ref[None]) * scale_leg
            knee_rest = rest["shin_" + side]["pos"]
            l1 = rest["thigh_" + side]["len"]
            l2 = rest["shin_" + side]["len"]
            dt, ds = rest["thigh_" + side]["dir"], rest["shin_" + side]["dir"]
            cross = dt[0] * ds[1] - dt[1] * ds[0]
            bend = -1.0 if cross > 0 else 1.0
            # Plant: a foot on the ground (Mixamo toe at the floor) keeps the world
            # spot it landed on for the whole contact, eased in and out over 2 frames.
            h_toe = P[mix + "ToeBase"][:, 2]
            floor = float(np.min(J3[mix + "ToeBase"][:, 2]))
            down = h_toe < floor + 0.025
            v_px = project(root_v[None], grid)[0] * scale_leg * (np.array([-1.0, 1.0]) if mirror else 1.0)
            world = ank + v_px[None, :] * t[:, None]
            locked = world.copy()
            wgt = np.zeros(n_out)
            i = 0
            while i < n_out:
                if down[i]:
                    j = i
                    while j + 1 < n_out and down[j + 1]:
                        j += 1
                    if j - i >= 2:
                        spot = world[i + 1]
                        locked[i:j + 1] = spot
                        wgt[i:j + 1] = 1.0
                        for e in (1, 2):
                            if i - e >= 0:
                                wgt[i - e] = max(wgt[i - e], 1.0 - e / 3.0)
                                locked[i - e] = spot
                            if j + e < n_out:
                                wgt[j + e] = max(wgt[j + e], 1.0 - e / 3.0)
                                locked[j + e] = spot
                    i = j + 1
                else:
                    i += 1
            if cfg.get("plant", True):
                world = world * (1 - wgt[:, None]) + locked * wgt[:, None]
                ank = world - v_px[None, :] * t[:, None]
            knee, foot, s = two_bone_ik(hip_p, ank, l1, l2, bend, stretch_max=1.07)
            dvec = ank - hip_p
            dist = np.linalg.norm(dvec, axis=1)
            excess = np.maximum(0.0, dist - (l1 + l2) * 1.08) * wgt
            nd = dvec / np.maximum(dist, 1e-6)[:, None] * excess[:, None]
            bigger = np.linalg.norm(nd, axis=1) > np.linalg.norm(need, axis=1)
            need[bigger] = nd[bigger]
            th_t = ang(knee - hip_p)
            th_s = ang(foot - knee)
            pos["thigh_" + side] = hip_p
            pos["shin_" + side] = knee
            pos["foot_" + side] = foot
            gdelta["thigh_" + side] = np.unwrap(th_t) - rest["thigh_" + side]["ang"]
            gdelta["shin_" + side] = np.unwrap(th_s) - rest["shin_" + side]["ang"]
            vf = S[mix + "ToeBase"] - S[mix + "Foot"]
            vf_ref = R[mix + "ToeBase"] - R[mix + "Foot"]
            gf = float(gains.get("foot", 1.0))
            gdelta["foot_" + side] = gf * wrap(np.unwrap(ang(vf)) - float(ang(vf_ref)))
            out_scale["thigh_" + side] = s
            out_scale["shin_" + side] = s
        if leg_pass == 0:
            reach_fix = need

    # Stretch eases, never jumps: smoothed and rate-limited (a blade passing
    # edge-on would otherwise snap from full length to half in a frame).
    for k in list(out_scale.keys()):
        v = np.asarray(out_scale[k], float).copy()
        if v.size > 4:
            pad = np.pad(v, 2, mode="wrap" if cfg.get("loop") else "edge")
            v = np.convolve(pad, np.array([1, 2, 3, 2, 1], float) / 9.0, mode="valid")
            for i in range(1, v.size):
                v[i] = v[i - 1] + np.clip(v[i] - v[i - 1], -0.035, 0.035)
        out_scale[k] = v
    # The head turns only a little relative to the chest: a painted 3/4 face
    # rotated further reads as a broken neck.
    lim = float(cfg.get("head_clamp", 0.16))
    rel_h = gdelta["head"] - gdelta["spine"]
    gdelta["head"] = gdelta["spine"] + lim * np.tanh(rel_h / lim)
    # Guard: the shield is carried to a point in front of the chest, upright,
    # pushed toward the enemy (the block reads as a wall, not a raised arm).
    sg = cfg.get("shield_guard")
    if sg:
        wsg = curve(t, sg["w"]) * float(sg.get("k", 1.0))
        chest_c = (pos["spine"] + pos["head"]) * 0.5
        fwd = np.array(cfg.get("_fwd_screen", [1.0, 0.5]), float)
        fwd = fwd / max(1e-6, np.linalg.norm(fwd))
        goal = chest_c + fwd[None, :] * float(sg.get("fwd", 14)) + np.array([float(sg.get("dx", 0)), float(sg.get("up", 8))])[None, :]
        shift = (goal - pos["shield"]) * wsg[:, None]
        for b in ("hand_l", "shield"):
            pos[b] = pos[b] + shift
        g_sh = gdelta["shield"]
        gdelta["shield"] = g_sh * (1 - wsg) + float(sg.get("tilt", 0.0)) * wsg
        gdelta["hand_l"] = gdelta["shield"]
    top = cfg.get("topple")
    if top:
        # Death: after the stagger and the buckle, the whole body tips over
        # backwards about the rear foot, lands, bounces a little and settles.
        u = np.clip((t - top["start"]) / (top["end"] - top["start"]), 0, 1)
        fall = u * u * (3 - 2 * u)
        fall = np.where(u < 1, u ** 2.2, 1.0)
        settle = np.where(t > top["end"], np.exp(-(t - top["end"]) * 9) * np.sin((t - top["end"]) * 26) * 0.06, 0.0)
        fwd = np.array(cfg.get("_fwd_screen", [1.0, 0.5]), float)
        sign = -1.0 if fwd[0] > 0 else 1.0
        theta = sign * (float(top["angle"]) * fall + settle)
        # Pivot: the ground under the knees once he has dropped to them, so the
        # kneeling body tips over as one and the legs stay on the ground.
        i0 = min(n_out - 1, int(top["start"] * FPS))
        knees = (pos["shin_r"][i0] + pos["shin_l"][i0]) * 0.5
        sole = max(pos["foot_r"][i0][1], pos["foot_l"][i0][1])
        piv = np.array([knees[0], sole])
        c_t, s_t = np.cos(theta), np.sin(theta)
        for name_b in list(pos.keys()):
            d = pos[name_b] - piv[None, :]
            pos[name_b] = piv[None, :] + np.stack([d[:, 0] * c_t - d[:, 1] * s_t, d[:, 0] * s_t + d[:, 1] * c_t], -1)
            gdelta[name_b] = gdelta[name_b] + theta
    # Global pose per bone: joint position (view px) and screen angle of the bone.
    gang = {name: np.unwrap(rest[name]["ang"] + gdelta[name]) for name in gdelta}
    # z order of the sword: behind the body when the blade is farther from the camera than the chest.
    blade_mid = P["RightHand"] + H["RightHand"][0] * 0.45
    chest_d = depth(P["Spine2"], grid)
    sword_behind = depth(blade_mid, grid) < chest_d - float(cfg.get("sword_behind_margin", 0.12))
    # Hysteresis: hold a state for at least 3 frames.
    sb = sword_behind.copy()
    for i in range(1, n_out):
        if sb[i] != sb[i - 1]:
            j = min(n_out, i + 3)
            if not np.all(sword_behind[i:j] == sword_behind[i]):
                sb[i] = sb[i - 1]
    # Authored layer windows (clip seconds): "front" draws the blade over the
    # shield (the cut must read), "back" under the body.
    lay = cfg.get("_sword_layers", {"hand": 45, "behind": 22, "front": 55})
    sword_layer = np.where(sb, lay["behind"], lay["hand"]).astype(int)
    for win in cfg.get("sword_front", []):
        m = (t >= win[0]) & (t <= win[1])
        sword_layer[m] = lay["front"]
    for win in cfg.get("sword_back", []):
        m = (t >= win[0]) & (t <= win[1])
        sword_layer[m] = lay["behind"]
    # Events.
    events = []
    if "impact_src" in cfg:
        fi = int(np.argmin(np.abs(fsrc - cfg["impact_src"])))
        events.append({"frame": fi, "t": fi / FPS, "name": "impact"})
    feet_trace = {}
    for side, mix in (("r", "Right"), ("l", "Left")):
        h_toe = P[mix + "ToeBase"][:, 2]
        floor = float(np.min(J3[mix + "ToeBase"][:, 2]))
        down = h_toe < floor + 0.025
        feet_trace[side] = down.tolist()
        for i in range(1, n_out):
            if down[i] and not down[i - 1]:
                events.append({"frame": i, "t": i / FPS, "name": "footstep", "side": side})
    # Ground speed in view px/s (march): projected root velocity, leg scale.
    v_screen = project(root_v[None], grid)[0] * scale_leg
    if mirror:
        v_screen = v_screen * np.array([-1.0, 1.0])
    return {
        "frames": n_out, "fps": FPS, "loop": bool(cfg.get("loop")), "t_src": fsrc.tolist(),
        "gpos": {k: np.round(np.asarray(v), 3).tolist() for k, v in pos.items()},
        "gang": {k: np.round(np.asarray(v), 5).tolist() for k, v in gang.items()},
        "stretch": {k: np.round(np.asarray(v), 4).tolist() for k, v in out_scale.items()},
        "sword_behind": sb.tolist(),
        "sword_layer": sword_layer.tolist(),
        "events": events, "contact": feet_trace,
        "root_velocity": v_screen.tolist(),
        "root_velocity_m": root_v[:2].tolist(),
        "blade_m": np.round(blade_rel, 3).tolist(),
    }


def main():
    proto = Path(sys.argv[1])
    preview = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
    only = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else None
    facings = sys.argv[sys.argv.index("--facings") + 1].split(",") if "--facings" in sys.argv else list(FACINGS)
    clips = json.loads((proto / "tools/clips.json").read_text(encoding="utf-8"))
    ref_cfg = clips.pop("_ref")
    ref_doc, ref_J, ref_hands = load_clip(proto / "motion_src" / f"{ref_cfg['src']}.json")
    rf = ref_cfg["frame"]
    ref = {"J": {k: v[rf] for k, v in ref_J.items()}, "hands": {k: [c[rf] for c in v] for k, v in ref_hands.items()}}
    out_dir = proto / "motion"
    out_dir.mkdir(exist_ok=True)
    cache = {}
    for facing in facings:
        fc = FACINGS[facing]
        view = ViewRig(proto, fc["view"], fc["mirror"], fc["swap"])
        view_spec = json.loads((proto / "art_src/specs" / f"{fc['view']}.json").read_text(encoding="utf-8"))
        rest = bone_rest(view.J)
        # Scales: px per metre for the legs from the drawn leg vs the reference leg (projected).
        grid = fc["grid"]
        Rp = {k: project(v[None], grid)[0] for k, v in ref["J"].items()}
        mix_leg = 0.0
        for mix in ("Right", "Left"):
            mix_leg += np.linalg.norm(ref["J"][mix + "UpLeg"] - ref["J"][mix + "Leg"]) + np.linalg.norm(ref["J"][mix + "Leg"] - ref["J"][mix + "Foot"])
        drawn_leg = sum(rest[b]["len"] for b in ("thigh_r", "shin_r", "thigh_l", "shin_l"))
        scale_leg = drawn_leg / mix_leg
        spine_m = np.linalg.norm(Rp["Neck"] - Rp["Hips"])
        scale_body = np.linalg.norm(view.J["neck"] - view.J["hip_c"]) / spine_m
        result = {"facing": facing, "view": fc["view"], "mirror": fc["mirror"], "swap": fc["swap"],
                  "part_shift": view.part_shift, "layers": view_spec.get("layers_" + facing, {}),
                  "scale_leg": scale_leg, "scale_body": scale_body,
                  "rest": {k: {"pos": v["pos"].tolist(), "ang": v["ang"], "len": v["len"]} for k, v in rest.items()},
                  "clips": {}}
        for name, cfg in clips.items():
            if only and name not in only:
                continue
            src = cfg["src"]
            if src not in cache:
                cache[src] = load_clip(proto / "motion_src" / f"{src}.json")
            doc, J3, hands = cache[src]
            cfg = dict(cfg)
            cfg["_sword_rest3d"] = view_spec.get("rest3d", {}).get("sword")
            gx, gy = fc["grid"]
            fwd_s = [(gx - gy), (gx + gy) * 0.5]
            if fc["mirror"]:
                fwd_s[0] = -fwd_s[0]
            cfg["_fwd_screen"] = fwd_s
            cfg["_sword_layers"] = view_spec.get("sword_layers_" + facing, view_spec.get("sword_layers", {"hand": 45, "behind": 22, "front": 55}))
            cfg.update(view_spec.get("clip_overrides", {}).get(name, {}))
            cfg.update(view_spec.get("clip_overrides_" + facing, {}).get(name, {}))
            result["clips"][name] = bake_clip(cfg, doc, J3, hands, rest, facing, ref, scale_body, scale_leg, None)
        (out_dir / f"{facing}.json").write_text(json.dumps(result), encoding="utf-8")
        print(facing, "scale_leg %.1f px/m  scale_body %.1f px/m" % (scale_leg, scale_body),
              {k: v["frames"] for k, v in result["clips"].items()})


if __name__ == "__main__":
    main()
