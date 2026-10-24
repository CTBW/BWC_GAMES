"""Offline preview of a baked clip on the cut-out parts (art QA, before Godot).

  python -I preview_rig.py <prototype dir> <facing> <clip> <out.gif> [--scale 1] [--travel] [--sheet <png>] [--bones]

Composites the part PNGs with the baked bone transforms exactly as the Godot
rig does (rotation about the joint, stretch along the drawn bone axis), in
the clip's frame order, and writes a GIF (and optionally a contact sheet).
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

PART_BONE = {
    "head": "head", "cowl_back": "spine", "cowl_front": "spine", "chest": "spine", "upper_l": "upper_l",
    "fore_l": "fore_l", "hand_l": "hand_l",
    "pelvis": "hips", "skirt_rear": "hips", "tabard": "hips", "skirt_front": "hips",
    "thigh_r": "thigh_r", "shin_r": "shin_r", "foot_r": "foot_r",
    "thigh_l": "thigh_l", "shin_l": "shin_l", "foot_l": "foot_l",
    "upper_r": "upper_r", "fore_r": "fore_r", "hand_r": "hand_r", "sword": "sword", "shield": "shield",
}
STRETCH_PARTS = {"upper_r", "fore_r", "upper_l", "fore_l", "sword", "thigh_r", "shin_r", "thigh_l", "shin_l"}


def affine(theta, s, u, joint, gpos):
    """Matrix mapping view-rest coordinates to output coordinates."""
    # stretch along unit u by s, then rotate by theta about the joint, then move joint to gpos
    S = np.eye(2) + (s - 1.0) * np.outer(u, u)
    c, si = math.cos(theta), math.sin(theta)
    Rm = np.array([[c, -si], [si, c]])
    A = Rm @ S
    t = gpos - A @ joint
    return A, t


def render(proto, facing, clip, scale=1.0, travel=False, bones=False, canvas=(560, 560), origin=(160, 60)):
    proto = Path(proto)
    mot = json.loads((proto / "motion" / f"{facing}.json").read_text(encoding="utf-8"))
    view = mot["view"]
    meta = json.loads((proto / "art_src/parts" / view / "parts.json").read_text(encoding="utf-8"))
    rest = mot["rest"]
    c = mot["clips"][clip]
    imgs = {p["name"]: Image.open(proto / "art_src/parts" / view / f"{p['name']}.png").convert("RGBA") for p in meta["parts"]}
    frames = []
    W, H = int(canvas[0] * scale), int(canvas[1] * scale)
    vel = np.array(c.get("root_velocity", [0, 0]))
    for f in range(c["frames"]):
        out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        shift = np.array(origin, float) + (vel * f / c["fps"] if travel else 0)
        order = []
        for p in meta["parts"]:
            layer = p["layer"]
            if p["name"] == "sword" and c["sword_behind"][f]:
                layer = 22
            order.append((layer, p))
        for layer, p in sorted(order, key=lambda t: t[0]):
            b = PART_BONE.get(p["name"])
            if b is None or b not in c["gpos"]:
                continue
            rb = rest[b]
            joint = np.array(rb["pos"])
            g = np.array(c["gpos"][b][f]) + shift
            theta = c["gang"][b][f] - rb["ang"]
            s = c["stretch"].get(b, [1.0] * c["frames"])[f] if p["name"] in STRETCH_PARTS else 1.0
            ang0 = rb["ang"]
            u = np.array([math.cos(ang0), math.sin(ang0)])
            A, t = affine(theta, s, u, joint, g)
            # part image pixel (i,j) -> view rest coords (x + i, y + j)
            A_img = A * scale
            t_img = (A @ np.array([p["x"], p["y"]]) + t) * scale
            inv = np.linalg.inv(A_img)
            ti = -inv @ t_img
            im = imgs[p["name"]]
            data = (inv[0, 0], inv[0, 1], ti[0], inv[1, 0], inv[1, 1], ti[1])
            layer_im = im.transform((W, H), Image.AFFINE, data, resample=Image.BILINEAR)
            out.alpha_composite(layer_im)
        if bones:
            d = ImageDraw.Draw(out)
            for name, gp in c["gpos"].items():
                q = (np.array(gp[f]) + shift) * scale
                d.ellipse([q[0] - 3, q[1] - 3, q[0] + 3, q[1] + 3], outline=(255, 0, 0, 255))
            for side in ("r", "l"):
                if c["contact"][side][f]:
                    q = (np.array(c["gpos"]["foot_" + side][f]) + shift) * scale
                    d.rectangle([q[0] - 4, q[1] - 4, q[0] + 4, q[1] + 4], outline=(0, 200, 0, 255), width=2)
        frames.append(out)
    return frames, c


def main():
    proto, facing, clip, out = sys.argv[1:5]
    scale = float(sys.argv[sys.argv.index("--scale") + 1]) if "--scale" in sys.argv else 1.0
    frames, c = render(proto, facing, clip, scale, "--travel" in sys.argv, "--bones" in sys.argv)
    bg = (196, 186, 150, 255)
    flat = []
    for fr in frames:
        b = Image.new("RGBA", fr.size, bg)
        b.alpha_composite(fr)
        flat.append(b.convert("RGB"))
    flat[0].save(out, save_all=True, append_images=flat[1:], duration=int(1000 / c["fps"]), loop=0)
    if "--sheet" in sys.argv:
        sheet_path = sys.argv[sys.argv.index("--sheet") + 1]
        n = len(flat)
        step = max(1, n // 12)
        pick = list(range(0, n, step))[:12]
        tw, th = flat[0].width // 2, flat[0].height // 2
        sheet = Image.new("RGB", (tw * len(pick), th + 16), (255, 255, 255))
        d = ImageDraw.Draw(sheet)
        for i, fi in enumerate(pick):
            sheet.paste(flat[fi].resize((tw, th)), (i * tw, 16))
            ev = [e["name"][0] for e in c["events"] if e["frame"] == fi]
            d.text((i * tw + 4, 2), f"{fi} {''.join(ev)}", fill=(0, 0, 0))
        sheet.save(sheet_path)
    print(out, len(frames))


if __name__ == "__main__":
    main()
