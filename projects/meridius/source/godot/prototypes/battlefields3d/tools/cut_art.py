"""Cut the 3D battlefields' painted art out of its Higgsfield originals.

The originals stand on magenta and stay out of Git, in
local/workspace-originals (terrain kit 2 from 2026-10-20, and the
battlefields' own winter variants, ruins, town pieces, village props, reeds,
waterside and yard props and ground textures from 2026-10-25;
art_sources.json records their hashes). Props are keyed and
shadowed exactly as the game's woodland (tools/props/woodland_cutout.py) and
rocks (tools/props/rock_cutout.py), so they share the battle's light; the
ground textures are made tileable and written at the battle textures' 1024 px.

    python -I prototypes/battlefields3d/tools/cut_art.py [--review DIR] [--only NAME,...]

(--only cuts again just those single pieces, or "village" for the village
props sheet, or a SHEETS id, and keeps the rest of the manifest.)

(from the Godot project). Writes prototypes/battlefields3d/art/*.webp, the
manifest art/art.json (keys of entries in the sprites.json format, read by
scripts/bf_field.gd) and art/art_sources.json. Then run tools/import.sh.
"""

import argparse
import hashlib
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools", "props"))
import rock_cutout  # noqa: E402
import woodland_cutout as wc  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "..", "..", ".."))
KIT = os.path.join(ROOT, "local/workspace-originals/2026-10-20_meridius/terrain-kit-2/originals")
OWN = os.path.join(ROOT, "local/workspace-originals/2026-10-25_meridius/battlefields3d/originals")
OUT = os.path.join(HERE, "..", "art")
RES = "res://prototypes/battlefields3d/art/"

# Winter trees: edits of kit 2's trees that kept their place in the frame, so
# they keep woodland_cutout's anchors and heights.
TREES = {
    "w_spruce": ("winter_spruce.png", "spruce"),
    "w_scots_pine": ("winter_scots_pine.png", "scots_pine"),
    "w_fir_young": ("winter_fir_young.png", "fir_young"),
    "w_oak_bare": ("winter_oak_bare.png", "oak_young"),
    "w_birch_bare": ("winter_birch_bare.png", "birch"),
}
# Buildings and other single pieces: (folder, file, world width of the piece
# itself in px; a tile is 128 wide, a soldier 49 tall), the shadow's alpha.
# The anchor is the front of the piece's footprint (its lowest painted point),
# so the upright card stands at the front of the building.
PIECES = {
    "house_cottage_stone": ("kit", "house_stone_cottage__take-01.png", 225, 0.2),
    "house_longhouse": ("kit", "house_longhouse__take-01.png", 330, 0.2),
    "house_barn": ("kit", "house_barn__take-01.png", 330, 0.2),
    "house_chapel": ("kit", "house_chapel__take-01.png", 250, 0.2),
    "house_windmill": ("kit", "house_windmill__take-01.png", 260, 0.18),
    "house_townhouse": ("own", "house_townhouse.png", 250, 0.2),
    "house_inn": ("own", "house_inn.png", 270, 0.2),
    "watermill": ("own", "watermill.png", 290, 0.2),
    "market_stall": ("own", "market_stall.png", 150, 0.18),
    "wagon_wreck": ("own", "wagon_wreck.png", 170, 0.18),
    "bridge_stone": ("own", "bridge_stone.png", 480, 0.0),
    "reeds": ("own", "reeds.png", 92, 0.12),
    "ruin_chapel": ("kit", "ruin_chapel__take-01.png", 290, 0.2),
    "ruin_colonnade": ("kit", "ruin_colonnade__take-01.png", 300, 0.2),
    "ruin_stones": ("kit", "ruin_standing_stones__take-01.png", 270, 0.18),
    "ruin_wall_corner": ("kit", "ruin_wall_corner__take-01.png", 220, 0.18),
    "ruin_farmhouse": ("own", "ruin_farmhouse.png", 230, 0.2),
    "ruin_barn_burnt": ("own", "ruin_barn_burnt.png", 320, 0.18),
    "w_house_longhouse": ("own", "winter_longhouse.png", 330, 0.2),
    "w_house_cottage_stone": ("own", "winter_stone_cottage.png", 225, 0.2),
    "w_house_chapel": ("own", "winter_chapel.png", 250, 0.2),
    "w_ruin_stones": ("own", "winter_standing_stones.png", 270, 0.18),
}
# Clean-ups in fractions of a piece's painting, cropped to it, before its
# shadow: "clear" boxes (x0, y0, x1, y1) lose what they hold (the bridge's
# stream bed, tinged by the magenta under the arches); "fade" (cx, cy, rx, ry,
# from_y) rounds off the snowfield a winter house stands in, which the
# painting cut straight at its edges, below from_y (a squared ellipse, so the
# house's corners stay whole).
EDIT = {
    "bridge_stone": {"clear": [(0.375, 0.70, 0.536, 1.0), (0.536, 0.768, 0.623, 1.0), (0.623, 0.70, 0.84, 1.0)]},
    "w_house_longhouse": {"fade": (0.51, 0.737, 0.505, 0.263, 0.544)},
}
# A painting's angle against the battle's grid: the slopes (rise over run)
# of its footprint's left and right base edges from its front corner as
# painted, where the grid has 0.5 both ways (32 px down a tile for 64 across).
# square_up shears and stretches the painting upright to the grid, keeping its
# verticals vertical. Measured on the cut sprites against slope guides (the
# rowboat by its thwarts, left, and its keel, right), the chapels by lines
# fitted to their eave and ridge (0.57, the winter one's 0.58) and the summer
# gable's stone courses (0.50); the other pieces lie within about 0.03 of the
# grid, the sheets' trough and bench within 0.05. The chapels' bell tower is
# drawn nearly frontal, which no shear of the whole painting mends.
SLOPE = {"bridge_stone": (0.53, 0.39), "house_chapel": (0.50, 0.57), "w_house_chapel": (0.50, 0.58),
         "rowboat": (0.5, 0.39)}
