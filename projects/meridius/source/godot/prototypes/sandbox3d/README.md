# 3D unit sandbox

Every rigged 3D character of the game on one training ground in the battle's
look: the terrain lab's painted ground on hills, the painted woodland (cards
that fade when a unit walks behind them), grass blades, a pond, the fog of war
and a night light. The camera is the game's: orthographic, 30 degrees down, a
soldier 49 px tall at zoom 1. Use it to judge how each unit walks over the
map, idles, attacks, takes a blow and dies, beside the others.

```
tools/godot.sh --path . res://prototypes/sandbox3d/scenes/sandbox3d.tscn
```

Or without a terminal: the **Open the sandbox** button on the Workspace's
Sandbox card, or `Meridius Sandbox.cmd` in the repository root. Both run
`tools/sandbox.ps1`, which opens the sandbox maximized without a console (or
brings an open one to the front).

The roster: footman (his own controller: start and stop, turns on the planted
foot, block, lane step, shield charge), spearman, crossbowman (bolt, then
reload), battle mage (four spells, quick and full), wolf scout (twin daggers,
stealth stance), succubus (whip lash with its slash effects), the goblin
rabble in its three loadouts (knife, hatchet, cleaver: one chop each, with the
barrel-bottom or plank shield) and the goblin archer (horn bow, arrows). Players
are blue, enemies red. Two straw
dummies stand in the yard, and a drill line of six in its south faces the
footman squad.

The **Goblin Rabble** stands by the wolf scouts, one goblin per loadout, each
with his own roster button. All three share the rig's idle, in-place walk
(0.86 m/s), chop (the blow at 0.8667 s, the hatchet's at 0.8333 s) and death,
retargeted from Mixamo and baked per loadout by
`references/characters/blender/goblin_rabble/tools/export_godot.py`. They
have no hit clip and flinch procedurally.

The **Goblin Archer** stands behind them, the hooded goblin with the horn bow.
He walks into range (10 m) and a clear line, draws an arrow over his shoulder,
nocks it and looses at 1.033 s: the sandbox's `arrow` missile leaves from the
arrow's middle at that frame (the sidecar's `shot_from`), so it takes the drawn
arrow's place and flies on a gentle arc. Struck, he raises the bow to block
(his `block` clip is the hit role); in his death he drops the bow. His run is
in the clip list. Exported by
`references/characters/blender/goblin_archer/tools/export_godot.py`.

The footman's model (`footman.glb`), the wolf scout's export and the goblins'
GLBs, the archer's too (their sidecars are in Git), are not in Git. Where they are missing, the
sandbox leaves those units out (and the squad with the footman) and says which
in the left panel and the console.

## The footman squad

Six footmen in two ranks of three, each on the footman's own controller, who
march, stand and fight together but never quite in step. Where the squad looks
lab (`prototypes/squad_looks`) is present, it dresses each man as a squad of
the blue livery and the line kit: his own helmet, face and build, and the
squad's mark on his shield; a squad spawned again is dressed anew. Without it
the men are the plain footman.

- **Marching.** Click a man to select the squad, then the ground. The squad
  follows its route in formation, each man at his own place in it (the ranks
  wheel at a corner), and the men take the places nearest them, so a squad
  sent back the way it came puts its rear rank in front. The file leader sets
  off first and the others a moment after, the rear rank last; each walks at
  his own pace (0.95x to 1.05x) and comes to rest a few centimetres off his
  exact place, turned a few degrees (up to 30 cm where his whole strides do
  not fit the way, or where he stood that near and did not move).
- **Standing.** Each man's idle starts at its own phase, and every so often
  each plays his guard idle at his own moment.
- **Fighting.** Click a foe or a dummy (or **1** / **Space**). The squad
  advances in formation to face the foe's front square (a line of foes, or a
  lone foe), its front rank at sword's reach. Only the front rank strikes
  while the rear rank stands ready: a few blows each, the slash or now and
  then the stab, each man after his own pause and never two at once (each
  blow starts at least 0.22 s after the last). A front man who falls is replaced by the
  nearest rear man. Then the ranks re-form where they fought.
