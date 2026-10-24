# Terrain test fields — 23 October 2026

## Painted woodland trial — 24 October 2026

Woodland scouting and Northern forest ford now default to a five-source painted
kit: pine, beech, oak, shrubs and ferns. The **Painted woodland** toggle compares
it with the earlier foliage without changing map, patrol or sight state. The
surrounding forest switches too. The three tree silhouettes are only a first
increment; a distinct birch and painted fallen timber remain future work.

The original PNGs are copied unchanged into `assets/terrain/woodland/`, with
source hashes in `sources.json`. The material keys their magenta background and
removes edge spill; their files are not transparent cutouts. CPU opacity masks
match the key for the existing canopy fade system. Root anchors, sizes and
mipmapped filtering are explicit. Ferns are presentation-only and use the same
continuous height surface. Existing rocks, stumps and logs are retained.

The native fog harness now includes the painted comparison, night and overview
captures, opaque-interior / transparent-background mask checks, and a map/unit
state comparison across the art toggle. Its final review passed 23 checks with
no in-scene errors. Review images, the 9.1-second clip and the current quick-suite
result are in the existing Terrain tests and fog of war report. The historical
sections below describe the earlier terrain pass. Campaign playthroughs remain
deferred. No generation or gameplay rule changes were made for this increment.

Current scope: small playable terrain experiments before finished maps. The
title's **Terrain Test Fields** entry and `--terrain-lab` open the same isolated
screen. Continue revisions in the existing Meridius card's terrain test tab.

The three deterministic 24×24 fixtures are rolling meadow, northern forest ford
and opposing ridges. Each has 16 tiles of presentation border. The grid uses
128×64 pixel isometric tiles and 26 pixels per height level. Rule heights remain
integers; `surface_h` is a continuous visual sample. The CPU and ground shader
bilinearly interpolate the same float height image. Patrol anchors, individual
feet/shadows, props, grid edges and inverse mouse projection use that surface.
The test shapes have no screen-space folds; inverse picking uses bisection.

The lab alone opts in via `terrainLab` / `smoothTerrain`. Its Battle subclass
only suppresses empty-enemy victory; patrol moves use normal movement rules and
refresh after arrival. No campaign balance or save format changes. Its brighter
moonlight is a separate visual test setting, not a change to production battles.

User art direction: the four `road_forest_wide`, `road_forest_wide_night`,
`road_forest_northern_fog` and `road_forest_northern_clear` originals in the
[terrain library](../references/terrain-library.md) govern the mystical golden,
soft, magical atmosphere. Mix tree types, bushes, shrubs and undergrowth. Add
variety incrementally and show progress in native captures. First pass uses
existing pine, oak, bush, stump and log art, with filtered materials, sparse
grass strokes, cool shade, soft golden light and world-anchored mist.

Recommended next increment: one small forest-road scene using the approved
painted asset library. Current tests establish traversal and surface geometry;
they do not yet reproduce the reference paintings. The library already contains
isolated oak, beech, pine, autumn/ancient/dead trees, green/bramble bushes and
ferns. The inspected oak take 2 and fern take 1 have magenta backgrounds, so
they still need clean transparency, edge cleanup, consistent scale, root anchors
and depth/shadow integration. They are concept sources, not ready-made sprites.

For this fixed isometric camera, use painted cutouts for trees, shrubs, rocks,
logs and grass clusters. Scene-image extraction is possible when the whole
object is visible; overlapping objects and baked fog/shadows need repair.
Prefer the existing isolated sources. Keep the continuous height surface for
hills and map painted grass, dirt and road-edge masks onto it. Pasting a hill
image alone does not provide walkable height or correct unit grounding. Build
the golden atmosphere from canopy composition, warm highlights, cool shadows,
soft ground transitions and restrained mist, then compare at gameplay zoom.

No additional generation is needed to test this route. Request targeted
Higgsfield corrections only for a demonstrated missing asset or unusable
cutout. Tripo trees are optional for a future camera/3D requirement; converting
the paintings to meshes is not required for the current visual approach.
Any paid Tripo action still needs the user's per-action cost approval.