# Paintings drawn with some perspective, whose edges slope differently at the
# foot, the eaves and the ridge, which no shear squares: (the front corner's x,
# and heights on its vertical with the slopes left and right measured there),
# in fractions of the cut painting. keystone moves each column up or down so
# that edges leaving the corner at any height take the grid's slope; between
# the measured heights the painted slope changes linearly, beyond them it
# holds. The townhouse and inn were read against slope guides; the others by
# lines fitted to traced edges (plinths, beams, log courses, lintels, eaves,
# and the ridge between the gables' tops). Their ridges run far flatter than
# their eaves (0.2 to 0.35), the roof sinking toward the back as if seen up
# close; squaring lifts its far end so that the ridge keeps its height.
KEYSTONE = {
    "house_townhouse": (0.497, [(0.096, 0.42, 0.42), (0.672, 0.44, 0.45), (0.905, 0.6, 0.6)]),
    "house_inn": (0.573, [(0.181, 0.40, 0.45), (0.622, 0.45, 0.48), (0.893, 0.55, 0.54)]),
    "house_longhouse": (0.631, [(0.248, 0.34, 0.5), (0.786, 0.5, 0.5), (1.0, 0.474, 0.5)]),
    "w_house_longhouse": (0.604, [(0.221, 0.345, 0.51), (0.703, 0.46, 0.51), (0.932, 0.465, 0.51)]),
    "w_house_cottage_stone": (0.489, [(0.121, 0.47, 0.303), (0.646, 0.47, 0.554), (0.881, 0.45, 0.53)]),
    "ruin_farmhouse": (0.489, [(0.148, 0.462, 0.234), (0.641, 0.462, 0.552)]),
    "house_barn": (0.389, [(0.114, 0.43, 0.207), (0.65, 0.43, 0.434), (0.86, 0.51, 0.45)]),
    "ruin_barn_burnt": (0.369, [(0.103, 0.452, 0.2), (0.59, 0.452, 0.212), (0.849, 0.527, 0.277)]),
}
# Anchors other than the front of the footprint, in fractions of the cut
# painting: the bridge's is the middle of its deck's near end on the bank, so
# bf_fields.gd lays the deck across the river from there.
# The winter cart and well stand in drifts wider than their base: their
# anchor is the front of their base, as the summer ones', not of the drift.
# The squared buildings keep the foot their painting had before squaring (the
# front of the ground they stand in): squaring a long side tips its end of the
# ground patch lower than the front, which would otherwise take the anchor.
ANCHOR = {"bridge_stone": (0.188, 0.632), "cart_hay_w": (0.5, 0.8), "well_snow_w": (0.5, 0.86),
          "house_chapel": (0.495, 0.992), "w_house_chapel": (0.493, 0.992), "house_longhouse": (0.663, 0.987),
          "w_house_longhouse": (0.51, 0.966), "w_house_cottage_stone": (0.47, 0.99),
          "ruin_farmhouse": (0.471, 0.99), "house_barn": (0.461, 0.986), "ruin_barn_burnt": (0.461, 0.986)}
# Chimney tops and windows (fractions of the painting) where the viewer puts
# smoke and the night's window light.
SMOKE = {
    "house_cottage_stone": [(0.66, 0.2)], "w_house_cottage_stone": [(0.62, 0.2)],
    "house_townhouse": [(0.669, 0.06)], "house_inn": [(0.728, 0.19)],
    "house_longhouse": [(0.43, 0.27)], "w_house_longhouse": [(0.44, 0.27)],
}
# The harvest sheet: two rows of three, read left to right (world widths).
HARVEST = ["stook", "stook", "sheaves", "pumpkins", "bale", "firewood"]
HARVEST_W = [52, 52, 66, 58, 54, 62]
# The village props sheet, two rows of three read left to right: (key, world
# width, anchor in fractions of the cut prop). The anchor is the front of the
# prop's base, or a fence's foot of its middle post: its end posts lie a tile
# apart (64 px across), so a panel a tile joins the next at a shared post.
VILLAGE = [("p_well", 118, (0.49, 0.88)), ("p_cart", 150, (0.55, 0.82)), ("p_crates", 128, (0.5, 0.86)),
           ("p_rick", 104, (0.5, 0.9)), ("p_fence_x", 88, (0.514, 0.663)), ("p_fence_y", 88, (0.511, 0.648))]
