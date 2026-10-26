# 3D unit sandbox

Every rigged 3D character of the game on one training ground in the battle's
look: the terrain lab's painted ground on hills, the painted woodland (cards
that fade when a unit walks behind them), grass blades, a pond, the fog of war
and a night light. The camera is the game's: orthographic, 30 degrees down, a
soldier 49 px tall at zoom 1. Use it to judge how each unit walks over the
map, idles, attacks, takes a blow and dies, beside the others, and how each
kind's squad marches, stands and fights.

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
stealth stance), succubus (whip lash with its slash effects, and the
Sovereign Kiss where its clip is on disk), the goblin
rabble in its three loadouts (knife, hatchet, cleaver: one chop each, with the
barrel-bottom or plank shield), the goblin archer (horn bow, arrows), the
goblin spearman (a two-handed spear thrust) and the orc brute (a spiked club,
or one in each fist). Players
are blue, enemies red. Every kind fights in its own squad (see **The
squads**); one of each stands alone on the bench, a row on the open ground
north of the yard, to try his clips and blows, with two straw dummies before
it. A drill line of six dummies stands in the yard for the footmen.

**Wolf Scout 2** stands on the bench beside the original Wolf Scout, with
her own roster button, model and squad. She uses the approved v04.5 sneak walk and the original
Scout's idle, twin-dagger attack and death motion transferred to the revised
rig. The attack still strikes at 0.8 and 0.8333 seconds; locomotion uses the
sneak's authored 1.83015 m/s speed. Select her, then use the clip buttons or
ordinary move/attack orders. The original Wolf Scout remains available.

The **Goblin Rabble** stands on the bench by the wolf scouts, one goblin per
loadout, each with his own roster button (their squad mixes the three). All three share the rig's idle, in-place walk
(0.86 m/s), chop (the blow at 0.8667 s, the hatchet's at 0.8333 s) and death,
retargeted from Mixamo and baked per loadout by
`references/characters/blender/goblin_rabble/tools/export_godot.py`. They
have no hit clip and flinch procedurally.

The **Goblin Archer** stands beside them, the hooded goblin with the horn bow.
He walks into range (10 m) and a clear line, draws an arrow over his shoulder,
nocks it and looses at 1.033 s: the sandbox's `arrow` missile leaves from the
arrow's middle at that frame (the sidecar's `shot_from`), so it takes the drawn
arrow's place and flies on a gentle arc. Struck, he raises the bow to block
(his `block` clip is the hit role); in his death he drops the bow. His run is
in the clip list. Exported by
`references/characters/blender/goblin_archer/tools/export_godot.py`.

The **Goblin Spearman** stands beside him, the bald goblin with the
red-ragged spear held level in both hands. His walk (in place, moved at
0.66 m/s) keeps the spear carried. He draws back and drives a two-handed thrust: the tip is
furthest forward, 2.29 m from where he stands, at 1.267 s (the blow), so he
strikes from 2 m. In his death the right fist opens at 1.5 s and the spear falls
flat beside him. He has no hit clip and flinches procedurally. Exported by
`references/characters/blender/goblin_spear/tools/export_godot.py`.

The **Orc Brute** stands beside the spearman, the brown-skinned orc, two
metres tall, with the spiked club in his right fist and his left hand empty.
His walk (in place, moved at 1.33 m/s) carries the club. His blow is a wild
rising swing on his right side: he winds the club far back, throws his left
arm up and sweeps the club up through chest height; the club's head is
furthest forward, 1.76 m from where he stands, at 1.033 s (the blow), so he
strikes from 1.6 m. In his death his fist lets the club go at 0.9 s and it
falls flat beside him. He has no hit clip and flinches procedurally.
**Orc Brute · two clubs** (`orc_brute_dual.glb`) stands beside him with a
club in each fist: the same clips and blow, the left club held up with his
left arm; dying, he lets the left club go at 0.733 s and the right at
0.833 s. Both are exported by
`references/characters/blender/orc_brute/tools/export_godot.py`.

