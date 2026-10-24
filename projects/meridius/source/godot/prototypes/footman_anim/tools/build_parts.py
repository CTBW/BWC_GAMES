"""Split a master view into rig parts (cut-out), with padded underlaps.

  python -I build_parts.py <spec.json> <out dir> [--preview <png>]

Spec (art_src/specs/<view>.json):
  cut        RGBA master (art_src/masters/<view>_cut.png)
  parts      [{name, layer, poly, under?, outline_under?, paint?}], later entries win
             where rough polygons overlap. `layer` is the draw order at rest.
  joints     named points (cut px)

How ownership is decided: the painting is split into "cells" (regions
between its dark ink lines). A cell that lies mostly (>= CELL_SNAP) inside one
part's rough polygon goes to that part whole, so part edges follow the art's
own outlines; a cell that straddles is cut by the polygons. An ink pixel goes
to the uppermost part beside it (the part in front owns the line between them).

Underlaps (`under` polygons): hidden area a part must cover when it turns
(e.g. the thigh's top under the skirt). It is filled from the part's own
nearest pixels, so colours and side outlines continue; `outline_under` inks
the new silhouette edge of the filled area. `paint` lists extra RGBA patches
(art_src/paint/*.png, cut coordinates) composited into a part after the fill:
hand reconstructions and inpaint drafts.

Writes <out>/<part>.png (cropped, padded) and <out>/parts.json
({name, layer, x, y, w, h}). The reassembly check (rest pose == master) is
printed and the preview shows the ownership map and the reassembly.
"""
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

SNAP = 4
BLEED = 4
INK_LUMA = 78
PAD = 6


def luma(rgb):
    return 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]


def poly_mask(shape, poly):
    im = Image.new("L", (shape[1], shape[0]), 0)
    ImageDraw.Draw(im).polygon([tuple(p) for p in poly], fill=1)
    return np.array(im, bool)


def polys_mask(shape, polys):
    m = np.zeros(shape, bool)
    for p in polys:
        m |= poly_mask(shape, p)
    return m


