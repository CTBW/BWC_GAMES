# 3D battlefields

Four places of the Meridius frontier in four seasons, built from the battle's
own pieces and seen through the game's camera: the relief ground with the
battle's textures, the painted woodland, painted houses, mills, ruins and farm
things, grass strokes, water, weather and the fog of war. There are no units:
scouts (invisible eyes, posted with a click) lift the fog by the battle's sight
rules. Use it to judge new battlefield settings and their art before they go
into battles. Nothing here touches the game's state, saves or production
scenes.

```
tools/godot.sh --path . res://prototypes/battlefields3d/scenes/battlefields3d.tscn
tools/godot.sh --path . res://prototypes/battlefields3d/scenes/battlefields3d.tscn -- --field=frosthollow
```

| Key | Field | Season | What stands there |
| --- | --- | --- | --- |
| 1 | Millford | summer | A market town where the road crosses the river on a stone bridge: stalls and well on the square, chapel on its knoll, watermill, windmill on the hill |
| 2 | Ashby farm | autumn, falling leaves | A farm the war has passed through: the farmhouse roofless, the barn smouldering, a wagon wrecked in the lane, stooks in the stubble |
| 3 | Frosthollow | winter, frozen, snowfall | A hamlet by a frozen lake in deep snow: lit windows, snowy yards, the chapel on its rise, standing stones |
| 4 | Willowford | spring, blossom petals | The road fords the river between reed beds; blossom in the woods, the ruins of an older chapel and a broken colonnade |

## Controls

Left click posts a scout on a tile or recalls the one there (eight at most);
right click recalls the nearest. Right or middle drag and WASD pan, the wheel
zooms (0.5 to 4). 1–4 change the field, V fog of war, N night, T weather,
G grid, X forgets the explored ground, Home frames the whole field. The panel
on the left has the fields and the field's description; the one on the right
has the same switches, reset and clear for the scouts, the camera presets
(field, 1x, 2x, 3x) and the tile under the cursor (terrain, rules prop, height
and, with the fog on, whether it is seen).

## The camera and the field

The camera is the game's and the 3D sandbox's: orthographic, 30 degrees down,
tiles 128 × 64 px and a soldier 49 px tall at zoom 1 (the footman's height
comes from `prototypes/footman_anim/art3d/footman.json`, 1.7 m without it).

- `scripts/bf_fields.gd` lays out the four fields as pure data: a map in the
  rules' format (`{x, y, h, surface_h, terrain, prop}`, rules props from
  `data/terrain.json`), so `scripts/rules/visibility.gd` works out the fog over
  it unchanged, plus the pieces (each over a footprint that carries its rules
  prop: a house blocks sight as a high wall), the decor and the tiles' art.
- `scripts/bf_field.gd` builds the scene from it: the ground as one mesh over
  the relief surface (`scripts/render/relief.gd`), painted once by the battle's
  relief shader in the field's season (`terrain_relief.gdshader`, `season` and
  `frozen`) into two top-down pictures; the woods, pieces and decor as upright
  painted cards with their shadows draped over the ground
  (`shaders/bf_card.gdshader`); grass strokes; the water (`bf_water.gd`)
  unless it is frozen.
- `scripts/bf_fog.gd` is the battle's fog of war over a field, eased as the
  battle eases its shroud (copied from the sandbox's fog so this prototype
  stands alone). The ground, the water, the cards and the smoke shade with the
  battle's grain; each point of a card takes the fog of the ground seen behind
  it, so the edge of the shroud cuts a house or a tree as it cuts the ground.
- `scripts/bf_weather.gd`: snow, leaves or petals over the part of the field
  in view, chimney smoke and the burnt barn's embers.
- Seasons: summer paintings turn gold in autumn; in winter the woods are the
  winter paintings (snowy spruce and pines, bare oaks and birches) and props
  have their own snowy paintings (`*_w`); what has none takes snow along its
  top edges. At night the lived-in houses' windows stay lit.

## The art

`art/*.webp` are cut out of Nano Banana Pro paintings made for this prototype
(winter woods and houses, ruins, town houses, village, waterside and yard
props, reeds, ground textures), and terrain kit 2's houses, windmill and
ruins. The pieces were checked against the battle's camera as in
`processes/isometric-art-check.md`.
`art/art.json` lists them in the format of `assets/sprites.json` (which the
prototype reads for the game's own trees, rocks, stumps, logs, ferns and
stones); `art/art_sources.json` records each original's file and SHA-256.
`art/ground/` holds the autumn, snow, snowy road and ice textures.

The originals (PNGs on magenta) stay out of Git, in
`local/workspace-originals/2026-10-25_meridius/battlefields3d/originals/` and
`local/workspace-originals/2026-10-20_meridius/terrain-kit-2/originals/`. With
them, `tools/cut_art.py` cuts the art again (from the Godot project):

```
python -I prototypes/battlefields3d/tools/cut_art.py [--only NAME,...] [--review DIR]
tools/import.sh
```

It keys and shadows each piece as `tools/props/woodland_cutout.py` and
`rock_cutout.py` do the game's woodland and rocks, so everything shares the
battle's light. Paintings drawn off the battle's 2:1 grid are squared in it:
`SLOPE` shears a whole painting (the bridge, the chapels, the rowboat), and
`KEYSTONE` corrects one whose edges slope differently at the foot, the eaves
and the ridge (the town houses, the inn, the longhouses, the barns, the stone
cottage and the ruined farmhouse). The chapels' bell tower is painted nearly
frontal, which no shear mends.

## Captures and checks

```
tools/godot.sh --path . --resolution 1600x900 --audio-driver Dummy res://prototypes/battlefields3d/scenes/battlefields3d.tscn -- --capture=<dir> [--clean] [--fields=millford,ashby]
tools/test.sh test_battlefields3d
```

The captures are six shots a field (whole field, the game's zoom, a close
look, fog by day, fog at night, night), then quit; `--clean` hides the panels
and the scouts' marks. `test_battlefields3d` checks
that the fields are maps the rules can read in four seasons, that the fog sees
what `visibility.gd` sees, that every painting loads with its anchor inside it,
and that each field draws all its pieces and decor, winter trees in winter,
and no weeping willow.