- **Spread to the line** (panel toggle; **Front rank only** is the default):
  after the front rank's first blows the rear rank steps up beside it, each
  man to a free place in reach of a foe, so all six fight in one line (or
  close round a lone foe), then the squad re-forms its two ranks.

The squad's panel also has **Re-form**, **Wheel left / right** (**Q / E**),
**About face**, **Halt**, hit, death, revive and stop for all six, and a
button per man to select him alone (his own clips and actions). A struck man
whose squad stands idle sets the squad on his attacker.

## Controls

- **Left click** a unit to select it (**Shift** adds or removes one; **Ctrl**
  selects a foe instead of attacking it). With a selection, a click on the
  ground marches it there (round trees, rocks and water and over no bank too
  steep to climb) and a click on a foe or a dummy attacks: the unit walks into
  reach (a missile unit to a spot with a clear line) and strikes. **Right
  click** only gives orders, never selects.
- **Right / middle drag** or **WASD / arrows** pan, the **wheel** zooms
  (0.6x to 6x). **Tab** selects the next unit, **Esc** clears the selection.
- **1-8** strike with that attack at the last target or the nearest foe or
  dummy within six tiles (in place if none); **Space** strikes again with it.
  **H** hit, **K** die, **R** revive, **Q / E** turn a quarter, **F** follow,
  **G** grid, **V** fog, **N** night.
- Footman only: **B** (held) block, **C** shield charge, **X** counter,
  **L** lane step, **P** walk pace or game pace.
- With the squad selected: **1 / Space** attack, **Q / E** wheel left or right.

The left panel lists the roster and, for the selected unit, its attacks,
stances and every clip in its model (any clip can be played). The right panel
switches the fog (and forgets the explored ground), grid, night, follow,
outlines, shadows, the footman's 2D sprite beside him, **Lethal blows** (a
landed blow kills) and **Fight back** (a struck unit strikes back once it has
steadied, if the attacker is in its reach), the look (toon, flat, PBR), the
time scale (0.25x to 2x) and the camera.

## Look

The ground and the woodland use the terrain lab's bakes and the game's painted
sprites. This project's Compatibility renderer writes a 3D shader's `ALBEDO` to
the screen without converting it, so `terrain3d.gdshader` and
`painted_card.gdshader` hand the painted (sRGB) colours on as they are. Turning
them to linear first (`to_linear`) darkens and burns the paint: the bake's
grass (0.29, 0.40, 0.17) showed as (0.04, 0.13, 0.0). Keep it out.

## Files

- `scenes/sandbox3d.tscn`, `scripts/sandbox3d.gd`: camera, selection, orders,
  combat (blows, fight back, missiles), fog, panels, captures.
- `scripts/field3d.gd`: the 28 x 28 map (hills, the yard, a road, the pond,
  woods) with a forest ring, its relief, ground bake, woodland cards, grass
  blades, routes (A* with string pulling) and ground picking.
- `scripts/squad3d.gd`: the footman squad: its formation, march, fight and
  re-forming (the sandbox spawns it, its drill line and its panel).
- `scripts/fog3d.gd`: seen and explored tiles from the battle's visibility rules
  (`scripts/rules/visibility.gd`), eased into the ground shader's fog texture.
- `scripts/roster.gd`: one profile per unit (see below).
- `scripts/unit3d.gd`: a rigged unit: clips from its sidecar, walking with the
  clip's ground speed, turning, attacks timed on the sidecar's events, hit
  (a short procedural flinch when the model has no hit clip), a random death
  among its death clips, revive, stances. `scripts/footman_unit.gd` puts the
  footman's own controller (`prototypes/footman_anim/scripts/footman3d.gd`)
  behind the same interface.
- `scripts/fx3d.gd`: sparks, the bolt, the arrow, fireball, chain lightning,
  frost nova and earth fist. A missile leaves from its unit's
  `missile_from()` where the sidecar gives the attack a `shot_from`.
