"""Copy the finished parts of each view into the imported prototype folder.

  python -I publish.py <prototype dir> [view ...]

art_src/ is ignored by Godot (.gdignore); art/<view>/ holds what the game
loads: the part PNGs (with .import files asking for mipmaps, so the 0.18x
battle scale stays clean), parts.json and a contact sheet of the parts.
"""
import json
import shutil
import sys
from pathlib import Path

IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="{res}"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def main():
    proto = Path(sys.argv[1]).resolve()
    views = sys.argv[2:] or ["se", "sw", "ne"]
    for view in views:
        src = proto / "art_src/parts" / view
        dst = proto / "art" / view
        dst.mkdir(parents=True, exist_ok=True)
        meta = json.loads((src / "parts.json").read_text(encoding="utf-8"))
        for p in meta["parts"]:
            name = p["name"] + ".png"
            shutil.copy2(src / name, dst / name)
            imp = dst / (name + ".import")
            res = "res://prototypes/footman_anim/art/%s/%s" % (view, name)
            if not imp.exists():
                imp.write_text(IMPORT.format(res=res), encoding="utf-8")
        keep = {"view": meta["view"], "size": meta["size"], "joints": meta["joints"],
                "parts": [{k: p[k] for k in ("name", "layer", "x", "y", "w", "h") if k in p} for p in meta["parts"]]}
        (dst / "parts.json").write_text(json.dumps(keep, indent=1), encoding="utf-8")
        print(view, len(meta["parts"]), "parts ->", dst)


main()