# Sheets of small props in varying sizes (2026-10-25, the battlefield's own
# camera as a reference), their pieces read in rows along their base lines,
# left to right: (key, sprite, world width), None for a piece left out. A key
# with several sprites draws one by the place's hash; "reeds" keeps the first
# reed painting (PIECES) among them. The world widths keep the kit's scale
# (about twice life size, like the well and the cart).
SHEETS = {
    "reedbeds": ("sheet_reeds_a.png", [
        ("reeds", "reeds_plume", 57), ("reeds", "reeds_bulrush", 48), ("reeds", "reeds_sparse", 60),
        ("reeds_small", "rush_tuft", 50), ("reeds", "reeds_bulrush_small", 40), ("reeds", "reeds_bed", 86),
        ("reeds_small", "rush_tuft_2", 48), ("iris", "iris", 52), ("reeds_small", "cattails", 20),
        ("reeds", "reeds_stones", 64)]),
    # The lily pads lie flat on the water: no standing card.
    "waterside": ("sheet_waterside.png", [
        None, ("driftwood", "driftwood", 100), ("river_stones", "river_stones", 56),
        ("marigolds", "marigolds", 38), ("horsetail", "horsetail", 30), ("mooring_post", "mooring_post", 46),
        ("rowboat", "rowboat", 120), ("fish_trap", "fish_trap", 70), ("reed_bundles", "reed_bundles", 40)]),
    # The milestone reads as a gravestone: left out.
    "yard": ("sheet_village.png", [
        ("signpost", "signpost", 52), ("trough", "trough", 110), ("chopping_block", "chopping_block", 70),
        ("sacks", "sacks", 60), ("wheelbarrow", "wheelbarrow", 80), ("scarecrow", "scarecrow", 78),
        ("milk_churns", "milk_churns", 34), ("barrels", "barrels", 76), ("beehives", "beehives", 92),
        ("shrine", "shrine", 44), None, ("lantern_post", "lantern_post", 52)]),
    # The yard's props painted anew in snow (a winter field draws a key's
    # "_w" sprites), two takes of each prompt. Barrels, crates, chopping
    # block and signpost: A standing barrel is as wide as the summer ones (29). Take 1's
    # signpost boards are off the grid, take 2's lie on it; its signpost is
    # given the summer one's height, the sheet painted it barely taller than a
    # barrel.
    "yard_winter": ("sheet_winter_yard_1.png", [
        ("barrels_w", "barrels_trio_w", 83), ("p_crates_w", "crates_barrels_w", 90),
        ("barrels_w", "barrel_single_w", 50), None, ("chopping_block_w", "chopping_block_axe_w", 75),
        ("barrels_w", "barrel_water_w", 53), ("barrels_w", "barrels_group_w", 72),
        ("barrels_w", "barrel_lying_w", 67)]),
    "yard_winter_2": ("sheet_winter_yard_2.png", [
        None, None, ("signpost_w", "signpost_snow_w", 50), None, None,
        ("chopping_block_w", "chopping_block_logs_w", 66), None, ("barrels_w", "barrels_pair_w", 57), None]),
    # The hay cart, the well, woodpiles and sledges. Take 2's cart faces the
    # other way from the summer one, take 1's well roof is off the grid. The
    # sheet drew the woodpiles and sledges at the cart's scale, far too big:
    # each has its own width.
    "yard_winter_3": ("sheet_winter_cart_1.png", [
        ("p_cart_w", "cart_hay_w", 150), None, ("harvest_firewood_w", "woodpile_w", 80),
        ("sledge_w", "sledge_logs_w", 64)]),
    "yard_winter_4": ("sheet_winter_cart_2.png", [
        None, ("p_well_w", "well_snow_w", 118), ("harvest_firewood_w", "woodpile_long_w", 92),
        ("sledge_w", "sledge_bound_w", 62)]),
    # Small stones and fallen wood on open snow, for a winter field's "stones"
    # and "deadwood": soft caps painted on, no shader snow along their edges.
    "stones_winter": ("sheet_winter_stones_1.png", [
        ("stones_w", "stones_snow_1", 50), ("stones_w", "stones_snow_2", 55), ("stones_w", "stones_snow_3", 52),
        ("stones_w", "stones_snow_4", 45), ("stones_w", "stones_snow_5", 40), ("stones_w", "stones_snow_6", 58),
        ("deadwood_w", "deadwood_snow_1", 80), ("deadwood_w", "deadwood_snow_2", 72),
        ("deadwood_w", "deadwood_snow_3", 60)]),
    "stones_winter_2": ("sheet_winter_stones_2.png", [
        ("stones_w", "stones_snow_7", 50), ("stones_w", "stones_snow_8", 55), ("stones_w", "stones_snow_9", 52),
        ("stones_w", "stones_snow_10", 45), ("stones_w", "stones_snow_11", 40), ("stones_w", "stones_snow_12", 58),
        ("deadwood_w", "deadwood_snow_4", 84), ("deadwood_w", "deadwood_snow_5", 72),
        ("deadwood_w", "deadwood_snow_6", 60)]),
}
SHEET_SHADOW = {"reeds": 0.12, "reeds_small": 0.12, "iris": 0.12, "marigolds": 0.12, "horsetail": 0.12}
# The winter trunks sheet keeps the summer sheet's layout (woodland_cutout.PIECES).
WOOD = {"stump": ["stump_old", "stump_sawn", "stump_rotten"], "log": ["log_fallen", "log_hollow", "log_mossy", "log_stack"]}
GROUND = {"snow": "ground_snow.png", "snow_road": "ground_snow_road.png", "ice": "ground_ice.png",
          "autumn": "ground_autumn_meadow.png"}