- `shaders/`: the ground (relief bake, fog, grid, route marks, hover) and the
  painted cards.
- `art3d/`: the spearman, crossbowman and battle mage exports with their
  sidecars. The footman and succubus are read from `prototypes/footman_anim/art3d`,
  the wolf scout from `prototypes/wolf_scout_anim/art3d`, the goblin rabble
  from `prototypes/goblin_rabble_anim/art3d` and the archer from
  `prototypes/goblin_archer_anim/art3d` (outside the ignored `art/`, so
  Godot imports them), the squad's dress from `prototypes/squad_looks/scripts`.

## Adding a unit

Export the rigged model (GLB or FBX) and its sidecar JSON (per clip: `length`,
`loop`, `speed_mps` or `root_vel`, `events` with the blow's time) into
`art3d/`, then add a profile to `Roster.UNITS`: `id`, `title`, `faction`,
`model`, `meta`, and what the sidecar does not say: `idle` / `walk` / `hit` /
`death` clip names if not those, `attacks` (`clip`, `label`, `reach` in metres
centre to centre, `hits`: the events that land, `missile` for a shot or spell,
`then`: a clip that follows, such as a reload) and `stances`. A shot's clip
can give `shot_from` (where the missile leaves, model axes from the feet). A sidecar with
`roles` (the spearman's, crossbowman's and goblins' exports) fills the clip
roles and attacks itself. A profile whose files are missing is left out.

## Checks

- `tools/test.sh test_sandbox3d`: the map, routes, fog, sidecar events, every
  roster model with its clips, and the squad (its ranks, places, foe's front,
  free places, and whole fights on stand-in men: only the front rank strikes,
  the blows are staggered, spread to the line all six strike, a rear man
  closes up, the ranks re-form).
- Review captures in a real window (all shots, or those starting with a prefix):
  ```
  tools/godot.sh --path . --audio-driver Dummy res://prototypes/sandbox3d/scenes/sandbox3d.tscn -- --capture=res://tests/visual/out/sandbox3d [--shots=strike]
  ```
  The field, the yard at game zoom and close, every unit (and a close
  portrait), a march over the hill, the fog by day and night, the night, the
  pond, every unit's strike at its blow, a duel (footman and wolf scout, who
  strikes back), a lethal thrust and the mage's four spells. `--shots=squad`
  takes the squad's: the start view, its ranks, the march to the drill line,
  the front rank's blows, the re-formed ranks, the line of six, a march north
  and a lone foe, and prints who struck when (`SQUAD` lines). `--clean` hides
  the panels and selection rings.
- A tour of about a minute and a half for a video, ending with the squad's
  fight (game time, so the movie maker records it frame by frame), then quit:
  ```
  tools/godot.sh --path . --resolution 1600x900 --fixed-fps 30 --write-movie <file.avi> res://prototypes/sandbox3d/scenes/sandbox3d.tscn -- --tour
  ```
  The Workspace's Sandbox card shows the clean captures.
- Frame cost with its parts switched off in turn:
  `tools/godot.sh --path . --audio-driver Dummy -s res://prototypes/sandbox3d/qa/perf.gd`.
  On an RTX 4070 at 1600 x 900, with the squad: about 63 fps at zoom 1.25 and
  53 at zoom 0.62 (measured with another Godot instance busy alongside; 77
  and 63 before the squad, alone); the sandbox's own `_process` takes about
  3 ms. Selection rings sample the relief at eight points each and are kept
  while their unit stands still: six re-sampled each frame cost under 1 ms.

## Open points

- The spearman's `turn_90` clip turns only 67.5 degrees; the sandbox does not use
  it (units turn in place by steering their yaw).
- The crossbowman's walk speed (1.19 m/s) comes from local Mixamo sources.
- The wolf scout and the goblin rabble have no hit clip; they flinch
  procedurally.
- The goblins' walk is in place; its planted foot slides about 4% slower than
  the walk's root speed (`speed_footlock_mps` 0.8197 against 0.8555 m/s).