Layout influences: AoE II open land/forest pockets; Warcraft III and Frozen
Throne routes and crossings; Total War broad hills and deployment ground;
historical ridge/reverse-slope compositions. Sources and interpretation are in
the report. These are experiments, not historical reconstructions.

Review commands (from `source/godot`):

```
tools/test.sh --quick
tools/godot.sh --path . --resolution 1920x1080 --audio-driver Dummy -s res://tests/visual/terrain_lab_shots.gd
```

The native harness checks real menu/mouse input and save isolation as well as
rendering all fields and night variants. It records results in
`tests/visual/out/terrain_lab/result.json`. Report builder:
`projects/meridius/review/terrain-lab/build.mjs`.

Verification on 23 October 2026, working tree based on `8adca51` (uncommitted):
12 native GL checks passed with zero recorded errors. The final quick suite
recorded 375 passed, 1 failed and 10 skipped. All three terrain cases passed.
The single failure is the previously recorded headless unit-outline shader
compiler error in `test_audio::test_a_marching_squad_is_one_tread`.

The report's 15 images, local links and registry entry were checked. Browser
review covered 1600- and 1000-pixel desktop widths, dark/light appearance, image
enlargement and Close. Download links resolve to the local originals with a
download filename; the browser automation's download-completion event timed out,
so completed browser downloads are not claimed as verified.

Limits to retain in future handoffs: current vegetation is existing placeholder
art, smooth visual elevations do not replace tactical integer heights, and
terrain occlusion behind steep crests/overhangs is not implemented. Preserve the
production renderer default until the new terrain is accepted and further
combat/visibility work is explicitly scoped. Higgsfield generation remains on
hold after the previously recorded credit discrepancy; this pass makes no jobs.


## Fog and woodland pass - 23 October 2026

Open Terrain Test Fields > Woodland scouting. The first three art fields still
start with fog off; the Fog of war toggle works on all four fields. The scouting
field starts with fog on and a stationary concealed goblin sentry. Move the
patrol from (5,10) through (5,8) to (6,7), then return via (5,8), (5,9), (5,10).
This uses the actual battle movement and rendering paths, with patrol movement
refilled for inspection. It does not advance or save a campaign.

The user-supplied image-185259-b5c8583d.png is copied byte-for-byte to
assets/terrain/fog_grain.png. Four overlapping rotated texture samples break
up regular repetition. Unknown terrain is opaque; explored terrain is dim.
Sight changes blend over about 0.22 seconds; visible-squad canopy fades ease
toward 28% opacity. Sight is shared within each faction, defaults to seven
tiles, and uses existing height/foliage line of sight. Woodland occupants are
concealed beyond roughly two tiles. Combat reveals participants until their
next faction turn. Hidden squads are omitted from bodies, bars, minimap, hover,
targeting, danger overlays and local action logs. AI scouts unknown ground when
it has no visible foe. Scouting moves that reveal ground/enemies cannot be undone.

Trees and bushes are traversable; forest ground retains movement cost 2.
Solid obstacles still block movement. Map generation and initial deployment
continue to reserve clear corridors, so authored layouts remain unchanged.
New ordinary battle setups enable fog; old explicit setups without the flag
retain their prior no-fog behavior. Continuous terrain rendering remains a lab
option. These are initial visibility balance values, not final campaign tuning.

Validation: tests/visual/fog_of_war_shots.gd passed 17 native GL Compatibility
checks with no in-scene errors. The renderer was inspected at 0.57x and 1.45x,
including night, reveal, withdrawal, canopy fade, HUD and minimap. The native
process still reports 8 leaked objects / 2 resources during shutdown; cleanup
needs a later pass. Focused headless checks: 29 passed, one failure caused by the
existing unit-outline shader compiler issue in the first battle-HUD test.
The same fog view assertions passed in native rendering. Battle traces were
re-recorded (77 traces, 16 groups passed); campaign playthroughs and campaign
recording are deferred by the user's latest instruction.

