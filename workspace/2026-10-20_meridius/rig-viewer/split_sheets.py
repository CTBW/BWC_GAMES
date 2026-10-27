"""Split a pose viewer clip's sheets into bands of whole rows (Python with Pillow).

  python split_sheets.py <frames dir> <card folder> <clip>[,<clip>...] [max Mpx]

A long clip on the wide canvas packs into sheets of 30 Mpx and more. With its four facings shown
together the browser cannot keep them all decoded, and the viewer stalls on every frame. For
each named clip and facing this re-packs the rendered frames into bands of whole rows of at most
max Mpx (default 4): the same scale, crop, cell and grid as the packed sheet, read from the
card's frames.json, so only the files change. It writes sheets/<clip>_<facing>_<n>.webp,
removes sheets/<clip>_<facing>.webp, and gives the frames.json entry "files" and "per" (frames
per band) in place of "file"; viewer.js draws each frame from its band. Run it after the
packer, on the same frames (<frames dir>/<clip>_<facing>/NNNN.png and render_info.json), then
copy frames.json into the page's #frames-data.
"""
import json
import math
import sys
from pathlib import Path

from PIL import Image

src, card = Path(sys.argv[1]), Path(sys.argv[2])
clips = sys.argv[3].split(",")
max_px = float(sys.argv[4]) * 1e6 if len(sys.argv) > 4 else 4e6
info = json.loads((src / "render_info.json").read_text())
fj = json.loads((card / "frames.json").read_text())
for clip in clips:
    entry = fj["clips"][clip]
    canvas = entry.get("canvas", fj["canvas"])
    assert info[clip]["canvas"][0] * canvas[1] == info[clip]["canvas"][1] * canvas[0], "frames and sheets differ in shape"
    for facing in ("sw", "se", "nw", "ne"):
        d = entry[facing]
        frames = sorted((src / f"{clip}_{facing}").glob("*.png"))
        assert len(frames) == d["frames"], f"{clip}_{facing}: {len(frames)} frames, frames.json has {d['frames']}"
        rows = max(1, int(max_px // (d["cols"] * d["w"] * d["h"])))
        per = rows * d["cols"]
        box = (d["x"], d["y"], d["x"] + d["w"], d["y"] + d["h"])
        files = []
        for b in range(math.ceil(len(frames) / per)):
            part = frames[b * per:(b + 1) * per]
            band = Image.new("RGBA", (d["cols"] * d["w"], math.ceil(len(part) / d["cols"]) * d["h"]), (0, 0, 0, 0))
            for i, p in enumerate(part):
                im = Image.open(p).convert("RGBA").resize(tuple(canvas), Image.LANCZOS)
                band.paste(im.crop(box), ((i % d["cols"]) * d["w"], (i // d["cols"]) * d["h"]))
            name = f"sheets/{clip}_{facing}_{b + 1}.webp"
            band.save(card / name, "WEBP", quality=80, method=4)
            files.append(name)
        (card / d.get("file", f"sheets/{clip}_{facing}.webp")).unlink(missing_ok=True)
        d.pop("file", None)
        entry[facing] = {"files": files, "per": per, **d}
        print("SPLIT", f"{clip}_{facing}", len(frames), "frames in", len(files), "bands of", per,
              f"({d['cols'] * d['w']} x {rows * d['h']} px)")
(card / "frames.json").write_text(json.dumps(fj, indent=1))
print("FRAMES_JSON", card / "frames.json")
