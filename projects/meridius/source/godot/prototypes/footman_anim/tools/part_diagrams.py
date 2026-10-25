"""Diagrams of how each master view is cut into rig parts.

  python -I part_diagrams.py <prototype dir> <out dir>

Per view, four panels at source resolution: the cut-out master, the part map
(one colour per part, labelled), an exploded view (every part pushed out from
the body centre so the cuts and their padded joint underlaps show), and the
hidden areas that were painted in (underlaps and reconstructions in magenta).
"""
import colorsys
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

BG = (232, 226, 210)


def font(size):
    for name in ("arialbd.ttf", "segoeuib.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main():
    proto, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    for view in ("se", "sw", "ne"):
        pdir = proto / "art_src/parts" / view
        meta = json.loads((pdir / "parts.json").read_text(encoding="utf-8"))
        cut = Image.open(proto / "art_src/masters" / f"{view}_cut.png").convert("RGBA")
        owner = np.array(Image.open(pdir / "_owner.png"))
        names = meta["owner_index"]
        w, h = cut.size
        pad = 70
        W, H = w + pad * 2, h + pad * 2
        panels = []
        # 1 master
        p1 = Image.new("RGBA", (W, H), BG + (255,))
        p1.alpha_composite(cut, (pad, pad))
        panels.append(("Painted master", p1))
        # 2 part map
        cols = {}
        n = len(names)
        for i, nm in enumerate(names):
            r, g, b = colorsys.hsv_to_rgb((i * 0.618) % 1.0, 0.55, 0.95)
            cols[i + 1] = (int(r * 255), int(g * 255), int(b * 255))
        rgb = np.array(cut.convert("RGB")).astype(float)
        lum = (0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2])[..., None] / 255.0
        vis = np.zeros((h, w, 4), np.uint8)
        for k, c in cols.items():
            m = owner == k
            vis[m, :3] = (np.array(c)[None, :] * (0.45 + 0.55 * lum[m])).clip(0, 255)
            vis[m, 3] = 255
        # ink lines stay dark so the art is still readable
        ink = (lum[..., 0] < 0.3) & (owner > 0)
        vis[ink, :3] = (vis[ink, :3] * 0.35).astype(np.uint8)
        p2 = Image.new("RGBA", (W, H), BG + (255,))
        p2.alpha_composite(Image.fromarray(vis), (pad, pad))
        d2 = ImageDraw.Draw(p2)
        f = font(12)
        for k in cols:
            ys, xs = np.nonzero(owner == k)
            if ys.size < 30:
                continue
            cx, cy = int(np.median(xs)) + pad, int(np.median(ys)) + pad
            label = names[k - 1]
            tw = d2.textlength(label, font=f)
            d2.rectangle([cx - tw / 2 - 3, cy - 8, cx + tw / 2 + 3, cy + 8], fill=(255, 255, 255, 215))
            d2.text((cx - tw / 2, cy - 7), label, fill=(20, 20, 20, 255), font=f)
        panels.append((f"Part map · {len(names)} parts", p2))
        # 3 exploded view
        p3 = Image.new("RGBA", (W, H), BG + (255,))
        centre = np.array(meta["joints"].get("waist", [w / 2, h / 2]), float)
        recs = sorted([r for r in meta["parts"] if not r.get("alias_of")], key=lambda r: r["layer"])
        for r in recs:
            im = Image.open(pdir / f"{r['name']}.png").convert("RGBA")
            c = np.array([r["x"] + r["w"] / 2, r["y"] + r["h"] / 2])
            off = (c - centre) * 0.32
            p3.alpha_composite(im, (int(r["x"] + off[0]) + pad, int(r["y"] + off[1]) + pad))
        panels.append(("Exploded: parts with padded joints", p3))
        # 4 hidden areas painted in (part pixels not owned by that part at rest)
        p4 = Image.new("RGBA", (W, H), BG + (255,))
        ghost = cut.copy()
        ga = np.array(ghost)
        ga[..., 3] = (ga[..., 3] * 0.35).astype(np.uint8)
        p4.alpha_composite(Image.fromarray(ga), (pad, pad))
        hidden = np.zeros((h + 2 * pad, w + 2 * pad), bool)
        for r in recs:
            im = np.array(Image.open(pdir / f"{r['name']}.png").convert("RGBA"))
            a = im[..., 3] > 0
            k = names.index(r["name"]) + 1
            x0, y0 = r["x"], r["y"]
            own = np.zeros_like(a)
            sub = owner[y0:y0 + r["h"], x0:x0 + r["w"]]
            own[:sub.shape[0], :sub.shape[1]] = sub == k
            filled = a & ~own
            hidden[y0 + pad:y0 + pad + r["h"], x0 + pad:x0 + pad + r["w"]] |= filled[:h + 2 * pad - y0 - pad, :w + 2 * pad - x0 - pad]
        ov = np.zeros((H, W, 4), np.uint8)
        ov[hidden] = (214, 40, 150, 170)
        p4.alpha_composite(Image.fromarray(ov))
        panels.append(("Hidden areas painted in (magenta)", p4))
        # strip
        title_h = 30
        strip = Image.new("RGB", (W * 4, H + title_h), BG)
        ds = ImageDraw.Draw(strip)
        for i, (t, p) in enumerate(panels):
            strip.paste(p.convert("RGB"), (i * W, title_h))
            ds.text((i * W + 12, 8), t, fill=(30, 34, 44), font=font(15))
        strip.save(out / f"parts_{view}.jpg", quality=88)
        print(view, strip.size)


main()
