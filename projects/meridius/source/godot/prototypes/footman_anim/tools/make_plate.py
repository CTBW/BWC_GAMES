"""Inpainting input for a view's hidden torso: the master on a flat ground with
the parts in front of the body removed (by ownership, so nothing else is cut).

  python -I make_plate.py <parts dir> <cut png> <out prefix> <part,part,...> [scale]

Writes <prefix>_in.png and <prefix>_mask.png (white = to be painted), scaled
up (default 2x) for the model.
"""
import json
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

parts_dir, cut_png, prefix, names = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4].split(",")
k = int(sys.argv[5]) if len(sys.argv) > 5 else 2
meta = json.load(open(parts_dir + "/parts.json"))
owner = np.array(Image.open(parts_dir + "/_owner.png"))
cut = np.array(Image.open(cut_png).convert("RGBA"))
h, w = owner.shape
ids = [meta["owner_index"].index(n) + 1 for n in names]
mask = np.isin(owner, ids)
mask = ndi.binary_dilation(mask, iterations=3)
bg = np.array([238, 236, 230], np.float32)
a = cut[..., 3:4] / 255.0
img = cut[..., :3] * a + bg * (1 - a)
img[mask] = bg
Image.fromarray(img.clip(0, 255).astype(np.uint8)).resize((w * k, h * k), Image.LANCZOS).save(prefix + "_in.png")
Image.fromarray((mask * 255).astype(np.uint8)).resize((w * k, h * k), Image.NEAREST).save(prefix + "_mask.png")
print(prefix, w * k, h * k, int(mask.sum()))