def main():
    spec_path = Path(sys.argv[1])
    out = Path(sys.argv[2])
    preview = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    base = spec_path.parent.parent  # art_src
    cut = np.array(Image.open(base / spec["cut"]).convert("RGBA")).astype(np.float32)
    h, w = cut.shape[:2]
    alpha = cut[..., 3] > 127
    rgb = cut[..., :3]
    parts = spec["parts"]
    n = len(parts)
    layer = np.array([p["layer"] for p in parts])

    # Ownership, front to back: each part's traced polygon is refined by GrabCut
    # inside a narrow band (+-SNAP px) so its edge lands on the colour edge of the
    # art; pixels already taken by a part in front are excluded.
    bgr = rgb[..., ::-1].astype(np.uint8).copy()
    owner = np.full((h, w), -1, int)
    claimed = np.zeros((h, w), bool)
    for i in np.argsort(-layer, kind="stable"):
        p = parts[i]
        polys = [p["poly"]] if isinstance(p["poly"][0][0], (int, float)) else p["poly"]
        m = polys_mask((h, w), polys) & alpha
        r = int(p.get("snap", SNAP))
        avail = alpha & ~claimed
        if r > 0 and m.any():
            grow = ndi.binary_dilation(m, iterations=r)
            core = ndi.binary_erosion(m, iterations=r)
            ys, xs = np.nonzero(grow)
            y0, y1 = max(0, ys.min() - 8), min(h, ys.max() + 9)
            x0, x1 = max(0, xs.min() - 8), min(w, xs.max() + 9)
            gc = np.full((y1 - y0, x1 - x0), cv2.GC_BGD, np.uint8)
            sub_av = avail[y0:y1, x0:x1]
            gc[(grow[y0:y1, x0:x1]) & sub_av] = cv2.GC_PR_FGD
            gc[(grow[y0:y1, x0:x1] & ~m[y0:y1, x0:x1]) & sub_av] = cv2.GC_PR_BGD
            gc[core[y0:y1, x0:x1] & sub_av] = cv2.GC_FGD
            if (gc == cv2.GC_FGD).any() and ((gc == cv2.GC_BGD) | (gc == cv2.GC_PR_BGD)).any():
                bg_model = np.zeros((1, 65), np.float64)
                fg_model = np.zeros((1, 65), np.float64)
                try:
                    cv2.grabCut(bgr[y0:y1, x0:x1].copy(), gc, None, bg_model, fg_model, 5, cv2.GC_INIT_WITH_MASK)
                    got = np.zeros((h, w), bool)
                    got[y0:y1, x0:x1] = (gc == cv2.GC_FGD) | (gc == cv2.GC_PR_FGD)
                    m = got & avail
                except cv2.error:
                    m = m & avail
            else:
                m = m & avail
        else:
            m = m & avail
        # Keep the main body of the part (drop GrabCut crumbs), close pinholes.
        lab, nl = ndi.label(m)
        if nl > 1:
            sizes = ndi.sum(m, lab, range(1, nl + 1))
            keep = np.zeros(nl + 1, bool)
            keep[1:] = sizes >= max(25, 0.04 * sizes.max())
            m = keep[lab]
        owner[m] = i
        claimed |= m
    left = alpha & (owner < 0)
    if left.any():
        known = owner >= 0
        _, (iy, ix) = ndi.distance_transform_edt(~known, return_indices=True)
        owner[left] = owner[iy[left], ix[left]]
    ink = (luma(rgb) < INK_LUMA) & alpha

    out.mkdir(parents=True, exist_ok=True)
    records = []
    recon = np.zeros((h, w, 4), np.float32)
    order = np.argsort(layer, kind="stable")
    canvas_parts = []
    for i, p in enumerate(parts):
        own = alpha & (owner == i)
        img = np.zeros((h, w, 4), np.float32)
        img[own, :3] = rgb[own]
        img[own, 3] = 255
        # Hidden at rest only: inside the figure, under a part drawn in front.
        front = alpha & (owner >= 0) & (layer[np.maximum(owner, 0)] > p["layer"])
        under = polys_mask((h, w), p.get("under", [])) & ~own & front
        if under.any() and own.any():
            _, (iy, ix) = ndi.distance_transform_edt(~own, return_indices=True)
            fill_y, fill_x = iy.copy(), ix.copy()
            axis = p.get("axis")
            if axis:
                # Continue the part along its bone: each hidden pixel takes the
                # colour a few px inside the part on the line parallel to the axis,
                # so side outlines and bands run on instead of smearing sideways.
                joints = spec.get("joints", {})
                a = np.array(joints[axis[0]] if isinstance(axis[0], str) else axis[:2], float)
                b = np.array(joints[axis[1]] if isinstance(axis[1], str) else axis[2:4], float)
                d = (b - a) / max(1e-6, np.linalg.norm(b - a))
                qy, qx = np.nonzero(under)
                inner = ndi.binary_erosion(own, iterations=2)
                for sign in (1.0, -1.0):
                    todo = (fill_y[qy, qx] == iy[qy, qx]) & (fill_x[qy, qx] == ix[qy, qx])
                    found = np.zeros(qy.size, bool)
                    for step in range(1, 120):
                        py = np.round(qy + sign * d[1] * step).astype(int)
                        px = np.round(qx + sign * d[0] * step).astype(int)
                        ok = (py >= 0) & (py < h) & (px >= 0) & (px < w) & ~found
                        hit = np.zeros(qy.size, bool)
                        hit[ok] = inner[py[ok], px[ok]]
                        new_hit = hit & todo
                        fill_y[qy[new_hit], qx[new_hit]] = py[new_hit]
                        fill_x[qy[new_hit], qx[new_hit]] = px[new_hit]
                        found |= hit
                        todo &= ~hit
                        if not todo.any():
                            break
                # Along an axis the underlap is only what the bone's rays reach:
                # the part's own silhouette carried on, never a box.
                missed = np.zeros((h, w), bool)
                missed[qy, qx] = (fill_y[qy, qx] == iy[qy, qx]) & (fill_x[qy, qx] == ix[qy, qx]) & ~inner[iy[qy, qx], ix[qy, qx]]
                if p.get("axis_only", True):
                    under &= ~missed
            img[under, :3] = rgb[fill_y[under], fill_x[under]]
            img[under, 3] = 255
            if p.get("fill") == "cel":
                # Cloth seen only when a part in front moves away: the part's own
                # main tone, its shadow tone on the side away from the top-left
                # light and near the silhouette, like the painted flats around it.
                tones = rgb[own & ~ink]
                hint = np.array(p.get("tone", [214, 192, 150]), np.float32)
                crit = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.5)
                _, lab_k, centers = cv2.kmeans(tones.astype(np.float32), 6, None, crit, 3, cv2.KMEANS_PP_CENTERS)
                chroma = lambda c: c - c.mean(-1, keepdims=True)
                same = np.linalg.norm(chroma(centers) - chroma(hint[None]), axis=1) < 28
                cand = centers[same] if same.any() else centers
                base = cand[np.argmin(np.linalg.norm(cand - hint, axis=1))]
                darker = cand[luma(cand) < luma(base[None])[0] - 18]
                shade = darker[np.argmax(luma(darker))] if darker.size else base * 0.82
                full = own | under
                dist = ndi.distance_transform_edt(full)
                gy, gx = np.gradient(ndi.gaussian_filter(dist, 2))
                # Outward normal is -grad; it faces away from the light when it points right/down.
                away = (-gx * 0.7 - gy * 0.7) < 0  # normal pointing right/down
                band = (dist <= float(p.get("shade_px", 7))) & away
                img[under, :3] = base
                img[under & band, :3] = shade
            if p.get("outline_under"):
                full = img[..., 3] > 0
                edge = full & ~ndi.binary_erosion(full, iterations=int(p.get("outline_px", 3)))
                edge &= under
                img[edge, :3] = np.array(p.get("ink", [34, 30, 38]), np.float32)
        # Seam bleed: wherever a part in front covers this one, carry this part
        # BLEED px under it (nearest own colour), so the two never meet edge to
        # edge with half-transparent filtered borders.
        cur = img[..., 3] > 0
        if cur.any():
            grow = ndi.binary_dilation(cur, iterations=BLEED) & front & ~cur
            if grow.any():
                _, (by, bx) = ndi.distance_transform_edt(~cur, return_indices=True)
                img[grow, :3] = img[by[grow], bx[grow], :3]
                img[grow, 3] = 255
        for patch in p.get("paint", []):
            pim = np.array(Image.open(base / patch).convert("RGBA")).astype(np.float32)
            a = pim[..., 3:4] / 255.0
            img[..., :3] = img[..., :3] * (1 - a) + pim[..., :3] * a
            img[..., 3] = np.maximum(img[..., 3], pim[..., 3])
        ys, xs = np.nonzero(img[..., 3] > 0)
        if ys.size == 0:
            print("empty part", p["name"])
            continue
        x0, y0 = max(0, xs.min() - PAD), max(0, ys.min() - PAD)
        x1, y1 = min(w, xs.max() + 1 + PAD), min(h, ys.max() + 1 + PAD)
        crop = img[y0:y1, x0:x1].clip(0, 255).astype(np.uint8)
        if p.get("mirror_about"):
            # The part is drawn flipped about a joint (a face turned the other way).
            jx = spec["joints"][p["mirror_about"]][0]
            crop = crop[:, ::-1].copy()
            nx0 = int(round(2 * jx - x1))
            x1, x0 = nx0 + (x1 - x0), nx0
        Image.fromarray(crop).save(out / f"{p['name']}.png")
        records.append({"name": p["name"], "layer": p["layer"], "x": int(x0), "y": int(y0),
                        "w": int(x1 - x0), "h": int(y1 - y0), "own_px": int(own.sum()),
                        "under_px": int(under.sum())})
        canvas_parts.append((p["layer"], img))
    for a in spec.get("aliases", []):
        # A part drawn from another part's art (the far arm reuses the near arm):
        # mirrored or not, darkened as it lies in the far plane. Not part of the
        # rest-pose reassembly (it is hidden at rest).
        srcp = Image.open(out / f"{a['from']}.png").convert("RGBA")
        if a.get("flip_h"):
            srcp = srcp.transpose(Image.FLIP_LEFT_RIGHT)
        if a.get("flip_v"):
            srcp = srcp.transpose(Image.FLIP_TOP_BOTTOM)
        arr = np.array(srcp).astype(np.float32)
        arr[..., :3] *= float(a.get("tint", 0.85))
        Image.fromarray(arr.clip(0, 255).astype(np.uint8)).save(out / f"{a['name']}.png")
        src_rec = next(r for r in records if r["name"] == a["from"])
        ax, ay = src_rec["x"], src_rec["y"]
        if "at" in a:
            # Placed so the source part's joint lands on another joint.
            jf = spec["joints"][a["at"][0]]
            jt = spec["joints"][a["at"][1]]
            ax, ay = ax + jt[0] - jf[0], ay + jt[1] - jf[1]
        records.append({"name": a["name"], "layer": a["layer"], "x": int(a.get("x", ax)),
                        "y": int(a.get("y", ay)), "w": srcp.width, "h": srcp.height,
                        "own_px": 0, "under_px": 0, "alias_of": a["from"], "flip_h": bool(a.get("flip_h"))})
    for _, img in sorted(canvas_parts, key=lambda t: t[0]):
        a = img[..., 3:4] / 255.0
        recon[..., :3] = recon[..., :3] * (1 - a) + img[..., :3] * a
        recon[..., 3] = np.maximum(recon[..., 3], img[..., 3])
    vis = alpha
    diff = np.abs(recon[..., :3] - rgb)[vis].max() if vis.any() else 0
    extra = (recon[..., 3] > 0) & ~alpha
    print(f"reassembly: max diff over master {diff:.1f}, pixels outside master {int(extra.sum())}")
    own_map = np.where(alpha, owner + 1, 0).astype(np.uint8)
    Image.fromarray(own_map).save(out / "_owner.png")
    (out / "parts.json").write_text(json.dumps({"view": spec.get("view"), "size": [w, h], "parts": records,
                                                "joints": spec.get("joints", {}),
                                                "owner_index": [p["name"] for p in parts]}, indent=1), encoding="utf-8")
    if preview:
        rng = np.random.default_rng(3)
        cols = rng.integers(40, 255, (n, 3))
        own_vis = np.zeros((h, w, 3), np.uint8) + 255
        for i in range(n):
            own_vis[alpha & (owner == i)] = cols[i]
        own_vis[ink & alpha] = (own_vis[ink & alpha] * 0.55).astype(np.uint8)
        pv = Image.new("RGB", (w * 3, h), "white")
        pv.paste(Image.fromarray(own_vis), (0, 0))
        bg = Image.new("RGBA", (w, h), (255, 0, 255, 255))
        bg.alpha_composite(Image.fromarray(recon.clip(0, 255).astype(np.uint8)))
        pv.paste(bg.convert("RGB"), (w, 0))
        # Under fills shown in place over a grey ghost.
        ghost = np.full((h, w, 3), 230, np.uint8)
        ghost[alpha] = (rgb[alpha] * 0.25 + 190).clip(0, 255).astype(np.uint8)
        g = Image.fromarray(ghost).convert("RGBA")
        d = ImageDraw.Draw(pv)
        for i, p in enumerate(parts):
            under = polys_mask((h, w), p.get("under", []))
            if under.any():
                ov = np.zeros((h, w, 4), np.uint8)
                ov[under] = [*cols[i], 150]
                g.alpha_composite(Image.fromarray(ov))
            ys, xs = np.nonzero(alpha & (owner == i))
            if ys.size:
                d.text((int(xs.mean()) - 10, int(ys.mean()) - 5), p["name"][:8], fill=(0, 0, 0))
        pv.paste(g.convert("RGB"), (w * 2, 0))
        for name, (x, y) in spec.get("joints", {}).items():
            for ox in (0, w):
                d.ellipse([ox + x - 3, y - 3, ox + x + 3, y + 3], outline=(255, 0, 0), width=2)
        pv.save(preview)
        big = Image.fromarray(own_vis).resize((w * 2, h * 2), Image.NEAREST)
        db = ImageDraw.Draw(big)
        for i, p in enumerate(parts):
            ys, xs = np.nonzero(alpha & (owner == i))
            if ys.size:
                db.text((int(xs.mean()) * 2 - 12, int(ys.mean()) * 2 - 5), p["name"], fill=(0, 0, 0))
        for x in range(0, w, 10):
            db.line([(x * 2, 0), (x * 2, h * 2)], fill=(255, 255, 255) if x % 50 else (255, 0, 0))
        for y in range(0, h, 10):
            db.line([(0, y * 2), (w * 2, y * 2)], fill=(255, 255, 255) if y % 50 else (255, 0, 0))
        big.save(preview.replace(".png", "_owner.png"))


main()
