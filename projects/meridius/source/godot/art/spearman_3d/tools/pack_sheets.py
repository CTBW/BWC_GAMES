"""Pack rendered frames into the report's sprite sheets (needs Pillow).

  python pack_sheets.py <WORK/renders> <workspace/2026-10-20_meridius/spearman-3d> [clip,clip...]

Reads <renders>/<clip>_<facing>/*.png for all twelve clips (render_clips.sh), or only those
listed (the others' entries in frames.json are kept), crops every clip/facing to the union
of its frames' alpha boxes, scales by 0.75 and writes sheets/<clip>_<facing>.webp plus
frames.json. Paste frames.json into the tab's <script id="frames-data"> afterwards.
"""
import glob, json, math, os, sys
from concurrent.futures import ProcessPoolExecutor
from PIL import Image
SCALE = 0.75

def pack(args):
    src, out, clip, f = args
    files = sorted(glob.glob(f"{src}/{clip}_{f}/*.png"))
    ims = [Image.open(p).convert("RGBA") for p in files]
    box = None
    for im in ims:
        b = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
        if b:
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    pad = 10
    x0, y0 = max(0, box[0] - pad), max(0, box[1] - pad)
    x1, y1 = min(ims[0].width, box[2] + pad), min(ims[0].height, box[3] + pad)
    cw, ch = int((x1 - x0) * SCALE), int((y1 - y0) * SCALE)
    n = len(ims)
    cols = max(1, min(n, math.ceil(math.sqrt(n * ch / max(1, cw)))))
    rows = math.ceil(n / cols)
    while rows * ch > 16000:
        cols += 1
        rows = math.ceil(n / cols)
    sheet = Image.new("RGBA", (cols * cw, rows * ch), (0, 0, 0, 0))
    for i, im in enumerate(ims):
        sheet.paste(im.crop((x0, y0, x1, y1)).resize((cw, ch), Image.LANCZOS), ((i % cols) * cw, (i // cols) * ch))
    sheet.save(f"{out}/sheets/{clip}_{f}.webp", "WEBP", quality=82, method=4)
    return clip, f, {"file": f"sheets/{clip}_{f}.webp", "frames": n, "cols": cols, "w": cw, "h": ch,
                     "x": round(x0 * SCALE, 1), "y": round(y0 * SCALE, 1)}

if __name__ == "__main__":
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(f"{out}/sheets", exist_ok=True)
    clips = ["idle", "idle_rest", "walk", "attack", "hit", "death", "death_2", "death_3", "step_lane", "turn_90",
             "turn_90_r", "turn_180"]
    only = sys.argv[3].split(",") if len(sys.argv) > 3 else None
    jobs = [(src, out, c, f) for c in (only or clips) for f in ["sw", "se", "nw", "ne"]]
    meta = {"clips": {}, "fps": 30, "canvas": [int(520 * SCALE), int(560 * SCALE)]}
    if only:
        meta = json.load(open(f"{out}/frames.json"))
    with ProcessPoolExecutor(max_workers=3) as ex:
        for clip, f, m in ex.map(pack, jobs):
            meta["clips"].setdefault(clip, {})[f] = m
    meta["clips"] = {c: meta["clips"][c] for c in clips + sorted(set(meta["clips"]) - set(clips)) if c in meta["clips"]}
    json.dump(meta, open(f"{out}/frames.json", "w"), indent=1)
    print("packed", len(jobs))
