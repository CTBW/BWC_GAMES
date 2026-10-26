# Orc brute base scene and rig

`orc_brute_base.blend` holds the textured Tripo body, his club and his knife,
scaled and placed, ready for rigging. Each object's base colour is in `textures/`
(4096², linked by relative path). The scene is built in background Blender from
the Tripo exports in `../../tripo/orc_brute/` (`<model>__take-01.zip`); see
`../../orc_brute/prompts.md` and its `jobs.json` for where they came from.

```sh
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
S=projects/meridius/references/characters/blender/orc_brute
"$B" -b --factory-startup --python $S/tools/build_orc_brute.py -- \
  projects/meridius/references/characters/tripo/orc_brute $S/orc_brute_base.blend
"$B" -b $S/orc_brute_base.blend --python $S/tools/render_check.py -- <out dir>
```

Set `BLENDER_USER_RESOURCES` to an empty folder for these runs (see
`knowledge/tripo-studio.md`).

## What the build does

- **Scale:** the orc is 2.006 m tall, the footman's 1.82 m times the battle view's
  figure heights, 54 px for an orc against 49 for a man (`member_height` in
  `squad_view.gd`). His feet are on the ground, he is centred and faces -Y like the
  Mixamo clips.
- **Club:** 0.85 m, as long as his arm, read off the concept against his height.
  Tripo modelled its grip as the leather wrap alone, one open sheet round an empty
  middle, so between the turns of the wrap one could see through the handle. The
  build gives it a core: a closed tube from inside the knob to inside the shaft,
  following the wrap 1.5 mm under its outer surface, textured with the wrap's own
  dark leather. Its origin is on the grip's axis just above the knob, where the
  middle of the fist belongs.
- **Knife:** 0.60 m, a long fighting knife, its origin on the handle's axis halfway
  between the pommel and the guard. The edge is on its local -X, the thick
  serrated spine on +X.
- Both weapons have their long axis on Z toward the head or the blade and their
  front toward -Y, as in the Tripo front view, and stand beside the body in the
  `Props` collection.

## Rig

`tools/rig_orc_brute.py` builds a rig from the base scene for a loadout, the
weapons in his fists, following the goblins' rigs: the spearman's for the hands
and the grips, the archer's for a prop in each hand. `tools/render_rig.py`
renders review sheets and prints the grip and clearance measurements, including
any body triangles that cut through a weapon.

- `orc_brute_rig.blend` (`club_knife`, the default): the club in his right fist,
  the knife in his left. Since 26 October 2026 the brutes carry the club alone
  (the user had the knife taken away); the rig keeps the knife and its grip, and
  `retarget_clips.py` leaves them out of the clips (below).
- `orc_brute_dual_rig.blend` (`dual`): a club in each fist, for the two brutes
  of a squad who fight with two (the user, 26 October 2026). `ClubLeft` is a
  copy of the club, its grip solved for the left hand as the right's.

```sh
"$B" -b $S/orc_brute_base.blend --factory-startup --python $S/tools/rig_orc_brute.py -- \
  <absolute path>/orc_brute_rig.blend
"$B" -b $S/orc_brute_base.blend --factory-startup --python $S/tools/rig_orc_brute.py -- \
  <absolute path>/orc_brute_dual_rig.blend dual
"$B" -b $S/orc_brute_rig.blend --python $S/tools/render_rig.py -- <out dir>
```

- **Skeleton:** 81 bones with Mixamo names, so Mixamo clips play on it. 58 of them
  deform the mesh, with at most four per vertex: the Mixamo body, four fingers and a
  thumb on each hand, forearm twist bones and two bones down each loincloth flap,
  front and back. The weapons' bones, the controls and the helpers are
  non-deforming, each group in its own bone collection.
- **Skin:** bone heat on the body shell and, separately, on the boots (his feet and
  shins). Each hand is a shell of its own with geometric weights, so a finger moves
  only its own skin. The bracers are his forearms and go over to the twist bone
  toward the wrist. The fur kilt follows the hips and its own thigh; the loincloth
  flaps hang from their own bones below the belt. The belt follows the waist and
  the skull buckle and studs ride it whole; the chest straps take the chest's
  weights and the rings ride the straps. Each pauldron plate moves as one piece
  with its shoulder, so it never folds; the spikes ride their plates and bracers.
  Eyes, teeth, tusks and the earrings follow the head.