Review: workspace/2026-10-20_meridius/terrain-lab.html; native records and
9.1-second normal-speed excerpts are under terrain-lab/. Original capture
frames remain under tests/visual/out/fog_of_war/. The fog shader and sight
rules live in battle_fog.gdshader, render/battle_fog.gd and rules/visibility.gd.
The later user authorization resumes Higgsfield Unlimited terrain production;
it supersedes the earlier credit-discrepancy hold. Check actual UI mode and
credit balance before and after each generation.


## Relief ground pass - 24 October 2026

Scope: the ground only (relief.gd, terrain_relief.gdshader, the ground part of
relief_terrain.gd). Trees and the lab screen stayed with the woodland work.
Targets: review/terrain/concept_a_repaint.png (raised ground with crumbling
banks), concept_c_hill_study.png (how a gentle slope reads).

The surface is now Catmull-Rom bicubic over a 4×4 tile window, on the CPU and
in the shader alike (it replaces the bilinear sample above). It passes through
every tile's height, has no creases at tile centres, and is exactly level where
all 16 samples agree, so feet on flat ground do not drift. A one-level step
becomes a bank about a tile wide.

The fifth field, **Bluff and hollow**, is a three-level plateau: steep toward
the camera, a long ramp behind it, a track along its foot and a smaller rise
to the east. tests/unit/test_relief.gd checks the surface, the bank shape,
camera-facing bank coverage, a connected patrol area that includes the top,
and picking on the banks.

Shader changes:
- Painted textures sampled with screen mips and a small bias (no forced far
  mip), two scales and turns mixed. Grass, dry grass and mud keep about 70% of
  their detail contrast around the local mean, so the light carries over them.
- Light as painted: slopes turned to the sun go golden, slopes turned away go
  cool teal; hill shadows marched toward the sun; occlusion under trees,
  bushes and rocks. The meadow's lit flank measures about 1.6× the flat ground
  and the shaded flank about 0.7× (0.57× zoom, mist off).
- Banks (slope above about 1 level per tile facing the camera): thick level
  beds of sandy soil and loam, about one and a half per level, with whole pale
  stone slabs now and then, painted in screen space so they are not stretched
  down the face. Each bed has a lit ledge and an antialiased crack with a soft
  undercut, broken by noise and shown on steep faces only (slope 1.2-2.0), so
  gentler faces do not show contour rings. Long blocks; under half the joints
  open, each cracking only part of the way down its bed. A grass lip at the
  crest, scree at the foot, wrapped light so camera-facing faces stay warm.
- Turf overhang: ragged tongues of turf over the top 8-17% of a face, with a
  dark undercut. The depth comes from -lap / slope, which does not depend on
  the bank's height.
- Fallen blocks along the foot: faceted like the rock props (a flat lit top,
  five or six flat sides, moss), in screen space. A block stands only where
  the ground under its centre is the concave foot of a camera-facing bank
  (lap above 0.6), so none is cut off. They are laid over the ground after its
  light, with their own light dimmed by hill shadow and canopy. Gentle hills get
  none (checked in fields 0 and 2).

Captures: `tools/godot.sh --path . --resolution 1920x1080 --audio-driver Dummy
-s res://tests/visual/terrain_relief_shots.gd` (optional `RELIEF_FIELDS=0,4`)
writes the whole fields and the bank, ramp, meadow and night close-ups to
tests/visual/out/terrain_relief/ with result.json (0 errors, build 55-85 ms).

Open: the lab's world mist lifts the shaded slopes by 10-15 levels, which
flattens gentle hills. Lower its strength or keep it out of the open field if
the slopes should read more. On the bluff's curved west end the strata still
show as faint arcs. The relief ground is still lab-only.

Concept A in motion: an 8 s Seedance 2.5 clip from concept A (Higgsfield MCP,
start image, 1080p, no sound, 128 credits) is in
review/terrain/concept_a_seedance.mp4. The prompt, job ID and cost are in
review/terrain/receipts/seedance_concept_a.json.
