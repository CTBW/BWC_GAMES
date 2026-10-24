"""Pass / fail for the footman prototype from qa/review.gd's log.

  python -I review_report.py <review dir> [out.json]

Checks (per clip x facing unless noted), thresholds in world px at battle scale:
  1 equipment   exactly one sword, one shield, one head visible in every frame
  2 weapons     sword and shield visible every frame; drawn in their authored
                layer relative to the chest (in hand / over the shield / behind)
  3 handedness  sword hangs off the right-hand chain, shield off the left, the
                grip stays in the hand (wrist-grip distance constant) and the
                sword is on the drawn side of the shield at rest
  4 sliding     a planted foot (contact frames) drifts < 1.5 px in the world
  5 size        bounding box and part scales change smoothly (no frame jumps)
  6 neighbours  squad scenarios: no body or blade overlap (Formation.overlaps)
  seams         small transparent cracks near joints in the figure-alone renders
  pops          transitions: no joint jumps beyond the clips' own motion
"""
import glob
import json
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

SLIDE_PX = 1.5
JUMP_BOX = 0.14
JUMP_SCALE = 0.08
CRACK_MAX = 30
VIEW = (300, 300)
ZOOM = 3.0
CAM = (0.0, -38.0)
SWORD_SIDE = {"se": -1, "sw": -1, "ne": 1, "nw": 1}


def runs(flags):
    out, start = [], None
    for i, f in enumerate(flags + [False]):
        if f and start is None:
            start = i
        elif not f and start is not None:
            out.append((start, i - 1))
            start = None
    return out


def check_clip(key, c):
    fr = c["frames"]
    res = {}
    n = len(fr)
    # 1 equipment
    bad = [i for i, f in enumerate(fr) if f["swords"] != 1 or f["shields"] != 1 or f["heads"] != 1]
    res["equipment"] = {"pass": not bad, "frames": n, "bad_frames": bad[:10],
                        "max_swords": max(f["swords"] for f in fr), "max_shields": max(f["shields"] for f in fr)}
    # 2 weapons visible and layered
    vis_bad = [i for i, f in enumerate(fr) if not f["sword_vis"] or not f["shield_vis"]]
    lay_bad = []
    for i, f in enumerate(fr):
        o = f["order"]
        lay = f["sword_layer"]
        if lay >= 45 and not o["sword"] > o["chest"]:
            lay_bad.append(i)
        if lay >= 55 and not o["sword"] > o["shield"]:
            lay_bad.append(i)
        if lay <= 22 and not o["sword"] < o["chest"]:
            lay_bad.append(i)
        if not o["shield"] > o["chest"]:
            lay_bad.append(i)
    res["weapons"] = {"pass": not vis_bad and not lay_bad, "hidden_frames": vis_bad[:10], "layer_bad": sorted(set(lay_bad))[:10],
                      "layers_seen": sorted(set(f["sword_layer"] for f in fr))}
    # 3 handedness
    chain_ok = all(f["sword_bone"] == "sword" and f["shield_bone"] == "shield" for f in fr)
    d = np.array([f["grip_hand_d"] for f in fr])
    j0 = fr[0]["joints"]
    side = math.copysign(1, j0["sword"][0] - j0["shield"][0])
    side_ok = side == SWORD_SIDE[c["facing"]]
    res["handedness"] = {"pass": bool(chain_ok and d.std() < 0.6 and side_ok), "chain": chain_ok,
                         "grip_in_hand_std_px": round(float(d.std()), 3), "sword_side_at_rest": "left" if side < 0 else "right",
                         "expected_side": "left" if SWORD_SIDE[c["facing"]] < 0 else "right"}
    # 4 foot sliding during contact
    v = np.array(c["root_velocity"])
    worst = 0.0
    detail = {}
    for side_k in ("r", "l"):
        con = c["contact"].get(side_k, [])
        flags = [bool(con[i]) if i < len(con) else False for i in range(n)]
        if c["clip"] == "walk":
            # The loop repeats: frames beyond the baked length reuse contact flags cyclically.
            L = len(con)
            flags = [bool(con[i % L]) for i in range(n)] if L else flags
        pts = np.array([f["joints"]["foot_" + side_k] for f in fr], float)
        t = np.arange(n) / 30.0
        world = pts + v[None, :] * t[:, None]
        drifts = []
        for a, b in runs(flags):
            if b - a < 2:
                continue
            seg = world[a:b + 1]
            drifts.append(float(np.max(np.linalg.norm(seg - seg[0], axis=1))))
        detail[side_k] = round(max(drifts), 3) if drifts else None
        if drifts:
            worst = max(worst, max(drifts))
    res["foot_slide"] = {"pass": worst < SLIDE_PX, "max_drift_px": round(worst, 3), "per_foot": detail}
    # 5 size changes
    box = np.array([f["bbox"] for f in fr], float)
    area = box[:, 2] * box[:, 3]
    jumps = []
    for i in range(1, n):
        r = abs(area[i] - area[i - 1]) / max(1.0, area[i - 1])
        if r > JUMP_BOX:
            jumps.append((i, round(float(r), 3)))
    sj = []
    for part in fr[0]["scales"]:
        sc = np.array([f["scales"][part] for f in fr], float)
        dd = np.abs(np.diff(sc, axis=0)).max(axis=1) / np.maximum(1e-6, np.abs(sc[:-1]).max(axis=1))
        for i in np.nonzero(dd > JUMP_SCALE)[0]:
            sj.append((part, int(i) + 1, round(float(dd[i]), 3)))
    res["size"] = {"pass": not jumps and not sj, "box_jumps": jumps[:8], "scale_jumps": sj[:8],
                   "box_range": [round(float(area.min()), 1), round(float(area.max()), 1)]}
    return res


