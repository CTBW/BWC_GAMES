"""Keep the blade clear of his body and his shield (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python clear_blade.py -- [clip,clip...] [margin_cm]

The test is sword_report.py's (the blade against the posed body and the shield,
ray-parity checked). Where the blade comes within `margin_cm` (default 2):
  * against the body or the shield, the whole sword arm turns at the shoulder,
    which carries the blade off as one piece;
  * against his own sword shoulder or upper arm (which turn with the arm), the
    wrist tilts the blade off it.
Where both joints may serve, the one needing the smaller turn is used. The
attack's wind-up passed the blade flat behind his neck and through his hood
and shoulders: there the sword arm goes straight from its frame-5 pose to its
frame-16 pose (raised, ready to cut), eased, and the cut itself is untouched.
Each clip gets one direction of turn (the one that clears every such frame
with the least), and only its amount varies: it is spread over the frames
around (looping clips wrap) and eased, so the blade drifts off and back
instead of rolling. Frames still too close step up, for up to four rounds.
Prints each clip before and after. Run last, after every other pass.
"""
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
CLIPS = argv[0].split(",") if argv and argv[0] else [
    "idle", "walk", "attack", "block", "hit", "block_hit", "death", "lane", "turn_90", "turn_180", "stop", "start", "run"]
MARGIN = (float(argv[1]) if len(argv) > 1 else 2.0) / 100.0
LOOPS = {"idle", "walk", "block", "step_lane", "run"}
# The report's test, shared (it reads no arguments when imported this way).
_here = Path(__file__).resolve().parent if "__file__" in globals() else Path(bpy.path.abspath("//tools"))
_saved = sys.argv
sys.argv = [sys.argv[0], "--", ""]
_ns = {"__name__": "sword_report_lib"}
_src = (_here / "sword_report.py").read_text()
exec(compile(_src.split("\nfor clip in CLIPS:")[0], str(_here / "sword_report.py"), "exec"), _ns)
sys.argv = _saved
depth_now = _ns["depth_now"]

sc = bpy.context.scene
rig = bpy.data.objects["FootmanRig"]
PB = rig.pose.bones
JOINTS = {"arm": PB["mixamorig:RightArm"], "hand": PB["mixamorig:RightHand"]}
OWN = {"RightArm", "RightShoulder"}
STEPS = [3, 5, 7, 10, 13, 17, 22, 28]
# Per clip: the joints allowed, the largest turn (deg) and the frames it may touch.
CONFIG = {"attack": {"bridge": (5, 16), "max": 15},
          # The run pumps the sword past his face: the wrist tips the blade off it
          # (turning the whole arm away took 28 degrees and still grazed the head).
          "run": {"joints": ("hand",), "max": 35}}
CHAIN = ["mixamorig:RightShoulder", "mixamorig:RightArm", "mixamorig:RightForeArm", "mixamorig:RightHand"]
DIRS = [Vector(v).normalized() for v in ((0, 1, 0), (0, -1, 0), (1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1),
                                         (0, 1, 1), (0, -1, 1), (1, 0, 1), (-1, 0, 1), (0, 1, -1), (0, -1, -1), (1, 0, -1), (-1, 0, -1))]


def chest_axes():
    r = (PB["mixamorig:RightArm"].head - PB["mixamorig:LeftArm"].head).normalized()
    f = Vector((0, 0, 1)).cross(r).normalized()
    u = r.cross(f).normalized()
    return r, f, u


def turn(pb, d, deg):
    """Turn a joint about its head by `deg` about the direction `d` in the
    chest's axes (right, forward, up)."""
    if abs(deg) < 1e-4:
        return
    r, f, u = chest_axes()
    axis = (r * d.x + f * d.y + u * d.z).normalized()
    h = pb.matrix.translation.copy()
    pb.matrix = Matrix.Translation(h) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-h) @ pb.matrix
    pb.scale = (1.0, 1.0, 1.0)  # a shear leaves scale on the bone; no clip keys it, so it would hold in every clip
    bpy.context.view_layer.update()


def pose_at(f, base, plan):
    """Frame f with every joint at its keyed rotation plus the planned turns."""
    sc.frame_set(f)
    for j, pb in JOINTS.items():
        pb.rotation_quaternion = base[j]
    bpy.context.view_layer.update()
    for j in ("arm", "hand"):
        if j in plan:
            d, deg = plan[j]
            turn(JOINTS[j], d, deg)


def measure(f, base, plan):
    pose_at(f, base, plan)
    d, part = depth_now()
    return -d, part


def smooth_out(f, hi, ease=4):
    """0 up to the last frame a turn may touch, easing to 1 over `ease` frames after it."""
    t = min(1.0, max(0.0, (f - hi) / float(ease)))
    return t * t * (3 - 2 * t)


def spread(mag, cyclic, widen=4, sigma=2.0):
    n = len(mag)
    wide = []
    for i in range(n):
        v = 0.0
        for k in range(-widen, widen + 1):
            j = (i + k) % n if cyclic else i + k
            if 0 <= j < n and mag[j] > 0:
                v = max(v, mag[j] * (1.0 - abs(k) / (widen + 1.0)))
        wide.append(v)
    ks = range(-int(3 * sigma), int(3 * sigma) + 1)
    wts = [math.exp(-0.5 * (k / sigma) ** 2) for k in ks]
    out = []
    for i in range(n):
        acc = tw = 0.0
        for k, wt in zip(ks, wts):
            j = (i + k) % n if cyclic else i + k
            if 0 <= j < n:
                acc += wide[j] * wt
                tw += wt
        out.append(max(acc / tw, mag[i]))
    return out


