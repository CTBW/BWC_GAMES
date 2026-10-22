# Meridius art production plan (phase one)

Status, 20 October 2026:

- **fal is blocked.** The account "Calle Bernsdorff" has credits but is
  admin-locked by fal; only fal support can lift it. No credits have been spent.
  The user's cap for phase-one art is about $30.
- **Environment art is rendered in Blender** (see below): trees, bushes, rocks,
  ruins, fences, camp props, all base buildings at three levels, the palisade,
  the gate tower and campaign landmarks.
- **Procedural figures added for the horde (21 October 2026)**: the goblin
  wolf rider is drawn as a warg (dog-legged hind legs, paws, hackles, a
  snarling jaw, a brush tail with a dark tip, harness and trophy skull), and
  the Margrave's riders (`margrave_rider`: warhorse, kettle helmet, couched
  lance with pennant, blue saddle cloth with a white star) charge in at the
  dawn relief. Both stay procedural until fal is unlocked.
- **Horde battle works (21 October 2026)**, built by `art/blender/meridius_horde.py`:
  battle palisade segments (`bwall_x`, `bwall_y`), open gateways (`gate_x`,
  `gate_y`), stake lines (`stakes_x`, `stakes_y`), an overturned cart, a
  haystack, a well, the horde's war standard (`war_banner`) and the Brannsted
  landmark for the campaign map (`node_objective`, replacing the war camp).
  Render with `R.render_asset(Hd.make(Hd.gate('x', 1), 'gate_x'), 'gate_x', 0)`,
  then `scripts/art/paint_all.py <prefix>`.
- **Footman pixel-art squads made with Higgsfield (21 October 2026)**: eight
  directions, six soldiers, in `art/sprites/footman_squad` (see
  `knowledge/higgsfield-setup.md`). Animations (idle breathing, walk, strike
  in four facings; death front and back) are in `art/sprites/footman_anim`
  with `sprites.json`, built by `scripts/art/footman_anim.sh`. None of it is
  registered in the manifest, so the game still draws the procedural
  footmen; walk and death would also need game code.
- **Units stay as the drawn (procedural) figures until fal is unlocked.** This
  is the user's decision. Blender unit renders exist in `art/raw/blender`
  (`meridius_chars.py`), but they are deliberately not registered in the
  manifest. Do not render or enable them without asking.

## Blender environment pipeline

1. In Blender 5.x (MCP add-on), `art/blender/meridius_rig.py` sets up the
   scene `MeridiusSprites`: an orthographic 2:1 camera matching the game
   (1 m = 1 tile, 90.51 world px per metre), a sun from the screen's upper left,
   a shadow catcher and Freestyle outlines. Cycles on the GPU (OptiX).
2. `meridius_rig.py` builds props and `meridius_build.py` builds structures.
   `render_asset()` writes `art/raw/blender/<key>_<v>.png` and registers the
   key in `public/assets/manifest.json` with baked shadows (`noShadow`).
3. `scripts/art/paint_all.py [prefix...]` applies the painterly pass. The
   result is the editable master `art/sprites/blender/<key>_<v>.png`, which is
   then published to `public/assets/sprites/blender/<key>_<v>.webp`.
4. Orientation matters for baked shadows: walls and fences have `_x` and `_y`
   variants. Never mirror a sprite with a baked shadow.

## Masters and published sprites

Edit and keep sprite masters as PNG under `art/sprites/`. The game only loads
the WebP copies in `public/assets/sprites/`, which `scripts/art/publish.py`
writes: colour at quality 92 and lossless alpha, so the outlines used for
clicking and the layout checks are pixel-exact while the download is about a
quarter of the PNG size (18.2 MB to 4.1 MB in October 2026). `paint_all.py`
and `slice.py` publish automatically; after editing a master by hand, run
`.venv-art/Scripts/python.exe scripts/art/publish.py [prefix...]`. Never put
PNG sprites in `public/`: Vite ships everything in that folder.

## fal pipeline (characters, when unlocked)

1. Upload the needed reference sheets from `projects/meridius/references`.
2. Generate each sheet with `fal-ai/nano-banana-pro/edit` ($0.15 per image, 2K,
   PNG). Seedream 5 Pro edit ($0.07) is the comparison model for the first sheet.
