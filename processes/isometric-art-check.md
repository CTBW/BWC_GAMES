# Isometric art check

Use this before a generated building, prop or plant goes onto a Meridius
battlefield, and when the owner reports that an object and the battlefield
"don't line up". Set out by the owner on 25 October 2026 for the 3D
battlefields; it applies to any isometric object in the game.

## The grid

The battle view projects a tile 64 px across and 32 px down. An edge that runs
along the grid (a wall's foot, an eave, a roof ridge, a plank, a road's edge)
rises 1 px for every 2 px across: slope 0.5. Verticals stay vertical. Circles
on the ground are ellipses twice as wide as they are deep. A painting with
some perspective has edges at 0.4 or 0.6 instead, and on the field it looks
turned against the tiles, the roads and the edge of the fog.

## Ask for the right camera

Attach a screenshot of the battlefield the object will stand on as the camera
reference, uploaded through the Higgsfield route, and name its role: "use ONLY
for the camera angle, for how big objects are against the ground, and for the
2:1 isometric ground grid; do not copy its objects, layout, fog or
interface". Spell out the camera: a true isometric game projection with no
perspective and no vanishing points; ground foreshortened exactly 2:1;
straight horizontal edges along only two directions, rising 1 px for every
2 px across; every vertical perfectly vertical; the nearest corner straight
down. Ask for an irregular ground patch no wider than the object's base, never
a plinth or a round coin-shaped base. The full wording is in the batch E
prompts of the 3D battlefields prototype (25 October 2026).

## Measure

Run `projects/meridius/source/godot/tools/props/iso_check.py` on the original:

```text
python -I tools/props/iso_check.py PAINTING OUT.jpg x0,y0,x1,y1 cx,cy [cx,cy ...]
```

It draws guides at slopes 0.4, 0.5 and 0.6 left and right from each corner
point. Put corners at the front corner of the footprint, of the eaves and of
the ridge, and read each edge's slope at those heights. Within about 0.03 of
0.5 is fine. Also note where the object's foot is: the front of its footprint,
or something else (a bridge's deck meets the bank).

Reject a piece that reads as something else at game size (a milestone that
looks like a gravestone, a house that looks broken), whatever its angles.

## Fix

The cutter is `prototypes/battlefields3d/tools/cut_art.py`:

- `SLOPE` (sheared square): use it when the error is the same at every height,
  for example a boat at 0.39 along the keel, or a barn at 0.47 and 0.45. Give
  the measured slopes on the left and right.
- `KEYSTONE` (columns moved up or down): use it when the slope changes with
  height (perspective), for example a townhouse at 0.42 at the foot and 0.6 at
  the ridge. Give the front corner's x, then the heights with the slopes
  measured there.
- `ANCHOR`, or the card's `stand` flag: use them when the foot is not the
  front of the footprint. A bridge's anchor is its deck's near end, and its
  piers stand down into the river.

Without an `ANCHOR`, the anchor is the lowest point of the paint, not of the
canvas, because a shear leaves clear corners below the paint. Re-cut only the
pieces you changed (`--only name,...`). Then run `tools/import.sh`.

## Verify

1. Run `iso_check.py` again on the cut WebP. Every edge should follow the red
   guide.
2. Lay the sprites over one-tile diamonds at their anchors. Check the size
   against the tile and against the props already on the field.
3. Take a `--clean` capture of the field in a real window and look at it next
   to the roads, the tile rows and the fog edge. Check the draw order too:
   anything nearer the camera (larger x + y) must cover what stands behind it,
   tree trunks included.
4. Then the owner reviews it. A passing measurement is not acceptance.