REST_CRACKS = {}


def rest_cracks(review_dir, log):
    """Pinholes the painted master itself has (anti-aliased thin features),
    counted on each facing's rest pose: a seam is a crack beyond these."""
    for key, c in log["clips"].items():
        if c["clip"] != "idle":
            continue
        f = os.path.join(review_dir, key, "0000.png")
        if os.path.exists(f):
            REST_CRACKS[c["facing"]] = _cracks(f, c["frames"][0]["joints"])


def _cracks(f, js):
    a = np.array(Image.open(f))[..., 3] > 12
    holes = ndi.binary_fill_holes(a) & ~a
    lab, nl = ndi.label(holes)
    if nl == 0:
        return 0
    sizes = ndi.sum(holes, lab, range(1, nl + 1))
    cents = ndi.center_of_mass(holes, lab, range(1, nl + 1))
    jpx = [((p[0] - CAM[0]) * ZOOM + VIEW[0] / 2, (p[1] - CAM[1]) * ZOOM + VIEW[1] / 2) for p in js.values()]
    return sum(1 for sz, (cy, cx) in zip(sizes, cents) if sz <= CRACK_MAX and min(math.hypot(cx - x, cy - y) for x, y in jpx) < 14)


def seams(review_dir, key, c):
    d = os.path.join(review_dir, key)
    files = sorted(glob.glob(os.path.join(d, "*.png")))
    worst, worst_frame, total = 0, None, 0
    for f in files:
        i = int(os.path.basename(f)[:-4])
        if i >= len(c["frames"]):
            continue
        a = np.array(Image.open(f))[..., 3] > 12
        holes = ndi.binary_fill_holes(a) & ~a
        lab, nl = ndi.label(holes)
        if nl == 0:
            continue
        sizes = ndi.sum(holes, lab, range(1, nl + 1))
        cents = ndi.center_of_mass(holes, lab, range(1, nl + 1))
        js = c["frames"][i]["joints"]
        jpx = [((p[0] - CAM[0]) * ZOOM + VIEW[0] / 2, (p[1] - CAM[1]) * ZOOM + VIEW[1] / 2) for p in js.values()]
        cracks = 0
        for sz, (cy, cx) in zip(sizes, cents):
            if sz > CRACK_MAX:
                continue
            if min(math.hypot(cx - x, cy - y) for x, y in jpx) < 14:
                cracks += 1
        total += cracks
        if cracks > worst:
            worst, worst_frame = cracks, i
    base = REST_CRACKS.get(c["facing"], 0)
    return {"pass": worst <= base, "frames_checked": len(files), "max_cracks_in_a_frame": worst, "worst_frame": worst_frame,
            "total_cracks": total, "rest_pose_cracks": base}