- **Grips:** solved on the skin as for the goblins. Each hand closes round its
  grip, laid across the palm at the tilt and place that close the four fingers
  best; the thumb closes the other way, toward the index finger. The right fist
  holds the club just above its knob, the left the knife between pommel and guard
  with the edge toward the knuckles (checked: the edge's direction against the
  knuckles' is +0.98). The fingers come to 0.2 to 0.4 mm of each grip's surface. Each
  grip is a one-frame Action applied by Action constraints on the finger bones.
  The dual rig's left fist holds its club as the right does, mirrored, its
  fingers 0.1 to 0.4 mm off the grip.
- **Inside or outside:** the grip solve and `render_rig.py` both need to know
  whether a point is inside a weapon. The nearest face's normal answers wrongly
  near the club's open wrap bands, so the grip's field (`PropField`) and the
  check sign each point by its winding number round the weapon's triangles.
- **Weapons:** the club rides the `Club` bone in the right hand, the knife the
  `Knife` bone in the left (the dual rig's left club the `ClubLeft` bone).
- **Standard pose:** the Action `stand`, active when the file opens. The arms hang
  with the weapons held low, as in the concept: the club's head forward, down
  30.5° and out 26.8° to his right, the knife's blade forward, down 35.9° and in
  22.1°. Each arm's angles and the hand's roll were searched for that aim with the
  weapon at least 2 cm off the body and the forearm and fist at least 1 cm off the
  rest: the club is 13.8 cm clear, the knife 5.7 cm, the right forearm 4.0 cm and
  the left 1.5 cm. No body triangle other than the fists passes through either
  weapon in the standard pose or the T-pose. On the dual rig the left club's head
  points forward, down 30.9° and out 26.9° to his left, 13.6 cm clear, and both
  forearms are 4.1 to 4.2 cm off the body.
- **Controls:** `club_ik` and `knife_ik` (`clubleft_ik` on the dual rig), and
  `leg_ik` (0 by default) switch on IK for the right arm, the left arm and the
  feet. `stand` keys the controls where the pose has put the hands, so switching
  the IK on keeps the pose (the forearms move 0.3 mm).
- **Known limits:** at the club, one finger vertex goes 0.8 mm into the grip, and
  the grip goes up to 3.4 mm into the palm. Nothing goes into the knife. At the
  dual rig's left club, two finger vertices go up to 0.5 mm into the grip, and the
  grip up to 2.3 mm into the palm.

## Clips

The orc's Idle, Walk and Death and the user's "Attack - Orc brute" are Mixamo
downloads in `projects/meridius/Animations/`, which stays local, so the
retargeted motion goes into a separate scratch copy of the rig rather than into
`orc_brute_rig.blend`. Each rig gets its own copy: the club alone from
`orc_brute_rig.blend` (the copy drops the knife, and the left hand keeps the
knife's grip at 0.7 of its close, an empty fist half shut), two clubs from
`orc_brute_dual_rig.blend`. The same four Mixamo clips play on both.

```sh
"$B" -b $S/orc_brute_rig.blend --python $S/tools/retarget_clips.py -- \
  projects/meridius/Animations <brute_clips.blend> <measure.json>
"$B" -b $S/orc_brute_dual_rig.blend --python $S/tools/retarget_clips.py -- \
  projects/meridius/Animations <brute_dual_clips.blend> <dual_measure.json>
CLIP_W=1100 CLIP_H=900 "$B" -b <brute_clips.blend> --python $S/tools/render_clips.py -- \
  <renders> idle=idle walk=walk attack=attack
CLIP_W=1200 CLIP_H=1050 "$B" -b <brute_clips.blend> --python $S/tools/render_clips.py -- \
  <renders> death=death
CLIP_W=1100 CLIP_H=900 "$B" -b <brute_dual_clips.blend> --python $S/tools/render_clips.py -- \
  <renders> dual_idle=idle dual_walk=walk dual_attack=attack
CLIP_W=1200 CLIP_H=1050 "$B" -b <brute_dual_clips.blend> --python $S/tools/render_clips.py -- \
  <renders> dual_death=death
python $S/tools/pack_sheets.py <renders> workspace/2026-10-20_meridius/orc-brute-3d \
  idle walk attack death dual_idle dual_walk dual_attack dual_death
```

| Clip | Source | Frames | Notes |
|---|---|---|---|
| `idle` | Orc - Idle | 161 (5.33 s) | in place; the last 10 frames ease into the first |
| `walk` | Orc - Walk | 37 (1.20 s) | in place, loops; 1.33 m/s |
| `attack` | Attack - Orc brute | 96 (3.17 s) | a rising swing on his right side |
| `death` | Orc - Death | 78 (2.57 s) | drops the club (with two clubs, the left, then the right) |

- **Retarget:** as the goblins', bone by bone in world space, with the hips'
  motion scaled by the hip-height ratio (0.959). The fingers keep the grip
  Actions. The walk's and the attack's
  hips rise or drop (up to 3.1 and 4.7 cm) so the lowest point of the soles
  stays on the ground; in the death they are lifted wherever the body would go
  below it (up to 22 cm).
- **Weapons and hands clear:** the clips were made for empty hands on a slimmer
  body. In each frame each arm gets the smallest correction that keeps its
  weapon off the body (its own hand left out), off the other weapon while both
  are held, and 1 cm above the ground, its hand out of the body (its own forearm
  left out) and the arm out of the ground. An empty hand is kept out of the body
  alone. Mixamo's hanging arms put the brute's hands into his thighs: before the
  hands were checked, the empty left went into the left thigh in 113 of the
  idle's 161 frames (15 of the walk's, 3 of the attack's) and into his belly
  in 5 of the death's, and the right fist into the right thigh in 24 idle and
  4 walk frames. Each correction is widened and averaged over the neighbouring
  frames. A frame still through gets the nearest clear grid point, kept in later
  rounds (they are pinned), and its neighbours ramp into it. With the club alone
  the idle took two rounds, the walk one, the attack and the death none; with
  two clubs the idle, the walk and the attack one each and the death six.
- **Attack:** the clip is a wild haymaker, not an overhead smash. He winds the club
  far back (frame 21), throws his left arm up (25 to 29; with two clubs, the
  left club with it) and sweeps the club up through chest height (32 to 33),
  following through overhead (36).
- **Death:** each hand lets go of its weapon at the latest frame before that weapon
  comes within 10 cm of the ground, from which it falls clear of him. His dying
  fists stop 2.5 to 4.4 cm short of the ground, so a weapon never came nearer
  than that. With the club alone the right lets it go at frame 28; it lies
  turned over, 8.3° off level. With two clubs the left lets its club go at
  frame 23; it lies 8.3° off level, turned 30° and pushed 0.25 m out of him. The
  right lets go at frame 26 and its club lies 7.5° off level, half under his
  hip without touching him. A dropped weapon tips about the line across it until
  both ends rest on the ground; an earlier version tipped it the wrong way, and
  `fall()` now asserts it lands within 20° of level. Each fall is checked
  against the other weapon, in his fist or on the ground.
- **Release planned twice:** the release is planned on the clip before the arms
  are corrected. Uncorrected, his dying left arm never brings its club within
  10 cm of the ground, so the plan had him hold it to the end, and the
  correction pushed the arm 9 to 12 cm into the floor to lift the club. Now a
  weapon still held after the correction gets its release planned again on the
  corrected clip, and the arms are corrected again from the start.
- **Checked:** in all 372 frames of each set, no body triangle cuts through a
  weapon (the hand holding it left out) or a hand (its own forearm left out),
  the two clubs never cross, and nothing goes more than 1 cm into the ground.
- **Frames:** Workbench, flat-lit with an outline and cavity, an orthographic
  camera 30° above the ground in the four facings, in an 1100 × 900 frame and
  1200 × 1050 for the death. The sheets are packed for the Workspace's pose
  viewer; the deaths get their own `canvas` in `frames.json`.

## Godot export

`tools/export_godot.py` bakes the clips scene into a GLB for the Godot sandbox,
with a JSON sidecar beside it. `tools/check_export.py` compares the GLB with the
rig it came from (0.01 mm at worst in every sampled frame, including the frames
round each weapon's release).

```sh
G=projects/meridius/source/godot/prototypes/orc_brute_anim/art3d
"$B" -b <brute_clips.blend> --python $S/tools/export_godot.py -- $G/orc_brute.glb
"$B" -b <brute_dual_clips.blend> --python $S/tools/export_godot.py -- $G/orc_brute_dual.glb
"$B" -b <brute_clips.blend> --python $S/tools/check_export.py -- source <samples.npz>
"$B" -b --factory-startup --python $S/tools/check_export.py -- glb $G/orc_brute.glb <samples.npz>
```

An optional second argument sets the textures' size (1024 px by default, JPEG).
Check the dual GLB the same way against its own clips scene.

- **Bake:** the 58 deforming bones plus each weapon's bone (59 in all with the
  club alone, 60 with `ClubLeft`), sampled at every frame and keyed as linear
  Actions `idle`, `walk`, `attack` and `death` (bake error under 0.002 mm). The
  constraints, drivers and the rig's own Actions go, and each weapon is skinned
  whole to its bone. 20,839 triangles (body 16,279, club 4,560) plus the faces'
  (below): jaw plate 4,108, beard 5,169, so 30,116 in `orc_brute.glb` and 34,676
  with the second club in `orc_brute_dual.glb`.
- **Pauldrons:** each spiked shoulder plate, its two plates and five spikes, comes
  out of the body into a mesh of its own, `PauldronLeft` and `PauldronRight`
  (335 and 336 vertices), with the body's skin weights, so a unit can go without
  one. The shoulder beneath was modelled and painted by Tripo; bare, it reads as
  his skin with the chest strap over it, and the faces stay clear of it (checked
  on renders of the windup and the death with the beard and the jaw plate).
- **Faces:** `JawPlate` and `Beard` are appended from `orc_brute_faces.blend` and
  put on this rig (their own rig, its widgets and Actions are dropped). The scar's
  body colour is scaled and encoded as the body's and written next to the GLB
  (`orc_brute_body_scar_basecolor.jpg`). The sidecar's `faces` says which meshes
  each face shows and which colour it swaps.
- **Sidecar:** fps, the rig's `loadout` and the GLB's `props`, height (1.93 m in
  the standard pose, 2.01 m in the T-pose), forward +Z, `faces`, `kit` (the
  variants that hide one pauldron, `no_left_pauldron` and `no_right_pauldron`),
  `roles` (no hit clip) and per clip its length and loop flag.
  - The walk has its `root_vel` (1.33 m/s forward) and its footfalls (left 0.333 s,
    right 0.9 s). A footfall starts a stance: the ankle low and the foot nearly
    still on the ground. Height alone gave four footfalls, because his heavy
    walk rolls the planted foot onto its outer edge (lifting the ankle up to
    4 cm) and swings the other foot within 2 cm of the ground.
  - The attack has its blow (`contact`, 1.033 s), found from the club's speed: the
    head furthest forward among the frames at 35% or more of its top speed,
    1.76 m from where he stands at 1.41 m up. `swing` (0.8 to 1.033 s) is the fast
    run up to the blow; the head's top speed is 25.6 m/s.
  - The death has its root motion (he turns 44°), `club_drop` (0.9 s; with two
    clubs `clubleft_drop` 0.733 s and `club_drop` 0.833 s) and when it settles
    (1.933 s).

## Squad faces

Three face variants tell the brutes of a squad apart: an iron jaw guard, a
braided beard and a clawed eye. Each was drawn on the brute's bust by Higgsfield
(`../../orc_brute/face_jaw.png`, `face_beard.png`, `face_scar.png`; prompts and
jobs in `../../orc_brute/prompts.md` and `jobs.json`). `orc_brute_faces.blend`
is the rig with the jaw plate and the beard on it, both in the rest pose; the
scar is a second body colour.

```sh
R=projects/meridius/references/characters/orc_brute
"$B" -b --factory-startup $S/orc_brute_rig.blend --python $S/tools/jaw_plate.py --   $S/orc_brute_faces.blend $S/tools/jaw_plate.json <grid.npz>
python $S/tools/jaw_texture.py $R/face_jaw.png <grid.npz> $S/textures/orc_brute_jaw_basecolor.png <rivets.json>
"$B" -b --factory-startup $S/orc_brute_rig.blend --python $S/tools/jaw_plate.py --   $S/orc_brute_faces.blend $S/tools/jaw_plate.json
"$B" -b --factory-startup $S/orc_brute_faces.blend --python $S/tools/fit_beard.py --   projects/meridius/references/characters/tripo/orc_brute/beard__take-01.zip $S/orc_brute_faces.blend
python $S/tools/scar_texture.py ratio $R/face_scar.png <ratio.npz> [debug prefix]
"$B" -b --factory-startup $S/orc_brute_rig.blend --python $S/tools/scar_uvmap.py -- <ratio.npz> <uvmap.npz> 4096
python $S/tools/scar_texture.py paint $S/textures/orc_brute_body_basecolor.jpg <ratio.npz> <uvmap.npz>   $S/textures/orc_brute_body_scar_basecolor.jpg [debug crop]
```

Run them in this order: the plate's texture needs its grid, so `jaw_plate.py`
runs twice (the first run says the texture is missing), and the beard goes onto
the plate's blend. `<…>` files are scratch. Then re-export (above).

- **Jaw plate** (`jaw_plate.py`, its outline, thickness, rims and rivets in
  `jaw_plate.json`): modelled, not generated. Higgsfield drew the guard as a
  closed ring twice, so the prop sheets were no use for Tripo. A chin cup with a
  band along each side of the jaw up to below the ear, its inside on the face's
  outer envelope (a rolling ball of 35 mm bridges the hollows under the chin and
  below the lip): 4,108 triangles, 16 rivet domes, 2.2 mm off the skin at the
  closest, nothing pushed. Skinned whole to the head.
- **Its texture** (`jaw_texture.py`): the bust's iron jaw unrolled onto the
  plate's grid, rims on rims. The painted rivets are filled with nearby iron, as
  the plate carries 3D domes; the domes sit at the bust's rivets (the `DOMES` it
  prints, their `t` clamped to 0.30–0.74 on the plate in `rivets_explicit`).
- **Beard** (`fit_beard.py`): the Tripo beard (Smart Mesh, 2,500 quads, 4K
  texture) without the loose 68-vertex arc Tripo left in front of the mouth.
  Scaled from the bust (0.36), pitched 0.5° about its top centre under the lower
  lip, and searched for depth and height against the body: nothing inside it,
  the inner rim along the jaw close to the skin. The hair below the chin then
  hangs back 5.5° so the braids lie 6 mm off the chest strap, and the beard is
  bent clear: no vertex inside the body, 1.2 mm at the closest, the rim 4 mm off
  the skin (median). 5,169 triangles, x ±0.136 m, z 1.495–1.865 m.
- **Its weights:** the head above the chin; below it, the weights of the skin
  nearest each vertex, blended over 1.69–1.73 m and smoothed along the hair. The
  braids then move with the chest they lie on. With weights by height (head,
  neck, chest) they swung with the neck: 1 cm into the chest on the walk and
  5 cm in the windup. Now the walk stays within 6 mm (at the lip) and the windup
  within 3 cm, the overlap behind his raised right pauldron. In the death his
  head rolls onto his left shoulder, and the beard goes up to 6 cm into the
  pauldron and the upper arm there, out of sight.
- **Scar** (`scar_uvmap.py`, `scar_texture.py`): two claw gouges from the
  forehead across his left eye to the cheek, with raw pink rims. `ratio` lifts
  them off the bust as a colour ratio to the skin around them; the bust maps to
  the head's front view by an affine fit on the eyes and nostrils (1 mm
  residual). `scar_uvmap.py` maps the body texture's texels there to bust pixels
  (42,705 texels; those the front view cannot reach, under the brow, are
  skipped), and `paint`
  multiplies 5,797 of them, so the texture keeps its own skin and light. At the
  export's 1024 px each gouge is about 3 texels wide.
- **In Godot** (`prototypes/sandbox3d`): a unit's `face` lists its faces; the
  other faces' meshes go and the scar swaps the body's colour. Its `kit` hides
  the meshes of the sidecar's kit variants the same way. The squad deals out jaw,
  beard, scar, beard and scar, jaw and scar, and one bare, and on its own,
  shuffled, one man without his left pauldron and one without his right. Two of
  its six men are `orc_brute_dual`, with a club in each fist.
- **Checked** on the exported GLB at every frame of every clip: the jaw plate
  goes at most 0.9 mm into the skin on the idle and walk. In the windup (attack
  frame 29) he tucks his chin into his right shoulder, and the plate and the
  beard cut into the right pauldron and go 1.1 and 1.5 cm into the skin under
  it. Lying dead (death frames 24 to 60) his head rolls onto his left shoulder:
  the plate goes 2.1 cm and the beard 6 cm into the shoulder and the upper arm,
  through the left pauldron. Renders of those frames with that pauldron off (the
  squad's kit) show the chin tucked against the bare shoulder and nothing
  through it. Neither face meets a club, in the GLB with one or with two.
