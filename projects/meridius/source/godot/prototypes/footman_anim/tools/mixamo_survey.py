"""Inventory the sampled Mixamo clips: travel, loop seam, hand activity, foot
contacts, plus a stick-figure contact sheet per clip (side and iso views).

  python -I mixamo_survey.py <motion_src dir> <out dir>
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

BONES = [("Hips", "Spine"), ("Spine", "Spine1"), ("Spine1", "Spine2"), ("Spine2", "Neck"), ("Neck", "Head"),
         ("Head", "HeadTop_End"),
         ("Spine2", "LeftShoulder"), ("LeftShoulder", "LeftArm"), ("LeftArm", "LeftForeArm"), ("LeftForeArm", "LeftHand"),
         ("LeftHand", "LeftHandMiddle1"),
         ("Spine2", "RightShoulder"), ("RightShoulder", "RightArm"), ("RightArm", "RightForeArm"),
         ("RightForeArm", "RightHand"), ("RightHand", "RightHandMiddle1"),
         ("Hips", "LeftUpLeg"), ("LeftUpLeg", "LeftLeg"), ("LeftLeg", "LeftFoot"), ("LeftFoot", "LeftToeBase"),
         ("LeftToeBase", "LeftToe_End"),
         ("Hips", "RightUpLeg"), ("RightUpLeg", "RightLeg"), ("RightLeg", "RightFoot"), ("RightFoot", "RightToeBase"),
         ("RightToeBase", "RightToe_End")]


def load(path):
    doc = json.loads(Path(path).read_text(encoding="utf-8"))
    names = list(doc["frames"][0]["joints"].keys())
    arr = np.array([[f["joints"][n] for n in names] for f in doc["frames"]], dtype=float)
    return doc, names, arr


def frame_axes(arr, idx):
    """Mixamo in Blender: the character faces -Y, its right is -X, up is +Z."""
    return np.array([0, -1.0, 0]), np.array([-1.0, 0, 0]), np.array([0, 0, 1.0])


def main():
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    report = []
    for path in sorted(src.glob("*.json")):
        if path.name.startswith("_"):
            continue
        doc, names, arr = load(path)
        idx = {n: i for i, n in enumerate(names)}
        fwd, right, up = frame_axes(arr, idx)
        # Toes point forward: make sure fwd agrees with the feet.
        toe = (arr[0, idx["LeftToe_End"]] + arr[0, idx["RightToe_End"]]) / 2 - (arr[0, idx["LeftFoot"]] + arr[0, idx["RightFoot"]]) / 2
        toe[2] = 0
        hips = arr[:, idx["Hips"]]
        travel = hips[-1] - hips[0]
        n = len(arr)
        local = lambda p: np.array([np.dot(p, fwd), np.dot(p, right), p[2]])
        tr = local(travel)
        seam = float(np.abs(arr[-1] - arr[0]).max())
        hand_r = np.linalg.norm(np.diff(arr[:, idx["RightHand"]], axis=0), axis=1).sum()
        hand_l = np.linalg.norm(np.diff(arr[:, idx["LeftHand"]], axis=0), axis=1).sum()
        foot_h = {s: arr[:, idx[s + "ToeBase"], 2] for s in ("Left", "Right")}
        contacts = {}
        for s, h in foot_h.items():
            floor = h.min()
            contacts[s] = "".join("_" if v < floor + 0.02 else "^" for v in h)
        entry = {"clip": path.stem, "source": doc["source"], "frames": n, "secs": round(n / doc["fps"], 2),
                 "travel_fwd_m": round(tr[0], 3), "travel_right_m": round(tr[1], 3), "travel_up_m": round(tr[2], 3),
                 "hips_height_range": [round(hips[:, 2].min(), 3), round(hips[:, 2].max(), 3)],
                 "loop_seam_m": round(seam, 3), "right_hand_path_m": round(hand_r, 2), "left_hand_path_m": round(hand_l, 2),
                 "contacts": contacts}
        report.append(entry)
        # Contact sheet: side view (fwd, up) and iso view (yaw 45, pitch 30).
        cols = min(n, 12)
        step = max(1, n // cols)
        picks = list(range(0, n, step))[:cols]
        cw, ch = 180, 260
        sheet = Image.new("RGB", (cw * len(picks), ch * 2), (245, 242, 235))
        d = ImageDraw.Draw(sheet)
        def proj_side(p):
            q = local(p - np.array([hips[0][0], hips[0][1], 0]))
            return q[0], q[2]
        yaw, pitch = math.radians(45), math.radians(30)
        def proj_iso(p):
            q = local(p - np.array([hips[0][0], hips[0][1], 0]))
            # camera looks at the character from its front-left at yaw 45
            x = q[0] * math.sin(yaw) + q[1] * math.cos(yaw)
            depth = q[0] * math.cos(yaw) - q[1] * math.sin(yaw)
            y = q[2] * math.cos(pitch) - depth * math.sin(pitch)
            return x, y
        for c, fi in enumerate(picks):
            for row, proj in enumerate((proj_side, proj_iso)):
                ox, oy = c * cw + cw / 2, row * ch + ch - 20
                for a, b in BONES:
                    pa, pb = proj(arr[fi, idx[a]]), proj(arr[fi, idx[b]])
                    side = "Left" in a or "Left" in b
                    col = (40, 90, 200) if side else ((200, 60, 40) if ("Right" in a or "Right" in b) else (40, 40, 40))
                    d.line([(ox + pa[0] * 100, oy - pa[1] * 100), (ox + pb[0] * 100, oy - pb[1] * 100)], fill=col, width=3)
                d.text((c * cw + 4, row * ch + 4), f"{fi}", fill=(0, 0, 0))
        d.text((4, ch * 2 - 14), f"{path.stem}  red=Right  blue=Left  top: side  bottom: iso", fill=(0, 0, 0))
        sheet.save(out / f"{path.stem}.png")
    (out / "survey.json").write_text(json.dumps(report, indent=1), encoding="utf-8")
    for e in report:
        print(json.dumps({k: v for k, v in e.items() if k != "contacts"}))
        for s, c in e["contacts"].items():
            print("   ", s[0], c)


main()