for clip in CLIPS:
    act = bpy.data.actions.get(clip)
    if act is None:
        continue
    rig.animation_data.action = act
    f0, f1 = (int(v) for v in act.frame_range)
    frames = list(range(f0, f1 + 1))
    cyclic = clip in LOOPS
    cfg = CONFIG.get(clip, {})
    if "bridge" in cfg:
        a, c = cfg["bridge"]
        qa, qc = {}, {}
        for f, store in ((a, qa), (c, qc)):
            sc.frame_set(f)
            store.update({n: PB[n].rotation_quaternion.copy() for n in CHAIN})
        for f in range(a + 1, c):
            u = (f - a) / float(c - a)
            u = u * u * (3 - 2 * u)
            for n in CHAIN:
                PB[n].rotation_quaternion = qa[n].slerp(qc[n], u)
                PB[n].keyframe_insert("rotation_quaternion", frame=f)
        print("CLEAR_BLADE %-10s sword arm bridged from f%d to f%d" % (clip, a, c))
    base = []
    for f in frames:
        sc.frame_set(f)
        base.append({j: pb.rotation_quaternion.copy() for j, pb in JOINTS.items()})
    mags = {j: [0.0] * len(frames) for j in JOINTS}
    dirs = {}
    first = [measure(f, base[i], {}) for i, f in enumerate(frames)]
    report = []
    steps = [x for x in STEPS + [35, 45] if x <= cfg.get("max", STEPS[-1])]
    lo, hi = cfg.get("frames", (frames[0], frames[-1]))
    for group in ("other", "own"):
        if len(dirs) == len(JOINTS):
            break
        cur = [measure(f, base[i], {jj: (dirs[jj], mags[jj][i]) for jj in dirs}) for i, f in enumerate(frames)]
        # With only the wrist allowed, every contact is one problem for it.
        wrist_only = "arm" not in cfg.get("joints", ("arm", "hand"))
        bad = [i for i, (c, part) in enumerate(cur)
               if c < MARGIN and (wrist_only or (part in OWN) == (group == "own")) and lo <= frames[i] <= hi]
        if not bad:
            continue
        # A blade in his own sword arm only comes off at the wrist.
        allowed = [j for j in cfg.get("joints", ("arm", "hand")) if j not in dirs and (group == "other" or j == "hand")]
        if not allowed:
            continue
        need = {}
        for joint in allowed:
            for d in DIRS:
                row = []
                for i in bad:
                    a = None
                    for deg in steps:
                        plan = {jj: (dirs[jj], mags[jj][i]) for jj in dirs}
                        plan[joint] = (d, deg)
                        if measure(frames[i], base[i], plan)[0] >= MARGIN + 0.003:
                            a = deg
                            break
                    row.append(a)
                need[(joint, tuple(d))] = row
        def cost(item):
            row = item[1]
            miss = sum(1 for a in row if a is None)
            return (miss, max([a for a in row if a is not None] or [0]), sum(a for a in row if a is not None))
        (joint, dk), row = min(need.items(), key=cost)
        d = Vector(dk)
        dirs[joint] = d
        m = [0.0] * len(frames)
        for i, a in zip(bad, row):
            m[i] = float(a if a is not None else steps[-1])
        m = spread(m, cyclic)
        # Nothing outside the frames it may touch (the attack's swing keeps its line).
        m = [x * (1.0 - smooth_out(frames[i], hi)) if not cyclic else x for i, x in enumerate(m)]
        for rnd in range(4):
            mags[joint] = m
            plan_of = lambda i: {jj: (dirs[jj], mags[jj][i]) for jj in dirs}
            still = [i for i, f in enumerate(frames) if lo <= f <= hi and measure(f, base[i], plan_of(i))[0] < MARGIN]
            if not still:
                break
            for i in still:
                nxt = [x for x in steps if x > m[i]]
                m[i] = float(nxt[0]) if nxt else m[i]
            m = spread(m, cyclic, widen=2, sigma=1.5)
            m = [x * (1.0 - smooth_out(frames[i], hi)) if not cyclic else x for i, x in enumerate(m)]
        mags[joint] = m
        report.append("%s %.0f deg max about (%+.1f,%+.1f,%+.1f) over %d frames" % (
            joint, max(m), d.x, d.y, d.z, sum(1 for x in m if x > 0.5)))
    if not dirs:
        print("CLEAR_BLADE %-10s clear (closest %.1f cm)" % (clip, 100 * min(c for c, _ in first)))
        continue
    after = []
    for i, f in enumerate(frames):
        pose_at(f, base[i], {jj: (dirs[jj], mags[jj][i]) for jj in dirs})
        for pb in JOINTS.values():
            pb.keyframe_insert("rotation_quaternion", frame=f)
        after.append(-depth_now()[0])
    act["clear_blade"] = "margin %.1f cm; %s" % (100 * MARGIN, "; ".join(report))
    print("CLEAR_BLADE %-10s too close before %3d, after %3d of %d; closest %.1f -> %.1f cm; %s" % (
        clip, sum(1 for c, _ in first if c < MARGIN), sum(1 for c in after if c < MARGIN), len(frames),
        100 * min(c for c, _ in first), 100 * min(after), "; ".join(report)))
rig.animation_data.action = bpy.data.actions["idle"]
bpy.ops.wm.save_mainfile(compress=True)
print("CLEAR_BLADE_SAVED")