3. Remove the background with `fal-ai/birefnet/v2` (fractions of a cent).
4. `scripts/art/slice.py <spec.json>` splits the cut-out sheet into sprites,
   trims them, sets the foot anchor and scale, saves masters under
   `art/sprites/`, publishes them as WebP and registers them in
   `public/assets/manifest.json`. The game swaps procedural placeholders for
   these sprites by key, with no code change.
5. Review in the actual game camera (`scripts/playtest.mjs`) next to the
   reference sheets. Keep receipts in `art/receipts/` (not committed), raw
   outputs in `art/raw/`, cut-outs in `art/cut/`.

## Rules for every prompt

- Reference images are canonical. Assign each attached image a role.
- One camera for every grid asset: high-angle three-quarter view looking down
  at about 40 degrees, light from the upper left.
- Flat plain light-grey background, no ground, no shadows, no text, no frame,
  generous spacing so figures never touch.
- Never name other games or artists.
- External links in `projects/meridius/references/links.md` serve only the
  role given there. Never upload their images to a generator.
- Player units face down-left in front views and up-right in back views; the
  game mirrors them for the other two directions.

## Asset list and keys

| Sheet | References (role) | Sprite keys |
| --- | --- | --- |
| Footman poses | Footmen.png (design), Battlefield 1.png (camera, light) | footman_idle_f, footman_atk_f, footman_dead, footman_idle_b, footman_atk_b, footman_flee_b |
| Spearman poses | Pikemen.png, Battlefield 1.png | spearman_* |
| Crossbowman poses | Crossbowmen.png, Battlefield 1.png | crossbowman_* |
| Goblin spearman poses | Goblin spearmen.png, Battlefield 1.png | goblin_spear_* |
| Goblin archer poses | Goblin archers.png, Battlefield 1.png | goblin_archer_* |
| Orc warrior poses | Orc Warriors.png, Battlefield 1.png | orc_warrior_* |
| Orc warlord poses | Savage Orcs.png (design), Orc Warriors.png (faction look) | orc_warlord_* |
| Trees and plants | Battlefield 1.png, Battlefield.png | tree_pine x3, tree_oak x3, bush x3, stump, log |
| Rocks and ruins | Battlefield 1.png | rock_large x2, rock_small x2, wall_ruin x2, wall_high, fence x2 |
| War camp props | Goblin spearmen.png (banner style), Battlefield 1.png | tent x2, totem, campfire, crates |
| Base buildings (6 sheets, 3 levels each) | Footmen.png (heraldry), Battlefield 1.png | b_<id>_1..3 |
| Campaign landmarks | Campaign map.png (mood), Battlefield 1.png | node_battle, node_village, node_camp, node_scout, node_event, node_objective, node_start |
| Portraits (3 player, 4 enemy sheets of 6) | unit reference sheets | portrait_<type> x6 |
| Ground detail texture | Battlefield.png | texture ground_detail |

Estimated cost: about 30 generations plus retries, $5 to $8. Optional extras
if the slice needs them: second face variants per unit ($1), four-frame walk
cycles per unit ($1), a generated sound bank.

## Unit sheet prompt (template)

```
Create a sprite sheet for an isometric tactics game. Use image 1 as the exact
character design: {DESIGN}. Keep the same detailed painterly illustration
style, line weight, colours and proportions as image 1.

Layout: a 3 by 2 grid of six separate full-body poses of the same {UNIT},
evenly spaced with wide empty space between them, nothing overlapping and
nothing cropped.
Row 1: (1) idle ready stance, front three-quarter view facing down-left toward
the viewer; (2) {ATTACK} at the moment of impact, same front view facing
down-left; (3) fallen dead, lying on the ground, seen from the same high camera.
Row 2: (4) idle ready stance seen from behind, back three-quarter view facing
up-right away from the viewer; (5) {ATTACK} seen from behind facing up-right;
(6) running away in panic seen from behind facing up-right.

Camera: high-angle three-quarter view looking down at about 40 degrees, the
same isometric game camera as image 2, identical scale for all six poses,
sunlight from the upper left. Use image 2 only for camera angle and lighting;
do not draw its scenery.
Background: perfectly flat plain light grey, no ground, no grass, no cast
shadows, no text, no labels, no frame.
```