The brutes' faces and kit tell the men of their squad apart. The sidecar's
`faces` names each face variant: `jaw` (an iron jaw guard on his head),
`beard` (a braided beard, its braids resting on his chest strap) and `scar`
(two claw gouges over his left eye, painted into a copy of his body's colour
that sits next to the GLB). A profile's `face` lists the faces a unit wears;
the meshes of the other faces go, and a face's `albedo` swaps the body's
colour. The sidecar's `kit` names gear a man can lose: `no_left_pauldron` and
`no_right_pauldron` hide that spiked shoulder plate, and a profile's `kit`
lists his (`unit3d.gd` `_dress`). The squad's `faces` in `Roster.SQUADS` deals
one to each man, shuffled: jaw, beard, scar, beard and scar, jaw and scar, and
one bare; its `kit`, shuffled on its own, takes the left pauldron off one man
and the right off another. Its `units` make two of the six men two-club
brutes. The brutes on the bench are bare, in full kit.

The **Succubus** has a second attack, the **Sovereign Kiss** (key 2): she
blows a kiss and a pink fog heart flies from her lips through the target,
the Blender study's (`art/succubus_3d/README.md`, "Sovereign Kiss (fog
heart)") in the game. Its clip is made from a Mixamo clip, so it is not in
Git: `art/succubus_3d/tools/export_kiss_godot.py` exports her rig with the
one clip to `local/succubus_3d/godot/succubus_kiss.fbx` and its sidecar
beside it, and `scripts/local_clips.gd` adds it to her model at run time
where it is on disk (the profile's `local_clips`). Without it she has her
whip only. The heart (`scripts/kiss_fx3d.gd`, `shaders/fog_heart.gdshader`
and the two shapes in `art3d/kiss_*_sdf.png`) starts at the clip's
`kiss_breath` (0.533 s): the breath gathers at her lips and the heart forms
there, leaves at `kiss_release` (0.7 s) 0.25 m wide, flies at 10 m/s at the
target's chest, following it, and is 1.2 m wide when its middle reaches it,
about 0.5 s later from 5 m (her reach is 6 m). A veil of fog washes over the
target, an enthrall mark fades in over its head and follows it for 4 s (a
placeholder for the status; it goes if the target dies), and the heart flies
on, eroding into wisps, gone 0.5 s after the contact. It keeps her playback,
so the time scale slows it with her, and a cast cut short before the release
lets it go. It does nothing to the target yet (the sandbox only says it
reached it), and only the target it was cast at is marked. The succubi's
squad keeps to the whip (its drill's `attacks`).

The footman's model (`footman.glb`), the wolf scout's export and the goblins'
GLBs, the archer's, the spearman's and the orc brute's too (their sidecars are in Git), are not in Git. Where they are missing, the
sandbox leaves those units out (and their squads) and says which in the left
panel and the console.

## The squads

Every kind fights in its own squad (`Roster.SQUADS`; each kind's drill in
`squad3d.gd` `DRILLS`), the players' west of the yard facing east and the
enemy's east of it facing west. Click a man, or the squad's button in the
left panel, to select his squad; **Battle: every squad attacks** sets each
squad on the foe squad nearest it.

| Squad | Men | Drill and fight |
| --- | --- | --- |
| Footmen | 6 | two ranks of three; the front rank fights, or **Spread to the line** (below) |
| Spearmen | 6 | two chequered ranks of three; both ranks thrust, the rear rank's spears past the front rank's shoulders |
| Crossbowmen | 6 | two chequered ranks of three; they halt in range with a clear line and loose in volleys, or at will |
| Battle Mages | 3 | a wedge; each casts his own spell when he is ready (a frost nova at a foe close by), or in volleys |
| Wolf Scouts, Wolf Scouts 2 | 3 each | a wedge; they close round the foe, each to a flank |
| Succubi | 3 | a wedge; they close round the foe with room for the whips |
| Goblin Rabble | 10 | two ragged ranks of five, knives, hatchets and cleavers mixed, each goblin his own size and pace; the rear rank joins the line |
| Goblin Archers | 8 | two chequered ranks of four; volleys on the arc, or at will |
| Goblin Spearmen | 8 | two chequered ranks of four; both ranks thrust |
| Orc Brutes | 6 | two loose ranks of three, each man with his own face, two with a club in each fist and two missing a pauldron; the rear rank shoulders in beside the front |

How every squad fights:

- **Each man goes for the foe nearest him**, each foe a mate already strikes
  counting 0.6 m farther, so that the men share the foes out; a man with no
  foe in reach goes to a free place by the foe nearest him (a spear in the
  rear rank keeps his place and strikes from there).
- **The man set upon answers.** A man picked or struck by a foe strikes back
  at him if he is in his reach (or a step beyond), rear rank or not; a man who
  has struck all his blows is given one more to answer with, at most three
  times a fight. His squad, if it stands at rest, takes up the fight with the
  foe's front when the foe is near (a shooting squad when he is in range) and
  turns to face a farther one. A strike back is not answered.
- **A swing cut short is not spent.** A hit reaction ends a man's swing; if
  his blow or shot had not left yet, he is given it back, so that a man struck
  often (a spearman among the rabble) still strikes back once the blows slack.
  So with a footman's step turn to strike, which the hit ends with the blow
  that was to follow; a unit that turns while idle swings after the hit.
- **Every fight ends.** A squad that took up a fight because it was set upon
  (it is `answering`) is not set on again, once it has re-formed, by its foe's
  last blows: its man struck strikes back once from his place when he has
  steadied, and the squad stays at rest. A blow from a squad at rest is a
  strike back, which nobody answers.
- **Blows** come each after the man's own pause, never two at once.
  **Shooting squads** halt in range with a clear line; in a volley every man
  waits for the others to have reloaded, then each starts his shot so that
  all leave together (within 0.22 s).
- With a squad selected, a ghost of its formation shows where it would stand
  at the cursor, and a foe under the cursor rings his whole squad red.
- The squad's panel: its orders, **Front rank only / Spread to the line** for
  a drill whose front rank fights, **In volleys / At will** for shooters, and
  a button per man (in his rank's row) to select him alone.

## The footman squad

The footmen's drill in detail. Six footmen in two ranks of three, each on the footman's own controller, who
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
button per man to select him alone (his own clips and actions).

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
- With a squad selected: **1 / Space** attack the nearest foe, **Q / E** wheel
  left or right. **Tab** goes through the squads, then the bench.

The left panel lists the squads, the **Battle** button and the bench's
roster and, for the selected squad its panel, for the selected unit its attacks,
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
  combat (blows, fight back, missiles), fog, panels, captures. It sets every
  figure on the relief and tilts a fallen one onto the ground's plane under it
  (sampled 0.9 m either way, over 0.8 s), so a body and the weapons it dropped
  lie on a slope rather than half above and half in it; a revived one stands
  back up.
- `scripts/field3d.gd`: the 28 x 28 map (hills, the yard, a road, the pond,
  woods) with a forest ring, its relief, ground bake, woodland cards, grass
  blades, routes (A* with string pulling) and ground picking.
- `scripts/squad3d.gd`: a squad: its drill (every kind's in `DRILLS`),
  formation, march, fight, volleys, answering and re-forming (the sandbox
  spawns every squad, the drill line and the squad's panel).
- `scripts/fog3d.gd`: seen and explored tiles from the battle's visibility rules
  (`scripts/rules/visibility.gd`), eased into the ground shader's fog texture.
- `scripts/roster.gd`: one profile per unit (see below) and the squads
  (`SQUADS`: units, size, home, blurb, drill).
- `scripts/unit3d.gd`: a rigged unit: clips from its sidecar, walking with the
  clip's ground speed, turning, attacks timed on the sidecar's events, hit
  (a short procedural flinch when the model has no hit clip), a random death
  among its death clips, revive, stances. `scripts/footman_unit.gd` puts the
  footman's own controller (`prototypes/footman_anim/scripts/footman3d.gd`)
  behind the same interface.
- `scripts/fx3d.gd`: sparks, the bolt, the arrow, fireball, chain lightning,
  frost nova and earth fist, and the succubus's kiss (`scripts/kiss_fx3d.gd`).
  A missile leaves from its unit's `missile_from()` where the sidecar gives
  the attack a `shot_from`.
- `scripts/local_clips.gd`: clips kept out of Git (the succubus's kiss),
  loaded from `local/` at run time onto a unit's model.
- `shaders/`: the ground (relief bake, fog, grid, route marks, hover), the
  painted cards and the kiss's fog (`fog_heart.gdshader`).
- `art3d/`: the spearman, crossbowman and battle mage exports with their
  sidecars, and the kiss heart's two shapes (`kiss_heart_sdf.png`,
  `kiss_puff_sdf.png`: distance from the edge, imported lossless). The
  footman and succubus are read from `prototypes/footman_anim/art3d`, the
  wolf scout from `prototypes/wolf_scout_anim/art3d`, the goblin rabble
  from `prototypes/goblin_rabble_anim/art3d`, the archer from
  `prototypes/goblin_archer_anim/art3d`, the goblin spearman from
  `prototypes/goblin_spear_anim/art3d` and the orc brute from
  `prototypes/orc_brute_anim/art3d` (outside the ignored `art/`, so
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
  roster model with its clips, and the squads: every squad's size and drill,
  the homes, bench and drill line on open ground and apart, each drill's
  places (two ranks of five, chequered ranks, the wedge), the footmen's ranks,
  places, foe's front and free places, and whole fights on stand-in men (only
  the front rank strikes, the blows are staggered, spread to the line all six
  strike, a rear man closes up, the ranks re-form; each man's first blow at
  the foe nearest him; both ranks of spears strike from their places; two
  volleys of six; a wedge closes round its foe; a squad set upon answers, each
  man struck strikes back and the fight ends; a swing cut short by a hit (or
  a footman's turn to strike) is given back, one that left is spent; a squad
  at rest strikes back
  from its places), and the kiss heart's course on a stand-in caster (it
  lands once, about 0.5 s after the release from 5 m, its cards go back to
  the pool, and a cast cut short lands nothing).
- Review captures in a real window (all shots, or those starting with a prefix):
  ```
  tools/godot.sh --path . --audio-driver Dummy res://prototypes/sandbox3d/scenes/sandbox3d.tscn -- --capture=res://tests/visual/out/sandbox3d [--shots=strike]
  ```
  The field, the yard at game zoom and close, every unit (and a close
  portrait), a march over the hill, the fog by day and night, the night, the
  pond, every unit's strike at its blow, a duel (footman and wolf scout, who
  strikes back), a lethal thrust, the mage's four spells and the succubus's
  kiss. `--shots=squad`
  takes the squad's: the start view, its ranks, the march to the drill line,
  the front rank's blows, the re-formed ranks, the line of six, a march north
  and a lone foe, and prints who struck when (`SQUAD` lines). `--shots=kiss`
  takes only the Sovereign Kiss's (where its clip is on disk), cast from 5 m
  at a quarter of the speed: close, the breath, the flight, the contact, the
  dissolve and the mark; at the game's zoom, the flight and the contact with
  the effect and without it; then at the spearman. `--shots=army`
  takes only the squads' shots: every squad at home (a squad with faces also
  close up, turned to the camera), the bench, then a battle
  and a battle with lethal blows (the advance, the clash, each squad close in
  the fight, a crossbow volley, the height of it, after), and prints `ARMY`
  lines: how many blows went to the foe nearest, the men struck who struck
  back, each shooting squad's volleys (shots and spread), who still stands
  and the frame rate in the clash. `--clean` hides the panels and selection
  rings.
- A tour of about a minute and a half for a video, ending with the squad's
  fight (game time, so the movie maker records it frame by frame), then quit:
  ```
  tools/godot.sh --path . --resolution 1600x900 --fixed-fps 30 --write-movie <file.avi> res://prototypes/sandbox3d/scenes/sandbox3d.tscn -- --tour
  ```
  The Workspace's Sandbox card shows the clean captures.
- Frame cost with its parts switched off in turn:
  `tools/godot.sh --path . --audio-driver Dummy -s res://prototypes/sandbox3d/qa/perf.gd`.
  On an RTX 4070 at 1600 x 900, with every squad and the bench (75 figures):
  about 52 fps at zoom 1.25 and 48 at zoom 0.62 (19 and 21 ms a frame; 78 fps
  without the figures, whose animation is most of the cost). The sandbox's
  own `_process` is under 1 ms: the crown fade looks only at the figures in
  the screen's columns under each crown, and a figure is set on the ground
  only where it moved. Selection rings sample the relief at eight points each
  and are kept while their unit stands still.

## Open points

- The spearman's `turn_90` clip turns only 67.5 degrees; the sandbox does not use
  it (units turn in place by steering their yaw).
- The crossbowman's walk speed (1.19 m/s) comes from local Mixamo sources.
- The wolf scout, the goblins and the orc brute have no hit clip; they flinch
  procedurally.
- The Sovereign Kiss is a view only: no status, no effect on the target, and
  only the target it was cast at is marked. Her Godot model has no face shape
  keys yet, so the kiss's pucker and exhale (`Kiss_Pucker`, `Exhale`) do not
  show.
- The goblins' walk is in place; its planted foot slides about 4% slower than
  the walk's root speed (`speed_footlock_mps` 0.8197 against 0.8555 m/s).