GROUND_PX = 1024


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def main_parts(a):
    """Only the pieces that matter: specks away from the subject (a stray
    dab on the backdrop) are dropped; a part keeps if it holds 2% of the
    largest part's area."""
    step = 4
    m = a[::step, ::step] > 0.1
    h, w = m.shape
    label = np.full((h, w), -1, dtype=np.int32)
    sizes = []
    for sy, sx in zip(*np.nonzero(m)):
        if label[sy, sx] >= 0:
            continue
        n = len(sizes)
        stack = [(sy, sx)]
        label[sy, sx] = n
        count = 0
        while stack:
            y, x = stack.pop()
            count += 1
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and label[ny, nx] < 0:
                    label[ny, nx] = n
                    stack.append((ny, nx))
        sizes.append(count)
    keep = np.array([s >= 0.02 * max(sizes) for s in sizes] + [False])
    full = np.repeat(np.repeat(label, step, axis=0), step, axis=1)[:a.shape[0], :a.shape[1]]
    # Pixels next to a kept part (soft edges below the threshold) stay too.
    near = Image.fromarray((keep[full] * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(2 * step + 1))
    return np.where(np.asarray(near) > 0, a, 0.0)


def edit(img, spec):
    a = np.asarray(img, dtype=np.float32).copy()
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    fx, fy = xx / w, yy / h
    for x0, y0, x1, y1 in spec.get("clear", []):
        a[(fx >= x0) & (fx < x1) & (fy >= y0) & (fy < y1)] = 0
    if "fade" in spec:
        cx, cy, rx, ry, from_y = spec["fade"]
        d = (((fx - cx) / rx) ** 4 + ((fy - cy) / ry) ** 4) ** 0.25
        k = np.clip((d - 0.85) / 0.15, 0, 1)
        k = 1 - k * k * (3 - 2 * k)
        a[..., 3] *= np.where(fy > from_y, k, 1.0)
    return Image.fromarray(a.round().astype(np.uint8), "RGBA")


def square_up(img, slopes):
    """The painting sheared and stretched upright (x stays) so its base edges
    take the grid's slope, and the map of its points into the result."""
    sl, sr = slopes
    d = 1.0 / (sl + sr)
    c = (sr - sl) / (2.0 * (sl + sr))
    w, h = img.size
    ys = [c * x + d * y for x in (0, w) for y in (0, h)]
    t = -min(ys)
    out = img.convert("RGBa").transform((w, int(np.ceil(max(ys) + t))), Image.AFFINE,
                                        (1, 0, 0, -c / d, 1 / d, -t / d), resample=Image.BICUBIC)
    return out.convert("RGBA"), lambda x, y: (x, c * x + d * y + t)


def keystone(img, spec):
    """The painting with each column moved up or down (x stays) so that its
    edges leave the front corner at the grid's slope at every height
    (KEYSTONE), and the map of its points into the result."""
    w, h = img.size
    cx = spec[0] * w
    levels = sorted(spec[1])
    vs = np.array([f * h for f, _, _ in levels])
    left = np.array([sl for _, sl, _ in levels])
    right = np.array([sr for _, _, sr in levels])

    def slope(v0, u):
        return np.where(u < 0, np.interp(v0, vs, left), np.interp(v0, vs, right))

    src = np.asarray(img.convert("RGBA"), dtype=np.float32)
    src[..., :3] *= src[..., 3:] / 255.0
    pad = int(np.ceil(0.25 * w))
    yy, xx = np.mgrid[0:h + 2 * pad, 0:w].astype(np.float32)
    u = xx + 0.5 - cx
    v0 = yy - pad + 0.5 * np.abs(u)
    sy = v0 - slope(v0, u) * np.abs(u)
    y0 = np.floor(sy).astype(int)
    t = (sy - y0)[..., None]
    xi = xx.astype(int)

    def row(y):
        return np.where(((y >= 0) & (y < h))[..., None], src[np.clip(y, 0, h - 1), xi], 0.0)

    out = row(y0) * (1.0 - t) + row(y0 + 1) * t
    rows = np.nonzero(out[..., 3].max(axis=1) > 0.5)[0]
    top, bottom = rows.min(), rows.max() + 1
    out = out[top:bottom]
    out[..., :3] = np.where(out[..., 3:] > 0, out[..., :3] * 255.0 / np.maximum(out[..., 3:], 1e-6), 0.0)

    def move(x, y):
        u = x - cx
        v0 = y
        for _ in range(40):
            v0 = y + float(slope(v0, u)) * abs(u)
        return x, v0 - 0.5 * abs(u) + pad - top

    return Image.fromarray(out.round().clip(0, 255).astype(np.uint8), "RGBA"), move


def cut_piece(path, world_w, shadow, spec=None, slopes=None, anchor=None, keys=None):
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
    fg, a = rock_cutout.key(rgb)
    a = main_parts(wc.no_cast_shadow(rgb, a))
    ys, xs = np.nonzero(a > 0.5)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    img = Image.fromarray(np.dstack([fg, a * 255.0])[y0:y1, x0:x1].round().astype(np.uint8), "RGBA")
    canvas, ax, ay, at = shape(img, world_w, shadow, spec, slopes, anchor, keys)

    def place(fx, fy):
        """A point of the painting (fractions) in the sprite's pixels."""
        return at(fx * rgb.shape[1] - x0, fy * rgb.shape[0] - y0)

    return canvas, ax, ay, place


def shape(img, world_w, shadow, spec=None, slopes=None, anchor=None, keys=None):
    """A cut-out painting at its world width, edited and squared to the grid,
    over its shadow; its anchor, and the map of its pixels into the sprite."""
    k = wc.DENSITY * world_w / img.width
    img = rock_cutout.premul_resize(img, (round(img.width * k), max(1, round(img.height * k))))
    if spec:
        img = edit(img, spec)
    w0, h0 = img.size
    move = lambda x, y: (x, y)  # noqa: E731
    if slopes:
        img, move = square_up(img, slopes)
    if keys:
        img, move = keystone(img, keys)
    w, h = img.size
    if anchor:
        rx, ry = move(anchor[0] * w0, anchor[1] * h0)
    else:
        # The foot of the paint, not of the canvas: a shear leaves clear
        # corners below it.
        al = np.asarray(img.getchannel("A"), dtype=np.float32) / 255.0
        bottom = int(np.nonzero(al.max(axis=1) > 0.5)[0].max()) + 1
        rows = al[max(0, bottom - round(h * 0.1)):bottom]
        rx = float((rows.sum(axis=0) * np.arange(w)).sum() / max(rows.sum(), 1e-6))
        ry = bottom - 0.01 * w
    canvas, ax, ay = wc.skewed_shadow(img, rx, ry, shadow)

    def at(x, y):
        px, py = move(x * k, y * k)
        return [round(px + ax - rx, 1), round(py + ay - ry, 1)]

    return canvas, round(ax, 1), round(ay, 1), at


def cut_cells(path, cols, rows, widths):
    """A sheet of small upright props, one a cell, each over the trees' shadow."""
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
    fg, a = rock_cutout.key(rgb)
    a = wc.no_cast_shadow(rgb, a)
    own = rock_cutout.owners(a, cols, rows)
    out = []
    for cell, width in enumerate(widths):
        ca = np.where(own == cell, a, 0.0)
        ys, xs = np.nonzero(ca > 0.5)
        img = Image.fromarray(np.dstack([fg, ca * 255.0])[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
                              .round().astype(np.uint8), "RGBA")
        out.append(wc.cut_piece(img, width, "upright"))
    return out


def soften(arr, r):
    """A float array blurred over r pixels along both axes (three box passes,
    close to a Gaussian)."""
    out = arr.astype(np.float32)
    for axis in (0, 1):
        for _ in range(3):
            pad = [(0, 0)] * out.ndim
            pad[axis] = (r + 1, r)
            c = np.cumsum(np.pad(out, pad, mode="edge"), axis=axis)
            n = out.shape[axis]
            out = (np.take(c, range(2 * r + 1, 2 * r + 1 + n), axis=axis) - np.take(c, range(0, n), axis=axis)) / (2 * r + 1)
    return out


def despill(fg, a):
    """The soft edge over magenta keeps a pink cast, and the painting's own
    edge often has one: where the paint thins out or turns pink (red and
    blue above green), its colour comes from the solid paint nearby."""
    pink = np.clip((np.minimum(fg[..., 0], fg[..., 2]) - fg[..., 1] + 6.0) / 24.0, 0, 1)
    solid = ((a > 0.9) & (pink == 0)).astype(np.float32)
    w = soften(solid, 6)
    near = soften(fg * solid[..., None], 6) / np.maximum(w, 1e-4)[..., None]
    t = (np.clip((a - 0.5) / 0.4, 0, 1) * (1 - pink))[..., None]
    return np.where(w[..., None] > 1e-3, near * (1 - t) + fg * t, fg)


def cut_village(path):
    """The village props, each over the trees' shadow: {key: (sprite, ax, ay)}."""
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
    fg, a = rock_cutout.key(rgb)
    fg = despill(fg, a)
    a = wc.no_cast_shadow(rgb, a)
    own = rock_cutout.owners(a, 3, 2)
    out = {}
    for cell, (name, width, (fx, fy)) in enumerate(VILLAGE):
        ca = np.where(own == cell, a, 0.0)
        ys, xs = np.nonzero(ca > 0.5)
        img = Image.fromarray(np.dstack([fg, ca * 255.0])[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
                              .round().astype(np.uint8), "RGBA")
        k = wc.DENSITY * width / img.width
        img = rock_cutout.premul_resize(img, (round(img.width * k), max(1, round(img.height * k))))
        shadow = 0.12 if name.startswith("p_fence") else wc.SHADOW["upright"]
        canvas, ax, ay = wc.skewed_shadow(img, fx * img.width, fy * img.height, shadow)
        out[name] = (canvas, round(ax, 1), round(ay, 1))
    return out


def sheet_pieces(a, step=4):
    """A sheet's pieces as masks of its pixels, read in rows along their base
    lines and left to right. The pieces stand apart on a free layout: each is
    what is connected (at a quarter of the resolution, bridged over a pixel's
    gap), less specks under 3% of the largest."""
    m = Image.fromarray(((a[::step, ::step] > 0.5) * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))
    m = np.asarray(m) > 0
    h, w = m.shape
    label = np.full((h, w), -1, dtype=np.int32)
    found = []
    for sy, sx in zip(*np.nonzero(m)):
        if label[sy, sx] >= 0:
            continue
        n = len(found)
        stack, pts = [(sy, sx)], []
        label[sy, sx] = n
        while stack:
            y, x = stack.pop()
            pts.append((y, x))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and label[ny, nx] < 0:
                    label[ny, nx] = n
                    stack.append((ny, nx))
        p = np.array(pts)
        found.append((len(pts), p[:, 0].max(), p[:, 1].min(), n))
    big = max(f[0] for f in found)
    found = sorted((f for f in found if f[0] >= 0.03 * big), key=lambda f: f[1])
    rows, row = [], []
    for f in found:
        if row and (f[1] - row[0][1]) * step > 0.12 * a.shape[0]:
            rows.append(row)
            row = []
        row.append(f)
    rows.append(row)
    full = np.repeat(np.repeat(label, step, axis=0), step, axis=1)[:a.shape[0], :a.shape[1]]
    return [full == f[3] for r in rows for f in sorted(r, key=lambda f: f[2])]


def cut_sheet(path, items):
    """A sheet's props (SHEETS), each over the trees' shadow: [(key, sprite,
    image, ax, ay)]."""
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
    fg, a = rock_cutout.key(rgb)
    fg = despill(fg, a)
    a = wc.no_cast_shadow(rgb, a)
    masks = sheet_pieces(a)
    if len(masks) != len(items):
        raise SystemExit("%s: %d pieces for %d items" % (os.path.basename(path), len(masks), len(items)))
    out = []
    for mask, item in zip(masks, items):
        if item is None:
            continue
        key, name, width = item
        ca = np.where(mask, a, 0.0)
        ys, xs = np.nonzero(ca > 0.5)
        img = Image.fromarray(np.dstack([fg, ca * 255.0])[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
                              .round().astype(np.uint8), "RGBA")
        img, ax, ay, _ = shape(img, width, SHEET_SHADOW.get(key, wc.SHADOW["upright"]), slopes=SLOPE.get(name),
                               anchor=ANCHOR.get(name))
        out.append((key, name, img, ax, ay))
    return out


def owners_by_gaps(a, cols, rows):
    """Each pixel's cell from where it lies, the cells split at the emptiest
    rows and columns near the even split: the winter rocks' snow drifts touch,
    so their pieces cannot be told apart by connection."""
    def cuts(profile, n):
        size = len(profile)
        out = [0]
        for i in range(1, n):
            lo, hi = int(size * (i - 0.3) / n), int(size * (i + 0.3) / n)
            out.append(lo + int(np.argmin(profile[lo:hi])))
        return out + [size]
    rs = cuts((a > 0.5).sum(axis=1), rows)
    own = np.full(a.shape, -1, dtype=np.int32)
    for r in range(rows):
        band = a[rs[r]:rs[r + 1]]
        cs = cuts((band > 0.5).sum(axis=0), cols)
        for c in range(cols):
            own[rs[r]:rs[r + 1], cs[c]:cs[c + 1]] = r * cols + c
    return own


def tileable(img):
    """Seamless: the picture crossfaded with itself moved by half, whose
    edges are the original's middle, in a mask that keeps the original at
    the centre and the moved copy at the edges."""
    a = np.asarray(img.convert("RGB"), dtype=np.float32)
    h, w = a.shape[:2]
    b = np.roll(np.roll(a, h // 2, axis=0), w // 2, axis=1)
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.minimum(np.minimum(xx, w - 1 - xx) / w, np.minimum(yy, h - 1 - yy) / h)
    m = np.clip(d / 0.22, 0, 1)
    m = m * m * (3 - 2 * m)
    return Image.fromarray((a * m[..., None] + b * (1 - m[..., None])).round().astype(np.uint8), "RGB")


def entry(name, img, ax, ay, size, extra=None):
    e = {"file": RES + name + ".webp", "ax": ax, "ay": ay, "scale": round(size / wc.DENSITY, 4),
         "w": img.width, "h": img.height, "noShadow": True, "art": True}
    if extra:
        e.update(extra)
    return e


def save(img, name):
    img.save(os.path.join(OUT, name + ".webp"), "WEBP", quality=92, alpha_quality=100, method=6)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--review")
    ap.add_argument("--only")
    args = ap.parse_args()
    if args.only:
        return recut(args.only.split(","))
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.join(OUT, "ground"), exist_ok=True)
    roots = {"kit": KIT, "own": OWN}
    manifest, sources, boards = {}, {}, []

    for name, (file, like) in TREES.items():
        path = os.path.join(OWN, file)
        _, _, anchor, world_h = wc.SOURCES[like]
        img, ax, ay = wc.cut(path, anchor, world_h, wc.SHADOW["tree"])
        save(img, name)
        manifest[name] = [entry(name, img, ax, ay, 1.0)]
        sources[name] = {"file": file, "sha256": sha(path), "anchor": list(anchor), "worldHeight": world_h}
        boards.append(img)

    for name, (root, file, width, shadow) in PIECES.items():
        path = os.path.join(roots[root], file)
        img, ax, ay, place = cut_piece(path, width, shadow, EDIT.get(name), SLOPE.get(name), ANCHOR.get(name),
                                       KEYSTONE.get(name))
        extra = {}
        if name in SMOKE:
            extra["smoke"] = [place(fx, fy) for fx, fy in SMOKE[name]]
        save(img, name)
        manifest[name] = [entry(name, img, ax, ay, 1.0, extra)]
        sources[name] = {"file": file, "folder": root, "sha256": sha(path), "worldWidth": width}
        boards.append(img)

    path = os.path.join(OWN, "harvest_sheet.png")
    for i, (img, ax, ay) in enumerate(cut_cells(path, 3, 2, HARVEST_W)):
        name = "harvest_%d" % i
        save(img, name)
        manifest.setdefault("harvest_" + HARVEST[i], []).append(entry(name, img, ax, ay, 1.0))
        boards.append(img)
    sources["harvest"] = {"file": "harvest_sheet.png", "sha256": sha(path), "cells": HARVEST, "worldWidth": HARVEST_W}

    boards += village(manifest, sources)
    boards += sheets(manifest, sources)

    path = os.path.join(OWN, "winter_rocks_sheet.png")
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
    fg, a = rock_cutout.key(rgb)
    own = owners_by_gaps(a, 4, 2)
    for row, key in enumerate(["w_rock_small", "w_rock_large"]):
        manifest[key] = []
        for col in range(4):
            img, ax, ay = rock_cutout.cut(fg, a, own, row * 4 + col, rock_cutout.WIDTH[key[2:]])
            name = "%s_%d" % (key, col)
            save(img, name)
            manifest[key].append({"file": RES + name + ".webp", "ax": ax, "ay": ay, "scale": rock_cutout.SCALE,
                                  "w": img.width, "h": img.height, "noShadow": True, "art": True})
            boards.append(img)
    sources["w_rocks"] = {"file": "winter_rocks_sheet.png", "sha256": sha(path), "cells": "as rock_cutout"}

    path = os.path.join(OWN, "winter_trunks_sheet.png")
    cuts = {}
    for name, img in wc.pieces(path).items():
        box, width, kind = wc.PIECES[name]
        cuts[name] = wc.cut_piece(img, width, kind)
    for key, names in WOOD.items():
        manifest["w_" + key] = []
        for n in names:
            img, ax, ay = cuts[n]
            save(img, "w_" + n)
            manifest["w_" + key].append(entry("w_" + n, img, ax, ay, 1.0))
            boards.append(img)
    sources["w_wood"] = {"file": "winter_trunks_sheet.png", "sha256": sha(path), "pieces": "as woodland_cutout"}

    for name, file in GROUND.items():
        path = os.path.join(OWN, file)
        img = tileable(Image.open(path)).resize((GROUND_PX, GROUND_PX), Image.LANCZOS)
        img.save(os.path.join(OUT, "ground", name + ".webp"), "WEBP", quality=90, method=6)
        sources["ground_" + name] = {"file": file, "sha256": sha(path)}

    with open(os.path.join(OUT, "art.json"), "w", newline="\n") as f:
        json.dump(manifest, f, indent=1)
    with open(os.path.join(OUT, "art_sources.json"), "w", newline="\n") as f:
        json.dump(sources, f, indent=1)
    if args.review:
        os.makedirs(args.review, exist_ok=True)
        imgs = [b.resize((max(1, b.width // 3), max(1, b.height // 3)), Image.LANCZOS) for b in boards]
        rows, row, x = [], [], 0
        for i in imgs:
            if x + i.width > 2400 and row:
                rows.append(row)
                row, x = [], 0
            row.append(i)
            x += i.width + 16
        rows.append(row)
        th = sum(max(i.height for i in r) + 24 for r in rows) + 24
        board = Image.new("RGBA", (2440, th), (92, 120, 52, 255))
        y = 24
        for r in rows:
            rh = max(i.height for i in r)
            x = 16
            for i in r:
                board.alpha_composite(i, (x, y + rh - i.height))
                x += i.width + 16
            y += rh + 24
        board.convert("RGB").save(os.path.join(args.review, "battlefields3d_art.jpg"), quality=88)
    print(json.dumps({k: len(v) for k, v in manifest.items()}))


def village(manifest, sources):
    path = os.path.join(OWN, "village_props.png")
    imgs = []
    for name, (img, ax, ay) in cut_village(path).items():
        save(img, name)
        manifest[name] = [entry(name, img, ax, ay, 1.0)]
        imgs.append(img)
    sources["village"] = {"file": "village_props.png", "sha256": sha(path), "cells": [v[0] for v in VILLAGE],
                          "worldWidth": [v[1] for v in VILLAGE]}
    return imgs


def sheets(manifest, sources, ids=SHEETS):
    """The SHEETS' props into the manifest, after any of their key's sprites
    that are no sheet's (the first reeds painting)."""
    imgs = []
    for sid in ids:
        file, items = SHEETS[sid]
        path = os.path.join(OWN, file)
        mine = {RES + it[1] + ".webp" for it in items if it}
        for key in {it[0] for it in items if it}:
            manifest[key] = [e for e in manifest.get(key, []) if e["file"] not in mine]
        for key, name, img, ax, ay in cut_sheet(path, items):
            save(img, name)
            # A winter sheet's props are painted in snow: no snow cap on top.
            manifest[key].append(entry(name, img, ax, ay, 1.0, {"snowy": True} if key.endswith("_w") else None))
            imgs.append(img)
        sources["sheet_" + sid] = {"file": file, "sha256": sha(path),
                                   "pieces": [list(it) if it else None for it in items]}
    return imgs


def recut(names):
    roots = {"kit": KIT, "own": OWN}
    with open(os.path.join(OUT, "art.json")) as f:
        manifest = json.load(f)
    for name in names:
        if name == "village" or name in SHEETS:
            with open(os.path.join(OUT, "art_sources.json")) as f:
                sources = json.load(f)
            if name == "village":
                village(manifest, sources)
            else:
                sheets(manifest, sources, [name])
            with open(os.path.join(OUT, "art_sources.json"), "w", newline="\n") as f:
                json.dump(sources, f, indent=1)
            continue
        root, file, width, shadow = PIECES[name]
        path = os.path.join(roots[root], file)
        img, ax, ay, place = cut_piece(path, width, shadow, EDIT.get(name), SLOPE.get(name), ANCHOR.get(name),
                                       KEYSTONE.get(name))
        extra = {"smoke": [place(fx, fy) for fx, fy in SMOKE[name]]} if name in SMOKE else {}
        save(img, name)
        # A sheet's sprites under the same key (the reeds) stay.
        manifest[name] = [entry(name, img, ax, ay, 1.0, extra)] + manifest.get(name, [])[1:]
        with open(os.path.join(OUT, "art_sources.json")) as f:
            sources = json.load(f)
        sources[name] = {"file": file, "folder": root, "sha256": sha(path), "worldWidth": width}
        with open(os.path.join(OUT, "art_sources.json"), "w", newline="\n") as f:
            json.dump(sources, f, indent=1)
    with open(os.path.join(OUT, "art.json"), "w", newline="\n") as f:
        json.dump(manifest, f, indent=1)
    print("recut", names)


if __name__ == "__main__":
    main()
