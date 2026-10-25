"""Painted ability icons: magenta-keyed paintings -> small cut-outs for the game.

Reads the painted icons ("<Ability> - Icon.png", 2048 px pixel art on a
magenta chroma-key ground) from a source folder, by default the repository's
local/ability-icons/ (local only, see local/README.md), and writes
assets/icons/painted/<icon>.png, named after the ability's `icon` in the data
(scripts/ui/widgets/icon.gd uses them in place of the SVG of the same name).

Per icon:
  1. Crop the painting's own frame where it has one (Shield Bash).
  2. Estimate the ground row by row from the outer columns, so a ground that
     shades from top to bottom (Growl's pink haze) or is darker (Square) keys
     as cleanly as the plain magenta.
  3. Key by colour difference: magenta is min(R, B) - G, a foreground of any
     other hue has none of it, so alpha = 1 - key(pixel) / key(ground) holds
     for antialiased edges and soft shadows alike. Unmix the ground out of
     the edge pixels (premultiplied colour = pixel - (1 - alpha) * ground).
     Soft shading painted as a tint of the ground (TINT) gets one colour.
  4. Crop to the painted shape, centre it on a square with a small margin and
     downscale (area average, premultiplied) to SIZE.

  python -I tools/ui_key_icons.py [--src DIR] [icons...]   (from the project root)
  --preview  also writes tests/visual/out/painted_keyed.png (every icon on
             parchment, dark and light checks)
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# The repository root is four levels above the project (projects/meridius/source/godot).
SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(ROOT)))), "local", "ability-icons")
OUT = os.path.join(ROOT, "assets", "icons", "painted")
PREVIEW = os.path.join(ROOT, "tests", "visual", "out")
SIZE = 128
MARGIN = 0.04
# Painting -> icon name (the `icon` of the ability in the data). Lob Rock is the
# same painting as Hurl Stone. Howl has no painting yet and keeps its SVG.
FILES = {
	"Aimed Shot": "aimed_shot", "Bloodlust": "blood", "Brutal Charge": "charge",
	"Chain Lightning": "lightning", "Charge (Footmen)": "shield_charge",
	"Charge (Royal Guard)": "hound_charge", "Defend": "defend", "Fireball": "fire",
	"Frost Blast": "frost", "Growl": "growl", "Gutripper": "gut", "Healing Light": "heal",
	"Heavy Bolt": "bolt", "Hurl Stone": "stone", "Lick Wounds": "lick_wounds",
	"Mending Circle": "circle", "Overwatch": "eye", "Pike Thrust": "thrust",
	"Shield Bash": "bash", "Shield Wall": "shield", "Spearwall": "spearwall",
	"Square": "square", "War Cry": "horn",
}
# Pixels cut from each side before keying (the painting's frame).
FRAME = {"bash": 60}
# Soft shading painted as tints of the magenta unmixes to maroon or pink: give
# the see-through and still-magenta pixels of these icons one colour instead (the stone's ground
# shadow, the fireball's glow).
TINT = {"stone": (24, 16, 10), "fire": (255, 140, 50)}
# Also the solid pixels of a red-to-magenta hue (the stone's shadow is painted
# in maroon; the grey and moss of the stone have no such hue).
REDS = {"stone"}
# Keying thresholds on 1 - key/ground: the ground's noise stays clear below LO,
# anything above HI is solid.
LO, HI = 0.12, 0.85


def _key(c):
	return np.minimum(c[..., 0], c[..., 2]) - c[..., 1]


def _ground_rows(c):
	"""The ground colour per row (h, 3), from the outer 6% of columns."""
	h, w, _ = c.shape
	side = max(8, w * 6 // 100)
	strip = np.concatenate([c[:, :side], c[:, w - side:]], axis=1)
	k = _key(strip)
	edge = np.concatenate([strip[:side].reshape(-1, 3), strip[-side:].reshape(-1, 3), strip.reshape(-1, 3)])
	kg = float(np.median(_key(edge)))
	rows = np.full((h, 3), np.nan, np.float32)
	for y in range(h):
		sel = strip[y][k[y] > 0.35 * kg]
		if len(sel) >= 8:
			rows[y] = np.median(sel, axis=0)
	ok = ~np.isnan(rows[:, 0])
	if not ok.any():
		raise ValueError("no magenta ground found")
	ys = np.arange(h)
	for ch in range(3):
		rows[:, ch] = np.interp(ys, ys[ok], rows[ok, ch])
	# Smooth the profile (a running mean over 41 rows) against art at the sides.
	pad = np.pad(rows, ((20, 20), (0, 0)), mode="edge")
	cs = np.cumsum(np.vstack([np.zeros((1, 3), np.float32), pad]), axis=0)
	return (cs[41:] - cs[:-41]) / 41.0


def key_icon(img, tint=None, reds=False):
	"""RGBA float (premultiplied colour, alpha) of a magenta-keyed painting."""
	c = np.asarray(img.convert("RGB")).astype(np.float32)
	g = _ground_rows(c)[:, None, :]
	kg = np.maximum(_key(g), 1.0)
	raw = 1.0 - _key(c) / kg
	a = np.clip((raw - LO) / (HI - LO), 0.0, 1.0)[..., None]
	pm = np.clip(c - (1.0 - a) * g, 0.0, None)
	pm = np.minimum(pm, a * 255.0)
	if tint is not None:
		# See-through, or solid but still magenta (the shadow's darkest wave).
		soft = (a < 0.98) | (_key(c)[..., None] > 15.0)
		if reds:
			r, gr, b = c[..., 0], c[..., 1], c[..., 2]
			soft |= ((r - gr > 25) & (b - gr > -8))[..., None]
		pm = np.where(soft, np.asarray(tint, np.float32) * a, pm)
	return np.concatenate([pm, a * 255.0], axis=2)


def _resize(rgba, size):
	chans = [Image.fromarray(rgba[..., i].astype(np.float32), "F").resize((size, size), Image.BOX) for i in range(4)]
	return np.stack([np.asarray(ch) for ch in chans], axis=2)


def fit(rgba, size=SIZE):
	"""Crop to the painted shape, centre on a square and downscale; 8-bit RGBA."""
	a = rgba[..., 3]
	# The shape's box from a coarse alpha, so stray specks don't widen it.
	s = 16
	h, w = a.shape
	coarse = a[: h // s * s, : w // s * s].reshape(h // s, s, w // s, s).mean(axis=(1, 3))
	ys, xs = np.nonzero(coarse > 0.2 * 255)
	y0, y1, x0, x1 = ys.min() * s, (ys.max() + 1) * s, xs.min() * s, (xs.max() + 1) * s
	side = int(max(y1 - y0, x1 - x0) * (1 + 2 * MARGIN))
	sq = np.zeros((side, side, 4), np.float32)
	oy, ox = (side - (y1 - y0)) // 2, (side - (x1 - x0)) // 2
	sq[oy:oy + y1 - y0, ox:ox + x1 - x0] = rgba[y0:y1, x0:x1]
	small = _resize(sq, size)
	al = small[..., 3:4]
	col = np.where(al > 0.5, small[..., :3] * 255.0 / np.maximum(al, 1e-3), 0.0)
	out = np.concatenate([col, al], axis=2)
	return Image.fromarray(np.clip(np.rint(out), 0, 255).astype(np.uint8), "RGBA")


def preview(icons, path):
	"""Every icon on parchment, a dark panel and a light check, 2x."""
	cell = SIZE + 16
	grounds = [(233, 219, 186), (32, 24, 16), (200, 200, 200)]
	sheet = Image.new("RGB", (cell * len(icons), cell * len(grounds)))
	for r, gcol in enumerate(grounds):
		for i, ic in enumerate(icons):
			tile = Image.new("RGB", (cell, cell), gcol)
			tile.paste(ic, (8, 8), ic)
			sheet.paste(tile, (i * cell, r * cell))
	sheet.save(path)


def main(argv):
	src = SRC
	want = []
	show = False
	it = iter(argv)
	for arg in it:
		if arg == "--src":
			src = next(it)
		elif arg == "--preview":
			show = True
		else:
			want.append(arg)
	os.makedirs(OUT, exist_ok=True)
	done = []
	for stem, name in FILES.items():
		if want and name not in want:
			continue
		p = os.path.join(src, stem + " - Icon.png")
		if not os.path.exists(p):
			print("missing", p)
			continue
		img = Image.open(p)
		cut = FRAME.get(name, 0)
		if cut:
			img = img.crop((cut, cut, img.width - cut, img.height - cut))
		ic = fit(key_icon(img, TINT.get(name), name in REDS))
		ic.save(os.path.join(OUT, name + ".png"), optimize=True)
		done.append(ic)
		print("wrote", name)
	if show and done:
		os.makedirs(PREVIEW, exist_ok=True)
		preview(done, os.path.join(PREVIEW, "painted_keyed.png"))


if __name__ == "__main__":
	main(sys.argv[1:])