def second_diff(frames, skip=("sword",)):
    """Largest joint acceleration (px / frame^2) per frame (60 Hz logs)."""
    names = [k for k in frames[0]["joints"] if k not in skip]
    P = np.array([[f["joints"][k] for k in names] for f in frames], float)
    acc = np.zeros(len(frames))
    if len(frames) > 2:
        a = np.linalg.norm(P[2:] - 2 * P[1:-1] + P[:-2], axis=2).max(axis=1)
        acc[1:-1] = a
    return acc


def check_transitions(log):
    # Natural limit: the clips' own largest joint acceleration, resampled to 60 Hz.
    natural = {}
    for key, c in log["clips"].items():
        acc30 = second_diff(c["frames"])
        natural[key] = float(acc30.max()) / 4.0  # 30 Hz -> 60 Hz second difference scales by 1/4
    out = {}
    for key, tr in log["transitions"].items():
        fac = tr["facing"]
        fr = tr["frames"]
        acc = second_diff(fr)
        anims = sorted(set(f["anim"] for f in fr if f["anim"]))
        lim = max([natural.get(f"{fac}_{a}", 0.0) for a in anims] + [0.5]) * 1.3 + 0.6
        # Changes of animation (the blend start) and the frames right after.
        pops = [(i, round(float(acc[i]), 2)) for i in range(len(fr)) if acc[i] > lim]
        eq_bad = [i for i, f in enumerate(fr) if f["swords"] != 1 or f["shields"] != 1]
        out[key] = {"pass": not pops and not eq_bad, "limit": round(lim, 2), "max_acc": round(float(acc.max()), 2),
                    "pops": pops[:6], "equipment_bad": eq_bad[:6], "anims": anims}
    return out


def check_squad(log):
    out = {}
    for key, sq in log["squad"].items():
        fr = sq["frames"]
        ov_frames = [i for i, f in enumerate(fr) if f["ov"] > 0]
        kinds = {}
        for f in fr:
            for k in f["kinds"]:
                kinds[k] = kinds.get(k, 0) + 1
        last = fr[-1]["m"]
        slot_err = [round(math.hypot(m["pos"][0] - s[0], m["pos"][1] - s[1]), 2) for m, s in zip(last, sq["slots"])]
        imp = [m["impacts"] for m in last]
        eq = [i for i, f in enumerate(fr) if any(m["swords"] != 1 for m in f["m"])]
        res = {"overlap_frames": len(ov_frames), "frames": len(fr), "kinds": kinds,
               "first_overlaps": [fr[i]["pairs"] for i in ov_frames[:3]], "blows": sq["blows"], "dummy_hits": sq["dummy_hits"],
               "impacts_per_soldier": imp, "slot_error_end_px": slot_err, "equipment_bad_frames": len(eq)}
        res["pass"] = len(ov_frames) == 0 and len(eq) == 0
        out[key] = res
    return out


def main():
    rd = sys.argv[1]
    log = json.load(open(os.path.join(rd, "review.json"), encoding="utf-8"))
    clips = {}
    rest_cracks(rd, log)
    for key, c in log["clips"].items():
        r = check_clip(key, c)
        r["seams"] = seams(rd, key, c)
        clips[key] = r
    report = {"clips": clips, "transitions": check_transitions(log) if log["transitions"] else {},
              "squad": check_squad(log) if log["squad"] else {}}
    summary = {}
    for k in ("equipment", "weapons", "handedness", "foot_slide", "size", "seams"):
        fails = [key for key, r in clips.items() if not r[k]["pass"]]
        summary[k] = {"pass": len(clips) - len(fails), "fail": len(fails), "failing": fails}
    summary["transitions"] = {"pass": sum(1 for r in report["transitions"].values() if r["pass"]),
                              "fail": [k for k, r in report["transitions"].items() if not r["pass"]]}
    summary["neighbours"] = {"pass": sum(1 for r in report["squad"].values() if r["pass"]),
                             "fail": [k for k, r in report["squad"].items() if not r["pass"]]}
    report["summary"] = summary
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(rd, "report.json")
    json.dump(report, open(out, "w", encoding="utf-8"), indent=1)
    print(json.dumps(summary, indent=1))


main()
