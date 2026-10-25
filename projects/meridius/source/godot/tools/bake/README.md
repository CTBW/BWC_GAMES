# tools/bake — sprites and sounds from the original

The Godot port draws every sprite and plays every sound the original produced,
baked once from the original code (`../game/src`, never modified). The bake runs
that code in Microsoft Edge through `playwright-core`, served by the original's
own vite install (`../game/node_modules`) on port 5181.

## Run

From `projects/meridius/source/godot`:

```sh
node tools/bake/bake.mjs           # sprites + audio + browser contact sheets
tools/import.sh                    # import what changed (never import any other way)
tools/test.sh test_assets test_sfx
```

Single steps: `node tools/bake/bake.mjs sprites | audio | sheets | imports`.
A re-bake only rewrites files whose bytes changed (sound randomness is seeded),
so unchanged assets are not re-imported. Override the browser with
`CHROME_PATH=…` and the port with `BAKE_PORT=…`.

## What it writes

| Output | Contents |
| --- | --- |
| `assets/sprites/blender/*.webp` | The original's Blender sprites (`public/assets/sprites/blender`), copied as is |
| `assets/sprites/baked/*.png` | Procedural art packed into atlases: `fig_<type>.png` (12 poses × 6 looks per unit type; the troll needs two pages), `engine_<type>.png` (war engines: 12 poses × 3 looks; poses the original draws alike, such as `run_f` / `idle_fs` / `idle_f`, share one region), `portraits.png`, `misc.png` (ground decals, the fallen log, the unexplored node icon, `missing`) |
| (not baked) `assets/sprites/painted/*.webp` | The painted stones and boulders that replaced the Blender rocks (`tools/props/rock_cutout.py`, MIGRATION.md *Painted rocks*) and the painted trees and bush that replaced the Blender woodland (`tools/props/woodland_cutout.py`, MIGRATION.md *Painted woodland*), with the stumps, logs, deadwood, ferns, seasonal trees and small stones of the second terrain kit (MIGRATION.md *Terrain kit 2*). A sprite re-bake rebuilds `sprites.json` from the original: it writes the Blender or baked variants back for `rock_small`, `rock_large`, `tree_pine`, `tree_oak`, `bush`, `stump` and `log`, and drops the keys the original never had (`fern`, `deadwood`, `stones`, `tree_oak_autumn`, `tree_oak_spring`). After one, re-run both cutouts with `--manifest assets/sprites.json` (the rocks with `--texture assets/terrain/rock.webp` and `--stones` with the kit's stone sheet; see the scripts' headers) |
| `assets/sprites.json` | `key → [{file, region?: [x, y, w, h], ax, ay, scale, w, h, noShadow, art?}]`, one entry per variant, exactly what the original's `sprite(key, v)` returns |
| `assets/audio/<name>_<i>.wav`, `sfx.json` | Every `sfx(name)` recipe rendered with `OfflineAudioContext` (44.1 kHz mono 16-bit, master gain 0.55 included); four takes for recipes that use `Math.random`, one otherwise. The browser's rendering jitters a few samples by one LSB between runs; a take within ±1 of its existing file keeps that file |
| `tests/fixtures/assets/variant_counts.json` | The original's `variantCount()` per key, `hasArt()` keys, and the key groups |
| `tests/fixtures/assets/hit_masks.json` | The original's `opaqueAt()` on a grid for a few sprites |
| `tests/fixtures/assets/sfx_names.json` | Sound names, takes, master gain and gaps from `sfx.ts` |
| `tests/fixtures/assets/sheets.json`, `tests/visual/out/assets_*_browser.png` | Contact-sheet layouts and the original's rendering of them |
| `*.import` | Sprites: lossless, mipmaps, fix alpha border, no 3D detection. WAVs: PCM |

## How keys are found

`bake.mjs` enumerates every key the original can request at runtime from its
sources: the figure, war engine and portrait key regexes in `procedural.ts` (`um`:
18 figure types and `em`: 4 engines, each × the 12 poses of `figures.ts`'s `Pose`
type; `pm` + `pe`: 20 portrait types), `PROPS[*].sprite`
and the prop ids the garrison and campaign scenes name directly, `b_<id>_<1..levels>`
from `BUILDINGS`, `node_<type>` from `NODE_INFO` plus `node_unknown`, the terrain
decals, literal `sprite('…')` / `hasArt('…')` keys in `src/render` and `src/ui`, and
`missing`. The page (`page.ts`) then calls the original `loadAssets()`,
`variantCount()` and `sprite()` for each and returns Blender files by path and
procedural canvases as straight-alpha `getImageData` pixels, which `png.mjs`
writes without further conversion.

## Visual check

```sh
node tools/bake/bake.mjs sheets                                   # browser sheets
tools/godot.sh --path . -s res://tests/visual/capture_assets.gd   # Godot sheets (windowed)
node tools/bake/compare.mjs                                       # diffs + side-by-side pairs
```

`capture_assets.gd` draws the same layouts through `scripts/render/assets.gd`
(`draw_sprite`, `draw_cast_shadow`, `draw_flash`, `draw_silhouette`,
`draw_sprite_rect`); `compare.mjs` writes `assets_<sheet>_diff.png` (differing
pixels in red) and `assets_<sheet>_pair.png` (browser | Godot) to
`tests/visual/out/`. Pass `-- nomat` to the capture to see `draw_flash` without
the sprite material.
